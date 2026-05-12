from __future__ import annotations

import argparse
import json
from pathlib import Path

from refactor_analyze import __version__
from refactor_analyze.analyzer import analyze_project
from refactor_analyze.config import ConfigurationError


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="refactor-analyze")
    parser.add_argument("root", nargs="?", default=".", help="Python repository to analyze.")
    parser.add_argument("--out", default=".analysis", help="Output directory for reports.")
    parser.add_argument("--path", action="append", default=[], help="Focus a file or directory.")
    parser.add_argument("--diff", action="store_true", help="Focus files changed in git diff.")
    parser.add_argument("--profile", help="Configuration profile from pyproject.toml.")
    parser.add_argument("--skip-checks", action="store_true", help="Do not run project checks.")
    parser.add_argument("--skip-refactor-probes", action="store_true", help="Skip Rope occurrence probes.")
    parser.add_argument("--timeout", type=int, help="Timeout seconds for checks.")
    parser.add_argument("--json", action="store_true", help="Print the result JSON to stdout.")
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = analyze_project(
            Path(args.root),
            Path(args.out),
            paths=[Path(item) for item in args.path],
            diff=args.diff,
            run_project_checks=not args.skip_checks,
            profile=args.profile,
            skip_refactor_probes=args.skip_refactor_probes,
            timeout_seconds=args.timeout,
        )
    except ConfigurationError as exc:
        parser.error(str(exc))
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(f"Wrote {result['reports']['count']} report files to {result['output_dir']}")
        for path in result["reports"]["files"]:
            print(f"Wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
