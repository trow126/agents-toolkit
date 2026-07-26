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
  "$FIXTURE_REPO/shared/skills/claude-sample" \
  "$FIXTURE_REPO/shared/skills/codex-sample" \
  "$FIXTURE_HOME/.claude/skills" \
  "$FIXTURE_HOME/.agents/skills" \
  "$STUB_BIN"
printf '{"autoMemoryEnabled":false}\n' > "$FIXTURE_REPO/claude/settings.json"
printf '%s\n' '# Claude fixture' > "$FIXTURE_REPO/shared/skills/claude-sample/SKILL.md"
printf '%s\n' '# Codex fixture' > "$FIXTURE_REPO/shared/skills/codex-sample/SKILL.md"
printf 'link-dir\tshared/skills/claude-sample\t.claude/skills/claude-sample\n' > "$FIXTURE_REPO/install/manifest.tsv"
printf 'link-dir\tshared/skills/codex-sample\t.agents/skills/codex-sample\n' >> "$FIXTURE_REPO/install/manifest.tsv"
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
elif [[ "${1:-}" == "debug" && "${2:-}" == "prompt-input" ]]; then
  printf '[{"text":"%s/shared/skills/codex-sample/SKILL.md"}]\n' "$FIXTURE_REPO"
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

out=""; rc=0
out="$(STUB_CLAUDE_SUPERPOWERS=on run_audit 2>&1)" || rc=$?
assert_exit_nonzero "Claude superpowers有効時は失敗する" "$rc"
assert_contains "superpowers違反を明示する" "$out" "FAIL: Claude superpowers plugin is missing or enabled"

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
