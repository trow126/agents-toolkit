#!/usr/bin/env bash
# test-migration.sh — scripts/migrate-layout.sh の統合テスト
# tests/lib/fixture-old-layout.sh の build_old_layout で旧whole-directory symlink構成を
# sandbox上に再現し、fixture用manifestと実bootstrap.shのコピーを使って
# AGENTS_TOOLKIT_REPO/AGENTS_TOOLKIT_HOME/XDG_STATE_HOME をsandboxへ向けたうえで
# migrate-layout.sh --dry-run / --apply を検証する。実$HOMEには一切触れない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATE="$REPO_ROOT/scripts/migrate-layout.sh"
BOOTSTRAP="$REPO_ROOT/bootstrap.sh"

# shellcheck source=lib/fixture-old-layout.sh
source "$SCRIPT_DIR/lib/fixture-old-layout.sh"

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

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (needle not found: $needle)" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# --- fixture用 mini manifest.tsv を書き込む ---
# claude/skills, codex/skills/sample-skill を link-dir にすることで
# exception1(link-dir配下untracked残置)とexception3(skill state)の優先順位を検証する。
write_manifest() {
  local repo="$1"
  mkdir -p "$repo/install"
  cat > "$repo/install/manifest.tsv" <<'EOF'
# fixture manifest
link-file	claude/CLAUDE.md	.claude/CLAUDE.md
link-dir	claude/rules	.claude/rules
link-dir	claude/skills	.claude/skills
link-file	codex/AGENTS.md	.codex/AGENTS.md
link-dir	codex/skills/sample-skill	.agents/skills/sample-skill
link-file	shared/rules/sample.md	.agents/rules/sample.md
EOF
}

# sandbox一式(repo + fixture manifest + 実bootstrap.shのコピー + 旧layout)を構築する
setup_sandbox() {
  local sandbox="$1"
  build_old_layout "$sandbox"
  local repo="$sandbox/agents-toolkit"
  write_manifest "$repo"
  cp "$BOOTSTRAP" "$repo/bootstrap.sh"
  chmod +x "$repo/bootstrap.sh"
  # migrate-layout.sh自体もfixture repo配下から動くようscripts/へ配置する
  # (script位置からのAGENTS_TOOLKIT_REPO自動算出はテストでは使わずenvで明示指定する)
  mkdir -p "$repo/scripts"
  cp "$MIGRATE" "$repo/scripts/migrate-layout.sh"
  chmod +x "$repo/scripts/migrate-layout.sh"
  # bootstrap は check/apply で doctor(scripts/check-runtime.sh)を強制するため実物を配置する
  cp "$REPO_ROOT/scripts/check-runtime.sh" "$repo/scripts/check-runtime.sh"
  chmod +x "$repo/scripts/check-runtime.sh"
}

# doctor の version 検査を host の claude 有無・version に依存させない(hermetic stub)。
# doctor 自体の分岐は tests/test-check-runtime.sh が網羅する
STUB_CLAUDE_BIN="$(mktemp -d)/stub-claude-bin"
trap 'rm -rf "$(dirname "$STUB_CLAUDE_BIN")"' EXIT
mkdir -p "$STUB_CLAUDE_BIN"
printf '#!/usr/bin/env bash\necho "2.1.218 (Claude Code)"\n' > "$STUB_CLAUDE_BIN/claude"
chmod +x "$STUB_CLAUDE_BIN/claude"

run_migrate() {
  local sandbox="$1"
  shift
  # 本テストは fixture の XDG を明示指定する(= doctor の custom XDG 検査対象)。
  # custom XDG を受容した machine を模擬するため acceptance env を与える(H-013)
  PATH="$STUB_CLAUDE_BIN:$PATH" \
  AGENTS_TOOLKIT_REPO="$sandbox/agents-toolkit" \
  AGENTS_TOOLKIT_HOME="$sandbox/home" \
  XDG_STATE_HOME="$sandbox/state" \
  XDG_CONFIG_HOME="$sandbox/config" \
  AGENTS_TOOLKIT_ACCEPT_CUSTOM_XDG=1 \
  AGENTS_TOOLKIT_MIGRATE_FORCE=1 \
  "$sandbox/agents-toolkit/scripts/migrate-layout.sh" "$@"
}

