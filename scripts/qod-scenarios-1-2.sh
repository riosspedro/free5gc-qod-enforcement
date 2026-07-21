#!/usr/bin/env bash

set +e

ROOT=/home/ubuntu/free5gc-qod-enforcement
CONTROLLER="$ROOT/scripts/qod-controller.py"
STATE=/tmp/qod-controller-state.json
IMAGE='lscr.io/linuxserver/ffmpeg@sha256:4a4ed3a9242b51ab7821c611b4101a6a7dd72517f7f19e3a7b1833cae5020ecb'
SCENARIO="${SCENARIO:-best-effort}"
THRESHOLD_BPS="${THRESHOLD_BPS:-4000000}"
QOS_PROFILE="${QOS_PROFILE:-QOS_M}"
QOS_DURATION="${QOS_DURATION:-180}"
RUN="${RUN:-/tmp/qod-${SCENARIO}-$(date -u +%Y%m%dT%H%M%SZ)}"
SOURCE="$RUN/source-330.ts"
EXPECTED_FILE="$RUN/expected-300.ts"
PORT="${PORT:-55024}"
RATE="${RATE:-5000000}"
QOD_ACTIVE=0
REQUEST_QOD=0
DECISION_REASON=not_evaluated
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
  case "$SCENARIO" in
    best-effort|fixed-rules)
      ;;
    *)
      echo "ERRO: SCENARIO deve ser best-effort ou fixed-rules"
      return 1
      ;;
  esac

  case "$THRESHOLD_BPS" in
    ''|*[!0-9]*)
      echo "ERRO: THRESHOLD_BPS deve ser inteiro"
      return 1
      ;;
  esac

  echo "SCENARIO=$SCENARIO"
  echo "THRESHOLD_BPS=$THRESHOLD_BPS"

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

  printf '\n===== MÉTRICA E REGRA DE DECISÃO =====\n'
  docker run --rm \
    -v "$RUN:/work:ro" \
    --entrypoint /usr/local/bin/ffprobe \
    "$IMAGE" \
    -v error \
    -show_entries format=bit_rate \
    -of json \
    /work/expected-300.ts \
    >"$RUN/application-metrics.json"

  APP_BITRATE_BPS=$(
    jq -r '.format.bit_rate // 0' \
      "$RUN/application-metrics.json"
  )

  case "$APP_BITRATE_BPS" in
    ''|*[!0-9]*)
      echo "ERRO: bitrate da aplicação inválido"
      return 1
      ;;
  esac

  if [ "$APP_BITRATE_BPS" -le "0" ]; then
    echo "ERRO: bitrate da aplicação não foi medido"
    return 1
  fi

  if [ "$SCENARIO" = "best-effort" ]; then
    REQUEST_QOD=0
    DECISION_REASON=scenario_forbids_qod
  elif [ "$APP_BITRATE_BPS" -gt "$THRESHOLD_BPS" ]; then
    REQUEST_QOD=1
    DECISION_REASON=bitrate_above_threshold
  else
    REQUEST_QOD=0
    DECISION_REASON=bitrate_not_above_threshold
  fi

  jq -n \
    --arg scenario "$SCENARIO" \
    --arg metric application_bitrate_bps \
    --argjson observed "$APP_BITRATE_BPS" \
    --argjson threshold "$THRESHOLD_BPS" \
    --arg request "$REQUEST_QOD" \
    --arg reason "$DECISION_REASON" \
    --arg profile "$QOS_PROFILE" \
    '{
      scenario: $scenario,
      metric: $metric,
      observed_bps: $observed,
      threshold_bps: $threshold,
      request_qod: ($request == "1"),
      reason: $reason,
      qos_profile: $profile
    }' >"$RUN/decision.json"

  jq . "$RUN/decision.json"

  EXPECTED_PDR=2
  EXPECTED_QER=1

  if [ "$REQUEST_QOD" = "1" ]; then
    printf '\n===== CRIAÇÃO DA SESSÃO QOD =====\n'
    PYTHONDONTWRITEBYTECODE=1 \
    python3 "$CONTROLLER" create \
      --device 10.61.0.1 \
      --server 10.100.200.1/32 \
      --profile "$QOS_PROFILE" \
      --duration "$QOS_DURATION" |
    tee "$RUN/create.log"

    CREATE_RC=${PIPESTATUS[0]}

    if [ "$CREATE_RC" != "0" ]; then
      echo "ERRO: criação da sessão falhou"
      return 1
    fi

    QOD_ACTIVE=1
    EXPECTED_PDR=4
    EXPECTED_QER=2
  else
    printf 'HTTP=SKIPPED\nreason=%s\n' \
      "$DECISION_REASON" \
      >"$RUN/create.log"
  fi

  printf '\n===== ESTADO ESPERADO DO UPF =====\n'
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

    if [ "$PDR_COUNT" = "$EXPECTED_PDR" ] &&
       [ "$QER_COUNT" = "$EXPECTED_QER" ]; then
      break
    fi

    sleep 1
  done

  if [ "$PDR_COUNT" != "$EXPECTED_PDR" ] ||
     [ "$QER_COUNT" != "$EXPECTED_QER" ]; then
    echo "ERRO: estado esperado do UPF não foi alcançado"
    return 1
  fi

  docker exec upf sh -lc \
    'cd /free5gc && ./gtp5g-tunnel list qer' |
  jq . >"$RUN/qer-during.json"

  docker exec upf sh -lc \
    'cd /free5gc && ./gtp5g-tunnel list pdr' |
  jq . >"$RUN/pdr-during.json"

  jq . "$RUN/qer-during.json"

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

  echo "Vídeo: VALIDADO"

  printf '\n===== LIBERAÇÃO DA QOS =====\n'
  if [ "$QOD_ACTIVE" = "1" ]; then
    PYTHONDONTWRITEBYTECODE=1 \
    python3 "$CONTROLLER" delete |
    tee "$RUN/delete.log"

    DELETE_RC=${PIPESTATUS[0]}

    if [ "$DELETE_RC" != "0" ]; then
      echo "ERRO: remoção da sessão falhou"
      return 1
    fi

    QOD_ACTIVE=0
  else
    printf 'HTTP=SKIPPED\nreason=%s\n' \
      "$DECISION_REASON" |
    tee "$RUN/delete.log"
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
  echo "SCENARIO=$SCENARIO"
  echo "APPLICATION_BITRATE_BPS=$APP_BITRATE_BPS"
  echo "THRESHOLD_BPS=$THRESHOLD_BPS"
  echo "QOD_REQUESTED=$REQUEST_QOD"
  echo "DECISION_REASON=$DECISION_REASON"
  echo "EXPERIMENTO_E2E=SUCESSO"
  echo "Evidências preservadas em: $RUN"
  return 0
}

main
