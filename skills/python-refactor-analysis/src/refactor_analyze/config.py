from __future__ import annotations

import tomllib
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any


SUPPORTED_PROFILES = ("full", "standard")


class ConfigurationError(ValueError):
    """Raised when analysis configuration is invalid."""


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
    tool_data: dict[str, Any] = {}
    for name in CONFIG_FILES:
        path = root / name
        if path.exists():
            data = _load_config_file(path)
            candidate = _tool_config(data, path)
            if candidate or path.name != "pyproject.toml":
                tool_data = candidate
                break

    base = _profile_defaults("standard")
    base.update(_optional_mapping(tool_data, "default"))
    requested_profile = _requested_profile(tool_data, profile)
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
    profiles = _optional_mapping(tool_data, "profiles")
    if requested_profile in profiles:
        base.update(_mapping_value(profiles[requested_profile], f"profiles.{requested_profile}"))

    config = AnalysisConfig(profile=requested_profile)
    return _merge(config, base)


def _tool_config(data: dict[str, Any], path: Path) -> dict[str, Any]:
    if path.name == "pyproject.toml":
        if "tool" not in data:
            return {}
        tool = _mapping_value(data["tool"], "tool")
        if "refactor-analyze" in tool:
            return _mapping_value(tool["refactor-analyze"], "tool.refactor-analyze")
        if "refactor_analyze" in tool:
            return _mapping_value(tool["refactor_analyze"], "tool.refactor_analyze")
        return {}

    if "refactor-analyze" in data:
        return _mapping_value(data["refactor-analyze"], "refactor-analyze")
    if "refactor_analyze" in data:
        return _mapping_value(data["refactor_analyze"], "refactor_analyze")
    return _mapping_value(data, str(path))


def _profile_defaults(profile: str) -> dict[str, Any]:
    if profile == "full":
        return {"skip_refactor_probes": False, "max_symbols": 50}
    return {"skip_refactor_probes": True, "max_symbols": 25}


def _load_config_file(path: Path) -> dict[str, Any]:
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ConfigurationError(f"Failed to read config file {path}: {exc}") from exc
    except tomllib.TOMLDecodeError as exc:
        raise ConfigurationError(f"Failed to parse config file {path}: {exc}") from exc


def _requested_profile(tool_data: dict[str, Any], profile: str | None) -> str:
    if profile is not None:
        return profile
    if "profile" not in tool_data:
        return "standard"
    value = tool_data["profile"]
    if not isinstance(value, str):
        raise ConfigurationError("Configuration key 'profile' must be a string.")
    return value


def _optional_mapping(values: dict[str, Any], key: str) -> dict[str, Any]:
    if key not in values:
        return {}
    return _mapping_value(values[key], key)


def _mapping_value(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ConfigurationError(f"Configuration section '{label}' must be a table.")
    return value


def _merge(config: AnalysisConfig, values: dict[str, Any]) -> AnalysisConfig:
    valid = set(AnalysisConfig.__dataclass_fields__)
    normalized: dict[str, Any] = {}
    for key, value in values.items():
        key = key.replace("-", "_")
        if key == "timeout":
            key = "check_timeout_seconds"
        if key not in valid:
            raise ConfigurationError(f"Unsupported configuration key: {key}")
        if key in {"exclude_dirs", "package_roots"} and isinstance(value, list):
            normalized[key] = tuple(str(item) for item in value)
        else:
            normalized[key] = value
    return replace(config, **normalized)
