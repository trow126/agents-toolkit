---
name: gh-roadmap-drive
description: Use when the user asks to advance a roadmap/tracking Issue by iterating its sub-Issues end-to-end with Codex as implementer（「Issue#Nに従って、Issue単位で/gh-codex-driveで実装して、実装が終わったら確認して/gh-finish --applyでクローズする流れを、出来るところまで繰り返して進めて」等）. Loops /gh-codex-drive → verify → /gh-finish --apply per sub-Issue and updates the tracking checklist, stopping at judgment gates, unmet dependencies, and failures. Do not use for a single Issue (use gh-codex-drive, gh-start, or gh-finish directly).
argument-hint: "<tracking-issue-number> [--status]"
---

# /gh-roadmap-drive

Read [`references/workflow.md`](references/workflow.md). The per-step contracts are owned by the `gh-codex-drive` and `gh-finish` skills — load each via the Skill tool at the step that uses it. This skill only adds the loop over a tracking Issue; it never relaxes either skill's rules.

## Roles

Codex implements each sub-Issue. Claude (owner, this session) reads the roadmap, picks the next actionable sub-Issue, drives delegation/verification/review per `gh-codex-drive`, applies completion per `gh-finish --apply`, updates the tracking checklist, and continues.

## Modes

- `/gh-roadmap-drive <tracking-issue>`: iterate the unchecked sub-Issues in roadmap order, as far as possible（「出来るところまで」）.
- `/gh-roadmap-drive <tracking-issue> --status`: report checklist state against GitHub and local evidence only; no delegation, no edits, no writes.

## Authority

Invoking default mode is the user's single explicit request covering, for each sub-Issue completed in this run: the `gh-finish --apply` sequence (commit → local merge → Issue close) and one tracking-Issue checklist update. Nothing else is authorized — no push, no PR, no branch deletion, no work outside the listed sub-Issues. Push remains a separate explicit request.

## Loop (per sub-Issue)

1. Fetch the tracking Issue; parse the ordered checklist and any dependency notes. Select the next unchecked sub-Issue whose dependencies are met.
2. If that sub-Issue is marked as a user decision（【判断ゲート】, 担当: ユーザー, ask-mode 等）, stop the loop and present the pending decisions instead of implementing.
3. Run the `gh-codex-drive` workflow for the sub-Issue: feature branch, success criteria from the Issue body, Codex delegation via `codex-companion.mjs task` in the background, deterministic verification, owner diff review. Fix small findings per its review-fix boundary; re-delegate substantial gaps to Codex as fresh tasks.
4. When the Issue's success criteria involve real data or runtime behavior, run the real smoke/backfill check before declaring the Issue done.
5. Run the `gh-finish --apply` sequence, then check the sub-Issue's box in the tracking Issue body.
6. Post a brief progress note in the session (sub-Issue, outcome, evidence) and continue with step 1.

## Stop conditions

- A judgment-gate sub-Issue is next, a dependency is unmet, or the Issue body is ambiguous in a way that changes design, data, or public API.
- Verification or review failure that survives one re-delegation — report; never merge over a failure and never retry silently.
- Any stop condition of `gh-codex-drive` or `gh-finish` (missing repo/Issue/plugin/auth, unrelated dirty changes, failing checks).
- The checklist is exhausted.

On stop, report: sub-Issues completed this run with evidence, the current checklist state, why the loop stopped, and the exact command to resume（再実行で未完了分から継続できる）.
