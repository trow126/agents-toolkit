from __future__ import annotations

import subprocess
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest

from refactor_analyze import checks
from refactor_analyze.cli import main
from refactor_analyze.config import AnalysisConfig, ConfigurationError, load_config
from refactor_analyze.refactors import _fallback_occurrences
from refactor_analyze.report_markdown import render_checks


SKILL_ROOT = Path(__file__).resolve().parents[1]


def write_pyproject(root: Path) -> None:
    root.joinpath("pyproject.toml").write_text(
        "\n".join(
            [
                "[project]",
                'name = "sample-project"',
                'version = "0.1.0"',
                'requires-python = ">=3.11"',
                "",
            ]
        ),
        encoding="utf-8",
    )


def test_run_checks_uses_target_uv_project(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    write_pyproject(tmp_path)
    calls: list[tuple[list[str], dict[str, Any]]] = []

    def fake_run(command: list[str], **kwargs: Any) -> SimpleNamespace:
        calls.append((command, kwargs))
        return SimpleNamespace(returncode=0, stdout="ok\n", stderr="")

    monkeypatch.setattr(checks, "_uv_available", lambda: True)
    monkeypatch.setattr(checks.subprocess, "run", fake_run)

    config = AnalysisConfig(run_mypy_check=False, run_pytest_check=False)
    results = checks.run_checks(tmp_path, config, timeout_seconds=7)

    assert [result["name"] for result in results] == ["ruff"]
    command, kwargs = calls[0]
    assert command == ["uv", "run", "--project", str(tmp_path), "ruff", "check", "."]
    assert kwargs["cwd"] == tmp_path
    assert kwargs["timeout"] == 7
    assert results[0]["returncode"] == 0
    assert results[0]["stdout"] == "ok\n"


def test_run_checks_reports_non_uv_project_as_unsupported(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(checks, "_uv_available", lambda: True)

    def fail_run(*_args: Any, **_kwargs: Any) -> None:
        pytest.fail("non-uv projects must not execute project checks")

    monkeypatch.setattr(checks.subprocess, "run", fail_run)

    config = AnalysisConfig(run_mypy_check=False, run_pytest_check=False)
    results = checks.run_checks(tmp_path, config)

    assert len(results) == 1
    assert results[0]["name"] == "ruff"
    assert results[0]["unsupported"] is True
    assert results[0]["returncode"] is None
    assert "uv project" in str(results[0]["stderr"])


def test_run_checks_reports_missing_uv_as_unsupported(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    write_pyproject(tmp_path)
    monkeypatch.setattr(checks, "_uv_available", lambda: False)

    results = checks.run_checks(
        tmp_path,
        AnalysisConfig(run_mypy_check=False, run_pytest_check=False),
    )

    assert results[0]["unsupported"] is True
    assert "uv is required" in str(results[0]["stderr"])


def test_load_config_ignores_unrelated_pyproject(tmp_path: Path) -> None:
    write_pyproject(tmp_path)

    config = load_config(tmp_path)

    assert config.profile == "standard"
    assert config.max_symbols == 25


def test_load_config_reads_dedicated_config_after_plain_pyproject(tmp_path: Path) -> None:
    write_pyproject(tmp_path)
    tmp_path.joinpath("refactor-analyze.toml").write_text(
        "\n".join(
            [
                'profile = "full"',
                "max-symbols = 12",
                "",
            ]
        ),
        encoding="utf-8",
    )

    config = load_config(tmp_path)

    assert config.profile == "full"
    assert config.max_symbols == 12
    assert config.skip_refactor_probes is False


def test_load_config_rejects_broken_toml(tmp_path: Path) -> None:
    tmp_path.joinpath("pyproject.toml").write_text(
        "[tool.refactor-analyze\n",
        encoding="utf-8",
    )

    with pytest.raises(ConfigurationError, match="Failed to parse config file"):
        load_config(tmp_path)


def test_load_config_rejects_unknown_keys(tmp_path: Path) -> None:
    tmp_path.joinpath("pyproject.toml").write_text(
        "\n".join(
            [
                "[tool.refactor-analyze]",
                "unknown-key = true",
                "",
            ]
        ),
        encoding="utf-8",
    )

    with pytest.raises(ConfigurationError, match="Unsupported configuration key: unknown_key"):
        load_config(tmp_path)


def test_cli_writes_reports_for_minimal_project(tmp_path: Path) -> None:
    repo = tmp_path / "repo"
    repo.mkdir()
    write_pyproject(repo)
    repo.joinpath("app.py").write_text("def main():\n    return 1\n", encoding="utf-8")
    output_dir = tmp_path / "analysis"

    exit_code = main([str(repo), "--out", str(output_dir), "--skip-checks"])

    assert exit_code == 0
    assert output_dir.joinpath("summary.md").is_file()
    assert output_dir.joinpath("findings.json").is_file()
    assert "Project checks were skipped" in output_dir.joinpath("checks.md").read_text(
        encoding="utf-8"
    )


def test_fallback_occurrences_records_read_errors(tmp_path: Path) -> None:
    source = tmp_path / "app.py"
    source.write_text("def target():\n    return 1\n", encoding="utf-8")
    invalid = tmp_path / "invalid.py"
    invalid.write_bytes(b"\xff")
    symbol_data = {
        "symbols": [
            {
                "file": "app.py",
                "name": "target",
                "kind": "FunctionDef",
                "line": 1,
            }
        ]
    }

    probes, errors = _fallback_occurrences(tmp_path, [source, invalid], symbol_data, 10)

    assert probes[0]["name"] == "target"
    assert probes[0]["occurrences"] == 1
    assert errors[0]["file"] == "invalid.py"
    assert errors[0]["error"] == "UnicodeDecodeError"


def test_render_checks_distinguishes_statuses() -> None:
    markdown = render_checks(
        {
            "checks": [
                {
                    "name": "ruff",
                    "returncode": 0,
                    "stdout": "",
                    "stderr": "",
                    "skipped": False,
                    "timeout": False,
                    "unsupported": False,
                },
                {
                    "name": "mypy",
                    "returncode": 1,
                    "stdout": "",
                    "stderr": "",
                    "skipped": False,
                    "timeout": False,
                    "unsupported": False,
                },
                {
                    "name": "pytest",
                    "returncode": None,
                    "stdout": "",
                    "stderr": "uv project required",
                    "skipped": False,
                    "timeout": False,
                    "unsupported": True,
                },
            ]
        }
    )

    assert "`ruff`: passed" in markdown
    assert "`mypy`: failed (1)" in markdown
    assert "`pytest`: unsupported" in markdown
    assert "uv project required" in markdown


def test_wrapper_requires_uv_without_python_fallback(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    dirname = bin_dir / "dirname"
    dirname.write_text(
        "\n".join(
            [
                "#!/bin/sh",
                'case "$1" in',
                '  */*) printf "%s\\n" "${1%/*}" ;;',
                '  *) printf ".\\n" ;;',
                "esac",
                "",
            ]
        ),
        encoding="utf-8",
    )
    dirname.chmod(0o755)

    result = subprocess.run(
        ["/bin/sh", str(SKILL_ROOT / "scripts" / "refactor-analyze"), "--version"],
        env={"PATH": str(bin_dir)},
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 127
    assert "requires uv" in result.stderr
    assert "No module named" not in result.stderr
