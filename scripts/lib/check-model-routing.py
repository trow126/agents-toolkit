#!/usr/bin/env python3
"""check-model-routing.py — routing 表（docs/contracts/model-routing.tsv）と targets の整合を検査する。

routing 表は validator が照合に使う正本で、配布しない。実行時の値は各行の targets にある。

targets の書式（1セルに複数あるときは ";" で区切る）:
  path#key[,key]  構造化された値。1つ目の key が model、2つ目が effort。
                  .toml は TOML の key（dotted 可）、.json は JSON の key（dotted 可）、
                  .md は YAML frontmatter の block-style key、それ以外は shell/env の KEY=value。
  path~anchor     文章の行。anchor を含む行がちょうど1行あり、その行に model が書かれていること。
  ~/...           live のファイル。repo の validator は検査しない（discovery が比較する）。

usage:
  check-model-routing.py <repo-root>            違反を "FAIL: " / "WARN: " / "INFO: " 行で出力する
  check-model-routing.py <repo-root> --targets  名前検査から除外する target 行を "<relpath>:<line>" で出力する
exit: 0 = 違反なし、1 = FAIL あり、2 = 使い方の誤り
"""
from __future__ import annotations

import csv
import datetime as dt
import json
import re
import sys
import tomllib
from pathlib import Path

TABLE = Path("docs/contracts/model-routing.tsv")
HEADER = ["role", "runtime", "launcher", "model", "effort", "targets", "fallback",
          "retires_at", "evidence", "verified_at", "adaptation"]
EFFORTS = {"-", "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"}
ENV_PIN = re.compile(r"^ANTHROPIC_DEFAULT_(OPUS|FABLE|SONNET|HAIKU)_MODEL$")
SETTINGS_FILES = ("claude/settings.json", "claude/managed-settings.json")


def valid_date(value: str) -> bool:
    try:
        dt.date.fromisoformat(value)
    except ValueError:
        return False
    return re.fullmatch(r"\d{4}-\d{2}-\d{2}", value) is not None


def model_token(model: str) -> re.Pattern[str]:
    return re.compile(r"(?<![A-Za-z0-9_])" + re.escape(model) + r"(?![A-Za-z0-9_])", re.I)


def unquote(value: str) -> str:
    value = re.sub(r"\s#.*$", "", value.strip()).strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value


def dotted(data: object, key: str) -> object:
    for part in key.split("."):
        if not isinstance(data, dict) or part not in data:
            return None
        data = data[part]
    return data


def line_of(text: str, pattern: str) -> int:
    for number, line in enumerate(text.split("\n"), 1):
        if re.search(pattern, line):
            return number
    return 0


def structured_value(path: Path, text: str, key: str) -> tuple[object, int]:
    """Return (value, line) for key in path; value None when absent."""
    last = key.split(".")[-1]
    if path.suffix == ".toml":
        value = dotted(tomllib.loads(text), key)
        return value, line_of(text, rf"^\s*{re.escape(last)}\s*=")
    if path.suffix == ".json":
        value = dotted(json.loads(text), key)
        return value, line_of(text, rf'"{re.escape(last)}"\s*:')
    if path.suffix == ".md":
        match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        if not match:
            return None, 0
        for number, line in enumerate(match.group(1).split("\n"), 2):
            km = re.match(rf"^{re.escape(key)}:\s*(.*)$", line)
            if km:
                return unquote(km.group(1)), number
        return None, 0
    hits = [(n, m) for n, line in enumerate(text.split("\n"), 1)
            if (m := re.match(rf"^\s*(?:export\s+)?{re.escape(key)}=(.*)$", line))]
    if len(hits) != 1:
        return None, 0
    return unquote(hits[0][1].group(1)), hits[0][0]


def load_rows(root: Path, out: list[str]) -> list[dict[str, str]]:
    path = root / TABLE
    if not path.is_file():
        out.append(f"FAIL: routing table missing: {TABLE}")
        return []
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle, delimiter="\t")
        rows = list(reader)
    if not rows or rows[0] != HEADER:
        out.append(f"FAIL: {TABLE}: header must be {'/'.join(HEADER)}")
        return []
    parsed = []
    for number, fields in enumerate(rows[1:], 2):
        if not fields or all(not f.strip() for f in fields):
            continue
        if len(fields) != len(HEADER):
            out.append(f"FAIL: {TABLE}:{number}: expected {len(HEADER)} columns, got {len(fields)}")
            continue
        row = dict(zip(HEADER, (f.strip() for f in fields)))
        row["_line"] = str(number)
        parsed.append(row)
    return parsed


