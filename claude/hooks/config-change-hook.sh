#!/bin/bash
# ConfigChange hook: enforce "edit settings.json via shell, restart Claude" rule
# Blocks in-session edits to ~/.claude/settings.json (rules/safety.md)

set -euo pipefail

INPUT=$(cat)

FILE=$(echo "$INPUT" | jq -r '.file_path // .tool_input.file_path // .path // empty' 2>/dev/null)

if [ -z "$FILE" ]; then
    exit 0
fi

case "$FILE" in
    "$HOME/.claude/settings.json"|"$HOME/.claude/settings.local.json")
        echo "Blocked: ~/.claude/settings.json must be edited via shell, then Claude restarted (rules/safety.md)" >&2
        exit 2
        ;;
esac

exit 0
