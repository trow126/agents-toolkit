#!/usr/bin/env bash
# routing table checks (check-model-routing.py) and the model-name scan (scan-model-pins.py --names)
# on fixture repos: agent membership, target values, prose anchors, env pins, schema, and the
# promote/revert property (table and targets changed together pass; either alone fails).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

HEADER=$'role\truntime\tlauncher\tmodel\teffort\ttargets\tfallback\tretires_at\tevidence\tverified_at\tadaptation'

build_fixture() {
  local repo="$1"
  mkdir -p "$repo/install" "$repo/scripts/lib" "$repo/claude/agents" "$repo/codex/agents" \
    "$repo/skills/sample" "$repo/docs/contracts"
  cp "$REPO_ROOT/scripts/lib/check-model-routing.py" "$REPO_ROOT/scripts/lib/scan-model-pins.py" "$repo/scripts/lib/"
  printf 'link-file\tclaude/CLAUDE.md\t.claude/CLAUDE.md\nlink-dir\tclaude/agents\t.claude/agents\nlink-dir\tcodex/agents\t.codex/agents\nlink-dir\tskills/sample\t.claude/skills/sample\n' \
    > "$repo/install/manifest.tsv"
  printf '# fixture\n\n- mainのFableはlead/advisorとして使う。\n' > "$repo/claude/CLAUDE.md"
  printf -- '---\nname: explore\ndescription: Fixture.\nmodel: haiku\n---\n\n# Explore\n' > "$repo/claude/agents/explore.md"
  printf 'name = "reviewer"\ndescription = "Fixture."\ndeveloper_instructions = "Review."\nmodel = "gpt-5.6-sol"\nmodel_reasoning_effort = "high"\nsandbox_mode = "read-only"\n' \
    > "$repo/codex/agents/reviewer.toml"
  printf -- '---\nname: sample\ndescription: Fixture skill.\n---\n\n# Sample\n' > "$repo/skills/sample/SKILL.md"
  {
    printf '%s\n' "$HEADER"
    printf 'claude-main\tclaude\tmain session\tfable\thigh\tclaude/CLAUDE.md~lead/advisor\topus\t\tfixture\t2026-09-25\t\n'
    printf 'claude-explore\tclaude\tAgent(Explore)\thaiku\t-\tclaude/agents/explore.md#model\tsonnet\tnot-before:2026-10-15\tfixture\t2026-09-25\t\n'
    printf 'codex-reviewer\tcodex\tspawn_agent\tgpt-5.6-sol\thigh\tcodex/agents/reviewer.toml#model,model_reasoning_effort\tgpt-6-sol/high\t\tfixture\t2026-09-25\t\n'
  } > "$repo/docs/contracts/model-routing.tsv"
  git -C "$repo" init -q
  git -C "$repo" add -A
}

CHECK_RC=0
CHECK_OUT=""
NAMES_OUT=""
run_checks() {
  local repo="$1"
  git -C "$repo" add -A
  CHECK_RC=0
  CHECK_OUT="$(python3 "$repo/scripts/lib/check-model-routing.py" "$repo" 2>&1)" || CHECK_RC=$?
  NAMES_OUT="$(python3 "$repo/scripts/lib/scan-model-pins.py" --names "$repo" 2>&1)"
}

# case <name> <mutation> <expect: PASS | FAIL:<text> | NAME:<text>>
run_case() {
  local name="$1" mutate="$2" expected="$3"
  local repo="$SANDBOX/$name"
  build_fixture "$repo"
  eval "$mutate"
  run_checks "$repo"
  case "$expected" in
    PASS)
      if [[ "$CHECK_RC" -eq 0 && "$CHECK_OUT" != *"FAIL:"* && -z "$NAMES_OUT" ]]; then
        ok "$name: PASS"
      else
        ng "$name: expected PASS (rc=$CHECK_RC out=$CHECK_OUT names=$NAMES_OUT)"
      fi
      ;;
    FAIL:*)
      if [[ "$CHECK_RC" -ne 0 && "$CHECK_OUT" == *"${expected#FAIL:}"* ]]; then
        ok "$name: FAIL を報告"
      else
        ng "$name: expected FAIL containing '${expected#FAIL:}' (rc=$CHECK_RC out=$CHECK_OUT)"
      fi
      ;;
    NAME:*)
      if [[ "$NAMES_OUT" == *"${expected#NAME:}"* ]]; then
        ok "$name: model 名を検出"
      else
        ng "$name: expected name hit '${expected#NAME:}' (names=$NAMES_OUT)"
      fi
      ;;
  esac
}

