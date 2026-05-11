# Python Refactor Analysis

`refactor-analyze` scans a Python project and writes 10 refactor-focused report files with:

- repository and package structure
- import graph and focus impact
- symbols, dead-code candidates, and refactor probes
- complexity, long-function, and large-file signals
- optional project checks (`ruff`, `mypy`, `pytest`)
- a structure-first prompt for the next coding agent

## Run

```bash
uv run --project . refactor-analyze /path/to/repo --out .analysis --diff --profile full
```

For invocation as a Claude Code skill, see [`SKILL.md`](./SKILL.md).

## Outputs

`summary.md`, `structure_map.md` (+`.json`), `structure_review.md`, `findings.json`,
`checks.md`, `hotspots.md`, `import_graph.json`, `refactor_prompt.md`, and the legacy
`analysis.md`.
