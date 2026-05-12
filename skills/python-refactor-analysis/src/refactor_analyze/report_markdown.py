from __future__ import annotations

import re
from typing import Any


_MERMAID_ID_RE = re.compile(r"[^0-9A-Za-z]+")


def render_markdown(result: dict[str, Any]) -> str:
    return render_summary(result)


def render_summary(result: dict[str, Any]) -> str:
    repo = result.get("repo", {})
    focus = result.get("focus", {})
    imports = result.get("imports", {})
    lines = [
        "# Python Refactor Analysis",
        "",
        f"- Schema version: `{result.get('schema_version')}`",
        f"- Root: `{result['root']}`",
        f"- Generated: `{result['generated_at']}`",
        f"- Profile: `{repo.get('profile')}`",
        f"- Source layout: `{repo.get('source_layout')}`",
        f"- Package roots: `{', '.join(repo.get('package_roots', []))}`",
        f"- Python files: `{repo.get('python_file_count')}`",
        f"- Focus files: `{len(focus.get('files', []))}`",
        f"- Import provider: `{imports.get('provider')}`",
        "",
    ]
    _section(lines, "Focus", _focus(result))
    _section(lines, "Checks", _checks(result.get("checks", [])))
    _section(lines, "Hotspots", _hotspots(result))
    _section(lines, "Dead Code Candidates", _dead_code(result.get("refactor_probes", {})))
    _section(lines, "Parse Errors", _parse_errors(result.get("complexity", {})))
    _section(lines, "Refactor Notes", _refactor_notes(result))
    return _finish(lines)


def render_structure_map(result: dict[str, Any]) -> str:
    structure = result.get("structure", {})
    lines = [
        "# Structure Map",
        "",
        f"- Status: `{structure.get('status', 'ok')}`",
        f"- Python files: `{structure.get('file_count', 0)}`",
        "",
    ]
    for directory, files in structure.get("directories", {}).items():
        label = directory if directory != "." else "<root>"
        lines.append(f"## {label}")
        lines.append("")
        for file in files:
            lines.append(f"- `{file}`")
        lines.append("")
    return _finish(lines)


def render_structure_review(result: dict[str, Any]) -> str:
    repo = result.get("repo", {})
    architecture = result.get("architecture", {})
    imports = result.get("imports", {})
    calls = result.get("calls", {})
    symbols = result.get("symbols", {})
    lines = [
        "# Structure Review",
        "",
        f"- Source layout: `{repo.get('source_layout')}`",
        f"- Module names: `{', '.join(repo.get('module_names', []))}`",
        f"- Import provider: `{imports.get('provider')}`",
        f"- Import cycles: `{len(architecture.get('cycles', []))}`",
        f"- Call edges: `{len(calls.get('edges', []))}`",
        "",
    ]
    _section(lines, "Packages", _packages(architecture))
    _section(lines, "Cycles", _cycles(architecture))
    _section(lines, "Call Edges", _call_edges(calls))
    _section(lines, "Mermaid: Call Graph", _mermaid_call_graph(calls))
    _section(lines, "Mermaid: Class Inheritance", _mermaid_class_diagram(symbols))
    _section(lines, "Mermaid: Imports", _mermaid_import_graph(imports))
    return _finish(lines)


def render_scopes(result: dict[str, Any]) -> str:
    symbols = result.get("symbols", {})
    scopes = symbols.get("scopes", [])
    lines = [
        "# Variable Scopes",
        "",
        f"- Total entries: `{len(scopes)}`",
        "- Coverage: function arguments and `Assign` / `AnnAssign` targets only.",
        "- Comprehension, `for`, and `with` bindings are intentionally excluded.",
        "",
    ]
    args = [scope for scope in scopes if scope.get("kind") == "arg"]
    assigns = [scope for scope in scopes if scope.get("kind") == "assign"]
    _section(lines, "Arguments", _scope_table(args))
    _section(lines, "Assignments", _scope_table(assigns))
    return _finish(lines)


def render_checks(result: dict[str, Any]) -> str:
    lines = ["# Checks", ""]
    lines.extend(_checks(result.get("checks", [])) or ["No checks were recorded."])
    return _finish(lines)


def render_hotspots(result: dict[str, Any]) -> str:
    lines = ["# Hotspots", ""]
    lines.extend(_hotspots(result) or ["No notable hotspots."])
    return _finish(lines)


