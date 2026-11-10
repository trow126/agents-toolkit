---
name: gh-test-first
description: "Implements one GitHub Issue in this session test-first: acceptance tests (plus causality/leak tests in time-series or quant repos) are written and seen failing before the code; passing them gates /gh-finish. Use when the user invokes /gh-test-first."
disable-model-invocation: true
argument-hint: "<issue-number>"
---

# /gh-test-first

Claude implements the Issue itself; Codex never implements (owner decision 2026-10-11). In the 2026-10 A/B experiments (`docs/eval/sandwich-ab-results.md` and `sandwich-ab-d-results.md` in agents-toolkit), delegating the implementation saved no cost and took 3–6 times longer, while tests written before the implementation and a clear specification raised quality for every implementer; in-process review did not.

**Stop** when the Issue is ambiguous in a way that changes design, data, or public API, on unrelated dirty changes in the scope, or when the new tests cannot be shown failing for the expected reason. **Done** when the frozen tests pass, the project's suite shows no test that passed at the base failing or missing, lint passes, and the report names `/gh-finish <N>` as the follow-up. Every stop ends with the stop record and question of the workflow's Stop conditions.

Read [`references/workflow.md`](references/workflow.md) and `~/.agents/rules/git-workflow.md`. In a time-series or quantitative repository, also read [`references/causality-tests.md`](references/causality-tests.md).

## Modes

- `/gh-test-first <issue>`: fetch the Issue, write the tests, show them failing, implement, and gate on the tests.

It never commits, pushes, merges, creates PRs, or writes to GitHub. Completion is `/gh-finish <N>` (preview) and `/gh-finish <N> --apply`, each a separate request unless `/gh-roadmap-run` authorizes it.

## Required behavior

1. Verify the Issue number, repository, and worktree. Work on a feature branch: on `main`/`master`, create and switch to `issue-<N>` (or that Issue's existing branch) without asking.
2. Run `~/.claude/bin/gh-issue-fetch.sh <N>`, again for each Issue of a `/gh-roadmap-run`, and save its full output and its `body` as the workflow's Setup says. The saved body is the only Issue text this run uses: do not discard, truncate, or filter the output, and do not read the Issue with `gh issue view` or `gh api`. If the helper fails, stop. Before writing any test, run the project's relevant suite once on the untouched tree and record the passing and failing test IDs (the base). Write the success criteria as a numbered list, each citing its line in the saved body (`issue-<N>.txt:<line>`), and map each to the test(s) that will check it. List criteria no test can check as manual checks.
3. Decide whether the repository is time-series or quantitative (see the workflow). If it is, add causality tests (prefix invariance, future perturbation, sensitivity) for every function the Issue adds or changes whose output is indexed by time.
4. Red: write only tests (and fixtures). Run them. Every new test must fail for the expected reason: an assertion, or the missing interface stated in the Specification step (named by the Issue, or the smallest one chosen and stated there). A collection error from a typo or a broken fixture is not red. A test that already passes means the criterion is already met or the test is too weak; report it or strengthen it.
5. Freeze: after formatting the test files, record the red output and `sha256sum` of each new or changed test file.
6. Green: implement the minimum that satisfies the Issue and the tests. Do not edit frozen tests to make them pass. If a test is wrong, stop implementing, say why, fix the test, and show the fixed test failing against the pre-implementation code before continuing (record the new hash).
7. Gate: the new tests and lint pass, and in the project's relevant suite no test that passed at the base fails or is missing and no test that failed at the base was fixed or edited by this run (list each existing test whose state changed by ID; report failures that already existed at the base as follow-ups, they do not block); the frozen hashes match, or each change is listed with its reason and the changed test is shown failing again against the pre-implementation code. A failing gate stops the run; never skip, weaken, or delete a test to pass it, and that includes adding paths, patterns, or thresholds to an existing test's exclusion or allow list. When an existing test flags the new code or tests, the gate has failed: stop at that point without editing that test, report the test name and its failure output, and do not name `/gh-finish <N>` as the follow-up.
8. Report: the criterion → test map with its line citations, red and green results, the frozen hashes, changed paths, manual checks, remaining risk, and the exact follow-up `/gh-finish <N>`.
