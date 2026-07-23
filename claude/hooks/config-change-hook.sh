#!/bin/bash
# ConfigChange hook: block unsafe user/project settings changes fail-closed.
# The definitive runtime gate also runs before every Bash tool call because
# SessionStart hooks cannot prevent session startup.
set -euo pipefail

block() {
    echo "Blocked: $*" >&2
    exit 2
}

command -v jq >/dev/null 2>&1 || block "config-change-hook requires jq (fail-closed)"
INPUT=$(cat) || block "failed to read ConfigChange input"
if ! echo "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
    block "ConfigChange input is not valid JSON"
fi

FILE=$(echo "$INPUT" | jq -r '.file_path // .tool_input.file_path // .path // empty' 2>/dev/null) || \
    block "ConfigChange file path cannot be parsed"
HOOK_CWD=$(echo "$INPUT" | jq -r '(.cwd // .tool_input.cwd // "") | if type == "string" then . else "" end' 2>/dev/null) || \
    block "ConfigChange cwd cannot be parsed"
[[ -n "$HOOK_CWD" ]] || HOOK_CWD="$PWD"

# User settings are linked toolkit preferences; edit them outside the running
# session and restart so managed/user composition is revalidated.
case "$FILE" in
    "$HOME/.claude/settings.json"|"$HOME/.claude/settings.local.json")
        block "~/.claude/settings.json must be edited via shell, then Claude restarted (rules/safety.md)"
        ;;
esac

HOOK_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)" || block "cannot resolve hook directory"
PROJECT_POLICY_GATE="$HOOK_DIR/../bin/project-policy-gate"
[[ -x "$PROJECT_POLICY_GATE" ]] || block "project-policy-gate is missing or not executable"
if ! GATE_OUTPUT=$("$PROJECT_POLICY_GATE" --cwd "$HOOK_CWD" --quiet 2>&1); then
    block "unsafe project/local Claude settings: $GATE_OUTPUT"
fi

exit 0