def render_refactor_prompt(result: dict[str, Any]) -> str:
    lines = [
        "# Recommended Refactor Prompt",
        "",
        "Use this prompt with the next coding agent:",
        "",
        "```text",
        "Plan a Python refactor without editing code yet.",
        "First read summary.md, structure_map.md, checks.md, structure_review.md, "
        "hotspots.md, and import_graph.json.",
        "Treat dead-code results as candidates only.",
        "Use structure, import, symbol, and check signals to decide what source "
        "files need close reading.",
        "Produce a scoped plan identifying affected modules, tests, risks, and rollback points.",
        "Implement only the smallest coherent change after plan acceptance.",
        "Rerun relevant checks.",
        "```",
        "",
        "## Structure-First Refactor Policy",
        "",
        "1. Read generated structure reports before reading implementation bodies.",
        "2. Use structure_map.md to identify high-value source files for close reading.",
        "3. Use import graph and focus impact to determine blast radius.",
        "4. Use hotspots to decide where characterization tests or smaller changes are needed.",
        "5. Use checks to determine whether the baseline is trustworthy.",
        "6. Use symbol/reference data and Rope probes to check rename, move, and cleanup risk.",
        "7. Use dead-code output only as a cleanup hypothesis.",
        "8. Read source code selectively after structural risks are known.",
        "9. Write a plan before implementation.",
        "",
        f"Generated for `{result['root']}`.",
    ]
    return _finish(lines)


def _section(lines: list[str], title: str, body: list[str]) -> None:
    lines.append(f"## {title}")
    lines.append("")
    lines.extend(body or ["No notable findings."])
    lines.append("")


def _focus(result: dict[str, Any]) -> list[str]:
    focus = result.get("focus", {})
    output = [f"- Impacted files: `{focus.get('impacted_count', 0)}`"]
    for key in ("files", "direct_dependencies", "related_tests", "impacted_files"):
        output.append(f"- {key.replace('_', ' ').title()}:")
        values = focus.get(key, [])
        output.extend(f"  - `{value}`" for value in values[:20])
        if not values:
            output.append("  - None")
    selection = focus.get("selection", {})
    diff = selection.get("diff", {})
    output.append(f"- Diff focus enabled: `{diff.get('enabled', False)}`")
    output.append(f"- Defaulted to all files: `{selection.get('defaulted_to_all', False)}`")
    return output


def _checks(checks: list[dict[str, Any]]) -> list[str]:
    output = []
    for check in checks:
        if check.get("unsupported"):
            status = "unsupported"
        elif check.get("skipped"):
            status = "skipped"
        elif check.get("timeout"):
            status = "timeout"
        elif check.get("returncode") == 0:
            status = "passed"
        else:
            status = f"failed ({check.get('returncode')})"
        output.append(f"- `{check.get('name')}`: {status}")
        if check.get("stderr") and (check.get("skipped") or check.get("unsupported")):
            output.append(f"  - {check['stderr']}")
    return output


def _hotspots(result: dict[str, Any]) -> list[str]:
    complexity = result.get("complexity", {})
    architecture = result.get("architecture", {})
    output = []
    for item in complexity.get("high_complexity", [])[:10]:
        output.append(
            f"- `{item['file']}`:{item['line']} `{item['name']}` complexity {item['complexity']}"
        )
    for item in complexity.get("long_functions", [])[:10]:
        output.append(f"- `{item['file']}`:{item['line']} `{item['name']}` length {item['length']}")
    for item in architecture.get("hotspots", [])[:10]:
        output.append(f"- `{item['file']}` fan-in {item['fan_in']}, fan-out {item['fan_out']}")
    return output


def _dead_code(refactor_probes: dict[str, Any]) -> list[str]:
    output = [
        f"- Rope provider status: `{refactor_probes.get('status')}`",
        "- Caveat: dead-code results are candidates only; dynamic references may be missed.",
    ]
    for item in refactor_probes.get("dead_code_candidates", [])[:20]:
        output.append(f"- `{item['file']}`:{item['line']} `{item['name']}`")
    return output


def _parse_errors(complexity: dict[str, Any]) -> list[str]:
    output = []
    for item in complexity.get("parse_errors", []):
        output.append(f"- `{item['file']}` {item['error']}: {item['message']}")
    return output


def _refactor_notes(result: dict[str, Any]) -> list[str]:
    return [
        "- Read `refactor_prompt.md` before starting code changes.",
        "- Keep the first refactor scoped to the smallest coherent change.",
        f"- Import cycles reported: `{len(result.get('architecture', {}).get('cycles', []))}`",
    ]


