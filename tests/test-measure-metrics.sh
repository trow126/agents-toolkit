#!/usr/bin/env bash
# test-measure-metrics.sh — measure-metrics.sh の期待値テスト(再レビュー ATK-007)
# 改名前(gh:start)・改名後(gh-start)両 layout の fixture に対して、
# tier alias / full pin / 無条件委譲 / learnings 常時ロードの計測値が定義どおりであることを確認する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEASURE="$REPO_ROOT/scripts/measure-metrics.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0
ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

assert_metric() {
  local desc="$1" out="$2" key="$3" expected="$4"
  local actual
  actual="$(grep "^$key:" <<< "$out" | head -1 | sed -E "s/^$key:[[:space:]]*//")"
  if [[ "$actual" == "$expected"* ]]; then
    ok "$desc ($key=$actual)"
  else
    ng "$desc (expected $key=$expected, got '$actual')"
  fi
}

# ---- before 相当 fixture(改名前 layout: gh:start、無条件委譲あり、pin 1 + alias 2、learnings 常時) ----
B="$SANDBOX/before"
mkdir -p "$B/claude/agents" "$B/claude/rules" "$B/claude/skills/gh:start" "$B/shared/rules" "$B/codex"
printf '# CLAUDE.md fixture\n@~/.agents/rules/learnings.md\n' > "$B/claude/CLAUDE.md"
printf '# learnings fixture\n' > "$B/shared/rules/learnings.md"
printf -- '---\nname: a\nmodel: sonnet\n---\n' > "$B/claude/agents/a.md"
printf -- '---\nname: b\nmodel: opus\n---\n' > "$B/claude/agents/b.md"
printf -- '---\nname: c\nmodel: claude-foo-1\n---\n' > "$B/claude/agents/c.md"
printf -- '---\nname: d\nmodel: "claude-foo-9"\n---\n' > "$B/claude/agents/d.md"
printf -- '---\nname: gh:start\n---\n- Agent tool で委譲\n```\nAgent(\n  subagent_type: "general-purpose",\n```\n' > "$B/claude/skills/gh:start/SKILL.md"
printf '<!-- BEGIN shared:learnings -->\n<!-- END shared:learnings -->\n' > "$B/codex/AGENTS.md"

out="$("$MEASURE" --repo "$B")"
assert_metric "改名前 layout の tier alias" "$out" "tier_aliases" "2"
assert_metric "改名前 layout の full pin(plain + quoted YAML)" "$out" "full_model_pins" "2"
assert_metric "改名前 layout(gh:start)の無条件委譲を検出" "$out" "unconditional_delegation_gh_start" "1"
assert_metric "改名前 layout の learnings 常時ロード(import+embed)" "$out" "always_on_learnings_paths" "2"

# ---- after 相当 fixture(改名後 layout: gh-start、委譲テンプレなし、alias のみ) ----
A="$SANDBOX/after"
mkdir -p "$A/claude/agents" "$A/claude/skills/gh-start" "$A/shared/rules" "$A/codex/agents"
printf '# CLAUDE.md fixture\n' > "$A/claude/CLAUDE.md"
printf -- '---\nname: a\nmodel: sonnet\n---\n' > "$A/claude/agents/a.md"
printf -- '---\nname: gh-start\n---\nownerが完遂する\n' > "$A/claude/skills/gh-start/SKILL.md"
printf '# AGENTS.md fixture(learnings 埋め込みなし)\n' > "$A/codex/AGENTS.md"
printf 'name = "explorer"\nmodel = "gpt-5.6-terra"\n' > "$A/codex/agents/explorer.toml"
printf '{"model": "claude-foo-9[1m]"}\n' > "$A/claude/settings.json"

out="$("$MEASURE" --repo "$A")"
assert_metric "改名後 layout の tier alias" "$out" "tier_aliases" "1"
assert_metric "改名後 layout の full pin(settings.json の /model 書き込みは runtime-pin として非計上)" "$out" "full_model_pins" "0"
assert_metric "改名後 layout(gh-start)の無条件委譲 0" "$out" "unconditional_delegation_gh_start" "0"
assert_metric "改名後 layout の learnings 常時ロード 0" "$out" "always_on_learnings_paths" "0"
assert_metric "改名後 layout の Codex custom agent" "$out" "codex_custom_agents" "1"

