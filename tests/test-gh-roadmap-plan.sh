#!/usr/bin/env bash
# test-gh-roadmap-plan.sh — claude/bin/gh-roadmap-plan (the deterministic parts of /gh-roadmap-plan).
# Uses a stub `gh` that keeps repositories, Issues, and sub-issues in a sandbox directory and a
# local bare repository as the remote. Checks the preconditions of check/init, the manifest
# validation (placeholders, checklist order, parent reference), Issue creation with real numbers,
# sub-issue order, resume after a failure without duplicates, the duplicate-title stop, and the
# skill's authority contract. No network is used.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_ROOT/claude/bin/gh-roadmap-plan"
SKILL="$REPO_ROOT/shared/skills/gh-roadmap-plan/SKILL.md"
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
jq_py() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

export HOME="$SANDBOX/home"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig"
: > "$GIT_CONFIG_GLOBAL"
export STUB="$SANDBOX/gh-state"
mkdir -p "$HOME/.agents/rules" "$HOME/.github/ISSUE_TEMPLATE/manual" "$SANDBOX/stubbin" "$STUB"
echo "## Issue Completeness Policy" > "$HOME/.agents/rules/issue-completeness.md"
echo "## Purpose / 目的" > "$HOME/.github/ISSUE_TEMPLATE/manual/backlog_umbrella.md"

# ---- stub gh -----------------------------------------------------------------------------------
cat > "$SANDBOX/stubbin/gh" <<'PY'
#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path
S = Path(os.environ["STUB"]); a = sys.argv[1:]
db = S / "db.json"
d = json.loads(db.read_text()) if db.exists() else {"repos": {}, "issues": {}, "subs": {}, "creates": 0}
def save(): db.write_text(json.dumps(d))
def opt(name, default=None):
    return a[a.index(name) + 1] if name in a else default
if a[:2] == ["auth", "status"]:
    sys.exit(1 if os.environ.get("STUB_NO_AUTH") else 0)
if a[:2] == ["repo", "view"]:
    r = d["repos"].get(a[2])
    if r is None: sys.exit(1)
    print(json.dumps(r)); sys.exit(0)
if a[:2] == ["repo", "create"]:
    repo, src = a[2], Path(opt("--source"))
    bare = S / "remotes" / (repo.replace("/", "_") + ".git")
    subprocess.run(["git", "init", "-q", "--bare", str(bare)], check=True)
    subprocess.run(["git", "-C", str(src), "remote", "add", "origin", str(bare)], check=True)
    subprocess.run(["git", "-C", str(src), "push", "-q", "-u", "origin", "HEAD"], check=True)
    d["repos"][repo] = {"name": repo.split("/")[1], "visibility": "PUBLIC" if "--public" in a else "PRIVATE",
                        "hasIssuesEnabled": True, "url": f"https://github.com/{repo}"}
    save(); sys.exit(0)
if a[:2] == ["issue", "list"]:
    repo = opt("-R"); iss = d["issues"].get(repo, {})
    rows = [{"number": int(n), "title": v["title"]} for n, v in iss.items()]
    if opt("--state") == "open": rows = [r for r in rows if iss[str(r["number"])]["state"] == "OPEN"]
    print(json.dumps(rows)); sys.exit(0)
if a[:2] == ["issue", "create"]:
    d["creates"] += 1
    if os.environ.get("STUB_FAIL_CREATE_AT") == str(d["creates"]):
        save(); print("HTTP 502", file=sys.stderr); sys.exit(1)
    repo = opt("-R"); iss = d["issues"].setdefault(repo, {})
    n = len(iss) + 1 + int(os.environ.get("STUB_NUMBER_OFFSET", "0"))
    iss[str(n)] = {"title": opt("--title"), "body": opt("--body"), "state": "OPEN"}
    save(); print(f"https://github.com/{repo}/issues/{n}"); sys.exit(0)
if a[:2] == ["issue", "edit"]:
    d["issues"][opt("-R")][a[2]]["body"] = Path(opt("--body-file")).read_text(); save(); sys.exit(0)
if a[:2] == ["issue", "view"]:
    print(json.dumps({"body": d["issues"][opt("-R")][a[2]]["body"]})); sys.exit(0)
