---
name: doctor
description: Diagnose and safely repair the local Codex installation, configuration, authentication, runtime, MCP, sandbox, state, update, and connectivity health. Use when the user invokes $doctor, asks for a Claude Code-style interactive checkup, reports that Codex is unhealthy or misconfigured, or wants Codex Doctor findings explained and fixed with confirmation.
---

# Doctor

Provide a Claude Code-style interactive checkup: diagnose, explain, propose precise fixes, apply only approved changes, and verify the result.

## Workflow

1. Run `codex doctor --json` from the user's current working directory. Preserve its exit code and stderr. If it fails, report the failure explicitly and diagnose the command failure before doing anything else.
2. Parse the redacted report. Prioritize `error` or `fail` checks, then `warning` checks. Treat informational notes and `idle` components as observations, not defects. In particular, do not classify an intentionally absent MCP server, an idle app server, or the user's chosen sandbox policy as broken without evidence.
3. For every actionable finding, report:
   - the check ID and status;
   - the concrete evidence from the report;
   - the likely root cause, clearly marked as confirmed or inferred;
   - the exact file, command, database, or external dependency involved;
   - the proposed fix, its impact, and whether it is reversible.
4. Investigate enough local evidence to justify each fix. Do not invent configuration keys, database repairs, commands, or paths. Use current official Codex documentation when behavior cannot be established locally.
5. Ask for explicit confirmation before making any state-changing repair. Group only closely related, equally safe changes. Allow the user to approve or reject findings individually.
6. Apply only the approved changes. Keep edits surgical and preserve unrelated user configuration.
7. Re-run `codex doctor --json`. Compare the affected check IDs before and after, then report resolved, unchanged, regressed, and newly introduced findings with exact counts.

## Safety Rules

- Never weaken sandbox, approval, hook-trust, or network restrictions merely to make a check pass.
- Never delete or rewrite session rollouts, SQLite rows, databases, credentials, tokens, or auth files without a separately explained recovery plan and explicit approval for that exact destructive action.
- Never print secrets. Prefer the redacted doctor report; if deeper auth inspection is indispensable, inspect only non-secret metadata and redact output.
- Never run `codex update`, package-manager installs, login/logout, MCP mutations, plugin mutations, or service start/stop commands before confirmation.
- Never silently catch errors, substitute guessed defaults, or claim success from a zero exit code alone. Validate the relevant check status and evidence after the repair.
- Do not modify healthy or unrelated components. If no actionable findings exist, say so and make no changes.

## Output Shape

Lead with the overall health and actionable finding count. Use a compact list for findings. For each proposed repair, show the exact action and ask for confirmation. After approved repairs, finish with the before/after status of each affected check and the remaining overall status.
