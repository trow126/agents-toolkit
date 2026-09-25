#!/usr/bin/env bash
# audit-context-runtime.sh — Claude Code/Codex の実context状態をread-onlyで検証する。
set -euo pipefail

REPO_DIR="$(cd "${AGENTS_TOOLKIT_REPO:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd -P)"
MANIFEST="$REPO_DIR/install/manifest.tsv"
FAILURES=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

require_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    return
  fi
  echo "ERROR: required command is missing: $command_name" >&2
  exit 1
}

for command_name in claude codex jq python3; do
  require_command "$command_name"
done
if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: manifest is missing: $MANIFEST" >&2
  exit 1
fi

declare -a CLAUDE_SKILL_SOURCES=()
declare -a CODEX_SKILL_SOURCES=()
declare -a CODEX_SKILL_NAMES=()

while IFS=$'\t' read -r mode source target; do
  [[ -z "$mode" || "$mode" == \#* ]] && continue
  case "$target" in
    .claude/skills/*/SKILL.md)
      CLAUDE_SKILL_SOURCES+=("$REPO_DIR/$source")
      ;;
    .claude/skills/*)
      [[ "$mode" == "link-dir" ]] && CLAUDE_SKILL_SOURCES+=("$REPO_DIR/$source/SKILL.md")
      ;;
    .agents/skills/*/SKILL.md)
      CODEX_SKILL_SOURCES+=("$REPO_DIR/$source")
      name="${target#.agents/skills/}"
      CODEX_SKILL_NAMES+=("${name%/SKILL.md}")
      ;;
    .agents/skills/*)
      if [[ "$mode" == "link-dir" ]]; then
        CODEX_SKILL_SOURCES+=("$REPO_DIR/$source/SKILL.md")
        CODEX_SKILL_NAMES+=("${target#.agents/skills/}")
      fi
      ;;
  esac
done < "$MANIFEST"

if [[ ${#CLAUDE_SKILL_SOURCES[@]} -eq 0 || ${#CODEX_SKILL_SOURCES[@]} -eq 0 ]]; then
  echo "ERROR: manifest does not declare both Claude Code and Codex skills" >&2
  exit 1
fi

if jq -e '.autoMemoryEnabled == false' "$REPO_DIR/claude/managed-settings.json" >/dev/null; then
  pass "Claude native auto memory is disabled"
else
  fail "Claude native auto memory must be disabled"
fi

claude_plugins="$(claude plugin list --json)"
if jq -e '
  any(.[];
    .id == "superpowers@claude-plugins-official"
    and .enabled == false
  )
' <<< "$claude_plugins" >/dev/null; then
  pass "Claude superpowers plugin is installed but disabled"
else
  fail "Claude superpowers plugin is missing or enabled"
fi

codex_plugins="$(codex plugin list --json)"
if jq -e '
  any(.installed[];
    .pluginId == "superpowers@openai-curated"
    and .installed == true
    and .enabled == false
  )
' <<< "$codex_plugins" >/dev/null; then
  pass "Codex superpowers plugin is installed but disabled"
else
  fail "Codex superpowers plugin is missing or enabled"
fi

codex_memories="$(codex features list | awk '$1 == "memories" {print $3}')"
if [[ "$codex_memories" == "false" ]]; then
  pass "Codex memories feature is disabled"
else
  fail "Codex memories feature must be disabled (actual: ${codex_memories:-missing})"
fi

stale_links=0
while IFS= read -r link_path; do
  raw_target="$(readlink "$link_path")"
  case "$raw_target" in
    "$REPO_DIR/claude/skills/"*)
      fail "broken toolkit symlink remains: $link_path -> $raw_target"
      stale_links=$((stale_links + 1))
      ;;
  esac
done < <(find "$HOME/.claude/skills" -maxdepth 2 -type l ! -exec test -e {} \; -print 2>/dev/null || true)
if [[ "$stale_links" -eq 0 ]]; then
  pass "no broken toolkit symlinks remain under ~/.claude/skills"
fi

claude_resource_errors="$(
  PYTHONDONTWRITEBYTECODE=1 python3 - "$REPO_DIR" "$MANIFEST" "$HOME" <<'PY'
import os
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
manifest = Path(sys.argv[2])
home = Path(sys.argv[3])
link_pattern = re.compile(r"\[[^\]]+\]\(([^)#]+\.md)(?:#[^)]+)?\)")
errors: list[str] = []


def check_skill(skill_name: str, source_skill: Path, installed_skill: Path) -> None:
    if not source_skill.is_file():
        errors.append(f"{skill_name}: source entrypoint missing: {source_skill}")
        return
    if not installed_skill.is_file():
        errors.append(f"{skill_name}: installed entrypoint missing: {installed_skill}")
        return
    text = source_skill.read_text(encoding="utf-8")
    for raw_target in link_pattern.findall(text):
        target_text = raw_target.strip()
        if target_text.startswith(("http://", "https://", "~/", "/")):
            continue
        logical_target = Path(os.path.normpath(installed_skill.parent / target_text))
        if not logical_target.is_file():
            errors.append(
                f"{skill_name}: installed Markdown reference missing: "
                f"{target_text} -> {logical_target}"
            )


with manifest.open(encoding="utf-8") as handle:
    for raw in handle:
        line = raw.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 3:
            continue
        _mode, source, target = fields
        source_path = repo / source
        if target == ".claude/skills" and source_path.is_dir():
            for source_skill in sorted(source_path.glob("*/SKILL.md")):
                skill_name = source_skill.parent.name
                check_skill(
                    skill_name,
                    source_skill,
                    home / ".claude" / "skills" / skill_name / "SKILL.md",
                )
            continue
        match = re.fullmatch(r"\.claude/skills/([^/]+)(?:/SKILL\.md)?", target)
        if match is None:
            continue
        skill_name = match.group(1)
        source_skill = source_path / "SKILL.md" if source_path.is_dir() else source_path
        installed_path = home / target
        installed_skill = (
            installed_path if target.endswith("/SKILL.md") else installed_path / "SKILL.md"
        )
        check_skill(skill_name, source_skill, installed_skill)

print("\n".join(errors))
PY
)"
if [[ -n "$claude_resource_errors" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && fail "Claude skill package: $line"
  done <<< "$claude_resource_errors"
else
  pass "Claude installed skill entrypoints and Markdown references are readable"
fi

claude_debug="$(mktemp)"
claude_output="$(mktemp)"
cleanup() {
  [[ ! -e "$claude_debug" ]] || unlink "$claude_debug"
  [[ ! -e "$claude_output" ]] || unlink "$claude_output"
}
trap cleanup EXIT

if CLAUDE_STREAM_IDLE_TIMEOUT_MS=900000 claude \
  --print \
  --output-format json \
  --debug skills \
  --debug-file "$claude_debug" \
  --max-turns 1 \
  --max-budget-usd 0.000001 \
  "/skills" > "$claude_output"; then
  if jq -e '.num_turns == 0 and .total_cost_usd == 0' "$claude_output" >/dev/null; then
    pass "Claude skill discovery initialized without model inference"
  else
    fail "Claude skill discovery unexpectedly used model inference"
  fi
else
  fail "Claude skill discovery probe failed"
fi

claude_discovered="$(
  sed -n 's/.*Loaded \([0-9][0-9]*\) unique skills.*/\1/p' "$claude_debug" \
    | tail -1
)"
if [[ "$claude_discovered" =~ ^[0-9]+$ ]] \
  && [[ "$claude_discovered" -ge "${#CLAUDE_SKILL_SOURCES[@]}" ]]; then
  pass "Claude discovered $claude_discovered user skills (${#CLAUDE_SKILL_SOURCES[@]} toolkit skills required)"
else
  fail "Claude discovered ${claude_discovered:-unknown} user skills; toolkit requires ${#CLAUDE_SKILL_SOURCES[@]}"
fi
if grep -F "Failed to follow symlink $HOME/.claude/skills/" "$claude_debug" >/dev/null; then
  fail "Claude debug log reports broken user skill symlinks"
fi
if grep -F "Checking plugin superpowers:" "$claude_debug" >/dev/null; then
  fail "Claude loaded superpowers despite the disabled policy"
else
  pass "Claude runtime did not load superpowers"
fi

# Codex lists skills by name with paths relative to skill roots (`r0/<name>/SKILL.md`),
# so discovery is matched by skill name. Skills whose agents/openai.yaml sets
# policy.allow_implicit_invocation: false must stay out of the list (manual-only).
codex_prompt="$(codex debug prompt-input "context-runtime-audit")"
codex_listed=""
if ! codex_listed="$(python3 -c '
import json, re, sys
texts = []
def walk(node):
    if isinstance(node, dict):
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)
    elif isinstance(node, str):
        texts.append(node)
