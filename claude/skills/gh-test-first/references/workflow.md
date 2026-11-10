# gh-test-first workflow

## Setup

1. Reject empty or non-numeric Issue identifiers and unknown flags.
2. Confirm the intended Git repository and no unresolved merge or rebase. On `main`/`master`, create and switch to `issue-<N>` (or the existing branch for that Issue). Stop only if the current branch clearly belongs to another Issue's work in progress.
3. Inspect `git status --short --branch`. Unrelated or overlapping dirty changes are never staged, reset, or rewritten.
4. Fetch the Issue with `~/.claude/bin/gh-issue-fetch.sh <N>`, again for each Issue of a `/gh-roadmap-run`. The helper exits non-zero on a missing or closed Issue and prints one JSON object with the whole Issue body (`body`, unchanged) and the parsed checkboxes (`tasks`); it does not include Issue comments. Save it outside the work tree, so that the diff stays clean; run both lines in one Bash call, because `d` does not carry over to the next call:

   ```bash
   d="$(git rev-parse --git-dir)/gh-test-first" && mkdir -p "$d" && ~/.claude/bin/gh-issue-fetch.sh <N> > "$d/issue-<N>.json"
   jq -r '.body' "$d/issue-<N>.json" > "$d/issue-<N>.txt"
   ```

   Read `issue-<N>.txt` in full with line numbers. It is the only Issue text this run uses: do not discard, truncate, or filter the helper output, and do not read the Issue with `gh issue view` or `gh api`. If the helper fails, stop. Fail on a missing or closed Issue unless the user asked to continue closed work.
5. Run the project's relevant test suite once on the untouched tree, before writing any test, and record the IDs of the passing and the failing tests (the base).
6. Read the project instructions, the code the Issue touches, and its existing tests. Use the project's test framework, layout, and naming; apply the relevant `implementation-quality` rules.

## Specification

- Turn the Issue into numbered success criteria. Each criterion cites the line of the saved body it comes from (`issue-<N>.txt:<line>`) and names its test(s) (`tests/...::test_name`), or is listed as a manual check with the command or observation that will close it.
- Map every requirement sentence of `issue-<N>.txt` to a criterion, or mark it "not a requirement, because ...". A criterion without a line citation is a stop (requirements traceability: https://pub.towardsai.net/keeping-specs-tests-and-code-in-sync-in-ai-development-cd3f79d11054).
- Name the interface the tests use (functions, CLI, files, columns) from the Issue. If the Issue does not fix an interface the tests need, choose the smallest one consistent with the code and state it; if the choice changes a public API, stop and ask.
- Edge cases the tests cover follow `~/.agents/rules/test-policy.md`: empty, single, boundary, invalid, NaN, and the round trip for persisted state.

## Time-series or quantitative repositories

Treat the repository as time-series or quantitative when the Issue or the code works with time-indexed data: prices, ticks, bars, signals, features, labels, rolling or expanding windows, resampling, backtests, forecasts, or walk-forward evaluation. When unsure, treat it as one.

For every function the Issue adds or changes whose output row `t` must depend only on input up to `t` (or `t + horizon` for labels with a forward window of `horizon` rows, so a perturbation after a cut may change only rows from `cut − horizon` on), write the three tests of [`causality-tests.md`](causality-tests.md): prefix invariance, future perturbation, and sensitivity. They are acceptance tests like the others: written before the implementation and frozen.

## Red

- Write tests and fixtures only. No implementation file changes in this phase (an empty module the import needs is the only exception, and it must stay empty).
- Run the new tests. Acceptable red: an assertion failure, or `ImportError`/`AttributeError` for the missing interface stated in the Specification step (named by the Issue, or the smallest one chosen and stated there). Not acceptable: a syntax error, a fixture that fails to build, or a failure unrelated to the criterion. Fix the test until the failure is the expected one.
- For a bug fix, the test must reproduce the bug against the current code.
- Run the project's formatter and lint autofix on the new test files, re-run them to confirm the same red, then record the command, the summary of failures, and `sha256sum <test files>`.

## Green

- Implement the smallest change that makes the tests pass and satisfies the criteria; keep the diff within the Issue's scope.
- Re-run the new tests often. Do not edit frozen tests. When a frozen test is wrong (it contradicts the Issue or checks an accident of the implementation), stop, explain, fix it, and show it failing against the pre-implementation code (`git stash` the implementation, run, `git stash pop`) before continuing.

## Gate

All of these must hold; any failure stops the run with the output shown:

1. The new tests pass.
2. Lint passes, and the project's relevant test suite (the same commands `gh-finish` will run) is compared with the base recorded in Setup: no test that passed at the base fails or is missing now, and no test that failed at the base was fixed or edited by this run. List each existing test whose state changed, by ID. A failure that already existed at the base does not block: report it as a follow-up and leave it unfixed. Do not add paths, patterns, or thresholds to an existing test's exclusion or allow list. When an existing test flags the new code or tests, the gate has failed: stop at that point without editing that test, report the test name and its failure output, and do not name `/gh-finish <N>` as the follow-up.
3. `sha256sum` of the frozen test files matches the record, or each change is listed with its reason and its re-shown red.
4. In a time-series or quantitative repository, the causality tests exist for every affected function and pass.
5. The diff contains only Issue-attributable changes.

## Report

- Success criteria with their line citations and tests, the sentences marked "not a requirement", and manual checks with their status.
- Red: command and failure summary. Green: command and pass summary. Frozen hashes, and any test change with its reason.
- Existing tests whose state changed against the base, by ID, and the failures that already existed at the base (follow-ups).
- Changed paths and remaining risk.
- The follow-up: `/gh-finish <N>` to verify and preview, then `/gh-finish <N> --apply` to commit, merge locally, and close.

## Stop conditions

- Missing repository, Issue, helper, or authentication.
- Ambiguity that changes design, data, or public API.
- New tests that cannot be made to fail for the expected reason.
- A success criterion that cannot cite a line of the saved Issue body.
- A failing gate that cannot be fixed within the Issue's scope.
- Any request to infer commit, push, PR, or close authority from this skill itself; the `/gh-finish` steps run only on a separate user request or when `/gh-roadmap-run` authorizes them.

At every stop, write a stop record: the blocker, the phase reached, what is done, what was verified and with which command, and the state left on disk. End it with an `AskUserQuestion` whose options are named for the condition, and resume only on the option the user selects. For an existing test that flags the new code or tests, the options are: the Issue requires changing that test, change the implementation instead, or end the run.
