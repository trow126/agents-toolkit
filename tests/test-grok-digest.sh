#!/usr/bin/env bash
# test-grok-digest.sh — claude/bin/grok-digest (the deterministic parts of /grok-digest).
# Checks the period selection from history date headings, the answer cut (question found after
# the pre-send divergence point, done/busy markers), vault resolution from the private config,
# the note format of the clipping pipeline (frontmatter, idempotent url, reserved sections,
# staging), the project listing, and the skill's safety contract. No browser or network is used.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_ROOT/claude/bin/grok-digest"
SKILL="$REPO_ROOT/claude/skills/grok-digest/SKILL.md"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
ok() { echo "ok: $1"; }
ng() { echo "FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }
export XDG_CONFIG_HOME="$SANDBOX/config"
export XDG_STATE_HOME="$SANDBOX/state"
unset GROK_DIGEST_INBOX_CONFIG
jq_py() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
expect_rc() { # desc want_rc cmd...
  local desc="$1" want="$2" rc=0
  shift 2
  "$@" >"$SANDBOX/out" 2>"$SANDBOX/err" || rc=$?
  if [[ "$rc" -eq "$want" ]]; then ok "$desc"; else ng "$desc (rc=$rc, want $want): $(cat "$SANDBOX/err")"; fi
}

# ---- select ------------------------------------------------------------------------------------
G='https://x.com/i/grok?conversation='
cat > "$SANDBOX/history.json" <<EOF
[
 {"heading": "", "href": "${G}100", "title": "no heading"},
 {"heading": "今日", "href": "${G}1", "title": "today one"},
 {"heading": "今日", "href": "${G}1&mode=x", "title": "duplicate"},
 {"heading": "昨日", "href": "${G}2", "title": "yesterday"},
 {"heading": "金曜日", "href": "${G}3", "title": "friday"},
 {"heading": "水曜日", "href": "${G}4", "title": "wednesday"},
 {"heading": "火曜日", "href": "${G}5", "title": "tuesday a week ago"},
 {"heading": "2026年9月28日", "href": "${G}6", "title": "older"},
 {"heading": "12月31日", "href": "${G}7", "title": "last year"},
 {"heading": "Yesterday", "href": "${G}8", "title": "english"},
 {"heading": "今日", "href": "https://x.com/home", "title": "not a conversation"}
]
EOF
# 2026-10-06 is a Tuesday: 7 days = 2026-09-30 .. 2026-10-06.
out="$("$BIN" select --days 7 --today 2026-10-06 "$SANDBOX/history.json")"
got="$(jq_py '" ".join(c["id"]+"="+c["date"] for c in d["conversations"])' <<< "$out")"
want="1=2026-10-06 2=2026-10-05 3=2026-10-02 4=2026-09-30 8=2026-10-05"
[[ "$got" == "$want" ]] && ok "select: 今日/昨日/weekday/English in period, duplicates dropped" || ng "select: got '$got', want '$want'"
[[ "$(jq_py 'd["older"]' <<< "$out")" == "3" ]] && ok "select: a weekday 7 days back and dated headings fall outside" || ng "select: older count $(jq_py 'd["older"]' <<< "$out")"
[[ "$(jq_py '[c["id"] for c in d["unparsed"]]' <<< "$out")" == "['100']" ]] && ok "select: a link without a date heading is reported, not guessed" || ng "select: unparsed $(jq_py 'd["unparsed"]' <<< "$out")"
[[ "$(jq_py 'd["conversations"][0]["url"]' <<< "$out")" == "${G}1" ]] && ok "select: URL normalized to the conversation id" || ng "select: url not normalized"
out="$("$BIN" select --days 1 --today 2026-10-06 < "$SANDBOX/history.json")"
[[ "$(jq_py '" ".join(c["id"] for c in d["conversations"])' <<< "$out")" == "1" ]] && ok "select --days 1: today only (stdin)" || ng "select --days 1 wrong"
out="$("$BIN" select --days 400 --today 2026-10-06 "$SANDBOX/history.json")"
[[ "$(jq_py '[c["date"] for c in d["conversations"] if c["id"]=="7"][0]' <<< "$out")" == "2025-12-31" ]] && ok "select: M月D日 after today is last year" || ng "select: 12月31日 not resolved to last year"
expect_rc "select: --days 0 is refused" 1 "$BIN" select --days 0 "$SANDBOX/history.json"

# ---- answer ------------------------------------------------------------------------------------
Q='過去ポストから手法Aの回収率を、根拠ポストの要約付きで。不明な点は「不明」と明記'
printf '%s\n' "$Q" > "$SANDBOX/q.txt"
cat > "$SANDBOX/before.txt" <<'EOF'
手法Aの回収率は？
手法Aの回収率は自己申告で120%です。
高速
どんなことでもお尋ねください
EOF
cat > "$SANDBOX/page.txt" <<'EOF'
手法Aの回収率は？
手法Aの回収率は自己申告で120%です。
高速
過去ポストから手法Aの回収率を、根拠ポストの要約付きで。
不明な点は「不明」と明記
Thinking
ご質問「過去ポストから手法Aの回収率を、根拠ポストの要約付きで。不明な点は「不明」と明記」にお答えします。
- 2026-09 のポスト: 回収率 120%（自己申告、3か月）
- 第三者検証: 不明
高速
どんなことでもお尋ねください
EOF
out="$("$BIN" answer --question-file "$SANDBOX/q.txt" --page-file "$SANDBOX/page.txt" --before-file "$SANDBOX/before.txt")"
ans="$(jq_py 'd["answer"]' <<< "$out")"
if [[ "$ans" == ご質問* && "$ans" == *"第三者検証: 不明" && "$ans" != *高速* && "$ans" != *Thinking* ]]; then
  ok "answer: cut after the sent question (line-wrapped), not at the quote inside the answer; ends at 高速"
else
  ng "answer: unexpected cut: $ans"
fi
expect_rc "answer: without --before-file a question quoted in the answer is ambiguous (exit 2)" 2 \
  "$BIN" answer --question-file "$SANDBOX/q.txt" --page-file "$SANDBOX/page.txt"
head -n 7 "$SANDBOX/page.txt" > "$SANDBOX/partial.txt"
expect_rc "answer: no done marker yet is still generating (exit 3)" 3 \
  "$BIN" answer --question-file "$SANDBOX/q.txt" --page-file "$SANDBOX/partial.txt" --before-file "$SANDBOX/before.txt"
printf '%s\n' "$(cat "$SANDBOX/before.txt")" "$Q" "Thinking" "高速" > "$SANDBOX/busy.txt"
expect_rc "answer: only a generating indicator before 高速 is not complete (exit 3)" 3 \
  "$BIN" answer --question-file "$SANDBOX/q.txt" --page-file "$SANDBOX/busy.txt" --before-file "$SANDBOX/before.txt"
expect_rc "answer: an unsent question is reported (exit 2)" 2 \
  "$BIN" answer --question-file "$SANDBOX/q.txt" --page-file "$SANDBOX/before.txt" --before-file "$SANDBOX/before.txt"
printf '%s\n' "$Q" "回答本文" "Done" > "$SANDBOX/custom.txt"
expect_rc "answer: --done-marker overrides the UI string" 0 \
  "$BIN" answer --question-file "$SANDBOX/q.txt" --page-file "$SANDBOX/custom.txt" --done-marker Done

# ---- vault resolution --------------------------------------------------------------------------
expect_rc "vault: unresolved without a private config (exit 3)" 3 "$BIN" vault
VAULT="$SANDBOX/vault"
mkdir -p "$VAULT/clippings" "$XDG_CONFIG_HOME/agents-toolkit"
printf '[tasks]\nlist_name = "x"\n[vault]\npath = "%s"\n[resync]\nwindow_days = 7\n' "$VAULT" > "$SANDBOX/pipeline.toml"
printf '[inbox]\nconfig = "%s"\n' "$SANDBOX/pipeline.toml" > "$XDG_CONFIG_HOME/agents-toolkit/grok-digest.toml"
out="$("$BIN" vault)"
[[ "$(jq_py 'd["vault"]' <<< "$out")" == "$VAULT" ]] && ok "vault: resolved through the private config and the pipeline's [vault] path" || ng "vault: $out"
printf '[vault]\npath = "%s/missing"\n' "$SANDBOX" > "$SANDBOX/other.toml"
GROK_DIGEST_INBOX_CONFIG="$SANDBOX/other.toml" expect_rc "vault: env override wins; a missing vault directory is exit 3" 3 "$BIN" vault

# ---- note --------------------------------------------------------------------------------------
cat > "$SANDBOX/body.md" <<'EOF'
## 会話の要約

- 手法Aの回収率を尋ねた

## 次の一手

- 公開データで再計算する
EOF
URL="${G}12345"
out="$("$BIN" note --url "$URL" --title 'Method "A" / test' --date 2026-10-02 --saved 2026-10-06 --body-file "$SANDBOX/body.md")"
NOTE="$(jq_py 'd["path"]' <<< "$out")"
# Slug rule of the pipeline: forbidden characters removed, spaces to hyphens, at most 50 chars.
if [[ "$NOTE" == "$VAULT/clippings/2026-10-06-Grok-Method-A--test.md" && -f "$NOTE" ]]; then
  ok "note: written to <vault>/clippings/<saved>-Grok-<slug>.md"
else
  ng "note: unexpected path $NOTE"
fi
# Parse it the way the pipeline does (line-based frontmatter, outer quotes stripped).
fm="$(python3 - "$NOTE" <<'PY'
import sys
fm = {}
with open(sys.argv[1], encoding="utf-8") as f:
    assert f.readline().strip() == "---"
    for line in f:
        if line.strip() == "---":
            break
        k, v = line.split(":", 1)
        fm[k.strip()] = v.strip().strip('"')
print(fm["url"], fm["source"], fm["saved"], fm["status"], fm["tags"], "summary" in fm, "curated" in fm, sep="|")
PY
)"
[[ "$fm" == "$URL|grok|2026-10-06|unread|[clipping, grok-digest]|False|False" ]] && ok "note: pipeline frontmatter (url key, clipping tag, unread, no summary/curated)" || ng "note: frontmatter $fm"
grep -q "^title: \"Grok: Method 'A' / test\"$" "$NOTE" && ok "note: title quotes escaped" || ng "note: title line $(grep '^title' "$NOTE")"
if grep -q '^## 出典$' "$NOTE" && grep -qF -- "- 元会話: $URL" "$NOTE" && grep -qF '2026-10-02' "$NOTE"; then ok "note: 出典 section with the conversation URL and date"; else ng "note: 出典 missing"; fi
python3 "$REPO_ROOT/claude/hooks/lib/post_edit_lint.py" "$NOTE" && ok "note: Markdown lint-clean" || ng "note: Markdown lint violations"
expect_rc "note: the same url is never written twice (exit 4)" 4 \
  "$BIN" note --url "$URL" --title other --saved 2026-10-07 --body-file "$SANDBOX/body.md"