walk(json.load(sys.stdin))
names = set()
for text in texts:
    names.update(re.findall(r"^- ([a-z0-9][a-z0-9-]*):", text, re.M))
print("\n".join(sorted(names)))
' <<< "$codex_prompt")"; then
  fail "Codex prompt-input output is not parseable JSON"
fi
codex_before="$FAILURES"
for i in "${!CODEX_SKILL_SOURCES[@]}"; do
  skill_source="${CODEX_SKILL_SOURCES[$i]}"
  skill_name="${CODEX_SKILL_NAMES[$i]}"
  policy_file="$(dirname "$skill_source")/agents/openai.yaml"
  if [[ ! -f "$skill_source" ]]; then
    fail "Codex manifest skill source is missing: $skill_source"
  elif [[ -f "$policy_file" ]] && grep -qE '^[[:space:]]*allow_implicit_invocation:[[:space:]]*false[[:space:]]*$' "$policy_file"; then
    if grep -qxF "$skill_name" <<< "$codex_listed"; then
      fail "Codex lists manual-only skill (allow_implicit_invocation: false): $skill_name"
    fi
  elif ! grep -qxF "$skill_name" <<< "$codex_listed"; then
    fail "Codex prompt discovery is missing toolkit skill: $skill_name"
  fi
done
if grep -F "/plugins/plugins/superpowers/" <<< "$codex_prompt" >/dev/null; then
  fail "Codex prompt discovery still contains superpowers skills"
