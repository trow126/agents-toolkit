# Configuration audit workflow

## Evidence order

1. Resolve actual executable, version, active profile, HOME/XDG paths, and current working directory.
2. Read the effective local source files and their symlink/managed-policy targets; do not infer behavior from repository layout alone.
3. Inspect hooks without executing unknown hook bodies. Verify skill and plugin discovery through the runtime where supported.
4. Check authentication and connectivity with read-only status commands only.
5. Consult current official documentation for time-sensitive keys, defaults, model aliases, permissions, sandbox, plugins, and MCP behavior.
6. Compare local state with official behavior and the repository's explicit owner decisions.

## Report

Return:

- Overall `HEALTHY`, `NEEDS_ATTENTION`, or `BROKEN`.
- Confirmed configuration and runtime boundaries.
- Findings ordered by severity, each with evidence, impact, and a precise proposed fix.
- Useful current features that are configured but unused.
- Static checks versus live checks, including anything not confirmed.
- A short prioritized next-action list. Do not implement it.

## History record

`--record` may create the parent XDG state directory and append one UTF-8 JSON object with schema version, timestamp, runtime, overall verdict, finding counts, and source commit when available. Validate JSON before append. Never include secrets, full environment dumps, private project names, or raw config values.

If an existing history file is malformed, report and stop without changing it. The record is comparison metadata, not auto memory and not a source of truth for current state.

## Stop conditions

- Required config is unreadable, ambiguous profiles are active, or source and runtime paths conflict.
- Official documentation cannot confirm a high-impact time-sensitive claim.
- Any proposed check would mutate settings, credentials, plugins, permissions, or external services.
