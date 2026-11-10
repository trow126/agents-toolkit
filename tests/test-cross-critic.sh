#!/usr/bin/env bash
# test-cross-critic.sh — claude/bin/cross-critic with stub codex and claude (no model is called).
# Checks the route choice (never the author model), read-only flags, output validation, git status
# guard, and the synthesis rules of finish (every ID decided, source, raised priority for 両方).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_ROOT/claude/bin/cross-critic"
ROUTE="$REPO_ROOT/claude/skills/cross-critic/references/critic-route.env"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
ok() { echo "ok: $1"; }
ng() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

route() { sed -n "s/^$1=//p" "$ROUTE"; }
CODEX_MODEL="$(route CODEX_MODEL)"
CODEX_EFFORT="$(route CODEX_EFFORT)"
GATE_MODEL="$(route CLAUDE_GATE_MODEL)"
ALT_MODEL="$(route CLAUDE_ALT_MODEL)"

export XDG_STATE_HOME="$SANDBOX/state"
export CODEX_HOME="$SANDBOX/codex-home"
export CROSS_CRITIC_NO_LOGIN_SHELL=1
mkdir -p "$CODEX_HOME" "$SANDBOX/stub"
printf '{"models":[{"slug":"%s","supported_reasoning_levels":[{"effort":"low"},{"effort":"%s"}]}]}\n' \
  "$CODEX_MODEL" "$CODEX_EFFORT" > "$CODEX_HOME/models_cache.json"

# ---- stubs -------------------------------------------------------------------------------------
cat > "$SANDBOX/stub/codex" <<'STUB'
#!/usr/bin/env python3
import json, os, re, sys, pathlib
args = sys.argv[1:]
prompt = sys.stdin.read()
sha = re.search(r"document_sha256: ([0-9a-f]{64})", prompt).group(1)
mode = os.environ.get("STUB_CODEX", "ok")
out = pathlib.Path(args[args.index("-o") + 1])
cwd = pathlib.Path(args[args.index("-C") + 1])
model, effort = args[args.index("-m") + 1], args[args.index("-c") + 1].split("=", 1)[1]
sandbox = args[args.index("-s") + 1]
pathlib.Path(os.environ["STUB_LOG"]).joinpath("codex-args").write_text("\n".join(args))
if mode == "badhash":
    sha = "0" * 64
if mode == "write":
    (cwd / "written-by-critic.txt").write_text("x")
findings = [
    {"kind": "objection", "target": "§1", "claim": "claim one | with pipe", "why_it_matters": "w",
     "resolution": "r", "severity": "medium"},
    {"kind": "oversight", "target": "§2", "claim": "claim two", "why_it_matters": "w",
     "resolution": "r", "severity": "low"},
]
recon = "" if mode == "norecon" or "were withheld" not in prompt else "codex would choose B"
story = "" if mode == "nostory" else "codex story: the split leaked because \"fit on all rows\" was followed"
out.write_text(json.dumps({"document_sha256": sha, "failure_story": story, "reconstruction": recon, "findings": findings}))
thread = "0199aaaa-bbbb-cccc-dddd-eeeeffff0000"
print(json.dumps({"type": "thread.started", "thread_id": thread}))
print(json.dumps({"type": "turn.completed", "usage": {"input_tokens": 10, "output_tokens": 5}}))
rollout = pathlib.Path(os.environ["CODEX_HOME"], "sessions/2026/10/04", f"rollout-x-{thread}.jsonl")
rollout.parent.mkdir(parents=True, exist_ok=True)
rollout.write_text(json.dumps({"type": "turn_context", "payload": {
    "model": model, "effort": effort, "sandbox_policy": {"type": sandbox}}}) + "\n")
