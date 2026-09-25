---
name: gh-codex-drive
description: Drives one GitHub Issue with Codex as implementer while Claude scopes, supervises, verifies, and reviews; --status reports only. Use when the user explicitly delegates the implementation to Codex（「実装はcodex」等）. Not for Claude's own work (gh-start).
argument-hint: "<issue-number> [--status]"
---

# /gh-codex-drive

Stop before delegating when the Issue, repository, or success criteria are unclear in a way that changes design, data, or public API. The run is complete when the post-delegation gate has passed (or has been reported as failed), the diff has been reviewed, and the report names the exact follow-up command.

Read [`references/workflow.md`](references/workflow.md) and `~/.agents/rules/git-workflow.md`.

## Roles

Codex implements. Claude (owner, this session) manages: scopes the Issue into a contract, launches and monitors the Codex run, verifies the result with the deterministic gate, and reviews the diff. Claude edits code only to fix small review findings the user approves; substantial rework goes back to Codex.

## Modes

- `/gh-codex-drive <issue>`: fetch the Issue, write the delegation contract, delegate implementation to Codex, then gate, review, and report.
- `/gh-codex-drive <issue> --status`: report the active delegation (contract, Codex progress, result, evidence) only; no new delegation, no edits.

## Required behavior

1. Verify Issue number, repository, and worktree cleanliness for the Issue scope. Work happens on a feature branch (never `main`/`master`); if currently on `main`/`master`, create and switch to `issue-<N>` automatically without asking.
2. Fetch structured Issue data via `~/.claude/bin/gh-issue-fetch.sh`; translate it into the contract (goal, acceptance criteria, scope paths, required checks, diff budget) before delegating.
3. Launch with `~/.claude/bin/codex-delegate <contract>` via `Bash(run_in_background=true)` from the main session, exactly as in `references/workflow.md`. Never wrap it in an Agent (the managed hook rejects Codex launches from subagents), never call `codex exec` for writes directly, and never use `codex-companion.mjs task`.
4. On completion, run the gate `~/.claude/bin/verify-delegation <contract>` (the live copy, never one inside the delegated tree), then review the diff with `/code-review`. Codex's own report is not evidence. Re-delegate at most once with the same contract; after a second failure or a `stopped` result, present the options and a recommendation to the user.
5. Default mode never commits, pushes, merges, creates PRs, or writes to GitHub. Completion side effects are `/gh-finish`'s job; it refuses to commit delegated work without passing evidence.
6. Report: delegated scope, Codex outcome, gate result and evidence path, review findings, and the exact follow-up command for any side effect.
