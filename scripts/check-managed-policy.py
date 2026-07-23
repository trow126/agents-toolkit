#!/usr/bin/env python3
"""Validate the toolkit's user/managed Claude Code policy split.

The security boundary lives in OS-managed settings. Lower-scope settings may be
supplied as fixtures; any project or project-local security-policy surface is
rejected because excluded-command and other array composition can otherwise
weaken the effective boundary.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SECURITY_KEYS = {
    "permissions",
    "sandbox",
    "hooks",
    "allowManagedHooksOnly",
    "allowManagedPermissionRulesOnly",
    "disableAutoMode",
    "requiredMinimumVersion",
}

REQUIRED_DENIES = {
    "Edit(.git/config)",
    "Edit(.git/hooks/**)",
    "Read(//**/.env)",
    "Read(//**/.env.*)",
    "Edit(//**/.env)",
    "Edit(//**/.env.*)",
}
REQUIRED_ALLOW_READ = {
    "~/.claude/bin",
    "~/.claude/skills",
    "~/.config/agents-toolkit",
}


def load_json(path: Path, label: str) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise ValueError(f"{label} file is missing: {path}") from None
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} file is not valid JSON: {path}: {exc}") from None
    if not isinstance(data, dict):
        raise ValueError(f"{label} root must be a JSON object: {path}")
    return data


def require(value: bool, message: str, errors: list[str]) -> None:
    if not value:
        errors.append(message)


def string_list(value: Any, path: str, errors: list[str]) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        errors.append(f"{path} must be an array of strings")
        return []
    return value


def validate_user(user: dict[str, Any], errors: list[str]) -> None:
    leaked = sorted(SECURITY_KEYS.intersection(user))
    require(
        not leaked,
        "user settings must not carry security policy keys; move them to managed settings: "
        + ", ".join(leaked),
        errors,
    )
    require(
        user.get("autoMemoryEnabled") is False,
        "user settings must set autoMemoryEnabled=false (no unmeasured native session injection)",
        errors,
    )


def validate_managed(managed: dict[str, Any], errors: list[str]) -> dict[str, Any]:
    require(
        managed.get("allowManagedHooksOnly") is True,
        "managed settings require allowManagedHooksOnly=true",
        errors,
    )
    require(
        managed.get("allowManagedPermissionRulesOnly") is True,
        "managed settings require allowManagedPermissionRulesOnly=true",
        errors,
    )

    require(
        managed.get("requiredMinimumVersion") == "2.1.218",
        'managed settings require requiredMinimumVersion="2.1.218"',
        errors,
    )

    permissions = managed.get("permissions")
    require(isinstance(permissions, dict), "managed permissions must be an object", errors)
    if not isinstance(permissions, dict):
        permissions = {}

    allow = string_list(permissions.get("allow"), "permissions.allow", errors)
    ask = string_list(permissions.get("ask"), "permissions.ask", errors)
    deny = string_list(permissions.get("deny"), "permissions.deny", errors)

    bash_allows = sorted(rule for rule in allow if rule.startswith("Bash("))
    require(
        not bash_allows,
        "managed permissions must not pre-approve Bash commands: " + ", ".join(bash_allows),
        errors,
    )
    require(
        permissions.get("disableBypassPermissionsMode") == "disable",
        'managed permissions.disableBypassPermissionsMode must be "disable"',
        errors,
    )
    require(
        managed.get("disableAutoMode") == "disable",
        'managed top-level disableAutoMode must be "disable"',
        errors,
    )
    require(
        "disableAutoMode" not in permissions,
        "permissions.disableAutoMode is invalid; disableAutoMode must be a top-level managed setting",
        errors,
    )
    require(
        permissions.get("defaultMode") == "default",
        'managed permissions.defaultMode must be "default"',
        errors,
    )
    require(
        ask == ["Bash"],
        "managed permissions.ask must be exactly [\"Bash\"] so built-in read-only Bash commands and excludedCommands cannot bypass approval",
        errors,
    )
    missing_denies = sorted(REQUIRED_DENIES.difference(deny))
    require(
        not missing_denies,
        "managed deny rules are missing: " + ", ".join(missing_denies),
        errors,
    )

    sandbox = managed.get("sandbox")
    require(isinstance(sandbox, dict), "managed sandbox must be an object", errors)
    if not isinstance(sandbox, dict):
        sandbox = {}
    require(sandbox.get("enabled") is True, "managed sandbox.enabled must be true", errors)
    require(
        sandbox.get("failIfUnavailable") is True,
        "managed sandbox.failIfUnavailable must be true",
        errors,
    )
    require(
        sandbox.get("allowUnsandboxedCommands") is False,
        "managed sandbox.allowUnsandboxedCommands must be false",
        errors,
    )
    require(
        sandbox.get("autoAllowBashIfSandboxed") is False,
        "managed sandbox.autoAllowBashIfSandboxed must be false so every Bash command keeps an approval gate",
        errors,
    )

    fs = sandbox.get("filesystem")
    require(isinstance(fs, dict), "managed sandbox.filesystem must be an object", errors)
    if not isinstance(fs, dict):
        fs = {}
    require(
        fs.get("allowManagedReadPathsOnly") is True,
        "managed sandbox.filesystem.allowManagedReadPathsOnly must be true",
        errors,
    )
    allow_read = set(string_list(fs.get("allowRead"), "sandbox.filesystem.allowRead", errors))
    missing_allow_read = sorted(REQUIRED_ALLOW_READ.difference(allow_read))
    require(
        not missing_allow_read,
        "managed allowRead is missing required toolkit paths: " + ", ".join(missing_allow_read),
        errors,
    )

    network = sandbox.get("network")
    require(isinstance(network, dict), "managed sandbox.network must be an object", errors)
    if not isinstance(network, dict):
        network = {}
    require(
        network.get("allowManagedDomainsOnly") is True,
        "managed sandbox.network.allowManagedDomainsOnly must be true",
        errors,
    )
    domains = string_list(network.get("allowedDomains"), "sandbox.network.allowedDomains", errors)
    require(not domains, "managed network allowedDomains must be empty/absent", errors)
    webfetch_allows = sorted(rule for rule in allow if rule.startswith("WebFetch(domain:"))
    require(
        not webfetch_allows,
        "managed WebFetch domain allows would pre-allow Bash egress: " + ", ".join(webfetch_allows),
        errors,
    )

    hooks = managed.get("hooks")
    require(isinstance(hooks, dict) and bool(hooks), "managed hooks must be a non-empty object", errors)

    return {
        "bash_allows": bash_allows,
        "excluded_commands": string_list(sandbox.get("excludedCommands"), "sandbox.excludedCommands", errors),
        "auto_allow_bash": sandbox.get("autoAllowBashIfSandboxed"),
    }


def validate_lower_scope(
    data: dict[str, Any], label: str, managed_summary: dict[str, Any], errors: list[str]
) -> list[str]:
    """Reject security policy at project/project-local scope.

    Managed precedence and the available managed-only locks cover most scalar
    and allowlist settings, but excludedCommands and related arrays still need a
    fail-closed project gate.  The toolkit therefore reserves all permission,
    hook, and sandbox policy for managed scope.
    """

    del managed_summary  # validation is deliberately independent of composition details
    attempted: list[str] = []
    for key in (
        "permissions",
        "hooks",
        "sandbox",
        "allowManagedHooksOnly",
        "allowManagedPermissionRulesOnly",
        "allowManagedMcpServersOnly",
        "disableAllHooks",
        "disableAutoMode",
        "requiredMinimumVersion",
    ):
        if key in data:
            attempted.append(f"{label}.{key}")

    env = data.get("env")
    if env is not None and not isinstance(env, dict):
        attempted.append(f"{label}.env(non-object)")
    elif isinstance(env, dict):
        prohibited_env = {
            "BASH_ENV", "ENV", "HOME", "PATH", "SHELLOPTS", "BASHOPTS",
            "LD_PRELOAD", "DYLD_INSERT_LIBRARIES", "PYTHONPATH", "NODE_OPTIONS",
            "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM", "CLAUDE_CONFIG_DIR",
            "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME",
        }
        attempted.extend(
            f"{label}.env.{key}" for key in sorted(prohibited_env.intersection(env))
        )

    if attempted:
        errors.append(
            f"{label} settings contain security policy surfaces reserved for managed scope: "
            + ", ".join(attempted)
        )
    return attempted


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--user", required=True, type=Path)
    parser.add_argument("--managed", required=True, type=Path)
    parser.add_argument("--project", type=Path)
    parser.add_argument("--local", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    errors: list[str] = []
    try:
        user = load_json(args.user, "user settings")
        managed = load_json(args.managed, "managed settings")
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    validate_user(user, errors)
    summary = validate_managed(managed, errors)
    attempted: list[str] = []
    for path, label in ((args.project, "project"), (args.local, "project-local")):
        if path is None:
            continue
        try:
            data = load_json(path, label)
        except ValueError as exc:
            errors.append(str(exc))
            continue
        attempted.extend(validate_lower_scope(data, label, summary, errors))

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print("OK: managed security policy and user-settings split are valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
