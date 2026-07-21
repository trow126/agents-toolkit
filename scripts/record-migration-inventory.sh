#!/usr/bin/env bash
# record-migration-inventory.sh — 構造移行(Phase 1)向けread-only inventory記録
# ~/.claude, ~/.codex, ~/.agents のsymlink targetと、
# claude/・codex/・shared/直下entryのpath・容量・所有者・種別(tracked/untracked/ignored/mixed)を
# XDG_STATE_HOME配下のtimestamp付きfileへ書き出す。
# ファイル内容やsecret値は記録しない。repositoryへは何も書き込まない。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
OUT_DIR="$STATE_HOME/agents-toolkit/migration"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUT_FILE="$OUT_DIR/inventory-$TIMESTAMP.txt"

mkdir -p "$OUT_DIR"

# entryの種別を判定する(directoryはtracked/untracked混在ならmixed)
classify_entry() {
  local path="$1"
  if [[ -d "$path" ]]; then
    local tracked_count untracked_count
    tracked_count="$(git -C "$REPO_DIR" ls-files -- "$path" | wc -l)"
    untracked_count="$(git -C "$REPO_DIR" status --porcelain --ignored=matching -- "$path" | wc -l)"
    if [[ "$tracked_count" -gt 0 && "$untracked_count" -gt 0 ]]; then
      echo "mixed"
    elif [[ "$tracked_count" -gt 0 ]]; then
      echo "tracked"
    else
      echo "untracked"
    fi
  else
    if git -C "$REPO_DIR" ls-files --error-unmatch "$path" >/dev/null 2>&1; then
      echo "tracked"
    elif git -C "$REPO_DIR" check-ignore -q "$path"; then
      echo "ignored"
    else
      echo "untracked"
    fi
  fi
}

# リポジトリ内directory直下entryのpath・容量・所有者・種別を記録する
record_dir_entries() {
  local rel_dir="$1"
  local abs_dir="$REPO_DIR/$rel_dir"
  [[ -d "$abs_dir" ]] || return 0
  local entry name rel_path size owner kind
  for entry in "$abs_dir"/* "$abs_dir"/.[!.]* "$abs_dir"/..?*; do
    [[ -e "$entry" ]] || continue
    name="$(basename "$entry")"
    rel_path="$rel_dir/$name"
    size="$(du -sh "$entry" 2>/dev/null | cut -f1)"
    owner="$(stat -c '%U' "$entry" 2>/dev/null)"
    kind="$(classify_entry "$rel_path")"
    printf '%s\t%s\t%s\t%s\n' "$rel_path" "$size" "$owner" "$kind"
  done
}

{
  echo "# agents-toolkit migration inventory"
  echo "# generated: $TIMESTAMP"
  echo "# repo: $REPO_DIR"
  echo

  echo "## symlinks"
  for name in claude codex agents; do
    local_home="$HOME/.$name"
    if [[ -L "$local_home" ]]; then
      raw_target="$(readlink "$local_home")"
      resolved_target="$(readlink -f "$local_home" 2>/dev/null || echo "UNRESOLVABLE")"
      printf '%s\tsymlink\t%s\t%s\n' "$local_home" "$raw_target" "$resolved_target"
    elif [[ -e "$local_home" ]]; then
      printf '%s\tNOT_A_SYMLINK\n' "$local_home"
    else
      printf '%s\tMISSING\n' "$local_home"
    fi
  done
  echo

  echo "## entries (path, size, owner, kind)"
  for d in claude codex shared; do
    record_dir_entries "$d"
  done
} > "$OUT_FILE"

echo "wrote: $OUT_FILE"
