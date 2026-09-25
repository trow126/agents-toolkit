#!/usr/bin/env bash
# Codex delegation (D8, appendix B): preflight, launcher, post-delegation gate, gh-finish evidence
# check, and report schema — on fixture git repos (plain and worktree) with a stub `codex`.
# No model is called.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_ROOT/claude/bin"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

export PYTHONDONTWRITEBYTECODE=1
export CODEX_HOME="$SANDBOX/codex-home"
mkdir -p "$CODEX_HOME" "$SANDBOX/stub"
cp "$REPO_ROOT/codex/profiles/toolkit-implementer.config.toml" "$CODEX_HOME/"
cat > "$CODEX_HOME/models_cache.json" <<'JSON'
{"models": [
 {"slug": "gpt-6-astra", "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}, {"effort": "xhigh"}, {"effort": "max"}, {"effort": "ultra"}]},
 {"slug": "gpt-6-luna", "supported_reasoning_levels": [{"effort": "low"}, {"effort": "medium"}, {"effort": "high"}]}
]}
JSON
# stub codex: `--version`, and `exec` that records argv, reads the prompt, edits files per
# STUB_EDIT, and writes the -o report per STUB_REPORT (completed | stopped | invalid)
cat > "$SANDBOX/stub/codex" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then echo "codex-cli 0.157.0"; exit 0; fi
printf '%s\n' "$@" > "$STUB_ARGV"
cat > "$STUB_PROMPT"
out=""; dir="."
while [[ $# -gt 0 ]]; do
  case "$1" in -o) out="$2"; shift 2 ;; -C) dir="$2"; shift 2 ;; *) shift ;; esac
done
cd "$dir"
case "${STUB_EDIT:-in-scope}" in
  in-scope) printf 'changed\n' >> src/a.txt ;;
  none) ;;
esac
case "${STUB_REPORT:-completed}" in
  completed) printf '%s\n' '{"status":"completed","summary":"done","changed_files":[{"path":"src/a.txt","reason":"goal"}],"assumptions":[],"checks_run":[{"cmd":"test -f src/a.txt","exit_code":0}],"checks_not_run":[],"residual_risks":[],"discovered_issues":[],"deliberately_unchanged":[],"stopped":null}' > "$out" ;;
  stopped) printf '%s\n' '{"status":"stopped","summary":"needs lockfile","changed_files":[],"assumptions":[],"checks_run":[],"checks_not_run":[],"residual_risks":[],"discovered_issues":[],"deliberately_unchanged":[],"stopped":{"trigger":"dependency_change","findings":"needs a new package","options":["allow uv.lock"],"recommendation":"allow uv.lock"}}' > "$out" ;;
  invalid) printf '%s\n' '{"status":"completed","summary":"missing keys"}' > "$out" ;;
esac
echo '{"type":"turn.completed"}'
STUB
chmod +x "$SANDBOX/stub/codex"
export PATH="$SANDBOX/stub:$PATH" STUB_ARGV="$SANDBOX/argv" STUB_PROMPT="$SANDBOX/prompt"

new_repo() {
  local repo="$1"
  mkdir -p "$repo/src" "$repo/docs"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config user.name Fixture
  git -C "$repo" config commit.gpgsign false
  printf 'base\n' > "$repo/src/a.txt"
  printf '# Doc\n\nbody\n' > "$repo/docs/readme.md"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  printf 'user note\n' > "$repo/notes.txt"
}

# write_contract <repo> <id> [jq filter applied to the default contract]
write_contract() {
  local repo="$1" id="$2" filter="${3:-.}" dir
  dir="$(git -C "$repo" rev-parse --absolute-git-dir)/agents-toolkit"
  mkdir -p "$dir"
  jq -n --arg id "$id" '{
    id: $id, goal: "append a line to src/a.txt",
    acceptance_criteria: ["src/a.txt has a new line"], scope_paths: ["src/**"],
    required_checks: ["test -f src/a.txt"], diff_budget: {files: 2, lines: 20},
    allowed_dependency_changes: [], non_goals: [], invariants: [], protected_paths_extra: [],
    route: {model: "gpt-6-astra", effort: "medium"}
  }' | jq "$filter" > "$dir/contract-$id.json"
  CONTRACT="$dir/contract-$id.json"
  STATE="$dir"
}

