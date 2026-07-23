---
name: issue-parser
description: Parse GitHub Issue markdown to extract tasks, requirements, phases, and metadata. Use when working with GitHub Issues, converting Issue content to structured data, analyzing Issue structure, or extracting task lists. Activates on "parse Issue", "analyze Issue", "extract tasks from Issue", or explicit "use issue-parser skill".
allowed-tools: Bash, Read
---

# Issue Parser Skill

Extracts structured task data from GitHub Issue markdown content.

## What This Skill Does

Parses GitHub Issues to extract:
- **Task lists**: Checkbox items (`- [ ]` or `- [x]`)
- **Phases**: Organized by section headings (`##`)
- **Metadata**: Issue number, title, URL
- **Statistics**: Completion percentage, task counts

## When to Use

This skill automatically activates when you:
- Mention "parse Issue #42"
- Say "extract tasks from Issue"
- Request "analyze Issue structure"
- Need to convert Issue content to structured format

You can also explicitly invoke with: **"use issue-parser skill to parse Issue #42"**

## How It Works

### Input

Requires Issue data in JSON format:
```json
{
  "number": 42,
  "title": "Feature: User Authentication",
  "body": "## Tasks\n- [ ] API implementation\n- [x] Database schema",
  "url": "https://github.com/user/repo/issues/42"
}
```

### Process

1. **Fetch Issue Data**
   ```bash
   gh issue view <number> --json number,title,body,url > /tmp/issue_data.json
   ```

2. **Parse with Python Script**
   ```bash
   cat /tmp/issue_data.json | python3 ~/.claude/skills/issue-parser/scripts/parse_issue.py
   ```

3. **Return Structured Data**

### Output Format

```json
{
  "issue_number": 42,
  "title": "Feature: User Authentication",
  "url": "https://github.com/user/repo/issues/42",
  "phases": ["Tasks", "Requirements"],
  "tasks": [
    {
      "id": 1,
      "phase": "Tasks",
      "text": "API implementation",
      "completed": false,
      "status": "pending"
    },
    {
      "id": 2,
      "phase": "Tasks",
      "text": "Database schema",
      "completed": true,
      "status": "completed"
    }
  ],
  "statistics": {
    "total_tasks": 2,
    "completed_tasks": 1,
    "pending_tasks": 1,
    "completion_percentage": 50.0
  }
}
```

## Usage Examples

### Example 1: Parse Specific Issue
```
User: "Parse Issue #42"
Claude: (Automatically invokes issue-parser skill)
  1. Fetches Issue #42 data
  2. Runs parse_issue.py
  3. Returns structured task data
```

### Example 2: Explicit Invocation
```
User: "Use issue-parser skill to analyze Issue #123"
Claude: (Explicitly invokes skill)
  - Detailed structure analysis
  - Task breakdown by phase
  - Completion statistics
```

### Example 3: Integration with Other Skills
```
User: "/gh:issue work 42"
Claude:
  1. Uses issue-parser skill to extract tasks
  2. Passes structured data to issue-todowrite-sync skill
  3. Creates TodoWrite tasks
```

## Error Handling

- **Missing Issue**: Returns error if Issue doesn't exist
- **Empty Body**: Returns empty task list with warning
- **Invalid Markdown**: Skips malformed lines, continues parsing
- **Network Issues**: Retries fetch operation once

## Files

- `SKILL.md`: This documentation
- `scripts/parse_issue.py`: Python parser implementation

## Dependencies

- `gh` CLI (GitHub CLI)
- Python 3.6+
- Standard library only (json, re, sys)

## Testing

Test the skill with a real Issue:

```bash
# Fetch test data
echo '{"number": 1, "title": "Test", "body": "## Tasks\n- [ ] Task 1\n- [x] Task 2"}' | \
  python3 ~/.claude/skills/issue-parser/scripts/parse_issue.py

# Expected output: Structured JSON with 2 tasks
```

## Integration Points

This skill is designed to work with:
- **issue-todowrite-sync**: Provides parsed data for TodoWrite conversion
- **progress-tracker**: Supplies task statistics for progress monitoring
- **/gh:issue command**: Primary workflow integration point
