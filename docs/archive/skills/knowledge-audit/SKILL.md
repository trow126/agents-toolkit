---
name: knowledge-audit
description: Audits, deduplicates, or compresses claudedocs/learnings.md or technical_debt.md; report-only by default, --apply edits only the selected files after showing the plan. Use when the user explicitly asks for a knowledge audit. Not for memory.
disable-model-invocation: true
argument-hint: "[path] [--apply]"
---

# knowledge-audit

Read [`references/workflow.md`](references/workflow.md), `~/.agents/rules/self-improvement.md`, and `~/.agents/rules/learnings.md`.

## Modes

- Default: inspect selected knowledge files and return a proposed consolidation report only.
- `--apply`: apply the reviewed consolidation to the selected project files and verify UTF-8 and semantic preservation.

`--apply` does not authorize updating `~/.agents/rules`, Codex memory, unrelated project files, commits, or deletion of user backups. Shared promotion remains a separately proposed line and requires a separate explicit request.

If the target is ambiguous, discover candidates and ask which one to use before any write. Preserve project-specific decisions, dates, evidence, unresolved debt, and links; remove only proven duplication, empty templates, or explicitly stale entries.
