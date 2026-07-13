from __future__ import annotations

from collections import defaultdict
from pathlib import Path
from typing import Any


def build_structure_map(root: Path, python_files: list[Path]) -> dict[str, Any]:
    tree: dict[str, Any] = {}
    by_directory: dict[str, list[str]] = defaultdict(list)
    for path in sorted(python_files):
        rel = path.resolve().relative_to(root.resolve())
        by_directory[rel.parent.as_posix()].append(rel.name)
        cursor = tree
        for part in rel.parts[:-1]:
            cursor = cursor.setdefault(part, {})
        cursor[rel.name] = "file"

    return {
        "status": "ok",
        "file_count": len(python_files),
        "directories": {key: sorted(value) for key, value in sorted(by_directory.items())},
        "tree": tree,
    }
