from __future__ import annotations

import ast
import importlib.util
from collections import defaultdict, deque
from pathlib import Path
from typing import Any


def build_import_analysis(
    root: Path,
    python_files: list[Path],
    package_roots: list[Path] | None = None,
    profile: str | None = None,
) -> dict[str, Any]:
    package_roots = package_roots or [root]
    modules = {_module_name(root, path, package_roots): path for path in python_files}
    graph: dict[str, list[str]] = {}
    imports_by_file: dict[str, list[str]] = {}
    unresolved: dict[str, list[str]] = {}
    errors: list[dict[str, Any]] = []

    for path in python_files:
        file_key = _rel(root, path)
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        except (SyntaxError, UnicodeDecodeError, OSError) as exc:
            errors.append({"file": file_key, "error": exc.__class__.__name__, "message": str(exc)})
            continue

        imported_modules = sorted(_imports(tree))
        imports_by_file[file_key] = imported_modules
        local_edges: list[str] = []
        missing: list[str] = []
        for imported in imported_modules:
            resolved = _resolve_local(imported, modules)
            if resolved is None:
                missing.append(imported)
            else:
                local_edges.append(_rel(root, resolved))
        graph[file_key] = sorted(set(local_edges))
        if missing:
            unresolved[file_key] = sorted(set(missing))

    reverse = _reverse_graph(graph)
    return {
        "provider": "grimp" if importlib.util.find_spec("grimp") else "ast",
        "profile": profile,
        "modules": {module: _rel(root, path) for module, path in sorted(modules.items())},
        "imports_by_file": imports_by_file,
        "graph": graph,
        "reverse_graph": reverse,
        "unresolved": unresolved,
        "cycles": _cycles(graph),
        "parse_errors": errors,
    }


def impact_for_focus(import_graph: dict[str, Any], focus_files: set[Path], root: Path) -> dict[str, Any]:
    reverse = import_graph.get("reverse_graph", {})
    focus = {_rel(root, path) for path in focus_files}
    impacted: set[str] = set()
    queue: deque[str] = deque(focus)
    while queue:
        current = queue.popleft()
        for parent in reverse.get(current, []):
            if parent not in impacted and parent not in focus:
                impacted.add(parent)
                queue.append(parent)
    return {
        "focus_files": sorted(focus),
        "impacted_files": sorted(impacted),
        "impacted_count": len(impacted),
    }


def _imports(tree: ast.AST) -> set[str]:
    found: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                found.add(alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module:
            base = "." * node.level + node.module if node.level else node.module
            for alias in node.names:
                if alias.name == "*":
                    found.add(base)
                else:
                    found.add(f"{base}.{alias.name}")
    return found


def _module_name(root: Path, path: Path, package_roots: list[Path]) -> str:
    for base in package_roots:
        try:
            relative = path.resolve().relative_to(base.resolve())
            break
        except ValueError:
            continue
    else:
        relative = path.resolve().relative_to(root.resolve())

    parts = list(relative.with_suffix("").parts)
    if parts and parts[-1] == "__init__":
        parts.pop()
    return ".".join(parts)


def _resolve_local(imported: str, modules: dict[str, Path]) -> Path | None:
    name = imported.lstrip(".")
    while name:
        if name in modules:
            return modules[name]
        name = name.rsplit(".", 1)[0] if "." in name else ""
    return None


def _reverse_graph(graph: dict[str, list[str]]) -> dict[str, list[str]]:
    reverse: dict[str, list[str]] = defaultdict(list)
    for source, targets in graph.items():
        for target in targets:
            reverse[target].append(source)
    return {key: sorted(set(value)) for key, value in reverse.items()}


def _cycles(graph: dict[str, list[str]]) -> list[list[str]]:
    cycles: list[list[str]] = []
    visiting: set[str] = set()
    visited: set[str] = set()
    stack: list[str] = []

    def visit(node: str) -> None:
        if node in visiting:
            start = stack.index(node)
            cycles.append(stack[start:] + [node])
            return
        if node in visited:
            return
        visiting.add(node)
        stack.append(node)
        for child in graph.get(node, []):
            visit(child)
        stack.pop()
        visiting.remove(node)
        visited.add(node)

    for node in graph:
        visit(node)
    return cycles


def _rel(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()
