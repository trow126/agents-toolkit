---
name: task-management
description: Hierarchical task organization with local checkpoint notes. Activate for operations with >3 steps or multiple file/directory scope (>2 dirs OR >3 files).
---

# Task Management

## Hierarchy
Plan > Phase > Task > Todo (TaskCreate + local checkpoint notes)

## Session Lifecycle
- **Start**: inspect existing `.claude/checkpoints/` notes when relevant
- **During**: update TaskCreate and checkpoint notes every 30min or on task completion
- **End**: provide a session summary and delete temporary items

## Tool Selection
| Task Type | Primary Tool | Checkpoint |
|-----------|-------------|------------|
| Analysis | Sequential MCP | `.claude/checkpoints/analysis_results.md` |
| Implementation | MultiEdit | `.claude/checkpoints/code_changes.md` |
| Testing | Test runner | `.claude/checkpoints/test_results.md` |
