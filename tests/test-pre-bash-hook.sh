#!/usr/bin/env bash
# test-pre-bash-hook.sh — pre-bash-validate-hook の fail-closed / path-aware / amend-gate テスト
# (2026-07-23 H-014 / H-011)
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
  # $1: command string。正常な hook input JSON を与える
  jq -n --arg c "$1" '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":$c}}' | "$HOOK" >/dev/null 2>&1
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

# ---- 2. .env 遮断(path-aware) ----
expect_block "cat .env を block" 'cat .env'
expect_block "nested config/.env を block" 'cat config/.env'
expect_block "perl による nested .env open を block" 'perl -e "open(F, q{config/.env}); print <F>"'
expect_block "ruby による nested .env read を block" 'ruby -e "puts File.read(%q{config/.env})"'
expect_block "redirection wc -c < config/.env を block" 'wc -c < config/.env'
expect_block "command substitution の .env を block" 'echo $(cat config/.env)'
expect_allow ".env の existence check(ls)は許可" 'ls .env'
expect_allow ".env の existence check(stat)は許可" 'stat .env'
expect_allow "無関係な command は許可" 'echo hello'

# ---- 3. git commit --amend の order 非依存 gate(H-011) ----
expect_block "--amend(標準順)を block" 'git commit --amend -m x'
expect_block "--amend(option 先行: -S)を block" 'git commit -S --amend -m x'
expect_block "--amend(git -c 前置)を block" 'git -c user.name=x commit --amend'
expect_block "--amend(git -C 前置)を block" 'git -C repo commit --amend --no-edit'
expect_allow "通常の commit は許可" 'git commit -m "normal message"'
expect_allow "amend を含まない -S commit は許可" 'git commit -S -m signed'

# ---- 4. 既存の危険 pattern ----
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
