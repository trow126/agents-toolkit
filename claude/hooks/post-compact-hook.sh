#!/usr/bin/env bash
# PostCompact hook: re-inject bounded repository orientation after compaction.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
EMITTER="$SCRIPT_DIR/lib/emit_system_message.py"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git branch --show-current 2>/dev/null || true)"
  [[ -n "$branch" ]] || branch="detached"
  status_count="$(git status --short 2>/dev/null | wc -l | tr -d ' ')"
  staged="$(git diff --cached --shortstat 2>/dev/null || true)"
  if [[ "$status_count" -gt 0 ]]; then
    state="Uncommitted changes: $status_count files"
  else
    state="Clean working tree"
  fi
  msg="[Post-Compact Context] Branch: $branch | $state"
  [[ -n "$staged" ]] && msg="$msg | Staged: $staged"
else
  msg="[Post-Compact Context] CWD: $(pwd -P) (not a git repo)"
fi

printf '%s\n' "$msg" | python3 "$EMITTER"
