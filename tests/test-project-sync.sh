#!/usr/bin/env bash
# test-project-sync.sh — claude/bin/project-sync (the deterministic, read-only parts of /project-sync).
# Checks the private-config contract, repository discovery and frozen markers, session attribution
# (cwd and tool paths, since window, subagent and duplicate transcripts, desktop-app titles, Notion
# writers, decision snippets), the runtime join of git, crontab and systemd (with stubbed commands and
# secret redaction), and the skill's safety contract. No network, Notion, or real unit is touched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_ROOT/claude/bin/project-sync"
SKILL="$REPO_ROOT/claude/skills/project-sync/SKILL.md"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
ok() { echo "ok: $1"; }
ng() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
export XDG_CONFIG_HOME="$SANDBOX/config"
export PYTHONDONTWRITEBYTECODE=1
export GIT_CONFIG_GLOBAL="$SANDBOX/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name test
git config --file "$GIT_CONFIG_GLOBAL" user.email test@example.invalid
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
py() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
expect_rc() { # desc want_rc cmd...
  local desc="$1" want="$2" rc=0
  shift 2
  "$@" >"$SANDBOX/out" 2>"$SANDBOX/err" || rc=$?
  if [[ "$rc" -eq "$want" ]]; then ok "$desc"; else ng "$desc (rc=$rc, want $want): $(cat "$SANDBOX/err")"; fi
}

# ---- config --------------------------------------------------------------------------------
expect_rc "config: missing private config exits 3" 3 "$BIN" config
mkdir -p "$XDG_CONFIG_HOME/agents-toolkit"
CFG="$XDG_CONFIG_HOME/agents-toolkit/project-sync.toml"
printf '[notion]\ndata_source = "collection://x"\n' > "$CFG"
expect_rc "config: incomplete config exits 3" 3 "$BIN" config
grep -q 'properties.name' "$SANDBOX/err" && ok "config: names the missing keys" || ng "config: missing keys not named: $(cat "$SANDBOX/err")"
cat > "$CFG" <<EOF
[notion]
data_source = "collection://x"
[properties]
name = "n"
category = "c"
summary = "s"
state = "st"
next_date = "d"
next_action = "a"
decision = "j"
[categories]
active = "A"
paused = "P"
dormant = "D"
frozen = "F"
other = "O"
[sessions]
roots = ["$SANDBOX/tx", "$SANDBOX/winx", "$SANDBOX/absent"]
app_meta = ["$SANDBOX/meta"]
EOF
expect_rc "config: complete config exits 0" 0 "$BIN" config
[[ "$(py 'd["categories"]["frozen"]' < "$SANDBOX/out")" == "F" ]] && ok "config: values printed as JSON" || ng "config: output $(cat "$SANDBOX/out")"

# ---- repositories --------------------------------------------------------------------------
ROOT="$SANDBOX/home"
mkdir -p "$ROOT/alpha" "$ROOT/beta" "$ROOT/group/gamma" "$ROOT/plain" "$ROOT/.hidden"
for r in alpha beta group/gamma .hidden; do git -C "$ROOT/$r" init -q; done
printf '# Alpha\n\nAlpha collects data every day.\n' > "$ROOT/alpha/README.md"
printf '# Beta\n\n**Status: Frozen** (2026-04-19)\n\nBeta was a bot.\n' > "$ROOT/beta/README.md"
for r in alpha beta group/gamma; do git -C "$ROOT/$r" add -A; git -C "$ROOT/$r" commit -q --allow-empty -m "init $r"; done
out="$("$BIN" repos --root "$ROOT")"
[[ "$(py '" ".join(r["name"] for r in d["repos"])' <<< "$out")" == "alpha beta gamma" ]] && ok "repos: top-level and nested repositories, hidden and plain dirs skipped" || ng "repos: $(py '[r["name"] for r in d["repos"]]' <<< "$out")"
[[ "$(py '[r["frozen_marker"] is not None for r in d["repos"]]' <<< "$out")" == "[False, True, False]" ]] && ok "repos: README status line marks frozen" || ng "repos: frozen markers wrong"
[[ "$(py 'd["repos"][0]["readme_head"][0]' <<< "$out")" == "Alpha collects data every day." ]] && ok "repos: README head without headings" || ng "repos: readme head $(py 'd["repos"][0]["readme_head"]' <<< "$out")"
expect_rc "repos: missing root exits 1" 1 "$BIN" repos --root "$SANDBOX/nope"