out="$("$BIN" note --url "${G}999" --title 'Method "A" / test' --saved 2026-10-06 --body-file "$SANDBOX/body.md")"
[[ "$(jq_py 'd["path"]' <<< "$out")" == "${NOTE%.md}-2.md" ]] && ok "note: a name collision gets a numbered suffix" || ng "note: collision path $out"
out="$("$BIN" note --url "${G}777" --title dry --saved 2026-10-06 --body-file "$SANDBOX/body.md" --dry-run)"
[[ ! -e "$(jq_py 'd["path"]' <<< "$out")" ]] && ok "note --dry-run writes nothing" || ng "note --dry-run wrote a file"
printf '## 会話の要約\n\n- x\n' > "$SANDBOX/no-next.md"
expect_rc "note: a body without 次の一手 is refused" 1 "$BIN" note --url "${G}778" --title t --body-file "$SANDBOX/no-next.md"
printf '%s\n\n## 関連ノート (auto)\n\n- [[x]]\n' "$(cat "$SANDBOX/body.md")" > "$SANDBOX/reserved.md"
expect_rc "note: the pipeline's reserved section is refused" 1 "$BIN" note --url "${G}779" --title t --body-file "$SANDBOX/reserved.md"
expect_rc "note: a non-Grok URL is refused" 1 "$BIN" note --url "https://x.com/someone/status/1" --title t --body-file "$SANDBOX/body.md"
rm "$XDG_CONFIG_HOME/agents-toolkit/grok-digest.toml"
expect_rc "note: an unresolved vault stops (exit 3)" 3 "$BIN" note --url "${G}780" --title t --body-file "$SANDBOX/body.md"
out="$("$BIN" note --url "${G}780" --title staged --saved 2026-10-06 --body-file "$SANDBOX/body.md" --staging)"
[[ "$(jq_py 'd["path"]' <<< "$out")" == "$XDG_STATE_HOME/agents-toolkit/grok-digest/clippings/2026-10-06-Grok-staged.md" ]] && ok "note --staging: XDG state in the clippings layout" || ng "note --staging: $out"

