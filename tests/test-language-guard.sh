#!/usr/bin/env bash
# test-language-guard.sh — claude/hooks/language-guard-hook.sh (Stop and PreToolUse AskUserQuestion).
# With "language": "japanese" an English final reply is blocked once per turn and an English question
# is refused; other languages, code-heavy replies, and internal errors never block. No model is called.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/claude/hooks/language-guard-hook.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
ok() { echo "ok: $1"; }
ng() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

export HOME="$SANDBOX/home"
mkdir -p "$HOME/.claude"
set_language() { printf '{"language": "%s"}\n' "$1" > "$HOME/.claude/settings.json"; }

ENGLISH='The run is finished: all 37 tests pass and the layout check is clean. I did not commit anything; the changes are left in the working tree for you to review before committing.'
JAPANESE='実行は完了しました。テストは 37 本すべて合格し、`validate-layout` も通っています。commit はしていません。変更は作業ツリーに残してあるので、確認してから commit してください。'
CODE_HEAVY=$'結果です。\n\n```text\nTraceback (most recent call last): File "x.py", line 3, in main raise ValueError("bad input value for the parser")\n```\n\n`/home/user/project/src/module/file.py` を直します。'

stop() { # <reply> [stop_hook_active]
  jq -n --arg m "$1" --argjson a "${2:-false}" \
    '{hook_event_name: "Stop", stop_hook_active: $a, last_assistant_message: $m}' | "$HOOK" 2>"$SANDBOX/err"
}
ask() { # <question>
  jq -n --arg q "$1" '{hook_event_name: "PreToolUse", tool_name: "AskUserQuestion",
    tool_input: {questions: [{question: $q, header: "h", multiSelect: false,
      options: [{label: "A", description: "a"}, {label: "B", description: "b"}]}]}}' | "$HOOK" 2>"$SANDBOX/err"
}
expect() { # <desc> <want rc> <command...>
  local desc="$1" want="$2" rc=0
  shift 2
  "$@" || rc=$?
  if [[ "$rc" -eq "$want" ]]; then ok "$desc"; else ng "$desc (rc=$rc, want $want): $(cat "$SANDBOX/err")"; fi
}

set_language japanese
expect "英語の最終返答は止める" 2 stop "$ENGLISH"
grep -q "日本語で書き直して" "$SANDBOX/err" && ok "止める理由は日本語で書き直しを求める" || ng "block message: $(cat "$SANDBOX/err")"
expect "同じ turn の2回目（stop_hook_active）は止めない" 0 stop "$ENGLISH" true
expect "日本語の返答は止めない" 0 stop "$JAPANESE"
expect "コードブロックとパスを除けば日本語の返答は止めない" 0 stop "$CODE_HEAVY"
expect "短い英語（80 字未満）は止めない" 0 stop "Done. Tests pass."
expect "last_assistant_message が無い入力は止めない" 0 sh -c 'echo "{\"hook_event_name\": \"Stop\", \"stop_hook_active\": false}" | "$0" 2>/dev/null' "$HOOK"
expect "日本語の質問は通す" 0 ask "どれを実装しますか？"
expect "英語の質問は拒否する" 2 ask "Which option should I implement?"
grep -q "日本語で書き直して" "$SANDBOX/err" && ok "拒否の理由は日本語で書き直しを求める" || ng "ask message: $(cat "$SANDBOX/err")"
expect "AskUserQuestion 以外の PreToolUse は対象外" 0 sh -c 'echo "{\"hook_event_name\": \"PreToolUse\", \"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"ls\"}}" | "$0"' "$HOOK"

set_language English
expect "language が日本語でなければ英語の返答も止めない" 0 stop "$ENGLISH"
expect "language が日本語でなければ英語の質問も通す" 0 ask "Which option should I implement?"
rm "$HOME/.claude/settings.json"
expect "settings.json が無ければ何もしない" 0 stop "$ENGLISH"

printf '{broken' > "$HOME/.claude/settings.json"
expect "settings.json が壊れていれば exit 1（止めない）" 1 stop "$ENGLISH"
grep -q "internal error" "$SANDBOX/err" && ok "内部エラーは理由を出す" || ng "no internal error message"
set_language japanese
expect "入力が JSON でなければ exit 1（止めない）" 1 sh -c 'printf "not json" | "$0" 2>/dev/null' "$HOOK"

if jq -e '[.hooks.Stop[].hooks[].command] | index("~/.claude/hooks/language-guard-hook.sh") != null' "$REPO_ROOT/claude/managed-settings.json" >/dev/null &&
  jq -e '[.hooks.PreToolUse[] | select(.matcher == "AskUserQuestion") | .hooks[].command] == ["~/.claude/hooks/language-guard-hook.sh"]' "$REPO_ROOT/claude/managed-settings.json" >/dev/null; then
  ok "managed settings が Stop と PreToolUse(AskUserQuestion) に登録している"
else
  ng "managed settings に language-guard-hook の登録が無い"
fi

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then echo "PASS: all assertions succeeded"; exit 0; fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
