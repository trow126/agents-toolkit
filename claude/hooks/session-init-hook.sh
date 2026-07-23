#!/usr/bin/env bash
# SessionStart hook: inject bounded, deterministic repository orientation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
EMITTER="$SCRIPT_DIR/lib/emit_system_message.py"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git branch --show-current 2>/dev/null || true)"
  [[ -n "$branch" ]] || branch="detached"
  status_count="$(git status --short 2>/dev/null | wc -l | tr -d ' ')"
  recent="$(git log -1 --format='%h %s' 2>/dev/null || true)"
  if [[ "$status_count" -gt 0 ]]; then
    state="Changes: $status_count files"
  else
    state="Clean working tree"
  fi
  msg="[Session Init] Branch: $branch | $state"
  [[ -n "$recent" ]] && msg="$msg | Recent: $recent"
else
  msg="[Session Init] CWD: $(pwd -P) (not a git repo)"
fi

printf '%s\n' "$msg" | python3 "$EMITTER"