elif [[ "$FAILURES" -eq "$codex_before" ]]; then
  pass "Codex prompt discovery contains all manifest skills and no superpowers skills"
fi

# Codex profiles (appendix C.2), checked only when the manifest distributes them. Both must put
# their developer instructions first and drop the multi-agent instructions. toolkit-implementer
# (D8) must also drop the skills it disables and the bundled skills; toolkit-divergent (D7) sets
# [skills] include_instructions=false and must drop the skill list entirely.
for profile_name in toolkit-implementer toolkit-divergent; do
  grep -qP "\t\.codex/${profile_name}\.config\.toml\$" "$MANIFEST" || continue
  profile_label="${profile_name#toolkit-}"
  profile_file="$HOME/.codex/${profile_name}.config.toml"
  if [[ ! -f "$profile_file" ]]; then
    fail "Codex ${profile_label} profile is not installed: $profile_file"
    continue
  fi
  if ! profile_prompt="$(codex -p "$profile_name" debug prompt-input "context-runtime-audit")"; then
    fail "codex -p ${profile_name} debug prompt-input failed"
    continue
  fi
  profile_prompt_file="$(mktemp)"
  printf '%s' "$profile_prompt" > "$profile_prompt_file"
  profile_problems="$(python3 - "$profile_file" "$profile_prompt_file" <<'PYPROFILE'
import json, re, sys, tomllib
profile = tomllib.loads(open(sys.argv[1], encoding="utf-8").read())
first_line = next(l.strip() for l in profile["developer_instructions"].splitlines() if l.strip())
skills = profile.get("skills") or {}
disabled = {c["name"] for c in skills.get("config") or [] if c.get("enabled") is False}
parts = []
for item in json.load(open(sys.argv[2], encoding="utf-8")):
    for content in item.get("content") or []:
        if isinstance(content, dict) and isinstance(content.get("text"), str):
            parts.append((item.get("role"), content["text"]))
listed = set()
for _, text in parts:
    if "<skills_instructions>" in text:
        listed |= set(re.findall(r"^- ([a-z0-9][a-z0-9-]*):", text, re.M))
problems = []
if not parts or parts[0][0] != "developer" or not parts[0][1].lstrip().startswith(first_line):
    problems.append("profile developer_instructions are not the first developer message")
if skills.get("include_instructions") is False:
    if any("<skills_instructions>" in t for _, t in parts):
        problems.append("skill list is still injected: " + ", ".join(sorted(listed)))
for name in sorted(listed & disabled):
    problems.append(f"profile-disabled skill is still listed: {name}")
if any(re.search(r"\(file: r\d+/[^)]*\)", t) and "/.system/" in t for _, t in parts):
    problems.append("bundled (.system) skills are still listed")
if any("<multi_agent" in t for _, t in parts):
    problems.append("multi-agent instructions are still injected")
print("\n".join(problems))
PYPROFILE
)"
  rm -f "$profile_prompt_file"
  if [[ -n "$profile_problems" ]]; then
    while IFS= read -r problem; do fail "Codex ${profile_label} profile: $problem"; done <<< "$profile_problems"
  elif [[ "$profile_name" == toolkit-divergent ]]; then
    pass "Codex divergent profile prompt drops the skill list and multi-agent instructions"
  else
    pass "Codex implementer profile prompt drops disabled skills and multi-agent instructions"
  fi
done

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: runtime context policy is effective"
  exit 0
fi
echo "FAIL: $FAILURES runtime context policy violation(s)" >&2
exit 1
