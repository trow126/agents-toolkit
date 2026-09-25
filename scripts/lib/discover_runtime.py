#!/usr/bin/env python3
"""discover_runtime.py — runtime と model の変化を read-only で取得し、routing 表と照合する。

scripts/discover-runtime.sh から呼ぶ。設定は変更しない。書き込むのは snapshot
（${XDG_STATE_HOME:-~/.local/state}/agents-toolkit/runtime-snapshot.json）だけで、前回分は
runtime-snapshot.prev.json に退避する。どちらも追跡しない。

出力は "FAIL: " / "WARN: " / "OK: " / "INFO: " の行と、指示書 §12 の Level の判定案。
exit: 0 = FAIL なし、1 = FAIL あり、2 = 使い方の誤り

options:
  --no-write   snapshot を書かない
  --online     公式の models / deprecations ページで Claude の alias と ID を照合する

test 用の上書き（env）:
  AGENTS_TOOLKIT_REPO                 routing 表と manifest を読む repo（既定: この script の repo）
  AGENTS_TOOLKIT_MANAGED_DIR          managed settings の directory（既定: /etc/claude-code）
  AGENTS_TOOLKIT_WINDOWS_MANAGED_DIR  Windows host の managed settings（既定: /mnt/c/Program Files/ClaudeCode）
  AGENTS_TOOLKIT_TODAY                retires_at の判定に使う日付（YYYY-MM-DD）
"""
from __future__ import annotations

import csv
import datetime as dt
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import tomllib
import urllib.request
from pathlib import Path

# codex-plugin-cc 1.0.6 の `task --effort` が受け付ける値（codex-companion.mjs の VALID_REASONING_EFFORTS）
COMPANION_EFFORTS = ("none", "minimal", "low", "medium", "high", "xhigh")
INSTRUCTION_MODES = ("claude-md", "claude-md-or-agents-md", "claude-md-and-agents-md", "managed-only")
DEFAULT_MODE = "claude-md-or-agents-md"
ENV_PIN = re.compile(r"^ANTHROPIC_DEFAULT_(OPUS|FABLE|SONNET|HAIKU)_MODEL$")
FAMILY = re.compile(r"^claude-(opus|sonnet|haiku|fable)-")
OFFICIAL_PAGES = (
    "https://platform.claude.com/docs/en/about-claude/models/overview.md",
    "https://platform.claude.com/docs/en/about-claude/model-deprecations.md",
)


class Report:
    def __init__(self) -> None:
        self.lines: list[str] = []
        self.levels: list[tuple[int, str]] = []

    def add(self, kind: str, message: str, level: int | None = None) -> None:
        self.lines.append(f"{kind}: {message}")
        if level is not None:
            self.levels.append((level, message))

    @property
    def failed(self) -> bool:
        return any(line.startswith("FAIL:") for line in self.lines)