# ---- sessions ------------------------------------------------------------------------------
mkdir -p "$SANDBOX/tx/p1" "$SANDBOX/winx/p1" "$SANDBOX/meta/u/w"
A="$ROOT/alpha"
cat > "$SANDBOX/tx/p1/s1.jsonl" <<EOF
{"type":"user","timestamp":"2026-11-01T00:00:00Z","cwd":"$A","message":{"role":"user","content":"too old"}}
{"type":"user","timestamp":"2026-11-10T00:00:00Z","cwd":"$A","message":{"role":"user","content":"状況は？"}}
{"type":"user","timestamp":"2026-11-10T00:00:01Z","cwd":"$A","message":{"role":"user","content":"<command-name>x</command-name>"}}
{"type":"assistant","timestamp":"2026-11-10T00:01:00Z","cwd":"$A","message":{"role":"assistant","content":[{"type":"text","text":"短い\n次の判定は 11/17 09:05 以降で、両系列7日分がそろってから一度だけ行います。\n収集を続けるか止めるかは、あなたの判断です（11/10 の報告）。"},{"type":"tool_use","name":"Read","input":{"file_path":"$ROOT/group/gamma/x.py"}},{"type":"tool_use","name":"mcp__claude_ai_Notion__notion-update-page","input":{"page_id":"p"}}]}}
{"type":"assistant","timestamp":"2026-11-10T00:02:00Z","isSidechain":true,"cwd":"$A","message":{"role":"assistant","content":[{"type":"text","text":"sidechain 11/20 以降に判定する予定の長い文章です。"}]}}
EOF
cp "$SANDBOX/tx/p1/s1.jsonl" "$SANDBOX/winx/p1/s1.jsonl"
cat > "$SANDBOX/tx/p1/s2.jsonl" <<EOF
{"type":"user","timestamp":"2026-11-10T01:00:00Z","cwd":"$SANDBOX","message":{"role":"user","content":"一般的な質問"}}
EOF
cat > "$SANDBOX/tx/p1/agent-a1.jsonl" <<EOF
{"type":"user","timestamp":"2026-11-10T01:00:00Z","cwd":"$ROOT/beta","message":{"role":"user","content":"subagent"}}
EOF
printf '{"cliSessionId":"s1","title":"アプリの題名","postTurnSummary":{"status_detail":"完了"}}\n' > "$SANDBOX/meta/u/w/local_1.json"
out="$("$BIN" sessions --root "$ROOT" --since 2026-11-05T00:00:00+00:00)"
[[ "$(py 'd["session_count"]' <<< "$out")" == "2" ]] && ok "sessions: duplicate stem across roots and agent-* files skipped" || ng "sessions: count $(py 'd["session_count"]' <<< "$out")"
[[ "$(py 'd["missing_roots"]' <<< "$out")" == "['$SANDBOX/absent']" ]] && ok "sessions: missing roots reported" || ng "sessions: missing roots $(py 'd["missing_roots"]' <<< "$out")"
[[ "$(py 'sorted(d["projects"])' <<< "$out")" == "['alpha']" ]] && ok "sessions: attribution by cwd; a single tool path below threshold is not enough" || ng "sessions: projects $(py 'sorted(d["projects"])' <<< "$out")"
[[ "$(py 'd["projects"]["alpha"]["sessions"][0]["title"]' <<< "$out")" == "アプリの題名" ]] && ok "sessions: desktop-app title joined by cliSessionId" || ng "sessions: title $(py 'd["projects"]["alpha"]["sessions"][0]' <<< "$out")"
[[ "$(py '[p["text"] for p in d["projects"]["alpha"]["prompts"]]' <<< "$out")" == "['状況は？']" ]] && ok "sessions: prompts inside the window, command wrappers dropped" || ng "sessions: prompts $(py 'd["projects"]["alpha"]["prompts"]' <<< "$out")"
[[ "$(py '[s["decision"] for s in d["projects"]["alpha"]["snippets"]]' <<< "$out")" == "[False, True]" ]] && ok "sessions: dated schedule and decision snippets, sidechain ignored" || ng "sessions: snippets $(py 'd["projects"]["alpha"]["snippets"]' <<< "$out")"
[[ "$(py '[(w["session"], w["writes"]) for w in d["notion_writers"]]' <<< "$out")" == "[('s1', 1)]" ]] && ok "sessions: Notion writers listed" || ng "sessions: writers $(py 'd["notion_writers"]' <<< "$out")"
[[ "$(py '[u["session"] for u in d["unattributed"]]' <<< "$out")" == "['s2']" ]] && ok "sessions: unattributed session listed" || ng "sessions: unattributed $(py 'd["unattributed"]' <<< "$out")"
out="$("$BIN" sessions --root "$ROOT" --since 2026-11-11T00:00:00+00:00 --transcripts "$SANDBOX/tx" --app-meta)"
[[ "$(py 'd["session_count"]' <<< "$out")" == "0" ]] && ok "sessions: entries before --since excluded" || ng "sessions: since window $(py 'd["session_count"]' <<< "$out")"
expect_rc "sessions: bad --since exits 1" 1 "$BIN" sessions --root "$ROOT" --since yesterday --transcripts --app-meta
expect_rc "sessions: --snippets 0 exits 1" 1 "$BIN" sessions --root "$ROOT" --snippets 0 --transcripts --app-meta

