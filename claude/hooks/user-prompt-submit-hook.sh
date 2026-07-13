#!/bin/bash
# UserPromptSubmit hook: inject project learnings.md as systemMessage on each turn.
# Lightweight: only runs if cwd has claudedocs/learnings.md.
# Output: hookSpecificOutput with additionalContext per Claude Code hook spec.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

LEARNINGS="$CWD/claudedocs/learnings.md"
if [ ! -f "$LEARNINGS" ]; then
    exit 0
fi

CONTENT=$(head -c 4000 "$LEARNINGS")

jq -n \
    --arg header "[project-learnings] $LEARNINGS" \
    --arg content "$CONTENT" \
    '{
        hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: ($header + "\n\n" + $content)
        }
    }'

exit 0
