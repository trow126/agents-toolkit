from __future__ import annotations

import ast
from pathlib import Path
from typing import Any

from refactor_analyze._ast_cache import AstCache, CacheEntry


def analyze_symbols(
    root: Path,
    python_files: list[Path],
    cache: AstCache,
) -> dict[str, Any]:
    symbols: list[dict[str, Any]] = []
    references: dict[str, list[dict[str, Any]]] = {}
    scopes: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []

    for path in python_files:
        entry = cache.get(path)
        if entry.tree is None:
            errors.append(_entry_error(root, entry))
            continue

        _SymbolVisitor(root, path, symbols, references, scopes).visit(entry.tree)

    exported = [item for item in symbols if not item["name"].startswith("_")]
    return {
        "symbols": symbols,
        "exported": exported,
        "references": references,
        "scopes": scopes,
        "parse_errors": errors,
    }


def find_dead_code_candidates(symbol_data: dict[str, Any]) -> list[dict[str, Any]]:
    references = symbol_data.get("references", {})
    symbols = symbol_data.get("symbols", [])
    class_ranges_by_file = _class_ranges_by_file(symbols)

    return [
        {**symbol, "reason": "No direct name references found."}
        for symbol in symbols
        if _is_dead_code_candidate(symbol, references, class_ranges_by_file)
    ]


def _class_ranges_by_file(symbols: list[dict[str, Any]]) -> dict[str, list[tuple[int, int]]]:
    class_ranges_by_file: dict[str, list[tuple[int, int]]] = {}
    for symbol in symbols:
        if symbol["kind"] != "ClassDef":
            continue
        end = symbol["end_line"] or symbol["line"]
        class_ranges_by_file.setdefault(symbol["file"], []).append((symbol["line"], end))
    return class_ranges_by_file


def _is_dead_code_candidate(
    symbol: dict[str, Any],
    references: dict[str, list[dict[str, Any]]],
    class_ranges_by_file: dict[str, list[tuple[int, int]]],
) -> bool:
    name = str(symbol["name"])
    if name.startswith("__") and name.endswith("__"):
        return False
    if name == "main":
        return False
    if symbol["kind"] in ("FunctionDef", "AsyncFunctionDef") and _is_method(
        symbol, class_ranges_by_file
    ):
        return False
    return not references.get(name)


def _is_method(
    symbol: dict[str, Any],
    class_ranges_by_file: dict[str, list[tuple[int, int]]],
) -> bool:
    ranges = class_ranges_by_file.get(symbol["file"], [])
    line = symbol["line"]
    return any(start < line <= end for start, end in ranges)


def _symbol(
    root: Path,
    path: Path,
    node: ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef,
) -> dict[str, Any]:
    record: dict[str, Any] = {
        "file": _rel(root, path),
        "name": node.name,
        "kind": node.__class__.__name__,
        "line": node.lineno,
        "end_line": node.end_lineno,
        "column": node.col_offset,
        "docstring": bool(ast.get_docstring(node)),
    }
    if isinstance(node, ast.ClassDef):
        record["bases"] = [base for base in (_base_name(b) for b in node.bases) if base]
    return record


def _base_name(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = _base_name(node.value)
        return f"{parent}.{node.attr}" if parent else node.attr
    return None


class _SymbolVisitor(ast.NodeVisitor):
    def __init__(
        self,
        root: Path,
        path: Path,
        symbols: list[dict[str, Any]],
        references: dict[str, list[dict[str, Any]]],
        scopes: list[dict[str, Any]],
    ) -> None:
        self._root = root
        self._path = path
        self._file = _rel(root, path)
        self._symbols = symbols
        self._references = references
        self._scopes = scopes
        self._stack: list[str] = []

    def _scope_label(self) -> str:
        return ".".join(self._stack) if self._stack else "<module>"

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        self._symbols.append(_symbol(self._root, self._path, node))
        self._stack.append(node.name)
        self.generic_visit(node)
        self._stack.pop()

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._enter_function(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._enter_function(node)

    def visit_Assign(self, node: ast.Assign) -> None:
        for target in node.targets:
            self._record_assignment_target(target, node.lineno, node.end_lineno)
        self.generic_visit(node)

    def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
        self._record_assignment_target(node.target, node.lineno, node.end_lineno)
        self.generic_visit(node)

    def visit_Name(self, node: ast.Name) -> None:
        if isinstance(node.ctx, ast.Load):
            self._references.setdefault(node.id, []).append(
                {"file": self._file, "line": node.lineno, "column": node.col_offset},
            )
        self.generic_visit(node)

    def _enter_function(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        self._symbols.append(_symbol(self._root, self._path, node))
        parent_scope = self._scope_label()
        self._stack.append(node.name)
        function_scope = self._scope_label()
        for arg in _iter_args(node.args):
            self._scopes.append(
                {
                    "file": self._file,
                    "name": arg.arg,
                    "scope": function_scope,
                    "kind": "arg",
                    "line": arg.lineno,
                    "end_line": arg.end_lineno,
                },
            )
        self.generic_visit(node)
        self._stack.pop()
        del parent_scope

    def _record_assignment_target(
        self,
        target: ast.AST,
        line: int,
        end_line: int | None,
    ) -> None:
        scope = self._scope_label()
        for name in _assignment_names(target):
            self._scopes.append(
                {
                    "file": self._file,
                    "name": name,
                    "scope": scope,
                    "kind": "assign",
                    "line": line,
                    "end_line": end_line,
                },
            )


def _iter_args(args: ast.arguments) -> list[ast.arg]:
    collected: list[ast.arg] = []
    collected.extend(args.posonlyargs)
    collected.extend(args.args)
    collected.extend(args.kwonlyargs)
    if args.vararg is not None:
        collected.append(args.vararg)
    if args.kwarg is not None:
        collected.append(args.kwarg)
    return collected


def _assignment_names(target: ast.AST) -> list[str]:
    if isinstance(target, ast.Name):
        return [target.id]
    if isinstance(target, (ast.Tuple, ast.List)):
        names: list[str] = []
        for element in target.elts:
            names.extend(_assignment_names(element))
        return names
    if isinstance(target, ast.Starred):
        return _assignment_names(target.value)
    return []


def _entry_error(root: Path, entry: CacheEntry) -> dict[str, Any]:
    assert entry.error is not None
    return {
        "file": _rel(root, entry.path),
        "error": entry.error["error"],
        "message": entry.error["message"],
    }


def _rel(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()
