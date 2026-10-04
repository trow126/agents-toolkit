# gh-test-first workflow

## Setup

1. Reject empty or non-numeric Issue identifiers and unknown flags.
2. Confirm the intended Git repository and no unresolved merge or rebase. On `main`/`master`, create and switch to `issue-<N>` (or the existing branch for that Issue). Stop only if the current branch clearly belongs to another Issue's work in progress.
3. Inspect `git status --short --branch`. Unrelated or overlapping dirty changes are never staged, reset, or rewritten.
4. Fetch the Issue through `~/.claude/bin/gh-issue-fetch.sh`. Fail on a missing or closed Issue unless the user asked to continue closed work.
5. Read the project instructions, the code the Issue touches, and its existing tests. Use the project's test framework, layout, and naming; apply the relevant `implementation-quality` rules.

## Specification

- Turn the Issue into numbered success criteria. Each criterion names its test(s) (`tests/...::test_name`) or is listed as a manual check with the command or observation that will close it.
- Name the interface the tests use (functions, CLI, files, columns) from the Issue. If the Issue does not fix an interface the tests need, choose the smallest one consistent with the code and state it; if the choice changes a public API, stop and ask.
- Edge cases the tests cover follow `~/.agents/rules/test-policy.md`: empty, single, boundary, invalid, NaN, and the round trip for persisted state.

## Time-series or quantitative repositories

Treat the repository as time-series or quantitative when the Issue or the code works with time-indexed data: prices, ticks, bars, signals, features, labels, rolling or expanding windows, resampling, backtests, forecasts, or walk-forward evaluation. When unsure, treat it as one.

For every function the Issue adds or changes whose output row `t` must depend only on input up to `t` (or `t − horizon` for labels with a forward window), write the three tests of [`causality-tests.md`](causality-tests.md): prefix invariance, future perturbation, and sensitivity. They are acceptance tests like the others: written before the implementation and frozen.

## Red

- Write tests and fixtures only. No implementation file changes in this phase (an empty module the import needs is the only exception, and it must stay empty).
- Run the new tests. Acceptable red: an assertion failure, or `ImportError`/`AttributeError` for an interface the Issue introduces. Not acceptable: a syntax error, a fixture that fails to build, or a failure unrelated to the criterion. Fix the test until the failure is the expected one.
- For a bug fix, the test must reproduce the bug against the current code.
- Record the command, the summary of failures, and `sha256sum <test files>`.

## Green

- Implement the smallest change that makes the tests pass and satisfies the criteria; keep the diff within the Issue's scope.
- Re-run the new tests often. Do not edit frozen tests. When a frozen test is wrong (it contradicts the Issue or checks an accident of the implementation), stop, explain, fix it, and show it failing against the pre-implementation code (`git stash` the implementation, run, `git stash pop`) before continuing.

## Gate

All of these must hold; any failure stops the run with the output shown:

1. The new tests pass.
2. The project's relevant test suite and lint pass (the same commands `gh-finish` will run).
3. `sha256sum` of the frozen test files matches the record, or each change is listed with its reason and its re-shown red.
4. In a time-series or quantitative repository, the causality tests exist for every affected function and pass.
5. The diff contains only Issue-attributable changes.

## Report

- Success criteria with their tests, and manual checks with their status.
- Red: command and failure summary. Green: command and pass summary. Frozen hashes, and any test change with its reason.
- Changed paths and remaining risk.
- The follow-up: `/gh-finish <N>` to verify and preview, then `/gh-finish <N> --apply` to commit, merge locally, and close.

## Stop conditions

- Missing repository, Issue, helper, or authentication.
- Ambiguity that changes design, data, or public API.
- New tests that cannot be made to fail for the expected reason.
- A failing gate that cannot be fixed within the Issue's scope.
- Any request to infer commit, push, PR, or close authority from this skill.