TABLE='$repo/docs/contracts/model-routing.tsv'

run_case valid ':' PASS
run_case orphan-agent \
  'cp "$repo/codex/agents/reviewer.toml" "$repo/codex/agents/extra.toml"' \
  'FAIL:agent file codex/agents/extra.toml must belong to exactly one routing row (found 0)'
run_case agent-in-two-rows \
  'printf "claude-explore-2\tclaude\tAgent\thaiku\t-\tclaude/agents/explore.md#model\t\t\tfixture\t2026-09-25\t\n" >> '"$TABLE" \
  'FAIL:agent file claude/agents/explore.md must belong to exactly one routing row (found 2)'
run_case structured-value-drift \
  'sed -i "s/^model_reasoning_effort = \"high\"/model_reasoning_effort = \"xhigh\"/" "$repo/codex/agents/reviewer.toml"' \
  'FAIL:model_reasoning_effort=xhigh does not match routing table value high'
run_case prose-value-drift \
  'sed -i "s/mainのFableは/mainのOpusは/" "$repo/claude/CLAUDE.md"' \
  'FAIL:line does not state routing table model fable'
run_case ambiguous-anchor \
  'printf "%s\n" "- 別のlead/advisorの行" >> "$repo/claude/CLAUDE.md"' \
  "FAIL:anchor 'lead/advisor' must match exactly one line (found 2)"
run_case name-outside-targets \
  'printf "%s\n" "" "Use Opus for this." >> "$repo/skills/sample/SKILL.md"' \
  'NAME:skills/sample/SKILL.md:8:name:Opus'
run_case name-japanese-boundary \
  'printf "%s\n" "" "Fableを使う。" >> "$repo/skills/sample/SKILL.md"' \
  'NAME:skills/sample/SKILL.md:8:name:Fable'
run_case name-full-id \
  'printf "%s\n" "" "model = gpt-6-sol and claude-opus-5-5" >> "$repo/skills/sample/SKILL.md"' \
  'NAME:name:claude-opus-5-5'
run_case env-pin-without-row \
  'mkdir -p "$repo/claude"; printf "{\"env\": {\"ANTHROPIC_DEFAULT_FABLE_MODEL\": \"claude-fable-5-1\"}}\n" > "$repo/claude/managed-settings.json"' \
  'FAIL:env pin claude/managed-settings.json:env.ANTHROPIC_DEFAULT_FABLE_MODEL is not a routing table target'
run_case env-pin-with-row \
  'printf "{\"env\": {\"ANTHROPIC_DEFAULT_FABLE_MODEL\": \"claude-fable-5-1\"}}\n" > "$repo/claude/managed-settings.json"; printf "claude-fable-pin\tclaude\tmanaged env pin\tclaude-fable-5-1\t-\tclaude/managed-settings.json#env.ANTHROPIC_DEFAULT_FABLE_MODEL\t\t\tfixture\t2026-09-25\t\n" >> '"$TABLE" \
  PASS
run_case promote-table-and-target \
  'sed -i "s/gpt-5.6-sol\thigh\tcodex/gpt-6-sol\thigh\tcodex/" '"$TABLE"'; sed -i "s/gpt-5.6-sol/gpt-6-sol/" "$repo/codex/agents/reviewer.toml"' \
  PASS
run_case promote-table-only \
  'sed -i "s/gpt-5.6-sol\thigh\tcodex/gpt-6-sol\thigh\tcodex/" '"$TABLE" \
  'FAIL:model=gpt-5.6-sol does not match routing table value gpt-6-sol'
run_case revert-restores \
  'sed -i "s/gpt-5.6-sol\thigh\tcodex/gpt-6-sol\thigh\tcodex/" '"$TABLE"'; sed -i "s/gpt-5.6-sol/gpt-6-sol/" "$repo/codex/agents/reviewer.toml"; git -C "$repo" checkout -q -- docs/contracts/model-routing.tsv codex/agents/reviewer.toml' \
  PASS
run_case bad-retires-at \
  'sed -i "s/not-before:2026-10-15/2026-13-40/" '"$TABLE" \
  'FAIL:retires_at must be empty, YYYY-MM-DD, or not-before:YYYY-MM-DD'
run_case duplicate-role \
  'printf "claude-main\tclaude\tx\tfable\thigh\tclaude/CLAUDE.md~lead/advisor\t\t\tfixture\t2026-09-25\t\n" >> '"$TABLE" \
  'FAIL:duplicate role'
run_case table-missing \
  'rm "$repo/docs/contracts/model-routing.tsv"' \
  'FAIL:routing table missing'

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
