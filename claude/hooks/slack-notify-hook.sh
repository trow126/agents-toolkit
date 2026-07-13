#!/bin/bash
#
# Claude Code Hook: Delayed Slack notification on stop/notification events
#
# Usage (called by Claude Code hooks):
#   echo '{"message":"..."}' | slack-notify-hook.sh notification
#   echo '{"stop_reason":"..."}' | slack-notify-hook.sh stop
#
# Behavior: Waits 5 minutes before sending notification.
# If a new event fires within that window, the pending notification is cancelled
# and a new 5-minute timer starts. This avoids notifying while the user is active.
#

set -euo pipefail

EVENT_TYPE="${1:-unknown}"
DELAY_SECONDS=300
PID_FILE="/tmp/claude-code-slack-notify.pid"
SLACK_NOTIFY="$HOME/.claude/bin/slack-notify"

# Cancel any pending notification
OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null || true
fi
rm -f "$PID_FILE"

# Project name from CWD
PROJECT_NAME=$(basename "$PWD")

# Build message based on event type
case "$EVENT_TYPE" in
    notification)
        CONTEXT=$(cat 2>/dev/null || echo "{}")
        MSG=$(echo "$CONTEXT" | jq -r '.message // empty' 2>/dev/null || true)
        if [[ -z "$MSG" ]]; then
            MSG="input required"
        fi
        NOTIFY_MSG="[$PROJECT_NAME] $MSG"
        ;;
    stop)
        NOTIFY_MSG="[$PROJECT_NAME] processing complete"
        ;;
    *)
        exit 0
        ;;
esac

# Schedule delayed notification in background
# setsid: new session so Claude Code doesn't wait for process group
# FD redirect: close inherited pipes so Claude Code sees hook as finished
(
    trap 'kill $(jobs -p) 2>/dev/null' TERM
    sleep "$DELAY_SECONDS" &
    wait
    "$SLACK_NOTIFY" -m "$NOTIFY_MSG" -s || true
) </dev/null >/dev/null 2>&1 &
disown

echo "$!" > "$PID_FILE"

exit 0