RC=0; OUT=""
run() { RC=0; OUT="$("$@" 2>&1)" || RC=$?; }
expect_rc() { # desc want_rc needle
  if [[ "$RC" -eq "$2" && "$OUT" == *"$3"* ]]; then ok "$1"; else ng "$1 (rc=$RC, want $2 containing '$3'): $OUT"; fi
}

# ---------------- preflight ----------------
R="$SANDBOX/pre"; new_repo "$R"
write_contract "$R" 1
run "$BIN/codex-delegate-preflight" "$CONTRACT" --repo "$R"
expect_rc "preflight: 正しい契約は通る" 0 "PREFLIGHT OK"
write_contract "$R" 2 '.scope_paths = []'
run "$BIN/codex-delegate-preflight" "$CONTRACT" --repo "$R"
expect_rc "preflight: 必須項目の空欄は FAIL" 1 "contract \$.scope_paths: needs at least 1 item(s)"
write_contract "$R" 3 '.route.model = "gpt-6-sol"'
run "$BIN/codex-delegate-preflight" "$CONTRACT" --repo "$R"
expect_rc "preflight: catalog に無いモデルは FAIL" 1 "route model gpt-6-sol is not in the live Codex catalog"
write_contract "$R" 4 '.route.effort = "ultra"'
run "$BIN/codex-delegate-preflight" "$CONTRACT" --repo "$R"
expect_rc "preflight: ultra は FAIL" 1 "route effort ultra is not allowed"
write_contract "$R" 5 '.route = {model: "gpt-6-luna", effort: "xhigh"}'
run "$BIN/codex-delegate-preflight" "$CONTRACT" --repo "$R"
expect_rc "preflight: モデルが対応しない effort は FAIL" 1 "route effort xhigh is not supported by gpt-6-luna"
write_contract "$R" 6 '.unexpected = true'
run "$BIN/codex-delegate-preflight" "$CONTRACT" --repo "$R"
expect_rc "preflight: schema にない key は FAIL" 1 "unexpected key unexpected"
write_contract "$R" 8
cp "$CONTRACT" "$SANDBOX/outside.json"
run "$BIN/codex-delegate-preflight" "$SANDBOX/outside.json" --repo "$R"
expect_rc "preflight: git-dir の外の契約は FAIL" 1 "contract must live at"
mv "$CODEX_HOME/toolkit-implementer.config.toml" "$SANDBOX/profile.bak"
write_contract "$R" 7
run "$BIN/codex-delegate-preflight" "$CONTRACT" --repo "$R"
expect_rc "preflight: profile が無ければ FAIL" 1 "Codex profile missing"
mv "$SANDBOX/profile.bak" "$CODEX_HOME/toolkit-implementer.config.toml"

# ---------------- launcher + gate (plain repo) ----------------
R="$SANDBOX/plain"; new_repo "$R"
write_contract "$R" 42
run "$BIN/codex-delegate" "$CONTRACT" --repo "$R" --dry-run
expect_rc "delegate --dry-run はコマンドだけを示す" 0 "-p toolkit-implementer -s workspace-write -m gpt-6-astra -c model_reasoning_effort=medium --json --output-schema"
if [[ ! -e "$STATE/active.json" ]]; then ok "delegate --dry-run は state を書かない"; else ng "dry-run wrote active.json"; fi
run "$BIN/codex-delegate" "$CONTRACT" --repo "$R"
expect_rc "delegate: stub codex の実行が成功する" 0 "codex exec exit 0"
if jq -e '.baseline.head and (.baseline.untracked | has("notes.txt")) and .route.cli_version == "codex-cli 0.157.0"' "$CONTRACT" >/dev/null; then
  ok "delegate: baseline（既存の untracked を含む）と CLI version を契約に記録する"
