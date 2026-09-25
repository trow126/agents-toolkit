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
  AGENTS_TOOLKIT_PROC_DIR             broker を探す proc の directory（既定: /proc）

任意の項目（Phase 8、FAIL にはしない）: broker の年齢と孤児、Codex の hook の trust、
`codex features list` の差分、skill 一覧のサイズ、`codex debug prompt-input` の監査（モデルは呼ばない）。
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
import tempfile
import tomllib
import urllib.request
from pathlib import Path

# codex-plugin-cc 1.0.6 の `task --effort` が受け付ける値（codex-companion.mjs の VALID_REASONING_EFFORTS）
COMPANION_EFFORTS = ("none", "minimal", "low", "medium", "high", "xhigh")
INSTRUCTION_MODES = ("claude-md", "claude-md-or-agents-md", "claude-md-and-agents-md", "managed-only")
DEFAULT_MODE = "claude-md-or-agents-md"
ENV_PIN = re.compile(r"^ANTHROPIC_DEFAULT_(OPUS|FABLE|SONNET|HAIKU)_MODEL$")
FAMILY = re.compile(r"^claude-(opus|sonnet|haiku|fable)-")
# shared/rules/core-contract.md の最初の規則。Codex の prompt に1回だけ入っているはず（付録 C.2）
CORE_CONTRACT_MARKER = "事実の正確さと安全性を速度より優先し"
BROKER_MAX_AGE = 24 * 3600
LISTING_GROWTH = 1.2
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


def process_table(proc: Path) -> list[dict]:
    """pid、ppid、経過秒数、argv（/proc を読む。取れなければ空）"""
    try:
        uptime = float((proc / "uptime").read_text().split()[0])
        hz = os.sysconf("SC_CLK_TCK")
    except (OSError, ValueError, IndexError):
        return []
    table = []
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            stat = (entry / "stat").read_text()
            argv = [a.decode("utf-8", "replace") for a in (entry / "cmdline").read_bytes().split(b"\0") if a]
            fields = stat[stat.rindex(")") + 2:].split()
            table.append({"pid": int(entry.name), "ppid": int(fields[1]),
                          "age": max(0, int(uptime - int(fields[19]) / hz)), "args": " ".join(argv)})
        except (OSError, ValueError, IndexError):
            continue
    return table


def check_brokers(report: Report, snap: dict, proc: Path) -> None:
    """codex-plugin-cc の broker（app-server-broker.mjs と、それが起動した codex app-server）の年齢と孤児。
    Codex 自身の app-server daemon（--managed-daemon）は常駐が正常なので、年齢の表示だけにする。"""
    table = process_table(proc)
    by_pid = {p["pid"]: p for p in table}
    daemons, brokers = [], []
    for p in table:
        args = p["args"]
        if "app-server" not in args:
            continue
        if "--managed-daemon" in args or "app-server daemon" in args:
            daemons.append(p)
        elif "app-server-broker" in args or re.search(r"(^|/)codex\S* app-server\b", args):
            parent = by_pid.get(p["ppid"], {}).get("args", "")
            p["orphan"] = p["ppid"] <= 1 or Path(parent.split(" ")[0]).name in ("init", "systemd")
            brokers.append(p)
    snap["brokers"] = [{k: p[k] for k in ("pid", "ppid", "age", "orphan")} for p in brokers]
    snap["codex_daemons"] = [{k: p[k] for k in ("pid", "age")} for p in daemons]
    report.add("INFO", f"codex-plugin-cc brokers: {len(brokers)}; Codex app-server daemon processes: {len(daemons)}"
               + (f" (oldest {max(p['age'] for p in daemons) // 3600} h)" if daemons else ""))
    for p in brokers:
        if p["orphan"]:
            report.add("WARN", f"orphaned codex-plugin-cc broker pid {p['pid']} (age {p['age'] // 60} min, parent is init); stop it if no session uses it")
        elif p["age"] > BROKER_MAX_AGE:
            report.add("WARN", f"codex-plugin-cc broker pid {p['pid']} is {p['age'] // 3600} h old")


