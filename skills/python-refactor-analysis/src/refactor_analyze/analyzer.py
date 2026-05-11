from __future__ import annotations

import ast
import subprocess
from dataclasses import asdict, replace
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

try:
    from radon.complexity import cc_visit
    from radon.raw import analyze as raw_analyze
except Exception:  # pragma: no cover - optional runtime fallback
    cc_visit = None
    raw_analyze = None

from refactor_analyze.architecture import analyze_architecture
from refactor_analyze.checks import run_checks, skipped_checks
from refactor_analyze.config import AnalysisConfig, load_config
from refactor_analyze.imports import build_import_analysis, impact_for_focus
from refactor_analyze.refactors import analyze_refactor_probes
from refactor_analyze.reports import write_reports
from refactor_analyze.structure_map import build_structure_map
from refactor_analyze.symbols import analyze_symbols, find_dead_code_candidates


SCHEMA_VERSION = "3"

EXCLUDED_DIRS = {
    ".git",
    ".hg",
    ".svn",
    ".venv",
    "venv",
    "env",
    "__pycache__",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".tox",
    ".nox",
    "node_modules",
    "build",
    "dist",
    "site-packages",
    ".codex",
}


def analyze_project(
    root: Path,
    out: Path,
    *,
    paths: list[Path] | None = None,
    diff: bool = False,
    run_project_checks: bool = True,
    profile: str | None = None,
    skip_type_inference: bool = False,
    skip_refactor_probes: bool = False,
    timeout_seconds: int | None = None,
) -> dict[str, Any]:
    root, output_dir, config = _prepare_analysis(
        root,
        out,
        profile=profile,
        skip_type_inference=skip_type_inference,
        skip_refactor_probes=skip_refactor_probes,
        timeout_seconds=timeout_seconds,
    )

    python_files = discover_python_files(root, extra_excluded_dirs=set(config.exclude_dirs))
    repo = detect_repo(root, python_files, config)
    import_analysis = build_import_analysis(
        root,
        python_files,
        repo["package_roots"],
        profile=config.profile,
    )
    focus, focus_selection = resolve_focus_details(
        root,
        python_files,
        import_analysis["graph"],
        paths or [],
        diff,
    )
    symbol_data = analyze_symbols(root, python_files)
    refactor_probes = analyze_refactor_probes(
        root,
        python_files,
        enabled=not config.skip_refactor_probes,
        max_symbols=config.max_symbols,
    )
    if "dead_code_candidates" not in refactor_probes:
        refactor_probes["dead_code_candidates"] = find_dead_code_candidates(symbol_data)

    complexity = _collect_complexity(root, python_files, config)
    checks = (
        run_checks(root, config, timeout_seconds=timeout_seconds)
        if run_project_checks
        else skipped_checks("Project checks were skipped.")
    )
    architecture = analyze_architecture(root, python_files, import_analysis)
    structure = build_structure_map(root, python_files)
    focus_analysis = {
        **impact_for_focus(import_analysis, focus, root),
        "files": sorted(_rel(root, path) for path in focus),
        "direct_dependencies": _direct_dependencies(import_analysis, focus, root),
        "related_tests": _related_tests(import_analysis, focus, python_files, root),
        "selection": focus_selection,
    }

    result = {
        "schema_version": SCHEMA_VERSION,
        "root": str(root),
        "output_dir": str(output_dir),
        "generated_at": datetime.now(UTC).isoformat(),
        "config": _config_dict(config),
        "repo": _public_repo(repo),
        "structure": structure,
        "imports": import_analysis,
        "focus": focus_analysis,
        "symbols": symbol_data,
        "refactor_probes": refactor_probes,
        "calls": {"edges": _collect_call_edges(root, python_files)},
        "complexity": complexity,
        "checks": checks,
        "architecture": architecture,
    }
    result["reports"] = write_reports(result, output_dir, config)
    return result


def discover_python_files(root: Path, extra_excluded_dirs: set[str] | None = None) -> list[Path]:
    excluded = EXCLUDED_DIRS | (extra_excluded_dirs or set())
    files: list[Path] = []
    for path in root.rglob("*.py"):
        parts = set(path.relative_to(root).parts)
        if parts & excluded:
            continue
        files.append(path.resolve())
    return sorted(files)


def detect_repo(root: Path, python_files: list[Path], config: AnalysisConfig) -> dict[str, Any]:
    package_roots = _package_roots(root, python_files, config)
    return {
        "root": str(root),
        "python_file_count": len(python_files),
        "package_roots": package_roots,
        "package_root_paths": [_rel(root, path) for path in package_roots],
        "has_pyproject": (root / "pyproject.toml").exists(),
        "source_layout": _source_layout(root, package_roots),
        "module_names": _module_names(root, python_files, package_roots),
        "profile": config.profile,
    }


