#!/usr/bin/env python3
"""scan-model-pins.py — model 指定の構造的スキャン（validator と metrics の共有 helper）。

quoted / plain / single-quoted / 前後空白 / inline comment を正規化して分類する
（grep の literal 前提による検査漏れ対策。2026-07-23 再々レビュー H-001）。

usage: scan-model-pins.py <repo-root>
output: <relpath>:<line>:<kind>:<normalized-value> を1行ずつ（kind = pin | alias | other）
  pin   = 完全モデル名（claude- で始まる値）
  alias = sonnet / opus / haiku / fable / inherit / default / best
exit 0（スキャン自体の失敗のみ非ゼロ）
"""
import json
import re
import sys
from pathlib import Path

ALIASES = {"sonnet", "opus", "haiku", "fable", "inherit", "default", "best"}


def normalize(raw: str) -> str:
    v = raw.strip()
    # inline comment を除去（YAML: " # ..." / TOML: " # ...")
    v = re.sub(r"\s#.*$", "", v).strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
        v = v[1:-1].strip()
    return v


def classify(value: str) -> str:
    if value.startswith("claude-"):
        return "pin"
    if value in ALIASES:
        return "alias"
    return "other"


def main() -> int:
    root = Path(sys.argv[1])
    results = []

    # 1. agent frontmatter（YAML の model: 行。quoted scalar 対応）
    for f in sorted(root.glob("claude/agents/*.md")):
        text = f.read_text(encoding="utf-8")
        m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        if not m:
            continue
        offset = 1
        for i, line in enumerate(m.group(1).split("\n"), start=offset + 1):
            km = re.match(r"^model:\s*(.+)$", line)
            if km:
                v = normalize(km.group(1))
                results.append(f"{f.relative_to(root)}:{i}:{classify(v)}:{v}")

    # 2. claude/settings.json と claude/bypass-profile.json（JSON parse）
    for name in ("claude/settings.json", "claude/bypass-profile.json"):
        f = root / name
        if not f.is_file():
            continue
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            print(f"ERROR: {name}: invalid JSON: {exc}", file=sys.stderr)
            return 1
        model = data.get("model")
        if isinstance(model, str):
            v = normalize(model)
            # 行番号は "model" キーの出現行（表示用）
            lineno = 0
            for i, line in enumerate(f.read_text(encoding="utf-8").split("\n"), start=1):
                if re.search(r'"model"\s*:', line):
                    lineno = i
                    break
            results.append(f"{name}:{lineno}:{classify(v)}:{v}")

    # 3. codex/*.toml（tomllib。parse 不能時は正規表現 fallback で quoted/literal string 両対応）
    for f in sorted(root.glob("codex/*.toml")):
        text = f.read_text(encoding="utf-8")
        values = []
        try:
            import tomllib

            data = tomllib.loads(text)

            def walk(node):
                if isinstance(node, dict):
                    for k, v in node.items():
                        if k == "model" and isinstance(v, str):
                            values.append(v)
                        else:
                            walk(v)
                elif isinstance(node, list):
                    for item in node:
                        walk(item)

            walk(data)
        except Exception:
            for line in text.split("\n"):
                km = re.match(r"""^\s*model\s*=\s*(.+)$""", line)
                if km:
                    values.append(normalize(km.group(1)))
        for v in values:
            v = normalize(v)
            lineno = 0
            for i, line in enumerate(text.split("\n"), start=1):
                if re.match(r"^\s*model\s*=", line) and v in line:
                    lineno = i
                    break
            results.append(f"{f.relative_to(root)}:{lineno}:{classify(v)}:{v}")

    print("\n".join(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