def read_json(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def run(cmd: list[str]) -> str | None:
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def version_tuple(text: str | None) -> tuple[int, ...] | None:
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", text or "")
    return tuple(int(x) for x in match.groups()) if match else None


def settings_sources(home: Path, managed_dir: Path, windows_dir: Path) -> list[tuple[str, dict]]:
    sources: list[tuple[str, dict]] = []
    for label, path in (("user", home / ".claude/settings.json"), ("user-local", home / ".claude/settings.local.json")):
        data = read_json(path)
        if data is not None:
            sources.append((label, data))
    for label, base in (("managed", managed_dir), ("windows-managed", windows_dir)):
        files = [base / "managed-settings.json"] + sorted(Path(p) for p in glob.glob(str(base / "managed-settings.d/*.json")))
        for path in files:
            data = read_json(path)
            if data is not None:
                sources.append((f"{label}:{path.name}", data))
    return sources


def instruction_files(sources: list[tuple[str, dict]]) -> dict:
    found = []
    for label, data in sources:
        plugin_configs = data.get("pluginConfigs") or {}
        for key in ("agents-md@builtin", "agents-md"):
            value = ((plugin_configs.get(key) or {}).get("options") or {}).get("instructionFiles")
            if value is not None:
                found.append({"source": label, "key": f"pluginConfigs.{key}.options.instructionFiles", "value": value})
        if "projectInstructions" in data:
            found.append({"source": label, "key": "projectInstructions", "value": data["projectInstructions"]})
    # managed wins over user; the last managed drop-in wins among managed files
    current = [f for f in found if f["key"] != "projectInstructions"]
    managed = [f for f in current if f["source"].startswith(("managed", "windows-managed"))]
    chosen = (managed or current or [None])[-1]
    return {
        "effective": chosen["value"] if chosen else DEFAULT_MODE,
        "source": chosen["source"] + ":" + chosen["key"] if chosen else "default",
        "all": found,
    }


def transcript_models(home: Path, limit: int = 30) -> dict[str, str]:
    files = sorted(glob.glob(str(home / ".claude/projects/*/*.jsonl")), key=os.path.getmtime)[-limit:]
    latest: dict[str, str] = {}
    for path in files:
        try:
            handle = open(path, encoding="utf-8", errors="ignore")
        except OSError:
            continue
        with handle:
            for line in handle:
                if '"assistant"' not in line or '"model"' not in line:
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue
                model = ((record.get("message") or {}) if isinstance(record.get("message"), dict) else {}).get("model")
                if isinstance(model, str) and (m := FAMILY.match(model)):
                    latest[m.group(1)] = model
    return latest


def routing_rows(repo: Path) -> list[dict[str, str]]:
    path = repo / "docs/contracts/model-routing.tsv"
    if not path.is_file():
        return []
    with path.open(encoding="utf-8", newline="") as handle:
        return [{k: (v or "").strip() for k, v in row.items()} for row in csv.DictReader(handle, delimiter="\t")]


def tree_hash(root: Path) -> str | None:
    if not root.is_dir():
        return None
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob("*") if p.is_file() and ".generated" not in p.parts and "node_modules" not in p.parts and p.name != ".in_use"):
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


def manifest_drift(repo: Path, home: Path) -> list[str]:
    drift = []
    manifest = repo / "install/manifest.tsv"
    if not manifest.is_file():
        return ["manifest missing"]
    for raw in manifest.read_text(encoding="utf-8").splitlines():
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("\t")
        if len(fields) != 3:
            continue
        _mode, source, target = fields
        link = home / target
        want = (repo / source).resolve()
        if link.is_symlink():
            if Path(os.readlink(link)).resolve() != want and link.resolve() != want:
                drift.append(f"{target} points elsewhere")
        elif link.exists():
            drift.append(f"{target} is a regular file, not a symlink")
        else:
            drift.append(f"{target} is missing")
    return drift


def check_catalog_route(report: Report, row: dict, catalog: dict[str, dict]) -> None:
    role, model, effort, launcher = row["role"], row["model"], row["effort"], row["launcher"]
    entry = catalog.get(model)
    if entry is None:
        report.add("FAIL", f"routing {role}: model {model} is not in the live Codex catalog", level=1)
        return
    levels = entry.get("levels") or []
    if effort != "-":
        if "companion" in launcher and effort not in COMPANION_EFFORTS:
            report.add("FAIL", f"routing {role}: launcher {launcher} does not accept effort {effort} (companion: {'..'.join((COMPANION_EFFORTS[0], COMPANION_EFFORTS[-1]))})", level=1)
        elif effort not in levels:
            report.add("FAIL", f"routing {role}: {model} does not support effort {effort} (catalog: {', '.join(levels)})", level=1)
        else:
            report.add("OK", f"routing {role}: {model}/{effort} is in the catalog and accepted by {launcher}")
    if entry.get("upgrade"):
        report.add("WARN", f"routing {role}: catalog marks {model} for upgrade to {entry['upgrade']}", level=1)
    fallback = row.get("fallback") or ""
    if fallback:
        fb_model, _, fb_effort = fallback.partition("/")
        fb_entry = catalog.get(fb_model)
        if fb_entry is None:
            report.add("WARN", f"routing {role}: fallback {fallback} is not in the live Codex catalog")
        elif fb_effort and (fb_effort not in (fb_entry.get("levels") or []) or ("companion" in launcher and fb_effort not in COMPANION_EFFORTS)):
            report.add("WARN", f"routing {role}: fallback {fallback} is not accepted by the catalog or launcher")