def resolve_focus_details(
    root: Path,
    python_files: list[Path],
    import_graph: dict[str, list[str]],
    paths: list[Path],
    diff: bool,
) -> tuple[set[Path], dict[str, Any]]:
    focus_files: set[Path] = set()
    explicit_files: set[Path] = set()
    for path in paths:
        resolved = root / path if not path.is_absolute() else path
        matched = _focus_files_for_path(resolved, python_files)
        explicit_files.update(matched)
        focus_files.update(matched)
    diff_info = {"enabled": False, "files": [], "note": ""}
    if diff:
        diff_info, diff_files = _diff_focus(root, python_files)
        focus_files.update(diff_files)
    defaulted_to_all = not focus_files
    if defaulted_to_all:
        focus_files = set(python_files)
    selection = {
        "explicit_files": sorted(_rel(root, path) for path in explicit_files),
        "diff": diff_info,
        "defaulted_to_all": defaulted_to_all,
    }
    return focus_files, selection


def _prepare_analysis(
    root: Path,
    out: Path,
    *,
    profile: str | None,
    skip_type_inference: bool,
    skip_refactor_probes: bool,
    timeout_seconds: int | None,
) -> tuple[Path, Path, AnalysisConfig]:
    root = root.resolve()
    output_dir = out.resolve()
    config = load_config(root, profile=profile)
    config = replace(
        config,
        skip_type_inference=skip_type_inference or config.skip_type_inference,
        skip_refactor_probes=skip_refactor_probes or config.skip_refactor_probes,
        check_timeout_seconds=timeout_seconds
        if timeout_seconds is not None
        else config.check_timeout_seconds,
    )
    return root, output_dir, config


def _collect_complexity(root: Path, python_files: list[Path], config: AnalysisConfig) -> dict[str, Any]:
    parse_errors: list[dict[str, Any]] = []
    largest_files: list[dict[str, Any]] = []
    high_complexity: list[dict[str, Any]] = []
    long_functions: list[dict[str, Any]] = []

    for path in python_files:
        result = _analyze_complexity_file(root, path, config, parse_errors)
        largest_files.extend(result["largest_files"])
        high_complexity.extend(result["high_complexity"])
        long_functions.extend(result["long_functions"])

    return {
        "high_complexity": sorted(high_complexity, key=lambda item: item["complexity"], reverse=True),
        "long_functions": sorted(long_functions, key=lambda item: item["length"], reverse=True),
        "largest_files": sorted(largest_files, key=lambda item: item["loc"], reverse=True)[:30],
        "parse_errors": parse_errors,
    }


def _analyze_complexity_file(
    root: Path,
    path: Path,
    config: AnalysisConfig,
    parse_errors: list[dict[str, Any]],
) -> dict[str, list[dict[str, Any]]]:
    try:
        source = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        parse_errors.append(_error_record(root, path, exc))
        return {"high_complexity": [], "long_functions": [], "largest_files": []}
    except OSError as exc:
        parse_errors.append(_error_record(root, path, exc))
        return {"high_complexity": [], "long_functions": [], "largest_files": []}

    return {
        "largest_files": _raw_file_metrics(root, path, source, parse_errors),
        "high_complexity": _complexity_blocks(root, path, source, parse_errors, config.max_complexity),
        "long_functions": _long_function_records(root, path, source, parse_errors, config.long_function_lines),
    }


