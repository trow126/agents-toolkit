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
mkdir -p "$A/claude/agents" "$A/claude/skills/gh-start" "$A/shared/rules" "$A/codex"
printf '# CLAUDE.md fixture\n' > "$A/claude/CLAUDE.md"
printf -- '---\nname: a\nmodel: sonnet\n---\n' > "$A/claude/agents/a.md"
printf -- '---\nname: gh-start\n---\nownerが完遂する\n' > "$A/claude/skills/gh-start/SKILL.md"
printf '# AGENTS.md fixture(learnings 埋め込みなし)\n' > "$A/codex/AGENTS.md"

out="$("$MEASURE" --repo "$A")"
assert_metric "改名後 layout の tier alias" "$out" "tier_aliases" "1"
assert_metric "改名後 layout の full pin" "$out" "full_model_pins" "0"
assert_metric "改名後 layout(gh-start)の無条件委譲 0" "$out" "unconditional_delegation_gh_start" "0"
assert_metric "改名後 layout の learnings 常時ロード 0" "$out" "always_on_learnings_paths" "0"

# ---- 実 repo(current checkout)への適用が主要指標で after 状態を示す ----
out="$("$MEASURE" --repo "$REPO_ROOT")"
assert_metric "実 repo: full pin 0" "$out" "full_model_pins" "0"
assert_metric "実 repo: 無条件委譲 0" "$out" "unconditional_delegation_gh_start" "0"
assert_metric "実 repo: learnings 常時ロード 0" "$out" "always_on_learnings_paths" "0"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
