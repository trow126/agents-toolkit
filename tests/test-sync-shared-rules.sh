#!/usr/bin/env bash
# test-sync-shared-rules.sh — shared/bin/sync-shared-rules.sh のstandaloneテスト
# 実$HOME・実repoには一切触れず、mktemp -d に最小の疑似repoを構築して検証する。
# SYNC_MAP（NAME<TAB>target対応表）は複製せず、テスト対象scriptのheredocからそのまま抽出する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/shared/bin/sync-shared-rules.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0

assert_true() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (expected=$expected actual=$actual)" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_exit_zero() {
  local desc="$1" rc="$2"
  if [[ "$rc" -eq 0 ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (exit=$rc)" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_exit_nonzero() {
  local desc="$1" rc="$2"
  if [[ "$rc" -ne 0 ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (expected non-zero exit, got 0)" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (expected output to contain: $needle)" >&2
    echo "--- actual output ---" >&2
    echo "$haystack" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

if [[ ! -f "$SYNC_SCRIPT" ]]; then
  echo "FAIL: sync script not found: $SYNC_SCRIPT" >&2
  exit 1
fi

# テスト対象scriptのheredocからSYNC_MAPをそのまま抽出する(テスト側での二重管理を避ける)
SYNC_MAP="$(sed -n "/^SYNC_MAP=\$(cat <<'EOF'\$/,/^EOF\$/p" "$SYNC_SCRIPT" | sed '1d;$d')"
if [[ -z "$SYNC_MAP" ]]; then
  echo "FAIL: SYNC_MAP could not be extracted from $SYNC_SCRIPT" >&2
  exit 1
fi

# ちょうど1つのtargetにしか出現しないNAMEを1つ選ぶ(marker破損テスト用。重複target名だと
# 破損の影響先が曖昧になるため避ける)
CORRUPT_NAME=""
CORRUPT_TARGET=""
read -r CORRUPT_NAME CORRUPT_TARGET < <(
  awk -F'\t' '{c[$1]++; t[$1]=$2} END{for (n in c) if (c[n]==1) {print n"\t"t[n]; exit}}' <<< "$SYNC_MAP"
)
if [[ -z "$CORRUPT_NAME" ]]; then
  echo "FAIL: could not pick a single-target NAME from SYNC_MAP for corruption tests" >&2
  exit 1
fi

# --- fixture構築: SYNC_MAPにある全NAME/targetを実装した最小repoを作る ---
build_fixture() {
  local repo="$1"
  mkdir -p "$repo/shared/bin" "$repo/shared/rules" "$repo/codex" "$repo/claude/rules"

  cp "$SYNC_SCRIPT" "$repo/shared/bin/sync-shared-rules.sh"
  chmod +x "$repo/shared/bin/sync-shared-rules.sh"

  declare -A target_content=()
  local name target block
  while IFS=$'\t' read -r name target; do
    [[ -z "$name" ]] && continue
    if [[ ! -f "$repo/shared/rules/$name.md" ]]; then
      printf 'baseline content for %s\nline two\n' "$name" > "$repo/shared/rules/$name.md"
    fi
    block="<!-- BEGIN shared:$name -->
$(cat "$repo/shared/rules/$name.md")
<!-- END shared:$name -->
"
    target_content["$target"]="${target_content[$target]:-}$block"
  done <<< "$SYNC_MAP"

  local t
  for t in "${!target_content[@]}"; do
    mkdir -p "$repo/$(dirname "$t")"
    printf '%s' "${target_content[$t]}" > "$repo/$t"
  done
}

run_sync() {
  local repo="$1"
  shift
  "$repo/shared/bin/sync-shared-rules.sh" "$@"
}

mutate_canonical() {
  local repo="$1" name="$2"
  printf 'mutated line for %s\n' "$name" >> "$repo/shared/rules/$name.md"
}

corrupt_missing_begin() {
  local repo="$1"
  local f="$repo/$CORRUPT_TARGET"
  grep -vF "<!-- BEGIN shared:$CORRUPT_NAME -->" "$f" > "$f.new"
  mv "$f.new" "$f"
}

corrupt_missing_end() {
  local repo="$1"
  local f="$repo/$CORRUPT_TARGET"
  grep -vF "<!-- END shared:$CORRUPT_NAME -->" "$f" > "$f.new"
  mv "$f.new" "$f"
}

corrupt_duplicate() {
  local repo="$1"
  local f="$repo/$CORRUPT_TARGET"
  awk -v begin="<!-- BEGIN shared:$CORRUPT_NAME -->" -v end="<!-- END shared:$CORRUPT_NAME -->" '
    $0 == begin { capturing = 1 }
    capturing { block = block $0 "\n" }
    $0 == end { capturing = 0 }
    { print }
    END { printf "%s", block }
  ' "$f" > "$f.new"
  mv "$f.new" "$f"
}

corrupt_invert() {
  local repo="$1"
  local f="$repo/$CORRUPT_TARGET"
  awk -v begin="<!-- BEGIN shared:$CORRUPT_NAME -->" -v end="<!-- END shared:$CORRUPT_NAME -->" '
    $0 == begin { print end; next }
    $0 == end { print begin; next }
    { print }
  ' "$f" > "$f.new"
  mv "$f.new" "$f"
}

echo "== corruption test target: NAME=$CORRUPT_NAME TARGET=$CORRUPT_TARGET =="
echo

# --- 1. 一致状態で --check が0 ---
REPO1="$SANDBOX/repo1"
build_fixture "$REPO1"
out=""
rc=0
out="$(run_sync "$REPO1" --check 2>&1)" || rc=$?
assert_exit_zero "一致状態で --check は成功する" "$rc"
assert_contains "--check の成功メッセージにOKが含まれる" "$out" "OK: all synced blocks match canonical sources"

# --- 2. 正本を書き換えると --check がdriftを検出して非ゼロ ---
REPO2="$SANDBOX/repo2"
build_fixture "$REPO2"
mutate_canonical "$REPO2" "$CORRUPT_NAME"
out=""
rc=0
out="$(run_sync "$REPO2" --check 2>&1)" || rc=$?
assert_exit_nonzero "正本変更後は --check が失敗する" "$rc"
assert_contains "drift出力に対象NAMEが含まれる" "$out" "DRIFT: shared:$CORRUPT_NAME"

# --- 3. --write 後に --check が0に戻り、全consumerが正本と一致する ---
out=""
rc=0
out="$(run_sync "$REPO2" --write 2>&1)" || rc=$?
assert_exit_zero "--write は成功する" "$rc"
out=""
rc=0
out="$(run_sync "$REPO2" --check 2>&1)" || rc=$?
assert_exit_zero "--write 後は --check が成功する" "$rc"
assert_eq "--write 後にconsumerの内容が正本と一致する" \
  "$(cat "$REPO2/shared/rules/$CORRUPT_NAME.md")" \
  "$(sed -n "/<!-- BEGIN shared:$CORRUPT_NAME -->/,/<!-- END shared:$CORRUPT_NAME -->/p" "$REPO2/$CORRUPT_TARGET" | sed '1d;$d')"

# --- atomic書き込みの確認: --write 後にtarget隣接ディレクトリへ一時ファイルが残らない ---
STRAY_COUNT=$(find "$REPO2/$(dirname "$CORRUPT_TARGET")" -maxdepth 1 -name "$(basename "$CORRUPT_TARGET").*" | wc -l)
assert_eq "--write 後に一時ファイルが残らない" "0" "$STRAY_COUNT"

# --- 4. 引数なしが --write と同動作 ---
REPO3="$SANDBOX/repo3"
build_fixture "$REPO3"
mutate_canonical "$REPO3" "$CORRUPT_NAME"
out=""
rc=0
out="$(run_sync "$REPO3" 2>&1)" || rc=$?
assert_exit_zero "引数なし実行は成功する" "$rc"
assert_contains "引数なし実行はsyncedログを出す(--write相当)" "$out" "synced shared:$CORRUPT_NAME -> $CORRUPT_TARGET"
out=""
rc=0
out="$(run_sync "$REPO3" --check 2>&1)" || rc=$?
assert_exit_zero "引数なし実行後は --check が成功する" "$rc"

# --- 5. marker欠落・重複・逆転の各エラーケース ---
REPO4="$SANDBOX/repo4"
build_fixture "$REPO4"
corrupt_missing_begin "$REPO4"
out=""
rc=0
out="$(run_sync "$REPO4" --check 2>&1)" || rc=$?
assert_exit_nonzero "BEGINマーカー欠落は失敗する" "$rc"
assert_contains "BEGINマーカー欠落のエラーメッセージ" "$out" "not found"

REPO5="$SANDBOX/repo5"
build_fixture "$REPO5"
corrupt_missing_end "$REPO5"
out=""
rc=0
out="$(run_sync "$REPO5" --check 2>&1)" || rc=$?
assert_exit_nonzero "ENDマーカー欠落は失敗する" "$rc"
assert_contains "ENDマーカー欠落のエラーメッセージ" "$out" "not found"

REPO6="$SANDBOX/repo6"
build_fixture "$REPO6"
corrupt_duplicate "$REPO6"
out=""
rc=0
out="$(run_sync "$REPO6" --check 2>&1)" || rc=$?
assert_exit_nonzero "マーカー区間重複は失敗する" "$rc"
assert_contains "マーカー区間重複のエラーメッセージ" "$out" "duplicate marker region for shared:$CORRUPT_NAME"

REPO7="$SANDBOX/repo7"
build_fixture "$REPO7"
corrupt_invert "$REPO7"
out=""
rc=0
out="$(run_sync "$REPO7" --check 2>&1)" || rc=$?
assert_exit_nonzero "BEGIN/END逆転は失敗する" "$rc"
assert_contains "BEGIN/END逆転のエラーメッセージ" "$out" "marker order inverted for shared:$CORRUPT_NAME"

# --- エラーケースでファイルが変更されていないこと(--checkは非破壊) ---
if grep -qF "<!-- BEGIN shared:$CORRUPT_NAME -->" "$REPO4/$CORRUPT_TARGET"; then
  echo "FAIL: repo4 の破損($CORRUPT_TARGET)が --check 実行後に復元されている(--checkが書き込んでいる)" >&2
  FAILURES=$((FAILURES + 1))
else
  echo "ok: BEGIN欠落エラー後もrepo4は破損したまま(--checkが書き込まない)"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