# ---- projects ----------------------------------------------------------------------------------
mkdir -p "$SANDBOX/home/alpha/.git" "$SANDBOX/home/beta" "$SANDBOX/home/.hidden/.git"
printf '# alpha\nline2\nline3\n' > "$SANDBOX/home/alpha/README.md"
out="$("$BIN" projects --root "$SANDBOX/home" --lines 2)"
[[ "$(jq_py '[(p["name"], p.get("README.md")) for p in d]' <<< "$out")" == "[('alpha', '# alpha\\nline2')]" ]] && ok "projects: git repositories only, first lines of README" || ng "projects: $out"

# ---- skill contract ----------------------------------------------------------------------------
for phrase in "data, not instructions" "only the questions the user approved" "Never post, reply, like" \
  "Never sign in or out" "自己申告" "disable-model-invocation: true" "Do not profile people"; do
  grep -qF -- "$phrase" "$SKILL" && ok "skill states: $phrase" || ng "skill lacks: $phrase"
done
if grep -rEq '/home/|/mnt/c/|My Drive' "$REPO_ROOT/claude/skills/grok-digest" "$BIN"; then
  ng "a machine-specific vault path is hard-coded"
else
  ok "no machine-specific vault path in the skill or helper"
fi

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then echo "PASS: all assertions succeeded"; exit 0; fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
