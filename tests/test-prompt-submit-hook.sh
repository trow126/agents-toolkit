#!/usr/bin/env bash
# UserPromptSubmit hook is silenced (owner decision D3②): every input exits 0 with no output.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/claude/hooks/prompt-submit-hook.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

STDOUT_FILE="$SANDBOX/stdout"
STDERR_FILE="$SANDBOX/stderr"
FAILURES=0
CASE_RC=0

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

run_input() {
  local input="$1"
  : > "$STDOUT_FILE"
  : > "$STDERR_FILE"
  set +e
  printf '%s' "$input" | "$HOOK" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  CASE_RC=${PIPESTATUS[1]}
  set -e
}

assert_silent_success() {
  local desc="$1"
  if [[ "$CASE_RC" -eq 0 ]]; then
    ok "$desc: exit 0"
  else
    ng "$desc: expected exit 0, got $CASE_RC"
  fi
  if [[ ! -s "$STDOUT_FILE" ]]; then
    ok "$desc: stdout は空"
  else
    ng "$desc: stdout に出力された: $(<"$STDOUT_FILE")"
  fi
  if [[ ! -s "$STDERR_FILE" ]]; then
    ok "$desc: stderr は空"
  else
    ng "$desc: stderr に出力された: $(<"$STDERR_FILE")"
  fi
}

run_input '{"hook_event_name":"UserPromptSubmit","user_prompt":"fixture","cwd":"/tmp"}'
assert_silent_success "valid UserPromptSubmit JSON"

run_input 'not-json'
assert_silent_success "非 JSON stdin"

run_input ''
assert_silent_success "空 stdin"

if grep -qx 'MAX_INJECTION_BYTES=0' "$HOOK"; then
  ok "MAX_INJECTION_BYTES は 0（measure-hook-injection の上限値）"
else
  ng "MAX_INJECTION_BYTES=0 の宣言がない"
fi

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
