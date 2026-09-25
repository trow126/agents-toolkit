#!/usr/bin/env python3
"""build-skill-trigger-eval.py — skill の起動精度を測る `claude plugin eval` の suite を組み立てる（K8）。

manifest が Claude に配布する skill のうち、モデルが自分の判断で起動できるもの（manual-only と、
settings の skillOverrides が off / user-invocable-only のものを除く）を、一時的な plugin `atk` に
copy する。各 case は依頼の prompt 1つと、期待する skill が起動したこと、紛らわしい隣の skill が
起動しなかったことを判定する `tool_used` grader を持つ。モデルは呼ばない。実行は integration 環境
でだけ行う（docs/runbooks/integration-environment.md）。

usage: build-skill-trigger-eval.py OUT_DIR [--repo DIR] [--settings FILE]
  --settings  skillOverrides を読む settings（既定: ~/.claude/settings.json。無ければ override なし）
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path

# name: (prompt, expected skill or None, skills that must not fire)
CASES = {
    "article-style": ("Zenn に公開する、uv の使い方を紹介する記事の導入部を書いて。", "article-style", []),
    "branch-cleanup": ("PR がリモートでマージされたから、ローカルのブランチを整理して。", "branch-cleanup", ["git-operations"]),
    "implementation-quality": ("src/parser.py の parse_date が空文字で例外を投げるバグを直して、テストも足して。", "implementation-quality", ["gh-start"]),
    "git-operations": ("今の変更を stage して、適切なメッセージで commit して。", "git-operations", ["gh-finish", "gh-start"]),
    "gh-start": ("Issue #42 の実装を始めて。", "gh-start", ["gh-codex-drive"]),
    "gh-codex-drive": ("Issue #42 の実装は Codex に任せて。", "gh-codex-drive", ["gh-start"]),
    # D3①: Codex への委任はユーザーの明示指示だけ
    "no-implicit-codex": ("Issue #42 を実装して。量が多いので効率よく進めて。", None, ["gh-codex-drive"]),
    "gh-finish": ("Issue #42 が完了したよ。PR は作らずに仕上げて。", "gh-finish", ["git-operations"]),
    "gh-issue-close": ("Issue #42 を close して。", "gh-issue", ["issue-writing"]),
    "gh-issue-create": ("issue-body.md の内容で Issue を起票して。", "gh-issue", []),
    "issue-writing": ("ログイン画面のタイムアウトの不具合について、Issue の本文を下書きして。まだ起票はしない。", "issue-writing", ["gh-issue"]),
    "model-routing": ("さっきの workflow の subagent が、実際にどのモデルで動いたか確認して。", "model-routing", []),
}
HIDDEN_OVERRIDES = ("off", "user-invocable-only")


def claude_skills(repo: Path) -> dict[str, Path]:
    skills = {}
    for line in (repo / "install/manifest.tsv").read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if len(fields) == 3 and fields[0] == "link-dir" and fields[2].startswith(".claude/skills/"):
            skills[fields[2].rsplit("/", 1)[1]] = repo / fields[1]
    return skills


def model_invocable(skill_dir: Path) -> bool:
    text = (skill_dir / "SKILL.md").read_text(encoding="utf-8")
    front = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    return not (front and re.search(r"^disable-model-invocation:\s*true\s*$", front.group(1), re.M))


def grader(skill: str, fired: bool) -> str:
    bounds = "min: 1" if fired else "min: 0\nmax: 0"
    return (f"---\ntype: tool_used\ntool: Skill\ninput_match: '\"skill\"\\s*:\\s*\"(?:[\\w-]+:)?{skill}\"'\n{bounds}\nweight: 1\n---\n\n"
            f"The {skill} skill {'fires' if fired else 'does not fire'}.\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("out")
    parser.add_argument("--repo", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--settings", default=str(Path.home() / ".claude/settings.json"))
    args = parser.parse_args()
    repo, out = Path(args.repo).resolve(), Path(args.out)
    settings = Path(args.settings)
    overrides = (json.loads(settings.read_text(encoding="utf-8")).get("skillOverrides") or {}) if settings.is_file() else {}

    included, excluded = {}, {}
    for name, source in sorted(claude_skills(repo).items()):
        if not model_invocable(source):
            excluded[name] = "manual-only"
        elif overrides.get(name) in HIDDEN_OVERRIDES:
            excluded[name] = f"skillOverrides {overrides[name]}"
        else:
            included[name] = source

    if out.exists():
        shutil.rmtree(out)
    (out / ".claude-plugin").mkdir(parents=True)
    (out / ".claude-plugin/plugin.json").write_text(json.dumps({"name": "atk", "version": "0.0.1"}) + "\n", encoding="utf-8")
    for name, source in included.items():
        shutil.copytree(source, out / "skills" / name, symlinks=False,
                        ignore=shutil.ignore_patterns("__pycache__", ".venv", ".pytest_cache", "tests"))

    written, skipped = [], []
    for case, (prompt, expected, forbidden) in CASES.items():
        if expected and expected not in included:
            skipped.append(f"{case} ({expected} is not model-invocable here)")
            continue
        forbidden = [s for s in forbidden if s in included]
        if not expected and not forbidden:
            skipped.append(f"{case} (nothing to grade)")
            continue
        d = out / "evals" / case
        (d / "graders").mkdir(parents=True)
        (d / "prompt.md").write_text(f"---\nname: {case}\ntags: [skill-trigger]\nmax_turns: 2\ntimeout_seconds: 180\nallowed_tools: [Skill, Read, Glob, Grep]\n---\n\n{prompt}\n", encoding="utf-8")
        if expected:
            (d / "graders" / f"fires-{expected}.md").write_text(grader(expected, True), encoding="utf-8")
        for skill in forbidden:
            (d / "graders" / f"not-{skill}.md").write_text(grader(skill, False), encoding="utf-8")
        written.append(case)

    print(f"plugin: {out} ({len(included)} skills: {', '.join(included)})")
    for name, reason in excluded.items():
        print(f"excluded: {name} ({reason})")
    print(f"cases: {len(written)}")
    for item in skipped:
        print(f"skipped case: {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
