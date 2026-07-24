from __future__ import annotations

import ast
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class CacheEntry:
    """Result of attempting to load and parse one Python source file.

    `tree` and `source` are None when reading or parsing failed; in that case
    `error` is populated with a structured record that callers can append to
    their own `parse_errors` list to preserve the existing report shape.
    """

    path: Path
    tree: ast.AST | None
    source: str | None
    error: dict[str, Any] | None


class AstCache:
    """Single-parse AST cache shared across analysis phases.

    Reads each Python file at most once and parses it at most once per cache
    instance. Phases that need the AST or source must use `get(path)` instead
    of calling `path.read_text` / `ast.parse` directly. Errors are not raised
    from `get`; they are surfaced via `entry.error` so each phase can decide
    how to record them.
    """

    def __init__(self) -> None:
        self._entries: dict[Path, CacheEntry] = {}

    def get(self, path: Path) -> CacheEntry:
        key = path.resolve()
        cached = self._entries.get(key)
        if cached is None:
            cached = self._load(key)
            self._entries[key] = cached
        return cached

    def _load(self, path: Path) -> CacheEntry:
        try:
            source = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError) as exc:
            return CacheEntry(path=path, tree=None, source=None, error=_error(path, exc))
        try:
            tree = ast.parse(source, filename=str(path))
        except SyntaxError as exc:
            return CacheEntry(path=path, tree=None, source=source, error=_error(path, exc))
        return CacheEntry(path=path, tree=tree, source=source, error=None)


def _error(path: Path, exc: BaseException) -> dict[str, Any]:
    return {
        "path": path,
        "error": exc.__class__.__name__,
        "message": str(exc),
    }
