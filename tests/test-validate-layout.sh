#!/usr/bin/env bash
# Standalone contract tests for scripts/validate-layout.sh.
# Every fixture is a real, isolated git repository; the user's HOME is untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/validate-layout.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0

ok(){ echo "ok: $1"; }
ng(){ echo "FAIL: $1" >&2; FAILURES=$((FAILURES+1)); }
assert_zero(){ [[ "$2" -eq 0 ]] && ok "$1" || ng "$1 (exit=$2)"; }
assert_nonzero(){ [[ "$2" -ne 0 ]] && ok "$1" || ng "$1 (expected non-zero)"; }
assert_contains(){ [[ "$2" == *"$3"* ]] && ok "$1" || { ng "$1 (missing: $3)"; printf '%s\n' "$2" >&2; }; }

build_fixture() {
  local repo="$1"
  mkdir -p \
    "$repo/install" "$repo/scripts/lib" \
    "$repo/claude/rules" "$repo/claude/agents" "$repo/claude/skills/sample-skill" "$repo/claude/githooks" \
    "$repo/codex" "$repo/shared/bin" "$repo/shared/rules" \
    "$repo/docs/contracts" "$repo/docs/waivers" "$repo/docs/requirements" "$repo/docs/reports" "$repo/tests"

  cp "$VALIDATE" "$repo/scripts/validate-layout.sh"
  cp "$REPO_ROOT/scripts/check-managed-policy.py" "$repo/scripts/check-managed-policy.py"
  cp "$REPO_ROOT/scripts/lib/scan-model-pins.py" "$repo/scripts/lib/scan-model-pins.py"
  chmod +x "$repo/scripts/validate-layout.sh" "$repo/scripts/check-managed-policy.py"

  cp "$REPO_ROOT/claude/settings.json" "$repo/claude/settings.json"
  cp "$REPO_ROOT/claude/managed-settings.json" "$repo/claude/managed-settings.json"

  cat > "$repo/install/manifest.tsv" <<'MANIFEST'
link-file	claude/settings.json	.claude/settings.json
link-file	claude/CLAUDE.md	.claude/CLAUDE.md
link-dir	claude/rules	.claude/rules
link-dir	claude/agents	.claude/agents
link-dir	claude/skills	.claude/skills
link-file	codex/AGENTS.md	.codex/AGENTS.md
link-dir	shared/rules	.agents/rules
link-dir	shared/bin	.agents/bin
MANIFEST

  printf '# fixture\n@~/.agents/rules/rule-a.md\n' > "$repo/claude/CLAUDE.md"
  printf '# fixture\n' > "$repo/claude/.gitignore"
  printf '# fixture\n' > "$repo/claude/README.md"
  printf '# fixture\n' > "$repo/claude/rules/sample.md"
  printf '# fixture\n' > "$repo/claude/agents/sample.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/claude/githooks/pre-commit"
  chmod +x "$repo/claude/githooks/pre-commit"
  cat > "$repo/claude/skills/sample-skill/SKILL.md" <<'SKILL'
---
name: sample-skill
description: Fixture skill.
allowed-tools: Read Grep
---
# Sample
SKILL
  cat > "$repo/codex/AGENTS.md" <<'CODEX'
# fixture
<!-- BEGIN shared:rule-b -->
# synchronized
<!-- END shared:rule-b -->
CODEX

  cat > "$repo/shared/bin/sync-shared-rules.sh" <<'SYNC'
#!/usr/bin/env bash
SYNC_MAP=$(cat <<'EOF'
rule-b	codex/AGENTS.md
EOF
)
SYNC
  chmod +x "$repo/shared/bin/sync-shared-rules.sh"
  printf '# imported\n' > "$repo/shared/rules/rule-a.md"
  printf '# synchronized\n' > "$repo/shared/rules/rule-b.md"
  cat > "$repo/docs/contracts/context-consumers.tsv" <<'CONSUMERS'
rule	load_mode	consumer	trigger
rule-a	always	claude/CLAUDE.md	all tasks
rule-b	always	codex/AGENTS.md	all tasks
CONSUMERS
  cat > "$repo/docs/contracts/skill-authority.tsv" <<'AUTHORITY'
skill	mode	repo_write	state_write	commit	push	github_write	delete	notes
sample-skill	default	deny	deny	deny	deny	deny	deny	fixture read
AUTHORITY

  printf '# no active waivers\n' > "$repo/docs/waivers/settings-waivers.tsv"
  printf 'fixture-env\n' > "$repo/docs/waivers/environments.txt"
  cp "$REPO_ROOT/docs/requirements/source-manifest.sha256" "$repo/docs/requirements/source-manifest.sha256"
  local sha
  sha="$(awk '{print $1}' "$repo/docs/requirements/source-manifest.sha256")"
  printf '# Requirements source\n\nSHA-256: `%s`\n' "$sha" > "$repo/docs/requirements/requirements-transcription-260722.md"
  printf 'fixture /home/example is intentionally under tests\n' > "$repo/tests/absolute-home-fixture.txt"

  # Minimal, schema-complete inventory for the validator fixture. Coverage is
  # generated from this fixture's actual operational paths.
  python3 - "$repo" <<'PYINV'
import csv, os, sys
from pathlib import Path
root=Path(sys.argv[1])
fields=["id","category","before_path","after_path","archive_path","tags","purpose","needed","builtin_alternative","overlap","context_load","false_positive","failure_impact","verification","low_cost_model","deterministic_replacement","disposition","evidence"]
paths=[]
for base in ["scripts","tests","claude/bin","claude/hooks","claude/scripts","claude/githooks",".github/workflows","install"]:
    d=root/base
    if not d.exists(): continue
    for dirpath, _, files in os.walk(d):
        for name in files:
            rel=str((Path(dirpath)/name).relative_to(root))
            if rel.startswith("tests/") and not (rel.endswith(".sh") or "/lib/" in rel):
                continue
            paths.append(rel)
for rel in ["bootstrap.sh","claude/settings.json","claude/managed-settings.json","codex/hooks.json"]:
    if (root/rel).exists(): paths.append(rel)
rows=[]
for i,rel in enumerate(sorted(set(paths)),1):
    rows.append({"id":f"fixture:{i}","category":"fixture","before_path":rel,"after_path":rel,"archive_path":"-","tags":"","purpose":f"validate {rel}","needed":"high","builtin_alternative":"none","overlap":"none","context_load":"test-only","false_positive":"low","failure_impact":"medium","verification":"fixture validator","low_cost_model":"n/a","deterministic_replacement":"yes","disposition":"keep","evidence":"test fixture"})
out=root/"docs/reports/inventory-elements.tsv"
with out.open("w",encoding="utf-8",newline="") as fh:
    w=csv.DictWriter(fh,fieldnames=fields,delimiter="\t",lineterminator="\n"); w.writeheader(); w.writerows(rows)
PYINV

  git -C "$repo" init -q
  git -C "$repo" add -A
}

