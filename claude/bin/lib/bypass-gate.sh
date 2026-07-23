#!/usr/bin/env bash
# bypass-gate.sh — claude-bypass の環境・marker 検証ロジック（pure helper）
#
# production entrypoint（claude-bypass）は本 helper を実引数（/proc/version・id -u）で呼び、
# 環境変数による判定の差し替えは受け付けない。テストは本 helper を fixture 引数で直接呼ぶ
# （dependency injection によるテスト分離。production 判定は偽装できない）。

# 環境検証: WSL2 かつ非 root のときだけ 0 を返す
#   $1: /proc/version 相当のファイル path
#   $2: 実効 UID
# WSL2 kernel は "microsoft-standard"（例: 5.15.x-microsoft-standard-WSL2）を含む。
# WSL1（例: 4.4.0-19041-Microsoft）はこの署名を含まないため明示的に拒否される。
bypass_env_check() {
  local proc_version="$1" uid="$2"
  if [[ ! -r "$proc_version" ]]; then
    echo "environment: $proc_version を読めません" >&2
    return 1
  fi
  if ! grep -q 'microsoft-standard' "$proc_version"; then
    if grep -qi 'microsoft' "$proc_version"; then
      echo "environment: WSL1 相当の kernel 署名です（WSL2 の 'microsoft-standard' 署名なし）。WSL2 へ upgrade してください" >&2
    else
      echo "environment: WSL2 kernel 署名（microsoft-standard）を確認できません" >&2
    fi
    return 1
  fi
  if [[ "$uid" -eq 0 ]]; then
    echo "environment: root での bypass は禁止です" >&2
    return 1
  fi
  return 0
}

# marker 検証: 所有者・権限・schema・期限を検査して 0 を返す
#   $1: marker ファイル path
#   $2: 実効 UID
bypass_marker_check() {
  local marker="$1" uid="$2"
  local owner mode expires today
  if [[ ! -f "$marker" ]]; then
    echo "marker: opt-in がありません（\`claude-bypass --enable-this-machine\` で有効化）" >&2
    return 1
  fi
  owner="$(stat -c %u "$marker")"
  if [[ "$owner" != "$uid" ]]; then
    echo "marker: 所有者（uid=$owner）が実行者（uid=$uid）と一致しません" >&2
    return 1
  fi
  mode="$(stat -c %a "$marker")"
  if [[ "$mode" != "600" ]]; then
    echo "marker: 権限が 600 ではありません（実際: $mode）。\`chmod 600\` するか再有効化してください" >&2
    return 1
  fi
  if ! grep -q '^schema=1$' "$marker"; then
    echo "marker: schema=1 がありません（旧形式または改変。再有効化してください）" >&2
    return 1
  fi
  expires="$(grep '^expires=' "$marker" | head -1 | cut -d= -f2)"
  if [[ ! "$expires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || ! date -d "$expires" +%F >/dev/null 2>&1; then
    echo "marker: expires が不正です（実際: '$expires'）" >&2
    return 1
  fi
  today="$(date +%F)"
  if [[ "$expires" < "$today" ]]; then
    echo "marker: opt-in の期限（$expires）が切れています。再有効化で再判断してください" >&2
    return 1
  fi
  return 0
}
