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

printf '%s\n' '{"skillOverrides": {"article-style": "user-invocable-only"}}' > "$SANDBOX/override.json"
out="$(python3 "$BUILD" "$SANDBOX/suite" --repo "$REPO_ROOT" --settings "$SANDBOX/override.json")"
included="$(ls "$SANDBOX/suite/skills" | tr '\n' ' ')"
expected="branch-cleanup gh-finish git-operations implementation-quality model-routing "
if [[ "$included" == "$expected" ]]; then ok "skillOverrides を適用し、モデルが起動できる5個だけを入れる"; else ng "included skills: $included"; fi
for name in break-consensus gh-test-first gh-roadmap-run; do
  if [[ "$out" == *"excluded: $name (manual-only)"* ]]; then ok "$name は manual-only として除く"; else ng "$name not excluded as manual-only: $out"; fi
done
if [[ "$out" == *"excluded: article-style (skillOverrides user-invocable-only)"* ]]; then ok "skillOverrides の user-invocable-only を除く"; else ng "article-style not excluded: $out"; fi
if jq -e '.name == "atk"' "$SANDBOX/suite/.claude-plugin/plugin.json" >/dev/null; then ok "plugin.json の name は atk"; else ng "plugin.json"; fi
if [[ ! -e "$SANDBOX/suite/skills/implementation-quality/SKILL.md" ]] || find "$SANDBOX/suite" -type l | grep -q .; then ng "skills are missing or still symlinks"; else ok "skill は symlink を解決して copy する"; fi

cases="$(ls "$SANDBOX/suite/evals" | wc -l)"
if [[ "$cases" -eq 5 && "$out" == *"cases: 5"* ]]; then ok "case は5件（article-style は起動できないので飛ばす）"; else ng "cases: $cases"; fi
bad=""
for d in "$SANDBOX"/suite/evals/*/; do
  grep -q '^max_turns: 2$' "$d/prompt.md" || bad+=" $(basename "$d"):max_turns"
  ls "$d"/graders/*.md >/dev/null 2>&1 || bad+=" $(basename "$d"):graders"
done
if [[ -z "$bad" ]]; then ok "各 case に prompt（2 turn まで）と grader がある"; else ng "case problems:$bad"; fi

out="$(python3 "$BUILD" "$SANDBOX/suite2" --repo "$REPO_ROOT" --settings "$SANDBOX/missing.json")"
if [[ -d "$SANDBOX/suite2/skills/article-style" ]]; then ok "settings が無ければ override を適用しない"; else ng "article-style missing without settings"; fi
if python3 - "$SANDBOX/suite2/evals/gh-finish/graders/fires-gh-finish.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
pattern = re.search(r"^input_match: '(.*)'$", text, re.M).group(1)
assert re.search(pattern, '{"skill": "atk:gh-finish"}')
assert re.search(pattern, '{"skill":"gh-finish"}')
assert not re.search(pattern, '{"skill": "atk:git-operations"}')
PY
then
  ok "input_match は namespace 付きの skill 名に一致し、別の skill には一致しない"
else
  ng "input_match regex"
fi
printf '%s\n' '{"skillOverrides": {"gh-finish": "off"}}' > "$SANDBOX/finish-off.json"
out="$(python3 "$BUILD" "$SANDBOX/suite3" --repo "$REPO_ROOT" --settings "$SANDBOX/finish-off.json")"
if [[ "$out" == *"skipped case: gh-finish (gh-finish is not model-invocable here)"* && ! -e "$SANDBOX/suite3/evals/git-operations/graders/not-gh-finish.md" ]]; then
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