snapshot() {
  find "$1" 2>/dev/null | sort
}

# ============================================================
# 1. --dry-run: 主要entryの移動計画が出力され、filesystemが無変更
# ============================================================
test_dry_run_no_op() {
  local sandbox out before after rc=0
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"

  before="$(snapshot "$sandbox")"
  out="$(run_migrate "$sandbox" --dry-run)" || rc=$?
  after="$(snapshot "$sandbox")"

  assert_eq "dry-run は exit 0" "0" "$rc"
  assert_eq "dry-run はfilesystemを変更しない" "$before" "$after"
  assert_contains "dry-run出力に claude/.credentials.json の移動計画が含まれる" "$out" "claude/.credentials.json"
  assert_contains "dry-run出力に claude/projects の移動計画が含まれる" "$out" "claude/projects"
  assert_contains "dry-run出力に shared/skills/agmsg/db のXDG移動計画が含まれる" "$out" "shared/skills/agmsg/db"
  assert_contains "dry-run出力に __pycache__ 情報が含まれる" "$out" "__pycache__"
  assert_contains "dry-run出力に symlink削除計画が含まれる" "$out" "rm $sandbox/home/.claude"

  rm -rf "$sandbox"
}

# ============================================================
# 2. --apply: 主要シナリオ(a)-(f)
# ============================================================
test_apply_success() {
  local sandbox repo home state rc=0
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"
  repo="$sandbox/agents-toolkit"
  home="$sandbox/home"
  state="$sandbox/state"

  run_migrate "$sandbox" --apply >"$sandbox/apply.log" 2>&1 || rc=$?
  assert_eq "apply は exit 0" "0" "$rc"

  # (a) credentials/sessions/sqliteが実directory側へ移動し内容保持
  assert_true "(a) \$HOME/.claude/.credentials.json が存在する" test -f "$home/.claude/.credentials.json"
  assert_eq "(a) credentials の内容保持" "FAKE" "$(cat "$home/.claude/.credentials.json" 2>/dev/null)"
  assert_true "(a) \$HOME/.claude/projects/p1/x.jsonl が存在する" test -f "$home/.claude/projects/p1/x.jsonl"
  assert_true "(a) \$HOME/.codex/state.sqlite が存在する" test -f "$home/.codex/state.sqlite"
  assert_false "(a) repo側 claude/.credentials.json は消えている" test -e "$repo/claude/.credentials.json"

  # (b) agmsg dbがXDG側へ
  assert_true "(b) \$XDG_STATE/agmsg/db/messages.db が存在する" test -f "$state/agmsg/db/messages.db"
  assert_false "(b) repo側 shared/skills/agmsg/db は消えている" test -e "$repo/shared/skills/agmsg/db"

  # skill state exception(exception3): link-dir配下でもXDGへ移動する
  assert_true "(exception3) config-audit/audit-history.jsonl がXDG agents-toolkit側へ移動" \
    test -f "$state/agents-toolkit/config-audit/audit-history.jsonl"
  assert_false "(exception3) repo側の audit-history.jsonl は消えている" \
    test -e "$repo/claude/skills/config-audit/audit-history.jsonl"

  # private routingはClaudeが実際に参照する外部configへ移動する
  assert_true "(private routing) CLAUDE.local.md がXDG configへ移動" \
    test -f "$sandbox/config/agents-toolkit/private-routing.md"
  assert_true "(private overlay) config.toml が実directoryへ移動" test -f "$home/.codex/config.toml"

  # (c) tracked sourceはrepoに残る
  assert_true "(c) claude/CLAUDE.md はrepoに残る" test -f "$repo/claude/CLAUDE.md"
  assert_true "(c) codex/skills/sample-skill/SKILL.md はrepoに残る" test -f "$repo/codex/skills/sample-skill/SKILL.md"
  assert_true "(c) claude/skills/sample-skill/SKILL.md はrepoに残る" test -f "$repo/claude/skills/sample-skill/SKILL.md"

  # (d) 3つの実ディレクトリ化とmanifestどおりの個別symlink
  assert_false "(d) \$HOME/.claude はもうsymlinkではない" test -L "$home/.claude"
  assert_true "(d) \$HOME/.claude は実ディレクトリ" test -d "$home/.claude"
  assert_false "(d) \$HOME/.codex はもうsymlinkではない" test -L "$home/.codex"
  assert_false "(d) \$HOME/.agents はもうsymlinkではない" test -L "$home/.agents"
  assert_true "(d) \$HOME/.claude/CLAUDE.md は個別symlink" test -L "$home/.claude/CLAUDE.md"
  assert_eq "(d) \$HOME/.claude/CLAUDE.md の解決先" "$repo/claude/CLAUDE.md" "$(readlink "$home/.claude/CLAUDE.md")"
  assert_true "(d) \$HOME/.claude/skills は個別symlink(link-dir)" test -L "$home/.claude/skills"
  assert_eq "(d) \$HOME/.claude/skills の解決先" "$repo/claude/skills" "$(readlink "$home/.claude/skills")"
  assert_true "(d) \$HOME/.agents/skills/sample-skill は個別symlink" test -L "$home/.agents/skills/sample-skill"

  # (e) allowlist済みlocal開発artifactだけが残置される
  assert_true "(e) .pytest_cache は許可済みlocal artifactとして残置" \
    test -f "$repo/codex/skills/sample-skill/.pytest_cache/CACHEDIR.TAG"
  assert_contains "(e) apply出力に許可済みartifactが含まれる" \
    "$(cat "$sandbox/apply.log")" "codex/skills/sample-skill/.pytest_cache"

  # __pycache__ も残置(削除されない)
  assert_true "__pycache__ は削除されず残置される" \
    test -f "$repo/codex/skills/sample-skill/__pycache__/x.pyc"

  # (f) repo側にruntimeが残っていない(既知のruntime top-levelが消えている)
  assert_false "(f) repo側 claude/projects は消えている" test -e "$repo/claude/projects"
  assert_false "(f) repo側 codex/auth.json は消えている" test -e "$repo/codex/auth.json"
  assert_false "(f) repo側 claude/CLAUDE.local.md は消えている" test -e "$repo/claude/CLAUDE.local.md"
  assert_true "(f) 旧nested configはXDG migration archiveへ退避" \
    test -f "$state/agents-toolkit/migration-archive/claude/.agents/legacy.md"
  assert_false "(f) repo側の旧nested configは消えている" test -e "$repo/claude/.agents"

  # bootstrap.sh --check がPASSする(個別symlinkが検証を通る)
  local check_rc=0
  PATH="$STUB_CLAUDE_BIN:$PATH" HOME="$home" AGENTS_TOOLKIT_REPO="$repo" "$repo/bootstrap.sh" --check >"$sandbox/check.log" 2>&1 || check_rc=$?
  assert_eq "bootstrap.sh --check はPASS" "0" "$check_rc"

  rm -rf "$sandbox"
}

