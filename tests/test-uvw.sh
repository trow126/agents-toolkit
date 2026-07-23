#!/usr/bin/env bash
# test-uvw.sh — sandbox 互換 uv wrapper(claude/bin/uvw)のテスト(2026-07-24 H-019)
# 検証: 可変 state の session temp 固定 / 既存環境変数の尊重 / args passthrough / uv 欠落 fail
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UVW="$REPO_ROOT/claude/bin/uvw"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0
ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

# uv stub: 受け取った args と関連環境変数を capture file へ書き出す
STUBBIN="$SANDBOX/stubbin"
mkdir -p "$STUBBIN"
cat > "$STUBBIN/uv" <<'STUB'
#!/usr/bin/env bash
{
  printf 'ARGS:%s\n' "$*"
  printf 'UV_CACHE_DIR:%s\n' "${UV_CACHE_DIR:-}"
  printf 'UV_PYTHON_INSTALL_DIR:%s\n' "${UV_PYTHON_INSTALL_DIR:-}"
  printf 'UV_TOOL_DIR:%s\n' "${UV_TOOL_DIR:-}"
  printf 'XDG_CONFIG_HOME:%s\n' "${XDG_CONFIG_HOME:-}"
} > "$UVW_TEST_CAPTURE"
STUB
chmod +x "$STUBBIN/uv"

capture_get() { grep "^$2:" "$1" | head -1 | cut -d: -f2-; }

# ---- 1. TMPDIR(= sandbox の session temp 相当)配下へ state が固定される ----
TMP1="$SANDBOX/session-tmp"
CAP1="$SANDBOX/cap1"
mkdir -p "$TMP1"
env -u UV_CACHE_DIR -u UV_PYTHON_INSTALL_DIR -u UV_TOOL_DIR -u XDG_CONFIG_HOME \
  PATH="$STUBBIN:$PATH" TMPDIR="$TMP1" UVW_TEST_CAPTURE="$CAP1" \
  "$UVW" run --frozen pytest -q

if [[ "$(capture_get "$CAP1" ARGS)" == "run --frozen pytest -q" ]]; then
  ok "args が verbatim で uv へ渡る"
else
  ng "args passthrough (got: $(capture_get "$CAP1" ARGS))"
fi
if [[ "$(capture_get "$CAP1" UV_CACHE_DIR)" == "$TMP1/uvw/cache" ]]; then
  ok "UV_CACHE_DIR が \$TMPDIR/uvw/cache へ固定される"
else
  ng "UV_CACHE_DIR (got: $(capture_get "$CAP1" UV_CACHE_DIR))"
fi
if [[ "$(capture_get "$CAP1" UV_PYTHON_INSTALL_DIR)" == "$TMP1/uvw/python" ]]; then
  ok "UV_PYTHON_INSTALL_DIR が \$TMPDIR/uvw/python へ固定される"
else
  ng "UV_PYTHON_INSTALL_DIR (got: $(capture_get "$CAP1" UV_PYTHON_INSTALL_DIR))"
fi
if [[ "$(capture_get "$CAP1" UV_TOOL_DIR)" == "$TMP1/uvw/tools" ]]; then
  ok "UV_TOOL_DIR が \$TMPDIR/uvw/tools へ固定される"
else
  ng "UV_TOOL_DIR (got: $(capture_get "$CAP1" UV_TOOL_DIR))"
fi
if [[ "$(capture_get "$CAP1" XDG_CONFIG_HOME)" == "$TMP1/uvw/xdg-config" ]]; then
  ok "XDG_CONFIG_HOME 未設定時は空 config dir へ向く(denyRead の EACCES を回避)"
else
  ng "XDG_CONFIG_HOME (got: $(capture_get "$CAP1" XDG_CONFIG_HOME))"
fi
if [[ -d "$TMP1/uvw/cache" && -d "$TMP1/uvw/python" && -d "$TMP1/uvw/tools" && -d "$TMP1/uvw/xdg-config" ]]; then
  ok "state directory が実際に作成される"
else
  ng "state directory が作成されていない"
fi

# ---- 2. 明示設定済みの環境変数は上書きしない ----
CAP2="$SANDBOX/cap2"
env PATH="$STUBBIN:$PATH" TMPDIR="$TMP1" UVW_TEST_CAPTURE="$CAP2" \
  UV_CACHE_DIR="/explicit/cache" XDG_CONFIG_HOME="/explicit/xdg" \
  "$UVW" sync
if [[ "$(capture_get "$CAP2" UV_CACHE_DIR)" == "/explicit/cache" ]]; then
  ok "明示 UV_CACHE_DIR を尊重する"
else
  ng "明示 UV_CACHE_DIR が上書きされた (got: $(capture_get "$CAP2" UV_CACHE_DIR))"
fi
if [[ "$(capture_get "$CAP2" XDG_CONFIG_HOME)" == "/explicit/xdg" ]]; then
  ok "明示 XDG_CONFIG_HOME を尊重する"
else
  ng "明示 XDG_CONFIG_HOME が上書きされた (got: $(capture_get "$CAP2" XDG_CONFIG_HOME))"
fi

# ---- 3. uv 欠落は明示エラーで非ゼロ終了(fail-closed) ----
MINBIN="$SANDBOX/minbin"
mkdir -p "$MINBIN"
for b in bash mkdir id; do
  ln -s "$(command -v $b)" "$MINBIN/$b"
done
rc=0
env PATH="$MINBIN" TMPDIR="$TMP1" "$UVW" run pytest >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 1 ]]; then
  ok "uv 欠落は exit 1(fail-closed)"
else
  ng "uv 欠落が exit $rc"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
