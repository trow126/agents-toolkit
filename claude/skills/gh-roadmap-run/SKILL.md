---
name: gh-roadmap-run
description: Loops a tracking Issue's sub-Issues through /gh-test-first, verification, and /gh-finish --apply, updating its checklist until a gate, unmet dependency, or failure; --critic adds cross-critic at gates. Use when the user invokes /gh-roadmap-run.
disable-model-invocation: true
argument-hint: "<tracking-issue-number> [--status|--critic]"
---

# /gh-roadmap-run

Claude implements each sub-Issue test-first; Codex never implements (2026-10 A/B experiments, `docs/eval/sandwich-ab-results.md` and `sandwich-ab-d-results.md` in agents-toolkit).

Read [`references/workflow.md`](references/workflow.md). The per-step contracts are owned by the `gh-test-first`, `gh-finish`, and `cross-critic` skills. Load `gh-finish` via the Skill tool. `gh-test-first` and `cross-critic` set `disable-model-invocation: true`, so the Skill tool refuses them; read their files instead at the step that uses them: `~/.claude/skills/gh-test-first/SKILL.md` and `~/.claude/skills/cross-critic/SKILL.md`, plus the references each one names. This skill only adds the loop over a tracking Issue; it never relaxes those skills' rules.

## Modes

- `/gh-roadmap-run <tracking-issue>`: iterate the unchecked sub-Issues in roadmap order, as far as possible（「出来るところまで」）.
- `/gh-roadmap-run <tracking-issue> --critic`: the same loop; at each judgment gate, also run `cross-critic` in its gate mode on the gate's decision material before presenting it.
- `/gh-roadmap-run <tracking-issue> --status`: report checklist state against GitHub and local evidence only; no implementation, no edits, no writes.

## Authority

Invoking the loop is the user's single explicit request to follow `~/.claude/skills/gh-test-first/SKILL.md` (and, with `--critic`, `~/.claude/skills/cross-critic/SKILL.md`) for the listed sub-Issues, and it covers, for each sub-Issue completed in this run: the `gh-test-first` work, the `gh-finish --apply` sequence (commit → local merge → Issue close), and one tracking-Issue checklist update; and, at reconciliation, one checklist update for each sub-Issue already closed on GitHub but unchecked. `--critic` also authorizes sending gate material to the cross-critic critics. Nothing else is authorized — no push, no PR, no branch deletion, no closing of or commenting on the tracking Issue, no work outside the listed sub-Issues.

## Loop (per sub-Issue)

1. Re-read `references/workflow.md` and `~/.claude/skills/gh-test-first/SKILL.md` with the references it names (after compaction only Skill-tool invocations come back, not files read with Read). Fetch the tracking Issue with `~/.claude/bin/gh-issue-fetch.sh <tracking>` (the same helper as for sub-Issues); parse the ordered checklist and dependency notes. On the first iteration only, run the reconciliation in workflow.md "Reading the roadmap" step 4. Select the next unchecked sub-Issue whose dependencies are met.
2. Classify the selected sub-Issue as a judgment gate or a work item (workflow.md "Judgment gates"). A judgment gate stops the loop here: with `--critic`, run the cross-critic step first; then present the pending decisions.
3. Run the `gh-test-first` workflow for the sub-Issue through its gate, as `~/.claude/skills/gh-test-first/SKILL.md` defines it.
4. Verify: when the success criteria involve real data or runtime behavior, run the real smoke or backfill check and read its output. Run `/code-review` on the diff only when the Issue touches architecture, data destruction, or a public API.
5. Run the `gh-finish --apply` sequence (commit, local merge, Issue close). The `/gh-roadmap-run` invocation is the explicit request that gh-finish requires for these three actions on this sub-Issue; do not ask again. Then check the sub-Issue's box in the tracking Issue body.
6. Post a brief progress note in the session (sub-Issue, outcome, evidence) and continue with step 1.

## Stop conditions

These are the only reasons to end the run. Starting the next sub-Issue after step 6 needs no confirmation, and a turn that lists remaining sub-Issues without one of these conditions is not a valid stop.

- A judgment gate is next, a dependency is unmet, or an Issue body is ambiguous in a way that changes design, data, or public API.
- A completed sub-Issue's result meets its `中止条件:` line (written by `/gh-roadmap-plan`). Show the result and the line to the user; do not skip ahead to a verdict sub-Issue on your own.
- A `gh-test-first` gate, verification, or `gh-finish` check fails and cannot be fixed within the sub-Issue's scope — report; never merge over a failure and never weaken a test.
- A cross-critic run fails (with `--critic`).
- Any stop condition of `gh-test-first`, `gh-finish`, or `cross-critic`.
- The checklist is exhausted: report that every box is checked and leave the tracking Issue open for the user to close.

On stop, report: sub-Issues completed this run with evidence, the current checklist state, why the loop stopped, and the exact command to resume（再実行で未完了分から継続できる）.
