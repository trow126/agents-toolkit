# gh-codex-drive workflow

## Default delegation mode

1. Reject empty or non-numeric Issue identifiers and unknown flags.
2. Confirm the intended Git repository. If already on a non-`main`/`master` feature branch, use it. If on `main`/`master`, create and switch to `issue-<N>` (or the existing branch for that Issue) automatically — do not ask for confirmation. Only stop if the current branch clearly belongs to a different Issue's in-progress work.
3. Fetch the Issue through the bundled structured helper. Fail on missing/closed Issue unless the user explicitly asked to continue closed work.
4. Write explicit success criteria from the Issue body. If the body is ambiguous in a way that changes design, data, or public API, pause before delegating.
5. Compose the Codex prompt per `codex:gpt-5-4-prompting`: scope, success criteria, files of interest, test command, and hard boundaries (no commit/push/PR, stay in Issue scope).
6. Launch `codex-companion.mjs task` from the installed codex plugin via `Bash(run_in_background=true)` in the main session, following the launch recipe below verbatim. Record the task id. Never wrap the launch in an Agent.
7. While the task runs, remain responsive; on the completion notification, read the task output and the actual diff — never trust the summary alone.
8. Verify: run the project's deterministic checks (tests, lint) and review the diff line-by-line against the success criteria and surrounding conventions.
9. Report delegated scope, outcome, verification evidence, review findings, and remaining risk. Side effects (commit/merge/close) require `/gh-finish` or another explicit request.

## Launch recipe

Use this form as-is. Do not discover options by trial runs.

1. Resolve the helper and stop if it is missing:
   `COMPANION=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs | sort -V | tail -1)`
2. Save the composed prompt to `<scratchpad>/codex-prompt-<N>.md`.
3. Launch from the main session with `Bash(run_in_background=true)`:
   `node "$COMPANION" task --write --prompt-file <scratchpad>/codex-prompt-<N>.md`
   - Add `--cwd <repo>` only when the shell cwd is not the repository root.
   - Add `--model` / `--effort` only on explicit user request. Do not add `--background`; the Bash tool owns backgrounding.
4. Inspect with `node "$COMPANION" status` (latest job) or `node "$COMPANION" status <task-id>` / `result <task-id>`.

`task`, `review`, and `adversarial-review` have no `--help` / `-h` handling: unknown flags and stray words become the prompt text and start a real Codex run (three accidental runs on 2026-09-03). Usage lives only in `node "$COMPANION" --help` with no subcommand, and the managed pre-bash hook blocks subcommand `--help`.

## Status mode

`--status` inspects the running or last-completed Codex task (task output, `git status`, `git diff --stat`, latest test evidence) and reports progress in a few sentences. It never launches tasks, edits files, or posts to GitHub.

## Review-fix boundary

Small, low-risk review fixes (typo, missing test assertion, lint) may be fixed by the owner after reporting them. Anything touching design, data handling, or public API is re-delegated to Codex or explicitly confirmed with the user first.

## Stop conditions

- Missing repository, Issue, helper script, codex plugin, or authentication.
- Detached HEAD, unresolved merge/rebase, or overlapping user changes in the Issue's scope (`main`/`master` alone is not a stop — auto-create the feature branch per step 2).
- Codex task failure or output that contradicts the Issue scope — report, do not silently retry more than once.
- Any request to infer commit, merge, push, PR, or close authority from the delegation itself.