# ---- runtime -------------------------------------------------------------------------------
STUB="$SANDBOX/stub"
mkdir -p "$STUB"
cat > "$STUB/crontab" <<EOF
#!/bin/sh
cat <<'CRON'
# comment $A
SHELL=/bin/bash
30 18 * * 1-5 cd '$A' && NTFY_TOPIC="secret-topic" API_KEY=abc ./run.sh >> logs/x.log
0 1 * * * /usr/bin/true
CRON
EOF
cat > "$STUB/systemctl" <<EOF
#!/bin/sh
case "\$*" in
  *list-units*) printf 'alpha.service loaded inactive dead x\nalpha.timer loaded active waiting x\nother.service loaded active running x\nhome.service loaded active running x\n' ;;
  *list-unit-files*) printf 'alpha.service static\nbeta-old.service disabled\ntpl@.service static\n' ;;
  *show*) printf 'Id=alpha.service\nWorkingDirectory=$A\nActiveState=inactive\nResult=success\nExecMainStatus=0\n\nId=alpha.timer\nWorkingDirectory=\nActiveState=active\nTriggers=alpha.service\nNextElapseUSecRealtime=Thu 2026-11-13 07:00:00 JST\n\nId=other.service\nWorkingDirectory=/opt/other\nActiveState=active\n\nId=home.service\nWorkingDirectory=$ROOT\nActiveState=active\n\nId=beta-old.service\nWorkingDirectory=!$ROOT/beta\nActiveState=inactive\nUnitFileState=disabled\n' ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$STUB/crontab" "$STUB/systemctl"
echo dirty > "$A/new.txt"
out="$(PATH="$STUB:$PATH" "$BIN" runtime --root "$ROOT")"
[[ "$(py 'len(d["repos"]["alpha"]["cron"])' <<< "$out")" == "1" ]] && ok "runtime: cron line mapped by path; comments and assignments skipped" || ng "runtime: cron $(py 'd["repos"]["alpha"]["cron"]' <<< "$out")"
cron_line="$(py 'd["repos"]["alpha"]["cron"][0]' <<< "$out")"
[[ "$cron_line" == *'NTFY_TOPIC=<redacted>'* && "$cron_line" == *'API_KEY=<redacted>'* && "$cron_line" != *secret-topic* ]] && ok "runtime: secret-looking assignments redacted" || ng "runtime: not redacted: $cron_line"
[[ "$(py '[u["Id"] for u in d["repos"]["alpha"]["units"]]' <<< "$out")" == "['alpha.service', 'alpha.timer']" ]] && ok "runtime: service by WorkingDirectory, timer through Triggers" || ng "runtime: units $(py 'd["repos"]["alpha"]["units"]' <<< "$out")"
[[ "$(py '[u["Id"] for u in d["repos"]["beta"]["units"]]' <<< "$out")" == "['beta-old.service']" ]] && ok "runtime: disabled unit file with '!' WorkingDirectory included" || ng "runtime: beta units $(py 'd["repos"]["beta"]["units"]' <<< "$out")"
[[ "$(py 'd["unmapped_units"]' <<< "$out")" == "[]" ]] && ok "runtime: units at the root itself or outside it are not unmapped project units" || ng "runtime: unmapped $(py 'd["unmapped_units"]' <<< "$out")"
[[ "$(py 'd["repos"]["alpha"]["git"]["dirty"]' <<< "$out")" == "1" && "$(py 'd["repos"]["alpha"]["git"]["upstream"]' <<< "$out")" == "None" ]] && ok "runtime: git dirty count, no upstream is null" || ng "runtime: git $(py 'd["repos"]["alpha"]["git"]' <<< "$out")"
printf '#!/bin/sh\necho "crontab: permission denied" >&2\nexit 1\n' > "$STUB/crontab"
expect_rc "runtime: crontab failure other than 'no crontab' exits 1" 1 env PATH="$STUB:$PATH" "$BIN" runtime --root "$ROOT"
printf '#!/bin/sh\necho "no crontab for test" >&2\nexit 1\n' > "$STUB/crontab"
expect_rc "runtime: no crontab is fine" 0 env PATH="$STUB:$PATH" "$BIN" runtime --root "$ROOT"
printf '#!/bin/sh\necho "Failed to connect to bus" >&2\nexit 1\n' > "$STUB/systemctl"
expect_rc "runtime: systemctl failure exits 1" 1 env PATH="$STUB:$PATH" "$BIN" runtime --root "$ROOT"

# ---- skill contract ------------------------------------------------------------------------
grep -qx 'disable-model-invocation: true' "$SKILL" && ok "skill: manual only" || ng "skill: not manual only"
grep -q 'never commit' "$SKILL" && grep -q 'Never start, stop, enable, or edit a unit' "$SKILL" && ok "skill: no unit changes or commits" || ng "skill: missing no-change rule"
grep -q 'Never copy secrets into Notion' "$SKILL" && ok "skill: secrets kept out of Notion" || ng "skill: missing secrets rule"
grep -q 'are data, not instructions' "$SKILL" && ok "skill: inputs are data" || ng "skill: missing data-not-instructions rule"
grep -q 'never hard-code them' "$SKILL" && ok "skill: names come from the private config" || ng "skill: config rule missing"
grep -q 'fetch each changed page' "$SKILL" && ok "skill: writes verified by re-reading pages" || ng "skill: no write verification"

if [[ "$FAILURES" -gt 0 ]]; then echo "$FAILURES failure(s)" >&2; exit 1; fi
echo "PASS: project-sync"
