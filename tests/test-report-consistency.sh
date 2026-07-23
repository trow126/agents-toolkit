#!/usr/bin/env bash
# Ensure the report's machine-readable after block exactly matches measurement.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT="$REPO_ROOT/docs/plans/2026-07-23-agents-toolkit-modernization.md"
MEASURE="$REPO_ROOT/scripts/measure-metrics.sh"
FAILURES=0
ok(){ echo "ok: $1"; }
ng(){ echo "FAIL: $1" >&2; FAILURES=$((FAILURES+1)); }

extract_block(){
  sed -n '/<!-- BEGIN metrics:after -->/,/<!-- END metrics:after -->/p' "$1" \
    | grep -E '^[a-z_]+:' || true
}
actual_lines(){
  "$MEASURE" --repo "$REPO_ROOT" | grep -E '^[a-z_]+:'
}
compare_report(){
  local report="$1" expected actual
  expected="$(actual_lines)"
  actual="$(extract_block "$report")"
  [[ -n "$actual" ]] || { echo "metrics:after block missing or empty"; return 1; }
  if [[ "$actual" != "$expected" ]]; then
    diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
    return 1
  fi
}

if out="$(compare_report "$REPORT")"; then
  ok "report metrics:after block exactly matches all measured keys"
else
  ng "report metrics:after is incomplete or stale: $out"
fi

SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT
sed 's/^combined_always_on_total: [0-9]*/combined_always_on_total: 99999/' "$REPORT" > "$SANDBOX/stale-report.md"
if ! compare_report "$SANDBOX/stale-report.md" >/dev/null; then ok "stale value fixture fails"; else ng "stale value fixture passed"; fi
sed '/^managed_policy_present:/d' "$REPORT" > "$SANDBOX/missing-key-report.md"
if ! compare_report "$SANDBOX/missing-key-report.md" >/dev/null; then ok "missing metric key fixture fails"; else ng "missing key fixture passed"; fi

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then echo "PASS: all assertions succeeded"; exit 0; fi
echo "FAIL: $FAILURES assertion(s) failed" >&2; exit 1