else ng "delegate: baseline not recorded"; fi
if [[ -f "$STATE/active.json" ]] && grep -q 'Do not commit, push' "$SANDBOX/prompt" && grep -q 'append a line to src/a.txt' "$SANDBOX/prompt"; then
  ok "delegate: active.json を作り、契約から prompt を組み立てる"
else ng "delegate: active.json or prompt missing"; fi
if grep -qx -- '--output-schema' "$STUB_ARGV" && grep -qx 'toolkit-implementer' "$STUB_ARGV"; then ok "delegate: exec に profile と output schema を渡す"; else ng "delegate: argv $(tr '\n' ' ' < "$STUB_ARGV")"; fi
run "$BIN/codex-delegate" "$CONTRACT" --repo "$R"
expect_rc "delegate: 別の委任が active なら起動しない" 1 "another delegation is active"

run "$BIN/delegation-evidence-check" --repo "$R"
expect_rc "evidence: gate 前は FAIL" 1 "no evidence for active delegation 42"
run "$BIN/verify-delegation" "$CONTRACT" --repo "$R"
expect_rc "gate: scope 内の変更は PASS" 0 "GATE PASS: 42 (1 files"
if jq -e '.passed == true and (.head | length == 40) and (.diff_hash | length == 64) and .checks[0].exit_code == 0 and .route.model == "gpt-6-astra"' "$STATE/evidence-42.json" >/dev/null; then
  ok "gate: evidence JSON に HEAD、diff hash、check、route を記録する"
else ng "gate: evidence incomplete"; fi
run "$BIN/delegation-evidence-check" --repo "$R"
expect_rc "evidence: 検証直後は OK" 0 "EVIDENCE OK: 42"
printf 'review fix\n' >> "$R/src/a.txt"
run "$BIN/delegation-evidence-check" --repo "$R"
expect_rc "evidence: 検証後の編集は FAIL（再検証が必要）" 1 "working tree changed after verification"
run "$BIN/delegation-evidence-check" --repo "$R" --clear
expect_rc "evidence: --clear で active を消す" 0 "active delegation cleared"
run "$BIN/delegation-evidence-check" --repo "$R"
expect_rc "evidence: active が無ければ OK" 0 "no active delegation"

# gate violations: each case launches a fresh delegation, then mutates the tree
gate_case() { # name contract-filter stub-report mutation want-needle
  local name="$1" filter="$2" report="$3" mutation="$4" needle="$5"
  local repo="$SANDBOX/gate-$name"
  new_repo "$repo"
  write_contract "$repo" "$name" "$filter"
  STUB_REPORT="$report" run "$BIN/codex-delegate" "$CONTRACT" --repo "$repo"
  (cd "$repo" && eval "$mutation")
  run "$BIN/verify-delegation" "$CONTRACT" --repo "$repo"
  expect_rc "gate: $name" 1 "$needle"
  run "$BIN/delegation-evidence-check" --repo "$repo"
  expect_rc "evidence: $name の失敗した evidence では gh-finish を止める" 1 "evidence did not pass"
}
gate_case out-of-scope . completed 'printf x > docs/extra.txt' "out of scope: docs/extra.txt"
gate_case protected '.scope_paths = ["**"]' completed 'printf "# x\n" > src/AGENTS.md' "protected path changed: src/AGENTS.md"
gate_case lockfile '.scope_paths = ["**"]' completed 'printf "x\n" > uv.lock' "lockfile changed without allowed_dependency_changes: uv.lock"
gate_case budget-files '.diff_budget.files = 1' completed 'printf "b\n" > src/b.txt' "diff budget exceeded: 2 files > 1"
gate_case budget-lines '.diff_budget.lines = 3' completed 'seq 1 5 > src/new.txt' "diff budget exceeded: 6 lines > 3"
gate_case head-moved . completed 'git add -A && git -c user.email=f@x -c user.name=f commit -q -m sneaky' "HEAD moved from"
gate_case stopped . stopped ':' "Codex stopped: dependency_change: needs a new package"
gate_case invalid-report . invalid ':' "report \$: missing required key changed_files"
gate_case failing-check '.required_checks = ["false"]' completed ':' "required check failed (exit 1): false"
gate_case lint '.scope_paths = ["**"]' completed 'printf "# T\nno blank\n" > docs/new.md' "lint: docs/new.md"