def check(root: Path) -> tuple[list[str], set[tuple[str, int]]]:
    out: list[str] = []
    excluded: set[tuple[str, int]] = set()
    rows = load_rows(root, out)
    roles: set[str] = set()
    owners: dict[str, list[str]] = {}
    env_targets: dict[tuple[str, str], str] = {}

    for row in rows:
        where = f"{TABLE}:{row['_line']} ({row['role']})"
        if not re.fullmatch(r"[a-z][a-z0-9-]*", row["role"]):
            out.append(f"FAIL: {where}: role must match [a-z][a-z0-9-]*")
        if row["role"] in roles:
            out.append(f"FAIL: {where}: duplicate role")
        roles.add(row["role"])
        if row["runtime"] not in {"claude", "codex"}:
            out.append(f"FAIL: {where}: runtime must be claude or codex")
        for field in ("launcher", "model", "targets", "evidence"):
            if not row[field]:
                out.append(f"FAIL: {where}: {field} must not be empty")
        if row["effort"] not in EFFORTS:
            out.append(f"FAIL: {where}: effort must be one of {sorted(EFFORTS)}")
        retires = row["retires_at"]
        if retires and not (valid_date(retires) or (retires.startswith("not-before:") and valid_date(retires[11:]))):
            out.append(f"FAIL: {where}: retires_at must be empty, YYYY-MM-DD, or not-before:YYYY-MM-DD")
        if not valid_date(row["verified_at"]):
            out.append(f"FAIL: {where}: verified_at must be YYYY-MM-DD")

        for target in (t.strip() for t in row["targets"].split(";") if t.strip()):
            if target.startswith("~/"):
                out.append(f"INFO: {where}: live target {target} is compared by discovery, not by this validator")
                continue
            if "#" in target:
                rel, keys_text = target.split("#", 1)
                keys = [k.strip() for k in keys_text.split(",") if k.strip()]
                owners.setdefault(rel, []).append(row["role"])
                path = root / rel
                if not path.is_file():
                    out.append(f"FAIL: {where}: target file missing: {rel}")
                    continue
                if not 1 <= len(keys) <= 2:
                    out.append(f"FAIL: {where}: target {target} must name 1 or 2 keys (model[,effort])")
                    continue
                if len(keys) == 2 and row["effort"] == "-":
                    out.append(f"FAIL: {where}: target {target} names an effort key but the row effort is '-'")
                    continue
                text = path.read_text(encoding="utf-8")
                try:
                    expected = [row["model"]] + ([row["effort"]] if len(keys) == 2 else [])
                    for key, want in zip(keys, expected):
                        value, line = structured_value(path, text, key)
                        if value is None:
                            out.append(f"FAIL: {where}: {rel}: key {key} not found (or not unique)")
                            continue
                        if key.startswith("env.") and path.name.endswith(".json"):
                            env_targets[(rel, key[4:])] = row["role"]
                        if str(value) != want:
                            out.append(f"FAIL: {where}: {rel}:{line}: {key}={value} does not match routing table value {want}")
                        excluded.add((rel, line))
                except (tomllib.TOMLDecodeError, json.JSONDecodeError) as exc:
                    out.append(f"FAIL: {where}: {rel}: cannot parse: {exc}")
            elif "~" in target:
                rel, anchor = target.split("~", 1)
                owners.setdefault(rel, []).append(row["role"])
                path = root / rel
                if not path.is_file():
                    out.append(f"FAIL: {where}: target file missing: {rel}")
                    continue
                lines = path.read_text(encoding="utf-8").split("\n")
                hits = [n for n, line in enumerate(lines, 1) if anchor in line]
                if len(hits) != 1:
                    out.append(f"FAIL: {where}: {rel}: anchor '{anchor}' must match exactly one line (found {len(hits)})")
                    continue
                if not model_token(row["model"]).search(lines[hits[0] - 1]):
                    out.append(f"FAIL: {where}: {rel}:{hits[0]}: line does not state routing table model {row['model']}")
                excluded.add((rel, hits[0]))
            else:
                out.append(f"FAIL: {where}: target {target} must use path#key, path~anchor, or ~/live")

    for pattern in ("claude/agents/*.md", "codex/agents/*.toml"):
        for agent in sorted(root.glob(pattern)):
            rel = agent.relative_to(root).as_posix()
            count = len(owners.get(rel, []))
            if count != 1:
                out.append(f"FAIL: agent file {rel} must belong to exactly one routing row (found {count})")

    for rel in SETTINGS_FILES:
        path = root / rel
        if not path.is_file():
            continue
        try:
            env = json.loads(path.read_text(encoding="utf-8")).get("env") or {}
        except json.JSONDecodeError:
            continue
        for key in sorted(k for k in env if ENV_PIN.match(k)):
            if (rel, key) not in env_targets:
                out.append(f"FAIL: env pin {rel}:env.{key} is not a routing table target")

    return out, excluded


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3) or (len(argv) == 3 and argv[2] != "--targets"):
        print(__doc__, file=sys.stderr)
        return 2
    root = Path(argv[1])
    out, excluded = check(root)
    if len(argv) == 3:
        for rel, line in sorted(excluded):
            print(f"{rel}:{line}")
        return 0
    if out:
        print("\n".join(out))
    return 1 if any(line.startswith("FAIL:") for line in out) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
