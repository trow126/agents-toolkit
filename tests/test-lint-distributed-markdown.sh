#!/usr/bin/env bash
# lint-distributed-markdown.sh: manifest-distributed tracked Markdown only, all violations listed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINTER="$REPO_ROOT/scripts/lint-distributed-markdown.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

run_linter() {
  local rc=0
  OUT="$("$LINTER" "$@" 2>&1)" || rc=$?
  RC="$rc"
}

run_linter
if [[ "$RC" -eq 0 ]]; then ok "実 repo の配布 Markdown は lint-clean"; else ng "実 repo: $OUT"; fi

fixture="$SANDBOX/repo"
mkdir -p "$fixture/install" "$fixture/skills/sample" "$fixture/docs"
git -C "$fixture" init -q
printf 'link-dir\tskills/sample\t.claude/skills/sample\n' > "$fixture/install/manifest.tsv"
printf '# Title\n\nbody\n' > "$fixture/skills/sample/SKILL.md"
printf '# Title\nno blank line\n' > "$fixture/skills/sample/broken.md"
printf '# Untracked\nno blank line\n' > "$fixture/skills/sample/untracked.md"
printf '# Not distributed\nno blank line\n' > "$fixture/docs/notes.md"
git -C "$fixture" add install/manifest.tsv skills/sample/SKILL.md skills/sample/broken.md docs/notes.md

run_linter --repo "$fixture"
if [[ "$RC" -ne 0 ]]; then ok "fixture: 違反があれば非ゼロ終了"; else ng "fixture: 違反を検出しない"; fi
if [[ "$OUT" == *"skills/sample/broken.md:1"* ]]; then ok "fixture: 配布 Markdown の違反を報告"; else ng "fixture: broken.md を報告しない: $OUT"; fi
if [[ "$OUT" != *"untracked.md"* && "$OUT" != *"docs/notes.md"* ]]; then
  ok "fixture: 未追跡と manifest 外は対象外"
else
  ng "fixture: 対象外のファイルを検査した: $OUT"
fi

printf '# Title\n\nfixed\n' > "$fixture/skills/sample/broken.md"
run_linter --repo "$fixture"
if [[ "$RC" -eq 0 && "$OUT" == *"PASS: 2 distributed Markdown files"* ]]; then ok "fixture: 修正後は PASS"; else ng "fixture: 修正後: $OUT"; fi

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
