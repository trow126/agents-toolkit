# gh-roadmap-drive workflow

## Reading the roadmap

1. Reject empty or non-numeric tracking-Issue identifiers and unknown flags.
2. Fetch the tracking Issue via `~/.claude/bin/gh-issue-fetch.sh`. It must contain a checklist of sub-Issue references (`- [ ] #N …`). If it does not, this is not a roadmap Issue — stop and say so.
3. Determine order from the checklist itself (top to bottom) plus any explicit dependency notes or graph in the body. Do not reorder for convenience.
4. Reconcile state before starting: a sub-Issue already closed on GitHub but unchecked in the list gets its box checked (one edit, counted as that Issue's checklist update); a checked but open sub-Issue is reported as an inconsistency, not silently fixed.

## Iteration detail

- One sub-Issue at a time. Never delegate two sub-Issues to Codex concurrently; the verify → apply → checklist sequence of one Issue completes before the next starts.
- Follow the `gh-codex-drive` skill for delegation, monitoring, verification, and review. Its stop conditions apply unchanged.
- Follow the `gh-finish` skill for the apply step. `--apply` authority for each sub-Issue completed in this run comes from the roadmap-drive invocation itself; everything `gh-finish` refuses (push, PR, branch deletion, unrelated changes) stays refused.
- Checklist update: edit the tracking Issue body with `gh issue edit <tracking> --body-file` after rewriting only the target checkbox; leave every other byte of the body unchanged.
- Real-runtime checks: when the sub-Issue's success criteria involve external data, network collection, or long-running computation, run the actual command (smoke run, backfill) and read its output before finishing. Background long runs with `Bash(run_in_background=true)` and keep driving or waiting on them; do not declare success from code review alone.
- If Codex delivers a defective result, prefer a fresh, narrowly scoped fix task over piling context onto the failed task. One re-delegation per defect; a second failure on the same defect stops the loop.

## Judgment gates

A sub-Issue is a gate if its title or body marks it as a user decision（例:【判断ゲート】, 「担当: <user>」, ask-mode 指定）. On reaching a gate:

1. Stop the loop before implementing anything for the gate or any later sub-Issue.
2. Summarize the decisions the gate needs, with the evidence produced by the completed sub-Issues.
3. Resume only when the user has made the decision; the resumed run treats the recorded decision as the gate's outcome.

## Status mode

`--status` fetches the tracking Issue, compares the checklist against GitHub Issue states, local branches, and the latest verification evidence, and reports progress plus the next actionable sub-Issue. It never launches tasks, edits files, or writes to GitHub.

## Reporting

- Per iteration: one short note — sub-Issue number, Codex outcome, verification evidence, apply result.
- On stop: completed sub-Issues with evidence, current checklist state, the stop reason, and the exact resume command. If anything was left unverified (e.g. a pending long-running backfill), name it and the check that would close it.