run_validate() {
  local repo="$1"
  mkdir -p "$repo/.home"
  env -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME \
    HOME="$repo/.home" "$repo/scripts/validate-layout.sh"
}

run_case() {
  local name="$1" mutate="$2" expected="$3"
  local repo="$SANDBOX/$name" out rc=0
  build_fixture "$repo"
  eval "$mutate"
  out="$(run_validate "$repo" 2>&1)" || rc=$?
  if [[ "$expected" == PASS ]]; then
    assert_zero "$name passes" "$rc"
    assert_contains "$name emits PASS" "$out" "PASS: no layout violations found"
  else
    assert_nonzero "$name fails" "$rc"
    assert_contains "$name reports contract" "$out" "$expected"
  fi
}

run_case valid ':' PASS
run_case forbidden-runtime \
  'printf "{}\n" > "$repo/shared/bin/history.jsonl"; git -C "$repo" add shared/bin/history.jsonl' \
  'forbidden runtime name tracked: shared/bin/history.jsonl'
run_case manifest-four-columns \
  'printf "link-file\tclaude/CLAUDE.md\t.claude/duplicate.md\textra\n" >> "$repo/install/manifest.tsv"' \
  '3列が必要です(実際: 4列)'
run_case codex-skill-file-link \
  'printf "link-file\tcodex/AGENTS.md\t.agents/skills/sample-skill/SKILL.md\n" >> "$repo/install/manifest.tsv"' \
  'Codex skill は SKILL.md 単体ではなく実ファイルを含むディレクトリを link-dir で配布してください'
