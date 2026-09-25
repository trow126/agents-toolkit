#!/usr/bin/env bash
# audit-context-runtime.sh のCLI出力・discovery・negative fixtureを検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT="$REPO_ROOT/scripts/audit-context-runtime.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0

ok() {
  echo "ok: $1"
}

ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    ok "$desc"
  else
    ng "$desc (missing: $needle)"
  fi
}

assert_exit_zero() {
  local desc="$1" rc="$2"
  [[ "$rc" -eq 0 ]] && ok "$desc" || ng "$desc (exit=$rc)"
}

assert_exit_nonzero() {
  local desc="$1" rc="$2"
  [[ "$rc" -ne 0 ]] && ok "$desc" || ng "$desc (expected non-zero)"
}

FIXTURE_REPO="$SANDBOX/repo"
FIXTURE_HOME="$SANDBOX/home"
STUB_BIN="$SANDBOX/bin"
mkdir -p \
  "$FIXTURE_REPO/install" \
  "$FIXTURE_REPO/claude" \
  "$FIXTURE_REPO/shared/skills/claude-sample/references" \
  "$FIXTURE_REPO/shared/skills/codex-sample" \
  "$FIXTURE_REPO/shared/skills/codex-manual/agents" \
  "$FIXTURE_HOME/.claude/skills" \
  "$FIXTURE_HOME/.agents/skills" \
  "$STUB_BIN"
printf '{"autoMemoryEnabled":false}\n' > "$FIXTURE_REPO/claude/managed-settings.json"
printf '%s\n' '# Claude fixture' '' '[Workflow](references/workflow.md)' > "$FIXTURE_REPO/shared/skills/claude-sample/SKILL.md"
printf '%s\n' '# Workflow fixture' > "$FIXTURE_REPO/shared/skills/claude-sample/references/workflow.md"
printf '%s\n' '# Codex fixture' > "$FIXTURE_REPO/shared/skills/codex-sample/SKILL.md"
printf 'link-dir\tshared/skills/claude-sample\t.claude/skills/claude-sample\n' > "$FIXTURE_REPO/install/manifest.tsv"
printf 'link-dir\tshared/skills/codex-sample\t.agents/skills/codex-sample\n' >> "$FIXTURE_REPO/install/manifest.tsv"
printf '%s\n' '# Codex manual-only fixture' > "$FIXTURE_REPO/shared/skills/codex-manual/SKILL.md"
printf '%s\n' 'policy:' '  allow_implicit_invocation: false' > "$FIXTURE_REPO/shared/skills/codex-manual/agents/openai.yaml"
printf 'link-dir\tshared/skills/codex-manual\t.agents/skills/codex-manual\n' >> "$FIXTURE_REPO/install/manifest.tsv"
mkdir -p "$FIXTURE_REPO/codex/profiles" "$FIXTURE_HOME/.codex"
cp "$REPO_ROOT/codex/profiles/toolkit-implementer.config.toml" "$FIXTURE_REPO/codex/profiles/"
ln -s "$FIXTURE_REPO/codex/profiles/toolkit-implementer.config.toml" "$FIXTURE_HOME/.codex/toolkit-implementer.config.toml"
printf 'link-file\tcodex/profiles/toolkit-implementer.config.toml\t.codex/toolkit-implementer.config.toml\n' >> "$FIXTURE_REPO/install/manifest.tsv"
cp "$REPO_ROOT/codex/profiles/toolkit-divergent.config.toml" "$FIXTURE_REPO/codex/profiles/"
ln -s "$FIXTURE_REPO/codex/profiles/toolkit-divergent.config.toml" "$FIXTURE_HOME/.codex/toolkit-divergent.config.toml"
printf 'link-file\tcodex/profiles/toolkit-divergent.config.toml\t.codex/toolkit-divergent.config.toml\n' >> "$FIXTURE_REPO/install/manifest.tsv"
ln -s "$FIXTURE_REPO/shared/skills/claude-sample" "$FIXTURE_HOME/.claude/skills/claude-sample"
ln -s "$FIXTURE_REPO/shared/skills/codex-sample" "$FIXTURE_HOME/.agents/skills/codex-sample"

