#!/usr/bin/env bash
# test-sandwich-ab-harness.sh — sandwich-ab harness が、#14 で削除した委任基盤に依存する経路（arm B・C・D と selftest）を
# Codex を呼ぶ前に理由付きで止め、委任基盤を使わない経路（check、arm A・AP）を止めないことを検査する（Issue #16）。
# モデルは呼ばない。claude・codex・uv は PATH 上の stub に置き換える。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HARNESS="$REPO_ROOT/docs/eval/sandwich-ab/harness/sandwich_ab.py"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0
ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# ---- fixture ----
STUBS="$SANDBOX/stubs"
mkdir -p "$STUBS"
for c in claude codex uv; do
  printf '#!/usr/bin/env bash\necho "%s 0.0.0-stub"\n' "$c" > "$STUBS/$c"
  chmod +x "$STUBS/$c"
done
export PATH="$STUBS:$PATH"

# 委任基盤が揃った toolkit_bin（d201b05 の worktree の代わりの stub）
FULL_BIN="$SANDBOX/full-bin"
mkdir -p "$FULL_BIN"
for n in codex-delegate verify-delegation delegation-evidence-check; do
  printf '#!/usr/bin/env python3\n' > "$FULL_BIN/$n"
  chmod +x "$FULL_BIN/$n"
done
cat > "$FULL_BIN/delegation_common.py" <<'PY'
CONTRACT_SCHEMA = "contract.schema.json"


def render_prompt(contract):
    return ""
PY
FULL_HOME="$SANDBOX/codex-home-full"
mkdir -p "$FULL_HOME"
: > "$FULL_HOME/toolkit-implementer.config.toml"
EMPTY_HOME="$SANDBOX/codex-home-empty"
mkdir -p "$EMPTY_HOME"

# 題材は check 用に 0 件、run 用に ready 1 件
mkdir -p "$SANDBOX/tasks-none" "$SANDBOX/tasks-one" "$SANDBOX/tests"
cat > "$SANDBOX/tasks-one/S01.json" <<'JSON'
{"id": "S01", "status": "ready", "repo": "no-such-repo", "base": "0123456789abcdef0123", "kind": "feature", "leak_trap": false}
JSON

write_config() { # <file> <toolkit_bin> <tasks_dir> <eval_root>
  jq -n --arg bin "$2" --arg tasks "$3" --arg root "$4" --arg tests "$SANDBOX/tests" \
    --arg tpl "$REPO_ROOT/docs/eval/sandwich-ab/templates" --arg repo "$SANDBOX/no-such-repo" '{
      eval_root: $root, tasks_dir: $tasks, tests_dir: $tests, toolkit_bin: $bin, templates_dir: $tpl,
      repo_paths: {"no-such-repo": $repo},
      arms: {A: {label: "opus-solo"}, AP: {label: "opus-visible"}, C: {label: "sol-solo"}},
      timeouts_s: {claude: 60, codex: 60, check: 60, uv_sync: 60}, parallel: 1
    }' > "$1"
}

write_schedule() { # <eval_root> <arm>
  mkdir -p "$1"
  jq -n --arg arm "$2" '{seed: 1, created_at: "2026-10-12T00:00:00+00:00", jobs: [{task: "S01", arm: $arm, rep: 1}]}' \
    > "$1/schedule.json"
}

OUT="$SANDBOX/out"
RC=0
harness() { # <codex_home> <config> <args...>
  local home="$1" cfg="$2"
  shift 2
  RC=0
  CODEX_HOME="$home" python3 "$HARNESS" --config "$cfg" "$@" > "$OUT" 2>&1 || RC=$?
}

expect_stop_reason() { # <desc>
  local desc="$1"
  if [[ "$RC" -eq 1 ]]; then ok "$desc: exit 1"; else ng "$desc: expected exit 1, got $RC: $(tail -5 "$OUT")"; fi
  if grep -q '#14' "$OUT" && grep -q 'd201b05' "$OUT"; then
    ok "$desc: 理由に #14 と d201b05 の再現方法がある"
  else
    ng "$desc: 理由に #14 と d201b05 がない: $(tail -5 "$OUT")"
  fi
  if ! grep -q 'Traceback' "$OUT"; then ok "$desc: traceback で落ちない"; else ng "$desc: traceback で落ちた"; fi
}

# ---- 1. 委任基盤が無い（master の claude/bin、implementer profile なし） ----
MASTER_BIN="$REPO_ROOT/claude/bin"

write_config "$SANDBOX/cfg-check.json" "$MASTER_BIN" "$SANDBOX/tasks-none" "$SANDBOX/root-check"
harness "$EMPTY_HOME" "$SANDBOX/cfg-check.json" selftest
expect_stop_reason "selftest（委任基盤なし）"

