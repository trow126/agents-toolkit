#!/bin/bash
# PostToolUse hook: detect gh pr create and trigger auto-review
# Data is passed via stdin as JSON, not environment variables

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
STDOUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty')

# Check if the Bash command contained gh pr create
if echo "$COMMAND" | grep -q "gh pr create"; then
  # Check tool output for success (PR URL present)
  if echo "$STDOUT" | grep -qE "https://github\.com/.+/pull/[0-9]+"; then
    echo "PR作成を検出。Skill ツールで 'pr-review' スキルを起動し、Post-PR セルフレビュー規約に従うこと。"
    echo "要点: Agent でレビュー生成 → gh pr comment で投稿 → 投稿後は修正・追加commit・追加pushをせず停止。"
  fi
fi
