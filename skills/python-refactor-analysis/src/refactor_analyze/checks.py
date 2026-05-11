from __future__ import annotations

import shutil
import subprocess
from collections.abc import Iterator
from dataclasses import asdict, dataclass
from pathlib import Path

from refactor_analyze.config import AnalysisConfig


@dataclass(frozen=True)
class CommandResult:
    name: str
    command: list[str]
    returncode: int | None
    stdout: str
    stderr: str
    skipped: bool = False
    timeout: bool = False
    unsupported: bool = False

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


def skipped_checks(reason: str) -> list[dict[str, object]]:
    return [
        CommandResult(
            name="checks",
            command=[],
            returncode=None,
            stdout="",
            stderr=reason,
            skipped=True,
        ).to_dict()
    ]


def run_checks(
    root: Path,
    config: AnalysisConfig,
    timeout_seconds: int | None = None,
) -> list[dict[str, object]]:
    timeout = timeout_seconds if timeout_seconds is not None else config.check_timeout_seconds
    commands = list(_enabled_commands(root, config))

    if not commands:
        return skipped_checks("No project checks are enabled.")

    if not _uv_available():
        return [
            _unsupported_command(name, command, "uv is required to run project checks.").to_dict()
            for name, command in commands
        ]

    if not _is_uv_project(root):
        reason = "Project checks require a uv project with pyproject.toml or uv.lock."
        return [_unsupported_command(name, command, reason).to_dict() for name, command in commands]

    results = []
    for name, command in commands:
        results.append(_run_command(name, command, root, timeout).to_dict())
    return results


def _enabled_commands(root: Path, config: AnalysisConfig) -> Iterator[tuple[str, list[str]]]:
    if config.run_ruff_check:
        yield "ruff", _uv_command(root, ["ruff", "check", "."])
    if config.run_mypy_check:
        yield "mypy", _uv_command(root, ["mypy", "."])
    if config.run_pytest_check:
        yield "pytest", _uv_command(root, ["pytest", "-q"])
    if config.run_pyright_check:
        yield "pyright", _uv_command(root, ["pyright"])
    if config.run_pyre_check:
        yield "pyre", _uv_command(root, ["pyre", "check"])
    if config.run_compile_check:
        yield "compileall", _uv_command(root, ["python", "-m", "compileall", "-q", str(root)])


def _uv_command(root: Path, args: list[str]) -> list[str]:
    return ["uv", "run", "--project", str(root), *args]


def _uv_available() -> bool:
    return shutil.which("uv") is not None


def _is_uv_project(root: Path) -> bool:
    return (root / "pyproject.toml").is_file() or (root / "uv.lock").is_file()


def _skipped_command(name: str, command: list[str], reason: str) -> CommandResult:
    return CommandResult(
        name=name,
        command=command,
        returncode=None,
        stdout="",
        stderr=reason,
        skipped=True,
    )


def _unsupported_command(name: str, command: list[str], reason: str) -> CommandResult:
    return CommandResult(
        name=name,
        command=command,
        returncode=None,
        stdout="",
        stderr=reason,
        unsupported=True,
    )


def _run_command(name: str, command: list[str], cwd: Path, timeout: int | None) -> CommandResult:
    try:
        completed = subprocess.run(
            command,
            cwd=cwd,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        return CommandResult(
            name=name,
            command=command,
            returncode=None,
            stdout=exc.stdout or "",
            stderr=exc.stderr or "",
            timeout=True,
        )
    except OSError as exc:
        return CommandResult(
            name=name,
            command=command,
            returncode=None,
            stdout="",
            stderr=str(exc),
        )

    return CommandResult(
        name=name,
        command=command,
        returncode=completed.returncode,
        stdout=completed.stdout[-6000:],
        stderr=completed.stderr[-6000:],
    )