harness "$EMPTY_HOME" "$SANDBOX/cfg-check.json" check
if [[ "$RC" -eq 0 ]]; then ok "check（委任基盤なし）: 他の前提が揃えば exit 0"; else ng "check（委任基盤なし）: exit $RC: $(cat "$OUT")"; fi
if grep -q '^WARN' "$OUT" && grep -q 'd201b05' "$OUT"; then
  ok "check（委任基盤なし）: 欠落と d201b05 の再現方法を warning で示す"
else
  ng "check（委任基盤なし）: warning がない: $(cat "$OUT")"
fi
if ! grep -q 'bootstrap.sh --apply' "$OUT"; then
  ok "check: 直らない bootstrap.sh --apply を案内しない"
else
  ng "check: bootstrap.sh --apply を案内する"
fi
if grep -q 'toolkit-implementer.config.toml' "$OUT" && grep -q 'codex-delegate' "$OUT" && grep -q 'render_prompt' "$OUT"; then
  ok "check: 欠けている要素（launcher、render_prompt、implementer profile）を挙げる"
else
  ng "check: 欠けている要素の列挙が足りない: $(cat "$OUT")"
fi

ROOT_C="$SANDBOX/root-run-c"
write_config "$SANDBOX/cfg-run-c.json" "$MASTER_BIN" "$SANDBOX/tasks-one" "$ROOT_C"
write_schedule "$ROOT_C" C
harness "$EMPTY_HOME" "$SANDBOX/cfg-run-c.json" run
expect_stop_reason "run arm C（委任基盤なし）"
if [[ ! -e "$ROOT_C/results.jsonl" ]]; then
  ok "run arm C（委任基盤なし）: results.jsonl に追記しない"
else
  ng "run arm C（委任基盤なし）: results.jsonl ができた: $(cat "$ROOT_C/results.jsonl")"
fi
if [[ ! -e "$ROOT_C/src" && ! -e "$ROOT_C/runs" ]]; then
  ok "run arm C（委任基盤なし）: mirror・worktree を作る前に止まる"
else
  ng "run arm C（委任基盤なし）: mirror か worktree を作った"
fi

for arm in A AP; do
  ROOT_A="$SANDBOX/root-run-$arm"
  write_config "$SANDBOX/cfg-run-$arm.json" "$MASTER_BIN" "$SANDBOX/tasks-one" "$ROOT_A"
  write_schedule "$ROOT_A" "$arm"
  harness "$EMPTY_HOME" "$SANDBOX/cfg-run-$arm.json" run --dry-run
  if [[ "$RC" -eq 0 ]] && grep -q "DRY S01-$arm-r1" "$OUT"; then
    ok "run --dry-run arm $arm（委任基盤なし）: 委任基盤の判定で止まらない"
  else
    ng "run --dry-run arm $arm（委任基盤なし）: exit $RC: $(cat "$OUT")"
  fi
done

# ---- 2. 委任基盤が揃っている（stub） ----
harness "$FULL_HOME" "$SANDBOX/cfg-check.json" check
if [[ "$RC" -eq 0 ]]; then ok "check（委任基盤あり、master bin）: exit 0"; else ng "check（委任基盤あり、master bin）: exit $RC"; fi

write_config "$SANDBOX/cfg-full-check.json" "$FULL_BIN" "$SANDBOX/tasks-none" "$SANDBOX/root-full-check"
harness "$FULL_HOME" "$SANDBOX/cfg-full-check.json" check
if [[ "$RC" -eq 0 ]] && ! grep -q '^WARN' "$OUT"; then
  ok "check（委任基盤あり）: exit 0 で warning を出さない"
else
  ng "check（委任基盤あり）: exit $RC: $(cat "$OUT")"
fi

ROOT_FULL="$SANDBOX/root-full-run"
write_config "$SANDBOX/cfg-full-run.json" "$FULL_BIN" "$SANDBOX/tasks-one" "$ROOT_FULL"
write_schedule "$ROOT_FULL" C
harness "$FULL_HOME" "$SANDBOX/cfg-full-run.json" run --dry-run
if [[ "$RC" -eq 0 ]] && grep -q 'DRY S01-C-r1' "$OUT"; then
  ok "run --dry-run arm C（委任基盤あり）: 判定が真で止まらない"
else
  ng "run --dry-run arm C（委任基盤あり）: exit $RC: $(cat "$OUT")"
fi

# profile だけ欠けていても止める
harness "$EMPTY_HOME" "$SANDBOX/cfg-full-run.json" run
expect_stop_reason "run arm C（implementer profile だけ欠落）"
if grep -q 'toolkit-implementer.config.toml' "$OUT"; then
  ok "run arm C（implementer profile だけ欠落）: 欠けた profile を挙げる"
else
  ng "run arm C（implementer profile だけ欠落）: profile を挙げない: $(cat "$OUT")"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
