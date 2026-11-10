# gh-roadmap-run workflow

## Reading the roadmap

1. Before any `gh` call, reject: an empty or non-numeric tracking-Issue identifier, more than one positional argument, an unknown flag, and `--status` combined with `--critic`. Report the usage line and stop.
2. Fetch the tracking Issue via `~/.claude/bin/gh-issue-fetch.sh`. It must contain a checklist of sub-Issue references (`- [ ] #N …`). If it does not, this is not a roadmap Issue — stop and say so.
3. Determine order from the checklist itself (top to bottom) plus any explicit dependency notes or graph in the body. Do not reorder for convenience.
4. Reconcile state once per invocation, before the first Loop iteration: a sub-Issue already closed on GitHub but unchecked in the list gets its box checked (one edit, counted as that Issue's checklist update); a checked but open sub-Issue is reported as an inconsistency, not silently fixed. In `--status`, do not edit; report each closed-but-unchecked sub-Issue as pending reconciliation.

## Iteration detail

- One sub-Issue at a time. The test-first → gate → verify → apply → checklist sequence of one Issue completes before the next starts.
- Follow the `gh-test-first` skill for the implementation: read `~/.claude/skills/gh-test-first/SKILL.md` and the references it names (the Skill tool refuses it). Its contract applies to every sub-Issue unchanged. A sub-Issue whose body gives neither a testable criterion nor manual verification steps is a stop: report it as not testable.
- Follow `~/.agents/rules/git-workflow.md` and the `gh-finish` skill for the apply step. `--apply` authority for each sub-Issue completed in this run comes from the roadmap-run invocation itself; everything `gh-finish` refuses (push, PR, branch deletion, unrelated changes) stays refused.
- Checklist update: read the `body` string from `gh api repos/{owner}/{repo}/issues/<tracking>` JSON (not `gh issue view`, which adds a trailing newline), change that one `[ ]` to `[x]` at its character offset, and write the result with `gh issue edit <tracking> --body-file` with no added newline and the original line endings (CRLF stays CRLF). Re-fetch the body and compare it byte for byte with the expected string; a mismatch is a stop.
- Real-runtime checks: when the sub-Issue's success criteria involve external data, network collection, or long-running computation, run the actual command (smoke run, backfill) and read its output before finishing. Background long runs with `Bash(run_in_background=true)` and keep driving or waiting on them; do not declare success from code reading alone.
- Review: the tests are the gate. In the 2026-10 sandwich A/B (`docs/eval/sandwich-ab-results.md`, line 63), blind reviewers reading only the diff gave a leak score to none of the 8 candidates whose hidden tests failed. It did not measure runs with and without a review gate. Use `/code-review` only for changes to architecture, data destruction, or public API, and treat its findings as input, not as approval.

## Judgment gates

A sub-Issue is a gate if its title or body marks it as a user decision（例:【判断ゲート】, 「担当: <user>」, ask-mode 指定）. On reaching a gate:

1. Implement nothing for the gate or any later sub-Issue until the gate is decided.
2. Summarize the decisions the gate needs, with the evidence produced by the completed sub-Issues.
3. With `--critic`: re-read `~/.claude/skills/cross-critic/SKILL.md` and its references, write the gate's decision material (the gate Issue body, the plan or preregistration it decides on, and the evidence summary) to one file in your scratchpad, run the `cross-critic` skill with `--gate` on it by following `~/.claude/skills/cross-critic/SKILL.md` and its references (the Skill tool refuses it), and present its decision table together with the decisions. The critics criticize; the user decides.
4. Ask the user for the decision with `AskUserQuestion`, using the gate body's own option names. A gate whose body already has a `## 決定` section is decided: do not ask again; go to step 6.
5. When the user decides, append this section to the end of the gate Issue's body. Write the chosen option with the name the gate body gives it and the user's reason in their own words; never record a decision the user did not make, and never rewrite the rest of the body.

   ```markdown
   ## 決定

   - 決定: <the chosen option>
   - 決定者: ユーザー
   - 日付: <YYYY-MM-DD>
   - 理由: <the user's words, or 記載なし>
   ```

   Use the checklist-update procedure of "Iteration detail" on the gate Issue: read `body` from `gh api`, append the section, write it with `gh issue edit <gate> --body-file`, re-fetch, and compare byte for byte; a mismatch is a stop. The decision lives in the body, not in a comment, because `gh-issue-fetch.sh` returns the body and no comments.
6. Close the gate with `gh issue close <gate> --reason completed` (no comment), check its box in the tracking Issue, and continue the loop.
7. When the user does not decide (no answer, a request for more evidence, or a deferral), write nothing to the gate, stop the loop, and report what the decision still needs.

A sub-Issue whose 前提 names a gate outcome has its dependency met only when that gate's body, fetched with `~/.claude/bin/gh-issue-fetch.sh <gate>`, has a `## 決定` section showing that outcome. A decision found only in a comment does not count: ask the user as in step 4.

## Status mode

`--status` reports each gate as decided (its body has `## 決定`) or pending, and writes nothing to it. It fetches the tracking Issue with `~/.claude/bin/gh-issue-fetch.sh <tracking>` (`gh issue view` is not used for it), compares the checklist against GitHub Issue states, local branches, and the latest test evidence in the session, and reports progress plus the next actionable sub-Issue. It never implements, edits files, runs critics, or writes to GitHub.

## Reporting

- Per iteration: one short note — sub-Issue number, red and green test results, verification evidence, apply result.
- On stop: completed sub-Issues with evidence, current checklist state, the stop reason, and the exact resume command. If anything was left unverified (e.g. a pending long-running backfill), name it and the check that would close it.
