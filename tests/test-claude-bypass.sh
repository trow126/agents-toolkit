#!/usr/bin/env bash
# test-claude-bypass.sh — claude-bypass launcher の環境検証ゲートテスト(再レビュー ATK-004)
# 実$HOME・実claudeに触れず、fake claude + fixture /proc/version + 一時XDG_CONFIG_HOMEで検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="$REPO_ROOT/claude/bin/claude-bypass"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0
ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# fake claude: 呼ばれた引数を記録するだけ
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/claude" <<FAKE
#!/usr/bin/env bash
echo "\$@" > "$SANDBOX/claude-args"
exit 0
FAKE
chmod +x "$SANDBOX/bin/claude"

WSL_PROC="$SANDBOX/proc-version-wsl"
echo "Linux version 6.6.0-microsoft-standard-WSL2 (build)" > "$WSL_PROC"
NONWSL_PROC="$SANDBOX/proc-version-plain"
echo "Linux version 6.6.0-generic (build)" > "$NONWSL_PROC"

XDG="$SANDBOX/xdg"

# 1. marker なし → 非ゼロ終了、claude は呼ばれない
rc=0
XDG_CONFIG_HOME="$XDG" AGENTS_TOOLKIT_BYPASS_UID=1000 AGENTS_TOOLKIT_BYPASS_PROC_VERSION="$WSL_PROC" PATH="$SANDBOX/bin:$PATH" \
  "$LAUNCHER" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 && ! -f "$SANDBOX/claude-args" ]]; then
  ok "opt-in marker なしでは fail-closed（claude 未起動）"
else
  ng "marker なしで bypass が通過した (rc=$rc)"
fi

# 2. 非WSL環境では --enable-this-machine が拒否される
rc=0
XDG_CONFIG_HOME="$XDG" AGENTS_TOOLKIT_BYPASS_UID=1000 AGENTS_TOOLKIT_BYPASS_PROC_VERSION="$NONWSL_PROC" PATH="$SANDBOX/bin:$PATH" \
  "$LAUNCHER" --enable-this-machine >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 && ! -f "$XDG/agents-toolkit/bypass-approved" ]]; then
  ok "非WSL環境では opt-in を拒否する"
else
  ng "非WSL環境で opt-in が成功してしまった (rc=$rc)"
fi

# 3. WSL環境では --enable-this-machine が marker を作成する
rc=0
XDG_CONFIG_HOME="$XDG" AGENTS_TOOLKIT_BYPASS_UID=1000 AGENTS_TOOLKIT_BYPASS_PROC_VERSION="$WSL_PROC" PATH="$SANDBOX/bin:$PATH" \
  "$LAUNCHER" --enable-this-machine >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 && -f "$XDG/agents-toolkit/bypass-approved" ]]; then
  ok "WSL環境では opt-in が成功し marker が作成される"
else
  ng "WSL環境での opt-in が失敗 (rc=$rc)"
fi

# 4. marker あり + WSL → bypassPermissions 付きで claude を exec する
rc=0
XDG_CONFIG_HOME="$XDG" AGENTS_TOOLKIT_BYPASS_UID=1000 AGENTS_TOOLKIT_BYPASS_PROC_VERSION="$WSL_PROC" PATH="$SANDBOX/bin:$PATH" \
  "$LAUNCHER" --resume >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -q -- "--permission-mode bypassPermissions --resume" "$SANDBOX/claude-args"; then
  ok "検証成功時のみ --permission-mode bypassPermissions で起動し引数を引き継ぐ"
else
  ng "bypass 起動の引数が不正: $(cat "$SANDBOX/claude-args" 2>/dev/null || echo 'claude 未起動')"
fi

# 5. marker があっても非WSL環境なら fail-closed（環境制約は毎回実行時検証）
rm -f "$SANDBOX/claude-args"
rc=0
XDG_CONFIG_HOME="$XDG" AGENTS_TOOLKIT_BYPASS_UID=1000 AGENTS_TOOLKIT_BYPASS_PROC_VERSION="$NONWSL_PROC" PATH="$SANDBOX/bin:$PATH" \
  "$LAUNCHER" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 && ! -f "$SANDBOX/claude-args" ]]; then
  ok "marker があっても環境不成立なら fail-closed"
else
  ng "環境不成立でも bypass が通過した (rc=$rc)"
fi

# 6. root(uid 0)では marker + WSL でも fail-closed
rm -f "$SANDBOX/claude-args"
rc=0
XDG_CONFIG_HOME="$XDG" AGENTS_TOOLKIT_BYPASS_UID=0 AGENTS_TOOLKIT_BYPASS_PROC_VERSION="$WSL_PROC" PATH="$SANDBOX/bin:$PATH" \
  "$LAUNCHER" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 && ! -f "$SANDBOX/claude-args" ]]; then
  ok "root では bypass を拒否する"
else
  ng "root で bypass が通過した (rc=$rc)"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
