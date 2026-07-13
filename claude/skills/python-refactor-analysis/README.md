# Python Refactor Analysis

`refactor-analyze` scans a Python project and writes 11 refactor-focused report files with:

- repository and package structure
- import graph and focus impact
- symbols, dead-code candidates, and refactor probes
- complexity, long-function, and large-file signals
- uv-only project checks (`ruff`, `mypy`, `pytest`)
- a structure-first prompt for the next coding agent

The tool borrows the structure-map approach from `ast-structure-map`, but narrows it to Python refactor planning. It does not implement security-scanner features such as taint analysis, CWE reports, secret scanning, or dependency CVE audits.

## Run

```bash
uv run --project . refactor-analyze /path/to/repo --out .analysis --profile full
```

The intended workflow is whole-repository analysis with the full profile.

Project checks run through `uv run --project /path/to/repo ...`. Repositories without
`pyproject.toml` or `uv.lock` are reported as unsupported for checks; the tool does not
fall back to system Python.

For invocation as a Claude Code skill, see [`SKILL.md`](./SKILL.md).

## Outputs

`summary.md`, `structure_map.md` (+`.json`), `structure_review.md` (with Mermaid
call graph, class inheritance, and import graph sections), `findings.json`,
`checks.md`, `hotspots.md`, `import_graph.json` (Tarjan SCC cycles),
`refactor_prompt.md`, `scopes.md`, and the legacy `analysis.md`.
