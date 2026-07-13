#!/bin/bash
# Single-line status line for Claude Code (full width, no truncation)

input=$(cat)

# Parse JSON
MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // "."')
CWD_SHORT="${CWD##*/}"

# Context info
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
USAGE=$(echo "$input" | jq '.context_window.current_usage // null')

if [ "$USAGE" != "null" ]; then
    INPUT_TOKENS=$(echo "$USAGE" | jq -r '.input_tokens // 0')
    CACHE_CREATE=$(echo "$USAGE" | jq -r '.cache_creation_input_tokens // 0')
    CACHE_READ=$(echo "$USAGE" | jq -r '.cache_read_input_tokens // 0')
    TOTAL_TOKENS=$((INPUT_TOKENS + CACHE_CREATE + CACHE_READ))

    if [ $TOTAL_TOKENS -ge 1000 ]; then
        TOKEN_DISPLAY=$(awk "BEGIN {printf \"%.1fk\", $TOTAL_TOKENS/1000}")
    else
        TOKEN_DISPLAY="${TOTAL_TOKENS}"
    fi
    PERCENT=$((TOTAL_TOKENS * 100 / CONTEXT_SIZE))
else
    TOKEN_DISPLAY="0"
    PERCENT=0
fi

# Git info
GIT_INFO=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    [ -z "$BRANCH" ] && BRANCH="detached"

    ADDED=$(git diff --numstat 2>/dev/null | awk '{s+=$1} END {print s+0}')
    REMOVED=$(git diff --numstat 2>/dev/null | awk '{s+=$2} END {print s+0}')

    if [ "$ADDED" -gt 0 ] || [ "$REMOVED" -gt 0 ]; then
        GIT_INFO="⎇ ${BRANCH} +${ADDED}/-${REMOVED}"
    else
        GIT_INFO="⎇ ${BRANCH}"
    fi
else
    GIT_INFO="⎇ -"
fi

# Colors
C='\033[36m'   # Cyan
G='\033[32m'   # Green
M='\033[35m'   # Magenta
B='\033[34m'   # Blue
R='\033[0m'    # Reset

# Single line output
echo -e "${C}${MODEL}${R} | Ctx:${TOKEN_DISPLAY} ${G}${PERCENT}%${R} | ${M}${GIT_INFO}${R} | ${B}${CWD_SHORT}${R}"
