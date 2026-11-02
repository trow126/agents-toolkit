#!/usr/bin/env bash
# test-pursue-issue.sh — claude/bin/pursue-issue (/pursue progress as a run Issue with one
# sub-Issue per hypothesis). Uses a stub `gh` that keeps Issues and sub-issues in a sandbox.
# Checks run creation (standalone and under an existing Issue), hypothesis numbering and
# attachment, verdict titles and close reasons, finish refusing open hypotheses, the done and
# not-done outcomes, invalid use, and the skill's authority contract. No network is used.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_ROOT/claude/bin/pursue-issue"
SKILL="$REPO_ROOT/claude/skills/pursue/SKILL.md"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
ok() { echo "ok: $1"; }
ng() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
expect_rc() { # desc want_rc cmd...
  local desc="$1" want="$2" rc=0
  shift 2
  "$@" >"$SANDBOX/out" 2>"$SANDBOX/err" || rc=$?
  if [[ "$rc" -eq "$want" ]]; then ok "$desc"; else ng "$desc (rc=$rc, want $want): $(cat "$SANDBOX/err")"; fi
}
out_field() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])" "$SANDBOX/out" "$1"; }
issue_field() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['issues'][sys.argv[2]][sys.argv[3]])" "$STUB/db.json" "$1" "$2"; }
subs_of() { python3 -c "import json,sys; print(' '.join(map(str, json.load(open(sys.argv[1]))['subs'].get(sys.argv[2], []))))" "$STUB/db.json" "$1"; }

export HOME="$SANDBOX/home"
export STUB="$SANDBOX/gh-state"
mkdir -p "$HOME" "$SANDBOX/stubbin" "$STUB"

# ---- stub gh -----------------------------------------------------------------------------------
cat > "$SANDBOX/stubbin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
S = Path(os.environ["STUB"]); a = sys.argv[1:]
db = S / "db.json"
d = json.loads(db.read_text()) if db.exists() else {"issues": {}, "subs": {}, "calls": []}
d["calls"].append(a[:2])
def save(): db.write_text(json.dumps(d, ensure_ascii=False))
def opt(name):
    return a[a.index(name) + 1] if name in a else None
def need_repo():
    if opt("-R") != "me/demo":
        print(f"stub gh: unexpected repo {opt('-R')}", file=sys.stderr); sys.exit(2)
if a[:2] == ["auth", "status"]:
    sys.exit(1 if os.environ.get("STUB_NO_AUTH") else 0)
if a[:2] == ["repo", "view"]:
    save()
    if os.environ.get("STUB_NO_REPO"): print("no git remotes", file=sys.stderr); sys.exit(1)
    print(json.dumps({"nameWithOwner": "me/demo", "hasIssuesEnabled": not os.environ.get("STUB_NO_ISSUES")})); sys.exit(0)
if a[:2] == ["issue", "create"]:
    need_repo()
    if os.environ.get("STUB_FAIL_CREATE"): save(); print("HTTP 502", file=sys.stderr); sys.exit(1)
    n = len(d["issues"]) + 1
    d["issues"][str(n)] = {"title": opt("--title"), "body": Path(opt("--body-file")).read_text(), "state": "OPEN", "reason": None}
    save(); print(f"https://github.com/me/demo/issues/{n}"); sys.exit(0)
if a[:2] == ["issue", "view"]:
    need_repo(); i = d["issues"].get(a[2])
    if i is None: save(); print("not found", file=sys.stderr); sys.exit(1)
    save(); print(json.dumps({"number": int(a[2]), "title": i["title"], "body": i["body"], "state": i["state"],
                              "url": f"https://github.com/me/demo/issues/{a[2]}"})); sys.exit(0)
if a[:2] == ["issue", "edit"]:
    need_repo(); i = d["issues"][a[2]]
    i["title"] = opt("--title"); i["body"] = Path(opt("--body-file")).read_text(); save(); sys.exit(0)
if a[:2] == ["issue", "close"]:
    need_repo(); i = d["issues"][a[2]]; i["state"] = "CLOSED"; i["reason"] = opt("--reason"); save(); sys.exit(0)
