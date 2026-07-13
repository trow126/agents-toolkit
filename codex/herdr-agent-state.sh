#!/bin/sh
# installed by herdr
# managed by herdr; reinstalling or updating the integration overwrites this file.
# add custom hooks beside this file instead of editing it.
# HERDR_INTEGRATION_ID=codex
# HERDR_INTEGRATION_VERSION=5

set -eu

action="${1:-}"
if ! hook_input_file="$(mktemp "${TMPDIR:-/tmp}/herdr-codex-hook.XXXXXX")"; then
    echo "[herdr-hook] failed to create temporary hook input file" >&2
    exit 0
fi
trap 'rm -f "$hook_input_file"' EXIT HUP INT TERM
if ! cat >"$hook_input_file"; then
    echo "[herdr-hook] failed to read hook input" >&2
    exit 0
fi

case "$action" in
  session) ;;
  *) exit 0 ;;
esac

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_SOCKET_PATH:-}" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0
if ! command -v python3 >/dev/null 2>&1; then
    echo "[herdr-hook] system Python is required but was not found" >&2
    exit 0
fi

# System Python is intentional: this zero-dependency hook runs outside a uv project.
HERDR_ACTION="$action" HERDR_HOOK_INPUT_FILE="$hook_input_file" python3 - <<'PY'
import json
import os
import random
import socket
import sys
import time

source = "herdr:codex"
action = os.environ.get("HERDR_ACTION", "")
pane_id = os.environ.get("HERDR_PANE_ID")
socket_path = os.environ.get("HERDR_SOCKET_PATH")
hook_input_file = os.environ.get("HERDR_HOOK_INPUT_FILE")


def log_error(message: str) -> None:
    print(f"[herdr-hook] {message}", file=sys.stderr)


if not pane_id or not socket_path:
    raise SystemExit(0)

hook_input = {}
if hook_input_file:
    try:
        with open(hook_input_file, encoding="utf-8") as handle:
            content = handle.read()
        if content.strip():
            hook_input = json.loads(content)
    except OSError as exc:
        log_error(f"failed to read hook input: {type(exc).__name__}")
    except UnicodeError as exc:
        log_error(f"hook input is not valid UTF-8: {type(exc).__name__}")
    except json.JSONDecodeError as exc:
        log_error(f"hook input is not valid JSON at line {exc.lineno}, column {exc.colno}")

request_id = f"{source}:{int(time.time() * 1000)}:{random.randrange(1_000_000):06d}"
report_seq = time.time_ns()
session_id = hook_input.get("session_id")
agent_session_id = session_id if isinstance(session_id, str) and session_id else None
if agent_session_id:
    request = {
        "id": request_id,
        "method": "pane.report_agent_session",
        "params": {
            "pane_id": pane_id,
            "source": source,
            "agent": "codex",
            "seq": report_seq,
            "agent_session_id": agent_session_id,
        },
    }
else:
    raise SystemExit(0)

try:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(0.5)
        client.connect(socket_path)
        client.sendall((json.dumps(request) + "\n").encode())
        try:
            client.recv(4096)
        except socket.timeout:
            log_error("timed out waiting for Herdr response; delivery is unconfirmed")
except OSError as exc:
    log_error(f"failed to report agent session to Herdr: {type(exc).__name__}")
PY
