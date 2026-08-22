#!/usr/bin/env bash
# test-pre-bash-hook.sh — pre-bash-validate-hook の fail-closed / lifecycle / safety-gate テスト
# (2026-07-23 H-014 / H-011, 2026-07-24 quote 正規化、2026-07-31 Codex lifecycle 一本化)
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
  # $1: command string, $2(optional): project cwd, $3(optional): agent_type,
  # $4(optional): Bash tool run_in_background JSON boolean
  local command="$1" cwd="${2:-}" agent_type="${3:-}"
  local run_in_background="${4:-null}"
  jq -n \
    --arg c "$command" \
    --arg cwd "$cwd" \
    --arg agent_type "$agent_type" \
    --argjson run_in_background "$run_in_background" '
    {
      "hook_event_name": "PreToolUse",
      "tool_name": "Bash",
      "tool_input": {"command": $c}
    }
    + (if $cwd == "" then {} else {"cwd": $cwd} end)
    + (if $agent_type == "" then {} else {"agent_type": $agent_type} end)
    + (
      if $run_in_background == null
      then {}
      else {"tool_input": {"command": $c, "run_in_background": $run_in_background}}
      end
    )
  ' | "$HOOK" >/dev/null 2>&1
}

run_agent_hook() {
  local subagent_type="$1"
  jq -n --arg subagent_type "$subagent_type" '{
    "hook_event_name": "PreToolUse",
    "tool_name": "Agent",
    "tool_input": {
      "description": "delegate task",
      "subagent_type": $subagent_type,
      "run_in_background": true,
      "prompt": "implement the fix"
    }
  }' | "$HOOK" >/dev/null 2>&1
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

expect_block_agent() {
  local desc="$1" agent_type="$2" cmd="$3" rc=0
  run_hook_cmd "$cmd" "" "$agent_type" || rc=$?
  if [[ "$rc" -eq 2 ]]; then ok "$desc"; else ng "$desc (expected exit 2, got $rc)"; fi
}

expect_allow_agent() {
  local desc="$1" agent_type="$2" cmd="$3" rc=0
  run_hook_cmd "$cmd" "" "$agent_type" || rc=$?
  if [[ "$rc" -eq 0 ]]; then ok "$desc"; else ng "$desc (expected exit 0, got $rc)"; fi
}

expect_block_agent_tool_background() {
  local desc="$1" agent_type="$2" cmd="$3" rc=0
  run_hook_cmd "$cmd" "" "$agent_type" true || rc=$?
  if [[ "$rc" -eq 2 ]]; then ok "$desc"; else ng "$desc (expected exit 2, got $rc)"; fi
}

expect_allow_agent_tool_background() {
  local desc="$1" agent_type="$2" cmd="$3" rc=0
  run_hook_cmd "$cmd" "" "$agent_type" true || rc=$?
  if [[ "$rc" -eq 0 ]]; then ok "$desc"; else ng "$desc (expected exit 0, got $rc)"; fi
}

expect_allow_agent_tool_foreground() {
  local desc="$1" agent_type="$2" cmd="$3" rc=0
  run_hook_cmd "$cmd" "" "$agent_type" false || rc=$?
  if [[ "$rc" -eq 0 ]]; then ok "$desc"; else ng "$desc (expected exit 0, got $rc)"; fi
}

expect_block_agent_tool_foreground() {
  local desc="$1" agent_type="$2" cmd="$3" rc=0
  run_hook_cmd "$cmd" "" "$agent_type" false || rc=$?
  if [[ "$rc" -eq 2 ]]; then ok "$desc"; else ng "$desc (expected exit 2, got $rc)"; fi
}

# ---- 1. fail-closed: malformed input / schema 欠落 / jq 欠落 ----
rc=0
printf '{' | "$HOOK" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then ok "malformed JSON は exit 2(block)"; else ng "malformed JSON が exit $rc"; fi

rc=0
printf '{"tool_name":"Bash","tool_input":{}}' | "$HOOK" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then ok "tool_input.command 欠落は exit 2(block)"; else ng "command 欠落が exit $rc"; fi

rc=0
printf '{"tool_name":"Bash","tool_input":{"command":""}}' | "$HOOK" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then ok "空 command は exit 2(block)"; else ng "空 command が exit $rc"; fi

rc=0
printf '{"tool_name":"Bash","agent_type":null,"tool_input":{"command":"echo hello"}}' | "$HOOK" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then ok "agent_type の不正な型は exit 2(block)"; else ng "不正 agent_type が exit $rc"; fi

rc=0
printf '{"tool_name":"Bash","tool_input":{"command":"echo hello","run_in_background":"true"}}' \
  | "$HOOK" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "run_in_background の不正な型は exit 2(block)"
else
  ng "不正 run_in_background が exit $rc"
fi

# jq 欠落環境の再現: PATH を最小化して bash/coreutils だけ見せる
MINBIN="$SANDBOX/minbin"
mkdir -p "$MINBIN"
for b in bash cat grep echo; do
  ln -s "$(command -v $b)" "$MINBIN/$b"
done
rc=0
printf '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' \
  | env PATH="$MINBIN" "$HOOK" >/dev/null 2>&1 || rc=$?
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

# ---- 3. Codex completion lifecycle は main session が所有 ----
rc=0
run_agent_hook "codex:codex-rescue" || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "codex-rescue Agent は background指定でも block"
else
  ng "codex-rescue Agent が exit $rc"
fi

rc=0
run_agent_hook "general-purpose" || rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "通常のgeneral-purpose Agentは許可"
else
  ng "general-purpose Agent が exit $rc"
