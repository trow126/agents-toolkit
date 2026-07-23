---
name: issue-work-logger
description: "Automatically log work progress for GitHub Issues to claudedocs/work/. Activates on /gh:issue work, TodoWrite state changes, and session start/end."
allowed-tools:
  - Write
  - Read
  - Bash
---

# issue-work-logger - Issue Work Progress Logger

## Purpose

Automatically record work progress, experiments, decisions, and notes when working on GitHub Issues.

## Activation

**Automatic Triggers**:
- `/gh:issue work <number>` command execution
- TodoWrite task state changes (pending → in_progress → completed)
- Session start/end detection

## Behavior

### 1. File Creation (on `/gh:issue work N`)

Automatically creates work files in `claudedocs/work/`:

```
claudedocs/work/
├── issue_N_context.md      # Issue overview (from GitHub)
├── issue_N_experiments.md  # Experimental results
├── issue_N_decisions.md    # Design decisions
└── issue_N_notes.md        # Work notes and logs
```

### 2. Automatic Logging

**Task State Changes**:
```markdown
## [2025-10-31 14:00] Task 1.1 started
(Auto-logged when TodoWrite task becomes in_progress)

## [2025-10-31 15:00] Task 1.1 completed
(Auto-logged when TodoWrite task becomes completed)
```

**Session Events**:
```markdown
## [2025-10-31 13:00] Session 1 started
**Starting task**: (from TodoWrite)

## [2025-10-31 16:00] Session 1 ended
(Auto-logged on session end detection)
```

### 3. File Structure

#### context.md (Auto-generated from GitHub Issue)
```markdown
# Issue #N: [Title]

**Created**: [date]
**State**: In Progress

## Tasks
- [ ] Task 1.1: ...
- [ ] Task 1.2: ...

## Current Progress
- Last updated: [timestamp]
- Completed: 0/3
- In progress: Task 1.1

## Links
- GitHub Issue: [URL]
```

#### experiments.md (Manual + Summary)
```markdown
# Issue #N: Experimental Results

## [timestamp] Task X.Y - Experiment name

**Purpose**: ...
**Method**: ...
**Results**: ...
**Data**: ...
```

#### decisions.md (Manual + Summary)
```markdown
# Issue #N: Design Decisions

## [timestamp] Task X.Y - Decision point

**Situation**: ...
**Options**:
- A) ...
- B) ...

**Decision**: Option B

**Rationale**: ...
**Trade-offs**: ...
```

#### notes.md (Auto + Manual + Summary)
```markdown
# Issue #N: Work Notes

## [timestamp] Session N started
**Starting task**: ...

## [timestamp] Task X.Y started
(Auto-logged)

## [timestamp] Task X.Y completed
(Auto-logged)

## [timestamp] Error occurred
**Problem**: ...
**Solution**: ...

## [timestamp] Session N ended
**Completed**: ...
**Next**: ...
```

## Integration Points

### With TodoWrite
- Monitors TodoWrite state changes
- Extracts current task information
- Logs task start/completion automatically

### With GitHub Issues
- Fetches Issue content for context.md
- Updates Issue comments with progress (via progress-tracker)

### With Session Management
- Detects session start (first TodoWrite interaction)
- Detects session end (explicit or timeout)

## Workflow

### Session Start
```
User: /gh:issue work 42
  ↓
1. Check if work/ files exist
2. If not, create from templates
3. Fetch GitHub Issue #42
4. Generate context.md
5. Log "Session started" in notes.md
6. Display: "Work files ready: claudedocs/work/issue_42_*.md"
```

### During Work
```
TodoWrite: Task 1.1 → in_progress
  ↓
1. Log "[timestamp] Task 1.1 started" in notes.md
2. Update context.md progress

TodoWrite: Task 1.1 → completed
  ↓
1. Log "[timestamp] Task 1.1 completed" in notes.md
2. Update context.md progress
```

### Session End
```
(Session end detected)
  ↓
1. Log "[timestamp] Session ended" in notes.md
2. Trigger summary prompt (see Phase 2)
```

## File Templates

Templates are stored in `skills/issue-work-logger/templates/`:
- `context_template.md`
- `experiments_template.md`
- `decisions_template.md`
- `notes_template.md`

## Configuration

```yaml
work_directory: claudedocs/work/
auto_create_files: true
log_task_changes: true
log_session_events: true
timestamp_format: "YYYY-MM-DD HH:mm"
```

## Limitations

- **Does not** log conversation content automatically
- **Does not** extract design decisions automatically
- **Does not** save experimental data automatically

These require:
- Manual recording during session
- Session-end summary (Phase 2 feature)
- Explicit save commands (future enhancement)

## Notes

- Work files are temporary (Issue lifetime)
- Files should be cleaned up after Issue completion
- Session-end summary helps capture important details
- Integration with `/gh:issue close` for automatic archival (Phase 3)

## Examples

### Example 1: Starting Work

```bash
$ /gh:issue work 42

> Creating work files for Issue #42...
> ✓ claudedocs/work/issue_42_context.md
> ✓ claudedocs/work/issue_42_experiments.md
> ✓ claudedocs/work/issue_42_decisions.md
> ✓ claudedocs/work/issue_42_notes.md
>
> Session started: 2025-10-31 13:00
> Ready to work on Task 1.1
```

### Example 2: Task Completion

```bash
(TodoWrite: Task 1.1 completed)

> Logged to issue_42_notes.md:
> [2025-10-31 15:00] Task 1.1 completed
```

### Example 3: Resuming Work

```bash
$ /gh:issue work 42

> Resuming work on Issue #42
> Last session: 2025-10-30 16:00
> Progress: Task 1.1 completed (1/3)
> Next: Task 1.2
>
> Work files: claudedocs/work/issue_42_*.md
```

## Future Enhancements

- **Phase 2**: Session-end summary with AI-generated content
- **Phase 3**: Automatic knowledge extraction on Issue close
- **Phase 4**: Integration with `/gh:issue:log` commands for explicit logging