cat > "$STUB_BIN/claude" <<'CLAUDE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "plugin" && "${2:-}" == "list" ]]; then
  if [[ "${STUB_CLAUDE_SUPERPOWERS:-off}" == "on" ]]; then
    printf '[{"id":"superpowers@claude-plugins-official","enabled":true}]\n'
  else
    printf '[{"id":"superpowers@claude-plugins-official","enabled":false}]\n'
  fi
  exit 0
fi
debug_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--debug-file" ]]; then
    debug_file="$2"
    shift 2
  else
    shift
  fi
done
printf 'Loaded 1 unique skills (1 unconditional)\n' > "$debug_file"
printf '{"num_turns":0,"total_cost_usd":0}\n'
CLAUDE

cat > "$STUB_BIN/codex" <<'CODEX'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "plugin" && "${2:-}" == "list" ]]; then
  printf '{"installed":[{"pluginId":"superpowers@openai-curated","installed":true,"enabled":false}]}\n'
elif [[ "${1:-}" == "features" && "${2:-}" == "list" ]]; then
  printf 'memories stable false\n'
elif [[ "${1:-}" == "-p" && "${2:-}" == "toolkit-divergent" && "${3:-}" == "debug" && "${4:-}" == "prompt-input" ]]; then
  # divergent profile: developer instructions and no skill list unless STUB_DIVERGENT_BAD=skills
  first='You are the Codex divergent worker for one /break-consensus --cross run. Follow the prompt and these rules:'
  extra=''
  [[ "${STUB_DIVERGENT_BAD:-}" == skills ]] && extra=',{"type":"input_text","text":"<skills_instructions>\n- codex-sample: fixture (file: r0/codex-sample/SKILL.md)\n</skills_instructions>"}'
  printf '[{"type":"message","role":"developer","content":[{"type":"input_text","text":"%s"}%s]}]\n' "$first" "$extra"
elif [[ "${1:-}" == "-p" && "${3:-}" == "debug" && "${4:-}" == "prompt-input" ]]; then
  # profile prompt: developer instructions first unless STUB_PROFILE_BAD names a failure
  first='You are the implementer for one delegated task. Follow the task prompt and these rules:'
  [[ "${STUB_PROFILE_BAD:-}" == order ]] && first='Some other developer text.'
  listed='codex-sample'
  [[ "${STUB_PROFILE_BAD:-}" == skill ]] && listed='codex-sample gh-pr'
  body='<skills_instructions>\n### Available skills\n'
  for name in $listed; do body="${body}- ${name}: fixture (file: r0/${name}/SKILL.md)\n"; done
  extra=''
  [[ "${STUB_PROFILE_BAD:-}" == multi ]] && extra=',{"type":"input_text","text":"<multi_agent_role>x"}'
  printf '[{"type":"message","role":"developer","content":[{"type":"input_text","text":"%s"},{"type":"input_text","text":"%s</skills_instructions>"}%s]}]\n' "$first" "$body" "$extra"
elif [[ "${1:-}" == "debug" && "${2:-}" == "prompt-input" ]]; then
  # 0.157.0 lists skills by name with root-relative paths, never the repo source path
  body='<skills_instructions>\n### Available skills\n'
  for name in ${STUB_CODEX_LISTED-codex-sample}; do
    body="${body}- ${name}: fixture (file: r0/${name}/SKILL.md)\n"
  done
  printf '[{"type":"message","role":"developer","content":[{"type":"input_text","text":"%s</skills_instructions>"}]}]\n' "$body"
else
  echo "unexpected codex invocation: $*" >&2
  exit 2
fi
CODEX
chmod +x "$STUB_BIN/claude" "$STUB_BIN/codex"

