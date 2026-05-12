---
name: python-refactor-analysis
description: Analyze a Python repository before refactoring. Use when planning code cleanup, dependency-impact analysis, dead-code review, structure-first refactor work, or before editing an unfamiliar Python project. Generates eleven structure/import/complexity/check reports under `.analysis/`.
---

# Python Refactor Analysis

A structure-first survey: read generated reports first, then read the smallest set of implementation files needed for one high-signal change.

## Workflow

1. Run the CLI on the target repository (see "Invocation").
2. Read the generated reports in this order: `summary.md` → `structure_review.md` → `checks.md` → `hotspots.md` → `import_graph.json` → `refactor_prompt.md`.
3. Pick the smallest high-signal change: high complexity, dead-code candidate, import cycle, or failing check.
4. Make the change and verify with the repository's own tests.

## Invocation

Use the bundled CLI through `uv`; this skill does not fall back to bare `python`:

```bash
uv run --project "${CLAUDE_SKILL_DIR}" \
  refactor-analyze <repo> --out .analysis --profile full
```

Equivalent via the bundled wrapper when this skill is installed under `~/.claude`:

```bash
~/.claude/skills/python-refactor-analysis/scripts/refactor-analyze \
  <repo> --out .analysis --profile full
```

Project checks are uv-only. `ruff`, `mypy`, `pytest`, and optional checks are run as
`uv run --project <repo> ...`. If the target repository has no `pyproject.toml` or
`uv.lock`, checks are reported as `unsupported`; do not silently run system Python.

## Useful options

- `--diff` — focus files from `git diff --name-only`.
- `--path PATH` — focus a file or directory (repeatable).
- `--profile {standard,full}` — analysis depth; `full` includes Rope-based occurrence probes.
- `--skip-checks` — skip running `ruff` / `mypy` / `pytest`.
- `--skip-refactor-probes` — skip Rope occurrence scans.
- `--skip-type-inference` — skip optional type inference.
- `--timeout N` — seconds for each project check.
- `--json` — print the result JSON to stdout in addition to writing files.

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
3. Start with the smallest coherent change; verify with the repo's tests.
4. Use `--diff` after pulling changes to scope a focused review.
