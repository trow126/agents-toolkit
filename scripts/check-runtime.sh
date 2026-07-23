#!/usr/bin/env bash
# check-runtime.sh — Claude Code runtime / 環境前提の doctor(2026-07-23 H-017, 2026-07-24 改訂)
#
# 検査内容:
#   1. XDG base directory が既定値であること(H-013)
#      sandbox.filesystem.denyRead は literal な ~/.config / ~/.local/state / ~/.local/share /
#      ~/.cache を遮断する。custom XDG(例: XDG_CONFIG_HOME=/opt/cfg)は denyRead の外側へ
#      解決されるため private routing / state が sandbox から読めてしまう。既定値以外は
#      fail-closed でエラーにする(--accept-custom-xdg で明示受容。受容する場合は
#      docs/waivers/settings-waivers.tsv へ記録し、denyRead に絶対 path を追加すること)
#   2. Claude Code version が検証済み下限以上の stable であること(H-017)
#      本 toolkit の settings は sandbox.credentials(v2.1.187+)、Read()/Edit() path rule の
#      現行挙動(v2.1.208+)、permissions.disableBypassPermissionsMode 等に依存する。
#      検証済み下限: 2.1.218。prerelease(例: 2.1.218-beta.1)は検証対象外として拒否する。
#      注: user settings に version floor を書く documented key は存在しない(minimumVersion は
#      settings 参照に無い。managed 配備の requiredMinimumVersion は fail-open 設計)。
#      したがって本 script + bootstrap 統合が toolkit の version gate である。
#
# 呼び出し:
#   standalone:                scripts/check-runtime.sh           (claude 欠落もエラー)
#   bootstrap --check/--apply: scripts/check-runtime.sh --soft-missing
#                              (claude 欠落は NOTE で続行。codex 専用マシンを壊さない)
set -euo pipefail

MINIMUM="2.1.218"
TESTED_MAJOR="2"
SOFT_MISSING="false"
ACCEPT_CUSTOM_XDG="false"

for arg in "$@"; do
  case "$arg" in
    --soft-missing) SOFT_MISSING="true" ;;
    --accept-custom-xdg) ACCEPT_CUSTOM_XDG="true" ;;
    *) echo "ERROR: unknown option: $arg (usage: check-runtime.sh [--soft-missing] [--accept-custom-xdg])" >&2; exit 1 ;;
  esac
done

fail=0

# --- 1. XDG 既定値検査(H-013) ---
check_xdg() {
  local var="$1" default="$2" val
  val="${!var:-}"
  if [[ -n "$val" && "$val" != "$default" ]]; then
    if [[ "$ACCEPT_CUSTOM_XDG" == "true" ]]; then
      echo "NOTE: $var=$val(既定 $default 以外)を明示受容しました。sandbox.filesystem.denyRead に絶対 path を追加し、docs/waivers/settings-waivers.tsv へ記録してください"
    else
      echo "ERROR: $var=$val は既定($default)と異なります。sandbox denyRead は既定 XDG path しか遮断しないため、custom XDG 下の private routing / state / cache が sandbox から読めます。対処: (a) custom XDG をやめる、または (b) denyRead へ絶対 path を追加し waiver を記録した上で --accept-custom-xdg(bootstrap 経由は --accept-custom-xdg か AGENTS_TOOLKIT_ACCEPT_CUSTOM_XDG=1)を付けて再実行" >&2
      fail=1
    fi
  fi
}
check_xdg XDG_CONFIG_HOME "$HOME/.config"
check_xdg XDG_STATE_HOME  "$HOME/.local/state"
check_xdg XDG_DATA_HOME   "$HOME/.local/share"
check_xdg XDG_CACHE_HOME  "$HOME/.cache"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "OK: XDG base directories are defaults (denyRead 前提と一致)"

# --- 2. Claude Code version 検査(H-017) ---
if ! command -v claude >/dev/null 2>&1; then
  if [[ "$SOFT_MISSING" == "true" ]]; then
    echo "NOTE: claude CLI が見つかりません。version 検査を skip します(Claude Code 導入後に scripts/check-runtime.sh を単体実行してください)"
    exit 0
  fi
  echo "ERROR: claude CLI が見つかりません。導入後に再実行してください" >&2
  exit 1
fi

RAW="$(claude --version 2>/dev/null | head -1)"
# no-match でも明示エラー分岐へ進めるよう pipeline 失敗を吸収する(set -e で握り潰さない)
VER_FULL="$( (grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.+-]+)?' <<< "$RAW" || true) | head -1)"
if [[ -z "$VER_FULL" ]]; then
  echo "ERROR: claude --version の出力から version を解釈できません: '$RAW'" >&2
  exit 1
fi

if [[ "$VER_FULL" == *-* ]]; then
  echo "ERROR: Claude Code $VER_FULL は prerelease です。本 toolkit の検証対象は stable のみのため、stable 版($MINIMUM 以上)へ切り替えてください" >&2
  exit 1
fi
VER="$VER_FULL"

lower="$(printf '%s\n%s\n' "$MINIMUM" "$VER" | sort -V | head -1)"
if [[ "$lower" != "$MINIMUM" ]]; then
  echo "ERROR: Claude Code $VER は検証済み下限 $MINIMUM 未満です。設定(sandbox.credentials / path rule / bypass lockout)が部分適用になる恐れがあるため、更新してから利用してください" >&2
  exit 1
fi

major="${VER%%.*}"
if [[ "$major" != "$TESTED_MAJOR" ]]; then
  echo "NOTE: Claude Code $VER は検証済み major($TESTED_MAJOR.x)と異なります。設定 semantics の互換を release note で確認してください"
fi

echo "OK: Claude Code $VER (>= $MINIMUM, stable)"
echo "NOTE: 初回起動時に settings の startup warning が 0 件であることを目視確認してください(unmatched permission rule / unknown key の検出)"
