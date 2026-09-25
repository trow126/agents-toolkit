#!/usr/bin/env bash
# /break-consensus --cross (D7, §6.6, appendix C.5 static part): break-consensus-cross prepare,
# codex, collect, and finish on a fixture repo with a stub `codex`, plus the skill's static
# contract. No model is called.
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

# A copy of the launcher and its references, so the route can be changed per case.
TOOLKIT="$SANDBOX/toolkit"
REFS="$TOOLKIT/shared/skills/break-consensus/references"
mkdir -p "$TOOLKIT/claude/bin" "$REFS"
cp "$REPO_ROOT/claude/bin/break-consensus-cross" "$REPO_ROOT/claude/bin/delegation_common.py" "$TOOLKIT/claude/bin/"
cp "$REPO_ROOT"/shared/skills/break-consensus/references/{cross.md,divergent-route.env,divergent.schema.json} "$REFS/"
CROSS="$TOOLKIT/claude/bin/break-consensus-cross"

export PYTHONDONTWRITEBYTECODE=1
export CODEX_HOME="$SANDBOX/codex-home" XDG_STATE_HOME="$SANDBOX/state" TMPDIR="$SANDBOX/tmp"
mkdir -p "$CODEX_HOME" "$TMPDIR" "$SANDBOX/stub"
cp "$REPO_ROOT/codex/profiles/toolkit-divergent.config.toml" "$CODEX_HOME/"
printf '# global Codex instructions fixture\n' > "$CODEX_HOME/AGENTS.md"
cat > "$CODEX_HOME/models_cache.json" <<'JSON'
{"models": [
 {"slug": "gpt-6-astra", "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}, {"effort": "ultra"}]},
 {"slug": "gpt-6-luna", "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}]}
]}
JSON

# stub codex: `--version`, and `exec` that records argv, stdin, and the cwd contents, writes a
# session rollout (model/effort/sandbox/cwd as launched unless STUB_MODEL overrides the model),
# prints thread.started, and writes the -o output per STUB_OUTPUT (valid | badhash | invalid).
# STUB_LEAVE=1 leaves a file in the cwd.
cat > "$SANDBOX/stub/codex" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then echo "codex-cli 0.157.0"; exit 0; fi
printf '%s\n' "$@" > "$STUB_ARGV"
cat > "$STUB_PROMPT"
out=""; dir="."; model=""; effort=""; sandbox=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -C) dir="$2"; shift 2 ;;
    -m) model="$2"; shift 2 ;;
    -s) sandbox="$2"; shift 2 ;;
    -c) effort="${2#model_reasoning_effort=}"; shift 2 ;;
    *) shift ;;
  esac
done
ls -A "$dir" > "$STUB_CWD_LIST"
[[ "${STUB_LEAVE:-}" == 1 ]] && touch "$dir/left-behind.txt"
thread="01a0cad0-0000-7000-8000-$(printf '%012d' "$RANDOM")"
mkdir -p "$CODEX_HOME/sessions/2026/09/25"
jq -cn --arg m "${STUB_MODEL:-$model}" --arg e "$effort" --arg s "$sandbox" --arg c "$dir" \
  '{type: "turn_context", payload: {model: $m, effort: $e, sandbox_policy: {type: $s}, cwd: $c}}' \
  > "$CODEX_HOME/sessions/2026/09/25/rollout-2026-09-25T00-00-00-$thread.jsonl"
echo "{\"type\":\"thread.started\",\"thread_id\":\"$thread\"}"
hash="$(sed -n 's/^brief_sha256: //p' "$STUB_PROMPT")"
case "${STUB_OUTPUT:-valid}" in
  valid) ;;
  badhash) hash="0000" ;;
  invalid) printf '%s\n' '{"brief_sha256":"x"}' > "$out"; echo '{"type":"turn.completed"}'; exit 0 ;;
esac
jq -n --arg h "$hash" '{brief_sha256: $h, consensus_baseline: ["cache the result"],
  candidates: [{title: "Invert who pays", generation_mechanism: "assumption_inversion",
    broken_assumption: "the caller pays", mechanism: "the callee pays", predicted_benefit: "fewer calls",
    failure_condition: "call volume unchanged"}], notes: ""}' > "$out"
echo '{"type":"turn.completed"}'
STUB
chmod +x "$SANDBOX/stub/codex"
export PATH="$SANDBOX/stub:$PATH" STUB_ARGV="$SANDBOX/argv" STUB_PROMPT="$SANDBOX/prompt" STUB_CWD_LIST="$SANDBOX/cwd-list"

