#!/usr/bin/env bash
# Unit tests for ask-claude.sh using deterministic mock binaries.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/ask-claude.sh"
SANDBOX="$(mktemp -d)"
MOCK_BIN="$(mktemp -d)"
trap 'rm -rf "$SANDBOX" "$MOCK_BIN"' EXIT

cat >"$MOCK_BIN/claudecode" <<'MOCK'
#!/usr/bin/env bash
[[ -z "${TEST_INVOCATIONS_FILE:-}" ]] || printf 'invoke\n' >>"$TEST_INVOCATIONS_FILE"
[[ -z "${TEST_CLAUDE_ARGS_FILE:-}" ]] || printf '%q\n' "$@" >"$TEST_CLAUDE_ARGS_FILE"
[[ -z "${TEST_PWD_FILE:-}" ]] || pwd >"$TEST_PWD_FILE"
[[ -z "${TEST_IDLE_FILE:-}" ]] || printf '%s' "${CLAUDE_STREAM_IDLE_TIMEOUT_MS:-}" >"$TEST_IDLE_FILE"
if [[ -n "${TEST_PROMPT_FILE:-}" ]]; then cat >"$TEST_PROMPT_FILE"; else cat >/dev/null; fi
[[ -z "${TEST_CLAUDE_SLEEP:-}" ]] || sleep "$TEST_CLAUDE_SLEEP"
[[ -z "${TEST_CLAUDE_EXIT:-}" ]] || exit "$TEST_CLAUDE_EXIT"

success_result() {
  printf '%s\n' '{"type":"system","subtype":"init","model":"claude-fable-5","tools":[]}'
  printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"MOCK_CLAUDECODE_OK"}'
}

case "${TEST_STREAM_MODE:-success}" in
  success) success_result ;;
  bytes)
    printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"日本語\nquote \"x\"\\tail\n"}'
    ;;
  unknown-event)
    printf '%s\n' '{"type":"future_event","payload":{"value":1}}'
    success_result
    ;;
  duplicate)
    printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"FIRST"}'
    printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"SECOND"}'
    ;;
  malformed) printf '%s\n' 'not-json'; success_result ;;
  empty-line) printf '\n'; success_result ;;
  missing-type) printf '%s\n' '{"subtype":"init"}'; success_result ;;
  error) printf '%s\n' '{"type":"result","subtype":"error","is_error":true,"result":"failure"}' ;;
  missing-result) printf '%s\n' '{"type":"system","subtype":"init","model":"claude-fable-5","tools":[]}' ;;
  empty-result) printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":""}' ;;
  whitespace-result) printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"  \n"}' ;;
  null-result) printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":null}' ;;
  nonstring-result) printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":42}' ;;
  *) exit 88 ;;
esac
MOCK
chmod 755 "$MOCK_BIN/claudecode"

cat >"$MOCK_BIN/timeout" <<'MOCK'
#!/usr/bin/env bash
[[ -z "${TEST_TIMEOUT_ARGS_FILE:-}" ]] || printf '%s\n%s' "$1" "$2" >"$TEST_TIMEOUT_ARGS_FILE"
exec /usr/bin/timeout "$@"
MOCK
chmod 755 "$MOCK_BIN/timeout"

cat >"$MOCK_BIN/claude" <<'MOCK'
#!/usr/bin/env bash
echo "WRONG_CLAUDE_COMMAND" >&2
exit 99
MOCK
chmod 755 "$MOCK_BIN/claude"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; shift; printf '        %s\n' "$@"; FAIL=$((FAIL + 1)); }

run_case() {
  local name="$1" expected_exit="$2"
  shift 2
  local actual_exit=0
  "$@" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    pass "$name (exit=$actual_exit)"
  else
    fail "$name" "expected=$expected_exit got=$actual_exit"
  fi
}

