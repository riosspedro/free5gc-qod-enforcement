#!/usr/bin/env bash

set +e

ROOT=/home/ubuntu/free5gc-qod-enforcement
CONTROLLER="$ROOT/scripts/qod-controller.py"
STATE=/tmp/qod-controller-state.json
IMAGE='lscr.io/linuxserver/ffmpeg@sha256:4a4ed3a9242b51ab7821c611b4101a6a7dd72517f7f19e3a7b1833cae5020ecb'
RUN="${RUN:-/tmp/qod-video-controller-e2e-$(date -u +%Y%m%dT%H%M%SZ)}"
SOURCE="$RUN/source-330.ts"
EXPECTED_FILE="$RUN/expected-300.ts"
PORT="${PORT:-55024}"
RATE="${RATE:-5000000}"
RX="qod-controller-e2e-rx-$(date +%s)"
UEPID=$(docker inspect -f '{{.State.Pid}}' ueransim)

mkdir -p "$RUN"
rm -f "$STATE"

cleanup() {
  if docker ps -a \
    --format '{{.Names}}' |
    grep -qx "$RX"; then
    docker stop -t 2 "$RX" >/dev/null 2>&1 || true
  fi

  if [ -s "$STATE" ]; then
    PYTHONDONTWRITEBYTECODE=1 \
    python3 "$CONTROLLER" delete \
      >"$RUN/cleanup-delete.log" 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

main() {
  printf '\n===== BASELINE INICIAL =====\n'
  PYTHONDONTWRITEBYTECODE=1 \
  python3 "$CONTROLLER" baseline |
  tee "$RUN/baseline-before.json"

  BASELINE_RC=${PIPESTATUS[0]}

  if [ "$BASELINE_RC" != "0" ]; then
    echo "ERRO: baseline inicial não está limpo"
    return 1
  fi

  printf '\n===== GERAÇÃO DA FONTE =====\n'
  docker run --rm \
    -v "$RUN:/work" \
    --entrypoint /usr/local/bin/ffmpeg \
    "$IMAGE" \
    -hide_banner \
    -loglevel warning \
    -y \
    -f lavfi \
    -i 'testsrc2=size=1280x720:rate=30' \
    -frames:v 330 \
    -c:v libx264 \
    -preset veryfast \
    -tune zerolatency \
    -pix_fmt yuv420p \
    -b:v 4M \
    -maxrate 4M \
    -bufsize 8M \
    -g 60 \
    -an \
    -f mpegts \
    /work/source-330.ts \
    >"$RUN/source-generation.log" 2>&1

  SOURCE_RC=$?

  if [ "$SOURCE_RC" != "0" ] || [ ! -s "$SOURCE" ]; then
    echo "ERRO: geração da fonte falhou"
    return 1
  fi

  printf '\n===== GERAÇÃO DO BASELINE DE 300 FRAMES =====\n'
  docker run --rm \
    -v "$RUN:/work" \
    --entrypoint /usr/local/bin/ffmpeg \
    "$IMAGE" \
    -hide_banner \
    -loglevel warning \
    -y \
    -i /work/source-330.ts \
    -map 0:v:0 \
    -c copy \
    -frames:v 300 \
    -f mpegts \
    /work/expected-300.ts \
    >"$RUN/expected-generation.log" 2>&1

  EXPECTED_RC=$?

  if [ "$EXPECTED_RC" != "0" ] ||
     [ ! -s "$EXPECTED_FILE" ]; then
    echo "ERRO: geração do baseline falhou"
    return 1
  fi

  EXPECTED=$(
    sha256sum "$EXPECTED_FILE" |
    awk '{print $1}'
  )

  echo "Fonte=$SOURCE"
  echo "Baseline=$EXPECTED_FILE"
  echo "Hash esperado=$EXPECTED"

  printf '\n===== CRIAÇÃO DA SESSÃO QOD =====\n'
  PYTHONDONTWRITEBYTECODE=1 \
  python3 "$CONTROLLER" create \
    --device 10.61.0.1 \
    --server 10.100.200.1/32 \
    --profile QOS_M \
    --duration 180 |
  tee "$RUN/create.log"

  CREATE_RC=${PIPESTATUS[0]}

  if [ "$CREATE_RC" != "0" ]; then
    echo "ERRO: criação da sessão falhou"
    return 1
  fi

  printf '\n===== PROPAGAÇÃO NO UPF =====\n'
  for N in $(seq 1 10)
  do
    PDR_COUNT=$(
      docker exec upf sh -lc \
        'cd /free5gc && ./gtp5g-tunnel list pdr' |
      jq 'length'
    )

    QER_COUNT=$(
      docker exec upf sh -lc \
        'cd /free5gc && ./gtp5g-tunnel list qer' |
      jq 'length'
    )

    echo "tentativa=$N PDRs=$PDR_COUNT QERs=$QER_COUNT"

    if [ "$PDR_COUNT" = "4" ] &&
       [ "$QER_COUNT" = "2" ]; then
      break
    fi

    sleep 1
  done

  if [ "$PDR_COUNT" != "4" ] ||
     [ "$QER_COUNT" != "2" ]; then
    echo "ERRO: regras QoD não foram instaladas"
    return 1
  fi

  docker exec upf sh -lc \
    'cd /free5gc && ./gtp5g-tunnel list qer' |
  jq '[.[] | {
    ID,
    UL_MBR_Kbps: .MBR.UL_Kbps,
    UL_GBR_Kbps: .GBR.UL_Kbps,
    QFI,
    PDRIDs
  }]' |
  tee "$RUN/qer-active.json"

  printf '\n===== RECEPTOR =====\n'
  timeout --signal=INT --kill-after=5s 25s \
  docker run --rm \
    --name "$RX" \
    --network host \
    -v "$RUN:/work" \
    --entrypoint /usr/local/bin/ffmpeg \
    "$IMAGE" \
    -hide_banner \
    -loglevel warning \
    -y \
    -i "udp://10.100.200.1:${PORT}?fifo_size=1000000&overrun_nonfatal=1" \
    -map 0:v:0 \
    -c copy \
    -frames:v 300 \
    -f mpegts \
    /work/received-300.ts \
    >"$RUN/receiver.log" 2>&1 &

  RXPID=$!
  sleep 2

  printf '\n===== TRANSMISSOR UNIFORME =====\n'
  sudo -n nsenter -t "$UEPID" -n \
    python3 - "$SOURCE" "$PORT" "$RATE" \
    >"$RUN/sender.log" 2>&1 <<'PY'