def _raw_file_metrics(
    root: Path,
    path: Path,
    source: str,
    parse_errors: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    if raw_analyze is None:
        return [{"file": _rel(root, path), "loc": len(source.splitlines()), "sloc": None, "comments": None}]
    try:
        raw = raw_analyze(source)
    except Exception as exc:
        parse_errors.append(_error_record(root, path, exc))
        return []
    return [
        {
            "file": _rel(root, path),
            "loc": raw.loc,
            "sloc": raw.sloc,
            "comments": raw.comments,
        }
    ]


def _complexity_blocks(
    root: Path,
    path: Path,
    source: str,
    parse_errors: list[dict[str, Any]],
    max_complexity: int,
) -> list[dict[str, Any]]:
    if cc_visit is None:
        return []
    try:
        blocks = cc_visit(source)
    except Exception as exc:
        parse_errors.append(_error_record(root, path, exc))
        return []
    return [
        {
            "file": _rel(root, path),
            "name": block.fullname,
            "line": block.lineno,
            "end_line": getattr(block, "endline", None),
            "complexity": block.complexity,
        }
        for block in blocks
        if block.complexity >= max_complexity
    ]


def _long_function_records(
    root: Path,
    path: Path,
    source: str,
    parse_errors: list[dict[str, Any]],
    long_function_lines: int,
) -> list[dict[str, Any]]:
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        parse_errors.append(_error_record(root, path, exc))
        return []
    records = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if not node.end_lineno:
            continue
        length = node.end_lineno - node.lineno + 1
        if length >= long_function_lines:
            records.append({"file": _rel(root, path), "name": node.name, "line": node.lineno, "length": length})
    return records


def _focus_files_for_path(path: Path, python_files: list[Path]) -> set[Path]:
    if path.is_dir():
        resolved = path.resolve()
        return {file for file in python_files if _is_relative_to(file, resolved)}
    if path.suffix == ".py" and path.exists():
        return {path.resolve()}
    return set()


def _diff_focus(root: Path, python_files: list[Path]) -> tuple[dict[str, Any], set[Path]]:
    try:
        completed = subprocess.run(
            ["git", "diff", "--name-only"],
            cwd=root,
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        return {"enabled": False, "files": [], "note": str(exc)}, set()

    diff_files = []
    focus_files = set()
    known = {path.resolve(): path.resolve() for path in python_files}
    for line in completed.stdout.splitlines():
        path = (root / line).resolve()
        diff_files.append(line)
        if path in known:
            focus_files.add(path)
    return {"enabled": True, "files": diff_files, "note": ""}, focus_files


def _direct_dependencies(import_analysis: dict[str, Any], focus_files: set[Path], root: Path) -> list[str]:
    graph = import_analysis.get("graph", {})
    dependencies: set[str] = set()
    focus = {_rel(root, path) for path in focus_files}
    for file in focus:
        dependencies.update(graph.get(file, []))
    return sorted(dependencies - focus)


def _related_tests(
    import_analysis: dict[str, Any],
    focus_files: set[Path],
    python_files: list[Path],
    root: Path,
) -> list[str]:
    graph = import_analysis.get("graph", {})
    reverse = import_analysis.get("reverse_graph", {})
    focus = {_rel(root, path) for path in focus_files}
    focus_stems = {Path(path).stem for path in focus}
    files = [_rel(root, path) for path in python_files]
    return sorted(
        file
        for file in files
        if _is_test_file(Path(file))
        and _is_related_test(file, Path(file), graph, reverse, focus, focus_stems)
    )


def _is_test_file(path: Path) -> bool:
    return "test" in path.parts or path.name.startswith("test_")


def _is_related_test(
    file: str,
    path: Path,
    graph: dict[str, list[str]],
    reverse: dict[str, list[str]],
    focus: set[str],
    focus_stems: set[str],
) -> bool:
    if set(graph.get(file, [])) & focus:
        return True
    if set(reverse.get(file, [])) & focus:
        return True
    return any(stem in path.stem for stem in focus_stems)


def _collect_call_edges(root: Path, python_files: list[Path]) -> list[dict[str, Any]]:
    edges: list[dict[str, Any]] = []
    for path in python_files:
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        except (SyntaxError, UnicodeDecodeError, OSError):
            continue
        stack: list[str] = []

        class Visitor(ast.NodeVisitor):
            def visit_ClassDef(self, node: ast.ClassDef) -> None:
                stack.append(node.name)
                self.generic_visit(node)
                stack.pop()

            def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
                stack.append(node.name)
                self.generic_visit(node)
                stack.pop()

            def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
                stack.append(node.name)
                self.generic_visit(node)
                stack.pop()

            def visit_Call(self, node: ast.Call) -> None:
                callee = _call_name(node.func)
                if callee:
                    edges.append(
                        {
                            "file": _rel(root, path),
                            "caller": ".".join(stack) if stack else "<module>",
                            "callee": callee,
                            "line": node.lineno,
                        }
                    )
                self.generic_visit(node)

        Visitor().visit(tree)
    return edges


def _call_name(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        parent = _call_name(node.value)
        return f"{parent}.{node.attr}" if parent else node.attr
    return None


def _package_roots(root: Path, python_files: list[Path], config: AnalysisConfig) -> list[Path]:
    configured = _configured_package_roots(root, config)
    if configured:
        return configured

    roots = []
    for candidate in (root / "src", root):
        if candidate.exists() and any(_is_relative_to(path, candidate) for path in python_files):
            roots.append(candidate.resolve())
    return roots or [root.resolve()]


def _configured_package_roots(root: Path, config: AnalysisConfig) -> list[Path]:
    roots = []
    for item in config.package_roots:
        path = (root / item).resolve() if not Path(item).is_absolute() else Path(item).resolve()
        if path.exists():
            roots.append(path)
    return roots


def _source_layout(root: Path, package_roots: list[Path]) -> str:
    src = (root / "src").resolve()
    if any(path == src or _is_relative_to(path, src) for path in package_roots):
        return "src"
    return "flat"


def _module_names(root: Path, python_files: list[Path], package_roots: list[Path]) -> list[str]:
    names: set[str] = set()
    for path in python_files:
        for base in package_roots:
            if not _is_relative_to(path, base):
                continue
            rel = path.resolve().relative_to(base.resolve())
            if rel.parts and rel.parts[0] not in {"tests", "test"}:
                first = Path(rel.parts[0])
                names.add(first.stem if first.suffix == ".py" else first.name)
            break
    return sorted(names)


def _error_record(root: Path, path: Path, exc: BaseException) -> dict[str, Any]:
    return {
        "file": _rel(root, path),
        "error": exc.__class__.__name__,
        "message": str(exc),
    }


def _config_dict(config: AnalysisConfig) -> dict[str, Any]:
    return asdict(config)


def _public_repo(repo: dict[str, Any]) -> dict[str, Any]:
    public = dict(repo)
    public["package_roots"] = public.pop("package_root_paths")
    return public


def _is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def _rel(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()
