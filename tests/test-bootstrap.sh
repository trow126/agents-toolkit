#!/usr/bin/env bash
# test-bootstrap.sh — bootstrap.sh のstandaloneテスト
# 実$HOME・実repoには一切触れず、mktemp -d に fixture repo と sandbox HOME を構築して検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

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

assert_false() {
  local desc="$1"
  shift
  if ! "$@" >/dev/null 2>&1; then
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

if [[ ! -x "$BOOTSTRAP" ]]; then
  echo "FAIL: bootstrap script not found or not executable: $BOOTSTRAP" >&2
  exit 1
fi

# fixture repo(mini source tree + mini manifest)を作る。
# entries: link-file x2, link-dir x2 (うち1つは .agents/skills/... の入れ子target)
build_fixture_repo() {
  local repo="$1"
  mkdir -p "$repo/install" "$repo/claude/rules" "$repo/codex" "$repo/shared/skills/agmsg"
  echo "# CLAUDE.md (fixture)" > "$repo/claude/CLAUDE.md"
  echo "# sample rule (fixture)" > "$repo/claude/rules/sample.md"
  echo "# AGENTS.md (fixture)" > "$repo/codex/AGENTS.md"
  echo "# agmsg SKILL.md (fixture)" > "$repo/shared/skills/agmsg/SKILL.md"

  printf 'link-file\tclaude/CLAUDE.md\t.claude/CLAUDE.md\n' > "$repo/install/manifest.tsv"
  printf 'link-dir\tclaude/rules\t.claude/rules\n' >> "$repo/install/manifest.tsv"
  printf 'link-file\tcodex/AGENTS.md\t.codex/AGENTS.md\n' >> "$repo/install/manifest.tsv"
  printf 'link-dir\tshared/skills/agmsg\t.agents/skills/agmsg\n' >> "$repo/install/manifest.tsv"
}

# NO_OVERLAY: 存在しないoverlay rootを指す(overlayなしケースの既定に使う)
NO_OVERLAY="$SANDBOX/no-such-overlay"

run_bootstrap() {
  local repo="$1" home="$2" overlay="$3"
  shift 3
  AGENTS_TOOLKIT_REPO="$repo" HOME="$home" AGENTS_TOOLKIT_OVERLAY="$overlay" "$BOOTSTRAP" "$@"
}

# =========================================================================
# 1. 新規 install (--apply) で全 symlink が正しく張られる
# =========================================================================
REPO1="$SANDBOX/repo1"
HOME1="$SANDBOX/home1"
build_fixture_repo "$REPO1"
mkdir -p "$HOME1"

out=""
rc=0
out="$(run_bootstrap "$REPO1" "$HOME1" "$NO_OVERLAY" --apply 2>&1)" || rc=$?
assert_exit_zero "新規 --apply は成功する" "$rc"

assert_true "\$HOME/.claude/CLAUDE.md が symlink" test -L "$HOME1/.claude/CLAUDE.md"
assert_eq "\$HOME/.claude/CLAUDE.md の解決先" "$REPO1/claude/CLAUDE.md" "$(readlink -f "$HOME1/.claude/CLAUDE.md")"
assert_true "\$HOME/.claude/rules が symlink" test -L "$HOME1/.claude/rules"
assert_eq "\$HOME/.claude/rules の解決先" "$REPO1/claude/rules" "$(readlink -f "$HOME1/.claude/rules")"
assert_true "\$HOME/.codex/AGENTS.md が symlink" test -L "$HOME1/.codex/AGENTS.md"
assert_true "\$HOME/.agents/skills/agmsg が symlink" test -L "$HOME1/.agents/skills/agmsg"
assert_eq "\$HOME/.agents/skills/agmsg の解決先" "$REPO1/shared/skills/agmsg" "$(readlink -f "$HOME1/.agents/skills/agmsg")"

# =========================================================================
# 2. 2回目の --apply が冪等(ok扱い・exit 0)
# =========================================================================
out=""
rc=0
out="$(run_bootstrap "$REPO1" "$HOME1" "$NO_OVERLAY" --apply 2>&1)" || rc=$?
assert_exit_zero "2回目の --apply も成功する(冪等)" "$rc"
assert_contains "2回目の --apply は ok 扱いになる" "$out" "ok: $HOME1/.claude/CLAUDE.md"

# =========================================================================
# 3. --check: 一致で0 / symlink欠落で非ゼロ / 別の場所を指すsymlinkで非ゼロ+列挙
# =========================================================================
out=""
rc=0
out="$(run_bootstrap "$REPO1" "$HOME1" "$NO_OVERLAY" --check 2>&1)" || rc=$?
assert_exit_zero "一致状態で --check は成功する" "$rc"
assert_contains "--check の成功メッセージにPASSが含まれる" "$out" "PASS: all 4 manifest entries are correctly linked"

REPO3B="$SANDBOX/repo3b"
HOME3B="$SANDBOX/home3b"
build_fixture_repo "$REPO3B"
mkdir -p "$HOME3B"
run_bootstrap "$REPO3B" "$HOME3B" "$NO_OVERLAY" --apply >/dev/null
rm "$HOME3B/.codex/AGENTS.md"
out=""
rc=0
out="$(run_bootstrap "$REPO3B" "$HOME3B" "$NO_OVERLAY" --check 2>&1)" || rc=$?
assert_exit_nonzero "symlink欠落があると --check は失敗する" "$rc"
assert_contains "欠落エントリが列挙される" "$out" "DRIFT: $HOME3B/.codex/AGENTS.md が存在しません"

REPO3C="$SANDBOX/repo3c"
HOME3C="$SANDBOX/home3c"
build_fixture_repo "$REPO3C"
mkdir -p "$HOME3C"
run_bootstrap "$REPO3C" "$HOME3C" "$NO_OVERLAY" --apply >/dev/null
rm "$HOME3C/.codex/AGENTS.md"
echo "elsewhere" > "$SANDBOX/elsewhere.md"
ln -s "$SANDBOX/elsewhere.md" "$HOME3C/.codex/AGENTS.md"
out=""
rc=0
out="$(run_bootstrap "$REPO3C" "$HOME3C" "$NO_OVERLAY" --check 2>&1)" || rc=$?
assert_exit_nonzero "別の場所を指す symlink があると --check は失敗する" "$rc"
assert_contains "別の場所を指す symlink が列挙される" "$out" "DRIFT: $HOME3C/.codex/AGENTS.md は別の場所"

# =========================================================================
# 4. --dry-run がファイルを変更しない
# =========================================================================
REPO4="$SANDBOX/repo4"
HOME4="$SANDBOX/home4"
build_fixture_repo "$REPO4"
mkdir -p "$HOME4"
out=""
rc=0
out="$(run_bootstrap "$REPO4" "$HOME4" "$NO_OVERLAY" --dry-run 2>&1)" || rc=$?
assert_exit_zero "--dry-run は成功する" "$rc"
assert_contains "--dry-run は would link を出力する" "$out" "would link: $HOME4/.claude/CLAUDE.md"
assert_false "--dry-run 後も \$HOME/.claude/CLAUDE.md は作られない" test -e "$HOME4/.claude/CLAUDE.md"
assert_false "--dry-run 後も \$HOME/.claude は作られない" test -e "$HOME4/.claude"

# =========================================================================
# 5. 既存実体(target に実file/dir)でエラー・上書きしない
# =========================================================================
REPO5="$SANDBOX/repo5"
HOME5="$SANDBOX/home5"
build_fixture_repo "$REPO5"
mkdir -p "$HOME5/.claude"
echo "SENTINEL" > "$HOME5/.claude/CLAUDE.md"
out=""
rc=0
out="$(run_bootstrap "$REPO5" "$HOME5" "$NO_OVERLAY" --apply 2>&1)" || rc=$?
assert_exit_nonzero "既存実体があると --apply は失敗する" "$rc"
assert_contains "既存実体エラーメッセージ" "$out" "実体が存在します"
assert_eq "既存実体の内容は上書きされない" "SENTINEL" "$(cat "$HOME5/.claude/CLAUDE.md")"
assert_false "既存実体は symlink 化されない" test -L "$HOME5/.claude/CLAUDE.md"

# =========================================================================
# 6. 欠損sourceでエラー(fail-fast、何も作られない)
# =========================================================================
REPO6="$SANDBOX/repo6"
HOME6="$SANDBOX/home6"
build_fixture_repo "$REPO6"
mkdir -p "$HOME6"
rm "$REPO6/codex/AGENTS.md"
out=""
rc=0
out="$(run_bootstrap "$REPO6" "$HOME6" "$NO_OVERLAY" --apply 2>&1)" || rc=$?
assert_exit_nonzero "source欠損だと --apply は失敗する" "$rc"
assert_contains "source欠損エラーメッセージ" "$out" "source ファイルが存在しません"
assert_false "fail-fast: \$HOME/.claude/CLAUDE.md も作られない" test -e "$HOME6/.claude/CLAUDE.md"

# =========================================================================
# 7. target重複manifestでエラー
# =========================================================================
REPO7="$SANDBOX/repo7"
HOME7="$SANDBOX/home7"
build_fixture_repo "$REPO7"
mkdir -p "$HOME7"
printf 'link-file\tclaude/rules/sample.md\t.claude/CLAUDE.md\n' >> "$REPO7/install/manifest.tsv"
out=""
rc=0
out="$(run_bootstrap "$REPO7" "$HOME7" "$NO_OVERLAY" --apply 2>&1)" || rc=$?
assert_exit_nonzero "target重複だと --apply は失敗する" "$rc"
assert_contains "target重複エラーメッセージ" "$out" "target が重複しています"

# =========================================================================
# 8. overlay: なし / あり / overlay内重複 / overlay root外参照
# =========================================================================

# --- overlayなし: 黙ってスキップ ---
REPO8A="$SANDBOX/repo8a"
HOME8A="$SANDBOX/home8a"
build_fixture_repo "$REPO8A"
mkdir -p "$HOME8A"
out=""
rc=0
out="$(run_bootstrap "$REPO8A" "$HOME8A" "$NO_OVERLAY" --apply 2>&1)" || rc=$?
assert_exit_zero "overlayなしでも --apply は成功する" "$rc"

# --- overlayあり: overlay entryも張られる ---
REPO8B="$SANDBOX/repo8b"
HOME8B="$SANDBOX/home8b"
OVERLAY8B="$SANDBOX/overlay8b"
build_fixture_repo "$REPO8B"
mkdir -p "$HOME8B" "$OVERLAY8B"
echo "# overlay CLAUDE.local.md (fixture)" > "$OVERLAY8B/CLAUDE.local.md"
printf 'link-file\tCLAUDE.local.md\t.claude/CLAUDE.local.md\n' > "$OVERLAY8B/manifest.tsv"
out=""
rc=0
out="$(run_bootstrap "$REPO8B" "$HOME8B" "$OVERLAY8B" --apply 2>&1)" || rc=$?
assert_exit_zero "overlayありで --apply は成功する" "$rc"
assert_true "overlay entry \$HOME/.claude/CLAUDE.local.md が symlink" test -L "$HOME8B/.claude/CLAUDE.local.md"
assert_eq "overlay entry の解決先は overlay root" "$OVERLAY8B/CLAUDE.local.md" "$(readlink -f "$HOME8B/.claude/CLAUDE.local.md")"
assert_true "公開manifest entryも引き続き張られる" test -L "$HOME8B/.claude/CLAUDE.md"

# --- overlay内target重複でエラー ---
REPO8C="$SANDBOX/repo8c"
HOME8C="$SANDBOX/home8c"
OVERLAY8C="$SANDBOX/overlay8c"
build_fixture_repo "$REPO8C"
mkdir -p "$HOME8C" "$OVERLAY8C"
echo "a" > "$OVERLAY8C/a.md"
echo "b" > "$OVERLAY8C/b.md"
printf 'link-file\ta.md\t.claude/CLAUDE.local.md\n' > "$OVERLAY8C/manifest.tsv"
printf 'link-file\tb.md\t.claude/CLAUDE.local.md\n' >> "$OVERLAY8C/manifest.tsv"
out=""
rc=0
out="$(run_bootstrap "$REPO8C" "$HOME8C" "$OVERLAY8C" --apply 2>&1)" || rc=$?
assert_exit_nonzero "overlay内target重複だと失敗する" "$rc"
assert_contains "overlay内target重複エラーメッセージ" "$out" "target が重複しています"

# --- overlay ⇔ 公開 manifest 間のtarget重複でエラー ---
REPO8D="$SANDBOX/repo8d"
HOME8D="$SANDBOX/home8d"
OVERLAY8D="$SANDBOX/overlay8d"
build_fixture_repo "$REPO8D"
mkdir -p "$HOME8D" "$OVERLAY8D"
echo "dup" > "$OVERLAY8D/dup.md"
printf 'link-file\tdup.md\t.claude/CLAUDE.md\n' > "$OVERLAY8D/manifest.tsv"
out=""
rc=0
out="$(run_bootstrap "$REPO8D" "$HOME8D" "$OVERLAY8D" --apply 2>&1)" || rc=$?
assert_exit_nonzero "公開manifestとoverlayのtarget重複だと失敗する" "$rc"
assert_contains "公開/overlay target重複エラーメッセージ" "$out" "target が重複しています"

# --- overlay root外参照(source に .. を含む)でエラー ---
REPO8E="$SANDBOX/repo8e"
HOME8E="$SANDBOX/home8e"
OVERLAY8E="$SANDBOX/overlay8e"
build_fixture_repo "$REPO8E"
mkdir -p "$HOME8E" "$OVERLAY8E"
echo "secret" > "$SANDBOX/secret.md"
printf 'link-file\t../secret.md\t.claude/CLAUDE.local.md\n' > "$OVERLAY8E/manifest.tsv"
out=""
rc=0
out="$(run_bootstrap "$REPO8E" "$HOME8E" "$OVERLAY8E" --apply 2>&1)" || rc=$?
assert_exit_nonzero "overlay root外参照だと失敗する" "$rc"
assert_contains "overlay root外参照エラーメッセージ" "$out" "source に .. を含めることはできません"

# --- overlay manifestの余剰列でエラー ---
REPO8F="$SANDBOX/repo8f"
HOME8F="$SANDBOX/home8f"
OVERLAY8F="$SANDBOX/overlay8f"
build_fixture_repo "$REPO8F"
mkdir -p "$HOME8F" "$OVERLAY8F"
echo "private" > "$OVERLAY8F/private.md"
printf 'link-file\tprivate.md\t.claude/private.md\textra\n' > "$OVERLAY8F/manifest.tsv"
out=""
rc=0
out="$(run_bootstrap "$REPO8F" "$HOME8F" "$OVERLAY8F" --apply 2>&1)" || rc=$?
assert_exit_nonzero "overlay manifestの4列行は失敗する" "$rc"
assert_contains "overlay余剰列のエラーに実列数が含まれる" "$out" "実際: 4列"

# --- source symlinkがoverlay root外を指す場合はエラー ---
REPO8G="$SANDBOX/repo8g"
HOME8G="$SANDBOX/home8g"
OVERLAY8G="$SANDBOX/overlay8g"
build_fixture_repo "$REPO8G"
mkdir -p "$HOME8G" "$OVERLAY8G"
echo "secret" > "$SANDBOX/outside-secret.md"
ln -s "$SANDBOX/outside-secret.md" "$OVERLAY8G/private.md"
printf 'link-file\tprivate.md\t.claude/private.md\n' > "$OVERLAY8G/manifest.tsv"
out=""
rc=0
out="$(run_bootstrap "$REPO8G" "$HOME8G" "$OVERLAY8G" --apply 2>&1)" || rc=$?
assert_exit_nonzero "overlay外を指すsource symlinkは失敗する" "$rc"
assert_contains "source symlinkの実体pathが表示される" "$out" "source root 外"

# --- target親子関係はsource treeへの書き込みを防ぐため拒否 ---
REPO8H="$SANDBOX/repo8h"
HOME8H="$SANDBOX/home8h"
build_fixture_repo "$REPO8H"
mkdir -p "$HOME8H"
printf 'link-file\tcodex/AGENTS.md\t.claude/rules/AGENTS.md\n' >> "$REPO8H/install/manifest.tsv"
out=""
rc=0
out="$(run_bootstrap "$REPO8H" "$HOME8H" "$NO_OVERLAY" --apply 2>&1)" || rc=$?
assert_exit_nonzero "target親子関係は失敗する" "$rc"
assert_contains "target親子関係が列挙される" "$out" "target が親子関係"
assert_false "target topology失敗時は1件も作成しない" test -e "$HOME8H/.claude/CLAUDE.md"

# --- 後半targetの既存実体も全件preflightし、partial installを防ぐ ---
REPO8I="$SANDBOX/repo8i"
HOME8I="$SANDBOX/home8i"
build_fixture_repo "$REPO8I"
mkdir -p "$HOME8I/.agents/skills/agmsg"
echo "SENTINEL" > "$HOME8I/.agents/skills/agmsg/existing"
out=""
rc=0
out="$(run_bootstrap "$REPO8I" "$HOME8I" "$NO_OVERLAY" --apply 2>&1)" || rc=$?
assert_exit_nonzero "後半target衝突は失敗する" "$rc"
assert_false "後半target衝突でも先頭targetを作成しない" test -e "$HOME8I/.claude/CLAUDE.md"
assert_eq "既存target内容は保持される" "SENTINEL" "$(cat "$HOME8I/.agents/skills/agmsg/existing")"

# =========================================================================
# 9. 「親が repo を指す symlink」ガードが発火してエラーになる
# =========================================================================
REPO9="$SANDBOX/repo9"
HOME9="$SANDBOX/home9"
build_fixture_repo "$REPO9"
mkdir -p "$HOME9"
ln -s "$REPO9/claude" "$HOME9/.claude"
out=""
rc=0
out="$(run_bootstrap "$REPO9" "$HOME9" "$NO_OVERLAY" --apply 2>&1)" || rc=$?
assert_exit_nonzero "旧whole-directory symlink構成だと --apply は失敗する" "$rc"
assert_contains "旧構成ガードのエラーメッセージ" "$out" "旧構成が未 migration"
assert_contains "旧構成ガードが migrate-layout.sh を案内する" "$out" "migrate-layout.sh"

# 同ガードは --check でも発火する
out=""
rc=0
out="$(run_bootstrap "$REPO9" "$HOME9" "$NO_OVERLAY" --check 2>&1)" || rc=$?
assert_exit_nonzero "旧構成では --check も失敗する" "$rc"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
