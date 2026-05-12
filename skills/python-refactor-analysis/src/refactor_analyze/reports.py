from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from refactor_analyze.config import AnalysisConfig
from refactor_analyze.report_markdown import (
    render_checks,
    render_hotspots,
    render_markdown,
    render_refactor_prompt,
    render_scopes,
    render_structure_map,
    render_structure_review,
    render_summary,
)


def write_reports(result: dict[str, Any], output_dir: Path, config: AnalysisConfig) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    files = {
        "summary": output_dir / "summary.md",
        "structure_map": output_dir / "structure_map.md",
        "structure_map_json": output_dir / "structure_map.json",
        "structure_review": output_dir / "structure_review.md",
        "findings": output_dir / "findings.json",
        "checks": output_dir / "checks.md",
        "hotspots": output_dir / "hotspots.md",
        "import_graph": output_dir / "import_graph.json",
        "refactor_prompt": output_dir / "refactor_prompt.md",
        "scopes": output_dir / "scopes.md",
        "analysis": output_dir / "analysis.md",
    }

    files["summary"].write_text(render_summary(result), encoding="utf-8")
    files["structure_map"].write_text(render_structure_map(result), encoding="utf-8")
    files["structure_map_json"].write_text(
        json.dumps(result["structure"], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    files["structure_review"].write_text(render_structure_review(result), encoding="utf-8")
    files["findings"].write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    files["checks"].write_text(render_checks(result), encoding="utf-8")
    files["hotspots"].write_text(render_hotspots(result), encoding="utf-8")
    files["import_graph"].write_text(
        json.dumps(
            {"imports": result["imports"], "focus": result["focus"], "calls": result["calls"]},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    files["refactor_prompt"].write_text(render_refactor_prompt(result), encoding="utf-8")
    files["scopes"].write_text(render_scopes(result), encoding="utf-8")
    files["analysis"].write_text(render_markdown(result), encoding="utf-8")

    ordered_files = [str(path) for path in files.values()]
    return {
        "json": str(files["findings"]),
        "markdown": str(files["summary"]),
        "analysis_markdown": str(files["analysis"]),
        "files": ordered_files,
        "count": len(ordered_files),
        **{name: str(path) for name, path in files.items()},
    }
