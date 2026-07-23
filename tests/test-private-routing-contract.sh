#!/usr/bin/env bash
# test-private-routing-contract.sh — private routing の消費契約テスト(再レビュー ATK-011)
# 1) CLAUDE.md の契約節に必須項目(status/配置/消費者/優先順位/不在時挙動)が揃っていることを静的検査
# 2) 必須項目が欠落した fixture では検査が非ゼロ終了することを確認
# 3) resolver(private-routing-locate)が dummy mapping fixture で migration後 path を選択し、
#    不在時は非エラー分岐(exit 1)になることを確認。private 内容は読まない・出力しない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOLVER="$REPO_ROOT/claude/bin/private-routing-locate"
CLAUDE_MD="$REPO_ROOT/claude/CLAUDE.md"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0
ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# 契約検査関数: 対象ファイルに必須5項目が存在するか(欠落項目を列挙し非ゼロ)
check_contract() {
  local file="$1" missing=0
  grep -q "# private routing" "$file" || { echo "missing: contract section"; missing=1; }
  grep -q "status: opt-in active config" "$file" || { echo "missing: status"; missing=1; }
  grep -q "private-routing.md" "$file" || { echo "missing: 配置 path"; missing=1; }
  grep -q "private-routing-locate" "$file" || { echo "missing: 消費者/resolver" ; missing=1; }
  grep -q "優先順位" "$file" || { echo "missing: 優先順位"; missing=1; }
  grep -q "不在時挙動" "$file" || { echo "missing: 不在時挙動"; missing=1; }
  return "$missing"
}

# 1. 実 CLAUDE.md は契約検査を通過する
if check_contract "$CLAUDE_MD" > "$SANDBOX/contract-out" 2>&1; then
  ok "CLAUDE.md の private routing 契約に必須項目が揃っている"
else
  ng "CLAUDE.md の契約項目が不足: $(cat "$SANDBOX/contract-out")"
fi

# 2. 優先順位を欠落させた fixture では検査が失敗する
FIXTURE="$SANDBOX/claude-md-missing-priority.md"
grep -v "優先順位" "$CLAUDE_MD" > "$FIXTURE"
if ! check_contract "$FIXTURE" >/dev/null 2>&1; then
  ok "priority 欠落 fixture で契約検査が非ゼロ終了する"
else
  ng "priority 欠落 fixture が検査を通過してしまった"
fi

# 3. resolver: dummy mapping が存在すれば migration 後 path を返す(exit 0)
XDG="$SANDBOX/xdg"
mkdir -p "$XDG/agents-toolkit"
printf '# dummy private routing fixture(実データではない)\n' > "$XDG/agents-toolkit/private-routing.md"
out=""
rc=0
out="$(XDG_CONFIG_HOME="$XDG" "$RESOLVER")" || rc=$?
if [[ "$rc" -eq 0 && "$out" == "$XDG/agents-toolkit/private-routing.md" ]]; then
  ok "resolver が migration 後 path を選択する"
else
  ng "resolver の解決結果が不正 (rc=$rc, out=$out)"
fi

# 4. resolver: 不在時は exit 1(非エラーの既定 routing 分岐)で、path 以外を出力しない
rc=0
out="$(XDG_CONFIG_HOME="$SANDBOX/empty-xdg" "$RESOLVER" 2>&1)" || rc=$?
if [[ "$rc" -eq 1 && -z "$out" ]]; then
  ok "resolver は不在時 exit 1・無出力(既定 routing へ)"
else
  ng "resolver の不在時挙動が不正 (rc=$rc, out=$out)"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
