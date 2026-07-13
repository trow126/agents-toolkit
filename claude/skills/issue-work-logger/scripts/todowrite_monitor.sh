#!/bin/bash
# TodoWrite Monitor - Triggered after /gh:issue work to monitor changes

set -e

ISSUE_NUMBER="$1"
WORK_DIR="${2:-$HOME/claudedocs/work}"

if [ -z "$ISSUE_NUMBER" ]; then
    echo "Error: Issue number required" >&2
    echo "Usage: todowrite_monitor.sh <issue_number> [work_dir]" >&2
    exit 1
fi

export CURRENT_ISSUE_NUMBER="$ISSUE_NUMBER"
export WORK_DIR="$WORK_DIR"

# Monitor function that should be called after TodoWrite operations
monitor_todowrite() {
    local todowrite_json="$1"
    
    # Call auto_logger
    echo "$todowrite_json" | python3 ~/.claude/skills/issue-work-logger/scripts/auto_logger.py
    
    # Call sync_progress
    echo "$todowrite_json" | python3 ~/.claude/skills/progress-tracker/scripts/sync_progress.py
}

# Export for use by Claude
export -f monitor_todowrite

echo "TodoWrite monitoring initialized for Issue #$ISSUE_NUMBER"
echo "Auto-logging enabled: claudedocs/work/issue_${ISSUE_NUMBER}_notes.md"
echo "Auto-sync enabled: GitHub Issue progress tracking"
