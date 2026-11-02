---
name: pursue
description: Works autonomously on one hard problem in a hypothesis, experiment, and verification loop; a managed Stop hook blocks stopping until the completion check passes or the budget runs out. Use when the user invokes /pursue (a /goal substitute).
disable-model-invocation: true
argument-hint: "<problem, optionally with its completion condition> [--budget N]"
---

# /pursue

**Done** when the completion check passes on a fresh run and you have reported the result. **Stop** early and report when the budget is spent or a stop condition below applies. Never stop to ask for approval between attempts.

The built-in `/goal` cannot run under the managed `allowManagedHooksOnly`. Instead, the managed Stop hook `pursue-stop-hook.sh` runs the registered check whenever you try to end your turn and blocks the stop (exit 2) while it fails, up to the budget. Its message is a fact about the check, not a suggestion.

## Usage

- `/pursue <problem>`: you derive the completion check yourself.
- `/pursue <problem>. 完了条件: <command or observable result>`: use the given check.
- `--budget N`: the Stop hook blocks at most N stops (default 5); after that it lets you stop with the goal unmet.

## Setup

Do this once and without questions, then state the contract in four lines (problem, completion check, scope, budget) and start immediately.

1. **Completion check**: use the user's condition when given. Otherwise derive a deterministic one from the repository: an existing test, a reproduction script, or a measurable command. When none exists, write the smallest failing test or repro first and show that it fails. Ask the user only when no machine-checkable condition can be stated, then stop.
2. **Scope**: the files the problem plausibly involves. Needing anything beyond that is a stop condition.
3. **Register**: from the project directory, run `~/.claude/bin/pursue-goal set --check '<check command>' --max-stops <N>` (add `--timeout <seconds>`, at most 540, for slow checks; default 300). The check must be a command the Bash pre-tool gate accepts; it runs at the git root. If registration fails, report the error and stop: do not continue without enforcement.
4. **Log**: create `pursue-log.md` in the session scratchpad directory. Read it before every new hypothesis.

## Loop

1. Write one hypothesis and the result that would refute it.
2. Run the smallest experiment that can decide it. Start commands that take minutes with `run_in_background` and use the wait for the next hypothesis.
3. Run the completion check.
4. Append to the log: hypothesis, change, command, result, verdict (confirmed, refuted, or inconclusive).
5. Undo your own changes from a refuted hypothesis before the next one, unless the next one builds on them.

Never repeat a refuted hypothesis. After two attempts that yield no new information, change the approach: re-read primary sources (code, official docs, real logs), widen what you observe, or question the assumption shared by the failed hypotheses. Read-only exploration may go to an `Explore` subagent.

## Stop conditions

- The completion check passes: run it once more from a clean state, plus the related existing tests to catch regressions.
- The budget is spent.
- The fix needs an out-of-scope change, a destructive operation, a dependency addition, or a settings, hook, or policy change.
- The next step needs information only the user has.

For the last two, run `~/.claude/bin/pursue-goal clear --reason '<reason>'` before reporting; the reason goes to the history. Never clear the goal only to escape a failing check. When the check passes, the Stop hook closes the goal itself.

## Never

- Commit, push, open a PR, or write to an external service.
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
6. The absolute path of `pursue-log.md`, and the goal outcome (`pursue-goal status` shows `none` once the hook closed it).