def snake(name: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def codex_hook_definitions(home: Path) -> dict[str, str]:
    """Codex の hooks.state と同じ key（"<file>:<event>:<group>:<hook>"）で、hook の定義の sha256。
    対象は ~/.codex/hooks.json と ~/.codex/*.toml（config.toml と profile の inline hook）。"""
    sources = []
    hooks_json = home / ".codex/hooks.json"
    data = read_json(hooks_json)
    if data:
        sources.append((hooks_json, data.get("hooks") or {}))
    for toml_path in sorted((home / ".codex").glob("*.toml")):
        try:
            data = tomllib.loads(toml_path.read_text(encoding="utf-8"))
        except (OSError, tomllib.TOMLDecodeError):
            continue
        sources.append((toml_path, {k: v for k, v in (data.get("hooks") or {}).items() if isinstance(v, list)}))
    definitions = {}
    for path, events in sources:
        for event, groups in events.items():
            for i, group in enumerate(groups or []):
                if not isinstance(group, dict):
                    continue
                for j, hook in enumerate(group.get("hooks") or []):
                    body = json.dumps([group.get("matcher"), hook], sort_keys=True, ensure_ascii=False)
                    definitions[f"{path}:{snake(event)}:{i}:{j}"] = hashlib.sha256(body.encode()).hexdigest()[:16]
    return definitions


def check_hook_trust(report: Report, snap: dict, previous: dict, home: Path, config: dict) -> None:
    definitions = codex_hook_definitions(home)
    state = (config.get("hooks") or {}).get("state") or {}
    trusted = {k: str((v or {}).get("trusted_hash", ""))[:16] for k, v in state.items() if isinstance(v, dict)}
    snap["codex_hooks"] = {"definitions": definitions, "trusted": trusted}
    untrusted = sorted(set(definitions) - set(trusted))
    for key in untrusted:
        report.add("WARN", f"Codex hook has no trust entry, so it does not run: {key} (trust it in /hooks; for a toolkit profile, then run scripts/codex-profile-trust.py)")
    prev = previous.get("codex_hooks") or {}
    for key, digest in definitions.items():
        before = (prev.get("definitions") or {}).get(key)
        if before and before != digest and key in trusted and (prev.get("trusted") or {}).get(key) == trusted[key]:
            report.add("WARN", f"Codex hook definition changed but its trust did not: {key} (re-trust it in /hooks)", level=2)
    stale = sorted(set(trusted) - set(definitions))
    report.add("INFO", f"Codex hooks: {len(definitions)} defined, {len(definitions) - len(untrusted)} trusted"
               + (f", {len(stale)} trust entries without a hook" if stale else ""))


def check_features(report: Report, snap: dict, previous: dict) -> None:
    out = run(["codex", "features", "list"])
    features = {}
    for line in (out or "").splitlines():
        m = re.match(r"^(\S+)\s+(.+?)\s+(true|false)\s*$", line)
        if m:
            features[m.group(1)] = [m.group(2), m.group(3) == "true"]
    if not features:
        report.add("INFO", "codex features list: unavailable")
        return
    snap["codex_features"] = features
    report.add("INFO", f"codex features: {len(features)} ({sum(1 for f in features.values() if f[1])} enabled)")
    prev = previous.get("codex_features") or {}
    if prev:
        added = sorted(set(features) - set(prev))
        removed = sorted(set(prev) - set(features))
        changed = sorted(k for k in set(features) & set(prev) if features[k] != prev[k])
        if added or removed or changed:
            def names(items: list[str]) -> str:
                return ", ".join(items[:8]) + (" ..." if len(items) > 8 else "")
            report.add("WARN", f"codex features changed: added [{names(added)}], removed [{names(removed)}], stage or enabled changed [{names(changed)}]", level=2)


def listed_skills(skills_dir: Path, runtime: str) -> tuple[int, int]:
    """model に一覧される skill の数と、description + when_to_use の字数（manual-only を除く）"""
    count = chars = 0
    for skill in sorted(skills_dir.glob("*/SKILL.md")):
        try:
            text = skill.read_text(encoding="utf-8")
        except OSError:
            continue
        m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        front = m.group(1) if m else ""
        if runtime == "claude" and re.search(r"^disable-model-invocation:\s*true\s*$", front, re.M):
            continue
        policy = skill.parent / "agents/openai.yaml"
        if runtime == "codex" and policy.is_file() and re.search(r"^\s*allow_implicit_invocation:\s*false\s*$", policy.read_text(encoding="utf-8"), re.M):
            continue
        values = [v.strip().strip("\"'") for k, v in re.findall(r"^(description|when_to_use):(.*)$", front, re.M)]
        count += 1
        chars += len(" ".join(v for v in values if v))
    return count, chars


def codex_prompt_texts() -> list[str] | None:
    """`codex debug prompt-input` を空の一時 directory で実行する（project の AGENTS.md を混ぜない。モデルは呼ばない）"""
    with tempfile.TemporaryDirectory() as cwd:
        try:
            result = subprocess.run(["codex", "debug", "prompt-input", "agents-toolkit-discovery"],
                                    capture_output=True, text=True, timeout=60, cwd=cwd)
            data = json.loads(result.stdout) if result.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
            return None
    texts: list[str] = []

    def walk(node) -> None:
        if isinstance(node, dict):
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)
        elif isinstance(node, str):
            texts.append(node)
    walk(data)
    return texts or None