REPO="$SANDBOX/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email fixture@example.invalid
git -C "$REPO" config user.name Fixture
git -C "$REPO" config commit.gpgsign false
printf 'base\n' > "$REPO/a.txt"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m base
BRIEF="$SANDBOX/brief.md"
printf 'How can we cut the retry storms in the job queue?\n' > "$BRIEF"
BRIEF_SHA="$(sha256sum "$BRIEF" | cut -d' ' -f1)"

RC=0; OUT=""
run() { RC=0; OUT="$("$@" 2>&1)" || RC=$?; }
expect_rc() { # desc want_rc needle
  if [[ "$RC" -eq "$2" && "$OUT" == *"$3"* ]]; then ok "$1"; else ng "$1 (rc=$RC, want $2 containing '$3'): $OUT"; fi
}
set_route() { printf 'CLAUDE_MODEL=%s\nCODEX_MODEL=%s\nCODEX_EFFORT=%s\n' "$1" "$2" "$3" > "$REFS/divergent-route.env"; }
claude_output() { # <run_dir> [hash]
  jq -n --arg h "${2:-$BRIEF_SHA}" '{brief_sha256: $h, consensus_baseline: ["add a circuit breaker"],
    candidates: [{title: "Queue forgets on purpose", generation_mechanism: "changed_principle",
      broken_assumption: "every job must run", mechanism: "drop duplicates by design", predicted_benefit: "no storm",
      failure_condition: "lost work is noticed"}], notes: ""}' > "$1/claude-output.json"
}
prepare() { # sets RUN from a successful prepare
  run "$CROSS" prepare "$BRIEF" --repo "$REPO"
  RUN="$(jq -r .run_dir <<< "$OUT" 2>/dev/null || true)"
}

# ---- prepare
printf 'secret brief\n' > "$REPO/brief.md"
run "$CROSS" prepare "$REPO/brief.md" --repo "$REPO"
expect_rc "repository の中の brief は拒否する" 1 "outside the repository"
rm "$REPO/brief.md"
: > "$SANDBOX/empty.md"
run "$CROSS" prepare "$SANDBOX/empty.md" --repo "$REPO"
expect_rc "空の brief は拒否する" 1 "brief is empty"
printf 'token ghp_%s\n' "$(printf 'a%.0s' {1..36})" > "$SANDBOX/secret.md"
run "$CROSS" prepare "$SANDBOX/secret.md" --repo "$REPO"
expect_rc "secret らしい brief は拒否する" 1 "contains a secret"
head -c 70000 /dev/zero | tr '\0' 'x' > "$SANDBOX/large.md"
run "$CROSS" prepare "$SANDBOX/large.md" --repo "$REPO"
expect_rc "大きすぎる brief は拒否する" 1 "larger than"
set_route opus gpt-6-astra ultra
run "$CROSS" prepare "$BRIEF" --repo "$REPO"
expect_rc "ultra は拒否する" 1 "ultra is not allowed"
set_route opus gpt-9 medium
run "$CROSS" prepare "$BRIEF" --repo "$REPO"
expect_rc "catalog に無いモデルは拒否する" 1 "not in the Codex catalog"
set_route opus gpt-6-luna high
run "$CROSS" prepare "$BRIEF" --repo "$REPO"
expect_rc "catalog に無い effort は拒否する" 1 "not supported by gpt-6-luna"
set_route opus gpt-6-astra medium
mv "$CODEX_HOME/toolkit-divergent.config.toml" "$SANDBOX/profile.toml"
run "$CROSS" prepare "$BRIEF" --repo "$REPO"
expect_rc "profile が無ければ拒否する" 1 "profile is not installed"
mv "$SANDBOX/profile.toml" "$CODEX_HOME/toolkit-divergent.config.toml"
[[ -z "$(ls -A "$XDG_STATE_HOME/agents-toolkit/break-consensus" 2>/dev/null)" ]] && ok "拒否した prepare は run を作らない" || ng "拒否した prepare が run を作った"

prepare
expect_rc "prepare は run を作る" 0 "\"brief_sha256\": \"$BRIEF_SHA\""
if [[ -n "$RUN" && "$RUN" == "$XDG_STATE_HOME/agents-toolkit/break-consensus/"* ]] && cmp -s "$BRIEF" "$RUN/brief.md"; then
  ok "brief を repository の外の state dir に複写する"
else
  ng "run dir が不正: $RUN"
fi
if grep -qxF "brief_sha256: $BRIEF_SHA" "$RUN/worker-prompt.md" && grep -qF 'retry storms' "$RUN/worker-prompt.md" &&
  ! grep -q '{{' "$RUN/worker-prompt.md"; then
  ok "worker prompt に brief と hash を埋め込む"
else
  ng "worker prompt が不正"
