#!/usr/bin/env bash
# check-runtime.sh — Claude Code runtime / 環境前提の doctor(2026-07-23 H-017, 2026-07-24 改訂)
#
# 検査内容:
#   1. XDG base directory が toolkit の対応済み既定値であること(H-013)
#      install manifest、runtime path、診断の整合を保つため custom XDG はサポートしない。
#   2. current project の .claude/settings*.json が managed owner policy を
#      上書き・拡張する security surface を持たないこと(C-02)
#   3. Claude Code version が検証済み下限以上の stable であること(H-017)
#      本 toolkit の settings は requiredMinimumVersion、
#      skipDangerousModePermissionPrompt、managed hooks 等の現行挙動に依存する。
#      検証済み下限: 2.1.218。prerelease(例: 2.1.218-beta.1)は検証対象外として拒否する。
#      managed policy の requiredMinimumVersion=2.1.218 が対応versionでは startupを拒否する。
#      それ以前のversionは当該keyを認識しないため、本 script + bootstrap も defense-in-depth
#      の version gate として維持する。
#
# 呼び出し:
#   standalone:                scripts/check-runtime.sh           (claude 欠落もエラー)
#   bootstrap --check/--apply: scripts/check-runtime.sh --soft-missing
#                              (claude 欠落は NOTE で続行。codex 専用マシンを壊さない)
set -euo pipefail

MINIMUM="2.1.218"
TESTED_MAJOR="2"
SOFT_MISSING="false"
SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "${SCRIPT_PATH%/*}" && pwd -P)"
PROJECT_POLICY_GATE="$SCRIPT_DIR/../claude/bin/project-policy-gate"

for arg in "$@"; do
  case "$arg" in
    --soft-missing) SOFT_MISSING="true" ;;
    *) echo "ERROR: unknown option: $arg (usage: check-runtime.sh [--soft-missing])" >&2; exit 1 ;;
  esac
done

fail=0

# --- 1. XDG 既定値検査(H-013/H-03/M-05) ---
# Lexical comparisonではなく absolute/real path を正規化して比較する。
# trailing slash・".."・既存symlinkの表記差は同一pathとして扱う。
normalize_path() {
  python3 - "$1" <<'PY_NORM'
import os
import sys
p = os.path.expanduser(sys.argv[1])
if not os.path.isabs(p):
    raise SystemExit(2)
print(os.path.realpath(p))
PY_NORM
}

check_xdg() {
  local var="$1" default="$2" val normalized default_normalized
  val="${!var:-}"
  [[ -z "$val" ]] && return 0
  if ! normalized="$(normalize_path "$val")"; then
    echo "ERROR: $var must be an absolute path: $val" >&2
    fail=1
    return 0
  fi
  default_normalized="$(normalize_path "$default")"
  if [[ "$normalized" != "$default_normalized" ]]; then
    echo "ERROR: $var=$val resolves to $normalized, but the supported default is $default_normalized. Custom XDG is outside the toolkit's installed/runtime path contract." >&2
    fail=1
  fi
}
check_xdg XDG_CONFIG_HOME "$HOME/.config"
check_xdg XDG_STATE_HOME  "$HOME/.local/state"
check_xdg XDG_DATA_HOME   "$HOME/.local/share"
check_xdg XDG_CACHE_HOME  "$HOME/.cache"
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "OK: XDG base directories resolve to toolkit-supported defaults"

# --- 2. project/local settings gate(C-02) ---
if [[ ! -x "$PROJECT_POLICY_GATE" ]]; then
  echo "ERROR: project policy gate is missing or not executable: $PROJECT_POLICY_GATE" >&2
  exit 1
fi
PROJECT_CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
if ! "$PROJECT_POLICY_GATE" --cwd "$PROJECT_CWD" --quiet; then
  echo "ERROR: unsafe project/local Claude settings detected; runtime startup is blocked fail-closed" >&2
  exit 1
fi
echo "OK: project/local Claude settings contain no managed-policy overrides"

# --- 3. Claude Code version 検査(H-017) ---
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
  echo "ERROR: Claude Code $VER は検証済み下限 $MINIMUM 未満です。設定(requiredMinimumVersion / bypassPermissions / managed hooks)が部分適用になる恐れがあるため、更新してから利用してください" >&2
  exit 1
fi

major="${VER%%.*}"
if [[ "$major" != "$TESTED_MAJOR" ]]; then
  echo "NOTE: Claude Code $VER は検証済み major($TESTED_MAJOR.x)と異なります。設定 semantics の互換を release note で確認してください"
fi

echo "OK: Claude Code $VER (>= $MINIMUM, stable)"
echo "NOTE: 初回起動時に settings の startup warning が 0 件であることを目視確認してください(unmatched permission rule / unknown key の検出)"
