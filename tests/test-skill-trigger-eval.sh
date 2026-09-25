#!/usr/bin/env bash
# build-skill-trigger-eval.py (K8): the suite holds only model-invocable Claude skills (no manual-only,
# no skillOverrides off / user-invocable-only), every case has a prompt and graders, and the
# tool_used regex matches a namespaced Skill input. No model is called.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD="$REPO_ROOT/scripts/build-skill-trigger-eval.py"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
export PYTHONDONTWRITEBYTECODE=1

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

printf '%s\n' '{"skillOverrides": {"gh-pr": "user-invocable-only", "gh-review": "user-invocable-only", "config-audit": "user-invocable-only", "gh-index": "user-invocable-only", "python-refactor-analysis": "user-invocable-only"}}' > "$SANDBOX/live-like.json"
out="$(python3 "$BUILD" "$SANDBOX/suite" --repo "$REPO_ROOT" --settings "$SANDBOX/live-like.json")"
included="$(ls "$SANDBOX/suite/skills" | tr '\n' ' ')"
expected="article-style branch-cleanup gh-codex-drive gh-finish gh-issue gh-start git-operations implementation-quality issue-writing model-routing "
if [[ "$included" == "$expected" ]]; then ok "live と同じ skillOverrides なら、モデルが起動できる10個だけを入れる"; else ng "included skills: $included"; fi
for name in break-consensus knowledge-audit gh-roadmap-drive; do
  if [[ "$out" == *"excluded: $name (manual-only)"* ]]; then ok "$name は manual-only として除く"; else ng "$name not excluded as manual-only: $out"; fi
done
if [[ "$out" == *"excluded: gh-pr (skillOverrides user-invocable-only)"* ]]; then ok "skillOverrides の user-invocable-only を除く"; else ng "gh-pr not excluded: $out"; fi
if jq -e '.name == "atk"' "$SANDBOX/suite/.claude-plugin/plugin.json" >/dev/null; then ok "plugin.json の name は atk"; else ng "plugin.json"; fi
if [[ ! -e "$SANDBOX/suite/skills/implementation-quality/SKILL.md" ]] || find "$SANDBOX/suite" -type l | grep -q .; then ng "skills are missing or still symlinks"; else ok "skill は symlink を解決して copy する"; fi

cases="$(ls "$SANDBOX/suite/evals" | wc -l)"
if [[ "$cases" -eq 12 && "$out" == *"cases: 12"* ]]; then ok "case は12件"; else ng "cases: $cases"; fi
bad=""
for d in "$SANDBOX"/suite/evals/*/; do
  grep -q '^max_turns: 2$' "$d/prompt.md" || bad+=" $(basename "$d"):max_turns"
  ls "$d"/graders/*.md >/dev/null 2>&1 || bad+=" $(basename "$d"):graders"
done
if [[ -z "$bad" ]]; then ok "各 case に prompt（2 turn まで）と grader がある"; else ng "case problems:$bad"; fi
if grep -q '^max: 0$' "$SANDBOX/suite/evals/no-implicit-codex/graders/not-gh-codex-drive.md" \
   && [[ ! -e "$SANDBOX/suite/evals/no-implicit-codex/graders/fires-gh-codex-drive.md" ]]; then
  ok "D3①: 明示の無い実装依頼で gh-codex-drive が起動しないことを判定する"
else
  ng "no-implicit-codex grader"
fi

if python3 - "$SANDBOX/suite/evals/gh-start/graders/fires-gh-start.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
pattern = re.search(r"^input_match: '(.*)'$", text, re.M).group(1)
assert re.search(pattern, '{"skill": "atk:gh-start"}')
assert re.search(pattern, '{"skill":"gh-start"}')
assert not re.search(pattern, '{"skill": "atk:gh-codex-drive"}')
PY
then
  ok "input_match は namespace 付きの skill 名に一致し、別の skill には一致しない"
else
  ng "input_match regex"
fi

out="$(python3 "$BUILD" "$SANDBOX/suite2" --repo "$REPO_ROOT" --settings "$SANDBOX/missing.json")"
if [[ -d "$SANDBOX/suite2/skills/gh-pr" ]]; then ok "settings が無ければ override を適用しない"; else ng "gh-pr missing without settings"; fi
printf '%s\n' '{"skillOverrides": {"gh-start": "off"}}' > "$SANDBOX/start-off.json"
out="$(python3 "$BUILD" "$SANDBOX/suite3" --repo "$REPO_ROOT" --settings "$SANDBOX/start-off.json")"
if [[ "$out" == *"skipped case: gh-start (gh-start is not model-invocable here)"* && ! -e "$SANDBOX/suite3/evals/gh-codex-drive/graders/not-gh-start.md" ]]; then
  ok "起動できない skill の case は飛ばし、その skill を判定しない"
else
  ng "skip logic: $out"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