fi
if jq -e --arg h "$(sha256sum "$CODEX_HOME/AGENTS.md" | cut -d' ' -f1)" \
  '.codex_global_instructions.sha256["AGENTS.md"] == $h and .git_before.status == [] and .route.codex_effort == "medium"' \
  "$RUN/run.json" >/dev/null; then
  ok "global の AGENTS.md の hash、git status、route を記録する"
else
  ng "run.json の記録が不正: $(cat "$RUN/run.json")"
fi

# ---- codex
run "$CROSS" codex "$RUN" --dry-run
expect_rc "--dry-run は command を示す" 0 "--skip-git-repo-check -p toolkit-divergent -s read-only -m gpt-6-astra -c model_reasoning_effort=medium --json --output-schema"
if ! jq -e 'has("codex")' "$RUN/run.json" >/dev/null && [[ ! -e "$STUB_ARGV" ]]; then ok "--dry-run は Codex を起動しない"; else ng "--dry-run が Codex を起動した"; fi
run "$CROSS" codex "$RUN"
expect_rc "Codex worker を起動する" 0 "codex exec exit 0"
CWD="$(jq -r .codex.cwd "$RUN/run.json")"
if grep -qx -- '-s' "$STUB_ARGV" && grep -qx 'read-only' "$STUB_ARGV" && grep -qx -- '--skip-git-repo-check' "$STUB_ARGV" &&
  grep -qx 'toolkit-divergent' "$STUB_ARGV" && grep -qx -- '--output-schema' "$STUB_ARGV"; then
  ok "codex exec を read-only、profile、output schema 付きで起動する"
else
  ng "codex exec の引数が不正: $(tr '\n' ' ' < "$STUB_ARGV")"
fi
if [[ "$CWD" == "$TMPDIR/"* && ! -s "$STUB_CWD_LIST" && ! -e "$CWD" ]]; then
  ok "cwd は空の一時ディレクトリで、終了後に消す"
else
  ng "cwd が不正: $CWD ($(cat "$STUB_CWD_LIST"))"
fi
if cmp -s "$STUB_PROMPT" "$RUN/worker-prompt.md"; then ok "Codex の入力は prepare した worker prompt そのもの"; else ng "Codex の入力が worker prompt と違う"; fi
if jq -e '.codex.used.model == "gpt-6-astra" and .codex.used.effort == "medium" and .codex.used.sandbox == "read-only"' "$RUN/run.json" >/dev/null; then
  ok "rollout から実際の model、effort、sandbox を記録する"
else
  ng "used の記録が不正: $(jq -c .codex "$RUN/run.json")"
fi
run "$CROSS" codex "$RUN"
expect_rc "同じ run で Codex を2回起動しない" 1 "already ran"

# ---- collect
run "$CROSS" collect "$RUN"
expect_rc "Claude の出力が無ければ collect は失敗する" 1 "FAIL: claude output"
claude_output "$RUN" 0000
run "$CROSS" collect "$RUN"
expect_rc "Claude の出力の hash が違えば失敗する" 1 "does not match the brief"
printf '{"brief_sha256":"x"}\n' > "$RUN/claude-output.json"
run "$CROSS" collect "$RUN"
expect_rc "schema に合わない出力は失敗する" 1 "missing required key"
claude_output "$RUN"
printf 'new\n' > "$REPO/untracked.txt"
run "$CROSS" collect "$RUN"
expect_rc "git status が変わっていれば失敗する" 1 "changed since prepare"
rm "$REPO/untracked.txt"
run "$CROSS" collect "$RUN"
expect_rc "両方の出力が揃えば collect は通る" 0 "COLLECT OK"
if [[ "$OUT" == *"OK: Codex used gpt-6-astra/medium"* && "$OUT" == *"OK: Codex sandbox was read-only"* &&
  "$OUT" == *"[changed_principle] Queue forgets on purpose"* && "$OUT" == *"WARN: codex did not use all three mechanisms"* ]]; then
  ok "collect は route、sandbox、両方の候補、mechanism の不足を示す"
else
  ng "collect の出力が不足: $OUT"
fi

