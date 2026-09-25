---
name: implementation-quality
description: Loads only the relevant test, error-handling, diagnosis, hygiene, and language rules for a change. Use when implementing, fixing, refactoring, or reviewing code. Not for Python structure reports (python-refactor-analysis) or Git (git-operations).
---

# Implementation Quality

Use the smallest relevant rule set:

| Situation | Read before acting |
|---|---|
| Any code implementation, fix, refactor, or review | `~/.agents/rules/test-policy.md` |
| The task creates files, tests, scripts, or build artifacts | `~/.agents/rules/workspace-hygiene.md` |
| Diagnosing a failure or bug | `~/.agents/rules/failure-investigation.md` |
| Python is in scope | `~/.agents/rules/python-guidelines.md` |
| Markdown is edited | `~/.agents/rules/markdown-rules.md` |
| A recurring environment or CLI failure is directly relevant | `~/.agents/rules/learnings.md` |

Before editing, state the concrete success condition and inspect the surrounding implementation and tests. Keep the change scoped, implement the complete requested behavior, and fail loudly when required inputs or invariants are missing.

After editing, run the narrowest deterministic checks that prove the behavior, then the repository gates required by the affected surface. Report executed checks and any remaining unverified item.

This skill does not authorize commit, push, external writes, memory updates, or deletion of pre-existing artifacts.