STUB
cat > "$SANDBOX/stub/claude" <<'STUB'
#!/usr/bin/env python3
import json, os, re, sys, pathlib
args = sys.argv[1:]
prompt = sys.stdin.read()
sha = re.search(r"document_sha256: ([0-9a-f]{64})", prompt).group(1)
pathlib.Path(os.environ["STUB_LOG"]).joinpath("claude-args").write_text("\n".join(args))
pathlib.Path(os.environ["STUB_LOG"]).joinpath("claude-env").write_text(os.environ.get("AGENTS_TOOLKIT_SLACK_NOTIFY", ""))
model = args[args.index("--model") + 1]
finding = {"kind": "alternative", "target": "§1", "claim": "claim three", "why_it_matters": "w",
           "resolution": "r", "severity": "medium"}
print("login shell noise")
print(json.dumps({"type": "result", "subtype": "success", "is_error": False, "result": "",
                  "structured_output": {"document_sha256": sha, "findings": [finding],
                                        "failure_story": "claude story: the gate passed on a stale baseline",
                                        "reconstruction": "claude would choose A" if "were withheld" in prompt else ""},
                  "total_cost_usd": 0.01, "num_turns": 1,
                  "modelUsage": {f"claude-{model}-9-9": {"inputTokens": 1}}}))
STUB
chmod +x "$SANDBOX/stub/codex" "$SANDBOX/stub/claude"
export PATH="$SANDBOX/stub:$PATH"
export STUB_LOG="$SANDBOX/log"
mkdir -p "$STUB_LOG"

REPO="$SANDBOX/repo"
git init -q "$REPO"
git -C "$REPO" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init
DOC="$SANDBOX/plan.md"
printf '# Plan\n\n1. Do the thing.\n2. Measure it.\n' > "$DOC"

run_cc() { (cd "$REPO" && "$BIN" "$@"); }

# ---- dry run and route choice --------------------------------------------------------------------
out="$(run_cc run "$DOC" --author "claude-other-5-5" --gate --dry-run)"
if grep -q -- "-s read-only" <<< "$out" && grep -q -- "--tools Read,Grep,Glob" <<< "$out" \
   && grep -q "Claude critic: $GATE_MODEL (gate model)" <<< "$out"; then
  ok "dry run: Codex read-only, Claude read-only tools, gate model when the author differs"
else
  ng "dry run output unexpected: $out"
fi
out="$(run_cc run "$DOC" --author "claude-$GATE_MODEL-5-1" --gate --dry-run)"
if grep -q "Claude critic: $ALT_MODEL (alternate model" <<< "$out"; then
  ok "author is the gate model: the alternate model criticizes instead"
else
  ng "author == gate model did not switch to the alternate model: $out"
fi
if ! grep -q -- "--tools" <<< "$(run_cc run "$DOC" --author x --dry-run)"; then
  ok "without --gate only the Codex critic runs"
else
  ng "default mode launched a Claude critic"
fi

# ---- refusals ------------------------------------------------------------------------------------
printf 'token ghp_%s\n' "$(printf 'a%.0s' {1..36})" > "$SANDBOX/secret.md"
if ! run_cc run "$SANDBOX/secret.md" --author x >/dev/null 2>&1; then ok "a document with a token is refused"; else ng "secret document accepted"; fi
if ! run_cc run "$DOC" >/dev/null 2>&1; then ok "--author is required"; else ng "run without --author accepted"; fi