echo "## CLI and input validation"
run_case "help" 0 env PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" --help
run_case "unknown-arg" 64 env PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" --unknown
run_case "missing-cwd-value" 64 env PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" --cwd
run_case "missing-timeout-value" 64 env PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" --cwd "$SANDBOX" --timeout
run_case "nonexistent-cwd" 2 env PATH="$MOCK_BIN:$PATH" bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX/missing'"
run_case "home-reject" 2 env PATH="$MOCK_BIN:$PATH" bash -c "printf q | '$SCRIPT' --cwd '$HOME'"
ln -s "$HOME" "$SANDBOX/home-link"
run_case "home-symlink-reject" 2 env PATH="$MOCK_BIN:$PATH" bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX/home-link'"
run_case "empty-prompt" 65 env PATH="$MOCK_BIN:$PATH" bash -c "printf '' | '$SCRIPT' --cwd '$SANDBOX'"
run_case "whitespace-prompt" 65 env PATH="$MOCK_BIN:$PATH" bash -c "printf ' \\n\\t' | '$SCRIPT' --cwd '$SANDBOX'"
run_case "timeout-zero" 64 env PATH="$MOCK_BIN:$PATH" bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX' --timeout 0"
run_case "timeout-negative" 64 env PATH="$MOCK_BIN:$PATH" bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX' --timeout -1"
run_case "timeout-text" 64 env PATH="$MOCK_BIN:$PATH" bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX' --timeout nope"

echo "## Dependency validation"
required=(claudecode timeout realpath jq mktemp cat grep rm)
for missing in "${required[@]}"; do
  dep_dir="$SANDBOX/no-$missing"
  mkdir -p "$dep_dir"
  for cmd in "${required[@]}"; do
    [[ "$cmd" == "$missing" ]] && continue
    if [[ "$cmd" == "claudecode" ]]; then
      ln -s "$MOCK_BIN/claudecode" "$dep_dir/claudecode"
    elif [[ "$cmd" == "timeout" ]]; then
      ln -s "$MOCK_BIN/timeout" "$dep_dir/timeout"
    else
      ln -s "$(command -v "$cmd")" "$dep_dir/$cmd"
    fi
  done
  run_case "missing-$missing" 127 env PATH="$dep_dir" /bin/bash -c "printf q | /bin/bash '$SCRIPT' --cwd '$SANDBOX'"
done

echo "## Protocol and exit behavior"
run_case "timeout-exceed" 124 env PATH="$MOCK_BIN:$PATH" TEST_CLAUDE_SLEEP=2 bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX' --timeout 1"
run_case "claude-nonzero" 42 env PATH="$MOCK_BIN:$PATH" TEST_CLAUDE_EXIT=42 bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX'"
for mode in malformed empty-line missing-type error missing-result empty-result whitespace-result null-result nonstring-result duplicate; do
  run_case "$mode" 70 env PATH="$MOCK_BIN:$PATH" TEST_STREAM_MODE="$mode" bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX'"
done
run_case "unknown-valid-event" 0 env PATH="$MOCK_BIN:$PATH" TEST_STREAM_MODE=unknown-event bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX'"

echo "## Output, arguments, isolation, and cleanup"
stdout_file="$SANDBOX/stdout"
stderr_file="$SANDBOX/stderr"
args_file="$SANDBOX/args"
timeout_file="$SANDBOX/timeout"
idle_file="$SANDBOX/idle"
pwd_file="$SANDBOX/pwd"
prompt_copy="$SANDBOX/prompt-copy"
input_file="$SANDBOX/input"
printf 'question with trailing newline\n' >"$input_file"

actual_exit=0
env PATH="$MOCK_BIN:$PATH" TEST_CLAUDE_ARGS_FILE="$args_file" TEST_TIMEOUT_ARGS_FILE="$timeout_file" \
  TEST_IDLE_FILE="$idle_file" TEST_PWD_FILE="$pwd_file" TEST_PROMPT_FILE="$prompt_copy" \
  bash "$SCRIPT" --cwd "$SANDBOX" <"$input_file" >"$stdout_file" 2>"$stderr_file" || actual_exit=$?

