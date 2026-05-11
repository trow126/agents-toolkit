from __future__ import annotations

import ast
from pathlib import Path
from typing import Any


def analyze_symbols(root: Path, python_files: list[Path]) -> dict[str, Any]:
    symbols: list[dict[str, Any]] = []
    references: dict[str, list[dict[str, Any]]] = {}
    errors: list[dict[str, Any]] = []

    for path in python_files:
        try:
            source = path.read_text(encoding="utf-8")
            tree = ast.parse(source, filename=str(path))
        except (SyntaxError, UnicodeDecodeError, OSError) as exc:
            errors.append(_error(root, path, exc))
            continue

        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                symbols.append(_symbol(root, path, node))
            elif isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
                references.setdefault(node.id, []).append(
                    {"file": _rel(root, path), "line": node.lineno, "column": node.col_offset}
                )

    exported = [item for item in symbols if not item["name"].startswith("_")]
    return {
        "symbols": symbols,
        "exported": exported,
        "references": references,
        "parse_errors": errors,
    }


def find_dead_code_candidates(symbol_data: dict[str, Any]) -> list[dict[str, Any]]:
    references = symbol_data.get("references", {})
    candidates: list[dict[str, Any]] = []
    for symbol in symbol_data.get("symbols", []):
        name = str(symbol["name"])
        if name.startswith("__") and name.endswith("__"):
            continue
        if name == "main":
            continue
        if not references.get(name):
            candidates.append({**symbol, "reason": "No direct name references found."})
    return candidates


def _symbol(root: Path, path: Path, node: ast.AST) -> dict[str, Any]:
    name = getattr(node, "name", "<unknown>")
    return {
        "file": _rel(root, path),
        "name": name,
        "kind": node.__class__.__name__,
        "line": getattr(node, "lineno", None),
        "end_line": getattr(node, "end_lineno", None),
        "column": getattr(node, "col_offset", None),
        "docstring": bool(ast.get_docstring(node)),
    }


def _error(root: Path, path: Path, exc: BaseException) -> dict[str, Any]:
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
