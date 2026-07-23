#!/usr/bin/env bash
# check-runtime.sh — Claude Code runtime version の互換性 doctor(2026-07-23 H-017)
#
# 本 toolkit の settings は以下の比較的新しい semantics に依存する:
#   - sandbox.credentials(v2.1.187+)
#   - Read()/Edit() path rule の file permission check 挙動(v2.1.208+)
#   - permissions.disableBypassPermissionsMode / ask rule の現行挙動
# 検証済み下限: 2.1.218(2026-07-23 の検証環境)。下限未満は設定が部分適用になり得るため
# 明示エラーで非ゼロ終了する(silent continuation しない)。
set -euo pipefail

MINIMUM="2.1.218"

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: claude CLI が見つかりません。導入後に再実行してください" >&2
  exit 1
fi

RAW="$(claude --version 2>/dev/null | head -1)"
VER="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<< "$RAW" | head -1)"
if [[ -z "$VER" ]]; then
  echo "ERROR: claude --version の出力から version を解釈できません: '$RAW'" >&2
  exit 1
fi

lower="$(printf '%s\n%s\n' "$MINIMUM" "$VER" | sort -V | head -1)"
if [[ "$lower" != "$MINIMUM" ]]; then
  echo "ERROR: Claude Code $VER は検証済み下限 $MINIMUM 未満です。設定(sandbox.credentials / path rule / bypass lockout)が部分適用になる恐れがあるため、更新してから利用してください" >&2
  exit 1
fi

echo "OK: Claude Code $VER (>= $MINIMUM)"
echo "NOTE: 初回起動時に settings の startup warning が 0 件であることを目視確認してください(unmatched permission rule / unknown key の検出)"