R="$SANDBOX/gate-allowed-lock"; new_repo "$R"
write_contract "$R" lock-ok '.scope_paths = ["**"] | .allowed_dependency_changes = ["uv.lock"]'
run "$BIN/codex-delegate" "$CONTRACT" --repo "$R"
printf 'x\n' > "$R/uv.lock"
run "$BIN/verify-delegation" "$CONTRACT" --repo "$R"
expect_rc "gate: allowed_dependency_changes に挙げた lockfile は通す" 0 "GATE PASS"
printf 'user note edited\n' > "$R/notes.txt"
run "$BIN/verify-delegation" "$CONTRACT" --repo "$R"
expect_rc "gate: 既存の untracked を変えたら差分に数える" 1 "diff budget exceeded: 3 files > 2"
if jq -e '.changed_files | index("notes.txt")' "$STATE/evidence-lock-ok.json" >/dev/null; then ok "gate: 変えた既存 untracked を changed_files に含める"; else ng "gate: notes.txt not in changed_files"; fi

# ---------------- worktree gitdir ----------------
R="$SANDBOX/wt-main"; new_repo "$R"
git -C "$R" worktree add -q "$SANDBOX/wt" -b feature
W="$SANDBOX/wt"
write_contract "$W" wt
case "$STATE" in */.git/worktrees/wt/agents-toolkit) ok "worktree: 契約は worktree 固有の gitdir に置く" ;; *) ng "worktree state dir: $STATE" ;; esac
run "$BIN/codex-delegate" "$CONTRACT" --repo "$W"
run "$BIN/verify-delegation" "$CONTRACT" --repo "$W"
expect_rc "worktree: gate が PASS し evidence を gitdir に書く" 0 "evidence -> $STATE/evidence-wt.json"
run "$BIN/delegation-evidence-check" --repo "$W"
expect_rc "worktree: evidence check が OK" 0 "EVIDENCE OK: wt"
run "$BIN/delegation-evidence-check" --repo "$R"
expect_rc "worktree: main checkout には active が無い" 0 "no active delegation"

# ---------------- report schema ----------------
run python3 - "$BIN" "$REPO_ROOT/claude/skills/gh-codex-drive/references/report.schema.json" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
from delegation_common import schema_errors
schema = json.load(open(sys.argv[2]))
base = {"summary": "s", "changed_files": [], "assumptions": [], "checks_run": [], "checks_not_run": [],
        "residual_risks": [], "discovered_issues": [], "deliberately_unchanged": []}
ok_completed = dict(base, status="completed", stopped=None)
ok_stopped = dict(base, status="stopped", stopped={"trigger": "out_of_scope_path", "findings": "f", "options": ["a"], "recommendation": "a"})
bad_trigger = dict(ok_stopped, stopped=dict(ok_stopped["stopped"], trigger="other"))
bad_extra = dict(ok_completed, extra=1)
assert not schema_errors(ok_completed, schema), schema_errors(ok_completed, schema)
assert not schema_errors(ok_stopped, schema), schema_errors(ok_stopped, schema)
assert schema_errors(bad_trigger, schema) and schema_errors(bad_extra, schema)
def strict(node, where="$"):
    if isinstance(node, dict):
        if "object" in (node.get("type") if isinstance(node.get("type"), list) else [node.get("type")]):
            assert node.get("additionalProperties") is False, where
            assert sorted(node.get("required", [])) == sorted(node.get("properties", {})), where
        for key, value in node.items():
            strict(value, f"{where}.{key}")
    elif isinstance(node, list):
        for i, value in enumerate(node):
            strict(value, f"{where}[{i}]")
strict(schema)
print("REPORT SCHEMA OK")
PY
expect_rc "report schema: completed と stopped を受け、strict（全 property が required）である" 0 "REPORT SCHEMA OK"

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
