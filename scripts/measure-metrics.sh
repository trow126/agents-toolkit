#!/usr/bin/env bash
# measure-metrics.sh — 近代化レポート指標の再現可能な計測(再レビュー ATK-007 対応版)
#
# 使い方:
#   measure-metrics.sh                              現在の checkout を計測する
#   measure-metrics.sh --repo <dir>                 任意の tree を計測する(.git 不要。fixture/展開済みarchive可)
#   measure-metrics.sh --before-ref <R1> [--after-ref <R2>]
#                                                   2つの git ref を展開して before -> after を並記する(既定 after=HEAD)
#
# 定義:
#   always-on(claude) = claude/CLAUDE.md + paths frontmatter を持たない claude/rules/*.md
#                       + CLAUDE.md が @import する shared/rules の合計バイト数(wc -c)
#   always-on(codex)  = codex/AGENTS.md のバイト数
#   full-model-pin    = 完全モデル名("claude-...")を値に持つ settings/agent frontmatter/TOML の件数
#   tier-alias        = agent frontmatter の model: sonnet|opus|haiku|fable|inherit の件数(pin と別指標)
#   unconditional-delegation = gh:start / gh-start(改名前後どちらの layout も対象)のタスクループに
#                       固定された `subagent_type: "general-purpose"` テンプレート件数
#   duplicated-principles(greppable) = shared/rules/*.md 内で同一原則シグネチャが複数ファイルに現れる組数。
#       sig1 テスト網羅: '空・単一・境界値|空、単一、境界値' / sig2 テスト無効化回避: 'テストをスキップ・無効化|テストの無効化'
#       sig3 No-Fallback: 'except: pass|except: return None'
#       ※ 残る 2 組(YAGNI の意味重複、git 安全の rule 文 vs settings deny)は grep で機械判定できないため
#         手動評価であり、レポート側にその旨を明記する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

