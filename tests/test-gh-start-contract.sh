#!/usr/bin/env bash
# test-gh-start-contract.sh — gh-start workflow の実行時契約テスト(2026-07-23 レビュー ATK-001/003)
# 1) gh-issue-fetch.sh が fake gh + SCRIPT_DIR 相対パーサーで end-to-end に動く(repo 直接 + bootstrap 済み HOME)
# 2) gh-start SKILL.md に無条件 Agent 委譲テンプレートがなく、条件付き委譲規約があることを静的検査
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0
ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# =========================================================================
# fixture: fake gh(issue view で構造化Issueを返す)
# =========================================================================
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/gh" <<'FAKEGH'
#!/usr/bin/env bash
# fake gh for tests: `gh issue view <n> --json ...` だけに応答する
if [[ "$1" == "issue" && "$2" == "view" ]]; then
  cat <<'JSON'
{"number": 42, "title": "Fixture issue", "state": "OPEN", "url": "https://example.invalid/issues/42", "body": "## Phase 1\n- [ ] Task one\n- [x] Task two\n"}
JSON
  exit 0
fi
echo "fake gh: unsupported args: $*" >&2
exit 64
FAKEGH
chmod +x "$SANDBOX/bin/gh"

# =========================================================================
# 1. repo 直接実行: exit 0 + 構造化JSON(tasks を含む)
# =========================================================================
out=""
rc=0
out="$(PATH="$SANDBOX/bin:$PATH" "$REPO_ROOT/claude/bin/gh-issue-fetch.sh" 42 2>/dev/null)" || rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "gh-issue-fetch.sh 42 が exit 0"
else
  ng "gh-issue-fetch.sh 42 が exit $rc"
fi
if echo "$out" | jq -e '.tasks | length >= 1' > /dev/null 2>&1; then
  ok "構造化JSONに tasks が含まれる"
else
  ng "構造化JSONに tasks が含まれない: $out"
fi

# =========================================================================
# 2. bootstrap 済み clean HOME 経由: ~/.claude/bin symlink から同様に動く
# =========================================================================
TESTHOME="$SANDBOX/home"
MANAGED_TARGET="$SANDBOX/managed/20-agents-toolkit-security.json"
mkdir -p "$TESTHOME" "$(dirname "$MANAGED_TARGET")"
HOME="$TESTHOME" git config --global --add safe.directory "$REPO_ROOT" 2>/dev/null || true
AGENTS_TOOLKIT_TESTING=1 "$REPO_ROOT/scripts/install-managed-policy.sh" --apply --target "$MANAGED_TARGET" > "$SANDBOX/managed-policy.log" 2>&1
if env -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME \
  HOME="$TESTHOME" AGENTS_TOOLKIT_TESTING=1 AGENTS_TOOLKIT_MANAGED_POLICY_TARGET="$MANAGED_TARGET" \
  "$REPO_ROOT/bootstrap.sh" --apply > "$SANDBOX/bootstrap.log" 2>&1; then
  ok "clean HOME への bootstrap --apply が成功"
else
  ng "clean HOME への bootstrap --apply が失敗: $(tail -3 "$SANDBOX/bootstrap.log")"
fi
out=""
rc=0
out="$(HOME="$TESTHOME" PATH="$SANDBOX/bin:$PATH" "$TESTHOME/.claude/bin/gh-issue-fetch.sh" 42 2>/dev/null)" || rc=$?
if [[ "$rc" -eq 0 ]] && echo "$out" | jq -e '.tasks' > /dev/null 2>&1; then
  ok "bootstrap 済み HOME の symlink 経由でも exit 0 + JSON"
else
  ng "bootstrap 済み HOME 経由で失敗 (exit=$rc)"
fi

# =========================================================================
# 3. パーサー欠落の配布物は明示エラーで非ゼロ終了する
# =========================================================================
BROKEN="$SANDBOX/broken-bin"
mkdir -p "$BROKEN"
cp "$REPO_ROOT/claude/bin/gh-issue-fetch.sh" "$BROKEN/"
rc=0
out="$(PATH="$SANDBOX/bin:$PATH" "$BROKEN/gh-issue-fetch.sh" 42 2>&1)" || rc=$?
if [[ "$rc" -ne 0 && "$out" == *"Parser script not found"* ]]; then
  ok "パーサー欠落時は明示エラーで非ゼロ終了"
else
  ng "パーサー欠落時の挙動が不正 (exit=$rc)"
fi

# =========================================================================
# 4. 静的契約: 旧パーサー/checkpointなし・default local only・副作用mode分離
# =========================================================================
GH_START_SKILL="$REPO_ROOT/shared/skills/claude-code/gh-start/SKILL.md"
if ! grep -q 'skills/issue-parser' "$REPO_ROOT/claude/bin/gh-issue-fetch.sh" "$GH_START_SKILL"; then
  ok "旧 issue-parser パス参照が残っていない"
else
  ng "旧 issue-parser パス参照が残っている"
fi
if [[ -f "$REPO_ROOT/claude/bin/parse_issue.py" ]]; then
  ok "parse_issue.py が claude/bin に存在する(配布対象)"
else
  ng "claude/bin/parse_issue.py が存在しない"
fi
if ! grep -q 'subagent_type: "general-purpose"' "$GH_START_SKILL"; then
  ok "gh-start に無条件 general-purpose 委譲テンプレートがない"
else
  ng "gh-start に無条件委譲テンプレートが残っている"
fi
if grep -q 'single owner' "$GH_START_SKILL" \
   && grep -q 'context isolation' "$GH_START_SKILL" \
   && grep -q 'task length alone is not a reason' "$GH_START_SKILL"; then
  ok "gh-start が単一 owner 既定 + 条件付き委譲規約を持つ"
else
  ng "gh-start の単一 owner / 条件付き委譲規約が見つからない"
fi
if grep -q -- '--commit' "$GH_START_SKILL" \
   && grep -q -- '--sync' "$GH_START_SKILL" \
   && grep -q 'mutually exclusive' "$GH_START_SKILL" \
   && grep -q 'Default mode never commits, pushes, creates a PR, comments on GitHub' "$GH_START_SKILL"; then
  ok "gh-start のcommit/sync権限がdefaultから分離されている"
else
  ng "gh-start の副作用mode分離契約が見つからない"
fi
if grep -q 'Never read, create, migrate, or delete `.claude/checkpoints` or `.codex/checkpoints`' "$GH_START_SKILL"; then
  ok "gh-start はlegacy checkpointを読み書き・削除しない"
else
  ng "gh-start のcheckpoint廃止契約が見つからない"
fi
if awk -F'\t' '$1=="gh-start" && $2=="default" && $3=="allow" && $5=="deny" && $6=="deny" && $7=="deny" {found=1} END{exit !found}' \
  "$REPO_ROOT/docs/contracts/skill-authority.tsv"; then
  ok "authority contractがgh-start defaultをlocal write onlyに固定する"
else
  ng "authority contractのgh-start default行が不正"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
