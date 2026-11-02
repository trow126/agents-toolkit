---
name: pursue
description: Works autonomously on one hard problem in a hypothesis-experiment-verify loop tracked as GitHub sub-Issues; a Stop hook blocks stopping until the completion check passes or the budget runs out. Use when the user invokes /pursue (a /goal substitute).
disable-model-invocation: true
argument-hint: "<problem, optionally with its completion condition> [--budget N] [--issue N | --no-issue]"
---

# /pursue

**Done** when the completion check passes on a fresh run and you have reported the result. **Stop** early and report when the budget is spent or a stop condition below applies. Never stop to ask for approval between attempts.

The built-in `/goal` cannot run under the managed `allowManagedHooksOnly`. Instead, the managed Stop hook `pursue-stop-hook.sh` runs the registered check whenever you try to end your turn and blocks the stop (exit 2) while it fails, up to the budget. Its message is a fact about the check, not a suggestion.

## Usage

- `/pursue <problem>`: you derive the completion check yourself.
- `/pursue <problem>. 完了条件: <command or observable result>`: use the given check.
- `--budget N`: the Stop hook blocks at most N stops (default 5); after that it lets you stop with the goal unmet.
- `--issue N`: attach the run Issue as a sub-issue of the existing open Issue N. Without it, the run Issue stands alone.
- `--no-issue`: no GitHub writes; progress is only in `pursue-log.md`.

## Setup

Do this once and without questions, then state the contract in five lines (problem, completion check, scope, budget, run Issue URL) and start immediately.

1. **Completion check**: use the user's condition when given. Otherwise derive a deterministic one from the repository: an existing test, a reproduction script, or a measurable command. When none exists, write the smallest failing test or repro first and show that it fails. Ask the user only when no machine-checkable condition can be stated, then stop.
2. **Scope**: the files the problem plausibly involves. Needing anything beyond that is a stop condition.
3. **Run Issue** (skip with `--no-issue`): write the contract (problem, completion check, scope, budget, the absolute path of `pursue-log.md`) to a scratchpad file and run `~/.claude/bin/pursue-issue start --title '<project>: <problem in one line>' --body-file <file>` (add `--issue N` when given). Keep the printed `run` number. If it fails, report the error and stop; the user can rerun with `--no-issue`.
4. **Register**: from the project directory, run `~/.claude/bin/pursue-goal set --check '<check command>' --max-stops <N>` (add `--timeout <seconds>`, at most 540, for slow checks; default 300). The check must be a command the Bash pre-tool gate accepts; it runs at the git root. If registration fails, report the error and stop: do not continue without enforcement.
5. **Log**: create `pursue-log.md` in the session scratchpad directory. Read it before every new hypothesis.

## Loop

1. Write one hypothesis and the result that would refute it. Open its Issue: `~/.claude/bin/pursue-issue hypothesis --run <run> --title '<hypothesis in one line>' --body-file <file>` with the hypothesis, the refuting result, and the planned experiment.
2. Run the smallest experiment that can decide it. Start commands that take minutes with `run_in_background` and use the wait for the next hypothesis.
3. Run the completion check.
4. Append to the log: hypothesis, change, command, result, verdict (confirmed, refuted, or inconclusive). Close its Issue with the same entry: `~/.claude/bin/pursue-issue verdict --issue <H issue> --verdict <verdict> --body-file <file>`.
5. Undo your own changes from a refuted hypothesis before the next one, unless the next one builds on them.

Never repeat a refuted hypothesis. After two attempts that yield no new information, change the approach: re-read primary sources (code, official docs, real logs), widen what you observe, or question the assumption shared by the failed hypotheses. Read-only exploration may go to an `Explore` subagent.

Issue updates are progress reporting, not enforcement. If a `pursue-issue` command fails mid-run, write the failure and the unsent entry to the log, keep going, and list it in the report; never drop it silently. Post no Issue comments: the sub-issue list and each Issue's body are the record.

## Stop conditions

- The completion check passes: run it once more from a clean state, plus the related existing tests to catch regressions.
- The budget is spent.
- The fix needs an out-of-scope change, a destructive operation, a dependency addition, or a settings, hook, or policy change.
- The next step needs information only the user has.

For the last two, run `~/.claude/bin/pursue-goal clear --reason '<reason>'` before reporting; the reason goes to the history. Never clear the goal only to escape a failing check. When the check passes, the Stop hook closes the goal itself.

Before the report, give every open hypothesis Issue a verdict, then run `~/.claude/bin/pursue-issue finish --issue <run> --outcome done|not-done|abandoned --body-file <file>` with the report. `done` closes the run Issue. Use `abandoned` (closed as not planned) when the check can no longer pass, for example a consumed one-shot holdout, or when the user says the problem will not be resumed; say why in the report. `not-done` leaves it open for a later attempt; such a run can be finished again as `done` or `abandoned` once the user decides.

## Never

- Commit, push, open a PR, or write to an external service other than the run and hypothesis Issues through `pursue-issue`.
- Put secrets, credentials, personal data, or raw private data in an Issue body; summarize results instead. Issues are as visible as the repository.
- Edit, close, or comment on the run and hypothesis Issues by hand.
- Weaken, skip, or rewrite the completion check or existing tests to make them pass, or `set --replace` a weaker check.
- Edit or delete the goal state under `~/.local/state/agents-toolkit/pursue/` by hand.
- Hide a failure behind a silent fallback.
- Fix unrelated bugs; list them as follow-ups.
- Send the problem to another model (`/cross-critic`, Codex); suggest it in the report instead.

## Report

1. Outcome: done or not done, with the final check command and its output.
2. Diff summary of the changes left in the working tree.
3. Hypotheses tried, each with its verdict and evidence.
4. What remains unverified and how to verify it.
5. Follow-ups found outside the scope.
6. The run Issue URL (or `--no-issue`), the absolute path of `pursue-log.md`, and the goal outcome (`pursue-goal status` shows `none` once the hook closed it).
