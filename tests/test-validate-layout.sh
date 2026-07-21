#!/usr/bin/env bash
# test-validate-layout.sh — scripts/validate-layout.sh のstandaloneテスト
# 実$HOME・実repoには一切触れず、mktemp -d に mini repo fixture(実git repo)を構築して検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE_SCRIPT="$REPO_ROOT/scripts/validate-layout.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0

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

if [[ ! -x "$VALIDATE_SCRIPT" ]]; then
  echo "FAIL: validate-layout script not found or not executable: $VALIDATE_SCRIPT" >&2
  exit 1
fi

# fixture repo: manifest整合が取れた最小構成(claude/codex/shared)を実git repoとして構築する。
# shared/rules/rule-a.md は claude/CLAUDE.md の @~/.agents/rules/ import で、
# shared/rules/rule-b.md は sync-shared-rules.sh の SYNC_MAP で、それぞれ別経路で消費させる。
build_fixture() {
  local repo="$1"
  mkdir -p "$repo/install" "$repo/scripts" \
    "$repo/claude/rules" "$repo/claude/agents" "$repo/claude/githooks" \
    "$repo/codex" \
    "$repo/shared/bin" "$repo/shared/rules"

  cp "$VALIDATE_SCRIPT" "$repo/scripts/validate-layout.sh"
  chmod +x "$repo/scripts/validate-layout.sh"

  cat > "$repo/install/manifest.tsv" <<'EOF'
# fixture manifest
link-file	claude/CLAUDE.md	.claude/CLAUDE.md
link-dir	claude/rules	.claude/rules
link-dir	claude/agents	.claude/agents
link-file	codex/AGENTS.md	.codex/AGENTS.md
link-dir	shared/rules	.agents/rules
link-dir	shared/bin	.agents/bin
EOF

  printf '# CLAUDE.md (fixture)\n@~/.agents/rules/rule-a.md\n' > "$repo/claude/CLAUDE.md"
  echo "# gitignore (fixture)" > "$repo/claude/.gitignore"
  echo "# README (fixture)" > "$repo/claude/README.md"
  echo "# pre-commit hook (fixture)" > "$repo/claude/githooks/pre-commit"
  echo "# sample rule (fixture)" > "$repo/claude/rules/sample.md"
  echo "# sample agent (fixture)" > "$repo/claude/agents/sample.md"
  echo "# AGENTS.md (fixture)" > "$repo/codex/AGENTS.md"

  printf '#!/usr/bin/env bash\nSYNC_MAP=$(cat <<'"'"'EOF'"'"'\nrule-b\tcodex/AGENTS.md\nEOF\n)\n' > "$repo/shared/bin/sync-shared-rules.sh"
  chmod +x "$repo/shared/bin/sync-shared-rules.sh"
  echo "# rule-a (consumed via CLAUDE.md import)" > "$repo/shared/rules/rule-a.md"
  echo "# rule-b (consumed via SYNC_MAP)" > "$repo/shared/rules/rule-b.md"

  git -C "$repo" init -q
  git -C "$repo" add -A
}

run_validate() {
  local repo="$1"
  "$repo/scripts/validate-layout.sh"
}

# =========================================================================
# 1. 正常構成は PASS する
# =========================================================================
REPO1="$SANDBOX/repo1"
build_fixture "$REPO1"
mkdir -p "$REPO1/claude/agents/.pytest_cache" "$REPO1/tests"
echo "allowed local cache" > "$REPO1/claude/agents/.pytest_cache/CACHEDIR.TAG"
echo 'fixture path: /home/exampleuser' > "$REPO1/tests/absolute-home-fixture.txt"
git -C "$REPO1" add tests/absolute-home-fixture.txt
out=""
rc=0
out="$(run_validate "$REPO1" 2>&1)" || rc=$?
assert_exit_zero "正常構成は exit 0" "$rc"
assert_contains "正常構成は PASS メッセージを出す" "$out" "PASS: no layout violations found"

# =========================================================================
# 2. 禁止runtime名の追跡は非ゼロ+対象列挙
# =========================================================================
REPO2="$SANDBOX/repo2"
build_fixture "$REPO2"
echo '{"fixture":"forbidden"}' > "$REPO2/shared/bin/history.jsonl"
git -C "$REPO2" add -A
out=""
rc=0
out="$(run_validate "$REPO2" 2>&1)" || rc=$?
assert_exit_nonzero "禁止runtime名の追跡は失敗する" "$rc"
assert_contains "禁止runtime名が列挙される" "$out" "forbidden runtime name tracked: shared/bin/history.jsonl"

# =========================================================================
# 3. 絶対home pathの追跡は非ゼロ+対象列挙
# =========================================================================
REPO3="$SANDBOX/repo3"
build_fixture "$REPO3"
echo "see /home/exampleuser/notes for details" > "$REPO3/claude/agents/leaky.md"
git -C "$REPO3" add -A
out=""
rc=0
out="$(run_validate "$REPO3" 2>&1)" || rc=$?
assert_exit_nonzero "絶対home pathの追跡は失敗する" "$rc"
assert_contains "絶対home pathが列挙される" "$out" "absolute home path in claude/agents/leaky.md:1: /home/exampleuser"