import socket
import sys
import time
from pathlib import Path

source = Path(sys.argv[1])
port = int(sys.argv[2])
rate_bps = int(sys.argv[3])
destination = ("10.100.200.1", port)
chunk_size = 1316

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("10.61.0.1", 0))

packets = 0
sent_bytes = 0
started = time.monotonic()
deadline = started

with source.open("rb") as stream:
    while True:
        payload = stream.read(chunk_size)

        if not payload:
            break

        sock.sendto(payload, destination)
        packets += 1
        sent_bytes += len(payload)

        deadline += len(payload) * 8 / rate_bps
        remaining = deadline - time.monotonic()

        if remaining > 0:
            time.sleep(remaining)

duration = time.monotonic() - started

print(f"origem={sock.getsockname()}")
print(f"destino={destination}")
print(f"pacotes={packets}")
print(f"bytes={sent_bytes}")
print(f"duração={duration:.6f}")
print(
    f"taxa={sent_bytes * 8 / duration / 1_000_000:.6f} Mbps"
)

sock.close()
PY

  TXRC=$?
  wait "$RXPID"
  RXRC=$?

  echo "Código transmissor=$TXRC"
  echo "Código receptor=$RXRC"
  cat "$RUN/sender.log"

  if [ "$TXRC" != "0" ] ||
     [ "$RXRC" != "0" ] ||
     [ ! -s "$RUN/received-300.ts" ]; then
    echo "ERRO: transmissão ou recepção falhou"
    return 1
  fi

  printf '\n===== FFPROBE =====\n'
  docker run --rm \
    -v "$RUN:/work:ro" \
    --entrypoint /usr/local/bin/ffprobe \
    "$IMAGE" \
    -v error \
    -count_frames \
    -show_entries \
    stream=codec_name,width,height,avg_frame_rate,nb_read_frames \
    -show_entries format=duration,size,bit_rate \
    -of json \
    /work/received-300.ts \
    >"$RUN/received.ffprobe.json"

  jq . "$RUN/received.ffprobe.json"

  FRAMES=$(
    jq -r '.streams[0].nb_read_frames // 0' \
      "$RUN/received.ffprobe.json"
  )

  printf '\n===== DECODIFICAÇÃO =====\n'
  docker run --rm \
    -v "$RUN:/work:ro" \
    --entrypoint /usr/local/bin/ffmpeg \
    "$IMAGE" \
    -hide_banner \
    -v warning \
    -i /work/received-300.ts \
    -map 0:v:0 \
    -f null - \
    >"$RUN/decode.log" 2>&1

  DECRC=$?
  ERRORS=$(
    grep -Eic \
      'error|corrupt|concealing|invalid|missing' \
      "$RUN/decode.log" || true
  )

  RXHASH=$(
    sha256sum "$RUN/received-300.ts" |
    awk '{print $1}'
  )

  echo "Frames=$FRAMES"
  echo "Código de decodificação=$DECRC"
  echo "Ocorrências de erro=$ERRORS"
  echo "Hash esperado=$EXPECTED"
  echo "Hash recebido=$RXHASH"

  if [ "$FRAMES" != "300" ] ||
     [ "$DECRC" != "0" ] ||
     [ "$ERRORS" != "0" ] ||
     [ "$RXHASH" != "$EXPECTED" ]; then
    echo "ERRO: validação do vídeo falhou"
    return 1
  fi

  echo "Vídeo QoD: VALIDADO"

  printf '\n===== REMOÇÃO DA SESSÃO =====\n'
  PYTHONDONTWRITEBYTECODE=1 \
  python3 "$CONTROLLER" delete |
  tee "$RUN/delete.log"

  DELETE_RC=${PIPESTATUS[0]}

  if [ "$DELETE_RC" != "0" ]; then
    echo "ERRO: remoção da sessão falhou"
    return 1
  fi

  printf '\n===== BASELINE FINAL =====\n'
  PYTHONDONTWRITEBYTECODE=1 \
  python3 "$CONTROLLER" baseline |
  tee "$RUN/baseline-after.json"

  FINAL_RC=${PIPESTATUS[0]}

  if [ "$FINAL_RC" != "0" ]; then
    echo "ERRO: baseline final não foi restaurado"
    return 1
  fi

  trap - EXIT INT TERM

  echo
  echo "EXPERIMENTO_E2E=SUCESSO"
  echo "Evidências preservadas em: $RUN"
  return 0
}

main