run_audit() {
  env \
    PATH="$STUB_BIN:$PATH" \
    HOME="$FIXTURE_HOME" \
    FIXTURE_REPO="$FIXTURE_REPO" \
    AGENTS_TOOLKIT_REPO="$FIXTURE_REPO" \
    "$AUDIT"
}

out=""; rc=0
out="$(run_audit 2>&1)" || rc=$?
assert_exit_zero "準拠fixtureは成功する" "$rc"
assert_contains "Claude memory offを確認する" "$out" "PASS: Claude native auto memory is disabled"
assert_contains "Codex discoveryを確認する" "$out" "PASS: Codex prompt discovery contains all manifest skills"
assert_contains "implementer profile の prompt を確認する（C.2）" "$out" "PASS: Codex implementer profile prompt drops disabled skills and multi-agent instructions"
for bad in order skill multi; do
  out=""; rc=0
  out="$(STUB_PROFILE_BAD="$bad" run_audit 2>&1)" || rc=$?
  assert_exit_nonzero "implementer profile の違反（$bad）は失敗する" "$rc"
done
out=""; rc=0
out="$(STUB_PROFILE_BAD=skill run_audit 2>&1)" || rc=$?
assert_contains "無効にした skill の残存を名前で示す" "$out" "FAIL: Codex implementer profile: profile-disabled skill is still listed: gh-pr"
out=""; rc=0
out="$(run_audit 2>&1)" || rc=$?
assert_contains "divergent profile の prompt を確認する（C.2、D7）" "$out" "PASS: Codex divergent profile prompt drops the skill list and multi-agent instructions"
out=""; rc=0
out="$(STUB_DIVERGENT_BAD=skills run_audit 2>&1)" || rc=$?
assert_exit_nonzero "divergent profile に skill の一覧が残れば失敗する" "$rc"
assert_contains "残った skill の一覧を示す" "$out" "FAIL: Codex divergent profile: skill list is still injected: codex-sample"

out=""; rc=0
out="$(STUB_CODEX_LISTED="" run_audit 2>&1)" || rc=$?
assert_exit_nonzero "Codex 一覧に toolkit skill が無ければ失敗する" "$rc"
assert_contains "欠けた skill を名前で示す" "$out" "FAIL: Codex prompt discovery is missing toolkit skill: codex-sample"

out=""; rc=0
out="$(STUB_CODEX_LISTED="codex-sample codex-manual" run_audit 2>&1)" || rc=$?
assert_exit_nonzero "manual-only skill が一覧に出たら失敗する" "$rc"
assert_contains "manual-only 違反を示す" "$out" "FAIL: Codex lists manual-only skill (allow_implicit_invocation: false): codex-manual"

out=""; rc=0
out="$(STUB_CLAUDE_SUPERPOWERS=on run_audit 2>&1)" || rc=$?
assert_exit_nonzero "Claude superpowers有効時は失敗する" "$rc"
assert_contains "superpowers違反を明示する" "$out" "FAIL: Claude superpowers plugin is missing or enabled"

unlink "$FIXTURE_REPO/shared/skills/claude-sample/references/workflow.md"
out=""; rc=0
out="$(run_audit 2>&1)" || rc=$?
assert_exit_nonzero "Claude supporting file欠落時は失敗する" "$rc"
assert_contains "欠落したinstalled参照を明示する" "$out" "installed Markdown reference missing:"
printf '%s\n' '# Workflow fixture' > "$FIXTURE_REPO/shared/skills/claude-sample/references/workflow.md"

ln -s "$FIXTURE_REPO/claude/skills/deep-research-mode" "$FIXTURE_HOME/.claude/skills/deep-research-mode"
out=""; rc=0
out="$(run_audit 2>&1)" || rc=$?
assert_exit_nonzero "broken toolkit symlinkがあると失敗する" "$rc"
assert_contains "broken linkを明示する" "$out" "FAIL: broken toolkit symlink remains:"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
