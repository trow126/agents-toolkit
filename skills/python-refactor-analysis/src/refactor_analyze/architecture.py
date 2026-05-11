from __future__ import annotations

from pathlib import Path
from typing import Any


def analyze_architecture(root: Path, python_files: list[Path], import_graph: dict[str, Any]) -> dict[str, Any]:
    packages = _top_level_packages(root, python_files)
    graph = import_graph.get("graph", {})
    fan_in: dict[str, int] = {path: 0 for path in graph}
    fan_out: dict[str, int] = {}
    for source, targets in graph.items():
        fan_out[source] = len(targets)
        for target in targets:
            fan_in[target] = fan_in.get(target, 0) + 1

    hotspots = sorted(
        (
            {"file": path, "fan_in": fan_in.get(path, 0), "fan_out": fan_out.get(path, 0)}
            for path in set(fan_in) | set(fan_out)
        ),
        key=lambda item: (item["fan_in"] + item["fan_out"], item["fan_in"]),
        reverse=True,
    )[:20]

    return {
        "packages": packages,
        "entrypoints": _entrypoints(root),
        "cycles": import_graph.get("cycles", []),
        "hotspots": hotspots,
    }


def _top_level_packages(root: Path, python_files: list[Path]) -> list[dict[str, Any]]:
    packages: dict[str, int] = {}
    for path in python_files:
        try:
            rel = path.resolve().relative_to(root.resolve())
        except ValueError:
            continue
        if len(rel.parts) >= 2:
            packages[rel.parts[0]] = packages.get(rel.parts[0], 0) + 1
    return [{"name": name, "python_files": count} for name, count in sorted(packages.items())]


def _entrypoints(root: Path) -> list[str]:
    candidates = []
    for name in ("pyproject.toml", "setup.cfg", "setup.py"):
        if (root / name).exists():
            candidates.append(name)
    for path in root.glob("**/__main__.py"):
        candidates.append(path.relative_to(root).as_posix())
    return sorted(candidates)
