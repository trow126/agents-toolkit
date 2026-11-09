#!/usr/bin/env bash
# test-ask-guard.sh — claude/hooks/ask-guard-hook.sh (Stop).
# In an interactive session a final reply that ends with a prose question to the user is blocked once
# per turn; headless runs, replies without a question, questions only inside code, quotes, or URLs, and
# internal errors never block. No model is called.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/claude/hooks/ask-guard-hook.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
ok() { echo "ok: $1"; }
ng() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

ASK_END=$'テストは 37 本すべて合格しました。\n\ncommit して main にマージしてよいですか？'
ASK_PLAIN=$'差分は作業ツリーに残してあります。\n\nどちらで進めますか。'
ASK_ENGLISH=$'All tests pass.\n\nShould I commit and push?'
ASK_THEN_NOTE=$'1 と 2 のどちらにしますか？\n\nなお、取り直しは今も裏で動いています。終わったら報告します。'
ASK_IN_LIST=$'## 決めてほしいこと\n\n1. commit してよいですか。\n2. #5 を閉じてよいですか。'
DONE=$'実行は完了しました。テストは 37 本すべて合格し、`validate-layout` も通っています。\n\ncommit はしていません。'
EARLY_ASK=$'なぜ落ちたのか？ 原因は timeout でした。\n\n修正を入れました。\n\nテストは通っています。'
IN_CODE=$'結果です。\n\n```text\nAre you sure? [y/N]\n```\n\n`git status --porcelain?` の出力は空でした。'
IN_URL=$'検索結果は次のとおりです。\n\n- https://example.com/search?q=abc&o=newest'
IN_QUOTE=$'前回の依頼です。\n\n> この1本も同じ方法で取りますか？\n\nその1本は手動で取り終えました。'

stop() { # <reply> [stop_hook_active] [entrypoint]
  jq -n --arg m "$1" --argjson a "${2:-false}" \
    '{hook_event_name: "Stop", stop_hook_active: $a, last_assistant_message: $m}' |
    CLAUDE_CODE_ENTRYPOINT="${3-cli}" "$HOOK" 2>"$SANDBOX/err"
}
expect() { # <desc> <want rc> <command...>
  local desc="$1" want="$2" rc=0
  shift 2
  "$@" || rc=$?
  if [[ "$rc" -eq "$want" ]]; then ok "$desc"; else ng "$desc (rc=$rc, want $want): $(cat "$SANDBOX/err")"; fi
}

expect "最後が「〜よいですか？」の返答は止める" 2 stop "$ASK_END"
grep -q "AskUserQuestion で" "$SANDBOX/err" && ok "止める理由は AskUserQuestion で聞き直すよう求める" || ng "block message: $(cat "$SANDBOX/err")"
grep -q "よいですか" "$SANDBOX/err" && ok "止める理由に該当の質問文を示す" || ng "block message lacks the question: $(cat "$SANDBOX/err")"
expect "「〜ますか。」（疑問符なし）も止める" 2 stop "$ASK_PLAIN"
expect "英語の疑問文も止める" 2 stop "$ASK_ENGLISH"
expect "質問の後に補足の段落が1つ続いても止める" 2 stop "$ASK_THEN_NOTE"
expect "箇条書きの確認項目も止める" 2 stop "$ASK_IN_LIST"
expect "claude-desktop の対話セッションも対象" 2 stop "$ASK_END" false claude-desktop
expect "同じ turn の2回目（stop_hook_active）は止めない" 0 stop "$ASK_END" true
expect "質問の無い完了報告は止めない" 0 stop "$DONE"
expect "末尾2段落より前の疑問文は止めない" 0 stop "$EARLY_ASK"
expect "コードブロックとインラインコードの ? は止めない" 0 stop "$IN_CODE"
expect "URL の ? は止めない" 0 stop "$IN_URL"
expect "引用行の質問は止めない" 0 stop "$IN_QUOTE"
expect "headless（sdk-cli）は止めない" 0 stop "$ASK_END" false sdk-cli
expect "entrypoint が無い runtime は止めない" 0 sh -c 'jq -n --arg m "$1" "{hook_event_name: \"Stop\", stop_hook_active: false, last_assistant_message: \$m}" | env -u CLAUDE_CODE_ENTRYPOINT "$0"' "$HOOK" "$ASK_END"
expect "last_assistant_message が無い入力は止めない" 0 sh -c 'echo "{\"hook_event_name\": \"Stop\", \"stop_hook_active\": false}" | CLAUDE_CODE_ENTRYPOINT=cli "$0"' "$HOOK"
expect "Stop 以外の event は対象外" 0 sh -c 'echo "{\"hook_event_name\": \"PreToolUse\", \"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"ls\"}}" | CLAUDE_CODE_ENTRYPOINT=cli "$0"' "$HOOK"
expect "入力が JSON でなければ exit 1（止めない）" 1 sh -c 'printf "not json" | CLAUDE_CODE_ENTRYPOINT=cli "$0" 2>"$1"' "$HOOK" "$SANDBOX/err"
grep -q "internal error" "$SANDBOX/err" && ok "内部エラーは理由を出す" || ng "no internal error message"

if jq -e '[.hooks.Stop[].hooks[].command] | index("~/.claude/hooks/ask-guard-hook.sh") != null' "$REPO_ROOT/claude/managed-settings.json" >/dev/null; then
  ok "managed settings が Stop に登録している"
else
  ng "managed settings に ask-guard-hook の登録が無い"
fi

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then echo "PASS: all assertions succeeded"; exit 0; fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
