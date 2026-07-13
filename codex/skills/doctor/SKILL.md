---
name: doctor
description: Run a comprehensive, Claude Code-style Codex checkup and safely repair the local installation, configuration, applicable AGENTS.md rules, authentication, runtime, PATH, profiles, hooks, skills, plugins, MCP, sandbox, state, update, and connectivity health. Use when the user invokes $doctor, asks for a full or interactive Codex checkup, reports that Codex is unhealthy or misconfigured, or wants Codex Doctor findings explained and fixed with confirmation.
---

# Doctor

Provide a Claude Code-style interactive checkup: diagnose, explain, propose precise fixes, apply only approved changes, and verify the result.

## Default Scope

Treat `$doctor` with no qualifier as a comprehensive checkup. Do not stop after `codex doctor --json` reports `ok`; use it as the baseline and complete the read-only checks below. Narrow the scope only when the user explicitly requests a specific check.

Audit the Codex environment that applies to the current working directory. Do not recursively review unrelated repositories, caches, dependencies, or every `AGENTS.md` under the user's home directory.

## Workflow

1. Run `codex doctor --json` from the user's current working directory. Preserve its exit code and stderr. If it fails, report the failure explicitly and diagnose the command failure before doing anything else.
2. Parse the redacted report. Expect `checks` to be an object keyed by check ID unless the live schema proves otherwise. Prioritize `error` or `fail` checks, then `warning` checks. Treat informational notes and `idle` components as observations, not defects.
3. Complete the following read-only audit, recording unsupported commands or inaccessible evidence explicitly instead of silently skipping them:
   - **Installation and PATH:** inspect every resolved `codex` executable, its real path, version, owner, and package-manager inventory. Distinguish repeated PATH entries pointing to one installation from distinct installations that can select different versions.
   - **Configuration and profiles:** inspect the active `CODEX_HOME`, validate `config.toml` with the installed CLI's strict-config mode, enumerate applicable profile files, validate referenced profiles, and inspect permissions without printing secrets.
   - **Rules:** enumerate and read only the global and ancestor/repository `AGENTS.md` files applicable to the current working directory. Check encoding, readability, scope, contradictions, stale path or command references, and agreement with the live configuration. Include referenced rule files that materially affect Codex operation.
   - **Hooks:** inspect hook configuration, trust metadata, referenced scripts, file permissions, syntax where a non-executing syntax check exists, and recent explicit hook failures. Do not execute hooks merely to test them, and do not compare unrelated hash formats as if they were equivalent.
   - **Skills, plugins, apps, and MCP:** inspect discoverability and broken paths for local skills, list installed/enabled plugins, and list effective MCP servers or app connectors. Reconcile plugin-provided MCP with user-configured MCP before calling a reported count inconsistent.
   - **Auth, runtime, sandbox, state, network, and updates:** use the redacted doctor evidence and narrowly targeted read-only checks to verify file metadata, database integrity/parity, provider reachability, active sandbox/approval policy, installed version, and available version. Treat a chosen permissive or restrictive policy as an observation unless it conflicts with an applicable rule or stated intent.
   - **Repository context:** run Git status/branch checks only when the current working directory is inside a Git repository; user-level Codex health checks from a non-repository home directory do not require repo diagnostics.
4. For every actionable finding, report:
   - the check ID and status;
   - the concrete evidence from the report;
   - the likely root cause, clearly marked as confirmed or inferred;
   - the exact file, command, database, or external dependency involved;
   - the proposed fix, its impact, and whether it is reversible.
5. Investigate enough local evidence to justify each fix. Do not invent configuration keys, database repairs, commands, paths, or package-manager behavior. Use current official Codex documentation when behavior cannot be established locally.
6. Ask for explicit confirmation before making any state-changing repair. Group only closely related, equally safe changes. Allow the user to approve or reject findings individually.
7. Apply only the approved changes. Keep edits surgical and preserve unrelated user configuration.
8. Re-run every affected targeted check and `codex doctor --json`. Compare the affected check IDs and extended-audit findings before and after, then report resolved, unchanged, regressed, and newly introduced findings with exact counts.

## Safety Rules

- Never weaken sandbox, approval, hook-trust, or network restrictions merely to make a check pass.
- Never delete or rewrite session rollouts, SQLite rows, databases, credentials, tokens, or auth files without a separately explained recovery plan and explicit approval for that exact destructive action.
- Never print secrets. Prefer the redacted doctor report; if deeper auth inspection is indispensable, inspect only non-secret metadata and redact output.
- Never run `codex update`, package-manager installs, login/logout, MCP mutations, plugin mutations, or service start/stop commands before confirmation.
- Never silently catch errors, substitute guessed defaults, or claim success from a zero exit code alone. Validate the relevant check status and evidence after the repair.
- Do not modify healthy or unrelated components. If no actionable findings exist, say so and make no changes.
- Do not expose config values, environment values, headers, URLs with embedded credentials, tokens, or auth-file contents. Prefer key names and redacted metadata.

## Output Shape

Lead with the overall health and actionable finding count. Separate actionable findings from non-defect observations and explicitly state which comprehensive audit areas were checked. For each proposed repair, show the exact action and ask for confirmation. After approved repairs, finish with the before/after status of each affected check, the extended-audit findings, and the remaining overall status.
