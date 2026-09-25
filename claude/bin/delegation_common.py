"""Shared helpers for Codex delegation: contract/report schemas, git baseline, scope checks, state files.

Used by codex-delegate, codex-delegate-preflight, verify-delegation, and delegation-evidence-check
(agents-toolkit, owner decision D8). Contracts, prompts, results, evidence, and the active-delegation
state live in $(git rev-parse --git-dir)/agents-toolkit/, which the Codex workspace-write sandbox
cannot write.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

TOOLKIT_ROOT = Path(__file__).resolve().parents[2]
REFERENCES = TOOLKIT_ROOT / "claude/skills/gh-codex-drive/references"
CONTRACT_SCHEMA = REFERENCES / "contract.schema.json"
REPORT_SCHEMA = REFERENCES / "report.schema.json"
PROMPT_TEMPLATE = REFERENCES / "contract.md"
POST_EDIT_LINT = TOOLKIT_ROOT / "claude/hooks/lib/post_edit_lint.py"
PROFILE = "toolkit-implementer"

ALWAYS_PROTECTED = [
    "**/AGENTS.md", "**/AGENTS.override.md", "**/CLAUDE.md", "**/CLAUDE.local.md",
    "**/.agents/**", "**/.claude/**", "**/.codex/**",
]
LOCKFILES = ["uv.lock", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "poetry.lock", "Cargo.lock", "go.sum"]
TOOLKIT_PROTECTED = [
    "claude/CLAUDE*.md", "codex/AGENTS*.md", "shared/rules/**", "claude/rules/**",
    "claude/hooks/**", "claude/bin/**", "codex/hooks.json", "codex/agents/**", "codex/profiles/**",
    "claude/skills/gh-codex-drive/**", "claude/skills/gh-finish/**", "claude/skills/gh-roadmap-drive/**",
    "claude/managed-settings.json", "install/manifest.tsv",
    "docs/reports/accepted-exceptions.md", "docs/contracts/model-routing.tsv",
    "scripts/validate-layout.sh", ".github/workflows/**",
]


class DelegationError(Exception):
    pass


# ---------------------------------------------------------------- JSON schema (subset)
def schema_errors(value: object, schema: dict, where: str = "$") -> list[str]:
    """Validate the JSON Schema subset used by contract/report schemas."""
    errors: list[str] = []
    types = schema.get("type")
    if types is not None:
        allowed = types if isinstance(types, list) else [types]
        if not any(_is_type(value, t) for t in allowed):
            return [f"{where}: expected {'|'.join(allowed)}"]
    if value is None:
        return errors
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{where}: must be one of {schema['enum']}")
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errors.append(f"{where}: must not be empty")
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errors.append(f"{where}: does not match {schema['pattern']}")
    if isinstance(value, int) and not isinstance(value, bool) and "minimum" in schema and value < schema["minimum"]:
        errors.append(f"{where}: must be >= {schema['minimum']}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errors.append(f"{where}: needs at least {schema['minItems']} item(s)")
        for index, item in enumerate(value):
            errors += schema_errors(item, schema.get("items", {}), f"{where}[{index}]")
    if isinstance(value, dict):
        props = schema.get("properties", {})
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{where}: missing required key {key}")
        extra = schema.get("additionalProperties", True)
        for key, item in value.items():
            if key in props:
                errors += schema_errors(item, props[key], f"{where}.{key}")
            elif extra is False:
                errors.append(f"{where}: unexpected key {key}")
            elif isinstance(extra, dict):
                errors += schema_errors(item, extra, f"{where}.{key}")
    return errors


def _is_type(value: object, name: str) -> bool:
    return {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "null": value is None,
    }.get(name, False)


def load_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DelegationError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise DelegationError(f"{path}: top level must be an object")
    return data


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


# ---------------------------------------------------------------- git and state
def git(repo: Path, *args: str, binary: bool = False) -> str | bytes:
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, check=False)
    if result.returncode != 0:
        raise DelegationError(f"git {' '.join(args)} failed: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout if binary else result.stdout.decode()


def repo_root(start: Path) -> Path:
    return Path(str(git(start, "rev-parse", "--show-toplevel")).strip())


def state_dir(repo: Path) -> Path:
    return Path(str(git(repo, "rev-parse", "--absolute-git-dir")).strip()) / "agents-toolkit"


def state_paths(repo: Path, contract_id: str) -> dict[str, Path]:
    base = state_dir(repo)
    return {
        "dir": base,
        "contract": base / f"contract-{contract_id}.json",
        "prompt": base / f"prompt-{contract_id}.md",
        "result": base / f"result-{contract_id}.json",
        "jsonl": base / f"exec-{contract_id}.jsonl",
        "stderr": base / f"exec-{contract_id}.stderr",
        "evidence": base / f"evidence-{contract_id}.json",
        "active": base / "active.json",
    }


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def active_problem(active: dict, paths: dict) -> str:
    """Why a new delegation must not start while active.json exists."""
    contract_id = active.get("contract_id")
    if "exit_code" in active:
        return (f"another delegation is active ({contract_id}, codex exec exit {active['exit_code']}); "
                "verify and finish it, or clear it with ~/.claude/bin/delegation-evidence-check --clear")
    pid = active.get("pid")
    if isinstance(pid, int) and not pid_alive(pid):
        return (f"stale active delegation {contract_id}: its launcher (pid {pid}) stopped before codex exec finished "
                "(for example, the Claude session ended; claude -p ends with the turn). Inspect the worktree and "
                f"{paths['result']}, then clear it with ~/.claude/bin/delegation-evidence-check --clear")
    return f"another delegation is active ({contract_id}" + (f", launcher pid {pid} is running" if pid else "") + ")"


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def untracked(repo: Path) -> dict[str, str]:
    raw = str(git(repo, "ls-files", "--others", "--exclude-standard", "-z"))
    return {p: sha256_file(repo / p) for p in raw.split("\0") if p and (repo / p).is_file()}


def record_baseline(repo: Path) -> dict:
    return {
        "head": str(git(repo, "rev-parse", "HEAD")).strip(),
        "status": [line for line in str(git(repo, "status", "--porcelain")).splitlines() if line],
        "untracked": untracked(repo),
    }


def changes_since(repo: Path, baseline: dict) -> dict:
    """Files and lines changed since the baseline, counting new or modified untracked files."""
    head = baseline["head"]
    tracked = [p for p in str(git(repo, "diff", "--name-only", "-z", head)).split("\0") if p]
    lines = 0
    for row in str(git(repo, "diff", "--numstat", head)).splitlines():
        added, deleted, _path = row.split("\t", 2)
        lines += (int(added) if added.isdigit() else 0) + (int(deleted) if deleted.isdigit() else 0)
    before = baseline.get("untracked") or {}
    new_untracked = {p: h for p, h in untracked(repo).items() if before.get(p) != h}
    for path in new_untracked:
        try:
            lines += len((repo / path).read_text(encoding="utf-8", errors="replace").splitlines())
        except OSError:
            pass
    files = sorted(set(tracked) | set(new_untracked))
    digest = hashlib.sha256(bytes(git(repo, "diff", "--binary", head, binary=True)))
    for path, value in sorted(new_untracked.items()):
        digest.update(f"\0{path}\0{value}".encode())
    return {"files": files, "lines": lines, "diff_hash": digest.hexdigest(),
            "head": str(git(repo, "rev-parse", "HEAD")).strip()}


# ---------------------------------------------------------------- path rules
def glob_regex(pattern: str) -> re.Pattern[str]:
    """gitignore-style glob: no slash matches at any depth; '**' spans directories; trailing '/' is a prefix."""
    pattern = pattern.strip()
    directory = pattern.endswith("/")
    pattern = pattern.rstrip("/")
    anchored = "/" in pattern
    pattern = pattern.lstrip("/")
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?"); i += 3
        elif pattern.startswith("**", i):
            out.append(".*"); i += 2
        elif pattern[i] == "*":
            out.append("[^/]*"); i += 1
        elif pattern[i] == "?":
            out.append("[^/]"); i += 1
        else:
            out.append(re.escape(pattern[i])); i += 1
    body = "".join(out)
    prefix = "" if anchored else "(?:.*/)?"
    suffix = "/.*" if directory else "(?:/.*)?"
    return re.compile(f"^{prefix}{body}{suffix}$")


def matches_any(path: str, patterns: list[str]) -> bool:
    return any(glob_regex(p).match(path) for p in patterns)


def is_toolkit_repo(repo: Path) -> bool:
    return (repo / "install/manifest.tsv").is_file() and (repo / "docs/contracts/model-routing.tsv").is_file()


def protected_patterns(repo: Path, contract: dict) -> list[str]:
    patterns = list(ALWAYS_PROTECTED) + list(contract.get("protected_paths_extra") or [])
    if is_toolkit_repo(repo):
        patterns += TOOLKIT_PROTECTED
    return patterns


# ---------------------------------------------------------------- catalog and preflight
def codex_home() -> Path:
    return Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")


def catalog_levels() -> dict[str, list[str]]:
    path = codex_home() / "models_cache.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    levels = {}
    for model in data.get("models") or []:
        if isinstance(model, dict) and model.get("slug"):
            levels[model["slug"]] = [l.get("effort") if isinstance(l, dict) else l for l in model.get("supported_reasoning_levels") or []]
    return levels


def preflight_errors(contract_path: Path, repo: Path) -> list[str]:
    try:
        contract = load_json(contract_path)
    except DelegationError as exc:
        return [str(exc)]
    errors = [f"contract {e}" for e in schema_errors(contract, load_json(CONTRACT_SCHEMA))]
    if errors:
        return errors
    expected = state_paths(repo, contract["id"])["contract"]
    if contract_path.resolve() != expected.resolve():
        errors.append(f"contract must live at {expected} (got {contract_path})")
    route = contract["route"]
    if route["effort"] == "ultra":
        errors.append("route effort ultra is not allowed (it auto-delegates to subagents)")
    levels = catalog_levels()
    if not levels:
        errors.append(f"live Codex catalog is missing: {codex_home() / 'models_cache.json'}")
    elif route["model"] not in levels:
        errors.append(f"route model {route['model']} is not in the live Codex catalog")
    elif route["effort"] not in levels[route["model"]]:
        errors.append(f"route effort {route['effort']} is not supported by {route['model']} (catalog: {', '.join(levels[route['model']])})")
    profile = codex_home() / f"{PROFILE}.config.toml"
    if not profile.is_file():
        errors.append(f"Codex profile missing: {profile}")
    return errors


def render_prompt(contract: dict) -> str:
    text = PROMPT_TEMPLATE.read_text(encoding="utf-8")
    match = re.search(r"```text\n(.*?)\n```", text, re.S)
    if not match:
        raise DelegationError(f"prompt template block missing in {PROMPT_TEMPLATE}")

    def bullets(values: list[str]) -> str:
        return "\n".join(f"- {v}" for v in values) or "- None"

    fields = {
        "goal": contract["goal"],
        "acceptance_criteria": bullets(contract["acceptance_criteria"]),
        "scope_paths": bullets(contract["scope_paths"]),
        "required_checks": bullets(contract["required_checks"]),
        "diff_budget_files": str(contract["diff_budget"]["files"]),
        "diff_budget_lines": str(contract["diff_budget"]["lines"]),
        "allowed_dependency_changes": ", ".join(contract["allowed_dependency_changes"]) or "none",
        "non_goals": bullets(contract["non_goals"]),
        "invariants": bullets(contract["invariants"]),
    }
    return re.sub(r"\{([a-z_]+)\}", lambda m: fields.get(m.group(1), m.group(0)), match.group(1)) + "\n"
