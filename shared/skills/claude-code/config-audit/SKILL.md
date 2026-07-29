---
name: config-audit
description: Use when the user asks to audit Claude Code configuration, settings, hooks, skills, plugins, MCP, or current best-practice alignment. Default mode is read-only; --record only appends the confirmed summary to XDG history. Do not repair settings.
argument-hint: "[--record]"
---

# /config-audit

Read [`references/workflow.md`](references/workflow.md).

## Authority

- Default: inspect local config/runtime and current official sources; return an in-chat report only.
- `--record`: perform the same audit, then append one validated JSONL record to `${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/config-audit/audit-history.jsonl`.

Reject unknown or combined arguments. `--record` does not authorize config edits, installation, permission changes, commits, or external writes.

For Claude Code, inspect effective user/managed settings, hooks, agents, skills, plugins, MCP, runtime version, and actual load paths. Separate static findings from live confirmation and give one evidence-backed verdict with confidence and reversal conditions.