expected_args=$'-p\n--verbose\n--output-format\nstream-json\n--permission-mode\ndontAsk\n--safe-mode\n--no-session-persistence\n--prompt-suggestions\nfalse\n--model\nfable\n--effort\nhigh\n--tools\n\x27\x27'
run_pwd="$(<"$pwd_file")"
prompt_contract_ok=1
[[ "$actual_exit" -eq 0 ]] || prompt_contract_ok=0
[[ "$(<"$stdout_file")" == "MOCK_CLAUDECODE_OK" ]] || prompt_contract_ok=0
[[ "$(<"$args_file")" == "$expected_args" ]] || prompt_contract_ok=0
[[ "$(<"$timeout_file")" == $'--kill-after=10s\n1200' ]] || prompt_contract_ok=0
[[ "$(<"$idle_file")" == "900000" ]] || prompt_contract_ok=0
[[ "$run_pwd" != "$SANDBOX" && ! -e "$run_pwd" ]] || prompt_contract_ok=0
grep -q -- '--add-dir' "$args_file" && prompt_contract_ok=0
cmp -s "$input_file" "$prompt_copy" || prompt_contract_ok=0
grep -q 'init model=claude-fable-5 tools=none' "$stderr_file" || prompt_contract_ok=0
grep -q '{"type"' "$stderr_file" && prompt_contract_ok=0
if (( prompt_contract_ok )); then
  pass "prompt-only-contract"
else
  fail "prompt-only-contract" "exit=$actual_exit" "stdout=$(<"$stdout_file")" "args=$(<"$args_file")" "stderr=$(<"$stderr_file")"
fi

env PATH="$MOCK_BIN:$PATH" TEST_TIMEOUT_ARGS_FILE="$timeout_file" \
  bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX' --timeout 77" >/dev/null 2>&1
[[ "$(<"$timeout_file")" == $'--kill-after=10s\n77' ]] \
  && pass "timeout-override" || fail "timeout-override" "value=$(<"$timeout_file")"

env PATH="$MOCK_BIN:$PATH" TEST_CLAUDE_ARGS_FILE="$args_file" \
  bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX' --allow-web" >/dev/null 2>&1
if grep -Fqx -- '--allowedTools' "$args_file" \
  && [[ "$(grep -Fxc 'WebSearch\,WebFetch' "$args_file")" -eq 2 ]]; then
  pass "allow-web-tools"
else
  fail "allow-web-tools" "args=$(<"$args_file")"
fi

env PATH="$MOCK_BIN:$PATH" TEST_CLAUDE_ARGS_FILE="$args_file" \
  bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX' --include-cwd" >/dev/null 2>&1
if grep -Fqx -- '--add-dir' "$args_file" \
  && grep -Fqx -- "$SANDBOX" "$args_file" \
  && grep -Fqx -- '--allowedTools' "$args_file" \
  && [[ "$(grep -Fxc 'Read\,Glob\,Grep' "$args_file")" -eq 2 ]]; then
  pass "include-cwd-tools"
else
  fail "include-cwd-tools" "args=$(<"$args_file")"
fi

env PATH="$MOCK_BIN:$PATH" TEST_CLAUDE_ARGS_FILE="$args_file" \
  bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX' --include-cwd --allow-web" >/dev/null 2>&1
if grep -Fqx -- '--allowedTools' "$args_file" \
  && [[ "$(grep -Fxc 'Read\,Glob\,Grep\,WebSearch\,WebFetch' "$args_file")" -eq 2 ]]; then
  pass "combined-tools"
else
  fail "combined-tools" "args=$(<"$args_file")"
fi

expected_bytes="$SANDBOX/expected-bytes"
actual_bytes="$SANDBOX/actual-bytes"
printf '日本語\nquote "x"\\tail\n' >"$expected_bytes"
env PATH="$MOCK_BIN:$PATH" TEST_STREAM_MODE=bytes bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX'" >"$actual_bytes" 2>/dev/null
cmp -s "$expected_bytes" "$actual_bytes" \
  && pass "verbatim-result-bytes" || fail "verbatim-result-bytes" "byte output differs"

invocations_file="$SANDBOX/invocations"
actual_exit=0
env PATH="$MOCK_BIN:$PATH" TEST_INVOCATIONS_FILE="$invocations_file" TEST_STREAM_MODE=error \
  bash -c "printf q | '$SCRIPT' --cwd '$SANDBOX'" >/dev/null 2>&1 || actual_exit=$?
if [[ "$actual_exit" -eq 70 && "$(wc -l <"$invocations_file")" -eq 1 ]]; then
  pass "single-invoke-no-fallback"
else
  fail "single-invoke-no-fallback" "exit=$actual_exit" "invocations=$(wc -l <"$invocations_file")"
fi

echo
echo "Total: PASS=$PASS  FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
