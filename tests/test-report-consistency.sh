#!/usr/bin/env bash
# test-report-consistency.sh — 近代化レポートの after 計測値が実測と一致することを検査する(ATK-007)
# レポート内の <!-- BEGIN metrics:after --> ... <!-- END metrics:after --> ブロックには
# measure-metrics.sh --repo . の出力行を verbatim で貼る。stale になると本テストが失敗する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT="$REPO_ROOT/docs/plans/2026-07-23-agents-toolkit-modernization.md"
MEASURE="$REPO_ROOT/scripts/measure-metrics.sh"

FAILURES=0
ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# 比較関数: ブロック内の各 "key: value" 行が実測出力に verbatim で存在するか
check_block_against() {
  local report_file="$1" actual="$2" missing=0 line
  local block
  block="$(sed -n '/<!-- BEGIN metrics:after -->/,/<!-- END metrics:after -->/p' "$report_file" | grep -E '^[a-z_]+:' || true)"
  if [[ -z "$block" ]]; then
    echo "metrics:after block missing or empty"
    return 1
  fi
  while IFS= read -r line; do
    if ! grep -qxF "$line" <<< "$actual"; then
      echo "stale metric line: $line"
      missing=1
    fi
  done <<< "$block"
  return "$missing"
}

ACTUAL="$("$MEASURE" --repo "$REPO_ROOT")"

# 1. 実レポートは実測と一致する
if out="$(check_block_against "$REPORT" "$ACTUAL")"; then
  ok "レポートの metrics:after ブロックが実測と一致する"
else
  ng "レポートの metrics:after が stale: $out"
fi

# 2. self-check: 値を改変した fixture では検査が失敗する(comparator が機能している証明)
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
sed 's/^combined_always_on_total: [0-9]*/combined_always_on_total: 99999/' "$REPORT" > "$SANDBOX/stale-report.md"
if ! check_block_against "$SANDBOX/stale-report.md" "$ACTUAL" >/dev/null; then
  ok "stale 数値の fixture では検査が失敗する"
else
  ng "stale fixture が検査を通過してしまった"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
