# gh-roadmap-run workflow

## Reading the roadmap

1. Reject empty or non-numeric tracking-Issue identifiers, unknown flags, and `--status` combined with `--critic`.
2. Fetch the tracking Issue via `~/.claude/bin/gh-issue-fetch.sh`. It must contain a checklist of sub-Issue references (`- [ ] #N …`). If it does not, this is not a roadmap Issue — stop and say so.
3. Determine order from the checklist itself (top to bottom) plus any explicit dependency notes or graph in the body. Do not reorder for convenience.
4. Reconcile state before starting: a sub-Issue already closed on GitHub but unchecked in the list gets its box checked (one edit, counted as that Issue's checklist update); a checked but open sub-Issue is reported as an inconsistency, not silently fixed.

## Iteration detail

- One sub-Issue at a time. The test-first → gate → verify → apply → checklist sequence of one Issue completes before the next starts.
- Follow the `gh-test-first` skill for the implementation. Its red phase (new tests failing for the expected reason), frozen tests, and gate are required for every sub-Issue; a sub-Issue with no testable criterion (documentation only, configuration) records its manual checks instead and says so in the progress note.
- Follow `~/.agents/rules/git-workflow.md` and the `gh-finish` skill for the apply step. `--apply` authority for each sub-Issue completed in this run comes from the roadmap-run invocation itself; everything `gh-finish` refuses (push, PR, branch deletion, unrelated changes) stays refused.
- Checklist update: edit the tracking Issue body with `gh issue edit <tracking> --body-file` after rewriting only the target checkbox; leave every other byte of the body unchanged.
- Real-runtime checks: when the sub-Issue's success criteria involve external data, network collection, or long-running computation, run the actual command (smoke run, backfill) and read its output before finishing. Background long runs with `Bash(run_in_background=true)` and keep driving or waiting on them; do not declare success from code reading alone.
- Review: the evidence behind this skill showed no quality gain from a routine in-process review, so the tests are the gate. Use `/code-review` only for changes to architecture, data destruction, or public API, and treat its findings as input, not as approval.

## Judgment gates

A sub-Issue is a gate if its title or body marks it as a user decision（例:【判断ゲート】, 「担当: <user>」, ask-mode 指定）. On reaching a gate:

1. Stop the loop before implementing anything for the gate or any later sub-Issue.
2. Summarize the decisions the gate needs, with the evidence produced by the completed sub-Issues.
3. With `--critic`: write the gate's decision material (the gate Issue body, the plan or preregistration it decides on, and the evidence summary) to one file in your scratchpad, run the `cross-critic` skill with `--gate` on it, and present its decision table together with the decisions. The critics criticize; the user decides.
4. Resume only when the user has made the decision; the resumed run treats the recorded decision as the gate's outcome.

## Status mode

`--status` fetches the tracking Issue, compares the checklist against GitHub Issue states, local branches, and the latest test evidence in the session, and reports progress plus the next actionable sub-Issue. It never implements, edits files, runs critics, or writes to GitHub.

## Reporting

- Per iteration: one short note — sub-Issue number, red and green test results, verification evidence, apply result.
- On stop: completed sub-Issues with evidence, current checklist state, the stop reason, and the exact resume command. If anything was left unverified (e.g. a pending long-running backfill), name it and the check that would close it.
