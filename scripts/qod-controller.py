#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

GATEWAY_URL = "http://127.0.0.1:8080"
GATEWAY_ENV = Path("/home/ubuntu/open-qod-gateway/.env")
STATE_FILE = Path("/tmp/qod-controller-state.json")
UPF_CONTAINER = "upf"


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()

        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip("'\"")

    return values


def request(
    method: str,
    path: str,
    *,
    token: str | None = None,
    payload: dict[str, Any] | None = None,
    form: dict[str, str] | None = None,
) -> tuple[int, Any]:
    headers: dict[str, str] = {}
    data: bytes | None = None

    if token:
        headers["Authorization"] = f"Bearer {token}"

    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")

    if form is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        data = urllib.parse.urlencode(form).encode("utf-8")

    req = urllib.request.Request(
        f"{GATEWAY_URL}{path}",
        data=data,
        headers=headers,
        method=method,
    )

    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            body = response.read()
            status = response.status
    except urllib.error.HTTPError as exc:
        body = exc.read()
        status = exc.code
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Falha de comunicação: {exc}") from exc

    if not body:
        return status, None

    try:
        return status, json.loads(body)
    except json.JSONDecodeError:
        return status, body.decode("utf-8", errors="replace")


def get_token() -> str:
    env = load_env(GATEWAY_ENV)

    client_id = env.get("GATEWAY_OAUTH_CLIENT_ID", "")
    client_secret = env.get("GATEWAY_OAUTH_CLIENT_SECRET", "")

    if not client_id or not client_secret:
        raise RuntimeError("Credenciais do Gateway não encontradas.")

    status, body = request(
        "POST",
        "/oauth2/token",
        form={
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
            "scope": "qod:read qod:write",
        },
    )

    if status != 200 or not isinstance(body, dict):
        raise RuntimeError(
            f"Falha ao obter token: HTTP {status} {body}"
        )

    token = body.get("access_token")

    if not isinstance(token, str) or not token:
        raise RuntimeError("Token ausente na resposta do Gateway.")

    return token


def docker_output(command: str) -> str:
    result = subprocess.run(
        [
            "docker",
            "exec",
            UPF_CONTAINER,
            "sh",
            "-lc",
            command,
        ],
        check=False,
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        raise RuntimeError(
            result.stderr.strip()
            or f"docker exec retornou {result.returncode}"
        )

    return result.stdout.strip()


def read_rules(rule_type: str) -> list[dict[str, Any]]:
    output = docker_output(
        f"cd /free5gc && ./gtp5g-tunnel list {rule_type}"
    )

    parsed = json.loads(output)

    if not isinstance(parsed, list):
        raise RuntimeError(
            f"Resposta inesperada ao listar {rule_type}."
        )

    return parsed


def read_state() -> dict[str, Any]:
    if not STATE_FILE.exists():
        raise RuntimeError(
            f"Estado não encontrado em {STATE_FILE}."
        )

    parsed = json.loads(
        STATE_FILE.read_text(encoding="utf-8")
    )

    if not isinstance(parsed, dict):
        raise RuntimeError("Arquivo de estado inválido.")

    return parsed


def resolve_session_id(argument: str | None) -> str:
    if argument:
        return argument

    session_id = read_state().get("sessionId")

    if not isinstance(session_id, str) or not session_id:
        raise RuntimeError("sessionId ausente no estado.")

    return session_id


def command_baseline(_: argparse.Namespace) -> int:
    health_status, health = request("GET", "/health")
    pdrs = read_rules("pdr")
    qers = read_rules("qer")
    qos = docker_output("cat /proc/gtp5g/qos")

    result = {
        "gatewayHttp": health_status,
        "gateway": health,
        "pdrCount": len(pdrs),
        "qerCount": len(qers),
        "qosEnabled": "QoS Enable: 1" in qos,
        "baselineClean": (
            health_status == 200
            and len(pdrs) == 2
            and len(qers) == 1
            and "QoS Enable: 1" in qos
        ),
    }

    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0 if result["baselineClean"] else 1


def command_create(args: argparse.Namespace) -> int:
    token = get_token()

    status, body = request(
        "POST",
        "/sessions",
        token=token,
        payload={
            "device": {
                "ipv4Address": args.device,
            },
            "applicationServer": {
                "ipv4Address": args.server,
            },
            "qosProfile": args.profile,
            "duration": args.duration,
        },
    )

    print(f"HTTP={status}")
    print(json.dumps(body, indent=2, ensure_ascii=False))

    if status != 201 or not isinstance(body, dict):
        return 1

    STATE_FILE.write_text(
        json.dumps(body, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(f"Estado salvo em: {STATE_FILE}")
    return 0


def command_get(args: argparse.Namespace) -> int:
    session_id = resolve_session_id(args.session_id)
    token = get_token()

    status, body = request(
        "GET",
        f"/sessions/{session_id}",
        token=token,
    )

    print(f"HTTP={status}")
    print(json.dumps(body, indent=2, ensure_ascii=False))
    return 0 if status == 200 else 1


def command_delete(args: argparse.Namespace) -> int:
    session_id = resolve_session_id(args.session_id)
    token = get_token()

    status, body = request(
        "DELETE",
        f"/sessions/{session_id}",
        token=token,
    )

    print(f"HTTP={status}")

    if body is not None:
        print(json.dumps(body, indent=2, ensure_ascii=False))

    if status == 204 and STATE_FILE.exists():
        state = read_state()

        if state.get("sessionId") == session_id:
            STATE_FILE.unlink()
            print(f"Estado removido: {STATE_FILE}")

    return 0 if status == 204 else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Protótipo de controlador para o experimento "
            "free5GC Quality-on-Demand."
        )
    )

    commands = parser.add_subparsers(
        dest="command",
        required=True,
    )

    baseline = commands.add_parser(
        "baseline",
        help="Verifica Gateway, PDRs, QERs e gtp5g QoS.",
    )
    baseline.set_defaults(function=command_baseline)

    create = commands.add_parser(
        "create",
        help="Cria uma sessão QoD e salva seu estado.",
    )
    create.add_argument(
        "--device",
        default="10.61.0.1",
    )
    create.add_argument(
        "--server",
        default="10.100.200.1/32",
    )
    create.add_argument(
        "--profile",
        default="QOS_M",
    )
    create.add_argument(
        "--duration",
        type=int,
        default=300,
    )
    create.set_defaults(function=command_create)

    get = commands.add_parser(
        "get",
        help="Consulta a sessão informada ou salva.",
    )
    get.add_argument("--session-id")
    get.set_defaults(function=command_get)

    delete = commands.add_parser(
        "delete",
        help="Exclui a sessão informada ou salva.",
    )
    delete.add_argument("--session-id")
    delete.set_defaults(function=command_delete)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        return int(args.function(args))
    except Exception as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
