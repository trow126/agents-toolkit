#!/usr/bin/env bash
# test-claude-bypass.sh — claude-bypass の gate 検証テスト(再々レビュー ATK-004 / H-006)
#
# 検証ロジック(lib/bypass-gate.sh)は dependency injection で fixture を直接渡してテストし、
# production launcher(claude-bypass)は実 /proc/version・実 id -u に固定であること
# (環境変数 seam を持たないこと)と fail-closed 挙動を実体で検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="$REPO_ROOT/claude/bin/claude-bypass"

# shellcheck source=../claude/bin/lib/bypass-gate.sh
source "$REPO_ROOT/claude/bin/lib/bypass-gate.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0
ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

WSL2_PROC="$SANDBOX/proc-wsl2"
echo "Linux version 5.15.167.4-microsoft-standard-WSL2 (build)" > "$WSL2_PROC"
WSL1_PROC="$SANDBOX/proc-wsl1"
echo "Linux version 4.4.0-19041-Microsoft (Microsoft@Microsoft.com) #1237-Microsoft" > "$WSL1_PROC"
PLAIN_PROC="$SANDBOX/proc-plain"
echo "Linux version 6.6.0-generic (build)" > "$PLAIN_PROC"

# ---- 1. bypass_env_check(dependency injection) ----
if bypass_env_check "$WSL2_PROC" 1000 2>/dev/null; then ok "WSL2 + 非root を受理"; else ng "WSL2 + 非root が拒否された"; fi
if ! bypass_env_check "$WSL1_PROC" 1000 2>/dev/null; then ok "WSL1 署名(microsoft-standard なし)を拒否"; else ng "WSL1 署名が通過した"; fi
if ! bypass_env_check "$PLAIN_PROC" 1000 2>/dev/null; then ok "非WSL kernel を拒否"; else ng "非WSL kernel が通過した"; fi
if ! bypass_env_check "$WSL2_PROC" 0 2>/dev/null; then ok "root(uid 0)を拒否"; else ng "root が通過した"; fi

# ---- 2. bypass_marker_check(所有者・権限・schema・期限) ----
MARKER="$SANDBOX/marker"
make_marker() {
  local expires="$1" schema="${2:-schema=1}"
  rm -f "$MARKER"
  ( umask 077 && printf '%s\nenabled-by=tester\nexpires=%s\n' "$schema" "$expires" > "$MARKER" )
}
UID_NOW="$(id -u)"
make_marker "$(date -d '+30 days' +%F)"
if bypass_marker_check "$MARKER" "$UID_NOW" 2>/dev/null; then ok "有効な marker(600・schema=1・期限内)を受理"; else ng "有効 marker が拒否された"; fi
chmod 644 "$MARKER"
if ! bypass_marker_check "$MARKER" "$UID_NOW" 2>/dev/null; then ok "権限 644 の marker を拒否"; else ng "権限 644 が通過した"; fi
make_marker "2020-01-01"
if ! bypass_marker_check "$MARKER" "$UID_NOW" 2>/dev/null; then ok "期限切れ marker を拒否"; else ng "期限切れが通過した"; fi
make_marker "not-a-date"
if ! bypass_marker_check "$MARKER" "$UID_NOW" 2>/dev/null; then ok "不正日付 marker を拒否"; else ng "不正日付が通過した"; fi
make_marker "$(date -d '+30 days' +%F)" "legacy-no-schema"
if ! bypass_marker_check "$MARKER" "$UID_NOW" 2>/dev/null; then ok "schema なし(旧形式)marker を拒否"; else ng "schema なしが通過した"; fi
if ! bypass_marker_check "$SANDBOX/no-such-marker" "$UID_NOW" 2>/dev/null; then ok "marker 不在を拒否"; else ng "marker 不在が通過した"; fi

# ---- 3. production launcher: 環境変数 seam を持たない(静的 + 実挙動) ----
if ! grep -q 'AGENTS_TOOLKIT_BYPASS' "$LAUNCHER"; then
  ok "launcher に環境変数 seam(AGENTS_TOOLKIT_BYPASS_*)が存在しない"
else
  ng "launcher に環境変数 seam が残っている"
fi
# fake claude / srt を PATH に置いても、この非WSL環境では必ず fail-closed になる
mkdir -p "$SANDBOX/bin"
for fake in claude srt; do
  printf '#!/usr/bin/env bash\necho "$0 $*" >> "%s/spawned"\nexit 0\n' "$SANDBOX" > "$SANDBOX/bin/$fake"
  chmod +x "$SANDBOX/bin/$fake"
done
rc=0
AGENTS_TOOLKIT_BYPASS_PROC_VERSION="$WSL2_PROC" AGENTS_TOOLKIT_BYPASS_UID=1000 \
  XDG_CONFIG_HOME="$SANDBOX/xdg" PATH="$SANDBOX/bin:$PATH" \
  "$LAUNCHER" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 && ! -f "$SANDBOX/spawned" ]]; then
  ok "spoof 環境変数を与えても production 判定は変わらず fail-closed(claude/srt 未起動)"
else
  ng "spoof 環境変数で launcher が通過した (rc=$rc)"
fi
rc=0
XDG_CONFIG_HOME="$SANDBOX/xdg" PATH="$SANDBOX/bin:$PATH" "$LAUNCHER" --enable-this-machine >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 && ! -f "$SANDBOX/xdg/agents-toolkit/bypass-approved" ]]; then
  ok "非WSL実環境では --enable-this-machine も fail-closed"
else
  ng "非WSL実環境で opt-in が成功してしまった (rc=$rc)"
fi

# ---- 4. 起動コマンドの構成(静的): srt 隔離 + 固定 profile + bypassPermissions ----
if grep -qE 'exec \$SRT_BIN --settings "\$SRT_SETTINGS" claude --permission-mode bypassPermissions --settings "\$BYPASS_PROFILE"' "$LAUNCHER"; then
  ok "launcher は srt 隔離内で固定 profile 付き bypass を exec する構成"
else
  ng "launcher の exec 構成が想定と異なる"
fi
if jq -e '.sandbox.failIfUnavailable == true and .sandbox.allowUnsandboxedCommands == false and (.permissions.ask | length > 0)' \
  "$REPO_ROOT/claude/bypass-profile.json" >/dev/null; then
  ok "bypass-profile が sandbox pin + ask gate を含む"
else
  ng "bypass-profile の内容が不正"
fi
if jq -e '.filesystem.denyRead | index("~/.ssh")' "$REPO_ROOT/claude/srt-bypass-settings.template.json" >/dev/null \
  && jq -e '.network.allowedDomains | length > 0' "$REPO_ROOT/claude/srt-bypass-settings.template.json" >/dev/null; then
  ok "srt template が credential denyRead + network allowlist を持つ"
else
  ng "srt template の内容が不正"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
