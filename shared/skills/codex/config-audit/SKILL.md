---
name: config-audit
description: Audits Codex configuration, AGENTS rules, hooks, skills, plugins, MCP, and profiles against best practice; read-only, --record appends to XDG history. Use when the user explicitly invokes $config-audit. Not for repairs (doctor).
argument-hint: "[--record]"
---

# $config-audit

Read [`../../config-audit/references/workflow.md`](../../config-audit/references/workflow.md).

## Authority

- Default: inspect local config/runtime and current official sources; return an in-chat report only.
- `--record`: perform the same audit, then append one validated JSONL record to `${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/config-audit/audit-history-codex.jsonl`.

Reject unknown or combined arguments. `--record` does not authorize config edits, installation, permission changes, commits, or external writes.

For Codex, inspect effective config, profiles, AGENTS load chain, hooks, skills, plugins, MCP, sandbox, runtime version, and actual discovery. Separate static findings from live confirmation and give one evidence-backed verdict with confidence and reversal conditions.
