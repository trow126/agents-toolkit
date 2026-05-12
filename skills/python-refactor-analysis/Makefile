# === Test Quality: Mutation Testing ===
.PHONY: mutation-test mutation-test-critical

mutation-test-critical:
	uv run mutmut run
	uv run mutmut results

mutation-test:
	uv run mutmut run --paths-to-mutate=$(shell python -c "import tomllib; print(tomllib.load(open('pyproject.toml','rb')).get('tool',{}).get('mutmut',{}).get('paths_to_mutate','src/'))")
	uv run mutmut results
