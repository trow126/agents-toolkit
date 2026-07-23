#!/usr/bin/env bash
# measure-metrics.sh — 近代化レポートの指標を再現可能に計測する(2026-07-23 レビュー ATK-007)
# 定義:
#   always-on(claude) = claude/CLAUDE.md + paths frontmatter を持たない claude/rules/*.md
#                       + CLAUDE.md が @import する shared rules の合計バイト数(wc -c)
#   always-on(codex)  = codex/AGENTS.md のバイト数
#   full-model-pin    = 完全モデル名("claude-<name>-<ver>")を値に持つ設定・frontmatter の件数
#   tier-alias        = agent frontmatter の model: sonnet|opus|haiku|fable|inherit の件数(pin とは区別)
#   unconditional-delegation = gh-start タスクループ内の無条件 Agent 委譲テンプレート件数
# 対象: git 追跡ファイルのみ。docs/・tests/ は集計対象外。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

section() { echo "== $1 =="; }

section "always-on context (bytes, wc -c)"
claude_md=$(wc -c < claude/CLAUDE.md)
always_rules=0
for f in claude/rules/*.md; do
  if ! head -1 "$f" | grep -q '^---$' || ! awk '/^---$/{c++} c==1' "$f" | grep -q '^paths:'; then
    always_rules=$((always_rules + $(wc -c < "$f")))
  fi
done
imports=0
import_count=0
while IFS= read -r name; do
  f="shared/rules/$name.md"
  [[ -f "$f" ]] && imports=$((imports + $(wc -c < "$f"))) && import_count=$((import_count + 1))
done < <(grep -oE '@~/\.agents/rules/[A-Za-z0-9_-]+\.md' claude/CLAUDE.md | sed -E 's#@~/\.agents/rules/##; s/\.md$//')
agents_md=$(wc -c < codex/AGENTS.md)
echo "claude/CLAUDE.md: $claude_md"
echo "claude always-on rules (no paths frontmatter): $always_rules"
echo "shared rules imported by CLAUDE.md ($import_count files): $imports"
echo "claude always-on total: $((claude_md + always_rules + imports))"
echo "codex/AGENTS.md: $agents_md"
echo "combined always-on total: $((claude_md + always_rules + imports + agents_md))"

section "component counts"
echo "custom agents: $(git ls-files 'claude/agents/*.md' | wc -l)"
echo "claude skills (active): $(git ls-files 'claude/skills/*/SKILL.md' | wc -l)"
echo "codex skills (active): $(git ls-files 'codex/skills/*/SKILL.md' | wc -l)"
echo "hook scripts: $(git ls-files 'claude/hooks/*.sh' | wc -l)"
echo "hook registrations: $(jq '[.hooks[][] | .hooks[]] | length' claude/settings.json)"
echo "shared rules: $(git ls-files 'shared/rules/*.md' | wc -l)"
echo "claude rules: $(git ls-files 'claude/rules/*.md' | wc -l)"
echo "output styles: $(git ls-files 'claude/output-styles/*.md' | wc -l)"

section "model pinning (full pin vs tier alias — 別指標)"
pins=0
pin_hits="$(grep -HnoE '"model"[[:space:]]*:[[:space:]]*"claude-[a-z0-9.-]+"' claude/settings.json || true)"
[[ -n "$pin_hits" ]] && { echo "$pin_hits"; pins=$(echo "$pin_hits" | wc -l); }
agent_pin_hits="$(grep -HnoE '^model:[[:space:]]*claude-[a-z0-9.-]+' claude/agents/*.md || true)"
[[ -n "$agent_pin_hits" ]] && { echo "$agent_pin_hits"; pins=$((pins + $(echo "$agent_pin_hits" | wc -l))); }
echo "full model pins (settings + agents): $pins"
echo "tier aliases in agents (sonnet/opus/haiku/fable/inherit): $(grep -hoE '^model:[[:space:]]*(sonnet|opus|haiku|fable|inherit)$' claude/agents/*.md | wc -l)"
echo "settings model value: $(jq -r '.model // "unset"' claude/settings.json) / effortLevel: $(jq -r '.effortLevel // "unset"' claude/settings.json)"

section "delegation contract (gh-start)"
uncond=$(grep -c 'subagent_type: "general-purpose"' claude/skills/gh-start/SKILL.md || true)
echo "unconditional delegation templates in gh-start: $uncond"
echo "conditional delegation section present: $(grep -q '委譲の条件（例外）' claude/skills/gh-start/SKILL.md && echo yes || echo no)"

section "always-on learnings"
echo "learnings imported by CLAUDE.md: $(grep -c '@~/\.agents/rules/learnings\.md' claude/CLAUDE.md || true)"
echo "learnings inlined in AGENTS.md: $(grep -c 'BEGIN shared:learnings' codex/AGENTS.md || true)"