fi

rc=0
agent_reason_output=$(
  jq -n '{
    "hook_event_name": "PreToolUse",
    "tool_name": "Agent",
    "tool_input": {
      "subagent_type": "codex:codex-rescue",
      "prompt": "implement the fix"
    }
  }' | "$HOOK" 2>&1
) || rc=$?
if [[ "$rc" -eq 2 && "$agent_reason_output" == *"main session"* ]]; then
  ok "Agent block理由が main session ownership を指示する"
else
  ng "Agent block理由に main session ownership 指示がない (exit $rc): $agent_reason_output"
fi

CODEX_AGENT='codex:codex-rescue'
COMPANION='/home/test/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs'
expect_block_agent "codex-rescue の task --background を block" "$CODEX_AGENT" \
  "node \"$COMPANION\" task --background --write \"implement the fix\""
expect_block_agent "flag 順序が異なる task --background を block" "$CODEX_AGENT" \
  "node \"$COMPANION\" task --write --background \"implement the fix\""
expect_block_agent "quote 分割 --back\"\"ground を block" "$CODEX_AGENT" \
  "node \"$COMPANION\" task --back\"\"ground \"implement the fix\""
expect_block_agent "multiline command の task --background を block" "$CODEX_AGENT" \
  $'TASK_TEXT="implement the fix"\nnode "'"$COMPANION"'" task --background "$TASK_TEXT"'
expect_block_agent_tool_background \
  "codex-rescue の Bash run_in_background=true を block" "$CODEX_AGENT" \
  "node \"$COMPANION\" task --write \"implement the fix\""
expect_block_agent "codex-rescue の foreground task も block" "$CODEX_AGENT" \
  "node \"$COMPANION\" task --write \"implement the fix\""
expect_block_agent_tool_foreground \
  "codex-rescue の明示foreground task も block" "$CODEX_AGENT" \
  "node \"$COMPANION\" task --write \"implement the fix\""
expect_allow_agent "codex-rescue の status は許可" "$CODEX_AGENT" \
  "node \"$COMPANION\" status task-123"
expect_allow_agent "codex-rescue の result は許可" "$CODEX_AGENT" \
  "node \"$COMPANION\" result task-123"
expect_allow_agent "別 agent の companion background は本規則の対象外" "general-purpose" \
  "node \"$COMPANION\" task --background \"implement the fix\""
expect_allow_agent_tool_background \
  "別 agent の Bash run_in_background=true は本規則の対象外" "general-purpose" \
  "node \"$COMPANION\" task --write \"implement the fix\""
expect_allow_agent_tool_background \
  "main session相当の companion Bash background は許可" "" \
  "node \"$COMPANION\" task --write \"implement the fix\""

rc=0
reason_output=$(
  jq -n --arg c "node \"$COMPANION\" task --write \"implement the fix\"" \
    --arg agent_type "$CODEX_AGENT" \
    '{"hook_event_name":"PreToolUse","tool_name":"Bash","agent_type":$agent_type,"tool_input":{"command":$c}}' \
    | "$HOOK" 2>&1
) || rc=$?
if [[ "$rc" -eq 2 && "$reason_output" == *"main sessionから"* ]]; then
  ok "block 理由が main session ownership を指示する"
else
  ng "block 理由に main session ownership 指示がない (exit $rc): $reason_output"
fi

# ---- 4. .env 遮断(path-aware) ----
expect_block "cat .env を block" 'cat .env'
expect_block "nested config/.env を block" 'cat config/.env'
expect_block "perl による nested .env open を block" 'perl -e "open(F, q{config/.env}); print <F>"'
expect_block "ruby による nested .env read を block" 'ruby -e "puts File.read(%q{config/.env})"'
expect_block "redirection wc -c < config/.env を block" 'wc -c < config/.env'
expect_block "command substitution の .env を block" 'echo $(cat config/.env)'
expect_block "quote 分割 .env(cat config/.e\"\"nv)を block" 'cat config/.e""nv'
expect_block "quote 分割 .env(single quote)を block" "cat config/.'e'nv"
expect_block "source .env を block" 'source .env'
expect_block "dot builtin(. .env)を block" '. .env'
expect_block "dot builtin(区切り後の nested .env)を block" 'true; . config/.env'
expect_allow ".env の existence check(ls)は許可" 'ls .env'
expect_allow ".env の existence check(stat)は許可" 'stat .env'
expect_allow "無関係な command は許可" 'echo hello'
# 偽陽性回帰(2026-08-22): readers list の `\.` が word.word の任意 dot に一致し、
# 実 reader なしのコマンドを block していた。
expect_allow "偽陽性回帰: jq の .env accessor + dotted filename は許可" 'jq -r ".env | keys" settings.json'
expect_allow "偽陽性回帰: ls .env.local(existence check)は許可" 'ls .env.local'

# hook 層の対象外(literal が現れない runtime 構築)を明示する scope テスト。
# 現行 owner policy は sandbox 無効のため別の下位境界もなく、hook は
# block しない(= exit 0 が本 hook の仕様)。
expect_allow "scope: base64 復号 path は hook 層の対象外(下位境界なし)" 'cat "$(printf Y29uZmlnLy5lbnY= | base64 -d)"'
expect_allow "scope: 変数連結 path は hook 層の対象外(下位境界なし)" 'a=config/.e; b=nv; cat "$a$b"'

# ---- 5. git commit --amend gate(H-011: quote 正規化 + git/--amend 共起判定) ----
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

# ---- 6. 既存の危険 pattern ----
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