if a[0] == "api":
    path = [x for x in a[1:] if x.startswith("repos/")][0].split("?")[0].split("/")
    n = path[4]
    if path[-1] == "sub_issues":
        subs = d["subs"].setdefault(n, [])
        if "-X" in a:
            sid = int(opt("-F").split("=")[1])
            if not os.environ.get("STUB_DROP_ATTACH"): subs.append(sid - 1000)
            save(); print("{}"); sys.exit(0)
        save(); print(json.dumps([{"number": x, "title": d["issues"][str(x)]["title"],
                                   "state": d["issues"][str(x)]["state"].lower()} for x in subs])); sys.exit(0)
    save(); print(json.dumps({"id": 1000 + int(n), "number": int(n)})); sys.exit(0)
save(); print("stub gh: unsupported " + " ".join(a), file=sys.stderr); sys.exit(2)
PY
chmod +x "$SANDBOX/stubbin/gh"
export PATH="$SANDBOX/stubbin:$PATH"

B="$SANDBOX/bodies"; mkdir -p "$B"
printf '課題: X\n完了条件: `make test`\n' > "$B/contract.md"
printf '仮説: Y\n反証条件: Z\n' > "$B/hyp.md"
printf '変更: none\n結果: exit 1\n' > "$B/result.md"
printf '最終: done\n' > "$B/final.md"
: > "$B/empty.md"

# ---- preconditions -----------------------------------------------------------------------------
STUB_NO_AUTH=1 expect_rc "gh not signed in -> 3" 3 "$BIN" start --title t --body-file "$B/contract.md"
STUB_NO_REPO=1 expect_rc "no GitHub repository -> 1" 1 "$BIN" start --title t --body-file "$B/contract.md"
STUB_NO_ISSUES=1 expect_rc "Issues disabled -> 2" 2 "$BIN" start --title t --body-file "$B/contract.md"
expect_rc "empty body -> 2" 2 "$BIN" start --title t --body-file "$B/empty.md"
expect_rc "blank title -> 2" 2 "$BIN" start --title "  " --body-file "$B/contract.md"
[[ ! -e "$STUB/db.json" ]] || ! grep -q '"1"' "$STUB/db.json" && ok "nothing created on invalid use" || ng "Issue created on invalid use"

# ---- standalone run ----------------------------------------------------------------------------
expect_rc "start: creates the run Issue" 0 "$BIN" start --title "edge-hunt: frozen.gate を通す" --body-file "$B/contract.md"
RUN="$(out_field run)"
[[ "$(issue_field "$RUN" title)" == "[pursue] edge-hunt: frozen.gate を通す" ]] && ok "start: run title" || ng "start: run title $(issue_field "$RUN" title)"
[[ "$(issue_field "$RUN" body)" == *"完了条件"* ]] && ok "start: contract in body" || ng "start: body"
[[ "$(out_field url)" == "https://github.com/me/demo/issues/$RUN" ]] && ok "start: prints the URL" || ng "start: url"

expect_rc "hypothesis: H1" 0 "$BIN" hypothesis --run "$RUN" --title "slippage が過大" --body-file "$B/hyp.md"
H1="$(out_field issue)"
expect_rc "hypothesis: H2" 0 "$BIN" hypothesis --run "$RUN" --title "fee tier の誤設定" --body-file "$B/hyp.md"
H2="$(out_field issue)"
[[ "$(issue_field "$H1" title)" == "H1: slippage が過大" && "$(issue_field "$H2" title)" == "H2: fee tier の誤設定" ]] \
  && ok "hypothesis: numbered titles" || ng "hypothesis: titles"
[[ "$(subs_of "$RUN")" == "$H1 $H2" ]] && ok "hypothesis: attached in order" || ng "hypothesis: subs $(subs_of "$RUN")"
[[ "$(issue_field "$H1" body)" == "親 Issue: #$RUN"* ]] && ok "hypothesis: links the run" || ng "hypothesis: body"
expect_rc "hypothesis: under a non-run Issue -> 2" 2 "$BIN" hypothesis --run "$H1" --title x --body-file "$B/hyp.md"

expect_rc "finish: refuses with open hypotheses" 2 "$BIN" finish --issue "$RUN" --outcome "done" --body-file "$B/final.md"
grep -q "#$H1, #$H2" "$SANDBOX/err" && ok "finish: names the open hypotheses" || ng "finish: message $(cat "$SANDBOX/err")"

