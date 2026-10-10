---
name: gh-roadmap-run
description: Loops a tracking Issue's sub-Issues through /gh-test-first, verification, and /gh-finish --apply, updating its checklist until a gate, unmet dependency, or failure; --critic adds cross-critic at gates. Use when the user invokes /gh-roadmap-run.
disable-model-invocation: true
argument-hint: "<tracking-issue-number> [--status|--critic]"
---

# /gh-roadmap-run

Successor of the deprecated `/gh-roadmap-drive`: Claude implements each sub-Issue test-first instead of delegating it to Codex (2026-10 A/B experiments, `docs/eval/sandwich-ab-results.md` and `sandwich-ab-d-results.md` in agents-toolkit).

Read [`references/workflow.md`](references/workflow.md). The per-step contracts are owned by the `gh-test-first`, `gh-finish`, and `cross-critic` skills. Load `gh-finish` via the Skill tool. `gh-test-first` and `cross-critic` set `disable-model-invocation: true`, so the Skill tool refuses them; read their files instead at the step that uses them: `~/.claude/skills/gh-test-first/SKILL.md` and `~/.claude/skills/cross-critic/SKILL.md`, plus the references each one names. This skill only adds the loop over a tracking Issue; it never relaxes those skills' rules.

## Modes

- `/gh-roadmap-run <tracking-issue>`: iterate the unchecked sub-Issues in roadmap order, as far as possible（「出来るところまで」）.
- `/gh-roadmap-run <tracking-issue> --critic`: the same loop; at each judgment gate, also run `cross-critic` in its gate mode on the gate's decision material before presenting it.
- `/gh-roadmap-run <tracking-issue> --status`: report checklist state against GitHub and local evidence only; no implementation, no edits, no writes.

## Authority

Invoking the loop is the user's single explicit request covering, for each sub-Issue completed in this run: the `gh-test-first` work, the `gh-finish --apply` sequence (commit → local merge → Issue close), and one tracking-Issue checklist update. `--critic` also authorizes sending gate material to the cross-critic critics. Nothing else is authorized — no push, no PR, no branch deletion, no work outside the listed sub-Issues.

## Loop (per sub-Issue)

1. Fetch the tracking Issue; parse the ordered checklist and dependency notes. Select the next unchecked sub-Issue whose dependencies are met.
2. If it is a user decision（【判断ゲート】, 担当: ユーザー, ask-mode 等）, stop the loop; with `--critic`, first run the cross-critic step in the workflow. Present the pending decisions.
3. Run the `gh-test-first` workflow for the sub-Issue: success criteria, tests written and failing first (with causality tests in time-series or quantitative repos), implementation, and its gate.
4. Verify: when the success criteria involve real data or runtime behavior, run the real smoke or backfill check and read its output. Run `/code-review` on the diff only when the Issue touches architecture, data destruction, or a public API.
5. Run the `gh-finish --apply` sequence, then check the sub-Issue's box in the tracking Issue body.
6. Post a brief progress note in the session (sub-Issue, outcome, evidence) and continue with step 1.

## Stop conditions

- A judgment gate is next, a dependency is unmet, or an Issue body is ambiguous in a way that changes design, data, or public API.
- A `gh-test-first` gate, verification, or `gh-finish` check fails and cannot be fixed within the sub-Issue's scope — report; never merge over a failure and never weaken a test.
- A cross-critic run fails (with `--critic`).
- Any stop condition of `gh-test-first`, `gh-finish`, or `cross-critic`.
- The checklist is exhausted.

On stop, report: sub-Issues completed this run with evidence, the current checklist state, why the loop stopped, and the exact command to resume（再実行で未完了分から継続できる）.