def check_listing_and_prompt(report: Report, snap: dict, previous: dict, home: Path) -> None:
    sizes = {}
    for runtime, skills_dir in (("claude", home / ".claude/skills"), ("codex", home / ".agents/skills")):
        count, chars = listed_skills(skills_dir, runtime)
        sizes[f"{runtime}_listed_skills"] = count
        sizes[f"{runtime}_listing_chars"] = chars
    texts = codex_prompt_texts()
    if texts is None:
        report.add("INFO", "codex debug prompt-input: unavailable")
    else:
        sizes["codex_prompt_chars"] = sum(len(t) for t in texts)
        sizes["codex_skills_block_chars"] = sum(len(t) for t in texts if "<skills_instructions>" in t)
        core = sum(t.count(CORE_CONTRACT_MARKER) for t in texts)
        sizes["codex_core_contract_copies"] = core
        if core != 1:
            report.add("WARN", f"Codex prompt-input carries the core contract {core} times (expected 1; appendix C.2)", level=2)
        else:
            report.add("OK", "Codex prompt-input carries the core contract once")
    snap["listing_sizes"] = sizes
    report.add("INFO", "skill listing: Claude {claude_listed_skills} skills / {claude_listing_chars} chars, Codex {codex_listed_skills} skills / {codex_listing_chars} chars".format(**sizes)
               + (f"; Codex prompt-input {sizes['codex_prompt_chars']} chars (skills block {sizes['codex_skills_block_chars']})" if "codex_prompt_chars" in sizes else ""))
    prev = previous.get("listing_sizes") or {}
    for key in ("claude_listing_chars", "codex_listing_chars", "codex_skills_block_chars", "codex_prompt_chars"):
        before, now = prev.get(key), sizes.get(key)
        if before and now and now > before * LISTING_GROWTH:
            report.add("WARN", f"{key} grew {before} -> {now} (more than {int((LISTING_GROWTH - 1) * 100)}% since the last snapshot)", level=2)


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
    # managed wins over user; EX-004 puts autoMemoryEnabled=false in managed (Phase 7)
    if "autoMemoryEnabled" in managed_only:
        auto_memory, memory_source = managed_only["autoMemoryEnabled"], "managed"
    else:
        auto_memory, memory_source = user_settings.get("autoMemoryEnabled"), "user"
    snap["auto_memory_enabled"] = auto_memory
    if auto_memory is not False:
        report.add("FAIL", f"autoMemoryEnabled is {auto_memory!r} (from {memory_source}), must be false (EX-004)")
    else:
        report.add("OK", f"autoMemoryEnabled is false (from {memory_source}; EX-004)")
    live_settings = home / ".claude/settings.json"
    snap["claude_settings_is_symlink"] = live_settings.is_symlink()
    if live_settings.is_symlink():
        report.add("WARN", "live ~/.claude/settings.json is a symlink; D5 makes the live file canonical (a regular file written by Claude Code)")
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

    # ---------------- optional (Phase 8; WARN at most) ----------------
    check_brokers(report, snap, Path(os.environ.get("AGENTS_TOOLKIT_PROC_DIR", "/proc")))
    check_hook_trust(report, snap, previous, home, config)
    check_features(report, snap, previous)
    check_listing_and_prompt(report, snap, previous, home)

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