def check_retirement(report: Report, row: dict, today: dt.date) -> None:
    retires = row.get("retires_at") or ""
    if not retires:
        return
    if retires.startswith("not-before:"):
        report.add("WARN", f"routing {row['role']}: {row['model']} retires not before {retires[11:]} (date not announced)", level=1)
        return
    try:
        days = (dt.date.fromisoformat(retires) - today).days
    except ValueError:
        report.add("FAIL", f"routing {row['role']}: invalid retires_at {retires}")
        return
    if days < 30:
        report.add("FAIL", f"routing {row['role']}: {row['model']} retires on {retires} ({days} days left)", level=1)
    else:
        report.add("INFO", f"routing {row['role']}: {row['model']} retires on {retires} ({days} days left)")


def main(argv: list[str]) -> int:
    args = set(argv[1:])
    if not args <= {"--no-write", "--online"}:
        print(__doc__, file=sys.stderr)
        return 2
    home = Path(os.environ.get("HOME", "~")).expanduser()
    repo = Path(os.environ.get("AGENTS_TOOLKIT_REPO") or Path(__file__).resolve().parents[2]).resolve()
    managed_dir = Path(os.environ.get("AGENTS_TOOLKIT_MANAGED_DIR", "/etc/claude-code"))
    windows_dir = Path(os.environ.get("AGENTS_TOOLKIT_WINDOWS_MANAGED_DIR", "/mnt/c/Program Files/ClaudeCode"))
    today = dt.date.fromisoformat(os.environ.get("AGENTS_TOOLKIT_TODAY") or dt.date.today().isoformat())
    state_dir = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state") / "agents-toolkit"
    snapshot_path = state_dir / "runtime-snapshot.json"
    previous = read_json(snapshot_path) or {}
    report = Report()
    snap: dict = {"generated_at": dt.datetime.now(dt.UTC).isoformat(timespec="seconds"), "repo": str(repo)}
    rows = routing_rows(repo)
    if not rows:
        report.add("FAIL", f"routing table missing or empty: {repo}/docs/contracts/model-routing.tsv")

    # ---------------- Claude ----------------
    claude_version = run(["claude", "--version"])
    snap["claude_version"] = claude_version
    report.add("INFO", f"Claude Code version: {claude_version or 'not found'}")
    if previous.get("claude_version") and previous.get("claude_version") != claude_version:
        report.add("WARN", f"Claude Code version changed: {previous.get('claude_version')} -> {claude_version} (review the CHANGELOG lines on AGENTS.md, model, effort, hook, skill)", level=2)
    sources = settings_sources(home, managed_dir, windows_dir)
    merged: dict = {}
    for _label, data in sources:
        merged.update(data)
    instr = instruction_files(sources)
    snap["instruction_files"] = instr
    if instr["effective"] not in INSTRUCTION_MODES:
        report.add("FAIL", f"instructionFiles has an unknown value {instr['effective']!r} (from {instr['source']}); Claude Code treats it as the default", level=2)
    elif instr["effective"] != DEFAULT_MODE:
        report.add("WARN", f"instructionFiles is {instr['effective']} (from {instr['source']}), not the default {DEFAULT_MODE}", level=2)
    else:
        report.add("OK", f"instructionFiles is the default {DEFAULT_MODE} ({instr['source']})")
    prev_instr = previous.get("instruction_files") or {}
    if prev_instr and (prev_instr.get("effective"), prev_instr.get("source")) != (instr["effective"], instr["source"]):
        report.add("WARN", f"instructionFiles changed: {prev_instr.get('effective')} ({prev_instr.get('source')}) -> {instr['effective']} ({instr['source']})", level=2)
    for item in instr["all"]:
        if item["key"] == "projectInstructions":
            report.add("WARN", f"legacy projectInstructions={item['value']!r} is set in {item['source']}; set instructionFiles instead")
    agents_md_enabled = [(label, (data.get("enabledPlugins") or {}).get("agents-md@builtin")) for label, data in sources if "agents-md@builtin" in (data.get("enabledPlugins") or {})]
    snap["agents_md_plugin"] = agents_md_enabled or "default (enabled)"
    for label, value in agents_md_enabled:
        if value is False:
            report.add("WARN", f"built-in agents-md plugin is disabled in {label} (AGENTS.md support unavailable)", level=2)
    managed_only = {k: v for label, data in sources if label.startswith("managed") for k, v in data.items()}
    required = managed_only.get("requiredMinimumVersion")
    snap["required_minimum_version"] = required
    report.add("INFO", f"requiredMinimumVersion: {required or 'unset'}")
    env: dict = {}
    for _label, data in sources:
        env.update({k: v for k, v in (data.get("env") or {}).items() if ENV_PIN.match(k)})
    env.update({k: v for k, v in os.environ.items() if ENV_PIN.match(k)})
    transcripts = transcript_models(home)
    resolution = {}
    for family in ("fable", "opus", "sonnet", "haiku"):
        pin = env.get(f"ANTHROPIC_DEFAULT_{family.upper()}_MODEL")
        resolution[family] = {"model": pin or transcripts.get(family), "via": "env pin" if pin else ("transcript" if family in transcripts else "unknown")}
    snap["alias_resolution"] = resolution
    for family, info in resolution.items():
        report.add("INFO", f"alias {family} -> {info['model'] or 'unknown'} ({info['via']})")
        prev = ((previous.get("alias_resolution") or {}).get(family) or {}).get("model")
        if prev and info["model"] and prev != info["model"]:
            report.add("WARN", f"alias {family} resolution changed: {prev} -> {info['model']}", level=2)
    snap["advisor_model"] = merged.get("advisorModel")
    report.add("INFO", f"advisorModel: {merged.get('advisorModel') or 'unset'}")
    user_settings = read_json(home / ".claude/settings.json") or {}
    auto_memory = user_settings.get("autoMemoryEnabled", managed_only.get("autoMemoryEnabled"))
    snap["auto_memory_enabled"] = auto_memory
    if auto_memory is not False:
        report.add("FAIL", f"autoMemoryEnabled is {auto_memory!r}, must be false (EX-004)")
    else:
        report.add("OK", "autoMemoryEnabled is false (EX-004)")
    live_settings = home / ".claude/settings.json"
    repo_settings = read_json(repo / "claude/settings.json") or {}
    snap["claude_settings_is_symlink"] = live_settings.is_symlink()
    if live_settings.exists() and not live_settings.is_symlink():
        diff_keys = sorted(k for k in set(user_settings) | set(repo_settings) if user_settings.get(k) != repo_settings.get(k))
        snap["claude_settings_diff_keys"] = diff_keys
        report.add("WARN", f"live ~/.claude/settings.json is a regular file, not the repo symlink (D5: resolved in the governance phase); keys differing from the repo: {', '.join(diff_keys) or 'none'}")
    main_row = next((r for r in rows if r["role"] == "claude-main"), None)
    if main_row:
        live_model = user_settings.get("model")
        family = FAMILY.match(live_model).group(1) if isinstance(live_model, str) and FAMILY.match(live_model) else (live_model or "").split("[")[0] or None
        if family != main_row["model"]:
            report.add("WARN", f"live main model is {live_model or 'unset (account default)'} (UI-managed); routing claude-main is {main_row['model']}")
        target_id = resolution.get(main_row["model"], {}).get("model")
        effort = ((user_settings.get("modelSettings") or {}).get(target_id or "") or {}).get("effortLevel")
        if effort != main_row["effort"]:
            report.add("WARN", f"live modelSettings[{target_id}].effortLevel is {effort!r}; routing claude-main effort is {main_row['effort']}")

    # ---------------- Codex ----------------
    codex_version = run(["codex", "--version"])
    version_json = read_json(home / ".codex/version.json") or {}
    snap["codex_version"] = codex_version
    snap["codex_latest"] = version_json.get("latest_version")
    report.add("INFO", f"Codex CLI: {codex_version or 'not found'} (latest known: {version_json.get('latest_version') or 'unknown'})")
    installed_v, latest_v = version_tuple(codex_version), version_tuple(version_json.get("latest_version"))
    if installed_v and latest_v and installed_v < latest_v:
        report.add("WARN", f"Codex CLI {codex_version} is older than the latest stable {version_json.get('latest_version')}", level=2)
    if previous.get("codex_version") and previous.get("codex_version") != codex_version:
        report.add("WARN", f"Codex CLI version changed: {previous.get('codex_version')} -> {codex_version} (re-check catalog and prompt-input)", level=2)
    cache = read_json(home / ".codex/models_cache.json") or {}
    catalog = {}
    for model in cache.get("models") or []:
        if isinstance(model, dict) and model.get("slug"):
            upgrade = model.get("upgrade")
            catalog[model["slug"]] = {
                "levels": [l.get("effort") if isinstance(l, dict) else l for l in model.get("supported_reasoning_levels") or []],
                "default": model.get("default_reasoning_level"),
                "upgrade": upgrade.get("model") if isinstance(upgrade, dict) else upgrade,
                "visibility": model.get("visibility"),
            }
    snap["codex_catalog"] = {"fetched_at": cache.get("fetched_at"), "client_version": cache.get("client_version"), "models": catalog}
    if not catalog:
        report.add("FAIL", "live Codex catalog (~/.codex/models_cache.json) is missing or empty")
    prev_models = set(((previous.get("codex_catalog") or {}).get("models") or {}))
    if prev_models and catalog and prev_models != set(catalog):
        report.add("WARN", f"Codex catalog changed: added {sorted(set(catalog) - prev_models)}, removed {sorted(prev_models - set(catalog))}", level=1)
    try:
        config = tomllib.loads((home / ".codex/config.toml").read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        config = {}
    agents = config.get("agents") or {}
    snap["codex_config"] = {
        "model": config.get("model"), "model_reasoning_effort": config.get("model_reasoning_effort"),
        "default_subagent_model": agents.get("default_subagent_model"),
        "default_subagent_reasoning_effort": agents.get("default_subagent_reasoning_effort"),
    }
    report.add("INFO", f"Codex config model: {config.get('model')}/{config.get('model_reasoning_effort')} (used only when a launcher passes no --model)")
    prev_cfg = previous.get("codex_config") or {}
    if prev_cfg and (prev_cfg.get("model"), prev_cfg.get("model_reasoning_effort")) != (config.get("model"), config.get("model_reasoning_effort")):
        report.add("WARN", f"Codex config default changed without the routing gate: {prev_cfg.get('model')}/{prev_cfg.get('model_reasoning_effort')} -> {config.get('model')}/{config.get('model_reasoning_effort')}", level=1)
    for row in rows:
        if row.get("runtime") == "codex" and catalog:
            check_catalog_route(report, row, catalog)
        if row.get("role") == "codex-default-subagent":
            live = (agents.get("default_subagent_model"), agents.get("default_subagent_reasoning_effort"))
            if live != (row["model"], row["effort"]):
                report.add("WARN", f"live [agents] default subagent is {live[0]}/{live[1]}; routing codex-default-subagent is {row['model']}/{row['effort']}")
        check_retirement(report, row, today)
    plugins = (read_json(home / ".claude/plugins/installed_plugins.json") or {}).get("plugins") or {}
    entry = (plugins.get("codex@openai-codex") or [{}])[0]
    install_path = Path(entry.get("installPath") or "/nonexistent")
    marketplace = home / ".claude/plugins/marketplaces/openai-codex"
    local_changes = run(["git", "-C", str(marketplace), "status", "--porcelain"]) if marketplace.is_dir() else None
    plugin = {
        "version": entry.get("version"), "commit": entry.get("gitCommitSha"),
        "cache_hash": tree_hash(install_path),
        "marketplace_local_changes": len(local_changes.splitlines()) if local_changes else 0,
    }
    snap["codex_plugin_cc"] = plugin
    report.add("INFO", f"codex-plugin-cc: {plugin['version'] or 'not installed'} ({(plugin['commit'] or '')[:7]}), companion efforts {', '.join(COMPANION_EFFORTS)}")
    if plugin["marketplace_local_changes"]:
        report.add("WARN", f"codex-plugin-cc marketplace clone has {plugin['marketplace_local_changes']} local changes (D11: upstream only)", level=2)
    prev_plugin = previous.get("codex_plugin_cc") or {}
    if prev_plugin and (prev_plugin.get("version"), prev_plugin.get("cache_hash")) != (plugin["version"], plugin["cache_hash"]):
        report.add("WARN", f"codex-plugin-cc changed: {prev_plugin.get('version')} -> {plugin['version']} (cache hash changed: {prev_plugin.get('cache_hash') != plugin['cache_hash']})", level=2)

    # ---------------- common ----------------
    drift = manifest_drift(repo, home)
    snap["manifest_drift"] = drift
    for item in drift:
        report.add("WARN", f"manifest drift: {item}")
    upper = []
    for directory in [home, *home.parents]:
        for name in ("AGENTS.md", "CLAUDE.md", "CLAUDE.local.md", ".claude/AGENTS.md") + (() if directory == home else (".claude/CLAUDE.md",)):
            if (directory / name).is_file():
                upper.append(str(directory / name))
    snap["upper_instruction_files"] = upper
    for path in upper:
        report.add("WARN", f"upper-directory instruction file is loaded as project instructions in repos below it: {path}")
    windows_nonempty = [label for label, data in sources if label.startswith("windows-managed") and data]
    snap["windows_managed_nonempty"] = windows_nonempty
    for label in windows_nonempty:
        report.add("WARN", f"Windows host managed settings are not empty: {label}")
    hooks_path = run(["git", "-C", str(repo), "config", "--get", "core.hooksPath"])
    snap["core_hooks_path"] = hooks_path
    report.add("INFO", f"core.hooksPath: {hooks_path or 'unset'}")
    slack = os.environ.get("AGENTS_TOOLKIT_SLACK_NOTIFY")
    snap["slack_notify_env"] = slack
    report.add("INFO", f"AGENTS_TOOLKIT_SLACK_NOTIFY: {slack or 'unset (notifications on)'}")

    # ---------------- online ----------------
    if "--online" in args:
        text = ""
        for url in OFFICIAL_PAGES:
            try:
                # the docs host rejects urllib's default User-Agent (HTTP 403)
                request = urllib.request.Request(url, headers={"User-Agent": "agents-toolkit-discovery/1"})
                with urllib.request.urlopen(request, timeout=20) as response:
                    text += response.read().decode("utf-8", "ignore")
            except OSError as exc:
                report.add("WARN", f"could not fetch {url}: {exc}")
        for family, info in resolution.items():
            if info["model"] and text and info["model"].split("[")[0] not in text:
                report.add("WARN", f"alias {family} -> {info['model']} is not listed on the official models/deprecations pages", level=2)
    else:
        report.add("INFO", "official models/deprecations check skipped (offline; use --online)")

    snap["findings"] = report.lines
    if "--no-write" not in args:
        state_dir.mkdir(parents=True, exist_ok=True)
        if snapshot_path.exists():
            os.replace(snapshot_path, state_dir / "runtime-snapshot.prev.json")
        tmp = snapshot_path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(snap, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        os.replace(tmp, snapshot_path)

    order = {"FAIL": 0, "WARN": 1, "OK": 2, "INFO": 3}
    for line in sorted(report.lines, key=lambda l: order.get(l.split(":", 1)[0], 9)):
        print(line)
    print()
    print("== Level の判定案（指示書 §12）")
    if not report.levels:
        print("変化なし: 再評価は不要")
    for level in (1, 2, 3):
        for lv, message in report.levels:
            if lv == level:
                print(f"Level {level} 候補: {message}")
    if "--no-write" not in args:
        print(f"snapshot: {snapshot_path}")
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