measure_tree() {
  local root="$1"
  local claude_md=0 always_rules=0 imports=0 import_count=0 agents_md=0
  [[ -f "$root/claude/CLAUDE.md" ]] && claude_md=$(wc -c < "$root/claude/CLAUDE.md")
  for f in "$root"/claude/rules/*.md; do
    [[ -f "$f" ]] || continue
    if ! head -1 "$f" | grep -q '^---$' || ! awk '/^---$/{c++} c==1' "$f" | grep -q '^paths:'; then
      always_rules=$((always_rules + $(wc -c < "$f")))
    fi
  done
  if [[ -f "$root/claude/CLAUDE.md" ]]; then
    while IFS= read -r name; do
      local rf="$root/shared/rules/$name.md"
      [[ -f "$rf" ]] && imports=$((imports + $(wc -c < "$rf"))) && import_count=$((import_count + 1))
    done < <(grep -oE '@~/\.agents/rules/[A-Za-z0-9_-]+\.md' "$root/claude/CLAUDE.md" | sed -E 's#@~/\.agents/rules/##; s/\.md$//')
  fi
  [[ -f "$root/codex/AGENTS.md" ]] && agents_md=$(wc -c < "$root/codex/AGENTS.md")

  echo "claude_md_bytes: $claude_md"
  echo "claude_always_rules_bytes: $always_rules"
  echo "claude_imported_shared_bytes: $imports ($import_count files)"
  echo "claude_always_on_total: $((claude_md + always_rules + imports))"
  echo "codex_agents_md_bytes: $agents_md"
  echo "combined_always_on_total: $((claude_md + always_rules + imports + agents_md))"

  echo "custom_agents: $(find "$root/claude/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
  echo "claude_skills: $(find "$root/claude/skills" -mindepth 2 -maxdepth 2 -name 'SKILL.md' 2>/dev/null | wc -l)"
  echo "codex_skills: $(find "$root/codex/skills" -mindepth 2 -maxdepth 2 -name 'SKILL.md' 2>/dev/null | wc -l)"
  echo "hook_scripts: $(find "$root/claude/hooks" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l)"
  if [[ -f "$root/claude/settings.json" ]] && command -v jq >/dev/null; then
    echo "hook_registrations: $(jq '[.hooks[][] | .hooks[]] | length' "$root/claude/settings.json" 2>/dev/null || echo 'n/a')"
  else
    echo "hook_registrations: n/a"
  fi
  echo "shared_rules: $(find "$root/shared/rules" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
  echo "claude_rules: $(find "$root/claude/rules" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
  echo "output_styles: $(find "$root/claude/output-styles" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"

  local pins=0
  [[ -f "$root/claude/settings.json" ]] && pins=$((pins + $(grep -coE '"model"[[:space:]]*:[[:space:]]*"claude-[a-z0-9.-]+"' "$root/claude/settings.json" || true)))
  local f
  for f in "$root"/claude/agents/*.md; do
    [[ -f "$f" ]] || continue
    pins=$((pins + $(grep -cE '^model:[[:space:]]*claude-' "$f" || true)))
  done
  for f in "$root"/codex/*.toml; do
    [[ -f "$f" ]] || continue
    pins=$((pins + $(grep -cE '^[[:space:]]*model[[:space:]]*=[[:space:]]*"claude-' "$f" || true)))
  done
  echo "full_model_pins: $pins"
  local aliases=0
  for f in "$root"/claude/agents/*.md; do
    [[ -f "$f" ]] || continue
    aliases=$((aliases + $(grep -cE '^model:[[:space:]]*(sonnet|opus|haiku|fable|inherit)[[:space:]]*$' "$f" || true)))
  done
  echo "tier_aliases: $aliases"

  local uncond=0
  for f in "$root/claude/skills/gh:start/SKILL.md" "$root/claude/skills/gh-start/SKILL.md"; do
    [[ -f "$f" ]] || continue
    uncond=$((uncond + $(grep -c 'subagent_type: "general-purpose"' "$f" || true)))
  done
  echo "unconditional_delegation_gh_start: $uncond"

  local learn=0
  [[ -f "$root/claude/CLAUDE.md" ]] && learn=$((learn + $(grep -c '@~/\.agents/rules/learnings\.md' "$root/claude/CLAUDE.md" || true)))
  [[ -f "$root/codex/AGENTS.md" ]] && learn=$((learn + $(grep -c 'BEGIN shared:learnings' "$root/codex/AGENTS.md" || true)))
  echo "always_on_learnings_paths: $learn"

  local dups=0 sig files
  for sig in '空・単一・境界値|空、単一、境界値' 'テストをスキップ・無効化|テストの無効化' 'except: pass|except: return None'; do
    files=$( (grep -lE "$sig" "$root"/shared/rules/*.md 2>/dev/null || true) | wc -l)
    if [[ "$files" -gt 1 ]]; then
      dups=$((dups + 1))
    fi
  done
  echo "duplicated_principles_greppable: $dups (of 3 signatures; +2 manual-assessed pairs documented in report)"
}

MODE="single"
TREE="$REPO_ROOT"
BEFORE_REF=""
AFTER_REF="HEAD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      TREE="$2"
      shift 2
      ;;
    --before-ref)
      MODE="compare"
      BEFORE_REF="$2"
      shift 2
      ;;
    --after-ref)
      AFTER_REF="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      exit 1
      ;;
  esac
done

if [[ "$MODE" == "single" ]]; then
  echo "== metrics: $TREE =="
  measure_tree "$TREE"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/before" "$TMP/after"
git -C "$REPO_ROOT" archive "$BEFORE_REF" | tar -x -C "$TMP/before"
git -C "$REPO_ROOT" archive "$AFTER_REF" | tar -x -C "$TMP/after"

echo "== metrics: before ($BEFORE_REF) =="
measure_tree "$TMP/before" > "$TMP/before.txt"
cat "$TMP/before.txt"
echo
echo "== metrics: after ($AFTER_REF) =="
measure_tree "$TMP/after" > "$TMP/after.txt"
cat "$TMP/after.txt"
echo
echo "== comparison (before -> after) =="
while IFS=: read -r key bval; do
  aval="$(grep "^$key:" "$TMP/after.txt" | cut -d: -f2- || echo ' n/a')"
  echo "$key:${bval} ->${aval}"
done < "$TMP/before.txt"
