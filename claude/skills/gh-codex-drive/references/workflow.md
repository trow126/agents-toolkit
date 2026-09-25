# gh-codex-drive workflow

## Default delegation mode

1. Reject empty or non-numeric Issue identifiers and unknown flags.
2. Confirm the intended Git repository. If already on a non-`main`/`master` feature branch, use it. If on `main`/`master`, create and switch to `issue-<N>` (or the existing branch for that Issue) automatically — do not ask for confirmation. Only stop if the current branch clearly belongs to a different Issue's in-progress work.
3. Fetch the Issue through the bundled structured helper. Fail on missing/closed Issue unless the user explicitly asked to continue closed work.
4. Write the contract (below) from the Issue body. If the body is ambiguous in a way that changes design, data, or public API, pause before delegating.
5. Check it: `~/.claude/bin/codex-delegate-preflight <contract>`. Fix the contract, never the check.
6. Launch from the main session with `Bash(run_in_background=true)`: `~/.claude/bin/codex-delegate <contract>`. Record the background task id. Never wrap the launch in an Agent. The session must outlive the turn (interactive or `claude --bg`); in `claude -p` the session ends with the turn, the background run is killed, and the next launch reports a stale delegation.
7. While Codex runs, remain responsive; `--status` reads the state files below. On the completion notification, read the Codex report (`result-<N>.json`) and the actual diff — never trust the summary alone.
8. Gate: `~/.claude/bin/verify-delegation <contract>`. It re-runs the required checks and writes `evidence-<N>.json`; a failure is reported with its violations.
9. Review the diff with `/code-review`. Small, low-risk fixes follow the review-fix boundary; after any edit, run the gate again so the evidence matches the tree.
10. Report delegated scope, outcome, gate result, evidence path, review findings, and remaining risk. Side effects (commit/merge/close) require `/gh-finish` or another explicit request.

## Contract

Write `$(git rev-parse --git-dir)/agents-toolkit/contract-<N>.json` (the Codex sandbox cannot write there). Schema: [`contract.schema.json`](contract.schema.json); prompt rendering: [`contract.md`](contract.md).

- `id`: the Issue number; `goal`; `acceptance_criteria` from the Issue, including ones no command can check
- `scope_paths`: gitignore-style globs Codex may change; `required_checks`: commands the gate re-runs
- `diff_budget`: `{files, lines}` (added+deleted, new untracked files included)
- `allowed_dependency_changes`, `non_goals`, `invariants`, `protected_paths_extra`: arrays, empty when none
- `route`: `{model, effort}` from [`codex-route.env`](codex-route.env) (`CODEX_MODEL`, `CODEX_EFFORT`). Use a different route only when the user explicitly asks for it in this run, and report the route used.

`codex-delegate` records `baseline` (HEAD, a snapshot of the working tree as a git tree, status, untracked hashes) and `route.cli_version`, renders the prompt, writes `active.json`, and runs `codex exec -p toolkit-implementer -s workspace-write --output-schema report.schema.json`. The profile `toolkit-implementer` disables subagents, bundled and GitHub-workflow skills, and memories.

## Status mode

`--status` reads `$(git rev-parse --git-dir)/agents-toolkit/`: `active.json`, the contract, `exec-<N>.jsonl` progress, `result-<N>.json`, and `evidence-<N>.json`, plus `git status` and `git diff --stat`. It never launches, edits, or posts.

## Outcomes

- Gate passes: review, report, and hand off to `/gh-finish`.
- Gate fails or Codex returns `stopped` (`out_of_scope_path`, `dependency_change`, `public_api_change`, `diff_budget_exceeded`): re-delegate once with the same contract when the failure is fixable within it; otherwise, and after a second failure, present the options and a recommendation. Changing the contract (scope, budget, dependencies) is the user's decision.
- The user abandons the delegation: `~/.claude/bin/delegation-evidence-check --clear` after reporting the state.

## Review-fix boundary

Small, low-risk review fixes (typo, missing test assertion, lint) may be fixed by the owner after reporting them, followed by a new gate run. Anything touching design, data handling, or public API is re-delegated to Codex or explicitly confirmed with the user first.

## Stop conditions

- Missing repository, Issue, helper, Codex CLI, profile, or authentication; a failing preflight.
- Detached HEAD, unresolved merge/rebase, or overlapping user changes in the Issue's scope (`main`/`master` alone is not a stop — auto-create the feature branch per step 2).
- Another delegation is already active in this repository.
- Any request to infer commit, merge, push, PR, or close authority from the delegation itself.
