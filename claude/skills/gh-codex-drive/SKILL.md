---
name: gh-codex-drive
description: Use when the user asks to drive a GitHub Issue with Codex as the implementer while Claude stays manager/reviewer（「Issue #N を進めて。実装はcodex、claudeは管理と確認・レビューに徹して」等）. Default mode delegates implementation to codex-companion and supervises; --status only reports progress. Do not use when Claude itself should implement (use gh-start).
argument-hint: "<issue-number> [--status]"
---

# /gh-codex-drive

Read [`references/workflow.md`](references/workflow.md) and `~/.agents/rules/git-workflow.md`.

## Roles

Codex implements. Claude (owner, this session) manages: scopes the Issue, launches and monitors the Codex task, verifies the result against the Issue's success criteria, and reviews the diff. Claude edits code only to fix small review findings the user approves; substantial rework goes back to Codex.

## Modes

- `/gh-codex-drive <issue>`: fetch the Issue, define success criteria, delegate implementation to Codex, then verify and review the delivered changes.
- `/gh-codex-drive <issue> --status`: report the current Codex task state and local evidence (diff, tests) only; no new delegation, no edits.

## Required behavior

1. Verify Issue number, repository, and worktree cleanliness for the Issue scope. Work happens on a feature branch (never `main`/`master`); if currently on `main`/`master`, create and switch to `issue-<N>` automatically without asking.
2. Fetch structured Issue data via `~/.claude/bin/gh-issue-fetch.sh`; translate it into concrete success criteria before delegating.
3. Launch Codex with `codex-companion.mjs task` directly via `Bash(run_in_background=true)` from the main session. Never wrap it in the `codex:codex-rescue` Agent — the completion notification must stay owned by this session.
4. On completion, run deterministic verification (tests, lint) and an owner review of the full diff against the success criteria. Report gaps honestly; re-delegate or fix per user direction.
5. Default mode never commits, pushes, merges, creates PRs, or writes to GitHub. Completion side effects are `/gh-finish`'s job.
6. Report: delegated scope, Codex task outcome, verification results, review findings, and the exact follow-up command for any side effect.