run_case manifest-orphan \
  'printf "orphan\n" > "$repo/claude/orphan.md"; git -C "$repo" add claude/orphan.md' \
  'tracked file not covered by manifest or allowlist: claude/orphan.md'
run_case unconsumed-rule \
  'printf "orphan\n" > "$repo/shared/rules/orphan.md"; git -C "$repo" add shared/rules/orphan.md' \
  'shared rule has no context consumer declaration: orphan'
run_case user-security-key \
  'jq ". + {sandbox:{enabled:false}}" "$repo/claude/settings.json" > "$repo/u"; mv "$repo/u" "$repo/claude/settings.json"' \
  'user settings must not carry security policy keys'
run_case missing-managed-lock \
  'jq "del(.allowManagedPermissionRulesOnly)" "$repo/claude/managed-settings.json" > "$repo/m"; mv "$repo/m" "$repo/claude/managed-settings.json"' \
  'managed settings require allowManagedPermissionRulesOnly=true'
run_case managed-bash-allow \
  'jq ".permissions.allow += [\"Bash(gh auth status)\"]" "$repo/claude/managed-settings.json" > "$repo/m"; mv "$repo/m" "$repo/claude/managed-settings.json"' \
  'managed permissions must not pre-approve Bash commands'
run_case sandbox-auto-allow \
  'jq ".sandbox.autoAllowBashIfSandboxed=false" "$repo/claude/managed-settings.json" > "$repo/m"; mv "$repo/m" "$repo/claude/managed-settings.json"' \
  'managed sandbox.autoAllowBashIfSandboxed must be true'
run_case bypass-default \
  'jq ".permissions.defaultMode=\"default\"" "$repo/claude/managed-settings.json" > "$repo/m"; mv "$repo/m" "$repo/claude/managed-settings.json"' \
  'managed permissions.defaultMode must be "bypassPermissions"'
run_case sandbox-enabled \
  'jq ".sandbox.enabled=true" "$repo/claude/managed-settings.json" > "$repo/m"; mv "$repo/m" "$repo/claude/managed-settings.json"' \
  'managed sandbox.enabled must be false'
run_case missing-helper-read \
  'jq ".sandbox.filesystem.allowRead -= [\"~/.claude/bin\"]" "$repo/claude/managed-settings.json" > "$repo/m"; mv "$repo/m" "$repo/claude/managed-settings.json"' \
  'managed allowRead is missing required toolkit paths: ~/.claude/bin'
run_case preallowed-domain \
  'jq ".sandbox.network.allowedDomains=[\"example.com\"]" "$repo/claude/managed-settings.json" > "$repo/m"; mv "$repo/m" "$repo/claude/managed-settings.json"' \
  'managed network allowedDomains must be empty/absent'
run_case broad-git-deny \
  'jq ".permissions.deny += [\"Edit(.git/**)\"]" "$repo/claude/managed-settings.json" > "$repo/m"; mv "$repo/m" "$repo/claude/managed-settings.json"' \
  "git-workflow-breaking deny: 'Edit(.git/**)'"
run_case source-hash-mismatch \
  'printf "# wrong transcription\n" > "$repo/docs/requirements/requirements-transcription-260722.md"' \
  'requirements transcription does not reference source manifest SHA-256'
