from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
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


def run_checks(root: Path, config: AnalysisConfig, timeout_seconds: int | None = None) -> list[dict[str, object]]:
    timeout = timeout_seconds if timeout_seconds is not None else config.check_timeout_seconds
    commands = list(_enabled_commands(root, config))

    if not commands:
        return skipped_checks("No project checks are enabled.")

    results = []
    for name, command, module in commands:
        if not _command_available(command[0], module):
            results.append(_skipped_command(name, command, f"{name} is not installed.").to_dict())
            continue
        results.append(_run_command(name, command, root, timeout).to_dict())
    return results


def _enabled_commands(
    root: Path, config: AnalysisConfig
) -> Iterator[tuple[str, list[str], str | None]]:
    py = sys.executable
    if config.run_ruff_check:
        yield "ruff", [py, "-m", "ruff", "check", "."], "ruff"
    if config.run_mypy_check:
        yield "mypy", [py, "-m", "mypy", "."], "mypy"
    if config.run_pytest_check:
        yield "pytest", [py, "-m", "pytest", "-q"], "pytest"
    if config.run_pyright_check:
        yield "pyright", ["pyright"], None
    if config.run_pyre_check:
        yield "pyre", ["pyre", "check"], None
    if config.run_compile_check:
        yield "compileall", [py, "-m", "compileall", "-q", str(root)], None


def _command_available(executable: str, module: str | None) -> bool:
    if module is not None:
        return importlib.util.find_spec(module) is not None
    if executable == sys.executable:
        return True
    return shutil.which(executable) is not None


def _skipped_command(name: str, command: list[str], reason: str) -> CommandResult:
    return CommandResult(
        name=name,
        command=command,
        returncode=None,
        stdout="",
        stderr=reason,
        skipped=True,
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
