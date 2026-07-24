---
name: python-refactor-analysis
description: Analyze a Python repository before refactoring. Use when planning code cleanup, dependency-impact analysis, dead-code review, structure-first refactor work, or before editing an unfamiliar Python project. Generates eleven structure/import/complexity/check reports under `.analysis/`.
---

# Python Refactor Analysis

A structure-first survey: read generated reports first, then read the smallest set of implementation files needed for one high-signal change.

This skill adapts the structure-map idea from `ast-structure-map` for Python refactor planning. It is not a security scanner: taint analysis, CWE reports, secret scanning, and dependency CVE audits are intentionally out of scope.

Normal skill usage is intentionally single-mode: analyze the whole target repository with the full profile.

Full-profile runs are not expected to finish quickly on medium or large repositories.
The Rope refactor probes and project checks can run for 10-30+ minutes and may emit no
stdout until all reports are written. Do not assume the command is hung just because it
is silent for several minutes. Use a long outer timeout when a strict result is needed;
use `--skip-refactor-probes` only for a fast structural preview, and rerun without that
flag before relying on dead-code/refactor-probe findings.

## Workflow

1. Run the full-depth CLI on the whole target repository (see "Invocation").
2. Read the generated reports in this order: `summary.md` → `structure_review.md` → `checks.md` → `hotspots.md` → `import_graph.json` → `refactor_prompt.md`.
3. Pick the smallest high-signal change: high complexity, dead-code candidate, import cycle, or failing check.
4. Make the change and verify with the repository's own tests.

## Invocation

Use the bundled wrapper (`scripts/refactor-analyze` under this skill's own
directory — e.g. `~/.claude/skills/python-refactor-analysis/scripts/refactor-analyze`
or `~/.agents/skills/python-refactor-analysis/scripts/refactor-analyze`); it pins
uv's mutable state (cache/python/tools) to the session temp directory, so it works
even where uv's default paths are outside the write boundary. This skill does not
fall back to bare `python`:

```bash
<this-skill-dir>/scripts/refactor-analyze <repo> --profile full
```

Reports are written to `<repo>/.analysis` by default, regardless of the current
working directory. Pass `--out` to write elsewhere.

For strict runs, prefer an explicit long timeout around the command:

```bash
timeout 1800 \
  <this-skill-dir>/scripts/refactor-analyze \
  <repo> --profile full --timeout 300
```

For a quick preview that skips Rope probes but still writes the structure/import/
complexity reports:

```bash
<this-skill-dir>/scripts/refactor-analyze <repo> --profile full --skip-refactor-probes
```

Project checks are uv-only. `ruff`, `mypy`, `pytest`, and optional checks are run as
`uv run --project <repo> ...`. If the target repository has no `pyproject.toml` or
`uv.lock`, checks are reported as `unsupported`; do not silently run system Python.

## Output files

| File | Purpose |
|------|---------|
| `summary.md` | Top-level snapshot: focus, hotspots, dead-code candidates, parse errors |
| `structure_map.md` / `.json` | Package and file structure |
| `structure_review.md` | Packages, cycles, call edges |
| `findings.json` | Machine-readable findings |
| `checks.md` | uv project check results: passed, failed, skipped, timeout, or unsupported |
| `hotspots.md` | Complexity, long functions, fan-in/out |
| `import_graph.json` | Resolved import graph and Tarjan SCC cycles |
| `refactor_prompt.md` | Suggested prompt for the next coding agent |
| `scopes.md` | Function arguments and `Assign` / `AnnAssign` targets per scope |
| `analysis.md` | Legacy single-file digest |

## Refactor policy

1. Read structure reports before implementation bodies.
2. Treat dead-code results as candidates only — dynamic references (pytest classes, AST visitors, plugin entry points) are commonly missed.
3. One session yields one PR. Bundle every coherent improvement discovered in the same analysis into the same session; split them across commits, not PRs. Each commit must be independently revertible and pass the repository's tests.
4. If the repository changes during analysis, rerun the whole-repository full profile before relying on stale reports.
