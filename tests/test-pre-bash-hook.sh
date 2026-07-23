#!/usr/bin/env bash
# test-pre-bash-hook.sh — pre-bash-validate-hook の fail-closed / path-aware / amend-gate テスト
# (2026-07-23 H-014 / H-011, 2026-07-24 quote 正規化・共起判定へ改訂)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/claude/hooks/pre-bash-validate-hook.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0
ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

run_hook_cmd() {
  # $1: command string, $2(optional): project cwd
  local command="$1" cwd="${2:-}"
  if [[ -n "$cwd" ]]; then
    jq -n --arg c "$command" --arg cwd "$cwd" \
      '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":$cwd,"tool_input":{"command":$c}}' \
      | "$HOOK" >/dev/null 2>&1
  else
    jq -n --arg c "$command" \
      '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":$c}}' \
      | "$HOOK" >/dev/null 2>&1
  fi
}

expect_block() {
  local desc="$1" cmd="$2" rc=0
  run_hook_cmd "$cmd" || rc=$?
  if [[ "$rc" -eq 2 ]]; then ok "$desc"; else ng "$desc (expected exit 2, got $rc)"; fi
}

expect_allow() {
  local desc="$1" cmd="$2" rc=0
  run_hook_cmd "$cmd" || rc=$?
  if [[ "$rc" -eq 0 ]]; then ok "$desc"; else ng "$desc (expected exit 0, got $rc)"; fi
}

expect_block_in() {
  local desc="$1" cwd="$2" cmd="$3" rc=0
  run_hook_cmd "$cmd" "$cwd" || rc=$?
  if [[ "$rc" -eq 2 ]]; then ok "$desc"; else ng "$desc (expected exit 2, got $rc)"; fi
}

expect_allow_in() {
  local desc="$1" cwd="$2" cmd="$3" rc=0
  run_hook_cmd "$cmd" "$cwd" || rc=$?
  if [[ "$rc" -eq 0 ]]; then ok "$desc"; else ng "$desc (expected exit 0, got $rc)"; fi
}

# ---- 1. fail-closed: malformed input / schema 欠落 / jq 欠落 ----
rc=0
printf '{' | "$HOOK" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then ok "malformed JSON は exit 2(block)"; else ng "malformed JSON が exit $rc"; fi

rc=0
printf '{"tool_name":"Bash","tool_input":{}}' | "$HOOK" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then ok "tool_input.command 欠落は exit 2(block)"; else ng "command 欠落が exit $rc"; fi

rc=0
printf '{"tool_input":{"command":""}}' | "$HOOK" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then ok "空 command は exit 2(block)"; else ng "空 command が exit $rc"; fi

# jq 欠落環境の再現: PATH を最小化して bash/coreutils だけ見せる
MINBIN="$SANDBOX/minbin"
mkdir -p "$MINBIN"
for b in bash cat grep echo; do
  ln -s "$(command -v $b)" "$MINBIN/$b"
done
rc=0
printf '{"tool_input":{"command":"cat .env"}}' | env PATH="$MINBIN" "$HOOK" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then ok "jq 欠落は exit 2(block。fail-open しない)"; else ng "jq 欠落が exit $rc"; fi

# ---- 2. project/local settings gate(C-02) ----
PROJECT_ROOT="$SANDBOX/project"
mkdir -p "$PROJECT_ROOT/.git" "$PROJECT_ROOT/.claude"
cat > "$PROJECT_ROOT/.claude/settings.json" <<'JSON'
{"model":"sonnet","env":{"PROJECT_FLAVOR":"test"}}
JSON
expect_allow_in "benign project settings do not block Bash hook" "$PROJECT_ROOT" 'echo hello'
cat > "$PROJECT_ROOT/.claude/settings.json" <<'JSON'
{"sandbox":{"enabled":false}}
JSON
expect_block_in "project sandbox override blocks PreToolUse" "$PROJECT_ROOT" 'echo hello'
cat > "$PROJECT_ROOT/.claude/settings.json" <<'JSON'
{"sandbox":{"excludedCommands":["cat *"]}}
JSON
expect_block_in "project excludedCommands blocks PreToolUse" "$PROJECT_ROOT" 'echo hello'
cat > "$PROJECT_ROOT/.claude/settings.json" <<'JSON'
{"sandbox":{"filesystem":{"allowRead":["~/.claude"]}}}
JSON
expect_block_in "project allowRead expansion blocks PreToolUse" "$PROJECT_ROOT" 'echo hello'
cat > "$PROJECT_ROOT/.claude/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(cat *)"]}}
JSON
expect_block_in "project permission rule blocks PreToolUse" "$PROJECT_ROOT" 'echo hello'
rm -rf "$PROJECT_ROOT"

