#!/bin/bash
# Track TodoWrite - Call this after TodoWrite operations to log and sync

ISSUE_NUMBER="${CURRENT_ISSUE_NUMBER:-}"
WORK_DIR="${WORK_DIR:-$HOME/claudedocs/work}"

if [ -z "$ISSUE_NUMBER" ]; then
    # No Issue tracking active, skip
    exit 0
fi

# Get current TodoWrite state as JSON
# This would normally come from Claude's TodoWrite tool
# For now, we accept it via stdin
TODOWRITE_JSON=$(cat)

if [ -z "$TODOWRITE_JSON" ]; then
    # No TodoWrite data, skip
    exit 0
fi

# Export for scripts
export CURRENT_ISSUE_NUMBER
export WORK_DIR

# Run auto_logger
echo "$TODOWRITE_JSON" | python3 ~/.claude/skills/issue-work-logger/scripts/auto_logger.py 2>&1 | \
    sed 's/^/[auto_logger] /' || true

# Run sync_progress
echo "$TODOWRITE_JSON" | python3 ~/.claude/skills/progress-tracker/scripts/sync_progress.py 2>&1 | \
    sed 's/^/[sync_progress] /' || true
