# gh-index workflow

## Survey

1. Read repository instructions and inspect status, branch, root files, manifests, primary entrypoints, tests, CI, package/dependency files, and documentation.
2. Build a compact structure map by subsystem rather than listing every file.
3. Trace actual execution and configuration consumers for important paths.
4. Identify current capabilities, incomplete work, duplicated mechanisms, risky boundaries, and verification gaps using file evidence.
5. Inspect existing Issues only when the user asked for GitHub-aware planning and the required read access is available.

## Output

Include:

- Repository purpose and technology summary.
- Subsystem map with exact key paths.
- Runtime/configuration/data flow.
- Test and release gates.
- Candidate work items with evidence, intended outcome, non-goals, dependencies, and verification.
- Unknowns that require investigation rather than implementation.

Do not present a candidate as an existing bug without reproduction or direct evidence. Do not create an Issue; hand the selected candidate to `issue-writing`.

## File mode

Normalize the requested output against the canonical repository root. Refuse path traversal and symlink escape. Create missing parent directories only inside the repository. Without `--force`, refuse an existing path and leave it unchanged. Write UTF-8 atomically and verify the resulting file.
