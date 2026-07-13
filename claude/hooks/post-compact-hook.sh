#!/bin/bash
# PostCompact hook: re-inject git context after context compaction
# Provides branch and working tree state so Claude retains orientation

set -euo pipefail

if git rev-parse --is-inside-work-tree 2>/dev/null; then
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    [ -z "$BRANCH" ] && BRANCH="detached"

    STATUS_COUNT=$(git status --short 2>/dev/null | wc -l)
    STAGED=$(git diff --cached --stat 2>/dev/null | tail -1)

    MSG="[Post-Compact Context] Branch: ${BRANCH}"
    if [ "$STATUS_COUNT" -gt 0 ]; then
        MSG="${MSG} | Uncommitted changes: ${STATUS_COUNT} files"
    else
        MSG="${MSG} | Clean working tree"
    fi
    if [ -n "$STAGED" ]; then
        MSG="${MSG} | Staged: ${STAGED}"
    fi

    printf '{"systemMessage":"%s"}\n' "$(echo "$MSG" | sed 's/"/\\"/g' | tr '\n' ' ')"
else
    CWD=$(pwd)
    printf '{"systemMessage":"[Post-Compact Context] CWD: %s (not a git repo)"}\n' "$CWD"
fi

exit 0
