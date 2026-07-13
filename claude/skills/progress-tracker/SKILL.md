---
name: progress-tracker
description: Track TodoWrite task completion and update GitHub Issues with progress comments. Use when TodoWrite tasks are completed or Issue progress needs updating. Activates on "sync progress" or explicit sync requests.
allowed-tools: Bash, TodoWrite
---

# Progress Tracker Skill

Monitors TodoWrite task completion and synchronizes progress to GitHub Issues.

## What This Skill Does

- **Detects TodoWrite completion**: When tasks are marked complete
- **Updates GitHub**: Posts progress comments via `gh-progress-sync.sh`
- **Auto-closes Issues**: When all tasks are complete (if enabled)

## When to Use

This skill activates when:
- **Explicit sync request**: "sync Issue progress"
- **Status check**: "show Issue #42 status"
- **Task completion**: After marking TodoWrite tasks complete

Explicit invocation: **"use progress-tracker skill to sync Issue #42"**

## How It Works

### Step 1: Calculate Progress
```bash
# Count TodoWrite states
total_tasks = (count all TodoWrite items)
completed_tasks = (count completed items)
percentage = (completed / total) * 100
```

### Step 2: Update GitHub
```bash
# Use gh-progress-sync.sh
gh-progress-sync.sh --json '{"issue": 42, "completed": [1,2,3], "total": 5, "task_name": "Task name"}'

# Or check specific task
gh-progress-sync.sh --check-task 42 "Task description"
```

### Step 3: Auto-Close (Optional)
```bash
if completed_tasks == total_tasks:
    gh issue comment 42 --body "All tasks completed!"
    gh issue close 42 --reason "completed"
```

## Usage Examples

### Example 1: Manual Sync
```
User: "Sync progress for Issue #42"

Claude:
  1. Reads current TodoWrite state
  2. Calculates: 3/5 tasks (60%)
  3. Runs: gh-progress-sync.sh --json '{"issue": 42, ...}'
  4. Reports: "Synced Issue #42: 3/5 tasks complete (60%)"
```

### Example 2: Auto-Close on Completion
```
User: (Marks final task as complete)

Claude:
  1. Detects last task completion
  2. Calculates: 5/5 tasks (100%)
  3. Posts completion comment
  4. Closes Issue #42

Output: "All tasks complete! Issue #42 closed."
```

## Scripts

- `~/.claude/bin/gh-progress-sync.sh` - GitHub sync utility

## Dependencies

- `gh` CLI (GitHub CLI)
- `jq` (JSON parsing)
- TodoWrite tool

## Best Practices

- Let progress updates happen after task completion
- Use `/gh:start` for full workflow integration
- Complete work within single session when possible

## Limitations

- **Single-direction**: TodoWrite → GitHub only
- **No reverse sync**: GitHub changes don't update TodoWrite
- **GitHub dependency**: Requires network access

---

**Version**: 2.0.0 (Simplified)
