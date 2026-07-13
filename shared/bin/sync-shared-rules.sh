#!/usr/bin/env bash
# sync-shared-rules.sh — ~/.agents/rules/ の正本を各消費ファイルのマーカー区間へ同期する
# 正本を編集したら本スクリプトを実行する。マーカー: <!-- BEGIN shared:NAME --> / <!-- END shared:NAME -->
set -euo pipefail

RULES_DIR="$HOME/.agents/rules"

sync_block() {
  local name="$1"
  local target="$2"
  local src="$RULES_DIR/$name.md"
  local begin="<!-- BEGIN shared:$name -->"
  local end="<!-- END shared:$name -->"
  if [[ ! -f "$src" ]]; then
    echo "ERROR: canonical file not found: $src" >&2
    exit 1
  fi
  if ! grep -qF "$begin" "$target"; then
    echo "ERROR: marker '$begin' not found in $target" >&2
    exit 1
  fi
  local tmp
  tmp=$(mktemp)
  awk -v begin="$begin" -v end="$end" -v src="$src" '
    $0 == begin {
      print
      while ((getline line < src) > 0) print line
      close(src)
      skipping = 1
      next
    }
    $0 == end { skipping = 0 }
    !skipping { print }
  ' "$target" > "$tmp"
  cp "$tmp" "$target"
  rm -f "$tmp"
  echo "synced shared:$name -> $target"
}

sync_block karpathy-guidelines "$HOME/.codex/AGENTS.md"
sync_block no-fallback "$HOME/.codex/AGENTS.md"
sync_block git-safety "$HOME/.codex/AGENTS.md"
sync_block decision-integrity "$HOME/.codex/AGENTS.md"
sync_block quality-priority "$HOME/.codex/AGENTS.md"
sync_block scope-discipline "$HOME/.codex/AGENTS.md"
sync_block test-policy "$HOME/.codex/AGENTS.md"
sync_block issue-completeness "$HOME/.codex/rules/issue_completeness_policy.md"
sync_block git-workflow "$HOME/.codex/AGENTS.md"
sync_block learnings "$HOME/.codex/AGENTS.md"
sync_block python-guidelines "$HOME/.codex/AGENTS.md"
sync_block python-guidelines "$HOME/.claude/rules/python.md"
