# Knowledge audit workflow

## Report-only analysis

1. Resolve the exact `claudedocs/learnings.md` and/or `technical_debt.md` target. Check Git status for those paths.
2. Parse headings and entries as UTF-8. Classify duplicates, near-duplicates, empty templates, one-off incidents, reusable patterns, resolved debt, stale debt, and conflicting guidance.
3. Verify claims against current code or history when inexpensive; do not treat old documentation as proof of current behavior.
4. Propose a preservation map showing each original entry's destination, merge, retention, or candidate removal.
5. Identify possible shared-rule promotions as proposals only, with destination and exact one-line text.

## Apply mode

After the user invoked `--apply`, re-read targets and abort on drift from the reviewed input. Write only the selected project files, preserve newline/encoding conventions, and verify:

- Every retained fact and unresolved obligation remains represented.
- No empty or duplicate sections remain.
- Links and Issue references still resolve syntactically.
- Japanese text round-trips as UTF-8.
- The diff contains no unrelated file.

Do not create timestamped backups inside the repository when Git already provides rollback. Never delete an existing backup or update shared rules, memory, or promotion ledgers.

## Technical debt rules

Resolved items move only when the project has an established archive convention. Otherwise mark them resolved in place. Items that cannot be reproduced remain documented as unconfirmed unless the user explicitly authorizes removal.
