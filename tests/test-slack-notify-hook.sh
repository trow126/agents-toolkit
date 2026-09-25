#!/usr/bin/env bash
# slack-notify-hook opt-out: AGENTS_TOOLKIT_SLACK_NOTIFY=off exits 0 at once, schedules no
# sender, and leaves the shared pending-notification PID file untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/claude/hooks/slack-notify-hook.sh"
PID_FILE="/tmp/claude-code-slack-notify.pid"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

mkdir -p "$SANDBOX/home/.claude/bin"
cat > "$SANDBOX/home/.claude/bin/slack-notify" <<'STUB'
#!/usr/bin/env bash
printf 'sent\n' >> "$HOME/sent.log"
STUB
chmod +x "$SANDBOX/home/.claude/bin/slack-notify"

pid_state() {
  if [[ -e "$PID_FILE" ]]; then
    stat -c '%Y %s' "$PID_FILE"
  else
    echo absent
  fi
}

for event in stop notification; do
  before="$(pid_state)"
  start=$SECONDS
  rc=0
  out="$(printf '{"message":"fixture"}' | HOME="$SANDBOX/home" AGENTS_TOOLKIT_SLACK_NOTIFY=off "$HOOK" "$event" 2>&1)" || rc=$?
  elapsed=$((SECONDS - start))
  after="$(pid_state)"
  if [[ "$rc" -eq 0 && -z "$out" ]]; then ok "$event: opt-out は何も出力せず exit 0"; else ng "$event: rc=$rc out=$out"; fi
  if [[ "$elapsed" -le 2 ]]; then ok "$event: opt-out は待たずに終了する"; else ng "$event: ${elapsed}s かかった"; fi
  if [[ "$before" == "$after" ]]; then ok "$event: pending PID file に触れない"; else ng "$event: PID file が変わった ($before -> $after)"; fi
  if [[ ! -e "$SANDBOX/home/sent.log" ]]; then ok "$event: sender を起動しない"; else ng "$event: sender が起動した"; fi
done

if grep -q 'AGENTS_TOOLKIT_SLACK_NOTIFY' "$HOOK"; then
  ok "hook は AGENTS_TOOLKIT_SLACK_NOTIFY を参照する"
else
  ng "hook に opt-out env が無い"
fi

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
