# === Test Quality: Mutation Testing ===
# Claude Code sandbox 互換: uv の可変 state を session temp へ固定する
# (~/.claude/bin/uvw と同じ前処理。sandbox 外では従来どおり動作する)
UVW_STATE ?= $(or $(TMPDIR),/tmp/uvw-state-make)/uvw
export UV_CACHE_DIR ?= $(UVW_STATE)/cache
export UV_PYTHON_INSTALL_DIR ?= $(UVW_STATE)/python
export UV_TOOL_DIR ?= $(UVW_STATE)/tools

.PHONY: mutation-test mutation-test-critical

mutation-test-critical:
	uv run mutmut run
	uv run mutmut results

mutation-test:
	uv run mutmut run --paths-to-mutate=$(shell python -c "import tomllib; print(tomllib.load(open('pyproject.toml','rb')).get('tool',{}).get('mutmut',{}).get('paths_to_mutate','src/'))")
	uv run mutmut results
