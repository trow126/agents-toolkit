---
name: gh-test-first
description: "Implements one GitHub Issue in this session test-first: acceptance tests (plus causality/leak tests in time-series or quant repos) are written and seen failing before the code; passing them gates /gh-finish. Use when the user invokes /gh-test-first."
disable-model-invocation: true
argument-hint: "<issue-number>"
---

# /gh-test-first

Claude implements the Issue itself; no Codex delegation. This is the successor of the deprecated `/gh-codex-drive`. In the 2026-10 A/B experiments (`docs/eval/sandwich-ab-results.md` and `sandwich-ab-d-results.md` in agents-toolkit), delegating the implementation saved no cost and took 3–6 times longer, while tests written before the implementation and a clear specification raised quality for every implementer; in-process review did not.

**Stop** when the Issue is ambiguous in a way that changes design, data, or public API, on unrelated dirty changes in the scope, or when the new tests cannot be shown failing for the expected reason. **Done** when the frozen tests and the project's checks pass and the report names `/gh-finish <N>` as the follow-up.

Read [`references/workflow.md`](references/workflow.md) and `~/.agents/rules/git-workflow.md`. In a time-series or quantitative repository, also read [`references/causality-tests.md`](references/causality-tests.md).

## Modes

- `/gh-test-first <issue>`: fetch the Issue, write the tests, show them failing, implement, and gate on the tests.

It never commits, pushes, merges, creates PRs, or writes to GitHub. Completion is `/gh-finish <N>` (preview) and `/gh-finish <N> --apply`, each a separate request unless `/gh-roadmap-run` authorizes it.

## Required behavior

1. Verify the Issue number, repository, and worktree. Work on a feature branch: on `main`/`master`, create and switch to `issue-<N>` (or that Issue's existing branch) without asking.
2. Fetch the Issue via `~/.claude/bin/gh-issue-fetch.sh`. Write the success criteria as a numbered list and map each to the test(s) that will check it. List criteria no test can check as manual checks.
3. Decide whether the repository is time-series or quantitative (see the workflow). If it is, add causality tests (prefix invariance, future perturbation, sensitivity) for every function the Issue adds or changes whose output is indexed by time.
4. Red: write only tests (and fixtures). Run them. Every new test must fail for the expected reason: an assertion, or the missing interface the Issue names. A collection error from a typo or a broken fixture is not red. A test that already passes means the criterion is already met or the test is too weak; report it or strengthen it.
5. Freeze: record the red output and `sha256sum` of each new or changed test file.
6. Green: implement the minimum that satisfies the Issue and the tests. Do not edit frozen tests to make them pass. If a test is wrong, stop implementing, say why, fix the test, and show the fixed test failing against the pre-implementation code before continuing (record the new hash).
7. Gate: the new tests, the project's relevant suite, and lint pass; the frozen hashes match or each change is listed with its reason. A failing gate stops the run; never skip, weaken, or delete a test to pass it.
8. Report: the criterion → test map, red and green results, the frozen hashes, changed paths, manual checks, remaining risk, and the exact follow-up `/gh-finish <N>`.