# ---- full run with --gate ----------------------------------------------------------------------------
rc=0
out="$(run_cc run "$DOC" --author "claude-other-5-5" --gate 2>/dev/null)" || rc=$?
RUN_DIR="$(python3 -c 'import json,sys; t=sys.stdin.read(); print(json.loads(t[t.index("{"):])["run_dir"])' <<< "$out")"
if [[ "$rc" -eq 0 && -f "$RUN_DIR/findings.json" && -f "$RUN_DIR/synthesis.template.md" ]]; then
  ok "run --gate succeeds and writes findings.json and the template"
else
  ng "run --gate failed (rc=$rc): $out"
fi
ids="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join(f["id"] for c in d["critics"] for f in c["findings"]))' "$RUN_DIR/findings.json")"
[[ "$ids" == "X1 X2 C1" ]] && ok "finding IDs: X<n> Codex, C<n> Claude" || ng "unexpected IDs: $ids"
if grep -qx "$GATE_MODEL" <<< "$(sed -n '/^--model$/{n;p}' "$STUB_LOG/claude-args")" \
   && grep -qx "Read,Grep,Glob" <<< "$(sed -n '/^--tools$/{n;p}' "$STUB_LOG/claude-args")" \
   && [[ "$(cat "$STUB_LOG/claude-env")" == "off" ]]; then
  ok "Claude critic: gate model, --tools Read,Grep,Glob, AGENTS_TOOLKIT_SLACK_NOTIFY=off"
else
  ng "Claude critic arguments or env unexpected"
fi

CL="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print({c["key"]: c["label"] for c in d["critics"]}[sys.argv[2]])' "$RUN_DIR/findings.json" claude)"
XL="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print({c["key"]: c["label"] for c in d["critics"]}[sys.argv[2]])' "$RUN_DIR/findings.json" codex)"

# ---- finish ------------------------------------------------------------------------------------------
cp "$RUN_DIR/synthesis.template.md" "$RUN_DIR/synthesis.md"
if ! "$BIN" finish "$RUN_DIR" >/dev/null 2>&1; then ok "finish rejects the unfilled template"; else ng "finish accepted empty decisions"; fi

write_synthesis() {
  printf '# s\n\n| ID | 指摘 | 出所 | 優先度 | 判定 | 理由 |\n|---|---|---|---|---|---|\n%s\n\n## Notes\n\nnone\n' "$1" > "$RUN_DIR/synthesis.md"
}
expect_finish() {
  local desc="$1" want="$2" rc=0
  "$BIN" finish "$RUN_DIR" >/dev/null 2>&1 || rc=$?
  if [[ "$want" == pass && "$rc" -eq 0 ]] || [[ "$want" == fail && "$rc" -ne 0 ]]; then ok "$desc"; else ng "$desc (rc=$rc)"; fi
}
write_synthesis "| X1, C1 | merged | 両方 | 高 | 採用 | fix §1 |
| X2 | two | $XL | 低 | 不採用 | covered by §3 |"
expect_finish "finish passes: every ID decided, 両方 raised one level" pass
[[ -f "$RUN_DIR/result.md" ]] && ok "finish writes result.md" || ng "result.md missing"

write_synthesis "| X1, C1 | merged | 両方 | 中 | 採用 | fix §1 |
| X2 | two | $XL | 低 | 不採用 | covered |"
expect_finish "finish rejects a 両方 row not raised above its highest severity" fail
write_synthesis "| X1, C1 | merged | 両方 | 高 | 採用 | fix §1 |"
expect_finish "finish rejects a synthesis that leaves an ID undecided" fail
write_synthesis "| X1 | one | $CL | 中 | 採用 | fix |
| C1 | three | $CL | 中 | 採用 | fix |
| X2 | two | $XL | 低 | 不採用 | covered |"
expect_finish "finish rejects a wrong 出所" fail
write_synthesis "| X1, C1 | merged | 両方 | 高 | 保留 | later |
| X2 | two | $XL | 低 | 不採用 | covered |"
expect_finish "finish rejects a decision other than 採用/不採用" fail
write_synthesis "| X1, C1 | merged | 両方 | 高 | 採用 | fix |
| X2 | two | $XL | 低 | 不採用 | - |"
expect_finish "finish rejects a placeholder reason" fail

# ---- --withhold (results-masked review) ------------------------------------------------------------
WDOC="$SANDBOX/prereg.md"
printf '# Prereg\n\n## Premises\n\nData from 2020.\n\n## Decision\n\nChoose A because SECRET-DECISION.\n\n### Detail\n\nmore detail\n\n## Risks\n\nLeak risk.\n' > "$WDOC"
rc=0; run_cc run "$WDOC" --author x --withhold Nope >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] && ok "--withhold refuses a heading that is not in the document" || ng "unknown --withhold heading accepted (rc=$rc)"
rc=0
out="$(run_cc run "$WDOC" --author "claude-other-5-5" --gate --withhold Decision 2>/dev/null)" || rc=$?
WRUN="$(python3 -c 'import json,sys; t=sys.stdin.read(); print(json.loads(t[t.index("{"):])["run_dir"])' <<< "$out")"
if [[ "$rc" -eq 0 ]] && ! grep -q "SECRET-DECISION\|more detail" "$WRUN/prompt.md" && grep -q "Leak risk" "$WRUN/prompt.md" \
   && grep -q 'The sections "Decision" were withheld' "$WRUN/prompt.md" && grep -q "SECRET-DECISION" "$WRUN/withheld.md" \
   && grep -q "more detail" "$WRUN/withheld.md" && cmp -s "$WDOC" "$WRUN/original.md" \
   && [[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["document_sha256"])' "$WRUN/run.json")" == "$(sha256sum < "$WRUN/document.md" | cut -d' ' -f1)" ]]; then
  ok "--withhold removes the section and its subsections from the sent copy, hashes the sent copy, and keeps the original"
else
  ng "--withhold run unexpected (rc=$rc): $out"
fi
if grep -q "^## Divergences" "$WRUN/synthesis.template.md" && grep -q "codex would choose B" "$WRUN/synthesis.template.md"; then
  ok "--withhold: the template has ## Divergences with each critic's reconstruction"
else
  ng "--withhold template lacks the reconstructions"
fi
WXL="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print({c["key"]: c["label"] for c in d["critics"]}["codex"])' "$WRUN/findings.json")"
write_wsynthesis() {
  printf '# s\n\n| ID | 指摘 | 出所 | 優先度 | 判定 | 理由 |\n|---|---|---|---|---|---|\n| X1, C1 | merged | 両方 | 高 | 採用 | fix |\n| X2 | two | %s | 低 | 不採用 | covered |\n\n## Notes\n\nnone\n\n## Divergences\n\n%s\n' "$WXL" "$1" > "$WRUN/synthesis.md"
}
rc=0; write_wsynthesis "- $WXL reconstruction: codex would choose B"; "$BIN" finish "$WRUN" >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] && ok "--withhold: finish refuses a Divergences section with only the pre-filled reconstructions" || ng "empty Divergences accepted"
rc=0; write_wsynthesis "Codex chose B, the document chose A: re-check the premise on 2020 data."; "$BIN" finish "$WRUN" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -q "SECRET-DECISION" "$WRUN/result.md" && grep -q "claude would choose A" "$WRUN/result.md"; then
  ok "--withhold: finish puts the withheld text next to the reconstructions in result.md"
else
  ng "--withhold finish failed or result.md lacks the comparison (rc=$rc)"
fi
if grep -q "^## Failure stories" "$WRUN/synthesis.template.md" && grep -q "codex story: the split leaked" "$WRUN/synthesis.template.md" \
   && grep -q "claude story: the gate passed" "$WRUN/synthesis.template.md" && grep -q "Failure story: codex story" "$WRUN/result.md" \
   && grep -q "failure_story: assume the document was carried out exactly as written" "$WRUN/prompt.md"; then
  ok "premortem: the prompt asks for a failure story, and the template and result.md show each critic's story"
else
  ng "premortem: failure stories missing from the prompt, the template, or result.md"
fi
rc=0; STUB_CODEX=nostory run_cc run "$WDOC" --author x >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] && ok "premortem: an empty failure_story fails the run" || ng "empty failure_story accepted"
rc=0; STUB_CODEX=norecon run_cc run "$WDOC" --author x --withhold Decision >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] && ok "--withhold: an empty reconstruction fails the run" || ng "empty reconstruction accepted"

# ---- failure paths ---------------------------------------------------------------------------------
rc=0; STUB_CODEX=badhash run_cc run "$DOC" --author x >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] && ok "a critic output with the wrong document hash fails the run" || ng "bad hash accepted"
rc=0; STUB_CODEX=write run_cc run "$DOC" --author x >/dev/null 2>&1 || rc=$?
[[ "$rc" -ne 0 ]] && ok "a changed git status fails the run" || ng "repository write by a critic went unnoticed"

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then echo "PASS: all assertions succeeded"; exit 0; fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
