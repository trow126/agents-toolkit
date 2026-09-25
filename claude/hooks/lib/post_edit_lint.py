#!/usr/bin/env python3
"""Deterministic file checks for the PostToolUse Edit/Write lint hook."""

from __future__ import annotations

import ast
import json
import re
import sys
import tokenize
from dataclasses import dataclass
from pathlib import Path

HEADING_RE = re.compile(r"^#{1,6}(?!#)(?:[ \t]+|$)")
FENCE_OPEN_RE = re.compile(r"^[ \t]{0,3}(`{3,}|~{3,})")
TOOL_STAR_RE = re.compile(r"^[A-Za-z]+:\*$")
NO_SPACE_WILDCARD_RE = re.compile(r"^[A-Za-z]+\([^)]*[^ )]\*\)$")
SETTINGS_NAMES = {"settings.json", "settings.local.json", "managed-settings.json"}


@dataclass(frozen=True)
class Violation:
    line: int
    problem: str
    fix: str


def is_blank(lines: list[str], ignored: list[bool], index: int) -> bool:
    """Treat file and ignored-region boundaries as blank."""
    return (
        index < 0 or index >= len(lines) or ignored[index] or not lines[index].strip()
    )


def front_matter_end(lines: list[str]) -> int:
    if not lines or lines[0].strip() != "---":
        return -1
    for index in range(1, len(lines)):
        if lines[index].strip() in {"---", "..."}:
            return index
    return len(lines) - 1


def markdown_violations(path: Path) -> list[Violation]:
    lines = path.read_text(encoding="utf-8").splitlines()
    ignored = [False] * len(lines)
    yaml_end = front_matter_end(lines)
    if yaml_end >= 0:
        for index in range(yaml_end + 1):
            ignored[index] = True

    fences: list[tuple[int, int]] = []
    index = yaml_end + 1
    while index < len(lines):
        match = FENCE_OPEN_RE.match(lines[index])
        if not match:
            index += 1
            continue
        marker = match.group(1)
        closing_re = re.compile(
            rf"^[ \t]{{0,3}}{re.escape(marker[0])}{{{len(marker)},}}[ \t]*$"
        )
        closing = len(lines) - 1
        for candidate in range(index + 1, len(lines)):
            if closing_re.match(lines[candidate]):
                closing = candidate
                break
        fences.append((index, closing))
        for fenced_line in range(index, closing + 1):
            ignored[fenced_line] = True
        index = closing + 1

    violations: list[Violation] = []
    for opening, closing in fences:
        if not is_blank(lines, ignored, opening - 1):
            violations.append(
                Violation(
                    opening + 1,
                    "Markdown コードブロックの前に空行がありません",
                    "コードブロックの直前に空行を追加する",
                )
            )
        if not is_blank(lines, ignored, closing + 1):
            violations.append(
                Violation(
                    closing + 1,
                    "Markdown コードブロックの後に空行がありません",
                    "コードブロックの直後に空行を追加する",
                )
            )

    for heading in range(len(lines)):
        if ignored[heading] or not HEADING_RE.match(lines[heading]):
            continue
        if not is_blank(lines, ignored, heading - 1):
            violations.append(
                Violation(
                    heading + 1,
                    "Markdown 見出しの前に空行がありません",
                    "見出しの直前に空行を追加する",
                )
            )
        if not is_blank(lines, ignored, heading + 1):
            violations.append(
                Violation(
                    heading + 1,
                    "Markdown 見出しの後に空行がありません",
                    "見出しの直後に空行を追加する",
                )
            )

    index = 0
    while index < len(lines):
        if ignored[index] or not lines[index].startswith("|"):
            index += 1
            continue
        start = index
        while (
            index + 1 < len(lines)
            and not ignored[index + 1]
            and lines[index + 1].startswith("|")
        ):
            index += 1
        end = index
        if not is_blank(lines, ignored, start - 1):
            violations.append(
                Violation(
                    start + 1,
                    "Markdown テーブルの前に空行がありません",
                    "テーブルの直前に空行を追加する",
                )
            )
        if not is_blank(lines, ignored, end + 1):
            violations.append(
                Violation(
                    end + 1,
                    "Markdown テーブルの後に空行がありません",
                    "テーブルの直後に空行を追加する",
                )
            )
        index += 1

    return sorted(violations, key=lambda item: item.line)


def python_violations(path: Path) -> list[Violation]:
    with tokenize.open(path) as handle:
        source = handle.read()
    try:
        ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        return [
            Violation(
                exc.lineno or 1,
                f"Python 構文エラー: {exc.msg}",
                "構文を修正して ast.parse が成功する状態にする",
            )
        ]
    return []


