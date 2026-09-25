# gh-codex-drive workflow

## Default delegation mode

1. Reject empty or non-numeric Issue identifiers and unknown flags.
2. Confirm the intended Git repository. If already on a non-`main`/`master` feature branch, use it. If on `main`/`master`, create and switch to `issue-<N>` (or the existing branch for that Issue) automatically — do not ask for confirmation. Only stop if the current branch clearly belongs to a different Issue's in-progress work.
3. Fetch the Issue through the bundled structured helper. Fail on missing/closed Issue unless the user explicitly asked to continue closed work.
4. Write explicit success criteria from the Issue body. If the body is ambiguous in a way that changes design, data, or public API, pause before delegating.
5. Compose the Codex prompt: goal, the success criteria from step 4, files of interest, and the test command, followed by these constraints verbatim:
   - Do not refactor, abstract speculatively, or reformat anything the request does not require.
   - Do not commit, push, open or update a PR or draft PR, update an Issue, or write to any external service.
   - Do not spawn subagents and do not call other providers.
   - Proceed on in-scope decisions with reasonable assumptions, and report every assumption you made.
   - When a check fails, fix it within scope and rerun it.
6. Launch `codex-companion.mjs task` from the installed codex plugin via `Bash(run_in_background=true)` in the main session, following the launch recipe below verbatim. Record the task id. Never wrap the launch in an Agent.
7. While the task runs, remain responsive; on the completion notification, read the task output and the actual diff — never trust the summary alone.
8. Verify: run the project's deterministic checks (tests, lint) and review the diff line-by-line against the success criteria and surrounding conventions.
9. Report delegated scope, outcome, verification evidence, review findings, and remaining risk. Side effects (commit/merge/close) require `/gh-finish` or another explicit request.

## Launch recipe

Use this form as-is. Do not discover options by trial runs.

1. Save the composed prompt to `<scratchpad>/codex-prompt-<N>.md`.
2. Launch from the main session with `Bash(run_in_background=true)`. One command resolves the helper, loads the route from [`codex-route.env`](codex-route.env), and starts the task; it stops if the helper or a route value is missing:
   `COMPANION=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs | sort -V | tail -1) && . ~/.claude/skills/gh-codex-drive/references/codex-route.env && [ -n "$COMPANION" ] && [ -n "$CODEX_MODEL" ] && [ -n "$CODEX_EFFORT" ] && node "$COMPANION" task --write --model "$CODEX_MODEL" --effort "$CODEX_EFFORT" --prompt-file <scratchpad>/codex-prompt-<N>.md`
   - Always pass `--model` and `--effort` from `codex-route.env`. Use a different route only when the user explicitly asks for it in this run, and report the route used.
   - Add `--cwd <repo>` only when the shell cwd is not the repository root. Do not add `--background`; the Bash tool owns backgrounding.
   - Never pass `--resume-last` or `--resume`. Every delegation, including the single allowed re-delegation, is a fresh task.
3. Record the task id. Inspect with `node "$COMPANION" status <task-id>` / `result <task-id>`. `status` without an id can list jobs from other sessions, so always use the recorded id.

`task`, `review`, and `adversarial-review` have no `--help` / `-h` handling: unknown flags and stray words become the prompt text and start a real Codex run (three accidental runs on 2026-09-03). Usage lives only in `node "$COMPANION" --help` with no subcommand, and the managed pre-bash hook blocks subcommand `--help`.

## Status mode

`--status` inspects the running or last-completed Codex task (task output, `git status`, `git diff --stat`, latest test evidence) and reports progress in a few sentences. It never launches tasks, edits files, or posts to GitHub.

## Review-fix boundary

Small, low-risk review fixes (typo, missing test assertion, lint) may be fixed by the owner after reporting them. Anything touching design, data handling, or public API is re-delegated to Codex or explicitly confirmed with the user first.

## Stop conditions

- Missing repository, Issue, helper script, codex plugin, or authentication.
- Detached HEAD, unresolved merge/rebase, or overlapping user changes in the Issue's scope (`main`/`master` alone is not a stop — auto-create the feature branch per step 2).
- Codex task failure or output that contradicts the Issue scope — re-delegate at most once with the same criteria; if that also fails, present the options and a recommendation to the user.
- Any request to infer commit, merge, push, PR, or close authority from the delegation itself.
