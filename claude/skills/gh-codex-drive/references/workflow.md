# gh-codex-drive workflow

## Default delegation mode

1. Reject empty or non-numeric Issue identifiers and unknown flags.
2. Confirm the intended Git repository. If already on a non-`main`/`master` feature branch, use it. If on `main`/`master`, create and switch to `issue-<N>` (or the existing branch for that Issue) automatically — do not ask for confirmation. Only stop if the current branch clearly belongs to a different Issue's in-progress work.
3. Fetch the Issue through the bundled structured helper. Fail on missing/closed Issue unless the user explicitly asked to continue closed work.
4. Write explicit success criteria from the Issue body. If the body is ambiguous in a way that changes design, data, or public API, pause before delegating.
5. Compose the Codex prompt per `codex:gpt-5-4-prompting`: scope, success criteria, files of interest, test command, and hard boundaries (no commit/push/PR, stay in Issue scope).
6. Launch `codex-companion.mjs task` from the installed codex plugin via `Bash(run_in_background=true)` in the main session. Record the task id. Never wrap the launch in an Agent.
7. While the task runs, remain responsive; on the completion notification, read the task output and the actual diff — never trust the summary alone.
8. Verify: run the project's deterministic checks (tests, lint) and review the diff line-by-line against the success criteria and surrounding conventions.
9. Report delegated scope, outcome, verification evidence, review findings, and remaining risk. Side effects (commit/merge/close) require `/gh-finish` or another explicit request.

## Status mode

`--status` inspects the running or last-completed Codex task (task output, `git status`, `git diff --stat`, latest test evidence) and reports progress in a few sentences. It never launches tasks, edits files, or posts to GitHub.

## Review-fix boundary

Small, low-risk review fixes (typo, missing test assertion, lint) may be fixed by the owner after reporting them. Anything touching design, data handling, or public API is re-delegated to Codex or explicitly confirmed with the user first.

## Stop conditions

- Missing repository, Issue, helper script, codex plugin, or authentication.
- Detached HEAD, unresolved merge/rebase, or overlapping user changes in the Issue's scope (`main`/`master` alone is not a stop — auto-create the feature branch per step 2).
- Codex task failure or output that contradicts the Issue scope — report, do not silently retry more than once.
- Any request to infer commit, merge, push, PR, or close authority from the delegation itself.