# ---- 3. .env 遮断(path-aware) ----
expect_block "cat .env を block" 'cat .env'
expect_block "nested config/.env を block" 'cat config/.env'
expect_block "perl による nested .env open を block" 'perl -e "open(F, q{config/.env}); print <F>"'
expect_block "ruby による nested .env read を block" 'ruby -e "puts File.read(%q{config/.env})"'
expect_block "redirection wc -c < config/.env を block" 'wc -c < config/.env'
expect_block "command substitution の .env を block" 'echo $(cat config/.env)'
expect_block "quote 分割 .env(cat config/.e\"\"nv)を block" 'cat config/.e""nv'
expect_block "quote 分割 .env(single quote)を block" "cat config/.'e'nv"
expect_allow ".env の existence check(ls)は許可" 'ls .env'
expect_allow ".env の existence check(stat)は許可" 'stat .env'
expect_allow "無関係な command は許可" 'echo hello'

# hook 層の対象外(literal が現れない runtime 構築)を明示する scope テスト。
# これらは OS-level 境界(Read(//**/.env) deny → sandbox filesystem 統合)が実アクセスを
# 遮断する担当であり、hook は block しない(= exit 0 が本 hook の仕様)
expect_allow "scope: base64 復号 path は hook 層の対象外(OS 境界の担当)" 'cat "$(printf Y29uZmlnLy5lbnY= | base64 -d)"'
expect_allow "scope: 変数連結 path は hook 層の対象外(OS 境界の担当)" 'a=config/.e; b=nv; cat "$a$b"'

# ---- 4. git commit --amend gate(H-011: quote 正規化 + git/--amend 共起判定) ----
expect_block "--amend(標準順)を block" 'git commit --amend -m x'
expect_block "--amend(option 先行: -S)を block" 'git commit -S --amend -m x'
expect_block "--amend(git -c 前置)を block" 'git -c user.name=x commit --amend'
expect_block "--amend(git -C 前置)を block" 'git -C repo commit --amend --no-edit'
# 再レビュー(final_4)の回避 7 形: すべて literal を含むか quote 正規化で復元されるため block
expect_block "回避形: command substitution 引数を block" 'git commit "$(printf -- --amend)" -m x'
expect_block "回避形: quote 分割 --am\"\"end を block" 'git commit --am""end -m x'
expect_block "回避形: 変数代入 x=--amend を block" 'x=--amend; git commit "$x" -m x'
expect_block "回避形: 変数 + substitution を block" 'x=$(printf -- --amend); git commit "$x" -m x'
expect_block "回避形: git alias(-c alias.ci)を block" 'git -c alias.ci=commit ci --amend -m x'
expect_block "回避形: shell alias(!git commit --amend)を block" 'git -c alias.x="!git commit --amend" x'
expect_block "回避形: nested shell(sh -c)を block" 'sh -c "git commit --amend -m x"'
expect_allow "通常の commit は許可" 'git commit -m "normal message"'
expect_allow "amend を含まない -S commit は許可" 'git commit -S -m signed'
expect_allow "git 以外の --amend 文字列は許可" 'echo --amend'

# ---- 5. 既存の危険 pattern ----
expect_block "block device への書き込みを block" 'echo x > /dev/sda'
expect_block "mkfs を block" 'mkfs.ext4 /dev/sda1'

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
