from __future__ import annotations

import tomllib
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any


SUPPORTED_PROFILES = ("full", "standard")


class ConfigurationError(ValueError):
    pass


@dataclass(frozen=True)
class AnalysisConfig:
    profile: str = "standard"
    package_roots: tuple[str, ...] = ()
    exclude_dirs: tuple[str, ...] = ()
    max_complexity: int = 10
    long_function_lines: int = 80
    large_file_lines: int = 500
    max_symbols: int = 25
    run_ruff_check: bool = True
    run_mypy_check: bool = True
    run_pytest_check: bool = True
    run_pyright_check: bool = False
    run_pyre_check: bool = False
    run_compile_check: bool = False
    skip_type_inference: bool = False
    skip_refactor_probes: bool = False
    check_timeout_seconds: int | None = 60


CONFIG_FILES = (
    "pyproject.toml",
    "refactor-analyze.toml",
    ".refactor-analyze.toml",
)


def load_config(root: Path, profile: str | None = None) -> AnalysisConfig:
    data: dict[str, Any] = {}
    for name in CONFIG_FILES:
        path = root / name
        if path.exists():
            data = _load_config_file(path)
            break

    tool_data = _tool_config(data)
    base = _profile_defaults("standard") | dict(tool_data.get("default", {}))
    requested_profile = str(profile or tool_data.get("profile") or "standard")
    if requested_profile not in SUPPORTED_PROFILES:
        allowed = ", ".join(SUPPORTED_PROFILES)
        raise ConfigurationError(f"--profile must be one of: {allowed}")

    base.update(_profile_defaults(requested_profile))
    base.update(
        {
            key: value
            for key, value in tool_data.items()
            if key not in {"default", "profile", "profiles"}
        }
    )
    base.update(tool_data.get("profiles", {}).get(requested_profile, {}))

    config = AnalysisConfig(profile=requested_profile)
    return _merge(config, base)


def _tool_config(data: dict[str, Any]) -> dict[str, Any]:
    tool = data.get("tool", {})
    if "refactor-analyze" in tool:
        return tool["refactor-analyze"]
    if "refactor_analyze" in tool:
        return tool["refactor_analyze"]
    if "refactor-analyze" in data:
        return data["refactor-analyze"]
    return data.get("refactor_analyze", data)


def _profile_defaults(profile: str) -> dict[str, Any]:
    if profile == "full":
        return {"skip_refactor_probes": False, "max_symbols": 50}
    return {"skip_refactor_probes": True, "max_symbols": 25}


def _load_config_file(path: Path) -> dict[str, Any]:
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        return {}


def _merge(config: AnalysisConfig, values: dict[str, Any]) -> AnalysisConfig:
    valid = set(AnalysisConfig.__dataclass_fields__)
    normalized: dict[str, Any] = {}
    for key, value in values.items():
        key = key.replace("-", "_")
        if key == "timeout":
            key = "check_timeout_seconds"
        if key not in valid:
            continue
        if key in {"exclude_dirs", "package_roots"} and isinstance(value, list):
            normalized[key] = tuple(str(item) for item in value)
        else:
            normalized[key] = value
    return replace(config, **normalized)
