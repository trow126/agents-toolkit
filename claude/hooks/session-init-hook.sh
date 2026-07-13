#!/bin/bash
# SessionStart hook: inject git context into systemMessage
# Outputs JSON with systemMessage field on success, exits 0 silently on failure

set -euo pipefail

OUTPUT=""

if git rev-parse --is-inside-work-tree 2>/dev/null; then
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    [ -z "$BRANCH" ] && BRANCH="detached"

    STATUS=$(git status --short 2>/dev/null | head -20)
    STATUS_COUNT=$(git status --short 2>/dev/null | wc -l)

    LOG=$(git log --oneline -3 2>/dev/null || echo "")

    MSG="[Session Init] Branch: ${BRANCH}"
    if [ -n "$STATUS" ]; then
        MSG="${MSG} | Changes: ${STATUS_COUNT} files"
    else
        MSG="${MSG} | Clean working tree"
    fi
    if [ -n "$LOG" ]; then
        MSG="${MSG} | Recent: $(echo "$LOG" | head -1)"
    fi

    printf '{"systemMessage":"%s"}\n' "$(echo "$MSG" | sed 's/"/\\"/g' | tr '\n' ' ')"
else
    CWD=$(pwd)
    printf '{"systemMessage":"[Session Init] CWD: %s (not a git repo)"}\n' "$CWD"
fi

exit 0
