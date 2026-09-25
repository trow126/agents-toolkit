#!/bin/bash
# PostToolUse hook (matcher: Bash): detect a successful `gh pr create` and tell Claude
# how the PR can be reviewed. It never asks Claude to post anything on its own.
# Data is passed via stdin as JSON, not environment variables.
#
# PostToolUse の plain stdout は Claude の context に入らない（debug log のみ）。
# Claude に届けるため hookSpecificOutput.additionalContext の JSON で出力する。
# https://code.claude.com/docs/en/hooks#add-context-for-claude
# fail-open: 入力不正や jq 欠落では何も出力せず exit 0（gate ではない）。

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat) || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
STDOUT=$(printf '%s' "$INPUT" | jq -r '.tool_response.stdout // empty' 2>/dev/null) || exit 0

printf '%s' "$COMMAND" | grep -q "gh pr create" || exit 0
PR_URL=$(printf '%s' "$STDOUT" | grep -oE "https://github\.com/[^[:space:]]+/pull/[0-9]+" | head -1)
[[ -n "$PR_URL" ]] || exit 0
PR_NUMBER="${PR_URL##*/}"

CONTEXT="PR #${PR_NUMBER} の作成を検出した（${PR_URL}）。レビューは \`/code-review ${PR_NUMBER}\` で行える。PR へのレビューコメント投稿は、ユーザーの明示指示があるときだけ \`/gh-pr --review-comment\` で行う。"

jq -n --arg ctx "$CONTEXT" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
exit 0