run_case invalid-waiver-schema \
  'printf "claude/managed-settings.json\tpattern\tfixture-env\t2099-01-01\n" > "$repo/docs/waivers/settings-waivers.tsv"' \
  'waiver schema:'
run_case invalid-skill-schema \
  'sed -i "s/name: sample-skill/name: wrong-name/" "$repo/claude/skills/sample-skill/SKILL.md"' \
  "name 'wrong-name' != skill directory 'sample-skill'"
run_case invalid-shared-variant-skill-schema \
  'mkdir -p "$repo/shared/skills/codex/sample-skill"; printf "%s\n" "---" "name: wrong-name" "description: Invalid nested fixture." "---" "# Sample" > "$repo/shared/skills/codex/sample-skill/SKILL.md"' \
  "skill schema: shared/skills/codex/sample-skill/SKILL.md: name 'wrong-name' != skill directory 'sample-skill'"
run_case active-skill-line-budget \
  'for _ in $(seq 1 151); do printf "line\n" >> "$repo/claude/skills/sample-skill/SKILL.md"; done' \
  'active skill budget: claude/skills/sample-skill/SKILL.md has'
run_case missing-skill-reference \
  'printf "\n[missing](references/missing.md)\n" >> "$repo/claude/skills/sample-skill/SKILL.md"' \
  'missing Markdown reference: claude/skills/sample-skill/SKILL.md -> references/missing.md'
run_case missing-consumer-declaration \
  'sed -i "/^rule-b\t/d" "$repo/docs/contracts/context-consumers.tsv"' \
  'shared rule has no context consumer declaration: rule-b'
run_case invalid-authority-value \
  'sed -i "s/sample-skill\tdefault\tdeny/sample-skill\tdefault\tmaybe/" "$repo/docs/contracts/skill-authority.tsv"' \
  'repo_write must be allow or deny'
run_case stale-reference \
  'printf "/gh:start\n" >> "$repo/claude/rules/sample.md"' \
  'stale reference in claude/rules/sample.md'
run_case unsupported-runtime-context-adapter \
  'mkdir -p "$repo/shared/skills/agmsg/templates"; printf "# unsupported\n" > "$repo/shared/skills/agmsg/templates/cmd.gemini.md"; git -C "$repo" add "$repo/shared/skills/agmsg/templates/cmd.gemini.md"' \
  'unsupported runtime context adapter is active: shared/skills/agmsg/templates/cmd.gemini.md'
run_case non-executable-script \
  'printf "#!/usr/bin/env bash\n" > "$repo/scripts/extra.sh"; chmod 0644 "$repo/scripts/extra.sh"; git -C "$repo" add scripts/extra.sh' \
  'non-executable direct-execution script: 100644 scripts/extra.sh'
run_case inventory-missing-element \
  'printf "#!/usr/bin/env bash\nexit 0\n" > "$repo/scripts/uninventoried.sh"; chmod +x "$repo/scripts/uninventoried.sh"; git -C "$repo" add scripts/uninventoried.sh' \
  'operational element missing from inventory: scripts/uninventoried.sh'
run_case unsupported-model-syntax \
  'printf -- "---\n\"model\": opus\n---\n" > "$repo/claude/agents/bad.md"; git -C "$repo" add claude/agents/bad.md' \
  'model pin scan failed:'
run_case runtime-model-pin-in-settings \
  'jq ".model=\"claude-foo-9[1m]\"" "$repo/claude/settings.json" > "$repo/u"; mv "$repo/u" "$repo/claude/settings.json"' \
  PASS
run_case agent-full-model-pin \
  'printf -- "---\nname: pinned\nmodel: claude-foo-1\n---\n" > "$repo/claude/agents/pinned.md"; git -C "$repo" add claude/agents/pinned.md' \
  'dangerous setting without waiver: claude/agents/pinned.md:3: full model pin '"'"'claude-foo-1'"'"''

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
