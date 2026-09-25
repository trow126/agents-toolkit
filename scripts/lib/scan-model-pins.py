#!/usr/bin/env python3
"""scan-model-pins.py — model 指定のスキャン（validator と metrics の共有 helper）。

対応構文を限定した parser である（実 YAML parser ではない）:
  - agent frontmatter は canonical block-style（`key: value` 行）のみ対応。
    quoted key（`"model":`）・flow mapping（`{...}`）等の非対応構文を検出した場合は
    **明示エラーで非ゼロ終了**する（fail-closed。黙って 0 件と報告しない — H-001）。
  - 値側は plain / single-quoted / double-quoted / 前後空白 / inline comment を正規化する。
  - Codex custom agent TOML は tomllib でparseし、decode不能・parse不能を
    明示エラーで非ゼロ終了する。

usage: scan-model-pins.py <repo-root>
       scan-model-pins.py --names <repo-root>
output: <relpath>:<line>:<kind>:<normalized-value> を1行ずつ
        （kind = pin | runtime-pin | alias | codex-model | other）
  pin         = 完全モデル名（claude- で始まる値）
  runtime-pin = claude/settings.json の model キーに限る完全モデル名。/model コマンドが
                正式な挙動として完全モデル名を書き込むため、governance 上の pin とは区別する
  alias       = sonnet / opus / haiku / fable / inherit / default / best
exit 0（スキャン自体の失敗のみ非ゼロ）

--names: routing 表の規則（2026-09-25 近代化 Phase 2）に従い、manifest で配布されるファイルの
  モデル名を検出する。対象は SKILL.md・references/*.md・claude/CLAUDE.md・codex/AGENTS.md・
  shared/rules/*.md・claude/agents/*.md・codex/agents/*.toml・codex/skills/*/scripts/*.sh。
  routing 表の targets の行（scripts/lib/check-model-routing.py --targets）は除外する。
  output: <relpath>:<line>:name:<matched-text> を1行ずつ（0件なら何も出力しない）
"""
import importlib.util
import json
import re
import subprocess
import sys
import tomllib
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
    if value.startswith("gpt-"):
        return "codex-model"
    if value in ALIASES:
        return "alias"
    return "other"


MODEL_NAME = re.compile(
    r"claude-(?:opus|sonnet|haiku|fable)\S*|gpt-\d\S*"
    r"|(?<![A-Za-z0-9_])(?:opus|sonnet|haiku|fable)(?![A-Za-z0-9_])",
    re.I,
)


def in_name_scope(rel: str) -> bool:
    path = Path(rel)
    if rel in ("claude/CLAUDE.md", "codex/AGENTS.md"):
        return True
    if path.suffix == ".md" and (path.name == "SKILL.md" or "references" in path.parts[:-1]):
        return True
    if path.suffix == ".md" and rel.startswith(("shared/rules/", "claude/agents/")) and len(path.parts) == 3:
        return True
    if path.suffix == ".toml" and rel.startswith("codex/agents/") and len(path.parts) == 3:
        return True
    return re.fullmatch(r"codex/skills/[^/]+/scripts/[^/]+\.sh", rel) is not None


def scan_names(root: Path) -> int:
    checker = Path(__file__).with_name("check-model-routing.py")
    spec = importlib.util.spec_from_file_location("check_model_routing", checker)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    _, excluded = module.check(root)

    sources = []
    for raw in (root / "install" / "manifest.tsv").read_text(encoding="utf-8").splitlines():
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("\t")
        if len(fields) == 3:
            sources.append(fields[1])
    tracked = subprocess.run(
        ["git", "-C", str(root), "ls-files"], capture_output=True, text=True, check=True
    ).stdout.splitlines()
    results = []
    for rel in tracked:
        if not any(rel == s or rel.startswith(s + "/") for s in sources) or not in_name_scope(rel):
            continue
        path = root / rel
        if not path.is_file():
            continue
        try:
            lines = path.read_text(encoding="utf-8").split("\n")
        except UnicodeDecodeError as exc:
            print(f"ERROR: {rel}: not valid UTF-8: {exc}", file=sys.stderr)
            return 1
        for number, line in enumerate(lines, 1):
            if (rel, number) in excluded:
                continue
            for match in MODEL_NAME.finditer(line):
                results.append(f"{rel}:{number}:name:{match.group(0)}")
    if results:
        print("\n".join(results))
    return 0


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--names":
        return scan_names(Path(sys.argv[2]))
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

    # 3. codex/agents/*.toml（tomllib。parse errorはfail-closed）
    for f in sorted(root.glob("codex/agents/*.toml")):
        try:
            text = f.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            print(f"ERROR: {f.relative_to(root)}: not valid UTF-8: {exc}", file=sys.stderr)
            return 1
        try:
            data = tomllib.loads(text)
        except tomllib.TOMLDecodeError as exc:
            print(f"ERROR: {f.relative_to(root)}: invalid TOML: {exc}", file=sys.stderr)
            return 1
        model = data.get("model")
        if isinstance(model, str):
            v = normalize(model)
            lineno = next(
                (
                    i
                    for i, line in enumerate(text.split("\n"), start=1)
                    if re.match(r"^\s*model\s*=", line)
                ),
                0,
            )
            results.append(f"{f.relative_to(root)}:{lineno}:{classify(v)}:{v}")

    print("\n".join(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
