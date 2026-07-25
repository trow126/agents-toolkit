#!/usr/bin/env python3
"""scan-model-pins.py — model 指定のスキャン（validator と metrics の共有 helper）。

対応構文を限定した parser である（実 YAML parser ではない）:
  - agent frontmatter は canonical block-style（`key: value` 行）のみ対応。
    quoted key（`"model":`）・flow mapping（`{...}`）等の非対応構文を検出した場合は
    **明示エラーで非ゼロ終了**する（fail-closed。黙って 0 件と報告しない — H-001）。
  - 値側は plain / single-quoted / double-quoted / 前後空白 / inline comment を正規化する。
  - decode 不能・parse 不能も明示エラーで非ゼロ終了する。

usage: scan-model-pins.py <repo-root>
output: <relpath>:<line>:<kind>:<normalized-value> を1行ずつ（kind = pin | runtime-pin | alias | other）
  pin         = 完全モデル名（claude- で始まる値）
  runtime-pin = claude/settings.json の model キーに限る完全モデル名。/model コマンドが
                正式な挙動として完全モデル名を書き込むため、governance 上の pin とは区別する
  alias       = sonnet / opus / haiku / fable / inherit / default / best
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

    # 1. agent frontmatter（canonical block-style のみ。非対応構文は fail-closed）
    for f in sorted(root.glob("claude/agents/*.md")):
        try:
            text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            print(f"ERROR: {f.relative_to(root)}: not valid UTF-8: {exc}", file=sys.stderr)
            return 1
        m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        if not m:
            continue
        offset = 1
        for i, line in enumerate(m.group(1).split("\n"), start=offset + 1):
            stripped = line.strip()
            if re.match(r"^[\"']", stripped) or stripped.startswith("{") or stripped.startswith("["):
                print(
                    f"ERROR: {f.relative_to(root)}:{i}: non-canonical YAML frontmatter "
                    f"(quoted key / flow style は本 parser の対応範囲外。block-style 'key: value' に書き換えるか、"
                    f"実 YAML parser 対応が必要): {stripped[:60]}",
                    file=sys.stderr,
                )
                return 1
            km = re.match(r"^model:\s*(.+)$", line)
            if km:
                v = normalize(km.group(1))
                results.append(f"{f.relative_to(root)}:{i}:{classify(v)}:{v}")

    # 2. claude/settings.json（JSON parse）
    for name in ("claude/settings.json",):
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
            # /model コマンドは完全モデル名をこのキーへ書き込む（ツールの正式な挙動）。
            # ユーザーの runtime 選択であり governance 上の pin ではないため区別する。
            kind = classify(v)
            if kind == "pin":
                kind = "runtime-pin"
            results.append(f"{name}:{lineno}:{kind}:{v}")

    # 3. codex/*.toml（tomllib。parse 不能時は正規表現 fallback で quoted/literal string 両対応）
    for f in sorted(root.glob("codex/*.toml")):
        try:
            text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            print(f"ERROR: {f.relative_to(root)}: not valid UTF-8: {exc}", file=sys.stderr)
            return 1
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