if a[0] == "api":
    path = [x for x in a[1:] if x.startswith("repos/")][0].split("?")[0].split("/")
    repo, n = f"{path[1]}/{path[2]}", path[4]
    if path[-1] == "sub_issues":
        subs = d["subs"].setdefault(f"{repo}#{n}", [])
        if "-X" in a:
            sid = int(opt("-F").split("=")[1]); subs.append(sid - 1000); save(); print("{}"); sys.exit(0)
        print(json.dumps([{"number": x} for x in subs])); sys.exit(0)
    print(json.dumps({"id": 1000 + int(n), "number": int(n)})); sys.exit(0)
print("stub gh: unsupported " + " ".join(a), file=sys.stderr); sys.exit(2)
PY
chmod +x "$SANDBOX/stubbin/gh"
export PATH="$SANDBOX/stubbin:$PATH"

# ---- templates ---------------------------------------------------------------------------------
expect_rc "templates: prints the rule and skeletons" 0 "$BIN" templates
grep -q 'Issue Completeness Policy' "$SANDBOX/out" && grep -q 'backlog_umbrella.md' "$SANDBOX/out" \
  && ok "templates: content present" || ng "templates: content missing"

# ---- check / init ------------------------------------------------------------------------------
STUB_NO_AUTH=1 expect_rc "check: gh not signed in -> 3" 3 "$BIN" check --repo me/demo --new --dir "$HOME/demo"
expect_rc "check --new: fresh name and absent dir" 0 "$BIN" check --repo me/demo --new --dir "$HOME/demo"
mkdir -p "$HOME/busy" && touch "$HOME/busy/x"
expect_rc "check --new: non-empty dir -> 2" 2 "$BIN" check --repo me/demo --new --dir "$HOME/busy"
expect_rc "check --existing: missing repo -> 2" 2 "$BIN" check --repo me/demo --existing
expect_rc "check: bad repo name -> 2" 2 "$BIN" check --repo demo --existing

W="$SANDBOX/work"; mkdir -p "$W"
echo "# demo" > "$W/README.md"; echo ".venv/" > "$W/gitignore"; printf 'chore: initialize demo\n' > "$W/msg"
expect_rc "init: creates folder, commit, private repo, push" 0 \
  "$BIN" init --repo me/demo --dir "$HOME/demo" --readme "$W/README.md" --gitignore "$W/gitignore" --message-file "$W/msg"
[[ "$(jq_py 'd["visibility"]' < "$SANDBOX/out")" == "PRIVATE" ]] && ok "init: private by default" || ng "init: visibility"
[[ "$(git -C "$HOME/demo" ls-files | sort | tr '\n' ' ')" == ".gitignore README.md " ]] \
  && ok "init: only README.md and .gitignore committed" || ng "init: committed files"
[[ "$(git -C "$HOME/demo" rev-list --count HEAD)" == "1" ]] && ok "init: one commit" || ng "init: commit count"
expect_rc "init: second run refuses (repo exists)" 2 \
  "$BIN" init --repo me/demo --dir "$HOME/demo2" --readme "$W/README.md" --gitignore "$W/gitignore" --message-file "$W/msg"
expect_rc "check --existing: lists open Issues" 0 "$BIN" check --repo me/demo --existing

