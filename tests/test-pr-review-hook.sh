#!/usr/bin/env bash
# pr-review-hook: additionalContext JSON only after a successful `gh pr create`,
# pointing at active skills and never at the removed pr-review skill.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/claude/hooks/pr-review-hook.sh"
FAILURES=0
HOOK_RC=0
HOOK_OUT=""

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

run_hook() {
  set +e
  HOOK_OUT="$(printf '%s' "$1" | "$HOOK" 2>/dev/null)"
  HOOK_RC=$?
  set -e
}

run_hook '{"tool_name":"Bash","tool_input":{"command":"gh pr create --fill"},"tool_response":{"stdout":"https://github.com/owner/repo/pull/42\n"}}'
if [[ "$HOOK_RC" == "0" ]]; then ok "PR作成: exit 0"; else ng "PR作成: exit $HOOK_RC"; fi
if jq -e '.hookSpecificOutput.hookEventName == "PostToolUse" and (.hookSpecificOutput.additionalContext | type == "string")' <<< "$HOOK_OUT" >/dev/null 2>&1; then
  ok "PR作成: hookSpecificOutput.additionalContext の JSON を出力する"
else
  ng "PR作成: additionalContext JSON ではない: $HOOK_OUT"
fi
ctx="$(jq -r '.hookSpecificOutput.additionalContext // empty' <<< "$HOOK_OUT" 2>/dev/null || true)"
if [[ "$ctx" == *'/code-review 42'* && "$ctx" == *'/gh-pr --review-comment'* ]]; then
  ok "PR作成: 有効な skill（/code-review と /gh-pr --review-comment）を案内する"
else
  ng "PR作成: 案内先が不正: $ctx"
fi
if [[ "$ctx" != *"'pr-review'"* && "$ctx" != *"Skill ツール"* ]]; then
  ok "PR作成: 削除済みの pr-review skill の起動を指示しない"
else
  ng "PR作成: pr-review skill の起動を指示している: $ctx"
fi

for case_name in no-url other-command invalid-json empty; do
  case "$case_name" in
    no-url) input='{"tool_input":{"command":"gh pr create --fill"},"tool_response":{"stdout":"error: no commits"}}' ;;
    other-command) input='{"tool_input":{"command":"git status"},"tool_response":{"stdout":"https://github.com/o/r/pull/1"}}' ;;
    invalid-json) input='not-json' ;;
    empty) input='' ;;
  esac
  run_hook "$input"
  if [[ "$HOOK_RC" == "0" && -z "$HOOK_OUT" ]]; then
    ok "$case_name: 何も出力せず exit 0"
  else
    ng "$case_name: rc=$HOOK_RC out=$HOOK_OUT"
  fi
done

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
