#!/usr/bin/env bash
# test-no-codex-implementation.sh — Codex へ実装を委任しない（Issue #14、owner 決定 2026-10-11）。
# 委任の skill・launcher・gate・implementer profile・規則が配布物に残らず、read-only 用途
# （cross-critic・break-consensus-cross・skill-tuneup）が使う delegation_common の汎用関数は残ることを確かめる。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAILURES=0

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# ---- 1. 撤去した path ----
for path in \
  claude/skills/gh-codex-drive claude/skills/gh-roadmap-drive \
  claude/bin/codex-delegate claude/bin/codex-delegate-preflight \
  claude/bin/verify-delegation claude/bin/delegation-evidence-check \
  codex/profiles/toolkit-implementer.config.toml tests/test-codex-delegate.sh; do
  if [[ ! -e "$REPO_ROOT/$path" ]]; then ok "撤去済み: $path"; else ng "残っている: $path"; fi
done
for skill in gh-codex-drive gh-roadmap-drive; do
  if [[ -f "$REPO_ROOT/docs/archive/skills/$skill/SKILL.md" ]]; then
    ok "archive へ移した: $skill"
  else
    ng "archive に無い: docs/archive/skills/$skill/SKILL.md"
  fi
done

# ---- 2. 委任経路への参照（履歴 docs と、撤去を検出・確認する側だけを許す）----
PATTERN='codex[-]delegate|verify[-]delegation|delegation[-]evidence|gh-codex-drive|gh-roadmap-drive|toolkit-implementer'
hits="$(git -C "$REPO_ROOT" grep --untracked -nE "$PATTERN" -- . \
  ':!docs/reports' ':!docs/eval' ':!docs/plans' ':!docs/archive' \
  ':!tests/test-no-codex-implementation.sh' ':!tests/test-bootstrap.sh' || true)"
unexpected="$(printf '%s\n' "$hits" | grep -vE \
  -e '^bootstrap\.sh:[0-9]+:  "gh-(codex|roadmap)-drive"$' \
  -e '^tests/test-break-consensus-cross\.sh:[0-9]+:.*(grep -nE|ok "break-consensus は実装の経路)' \
  -e '^tests/test-pre-bash-hook\.sh:[0-9]+:.*(!= \*codex-delegate\*|ng ".*codex-delegate)' \
  -e '^$' || true)"
if [[ -z "$unexpected" ]]; then
  ok "委任経路への参照は履歴と撤去検出の箇所だけ"
else
  ng "委任経路への参照が残っている:"$'\n'"$unexpected"
fi

# ---- 3. delegation_common は read-only 用途の汎用関数だけを持つ ----
if out="$(python3 -I - "$REPO_ROOT/claude/bin" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import delegation_common as dc
needed = ["DelegationError", "catalog_levels", "codex_home", "load_json", "schema_errors", "sha256_file", "write_json"]
missing = [n for n in needed if not hasattr(dc, n)]
leftover = [n for n in ["render_prompt", "preflight_errors", "record_baseline", "changes_since", "state_paths",
                        "protected_patterns", "PROFILE", "REFERENCES", "CONTRACT_SCHEMA", "REPORT_SCHEMA"] if hasattr(dc, n)]
if missing or leftover:
    sys.exit(f"missing={missing} leftover={leftover}")
PY
)"; then
  ok "delegation_common は汎用関数を残し委任専用の部分を持たない"
else
  ng "delegation_common: $out"
fi

# ---- 4. 規則と hook ----
if grep -q '委任しない' "$REPO_ROOT/claude/CLAUDE.md"; then
  ok "CLAUDE.md が Codex へ実装を委任しないことを明記する"
else
  ng "CLAUDE.md に委任しない旨が無い"
fi
if ! grep -q -- '--apply-patch-hook' "$REPO_ROOT/claude/hooks/lib/post_edit_lint.py"; then
  ok "implementer profile 専用の --apply-patch-hook mode は無い"
else
  ng "post_edit_lint.py に --apply-patch-hook mode が残っている"
fi
if ! grep -qi 'delegat' "$REPO_ROOT/claude/skills/gh-finish/SKILL.md" "$REPO_ROOT/claude/skills/gh-finish/references/workflow.md"; then
  ok "gh-finish に委任証跡の手順は無い"
else
  ng "gh-finish に委任証跡の手順が残っている"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