def permission_entry_lines(source: str) -> dict[tuple[str, int], int]:
    """Map permission array indexes to source lines with a small JSON walker."""
    decoder = json.JSONDecoder()
    positions: dict[tuple[str, int], int] = {}

    def skip_space(offset: int) -> int:
        while offset < len(source) and source[offset].isspace():
            offset += 1
        return offset

    def parse_value(offset: int, path: tuple[str | int, ...]) -> int:
        offset = skip_space(offset)
        start = offset
        if source[offset] == "{":
            offset = skip_space(offset + 1)
            if source[offset] == "}":
                return offset + 1
            while True:
                key, offset = decoder.raw_decode(source, offset)
                offset = skip_space(offset)
                if not isinstance(key, str) or source[offset] != ":":
                    raise ValueError("invalid JSON object")
                offset = parse_value(offset + 1, (*path, key))
                offset = skip_space(offset)
                if source[offset] == "}":
                    return offset + 1
                if source[offset] != ",":
                    raise ValueError("invalid JSON object separator")
                offset = skip_space(offset + 1)
        if source[offset] == "[":
            offset = skip_space(offset + 1)
            if source[offset] == "]":
                return offset + 1
            index = 0
            while True:
                offset = parse_value(offset, (*path, index))
                offset = skip_space(offset)
                if source[offset] == "]":
                    return offset + 1
                if source[offset] != ",":
                    raise ValueError("invalid JSON array separator")
                offset = skip_space(offset + 1)
                index += 1

        value, end = decoder.raw_decode(source, offset)
        if (
            isinstance(value, str)
            and len(path) == 3
            and path[0] == "permissions"
            and path[1] in {"allow", "ask", "deny"}
            and isinstance(path[2], int)
        ):
            positions[(path[1], path[2])] = source.count("\n", 0, start) + 1
        return end

    parse_value(0, ())
    return positions


def settings_violations(path: Path) -> list[Violation]:
    source = path.read_text(encoding="utf-8")
    data = json.loads(source)
    if not isinstance(data, dict):
        return []
    permissions = data.get("permissions")
    if not isinstance(permissions, dict):
        return []

    entry_lines = permission_entry_lines(source)

    violations: list[Violation] = []
    for array_name in ("allow", "ask", "deny"):
        entries = permissions.get(array_name)
        if not isinstance(entries, list):
            continue
        for index, entry in enumerate(entries):
            if not isinstance(entry, str):
                continue
            if TOOL_STAR_RE.fullmatch(entry):
                tool = entry.removesuffix(":*")
                violations.append(
                    Violation(
                        entry_lines.get((array_name, index), 1),
                        f'permissions.{array_name} の "{entry}" は無効な Tool:* 構文です',
                        f'":*" を外して "{tool}" の形式にする',
                    )
                )
            elif (
                array_name == "allow"
                and entry.startswith("Bash(")
                and NO_SPACE_WILDCARD_RE.fullmatch(entry)
                and not entry.endswith(":*)")
            ):
                # prefix matching (word boundary) applies to Bash rules only;
                # file-tool rules such as Edit(**) / Read(**) are path globs
                violations.append(
                    Violation(
                        entry_lines.get((array_name, index), 1),
                        f'permissions.allow の "{entry}" は no-space wildcard です',
                        "word boundary のある trailing space-star に直す",
                    )
                )
    return sorted(violations, key=lambda item: item.line)


def is_claude_settings(path: Path) -> bool:
    if path.name not in SETTINGS_NAMES:
        return False
    absolute = path.absolute()
    repo_root = Path(__file__).resolve().parents[3]
    return ".claude" in absolute.parts or absolute.parent == repo_root / "claude"


def lint(path: Path) -> list[Violation]:
    if path.suffix == ".md":
        return markdown_violations(path)
    if path.suffix == ".py":
        return python_violations(path)
    if is_claude_settings(path):
        return settings_violations(path)
    return []


APPLY_PATCH_FILE_RE = re.compile(r"^\*\*\* (?:Add File|Update File|Move to): (.+)$", re.M)


def apply_patch_hook() -> int:
    """Codex PostToolUse hook for apply_patch: lint the files named in tool_input.command.

    Exit 2 with the violations on stderr feeds them back to the model (Codex hooks
    contract); malformed input or internal errors stay fail-open (exit 0).
    """
    try:
        event = json.loads(sys.stdin.read() or "{}")
        patch = (event.get("tool_input") or {}).get("command")
        if not isinstance(patch, str):
            return 0
        base = Path(event.get("cwd") or ".")
        reported = False
        for name in dict.fromkeys(m.strip() for m in APPLY_PATCH_FILE_RE.findall(patch)):
            path = Path(name) if Path(name).is_absolute() else base / name
            if not path.is_file():
                continue
            for violation in lint(path):
                print(
                    f"post-edit-lint: {name}:{violation.line}: {violation.problem} — {violation.fix}",
                    file=sys.stderr,
                )
                reported = True
        if reported:
            print("意図的な場合はレポートにその理由を書くこと。", file=sys.stderr)
            return 2
        return 0
    except Exception:
        return 0


def main() -> int:
    if sys.argv[1:] == ["--apply-patch-hook"]:
        return apply_patch_hook()
    try:
        if len(sys.argv) != 2:
            return 0
        path = Path(sys.argv[1])
        violations = lint(path)
        if not violations:
            return 0
        for violation in violations:
            print(
                f"post-edit-lint: {path}:{violation.line}: "
                f"{violation.problem} — {violation.fix}",
                file=sys.stderr,
            )
        print("意図的な場合はレポートにその理由を書くこと。", file=sys.stderr)
        return 2
    except Exception:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