# =========================================================================
# 4. manifestが4列(余剰列)だと非ゼロ+対象列挙
# =========================================================================
REPO4="$SANDBOX/repo4"
build_fixture "$REPO4"
printf 'link-file\tclaude/rules/sample.md\t.claude/rules/sample.md\textra-column\n' >> "$REPO4/install/manifest.tsv"
git -C "$REPO4" add -A
out=""
rc=0
out="$(run_validate "$REPO4" 2>&1)" || rc=$?
assert_exit_nonzero "manifestの4列行は失敗する" "$rc"
assert_contains "4列違反のエラーメッセージ" "$out" "3列が必要です(実際: 4列)"

# =========================================================================
# 5. manifest外(かつallowlist外)のtracked fileは非ゼロ+対象列挙
# =========================================================================
REPO5="$SANDBOX/repo5"
build_fixture "$REPO5"
echo "# untracked-by-manifest fixture file" > "$REPO5/claude/orphan.md"
git -C "$REPO5" add -A
out=""
rc=0
out="$(run_validate "$REPO5" 2>&1)" || rc=$?
assert_exit_nonzero "manifest外tracked fileは失敗する" "$rc"
assert_contains "manifest外tracked fileが列挙される" "$out" "tracked file not covered by manifest or allowlist: claude/orphan.md"

# =========================================================================
# 6. 未消費shared ruleは非ゼロ+対象列挙
# =========================================================================
REPO6="$SANDBOX/repo6"
build_fixture "$REPO6"
echo "# orphan rule (consumed by nothing)" > "$REPO6/shared/rules/rule-orphan.md"
git -C "$REPO6" add -A
out=""
rc=0
out="$(run_validate "$REPO6" 2>&1)" || rc=$?
assert_exit_nonzero "未消費shared ruleは失敗する" "$rc"
assert_contains "未消費shared ruleが列挙される" "$out" "shared rule not consumed by SYNC_MAP or claude/CLAUDE.md import: shared/rules/rule-orphan.md"

# =========================================================================
# 7. 危険設定(bypassPermissions等)はWARNのみでexit codeに影響しない
# =========================================================================
REPO7="$SANDBOX/repo7"
build_fixture "$REPO7"
echo '{"defaultMode": "bypassPermissions"}' > "$REPO7/claude/settings.json"
printf 'link-file\tclaude/settings.json\t.claude/settings.json\n' >> "$REPO7/install/manifest.tsv"
git -C "$REPO7" add -A
out=""
rc=0
out="$(run_validate "$REPO7" 2>&1)" || rc=$?
assert_exit_zero "危険設定はWARNのみでPASSする" "$rc"
assert_contains "危険設定がWARNとして出力される" "$out" "WARN: claude/settings.json:1: bypassPermissions"

# =========================================================================
# 8. generic agent内のproject固有sectionは非ゼロ+対象列挙
# =========================================================================
REPO8="$SANDBOX/repo8"
build_fixture "$REPO8"
printf '\n## Primary Focus（プロジェクト固有）\n' >> "$REPO8/claude/agents/sample.md"
git -C "$REPO8" add -A
out=""
rc=0
out="$(run_validate "$REPO8" 2>&1)" || rc=$?
assert_exit_nonzero "generic agentのproject固有sectionは失敗する" "$rc"
assert_contains "project固有sectionのfileが列挙される" "$out" "project-specific section in generic agent"

# =========================================================================
# 9. link-dir配下の未知local artifactは非ゼロ、許可cacheは正常系でPASS済み
# =========================================================================
REPO9="$SANDBOX/repo9"
build_fixture "$REPO9"
echo "unknown" > "$REPO9/claude/agents/.unknown-runtime"
out=""
rc=0
out="$(run_validate "$REPO9" 2>&1)" || rc=$?
assert_exit_nonzero "link-dir配下の未知artifactは失敗する" "$rc"
assert_contains "未知artifactが列挙される" "$out" "unapproved local artifact under source tree: claude/agents/.unknown-runtime"

# =========================================================================
# 10. manifest source symlinkがrepo外を指す場合は非ゼロ
# =========================================================================
REPO10="$SANDBOX/repo10"
build_fixture "$REPO10"
echo "outside" > "$SANDBOX/outside.md"
ln -s "$SANDBOX/outside.md" "$REPO10/claude/agents/outside.md"
git -C "$REPO10" add claude/agents/outside.md
out=""
rc=0
out="$(run_validate "$REPO10" 2>&1)" || rc=$?
assert_exit_nonzero "repo外を指すmanifest source symlinkは失敗する" "$rc"
assert_contains "repo外sourceの実体pathが列挙される" "$out" "tracked symlink points outside repo"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
