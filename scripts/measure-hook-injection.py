#!/usr/bin/env python3
"""Measure deterministic hook injection for a controlled fixture.

The hooks are read from the managed policy (claude/managed-settings.json) of the
measured tree, so the same script measures the current layout and older layouts
(for example the baseline commit) that still registered SessionStart, PostCompact,
or UserPromptSubmit hooks. Registered ~/.claude/hooks commands are resolved to the
tree's claude/hooks/ and run in an isolated HOME against a small git fixture.

Per event, "typical" is the stdout bytes the registered command hooks emit in the
fixture (SessionStart / PostCompact: the systemMessage JSON; UserPromptSubmit:
everything, because plain stdout and additionalContext both reach the model).
"max" is the bound a hook declares (MAX_OUTPUT_BYTES or MAX_INJECTION_BYTES in the
hook script, or in a claude/hooks/lib/*.py helper the script references). A hook
that emits without a declared bound makes the event "unbounded"; a hook that stays
silent in the fixture contributes 0. An event with no registered hook reports 0 / 0.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

HELPER_DIR = "claude/hooks/lib"
HELPER_RE = re.compile(r"lib/([A-Za-z0-9_.-]+\.py)")
BOUND_RE = re.compile(r"^(?:MAX_OUTPUT_BYTES|MAX_INJECTION_BYTES)\s*=\s*([0-9]+)\s*$", re.M)
HOOK_PATH_RE = re.compile(r"([^\s\"']*/claude/hooks/[^\s\"']+)")
FIXTURE_ENV_UNSET = ("HERDR_ENV", "HERDR_SOCKET_PATH", "HERDR_PANE_ID")


def run(
    cmd: list[str],
    cwd: Path,
    env: dict[str, str],
    input_data: bytes | None = None,
) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        check=True,
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def registered_commands(root: Path, event: str) -> list[str]:
    managed = root / "claude/managed-settings.json"
    if not managed.is_file():
        return []
    try:
        data = json.loads(managed.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f"ERROR: invalid managed settings JSON: {managed}: {exc}")
    commands: list[str] = []
    for matcher in data.get("hooks", {}).get(event) or []:
        for hook in matcher.get("hooks") or []:
            hook_type = hook.get("type", "command")
            if hook_type != "command":
                raise SystemExit(f"ERROR: unsupported {event} hook type {hook_type!r}: {managed}")
            command = hook.get("command")
            if not isinstance(command, str) or not command.strip():
                raise SystemExit(f"ERROR: {event} hook without a command: {managed}")
            commands.append(command)
    return commands


def resolve(command: str, root: Path) -> str:
    claude_dir = str(root / "claude")
    for prefix in ("~/.claude", "$HOME/.claude", "${HOME}/.claude"):
        command = command.replace(prefix, claude_dir)
    return command


def declared_bound(resolved: str, root: Path) -> str | None:
    match = HOOK_PATH_RE.search(resolved)
    if not match:
        return None
    script = Path(match.group(1))
    if not script.is_file():
        raise SystemExit(f"ERROR: registered hook script is missing: {script}")
    text = script.read_text(encoding="utf-8", errors="replace")
    found = BOUND_RE.search(text)
    if found:
        return found.group(1)
    for helper_name in HELPER_RE.findall(text):
        helper = root / HELPER_DIR / helper_name
        if not helper.is_file():
            continue
        found = BOUND_RE.search(helper.read_text(encoding="utf-8", errors="replace"))
        if found:
            return found.group(1)
    return None


def measure_event(
    event: str,
    extra: dict[str, str],
    root: Path,
    repo: Path,
    env: dict[str, str],
) -> tuple[int, str]:
    commands = registered_commands(root, event)
    if not commands:
        return 0, "0"
    payload = json.dumps({"hook_event_name": event, "cwd": str(repo), **extra}).encode("utf-8")
    typical = 0
    bounds: list[int] = []
    unbounded = False
    for command in commands:
        resolved = resolve(command, root)
        try:
            proc = run(["bash", "-c", resolved], repo, env, input_data=payload)
        except subprocess.CalledProcessError as exc:
            stderr = exc.stderr.decode(errors="replace")
            raise SystemExit(f"ERROR: {event} hook exited {exc.returncode}: {command}; stderr={stderr}")
        emitted = len(proc.stdout)
        typical += emitted
        bound = declared_bound(resolved, root)
        if bound is not None:
            bounds.append(int(bound))
        elif emitted:
            unbounded = True
    return typical, "unbounded" if unbounded else str(sum(bounds))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()

    with tempfile.TemporaryDirectory(prefix="agents-toolkit-hook-metrics-") as tmp_s:
        tmp = Path(tmp_s)
        repo = tmp / "repo"
        home = tmp / "home"
        repo.mkdir()
        home.mkdir()
        env = os.environ.copy()
        for name in FIXTURE_ENV_UNSET:
            env.pop(name, None)
        env.update({
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "XDG_STATE_HOME": str(home / ".local/state"),
            "XDG_DATA_HOME": str(home / ".local/share"),
            "XDG_CACHE_HOME": str(home / ".cache"),
            "LC_ALL": "C.UTF-8",
        })
        run(["git", "init", "-q", "-b", "main"], repo, env)
        run(["git", "config", "user.email", "fixture@example.invalid"], repo, env)
        run(["git", "config", "user.name", "Fixture"], repo, env)
        run(["git", "config", "commit.gpgsign", "false"], repo, env)
        (repo / "README.md").write_text("baseline\n", encoding="utf-8")
        run(["git", "add", "README.md"], repo, env)
        run(["git", "commit", "-q", "-m", "fixture baseline"], repo, env)
        (repo / "README.md").write_text("baseline\nchanged\n", encoding="utf-8")

        # SessionStart sees an unstaged change; PostCompact sees it staged.
        session = measure_event("SessionStart", {"source": "startup"}, root, repo, env)
        run(["git", "add", "README.md"], repo, env)
        compact = measure_event("PostCompact", {"trigger": "auto"}, root, repo, env)
        prompt = measure_event("UserPromptSubmit", {"user_prompt": "fixture"}, root, repo, env)

    print(f"session_start_system_message_typical_bytes: {session[0]}")
    print(f"session_start_system_message_max_bytes: {session[1]}")
    print(f"post_compact_system_message_typical_bytes: {compact[0]}")
    print(f"post_compact_system_message_max_bytes: {compact[1]}")
    print(f"user_prompt_submit_injection_typical_bytes: {prompt[0]}")
    print(f"user_prompt_submit_injection_max_bytes: {prompt[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
