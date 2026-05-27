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
    echo "PR作成を検出。PRレビュー手順を実行してください："
    echo "1. gh pr view --json number -q '.number' でPR番号を取得"
    echo "2. gh pr diff <PR番号> で差分を取得"
    echo "3. Agent でコードレビューを実施（自己レビュー防止のため別コンテキスト）"
    echo "4. レビュー結果を gh pr comment <PR番号> --body でPRコメントに投稿"
    echo "5. コメント投稿後は修正・追加commit・追加pushを開始せず停止"
  fi
fi
