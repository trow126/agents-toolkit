#!/usr/bin/env bash
# test-check-runtime.sh — runtime doctor(scripts/check-runtime.sh)のテスト
# (2026-07-24 H-013/H-017: XDG fail-closed / version floor / prerelease 拒否 / soft-missing)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCTOR="$REPO_ROOT/scripts/check-runtime.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0
ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# claude stub: CLAUDE_STUB_VERSION の内容を version 行として出力する
STUBBIN="$SANDBOX/stubbin"
mkdir -p "$STUBBIN"
cat > "$STUBBIN/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s (Claude Code)\n' "${CLAUDE_STUB_VERSION:?}"
STUB
chmod +x "$STUBBIN/claude"

# claude 欠落環境: doctor が必要とする外部コマンドだけを見せる
MINBIN="$SANDBOX/minbin"
mkdir -p "$MINBIN"
for b in bash grep sort head; do
  ln -s "$(command -v $b)" "$MINBIN/$b"
done

run_doctor() {
  # $1: stub version("-" で claude 欠落) 以降: doctor への引数。XDG は既定化して実行する
  local ver="$1"
  shift
  if [[ "$ver" == "-" ]]; then
    env -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME \
      PATH="$MINBIN" "$DOCTOR" "$@"
  else
    env -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME \
      PATH="$STUBBIN:$PATH" CLAUDE_STUB_VERSION="$ver" "$DOCTOR" "$@"
  fi
}

expect_rc() {
  local desc="$1" want="$2" ver="$3" rc=0
  shift 3
  run_doctor "$ver" "$@" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq "$want" ]]; then ok "$desc"; else ng "$desc (expected exit $want, got $rc)"; fi
}

# ---- 1. version floor(H-017) ----
expect_rc "下限ちょうど(2.1.218)は accept" 0 "2.1.218"
expect_rc "下限超過(2.1.230)は accept" 0 "2.1.230"
expect_rc "下限未満(2.1.217)は reject" 1 "2.1.217"
expect_rc "prerelease(2.1.218-beta.1)は reject" 1 "2.1.218-beta.1"
expect_rc "prerelease(2.1.219-rc.1)は下限超相当でも reject" 1 "2.1.219-rc.1"
expect_rc "解釈不能な version 出力は reject" 1 "not-a-version"

out="$(run_doctor "3.0.0" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -q "検証済み major" <<< "$out"; then
  ok "future major(3.0.0)は accept + NOTE"
else
  ng "future major (rc=$rc, note=$(grep -c '検証済み major' <<< "$out" || true))"
fi

# ---- 2. claude 欠落(H-017: soft-missing は bootstrap 経路専用) ----
expect_rc "claude 欠落は既定で reject" 1 "-"
expect_rc "claude 欠落 + --soft-missing は NOTE 続行" 0 "-" --soft-missing

# ---- 3. custom XDG は fail-closed(H-013) ----
rc=0
env XDG_CONFIG_HOME="$SANDBOX/custom-config" PATH="$STUBBIN:$PATH" CLAUDE_STUB_VERSION="2.1.218" \
  "$DOCTOR" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 1 ]]; then ok "custom XDG_CONFIG_HOME は reject(denyRead 前提と不一致)"; else ng "custom XDG が exit $rc"; fi

rc=0
env XDG_DATA_HOME="$SANDBOX/custom-data" PATH="$STUBBIN:$PATH" CLAUDE_STUB_VERSION="2.1.218" \
  "$DOCTOR" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 1 ]]; then ok "custom XDG_DATA_HOME は reject"; else ng "custom XDG_DATA_HOME が exit $rc"; fi

rc=0
env XDG_CONFIG_HOME="$HOME/.config" PATH="$STUBBIN:$PATH" CLAUDE_STUB_VERSION="2.1.218" \
  "$DOCTOR" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]]; then ok "既定値と同値の XDG_CONFIG_HOME は accept"; else ng "既定値 XDG が exit $rc"; fi

rc=0
out="$(env XDG_CONFIG_HOME="$SANDBOX/custom-config" PATH="$STUBBIN:$PATH" CLAUDE_STUB_VERSION="2.1.218" \
  "$DOCTOR" --accept-custom-xdg 2>&1)" || rc=$?
if [[ "$rc" -eq 0 ]] && grep -q "明示受容" <<< "$out"; then
  ok "--accept-custom-xdg は NOTE つきで受容(waiver 運用)"
else
  ng "--accept-custom-xdg (rc=$rc)"
fi

# ---- 4. 未知 option は reject ----
expect_rc "未知 option は reject" 1 "2.1.218" --bogus

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
