from __future__ import annotations

import ast
from pathlib import Path
from typing import Any

from refactor_analyze._ast_cache import AstCache
from refactor_analyze.symbols import find_dead_code_candidates


def analyze_refactor_probes(
    root: Path,
    python_files: list[Path],
    symbol_data: dict[str, Any],
    cache: AstCache,
    *,
    enabled: bool,
    max_symbols: int = 25,
) -> dict[str, Any]:
    if not enabled:
        return {
            "status": "skipped",
            "provider": "rope",
            "note": "Refactor probes were skipped.",
            "probes": [],
            "errors": [],
            "dead_code_candidates": find_dead_code_candidates(symbol_data),
        }

    try:
        from rope.base import libutils
        from rope.base.project import Project
        from rope.contrib.findit import find_occurrences
    except Exception as exc:
        fallback_probes, fallback_errors = _fallback_occurrences(
            root,
            python_files,
            symbol_data,
            max_symbols,
        )
        return {
            "status": "unavailable",
            "provider": "rope",
            "note": str(exc),
            "probes": fallback_probes,
            "errors": fallback_errors,
            "dead_code_candidates": find_dead_code_candidates(symbol_data),
        }

    project = Project(str(root), ropefolder=None)
    probes: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []
    try:
        for symbol in _definition_offsets(root, python_files, cache)[:max_symbols]:
            path = root / str(symbol["file"])
            try:
                resource = libutils.path_to_resource(project, str(path))
                offset = symbol["offset"] if isinstance(symbol["offset"], int) else 0
                occurrences = find_occurrences(
                    project,
                    resource,
                    offset,
                    unsure=True,
                    resources=None,
                )
                probes.append(
                    {
                        "file": symbol["file"],
                        "name": symbol["name"],
                        "kind": symbol["kind"],
                        "line": symbol["line"],
                        "occurrences": len(occurrences),
                    }
                )
            except Exception as exc:
                errors.append(_probe_error(symbol, exc))
    finally:
        project.close()

    return {
        "status": "ok" if not errors else "partial",
        "provider": "rope",
        "note": "",
        "probes": probes,
        "errors": errors,
        "dead_code_candidates": find_dead_code_candidates(symbol_data),
    }


def _definition_offsets(
    root: Path,
    python_files: list[Path],
    cache: AstCache,
) -> list[dict[str, Any]]:
    symbols: list[dict[str, Any]] = []
    for path in python_files:
        entry = cache.get(path)
        if entry.tree is None or entry.source is None:
            continue
        source = entry.source
        tree = entry.tree
        line_starts = _line_starts(source)
        lines = source.splitlines()
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                continue
            line = lines[node.lineno - 1] if node.lineno - 1 < len(lines) else ""
            name_column = line.find(node.name)
            column = name_column if name_column >= 0 else node.col_offset
            symbols.append(
                {
                    "file": _rel(root, path),
                    "name": node.name,
                    "kind": node.__class__.__name__,
                    "line": node.lineno,
                    "offset": line_starts[node.lineno - 1] + column,
                }
            )
    return symbols


def _fallback_occurrences(
    root: Path,
    python_files: list[Path],
    symbol_data: dict[str, Any],
    max_symbols: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    sources = []
    errors = []
    for path in python_files:
        try:
            sources.append(path.read_text(encoding="utf-8"))
        except (UnicodeDecodeError, OSError) as exc:
            errors.append(_file_error(root, path, exc))
    joined = "\n".join(sources)
    probes = []
    for symbol in symbol_data.get("symbols", [])[:max_symbols]:
        name = str(symbol["name"])
        probes.append(
            {
                "file": symbol["file"],
                "name": name,
                "kind": symbol["kind"],
                "line": symbol["line"],
                "occurrences": joined.count(name),
            }
        )
    return probes, errors


def _line_starts(source: str) -> list[int]:
    starts = [0]
    offset = 0
    for line in source.splitlines(keepends=True):
        offset += len(line)
        starts.append(offset)
    return starts


def _probe_error(symbol: dict[str, Any], exc: BaseException) -> dict[str, Any]:
    return {
        "file": symbol.get("file"),
        "name": symbol.get("name"),
        "error": exc.__class__.__name__,
        "message": str(exc),
    }


def _file_error(root: Path, path: Path, exc: BaseException) -> dict[str, Any]:
    return {
        "file": _rel(root, path),
        "error": exc.__class__.__name__,
        "message": str(exc),
    }


def _rel(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()
