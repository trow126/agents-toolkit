#!/usr/bin/env python3
"""codex-profile-trust.py — move Codex local state out of the toolkit profile files (K11).

usage: scripts/codex-profile-trust.py [--check] [--repo DIR] [--codex-home DIR]

Codex writes hook trust ([hooks.state]), project trust ([projects]), and UI state ([tui]) into
the config layer of the active profile. The toolkit profiles are symlinks into this repository
(~/.codex/toolkit-*.config.toml -> codex/profiles/*.config.toml), so trusting the delegation hook
in `codex -p toolkit-implementer` dirties the checkout. Codex honors the same entries in
$CODEX_HOME/config.toml (verified on the integration host, 2026-09-25), so this script moves the
hook and project trust there, drops the UI state, and restores each profile from git HEAD.

--check  report profiles that carry local state and exit 1; change nothing.
A profile with any other local edit is left alone (exit 1).
"""
import argparse
import copy
import json
import os
import subprocess
import sys
import tomllib
from pathlib import Path

STATE_TABLES = ("projects", "tui")


def git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=False)


def split_state(data: dict) -> tuple[dict, dict, dict]:
    """Return (profile without local state, hook trust entries, project trust entries)."""
    rest = copy.deepcopy(data)
    hooks = rest.get("hooks")
    hook_state = {}
    if isinstance(hooks, dict) and isinstance(hooks.get("state"), dict):
        hook_state = hooks.pop("state")
        if not hooks:
            rest.pop("hooks")
    projects = rest.pop("projects", {}) or {}
    rest.pop("tui", None)
    return rest, hook_state, projects


def toml_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    raise ValueError(f"unsupported value in local state: {value!r}")


def upsert_table(text: str, header: str, values: dict) -> str:
    """Replace the body of `header` in TOML text, or append the table."""
    body = [f"{key} = {toml_value(value)}" for key, value in values.items()]
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.strip() == header:
            end = i + 1
            while end < len(lines) and not lines[end].lstrip().startswith("["):
                end += 1
            while end > i + 1 and not lines[end - 1].strip():
                end -= 1
            return "\n".join(lines[: i + 1] + body + lines[end:])
    return text.rstrip("\n") + "\n\n" + "\n".join([header, *body]) + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--codex-home", type=Path,
                        default=Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex"))
    args = parser.parse_args(argv[1:])
    repo = args.repo.resolve()
    config_path = args.codex_home / "config.toml"
    failures = 0
    moved: list[tuple[str, str, dict]] = []
    restore: list[str] = []

    for path in sorted((repo / "codex/profiles").glob("*.toml")):
        rel = path.relative_to(repo).as_posix()
        head = git(repo, "show", f"HEAD:{rel}")
        if head.returncode != 0:
            print(f"SKIP: {rel} is not committed")
            continue
        current_text = path.read_text(encoding="utf-8")
        if current_text == head.stdout:
            continue
        try:
            current = tomllib.loads(current_text)
            committed = tomllib.loads(head.stdout)
        except tomllib.TOMLDecodeError as exc:
            print(f"FAIL: {rel}: cannot parse: {exc}")
            failures += 1
            continue
        rest, hook_state, projects = split_state(current)
        if rest != split_state(committed)[0]:
            print(f"FAIL: {rel} has local edits other than Codex state; resolve them by hand")
            failures += 1
            continue
        names = [f"hooks.state ({len(hook_state)})" if hook_state else "", f"projects ({len(projects)})" if projects else "",
                 "tui" if "tui" in current else ""]
        print(f"STATE: {rel} carries local Codex state: {', '.join(n for n in names if n)}")
        if args.check:
            failures += 1
            continue
        moved += [(f"[hooks.state.{json.dumps(key)}]", key, value) for key, value in hook_state.items()]
        moved += [(f"[projects.{json.dumps(key)}]", key, value) for key, value in projects.items()]
        restore.append(rel)

    if args.check or failures:
        if not failures:
            print("OK: toolkit profiles carry no local Codex state")
        return 1 if failures else 0
    if not restore:
        print("OK: toolkit profiles carry no local Codex state")
        return 0

    text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    for header, _, values in moved:
        if not isinstance(values, dict):
            print(f"FAIL: unexpected local state {header}: {values!r}")
            return 1
        text = upsert_table(text, header, values)
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as exc:
        print(f"FAIL: merged {config_path} would not parse ({exc}); nothing changed")
        return 1
    config_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = config_path.with_name(config_path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, config_path)
    for rel in restore:
        result = git(repo, "checkout", "--", rel)
        if result.returncode != 0:
            print(f"FAIL: git checkout -- {rel}: {result.stderr.strip()}")
            return 1
    for header, _, _ in moved:
        print(f"MOVED: {header} -> {config_path}")
    print(f"RESTORED: {', '.join(restore)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
