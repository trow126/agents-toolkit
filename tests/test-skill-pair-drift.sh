#!/usr/bin/env bash
# Skill pairs across runtimes (§6.5). The skills kept per runtime (break-consensus, config-audit) may
# differ only by the reviewed lines in tests/fixtures/skill-pair-drift/<name>.diff, after the
# invocation prefix (/name, $name) and the reference path (../../name/references/) are normalized.
# The merged skills (gh-issue, gh-pr, gh-review, gh-start) have one source dir linked into both
# runtimes, and only their "Invoked as" line names a runtime. No model is called.
#
# After a reviewed change to either copy of a kept pair: bash tests/test-skill-pair-drift.sh --update
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures/skill-pair-drift"
UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1
FAILURES=0

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

results="$(python3 - "$REPO_ROOT" "$FIXTURES" "$UPDATE" <<'PY'
import difflib
import re
import sys
from pathlib import Path

root, fixtures, update = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3] == "1"
PAIRS = ("break-consensus", "config-audit")
# Same name in both runtimes, different content by design: no drift test.
EXCLUDED = {"model-routing": "Claude model assignment and Codex agent routing are different procedures"}
MERGED = ("gh-issue", "gh-pr", "gh-review", "gh-start")


def normalize(text, name):
    text = re.sub(rf"(?<![\w./~-])[/$]{re.escape(name)}\b", f"<invoke>{name}", text)
    return text.replace(f"../../{name}/references/", "references/").splitlines()


def skills(runtime):
    return {p.parent.name for p in (root / "shared/skills" / runtime).glob("*/SKILL.md")}


both = skills("claude-code") & skills("codex")
unknown = sorted(both - set(PAIRS) - set(EXCLUDED))
if unknown:
    print(f"FAIL\tper-runtime pairs without a drift test or a recorded exclusion: {', '.join(unknown)}")
else:
    print("ok\tevery per-runtime pair has a drift test or a recorded exclusion (model-routing: " + EXCLUDED["model-routing"] + ")")

for name in PAIRS:
    a = normalize((root / f"shared/skills/claude-code/{name}/SKILL.md").read_text(encoding="utf-8"), name)
    b = normalize((root / f"shared/skills/codex/{name}/SKILL.md").read_text(encoding="utf-8"), name)
    # Hunk positions are dropped so that a change made to both copies does not count as drift.
    lines = ["@@" if line.startswith("@@") else line
             for line in difflib.unified_diff(a, b, "claude-code", "codex", n=0, lineterm="")]
    actual = "\n".join(lines) + "\n"
    fixture = fixtures / f"{name}.diff"
    if update:
        fixture.parent.mkdir(parents=True, exist_ok=True)
        fixture.write_text(actual, encoding="utf-8")
        print(f"ok\t{name}: fixture updated")
        continue
    expected = fixture.read_text(encoding="utf-8") if fixture.is_file() else ""
    if actual == expected:
        print(f"ok\t{name}: the Claude and Codex copies differ only by the reviewed lines")
    else:
        print(f"FAIL\t{name}: the copies drifted from tests/fixtures/skill-pair-drift/{name}.diff (edit both copies, or review and run --update)")
        for line in difflib.unified_diff(expected.splitlines(), actual.splitlines(), "fixture", "actual", lineterm=""):
            print(f"info\t    {line}")

manifest = (root / "install/manifest.tsv").read_text(encoding="utf-8")
links = {tuple(line.split("\t")[1:3]) for line in manifest.splitlines() if line.startswith("link-dir\t")}
for name in MERGED:
    skill = root / f"shared/skills/{name}/SKILL.md"
    problems = []
    if not skill.is_file():
        problems.append("SKILL.md missing")
    for runtime in ("claude-code", "codex"):
        if (root / f"shared/skills/{runtime}/{name}").exists():
            problems.append(f"shared/skills/{runtime}/{name} still exists")
    for target in (f".claude/skills/{name}", f".agents/skills/{name}"):
        if (f"shared/skills/{name}", target) not in links:
            problems.append(f"manifest does not link shared/skills/{name} to {target}")
    if skill.is_file():
        text = skill.read_text(encoding="utf-8")
        runtime_lines = [line for line in text.splitlines() if re.search(rf"(?<![\w./~-])[/$]{re.escape(name)}\b", line)]
        if len(runtime_lines) != 1 or not runtime_lines[0].startswith("Invoked as "):
            problems.append(f"lines naming a runtime invocation: {runtime_lines}")
        if "../../" in text:
            problems.append("cites ../../ (the references sit in the skill dir)")
        if not (root / f"shared/skills/{name}/references").is_dir() or (root / f"shared/skills/{name}/references").is_symlink():
            problems.append("references is not a directory in the skill dir")
    if problems:
        print(f"FAIL\t{name}: " + "; ".join(problems))
    else:
        print(f"ok\t{name}: one source dir for both runtimes; only the 'Invoked as' line names a runtime")
PY
)"

while IFS=$'\t' read -r status message; do
  case "$status" in
    ok) ok "$message" ;;
    FAIL) ng "$message" ;;
    info) echo "$message" >&2 ;;
  esac
done <<< "$results"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
