#!/usr/bin/env bash
# discover-runtime: FAIL / WARN conditions on fixture HOME + stub CLIs (no live settings, no model calls),
# including the §2.4-1 upper-directory AGENTS.md and the §2.4-4 settings drift, snapshot rotation,
# and change detection against the previous snapshot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DISCOVER="$REPO_ROOT/scripts/discover-runtime.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

ROUTE_HEADER=$'role\truntime\tlauncher\tmodel\teffort\ttargets\tfallback\tretires_at\tevidence\tverified_at\tadaptation'

build_fixture() {
  local base="$1"
  local repo="$base/repo" home="$base/home"
  mkdir -p "$repo/install" "$repo/claude" "$repo/docs/contracts" "$home/.claude/projects/p" "$home/.codex" \
    "$base/managed" "$base/win" "$base/bin" "$base/state"
  printf 'link-file\tclaude/CLAUDE.md\t.claude/CLAUDE.md\n' > "$repo/install/manifest.tsv"
  printf '# fixture\n' > "$repo/claude/CLAUDE.md"
  # D5: the live user settings are a regular file written by Claude Code
  printf '{"autoMemoryEnabled": false, "modelSettings": {"claude-fable-5-1": {"effortLevel": "high"}}, "model": "fable[1m]"}\n' > "$home/.claude/settings.json"
  {
    printf '%s\n' "$ROUTE_HEADER"
    printf 'claude-main\tclaude\tmain session\tfable\thigh\tclaude/CLAUDE.md~lead\topus\t\tfixture\t2026-09-25\t\n'
    printf 'claude-explore\tclaude\tAgent(Explore)\thaiku\t-\tclaude/agents/explore.md#model\tsonnet\tnot-before:2026-10-15\tfixture\t2026-09-25\t\n'
    printf 'codex-implementer\tcodex\tcodex-companion task\tgpt-6-astra\tmedium\tx.env#M,E\tgpt-6-astra/low\t\tfixture\t2026-09-25\t\n'
    printf 'codex-default-subagent\tcodex\tspawn_agent (built-in)\tgpt-5.6-sol\thigh\t~/.codex/config.toml#agents.default_subagent_model\t\t\tfixture\t2026-09-25\t\n'
  } > "$repo/docs/contracts/model-routing.tsv"
  git -C "$repo" init -q
  ln -s "$repo/claude/CLAUDE.md" "$home/.claude/CLAUDE.md"
  printf '%s\n' '{"type":"assistant","message":{"model":"claude-fable-5-1","content":[]}}' \
    '{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","content":[]}}' > "$home/.claude/projects/p/s.jsonl"
  cat > "$home/.codex/models_cache.json" <<'JSON'
{"fetched_at": "2026-09-25T00:00:00Z", "client_version": "0.157.0", "models": [
 {"slug": "gpt-6-astra", "default_reasoning_level": "medium", "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}, {"effort": "xhigh"}, {"effort": "max"}, {"effort": "ultra"}]},
 {"slug": "gpt-5.6-sol", "default_reasoning_level": "low", "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}, {"effort": "xhigh"}]}
]}
JSON
  printf '{"latest_version": "0.157.0"}\n' > "$home/.codex/version.json"
  printf 'model = "gpt-6-astra"\nmodel_reasoning_effort = "medium"\n[agents]\ndefault_subagent_model = "gpt-5.6-sol"\ndefault_subagent_reasoning_effort = "high"\n' > "$home/.codex/config.toml"
  printf '{}\n' > "$base/win/managed-settings.json"
  printf '#!/usr/bin/env bash\necho "2.1.282 (Claude Code)"\n' > "$base/bin/claude"
  printf '#!/usr/bin/env bash\necho "codex-cli ${STUB_CODEX_VERSION:-0.157.0}"\n' > "$base/bin/codex"
  chmod +x "$base/bin/claude" "$base/bin/codex"
}

OUT=""
RC=0
discover() {
  local base="$1"
  shift
  RC=0
  OUT="$(env -u AGENTS_TOOLKIT_SLACK_NOTIFY PATH="$base/bin:$PATH" HOME="$base/home" XDG_STATE_HOME="$base/state" \
    AGENTS_TOOLKIT_REPO="$base/repo" AGENTS_TOOLKIT_MANAGED_DIR="$base/managed" \
    AGENTS_TOOLKIT_WINDOWS_MANAGED_DIR="$base/win" AGENTS_TOOLKIT_TODAY=2026-09-25 \
    "$DISCOVER" "$@" 2>&1)" || RC=$?
}

expect() {
  local name="$1" rc_kind="$2" needle="$3"
  if [[ "$rc_kind" == zero && "$RC" -ne 0 ]]; then ng "$name: expected exit 0, got $RC: $OUT"; return; fi
  if [[ "$rc_kind" == nonzero && "$RC" -eq 0 ]]; then ng "$name: expected non-zero exit"; return; fi
  if [[ "$OUT" == *"$needle"* ]]; then ok "$name"; else ng "$name: missing '$needle' in: $OUT"; fi
}

new_case() {
  CASE="$SANDBOX/$1"
  build_fixture "$CASE"
}

ROUTES='$CASE/repo/docs/contracts/model-routing.tsv'

new_case clean
discover "$CASE"
expect "clean: FAIL なし" zero "OK: instructionFiles is the default claude-md-or-agents-md"
if [[ "$OUT" != *"FAIL:"* ]]; then ok "clean: FAIL 行が無い"; else ng "clean: unexpected FAIL: $OUT"; fi
if [[ -f "$CASE/state/agents-toolkit/runtime-snapshot.json" ]] && jq -e '.alias_resolution.fable.model == "claude-fable-5-1"' "$CASE/state/agents-toolkit/runtime-snapshot.json" >/dev/null; then
  ok "clean: snapshot を書き、alias の解決先を記録する"
else
  ng "clean: snapshot が無いか alias が記録されていない"
fi
discover "$CASE"
if [[ -f "$CASE/state/agents-toolkit/runtime-snapshot.prev.json" ]]; then ok "clean: 2回目は前回分を .prev に退避する"; else ng "clean: prev snapshot missing"; fi

new_case no-write
discover "$CASE" --no-write
if [[ ! -e "$CASE/state/agents-toolkit/runtime-snapshot.json" && "$OUT" != *"snapshot:"* ]]; then ok "--no-write は snapshot を書かない"; else ng "--no-write wrote a snapshot"; fi

new_case upper-agents-md
printf '# upper\n' > "$CASE/home/AGENTS.md"
discover "$CASE"
expect "§2.4-1: 上位ディレクトリの AGENTS.md を検出する" zero "WARN: upper-directory instruction file is loaded as project instructions in repos below it: $CASE/home/AGENTS.md"

new_case settings-live
discover "$CASE"
if [[ "$OUT" != *"settings.json is a symlink"* ]]; then ok "D5: 通常ファイルの live settings.json は WARN しない"; else ng "D5: regular live settings warned"; fi
printf '{"autoMemoryEnabled": false, "skillOverrides": {"gh-pr": "off"}, "modelSettings": {"claude-fable-5-1": {"effortLevel": "high"}}}\n' > "$CASE/home/.claude/settings.json"
discover "$CASE"
expect "§2.4-4: UI の model と routing の不一致" zero "WARN: live main model is unset (account default) (UI-managed); routing claude-main is fable"
mv "$CASE/home/.claude/settings.json" "$CASE/user-settings.json"
ln -s "$CASE/user-settings.json" "$CASE/home/.claude/settings.json"
discover "$CASE"
expect "D5: symlink の live settings.json は旧構成として WARN" zero "WARN: live ~/.claude/settings.json is a symlink; D5 makes the live file canonical"

new_case catalog-missing
sed -i 's/\tgpt-6-astra\tmedium\t/\tgpt-6-sol\tmedium\t/' "$CASE/repo/docs/contracts/model-routing.tsv"
discover "$CASE"
expect "catalog に無い codex model は FAIL" nonzero "FAIL: routing codex-implementer: model gpt-6-sol is not in the live Codex catalog"

new_case launcher-effort
sed -i 's/\tgpt-6-astra\tmedium\t/\tgpt-6-astra\tmax\t/' "$CASE/repo/docs/contracts/model-routing.tsv"
discover "$CASE"
expect "companion が受け付けない effort は FAIL" nonzero "FAIL: routing codex-implementer: launcher codex-companion task does not accept effort max"

new_case catalog-effort
sed -i 's/\tgpt-5.6-sol\thigh\t/\tgpt-5.6-sol\tultra\t/' "$CASE/repo/docs/contracts/model-routing.tsv"
discover "$CASE"
expect "catalog のモデルが対応しない effort は FAIL" nonzero "FAIL: routing codex-default-subagent: gpt-5.6-sol does not support effort ultra"

new_case retire-soon
sed -i 's/not-before:2026-10-15/2026-10-10/' "$CASE/repo/docs/contracts/model-routing.tsv"
discover "$CASE"
expect "確定した退役日まで30日未満は FAIL" nonzero "FAIL: routing claude-explore: haiku retires on 2026-10-10 (15 days left)"

new_case retire-not-before
discover "$CASE"
expect "not-before の退役は WARN" zero "WARN: routing claude-explore: haiku retires not before 2026-10-15"

new_case instruction-unknown
printf '{"autoMemoryEnabled": false, "pluginConfigs": {"agents-md@builtin": {"options": {"instructionFiles": "agents-md-only"}}}}\n' > "$CASE/home/.claude/settings.json"
discover "$CASE"
expect "未知の instructionFiles は FAIL" nonzero "FAIL: instructionFiles has an unknown value 'agents-md-only' (from user:pluginConfigs.agents-md@builtin.options.instructionFiles)"

new_case instruction-nondefault
printf '{"pluginConfigs": {"agents-md@builtin": {"options": {"instructionFiles": "claude-md-and-agents-md"}}}}\n' > "$CASE/managed/managed-settings.json"
discover "$CASE"
expect "既定以外の instructionFiles は WARN（設定元つき）" zero "WARN: instructionFiles is claude-md-and-agents-md (from managed:managed-settings.json:pluginConfigs.agents-md@builtin.options.instructionFiles)"

new_case agents-md-disabled
printf '{"autoMemoryEnabled": false, "enabledPlugins": {"agents-md@builtin": false}}\n' > "$CASE/home/.claude/settings.json"
discover "$CASE"
expect "agents-md plugin の無効化は WARN（K14）" zero "WARN: built-in agents-md plugin is disabled in user"

new_case auto-memory
printf '{"autoMemoryEnabled": true}\n' > "$CASE/home/.claude/settings.json"
discover "$CASE"
expect "autoMemoryEnabled が false でなければ FAIL" nonzero "FAIL: autoMemoryEnabled is True (from user), must be false (EX-004)"
printf '{"autoMemoryEnabled": false}\n' > "$CASE/managed/managed-settings.json"
discover "$CASE"
expect "managed の autoMemoryEnabled=false が user より優先される（EX-004）" zero "OK: autoMemoryEnabled is false (from managed; EX-004)"

new_case alias-change
discover "$CASE"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-fable-5-2","content":[]}}' > "$CASE/home/.claude/projects/p/t.jsonl"
touch -d '+1 minute' "$CASE/home/.claude/projects/p/t.jsonl"
discover "$CASE"
expect "alias の解決先の変化は WARN" zero "WARN: alias fable resolution changed: claude-fable-5-1 -> claude-fable-5-2"
expect "alias の変化は Level 2 候補" zero "Level 2 候補: alias fable resolution changed"

new_case codex-config-change
discover "$CASE"
sed -i 's/^model = "gpt-6-astra"/model = "gpt-6-sol"/' "$CASE/home/.codex/config.toml"
discover "$CASE"
expect "Codex config の既定の変化は WARN（K2）" zero "WARN: Codex config default changed without the routing gate: gpt-6-astra/medium -> gpt-6-sol/medium"

new_case windows-managed
printf '{"env": {"X": "1"}}\n' > "$CASE/win/managed-settings.json"
discover "$CASE"
expect "Windows host の managed が空でなければ WARN" zero "WARN: Windows host managed settings are not empty: windows-managed:managed-settings.json"

new_case cli-outdated
printf '{"latest_version": "0.158.0"}\n' > "$CASE/home/.codex/version.json"
discover "$CASE"
expect "installed の Codex CLI が古ければ WARN" zero "WARN: Codex CLI codex-cli 0.157.0 is older than the latest stable 0.158.0"

new_case plugin-change
mkdir -p "$CASE/home/.claude/plugins/cache/codex/1.0.6"
printf 'a\n' > "$CASE/home/.claude/plugins/cache/codex/1.0.6/script.mjs"
printf '{"plugins": {"codex@openai-codex": [{"version": "1.0.6", "gitCommitSha": "db52e28", "installPath": "%s"}]}}\n' "$CASE/home/.claude/plugins/cache/codex/1.0.6" > "$CASE/home/.claude/plugins/installed_plugins.json"
discover "$CASE"
printf 'patched\n' > "$CASE/home/.claude/plugins/cache/codex/1.0.6/script.mjs"
discover "$CASE"
expect "plugin の patch hash の変化は WARN" zero "WARN: codex-plugin-cc changed: 1.0.6 -> 1.0.6 (cache hash changed: True)"

new_case routing-missing
rm "$CASE/repo/docs/contracts/model-routing.tsv"
discover "$CASE"
expect "routing 表が無ければ FAIL" nonzero "FAIL: routing table missing or empty"

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
