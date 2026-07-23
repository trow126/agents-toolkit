#!/usr/bin/env bash
# measure-metrics.sh — reproducible before/after metrics for the modernization.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY="$REPO_ROOT/docs/reports/inventory-elements.tsv"

inventory_count() {
  local root="$1" tag="$2"
  if [[ ! -f "$INVENTORY" ]]; then
    echo "n/a"
    return
  fi
  python3 - "$root" "$INVENTORY" "$tag" <<'PY'
import csv, os, sys
root, inventory, tag = sys.argv[1:]
active=set()
with open(inventory, encoding='utf-8', newline='') as fh:
    for row in csv.DictReader(fh, delimiter='\t'):
        if tag not in (row.get('tags') or '').split():
            continue
        for key in ('before_path','after_path'):
            path=(row.get(key) or '').strip()
            if not path or path == '-' or path.startswith(('~','$','active ')) or ' -> ' in path or ';' in path:
                continue
            candidate=os.path.join(root,path)
            if os.path.exists(candidate):
                active.add(path)
print(len(active))
PY
}

measure_tree() {
  local root="$1"
  local claude_md=0 always_rules=0 imports=0 import_count=0 agents_md=0
  local claude_md_lines=0 always_rules_lines=0 agents_md_lines=0

  if [[ -f "$root/claude/CLAUDE.md" ]]; then
    claude_md=$(wc -c < "$root/claude/CLAUDE.md")
    claude_md_lines=$(wc -l < "$root/claude/CLAUDE.md")
  fi
  for f in "$root"/claude/rules/*.md; do
    [[ -f "$f" ]] || continue
    if ! head -1 "$f" | grep -q '^---$' || ! awk '/^---$/{c++} c==1' "$f" | grep -q '^paths:'; then
      always_rules=$((always_rules + $(wc -c < "$f")))
      always_rules_lines=$((always_rules_lines + $(wc -l < "$f")))
    fi
  done
  if [[ -f "$root/claude/CLAUDE.md" ]]; then
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      local rf="$root/shared/rules/$name.md"
      if [[ -f "$rf" ]]; then
        imports=$((imports + $(wc -c < "$rf")))
        import_count=$((import_count + 1))
      fi
    done < <(grep -oE '@~/\.agents/rules/[A-Za-z0-9_-]+\.md' "$root/claude/CLAUDE.md" 2>/dev/null | sed -E 's#@~/\.agents/rules/##; s/\.md$//' || true)
  fi
  if [[ -f "$root/codex/AGENTS.md" ]]; then
    agents_md=$(wc -c < "$root/codex/AGENTS.md")
    agents_md_lines=$(wc -l < "$root/codex/AGENTS.md")
  fi

  local claude_total=$((claude_md + always_rules + imports))
  echo "claude_md_bytes: $claude_md"
  echo "claude_md_lines: $claude_md_lines"
  echo "claude_always_rules_bytes: $always_rules"
  echo "claude_always_rules_lines: $always_rules_lines"
  echo "claude_imported_shared_bytes: $imports ($import_count files)"
  echo "claude_always_on_total: $claude_total"
  echo "codex_agents_md_bytes: $agents_md"
  echo "codex_agents_md_lines: $agents_md_lines"
  echo "combined_always_on_total: $((claude_total + agents_md))"

  echo "custom_agents: $(find "$root/claude/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
  echo "claude_skills: $(find "$root/claude/skills" -mindepth 2 -maxdepth 2 -name 'SKILL.md' 2>/dev/null | wc -l)"
  echo "codex_skills: $(find "$root/codex/skills" -mindepth 2 -maxdepth 2 -name 'SKILL.md' 2>/dev/null | wc -l)"
  echo "hook_scripts: $(find "$root/claude/hooks" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l)"

  local user_settings="$root/claude/settings.json"
  local managed_settings="$root/claude/managed-settings.json"
  local security_settings="$user_settings"
  [[ -f "$managed_settings" ]] && security_settings="$managed_settings"

  if [[ -f "$security_settings" ]] && command -v jq >/dev/null; then
    echo "hook_registrations: $(jq '[.hooks[][]? | .hooks[]?] | length' "$security_settings" 2>/dev/null || echo 'n/a')"
  else
    echo "hook_registrations: n/a"
  fi
  echo "shared_rules: $(find "$root/shared/rules" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
  echo "claude_rules: $(find "$root/claude/rules" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
  echo "output_styles: $(find "$root/claude/output-styles" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
  echo "inventory_audited_elements: $(($(wc -l < "$INVENTORY") - 1))"
  echo "review_progress_retrospective_mechanisms: $(inventory_count "$root" review-progress-retrospective)"
  echo "custom_builtin_agent_overlaps: $(inventory_count "$root" builtin-overlap)"

  local scan
  if ! scan="$(python3 "$SCRIPT_DIR/lib/scan-model-pins.py" "$root")"; then
    echo "ERROR: model scanner failed for $root — metrics abort (fail-closed)" >&2
    exit 1
  fi
  echo "full_model_pins: $( (grep -c ':pin:' <<< "$scan") || true)"
  echo "tier_aliases: $( (grep 'claude/agents/' <<< "$scan" | grep -c ':alias:') || true)"

  if [[ -f "$security_settings" ]] && command -v jq >/dev/null; then
    echo "permissions_allow_count: $(jq '.permissions.allow // [] | length' "$security_settings")"
    echo "permissions_ask_count: $(jq '.permissions.ask // [] | length' "$security_settings")"
    echo "permissions_deny_count: $(jq '.permissions.deny // [] | length' "$security_settings")"
    echo "bypass_lockout_ok: $(jq -r 'if .permissions.disableBypassPermissionsMode == "disable" then "yes" else "no" end' "$security_settings")"
    echo "auto_mode_lockout_ok: $(jq -r 'if .disableAutoMode == "disable" then "yes" else "no" end' "$security_settings")"
    echo "effective_preallowed_domains_count: $(jq '[(.sandbox.network.allowedDomains[]? // empty), (.permissions.allow[]? | select(test("^WebFetch\\(domain:")))] | length' "$security_settings")"
    echo "unsandboxed_query_capable_allows: $(jq '[.sandbox.excludedCommands[]? | split(" ")[0]] as $words | [.permissions.allow[]? | select(startswith("Bash(")) | select(. as $r | [$words[] | . as $w | (($r == ("Bash(" + $w + ")")) or ($r | startswith("Bash(" + $w + " ")))] | any)] | length' "$security_settings")"
    echo "managed_bash_allows: $(jq '[.permissions.allow[]? | select(startswith("Bash("))] | length' "$security_settings")"
  else
    for key in permissions_allow_count permissions_ask_count permissions_deny_count bypass_lockout_ok auto_mode_lockout_ok effective_preallowed_domains_count unsandboxed_query_capable_allows managed_bash_allows; do
      echo "$key: n/a"
    done
  fi

  if [[ -f "$managed_settings" ]] && command -v jq >/dev/null; then
    echo "managed_policy_present: yes"
    echo "managed_permission_lock_ok: $(jq -r 'if .allowManagedPermissionRulesOnly == true then "yes" else "no" end' "$managed_settings")"
    echo "managed_hooks_lock_ok: $(jq -r 'if .allowManagedHooksOnly == true then "yes" else "no" end' "$managed_settings")"
    echo "managed_read_lock_ok: $(jq -r 'if .sandbox.filesystem.allowManagedReadPathsOnly == true then "yes" else "no" end' "$managed_settings")"
    echo "managed_domain_lock_ok: $(jq -r 'if .sandbox.network.allowManagedDomainsOnly == true then "yes" else "no" end' "$managed_settings")"
    echo "sandbox_auto_allow_bash: $(jq -r 'if .sandbox.autoAllowBashIfSandboxed == true then "yes" else "no" end' "$managed_settings")"
  else
    echo "managed_policy_present: no"
    echo "managed_permission_lock_ok: n/a"
    echo "managed_hooks_lock_ok: n/a"
    echo "managed_read_lock_ok: n/a"
    echo "managed_domain_lock_ok: n/a"
    echo "sandbox_auto_allow_bash: n/a"
  fi
  if [[ -f "$user_settings" ]] && command -v jq >/dev/null; then
    echo "auto_memory_enabled: $(jq -r 'if .autoMemoryEnabled == true then "yes" else "no" end' "$user_settings")"
  else
    echo "auto_memory_enabled: n/a"
  fi

  local hook_metrics session_typical session_max
  hook_metrics="$(python3 "$SCRIPT_DIR/measure-hook-injection.py" "$root")"
  printf '%s\n' "$hook_metrics"
  session_typical="$(awk -F': ' '/^session_start_system_message_typical_bytes:/{print $2}' <<< "$hook_metrics")"
  session_max="$(awk -F': ' '/^session_start_system_message_max_bytes:/{print $2}' <<< "$hook_metrics")"
  echo "claude_session_start_injection_typical_bytes: $((claude_total + session_typical))"
  if [[ "$session_max" =~ ^[0-9]+$ ]]; then
    echo "claude_session_start_injection_max_bytes: $((claude_total + session_max))"
  else
    echo "claude_session_start_injection_max_bytes: $session_max"
  fi

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
    [[ "$files" -gt 1 ]] && dups=$((dups + 1))
  done
  echo "duplicated_principles_greppable: $dups (of 3 signatures; +2 manual-assessed pairs documented in report)"
}

MODE="single"
TREE="$REPO_ROOT"
BEFORE_REF=""
AFTER_REF="HEAD"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) TREE="$2"; shift 2 ;;
    --before-ref) MODE="compare"; BEFORE_REF="$2"; shift 2 ;;
    --after-ref) AFTER_REF="$2"; shift 2 ;;
    *) echo "ERROR: unknown argument '$1'" >&2; exit 1 ;;
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