expect_rc "verdict: refuted" 0 "$BIN" verdict --issue "$H1" --verdict refuted --body-file "$B/result.md"
[[ "$(issue_field "$H1" title)" == "H1 [refuted]: slippage が過大" ]] && ok "verdict: refuted title" || ng "verdict: title $(issue_field "$H1" title)"
[[ "$(issue_field "$H1" state)" == CLOSED && "$(issue_field "$H1" reason)" == "not planned" ]] \
  && ok "verdict: refuted closes as not planned" || ng "verdict: refuted close"
[[ "$(issue_field "$H1" body)" == *"## 結果（refuted）"*"結果: exit 1"* ]] && ok "verdict: result appended" || ng "verdict: body"
expect_rc "verdict: second verdict on a closed Issue -> 2" 2 "$BIN" verdict --issue "$H1" --verdict confirmed --body-file "$B/result.md"
expect_rc "verdict: on the run Issue -> 2" 2 "$BIN" verdict --issue "$RUN" --verdict refuted --body-file "$B/result.md"
expect_rc "verdict: unknown verdict -> 2" 2 "$BIN" verdict --issue "$H2" --verdict maybe --body-file "$B/result.md"

expect_rc "hypothesis: H3 after a closed H1" 0 "$BIN" hypothesis --run "$RUN" --title "holdout 欠損" --body-file "$B/hyp.md"
H3="$(out_field issue)"
[[ "$(issue_field "$H3" title)" == "H3: holdout 欠損" ]] && ok "hypothesis: numbering skips verdict marks" || ng "hypothesis: H3 title $(issue_field "$H3" title)"
expect_rc "verdict: inconclusive" 0 "$BIN" verdict --issue "$H3" --verdict inconclusive --body-file "$B/result.md"
[[ "$(issue_field "$H3" reason)" == "not planned" ]] && ok "verdict: inconclusive closes as not planned" || ng "verdict: inconclusive"
expect_rc "verdict: confirmed" 0 "$BIN" verdict --issue "$H2" --verdict confirmed --body-file "$B/result.md"
[[ "$(issue_field "$H2" reason)" == completed ]] && ok "verdict: confirmed closes as completed" || ng "verdict: confirmed"

expect_rc "finish: done" 0 "$BIN" finish --issue "$RUN" --outcome "done" --body-file "$B/final.md"
[[ "$(issue_field "$RUN" title)" == "[pursue:done] edge-hunt: frozen.gate を通す" ]] && ok "finish: done title" || ng "finish: title"
[[ "$(issue_field "$RUN" state)" == CLOSED && "$(issue_field "$RUN" reason)" == completed ]] && ok "finish: done closes" || ng "finish: done state"
[[ "$(issue_field "$RUN" body)" == *"## 最終報告（done）"* ]] && ok "finish: report appended" || ng "finish: body"
expect_rc "finish: twice -> 2" 2 "$BIN" finish --issue "$RUN" --outcome "done" --body-file "$B/final.md"
expect_rc "hypothesis: on a closed run -> 2" 2 "$BIN" hypothesis --run "$RUN" --title x --body-file "$B/hyp.md"

# ---- run under an existing Issue, not-done -----------------------------------------------------
expect_rc "start --issue: unknown Issue -> 1" 1 "$BIN" start --title t --body-file "$B/contract.md" --issue 99
expect_rc "start --issue: closed Issue -> 2" 2 "$BIN" start --title t --body-file "$B/contract.md" --issue "$RUN"
python3 - "$STUB/db.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["issues"][str(len(d["issues"]) + 1)] = {"title": "既存の課題", "body": "x", "state": "OPEN", "reason": None}
json.dump(d, open(p, "w"))
PY
EXISTING="$(python3 -c "import json; print(len(json.load(open('$STUB/db.json'))['issues']))")"
expect_rc "start --issue: attaches the run" 0 "$BIN" start --title "mm-lab: oos gate" --body-file "$B/contract.md" --issue "$EXISTING"
RUN2="$(out_field run)"
[[ "$(subs_of "$EXISTING")" == "$RUN2" && "$(out_field parent)" == "$EXISTING" ]] && ok "start --issue: run is a sub-issue" || ng "start --issue: subs"
[[ "$(issue_field "$EXISTING" body)" == x ]] && ok "start --issue: existing body untouched" || ng "start --issue: body changed"
expect_rc "finish: not-done with no hypotheses" 0 "$BIN" finish --issue "$RUN2" --outcome not-done --body-file "$B/final.md"
[[ "$(issue_field "$RUN2" title)" == "[pursue:未達] mm-lab: oos gate" && "$(issue_field "$RUN2" state)" == OPEN ]] \
  && ok "finish: not-done marks the title and stays open" || ng "finish: not-done"