# ============================================================
# 3. 冪等性/再実行: 移行済み状態で再実行するとpreflight(symlinkでない)で安全に中断
# ============================================================
test_idempotent_rerun_blocked() {
  local sandbox home rc=0
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"
  home="$sandbox/home"

  run_migrate "$sandbox" --apply >/dev/null 2>&1

  local before after
  before="$(snapshot "$home")"
  run_migrate "$sandbox" --dry-run >"$sandbox/rerun.log" 2>&1 || rc=$?
  after="$(snapshot "$home")"

  assert_eq "移行済み状態での再実行は非ゼロ終了" "1" "$rc"
  assert_contains "再実行はsymlink前提のpreflightで止まる" "$(cat "$sandbox/rerun.log")" "preflight(symlink)"
  assert_eq "再実行は\$HOMEを変更しない" "$before" "$after"

  rm -rf "$sandbox"
}

# ============================================================
# 4. bootstrap失敗時rollback: データ移動後のbootstrap失敗もtransaction失敗として
#    旧構成(whole-directory symlink・全runtimeが元位置)へ復元されることを確認する。
# ============================================================
test_failure_rollback() {
  local sandbox repo home state rc=0
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"
  repo="$sandbox/agents-toolkit"
  home="$sandbox/home"
  state="$sandbox/state"

  # migration preflight後、データ移動後に呼ばれるbootstrapだけを失敗させる。
  printf '#!/usr/bin/env bash\necho "fixture bootstrap failure" >&2\nexit 42\n' > "$repo/bootstrap.sh"
  chmod +x "$repo/bootstrap.sh"

  run_migrate "$sandbox" --apply >"$sandbox/fail.log" 2>&1 || rc=$?

  assert_eq "bootstrap失敗時の apply は非ゼロ終了" "1" "$rc"
  assert_contains "失敗ログにrollback実行の記録がある" "$(cat "$sandbox/fail.log")" "旧構成"

  # 旧構成(whole-directory symlink)へ復元されている
  assert_true "\$HOME/.claude が symlink に復元される" test -L "$home/.claude"
  assert_eq "\$HOME/.claude の解決先が復元される" "$repo/claude" "$(readlink -f "$home/.claude")"
  assert_true "\$HOME/.codex が symlink に復元される" test -L "$home/.codex"
  assert_true "\$HOME/.agents が symlink に復元される" test -L "$home/.agents"

  # runtimeが元位置(repo側)へ復元されている(実ディレクトリ側へ一度移動が成功したものも含む)
  assert_true "claude/.credentials.json がrepo側に復元される" test -f "$repo/claude/.credentials.json"
  assert_eq "復元されたcredentialsの内容保持" "FAKE" "$(cat "$repo/claude/.credentials.json" 2>/dev/null)"
  assert_true "claude/projects/p1/x.jsonl がrepo側に復元される" test -f "$repo/claude/projects/p1/x.jsonl"
  assert_true "shared/skills/agmsg/db/messages.db がrepo側に復元される" \
    test -f "$repo/shared/skills/agmsg/db/messages.db"
  assert_true "旧nested configもrepo側に復元される" test -f "$repo/claude/.agents/legacy.md"
  assert_true "claude/CLAUDE.md はtracked sourceとしてrepoに残ったまま" test -f "$repo/claude/CLAUDE.md"

  rm -rf "$sandbox"
}