# ---- manifest validation -----------------------------------------------------------------------
M="$SANDBOX/plan"; mkdir -p "$M"
write_plan() {
  cat > "$M/roadmap.md" <<'EOF'
## Child work items / 子Issue

- [ ] {{#prereg}} 事前登録
- [ ] {{#data}} データ
- [ ] {{#gate}} 判断

{{#data}} は {{#prereg}} の後。
EOF
  printf '親 Issue: {{#roadmap}}\n\n本文\n' > "$M/prereg.md"
  printf '親 Issue: {{#roadmap}}\n前提: {{#prereg}}\n' > "$M/data.md"
  printf '親 Issue: {{#roadmap}}\n前提: {{#data}}\n担当: ユーザー\n' > "$M/gate.md"
  cat > "$M/manifest.json" <<'EOF'
{"repo": "me/demo",
 "parent": {"key": "roadmap", "title": "ロードマップ: demo", "body_file": "roadmap.md"},
 "children": [
  {"key": "prereg", "title": "事前登録", "body_file": "prereg.md"},
  {"key": "data", "title": "データ取得", "body_file": "data.md"},
  {"key": "gate", "title": "【判断ゲート】Go/No-Go", "body_file": "gate.md"}]}
EOF
}
write_plan
expect_rc "create --dry-run: valid plan" 0 "$BIN" create "$M/manifest.json" --dry-run
[[ "$(jq_py '[i["gate"] for i in d["issues"]]' < "$SANDBOX/out")" == "[False, False, False, True]" ]] \
  && ok "dry-run: gate detected" || ng "dry-run: gate flag"
[[ ! -e "$STUB/db.json" ]] || [[ "$(jq_py 'len(d["issues"])' < "$STUB/db.json")" == "0" ]] \
  && ok "dry-run: no Issue created" || ng "dry-run created Issues"

sed -i 's/{{#data}} データ/{{#dta}} データ/' "$M/roadmap.md"
expect_rc "validate: unknown placeholder -> 2" 2 "$BIN" create "$M/manifest.json" --dry-run
write_plan; sed -i '/{{#data}} データ/d' "$M/roadmap.md"
expect_rc "validate: child missing from checklist -> 2" 2 "$BIN" create "$M/manifest.json" --dry-run
write_plan; printf -- '- [ ] {{#data}} a\n- [ ] {{#prereg}} b\n- [ ] {{#gate}} c\n' > "$M/roadmap.md"
expect_rc "validate: checklist out of order -> 2" 2 "$BIN" create "$M/manifest.json" --dry-run
write_plan; printf '本文だけ\n' > "$M/data.md"
expect_rc "validate: child without parent reference -> 2" 2 "$BIN" create "$M/manifest.json" --dry-run
grep -q 'does not reference the parent' "$SANDBOX/err" && ok "validate: names the reason" || ng "validate: reason"
write_plan

# ---- create with a failure in the middle, then resume -----------------------------------------
STUB_FAIL_CREATE_AT=3 expect_rc "create: fails on the 3rd Issue" 1 "$BIN" create "$M/manifest.json"
[[ "$(jq_py 'sorted(d["numbers"].values())' < "$M/manifest.json.state.json")" == "[1, 2]" ]] \
  && ok "state: records the 2 created Issues" || ng "state after failure"
expect_rc "create: rerun resumes" 0 "$BIN" create "$M/manifest.json"
[[ "$(jq_py 'len(d["issues"]["me/demo"])' < "$STUB/db.json")" == "4" ]] && ok "resume: no duplicate Issue" || ng "resume: duplicates"
[[ "$(jq_py 'd["subs"]["me/demo#1"]' < "$STUB/db.json")" == "[2, 3, 4]" ]] && ok "sub-issues attached in order" || ng "sub-issue order"
body1="$(jq_py 'd["issues"]["me/demo"]["1"]["body"]' < "$STUB/db.json")"
grep -q -- '- \[ \] #2 事前登録' <<< "$body1" && grep -q '#3 は #2 の後' <<< "$body1" \
  && ok "parent body rendered with real numbers" || ng "parent render: $body1"
[[ "$(jq_py 'd["issues"]["me/demo"]["4"]["body"]' < "$STUB/db.json" | head -1)" == "親 Issue: #1" ]] \
  && ok "child body references the parent number" || ng "child render"
expect_rc "create: rerun after completion is a no-op" 0 "$BIN" create "$M/manifest.json"
[[ "$(jq_py 'len(d["issues"]["me/demo"])' < "$STUB/db.json")" == "4" ]] && ok "no-op rerun creates nothing" || ng "no-op rerun"

# ---- duplicate title without state --------------------------------------------------------------
rm "$M/manifest.json.state.json"
expect_rc "create: existing title unknown to the state -> 2" 2 "$BIN" create "$M/manifest.json"
[[ "$(jq_py 'len(d["issues"]["me/demo"])' < "$STUB/db.json")" == "4" ]] && ok "duplicate stop creates nothing" || ng "duplicate stop"

# ---- skill contract ----------------------------------------------------------------------------
grep -q '^disable-model-invocation: true' "$SKILL" && ok "skill: user-invoked only (Claude)" || ng "skill: model invocation"
grep -q 'allow_implicit_invocation: false' "$REPO_ROOT/shared/skills/gh-roadmap-plan/agents/openai.yaml" \
  && ok "skill: user-invoked only (Codex)" || ng "skill: Codex implicit invocation"
grep -q '\*\*private\*\*' "$SKILL" && grep -q 'never touches files, commits, or pushes' "$SKILL" \
  && ok "skill: authority limits stated" || ng "skill: authority text"

if [[ "$FAILURES" -gt 0 ]]; then echo "$FAILURES failure(s)" >&2; exit 1; fi
echo "all gh-roadmap-plan tests passed"
