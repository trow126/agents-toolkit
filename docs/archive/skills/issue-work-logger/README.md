# Issue Work Logger - Automatic Progress Tracking

Automatically logs TodoWrite task state changes to `claudedocs/work/issue_N_notes.md`.

## Features

✅ **Session start detection** - Logs when work begins on an Issue  
✅ **Task start tracking** - Logs when tasks move to in_progress  
✅ **Task completion tracking** - Logs when tasks are completed  
✅ **State persistence** - Maintains TodoWrite state between invocations  

## Installation

Scripts are already installed in:
```
~/.claude/skills/issue-work-logger/scripts/auto_logger.py
```

## Usage

### Environment Variables

```bash
export CURRENT_ISSUE_NUMBER=42  # Required: Issue number
export WORK_DIR=~/claudedocs/work  # Optional: Work directory path
```

### Automatic Invocation

The script is designed to be called automatically by Claude after TodoWrite operations:

```bash
# Claude internally runs:
echo "$TODOWRITE_JSON" | python3 ~/.claude/skills/issue-work-logger/scripts/auto_logger.py
```

### Manual Testing

```bash
cd ~/.claude/skills/issue-work-logger/scripts
bash test_auto_logger.sh
```

## How It Works

1. **State Comparison**: Compares current TodoWrite state with previous state
2. **Change Detection**: Identifies status changes (pending→in_progress→completed)
3. **Log Append**: Writes timestamped entries to notes.md
4. **State Save**: Persists current state for next comparison

## Log Format

```markdown
## [2025-11-01 16:35] Session started
**Starting task**: Analyze requirements

## [2025-11-01 16:35] Task started
**Task**: Analyze requirements

## [2025-11-01 16:40] Task completed
**Task**: Analyze requirements
```

## Files

- `auto_logger.py` - Main script
- `test_auto_logger.sh` - Integration tests
- `templates/` - Log file templates
- `SKILL.md` - Skill documentation

## Requirements

- Python 3.x (standard library only)
- TodoWrite state as JSON via stdin
- `CURRENT_ISSUE_NUMBER` environment variable

## Error Handling

- Missing Issue number: Error exit
- Invalid JSON: Error exit
- Missing notes file: Creates new file
- State file corruption: Treats as empty state
