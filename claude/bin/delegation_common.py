"""Shared helpers for the read-only Codex runs: JSON schema subset, JSON files, and the live Codex catalog.

Used by cross-critic, break-consensus-cross, and skill-tuneup (agents-toolkit). Codex is never
delegated implementation (owner decision 2026-10-11, Issue #14); the launcher, gate, and state helpers
that served the delegation skills were removed with it and remain only in git history.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path


class DelegationError(Exception):
    pass


# ---------------------------------------------------------------- JSON schema (subset)
def schema_errors(value: object, schema: dict, where: str = "$") -> list[str]:
    """Validate the JSON Schema subset used by the critic, divergent, and tuneup schemas."""
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
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append(f"{where}: longer than {schema['maxLength']} characters")
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


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---------------------------------------------------------------- live Codex catalog
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