expect_rc "finish: not-done twice -> 2" 2 "$BIN" finish --issue "$RUN2" --outcome not-done --body-file "$B/final.md"
printf '打ち切り理由: holdout 消費済み\n' > "$B/abandon.md"
expect_rc "finish: abandon a not-done run" 0 "$BIN" finish --issue "$RUN2" --outcome abandoned --body-file "$B/abandon.md"
[[ "$(issue_field "$RUN2" title)" == "[pursue:打ち切り] mm-lab: oos gate" ]] && ok "finish: abandoned replaces the not-done mark" || ng "finish: abandoned title $(issue_field "$RUN2" title)"
[[ "$(issue_field "$RUN2" state)" == CLOSED && "$(issue_field "$RUN2" reason)" == "not planned" ]] \
  && ok "finish: abandoned closes as not planned" || ng "finish: abandoned state"
[[ "$(issue_field "$RUN2" body)" == *"## 最終報告（not-done）"*"## 最終報告（abandoned）"*"holdout 消費済み"* ]] \
  && ok "finish: both reports kept in order" || ng "finish: abandoned body"
expect_rc "start: run for direct abandon" 0 "$BIN" start --title "direct" --body-file "$B/contract.md"
RUN4="$(out_field run)"
expect_rc "finish: abandoned from a fresh run" 0 "$BIN" finish --issue "$RUN4" --outcome abandoned --body-file "$B/abandon.md"
[[ "$(issue_field "$RUN4" title)" == "[pursue:打ち切り] direct" && "$(issue_field "$RUN4" reason)" == "not planned" ]] \
  && ok "finish: abandoned directly" || ng "finish: abandoned directly"

# ---- gh failures surface -----------------------------------------------------------------------
STUB_FAIL_CREATE=1 expect_rc "create failure -> 1" 1 "$BIN" start --title t --body-file "$B/contract.md"
grep -q 'HTTP 502' "$SANDBOX/err" && ok "create failure: gh stderr surfaced" || ng "create failure: message"
expect_rc "start: third run" 0 "$BIN" start --title "attach check" --body-file "$B/contract.md"
RUN3="$(out_field run)"
STUB_DROP_ATTACH=1 expect_rc "attach not visible -> 1" 1 "$BIN" hypothesis --run "$RUN3" --title x --body-file "$B/hyp.md"

# ---- no comments --------------------------------------------------------------------------------
python3 -c "import json,sys; c=json.load(open(sys.argv[1]))['calls']; sys.exit(1 if ['issue','comment'] in c else 0)" "$STUB/db.json" \
  && ok "no Issue comments posted" || ng "an Issue comment was posted"

# ---- skill contract -----------------------------------------------------------------------------
grep -q 'pursue-issue start' "$SKILL" && grep -q 'pursue-issue hypothesis' "$SKILL" \
  && grep -q 'pursue-issue verdict' "$SKILL" && grep -q 'pursue-issue finish' "$SKILL" \
  && ok "skill: uses every subcommand" || ng "skill: subcommand missing"
grep -q -- '--no-issue' "$SKILL" && ok "skill: --no-issue documented" || ng "skill: --no-issue missing"
AUTH="$REPO_ROOT/docs/contracts/skill-authority.tsv"
awk -F'\t' '$1=="pursue" && $2=="default" && $7=="allow" && $5=="deny" && $6=="deny" {f=1} END {exit !f}' "$AUTH" \
  && ok "authority: default writes GitHub Issues, no commit or push" || ng "authority: default row"
awk -F'\t' '$1=="pursue" && $2=="--no-issue" && $7=="deny" {f=1} END {exit !f}' "$AUTH" \
  && ok "authority: --no-issue has no GitHub write" || ng "authority: --no-issue row"

if [[ "$FAILURES" -gt 0 ]]; then
  echo "$FAILURES pursue-issue test(s) failed" >&2
  exit 1
fi
echo "all pursue-issue tests passed"