# ---- finish
run "$CROSS" finish "$RUN"
expect_rc "synthesis が無ければ finish は失敗する" 1 "synthesis.md is missing"
printf '## Agreements\n\nnone\n\n## Differences\n\nall\n\n## Decisions\n\n' > "$RUN/synthesis.md"
run "$CROSS" finish "$RUN"
expect_rc "空の section があれば失敗する" 1 "'## Decisions' section"
printf '## Agreements\n\nnone\n\n## Differences\n\nall\n\n## Decisions\n\n- Invert who pays: rejected, prior art\n\n## Notes\n\nCodex read the global AGENTS.md.\n' > "$RUN/synthesis.md"
cp "$RUN/claude-output.json" "$SANDBOX/claude-output.bak"
claude_output "$RUN" && jq '.notes = "edited"' "$RUN/claude-output.json" > "$SANDBOX/x" && mv "$SANDBOX/x" "$RUN/claude-output.json"
run "$CROSS" finish "$RUN"
expect_rc "collect の後に出力が変われば失敗する" 1 "changed after collect"
cp "$SANDBOX/claude-output.bak" "$RUN/claude-output.json"
run "$CROSS" finish "$RUN"
expect_rc "finish は result を書く" 0 "FINISH OK"
if grep -qF '## Raw output: Codex' "$RUN/result.md" && grep -qF 'Invert who pays' "$RUN/result.md" &&
  grep -qF 'Queue forgets on purpose' "$RUN/result.md" && grep -qF '## Agreements' "$RUN/result.md" &&
  grep -qF 'retry storms' "$RUN/result.md"; then
  ok "result に一致点、相違点、両方の生の出力、brief がある"
else
  ng "result.md が不足"
fi
[[ -z "$(git -C "$REPO" status --porcelain)" ]] && ok "実行の前後で repository の git status が変わらない" || ng "repository が変わった"

# ---- Codex worker failures (new runs)
prepare
STUB_MODEL=gpt-6-luna run "$CROSS" codex "$RUN"
claude_output "$RUN"
run "$CROSS" collect "$RUN"
expect_rc "route と違うモデルが使われたら失敗する" 1 "FAIL: Codex used gpt-6-luna/medium"
prepare
STUB_LEAVE=1 run "$CROSS" codex "$RUN"
claude_output "$RUN"
run "$CROSS" collect "$RUN"
expect_rc "cwd に file が残れば失敗する" 1 "left-behind.txt"
prepare
STUB_OUTPUT=badhash run "$CROSS" codex "$RUN"
claude_output "$RUN"
run "$CROSS" collect "$RUN"
expect_rc "Codex の出力の hash が違えば失敗する" 1 "FAIL: codex output"

# ---- static contract of the skill (C.5: no automatic move to implementation)
SKILL_FILES=("$REPO_ROOT/shared/skills/claude-code/break-consensus/SKILL.md" "$REPO_ROOT/shared/skills/codex/break-consensus/SKILL.md"
  "$REPO_ROOT/shared/skills/break-consensus/references/cross.md")
if ! grep -nE 'gh-codex-drive|codex-delegate|task --write|--write' "${SKILL_FILES[@]}"; then
  ok "break-consensus は実装の経路（gh-codex-drive、codex-delegate、task --write）を参照しない"
else
  ng "break-consensus が実装の経路を参照している"
fi
if [[ "$(grep -n '\bEdit\b' "${SKILL_FILES[@]}" | grep -vc 'disallowedTools\|Bash, Edit, Write, and NotebookEdit')" -eq 0 ]]; then
  ok "Edit は Claude worker から除く tool としてだけ現れる"
else
  ng "Edit を指示している: $(grep -n '\bEdit\b' "${SKILL_FILES[@]}")"
fi
if grep -qF "disallowedTools: ['Bash', 'Edit', 'Write', 'NotebookEdit']" "$REPO_ROOT/shared/skills/break-consensus/references/cross.md" &&
  grep -qF 'model: args.model' "$REPO_ROOT/shared/skills/break-consensus/references/cross.md"; then
  ok "Claude worker は model を route から受け、Bash、Edit、Write、NotebookEdit を除く"
else
  ng "Claude worker の workflow が不正"
fi
steps() { sed -n '/^1\. /,/^6\. /p' "$1"; }
if diff <(steps "${SKILL_FILES[0]}") <(steps "${SKILL_FILES[1]}") >/dev/null; then
  ok "既定の手順は Claude 版と Codex 版で同じ"
else
  ng "既定の手順が runtime 間で違う"
fi
if python3 - "$REPO_ROOT/shared/skills/break-consensus/references/divergent.schema.json" <<'PY'
import json, sys
def strict(node, where="$"):
    if isinstance(node, dict):
        if node.get("type") == "object":
            assert node.get("additionalProperties") is False, f"{where}: additionalProperties must be false"
            assert sorted(node.get("required", [])) == sorted(node.get("properties", {})), f"{where}: every property must be required"
        for key, value in node.items():
            strict(value, f"{where}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            strict(value, f"{where}[{index}]")
strict(json.load(open(sys.argv[1])))
PY
then
  ok "divergent.schema.json は Codex の --output-schema の strict 形式"
else
  ng "divergent.schema.json が strict でない"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