# ============================================================
# 5. commit後のrollback scriptは無効化され、新規runtimeを削除しないこと
# ============================================================
test_manual_rollback_script() {
  local sandbox repo home rc=0
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"
  repo="$sandbox/agents-toolkit"
  home="$sandbox/home"

  run_migrate "$sandbox" --apply >"$sandbox/apply2.log" 2>&1

  local reverse_script
  reverse_script="$(find "$home" -maxdepth 1 -name '.agents-toolkit-migration-*' -type d | head -n1)/rollback.sh"
  assert_true "逆操作scriptが生成されている" test -f "$reverse_script"

  echo "NEW SESSION" > "$home/.claude/new-session.jsonl"
  "$reverse_script" >"$sandbox/manual-rollback.log" 2>&1 || rc=$?
  assert_eq "commit後のrollback scriptは非ゼロ終了" "1" "$rc"
  assert_contains "commit後のrollback拒否理由が表示される" \
    "$(cat "$sandbox/manual-rollback.log")" "commit済み"
  assert_true "rollback拒否後も新規runtimeが保持される" test -f "$home/.claude/new-session.jsonl"
  assert_false "rollback拒否後もwhole-directory symlinkへ戻らない" test -L "$home/.claude"

  rm -rf "$sandbox"
}

# ============================================================
# 6. destination collisionは移動開始前に停止し、既存stateを変更しない
# ============================================================
test_destination_collision_preflight() {
  local sandbox repo home rc=0 before after
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"
  repo="$sandbox/agents-toolkit"
  home="$sandbox/home"
  mkdir -p "$sandbox/state/agmsg/db"
  echo "SENTINEL" > "$sandbox/state/agmsg/db/existing"
  before="$(snapshot "$repo"; snapshot "$home"; snapshot "$sandbox/state")"

  run_migrate "$sandbox" --apply >"$sandbox/collision.log" 2>&1 || rc=$?
  after="$(snapshot "$repo"; snapshot "$home"; snapshot "$sandbox/state")"

  assert_eq "destination collisionは非ゼロ終了" "1" "$rc"
  assert_contains "collision対象が表示される" "$(cat "$sandbox/collision.log")" "移行先が既に存在"
  assert_eq "collision preflightはfilesystemを変更しない" "$before" "$after"
  assert_eq "既存stateの内容を保持" "SENTINEL" "$(cat "$sandbox/state/agmsg/db/existing")"
  assert_true "旧whole-directory symlinkを保持" test -L "$home/.claude"

  rm -rf "$sandbox"
}