# ---- scanner 失敗時は metrics 全体が fail-closed(非ゼロ・0件出力なし)になる ----
F="$SANDBOX/failclosed"
mkdir -p "$F/claude/agents"
printf -- '---\nname: bad\n"model": "claude-x-1"\n---\n' > "$F/claude/agents/bad.md"
rc=0
out="$("$MEASURE" --repo "$F" 2>&1)" || rc=$?
if [[ "$rc" -ne 0 ]]; then
  ok "非対応構文で measure-metrics が非ゼロ終了(fail-closed)"
else
  ng "scanner失敗が隠されて exit 0 になった"
fi
if ! grep -q "full_model_pins: 0" <<< "$out"; then
  ok "失敗時に pin 0 件を出力しない"
else
  ng "失敗時に pin 0 件が出力された(fail-open)"
fi

# ---- 実 repo(current checkout)への適用が主要指標で after 状態を示す ----
out="$("$MEASURE" --repo "$REPO_ROOT")"
assert_metric "実 repo: full pin 0" "$out" "full_model_pins" "0"
assert_metric "実 repo: 無条件委譲 0" "$out" "unconditional_delegation_gh_start" "0"
assert_metric "実 repo: learnings 常時ロード 0" "$out" "always_on_learnings_paths" "0"
assert_metric "実 repo: Claude effective skill は17件" "$out" "claude_skills" "17"
assert_metric "実 repo: Codex effective skill は21件" "$out" "codex_skills" "21"
assert_metric "実 repo: Codex custom agent は4件" "$out" "codex_custom_agents" "4"
assert_metric "実 repo: active skill entrypoint は150行以内" "$out" "active_skill_entrypoint_over_150_lines" "0"
assert_metric "実 repo: active skill entrypoint は8192 bytes以内" "$out" "active_skill_entrypoint_over_8192_bytes" "0"
assert_metric "実 repo: shared rule always-onはcoreのみ" "$out" "shared_rules_always_on_bytes" "1407"
assert_metric "実 repo: 要素別 inventory 行数" "$out" "inventory_audited_elements" "149"
assert_metric "実 repo: review/progress/retrospective active unique path" "$out" "review_progress_retrospective_mechanisms" "10"
assert_metric "実 repo: built-in agent overlap 0" "$out" "custom_builtin_agent_overlaps" "0"
assert_metric "実 repo: managed policy present" "$out" "managed_policy_present" "yes"
assert_metric "実 repo: managed permission lock" "$out" "managed_permission_lock_ok" "yes"
assert_metric "実 repo: managed hooks lock" "$out" "managed_hooks_lock_ok" "yes"
assert_metric "実 repo: managed read lock" "$out" "managed_read_lock_ok" "yes"
assert_metric "実 repo: managed domain lock" "$out" "managed_domain_lock_ok" "yes"
assert_metric "実 repo: bypassPermissions が既定" "$out" "bypass_permissions_default" "yes"
assert_metric "実 repo: dangerous mode confirmation を省略" "$out" "dangerous_mode_prompt_skipped" "yes"
assert_metric "実 repo: sandbox 無効" "$out" "sandbox_enabled" "no"
assert_metric "実 repo: auto mode top-level lockout" "$out" "auto_mode_lockout_ok" "yes"
assert_metric "実 repo: managed Bash allow 0" "$out" "managed_bash_allows" "0"
assert_metric "実 repo: sandbox Bash auto-allow enabled" "$out" "sandbox_auto_allow_bash" "yes"
assert_metric "実 repo: auto memory disabled" "$out" "auto_memory_enabled" "no"
assert_metric "実 repo: SessionStart output bounded" "$out" "session_start_system_message_max_bytes" "512"
assert_metric "実 repo: PostCompact output bounded" "$out" "post_compact_system_message_max_bytes" "512"

authority="$REPO_ROOT/docs/contracts/skill-authority.tsv"
if awk -F '\t' '
  $1 == "implementation-quality" && $2 == "default" &&
  $3 == "allow" && $4 == "deny" && $5 == "deny" &&
  $6 == "deny" && $7 == "deny" && $8 == "deny" { found = 1 }
  END { exit found ? 0 : 1 }
' "$authority"; then
  ok "implementation-quality はlocal source/test writeだけを許可する"
else
  ng "implementation-quality default authority が不正"
fi

git_modes="$(awk -F '\t' '$1 == "git-operations" { print $2 }' "$authority" | sort | paste -sd ' ' -)"
if [[ "$git_modes" == "branch commit default merge push stage" ]]; then
  ok "git-operations は6つの単一modeに分離されている"
else
  ng "git-operations mode contract が不正: $git_modes"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
