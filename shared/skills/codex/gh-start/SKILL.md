---
name: gh-start
description: Use when the user asks Codex to start or continue implementation for a GitHub Issue. Default mode edits and tests locally only; use explicit, separate --commit or --sync follow-up modes for those side effects. Do not use for PR creation or review feedback.
argument-hint: "<issue-number> [--commit|--sync]"
---

# $gh-start

Read [`../../gh-start/references/workflow.md`](../../gh-start/references/workflow.md) and `~/.agents/rules/git-workflow.md`.

## Modes

- `$gh-start <issue>`: fetch the Issue, inspect the repo, implement the scoped work, and test locally.
- `$gh-start <issue> --commit`: commit already implemented and verified Issue-scoped changes only.
- `$gh-start <issue> --sync`: post exactly one Issue progress/status update from the current local evidence.

`--commit` and `--sync` are mutually exclusive and are follow-up modes: they do not start or continue implementation. Default mode never commits, pushes, creates a PR, comments on GitHub, or writes checkpoint files.

## Required behavior

1. Verify the Issue number, repository, current feature branch, worktree scope, and Issue state.
2. Use `~/.claude/bin/gh-issue-fetch.sh` to retrieve structured Issue data.
3. In default mode, state success criteria, inspect surrounding code/tests, implement with a single owner, and run deterministic verification.
4. Preserve unrelated changes. Stop on `main`/`master`, conflicting dirty changes, missing requirements, or failed tests that cannot be resolved in scope.
5. Use the current session, Issue, and `git diff` as progress state. Never read, create, migrate, or delete `.claude/checkpoints` or `.codex/checkpoints`.
6. Report local changes, tests, and the exact unperformed operations.

Delegation is permitted only for genuine context isolation or independent review; task length alone is not a reason. The owner integrates and verifies all results.
