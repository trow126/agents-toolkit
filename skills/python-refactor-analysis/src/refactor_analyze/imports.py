from __future__ import annotations

import ast
import importlib.util
from collections import defaultdict, deque
from pathlib import Path
from typing import Any

from refactor_analyze._ast_cache import AstCache


def build_import_analysis(
    root: Path,
    python_files: list[Path],
    cache: AstCache,
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
        entry = cache.get(path)
        if entry.tree is None:
            assert entry.error is not None
            errors.append(
                {
                    "file": file_key,
                    "error": entry.error["error"],
                    "message": entry.error["message"],
                }
            )
            continue

        imported_modules = sorted(_imports(entry.tree))
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
    return _tarjan_scc(graph)


def _tarjan_scc(graph: dict[str, list[str]]) -> list[list[str]]:
    """Return non-trivial strongly connected components as sorted node lists.

    A component is reported when it has 2 or more nodes, or when it is a single
    node with a self-loop. Implemented iteratively to avoid Python recursion
    limits on large repositories.
    """
    index_of: dict[str, int] = {}
    lowlink: dict[str, int] = {}
    on_stack: set[str] = set()
    scc_stack: list[str] = []
    components: list[list[str]] = []
    counter = 0

    nodes = set(graph)
    for targets in graph.values():
        nodes.update(targets)

    for start in sorted(nodes):
        if start in index_of:
            continue
        work: list[tuple[str, list[str], int]] = [(start, list(graph.get(start, [])), 0)]
        index_of[start] = counter
        lowlink[start] = counter
        counter += 1
        scc_stack.append(start)
        on_stack.add(start)

        while work:
            node, successors, pos = work[-1]
            if pos < len(successors):
                work[-1] = (node, successors, pos + 1)
                child = successors[pos]
                if child not in index_of:
                    index_of[child] = counter
                    lowlink[child] = counter
                    counter += 1
                    scc_stack.append(child)
                    on_stack.add(child)
                    work.append((child, list(graph.get(child, [])), 0))
                elif child in on_stack:
                    lowlink[node] = min(lowlink[node], index_of[child])
                continue

            if lowlink[node] == index_of[node]:
                component: list[str] = []
                while True:
                    member = scc_stack.pop()
                    on_stack.discard(member)
                    component.append(member)
                    if member == node:
                        break
                if len(component) > 1 or node in graph.get(node, []):
                    components.append(sorted(component))

            work.pop()
            if work:
                parent = work[-1][0]
                lowlink[parent] = min(lowlink[parent], lowlink[node])

    components.sort(key=lambda component: (len(component), component), reverse=True)
    return components


def _rel(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()