def _packages(architecture: dict[str, Any]) -> list[str]:
    return [
        f"- `{item['name']}`: `{item['python_files']}` Python files"
        for item in architecture.get("packages", [])
    ]


def _cycles(architecture: dict[str, Any]) -> list[str]:
    return [
        f"- SCC ({len(cycle)}): " + ", ".join(f"`{item}`" for item in cycle)
        for cycle in architecture.get("cycles", [])
    ]


def _call_edges(calls: dict[str, Any]) -> list[str]:
    output = []
    for edge in calls.get("edges", [])[:25]:
        output.append(f"- `{edge['file']}`:{edge['line']} `{edge['caller']}` -> `{edge['callee']}`")
    return output


def _mermaid_id(value: str) -> str:
    sanitized = _MERMAID_ID_RE.sub("_", value).strip("_")
    if not sanitized:
        return "node"
    if sanitized[0].isdigit():
        return f"n_{sanitized}"
    return sanitized


def _mermaid_block(header: str, body: list[str], note: str) -> list[str]:
    if not body:
        return [f"_No data for {header}._"]
    lines = ["```mermaid", header, *body, "```", "", note]
    return lines


def _mermaid_call_graph(calls: dict[str, Any], *, top: int = 80) -> list[str]:
    edges = calls.get("edges", [])
    seen: set[tuple[str, str]] = set()
    body: list[str] = []
    for edge in edges:
        caller = str(edge.get("caller") or "<module>")
        callee = str(edge.get("callee") or "")
        if not callee:
            continue
        key = (caller, callee)
        if key in seen:
            continue
        seen.add(key)
        caller_id = _mermaid_id(caller)
        callee_id = _mermaid_id(callee)
        body.append(f'    {caller_id}["{caller}"] --> {callee_id}["{callee}"]')
        if len(body) >= top:
            break
    note = f"_Filtered to first {top} unique caller→callee pairs._"
    return _mermaid_block("flowchart LR", body, note)


def _mermaid_class_diagram(symbols: dict[str, Any], *, top: int = 50) -> list[str]:
    body: list[str] = []
    seen: set[tuple[str, str]] = set()
    for symbol in symbols.get("symbols", []):
        if symbol.get("kind") != "ClassDef":
            continue
        bases = symbol.get("bases") or []
        if not bases:
            continue
        sub = str(symbol.get("name") or "")
        if not sub:
            continue
        for base in bases:
            key = (base, sub)
            if key in seen:
                continue
            seen.add(key)
            body.append(f"    {base} <|-- {sub}")
            if len(body) >= top:
                break
        if len(body) >= top:
            break
    note = f"_Filtered to first {top} inheritance edges._"
    return _mermaid_block("classDiagram", body, note)


def _mermaid_import_graph(imports: dict[str, Any], *, top: int = 30) -> list[str]:
    graph: dict[str, list[str]] = imports.get("graph", {}) or {}
    if not graph:
        return ["_No import edges available._"]
    fan_in: dict[str, int] = {}
    fan_out: dict[str, int] = {}
    for source, targets in graph.items():
        fan_out[source] = len(targets)
        for target in targets:
            fan_in[target] = fan_in.get(target, 0) + 1
    nodes = set(fan_in) | set(fan_out)
    ranked = sorted(
        nodes,
        key=lambda node: (fan_in.get(node, 0) + fan_out.get(node, 0), node),
        reverse=True,
    )[:top]
    selected = set(ranked)
    body: list[str] = []
    for source in ranked:
        for target in graph.get(source, []):
            if target not in selected:
                continue
            source_id = _mermaid_id(source)
            target_id = _mermaid_id(target)
            body.append(f'    {source_id}["{source}"] --> {target_id}["{target}"]')
    note = f"_Filtered to top {top} fan-in+fan-out nodes._"
    return _mermaid_block("flowchart LR", body, note)


def _scope_table(scopes: list[dict[str, Any]]) -> list[str]:
    if not scopes:
        return ["_No entries._"]
    lines = [
        "| File | Scope | Name | Line |",
        "| --- | --- | --- | --- |",
    ]
    for scope in scopes[:200]:
        lines.append(
            f"| `{scope.get('file')}` | `{scope.get('scope')}` | `{scope.get('name')}` | {scope.get('line')} |"
        )
    if len(scopes) > 200:
        lines.append(f"_Truncated to first 200 of {len(scopes)} entries._")
    return lines


def _finish(lines: list[str]) -> str:
    return "\n".join(lines).rstrip() + "\n"