# ============================================================
# 7. link-dir配下の未知artifactは黙って残さずpreflightで停止する
# ============================================================
test_unknown_linkdir_artifact_blocked() {
  local sandbox repo rc=0
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"
  repo="$sandbox/agents-toolkit"
  echo "UNKNOWN" > "$repo/codex/skills/sample-skill/.unknown-runtime"

  run_migrate "$sandbox" --dry-run >"$sandbox/unknown.log" 2>&1 || rc=$?
  assert_eq "未知のlink-dir artifactは非ゼロ終了" "1" "$rc"
  assert_contains "未知artifactが未分類として列挙される" \
    "$(cat "$sandbox/unknown.log")" "codex/skills/sample-skill/.unknown-runtime"
  assert_true "停止後も未知artifactを保持" test -f "$repo/codex/skills/sample-skill/.unknown-runtime"

  rm -rf "$sandbox"
}

# ============================================================
# 8. migration preflightもmanifestの余剰列を移動前に拒否する
# ============================================================
test_invalid_manifest_blocked() {
  local sandbox repo home rc=0 before after
  sandbox="$(mktemp -d)"
  setup_sandbox "$sandbox"
  repo="$sandbox/agents-toolkit"
  home="$sandbox/home"
  printf 'link-file\tclaude/CLAUDE.md\t.claude/duplicate.md\textra\n' >> "$repo/install/manifest.tsv"
  before="$(snapshot "$repo"; snapshot "$home")"

  run_migrate "$sandbox" --apply >"$sandbox/invalid-manifest.log" 2>&1 || rc=$?
  after="$(snapshot "$repo"; snapshot "$home")"

  assert_eq "4列manifestは移動前に非ゼロ終了" "1" "$rc"
  assert_contains "manifestの実列数を表示" "$(cat "$sandbox/invalid-manifest.log")" "実際: 4列"
  assert_eq "manifest preflight失敗はrepo/HOMEを変更しない" "$before" "$after"
  assert_true "manifest preflight失敗後も旧symlinkを保持" test -L "$home/.claude"

  rm -rf "$sandbox"
}

test_dry_run_no_op
test_apply_success
test_idempotent_rerun_blocked
test_failure_rollback
test_manual_rollback_script
test_destination_collision_preflight
test_unknown_linkdir_artifact_blocked
test_invalid_manifest_blocked

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
