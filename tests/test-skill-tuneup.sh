#!/usr/bin/env bash
# /skill-tuneup: skill-tuneup prepare, record, finish, and plan on a fixture toolkit, the Workflow
# script run against a mock agent() (node), and the skill's static contract. No model is called.
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

# A fixture toolkit: a shared skill, a per-runtime pair with shared references, a Claude-only skill,
# a deprecated Codex-only skill, and the helper with its skill directory.
TK="$SANDBOX/toolkit"
mkdir -p "$TK/claude/bin" "$TK/claude/skills/skill-tuneup/references"
cp "$REPO_ROOT/claude/bin/skill-tuneup" "$REPO_ROOT/claude/bin/delegation_common.py" "$TK/claude/bin/"
cp "$REPO_ROOT/claude/skills/skill-tuneup/SKILL.md" "$TK/claude/skills/skill-tuneup/"
cp "$REPO_ROOT/claude/skills/skill-tuneup/references/result.schema.json" "$TK/claude/skills/skill-tuneup/references/"
TUNE="$TK/claude/bin/skill-tuneup"
skill() { # <dir> <name> <description> [body]
  mkdir -p "$TK/$1"
  printf -- '---\nname: %s\ndescription: "%s"\n---\n\n# %s\n\n%s\n' "$2" "$3" "$2" "${4:-}" > "$TK/$1/SKILL.md"
}
skill shared/skills/alpha alpha "Does alpha things."
mkdir -p "$TK/shared/skills/pair/references"
printf '# pair evidence\n' > "$TK/shared/skills/pair/references/evidence.md"
skill shared/skills/claude-code/pair pair "Pair for Claude." 'Read [`references/evidence.md`](../../pair/references/evidence.md).'
skill shared/skills/codex/pair pair "Pair for Codex." 'Read [`references/evidence.md`](../../pair/references/evidence.md).'
skill claude/skills/beta beta "Beta, Claude only."
mkdir -p "$TK/claude/skills/beta/references" && printf 'X=1\n' > "$TK/claude/skills/beta/references/route.env"
skill codex/skills/gamma gamma "Deprecated (2026-10). Gamma."
git -C "$TK" init -q -b main
git -C "$TK" config user.email fixture@example.invalid
git -C "$TK" config user.name Fixture
git -C "$TK" config commit.gpgsign false
git -C "$TK" add -A && git -C "$TK" commit -q -m base

export PYTHONDONTWRITEBYTECODE=1 XDG_STATE_HOME="$SANDBOX/state"
RC=0; OUT=""
run() { RC=0; OUT="$("$@" 2>&1)" || RC=$?; }
expect_rc() { # desc want_rc needle
  if [[ "$RC" -eq "$2" && "$OUT" == *"$3"* ]]; then ok "$1"; else ng "$1 (rc=$RC, want $2 containing '$3'): $OUT"; fi
}

# ---- prepare
run "$TUNE" prepare --only alpha,nope
expect_rc "--only の未知の skill は拒否する" 1 "unknown skill(s) for --only: nope"
run "$TUNE" prepare
expect_rc "prepare は run を作る" 0 '"count": 5'
PREP="$OUT"
RUN="$(jq -r .run_dir <<< "$PREP")"
if jq -e '[.skills[].name] == ["alpha","beta","gamma","pair","skill-tuneup"]' <<< "$PREP" >/dev/null &&
  jq -e '.estimated_agents == {"min": 43, "max": 83}' <<< "$PREP" >/dev/null; then
  ok "同名の pair は1つの skill にまとめ、推定エージェント数を出す（3 + 5 x 8..16）"
else
  ng "prepare の skill 一覧か推定が不正: $PREP"
fi
if jq -e --arg ev "$TK/shared/skills/pair/references/evidence.md" '.skills[] | select(.name == "pair") | .files | index($ev) != null' <<< "$PREP" >/dev/null &&
  jq -e '.skills[] | select(.name == "beta") | .files | map(endswith("route.env")) | any' <<< "$PREP" >/dev/null &&
  jq -e '.skills[] | select(.name == "gamma") | .deprecated' <<< "$PREP" >/dev/null &&
  jq -e '.skills[] | select(.name == "pair") | .files | length == 3' <<< "$PREP" >/dev/null; then
  ok "skill の files は両 runtime の entrypoint、directory の内容、link 先の共有 reference を含み、非推奨を示す"
else
  ng "skill の files か deprecated が不正"
fi
if jq -e '.since == null and .git_before.status == [] and (.skills | length) == 5' "$RUN/run.json" >/dev/null; then
  ok "run.json に前回の run（なし）、git status、skill を記録する"
else
  ng "run.json が不正"
fi

# ---- the Workflow script against a mock agent()
WF="$SANDBOX/workflow.mjs"
python3 - "$REPO_ROOT/claude/skills/skill-tuneup/references/workflow.md" "$WF" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
script = re.search(r"^```js\n(.*?)^```$", text, re.M | re.S).group(1)
body = script.replace("export const meta", "const meta", 1)
harness = r"""
import fs from 'node:fs'
const args = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const calls = []
const log = () => {}
const parallel = async (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))
const pipeline = async (items, ...stages) => Promise.all(items.map(async (item, i) => {
  let value
  try { for (const [k, stage] of stages.entries()) value = k === 0 ? await stage(item, item, i) : await stage(value, item, i) } catch { return null }
  return value
}))
const C = { id: 'C1', generation_mechanism: 'assumption_inversion', broken_assumption: 'b', mechanism: 'm', predicted_benefit: 'p',
  failure_condition: 'f', purpose_line: 'pu', mechanism_line: 'me', implementation_line: 'im' }
const agent = async (prompt, opts) => {
  calls.push({ label: opts.label, deny: opts.disallowedTools || [], prompt })
  const kind = opts.label.split(/[ :]/)[0]
  if (opts.label.startsWith('probe 1: gamma')) return null
  return {
    probe: '1. a\n2. b', cluster: { clusters: [{ name: 'c1', probes: 3 }] }, layer: { recommendations: ['r1'] },
    generate: { hygiene: [{ kind: 'outdated', finding: 'f', evidence: 'e', fix: 'x' }], candidates: [C] },
    audit: { verdicts: [{ id: 'C1', verdict: 'KNOWN', method: 'known method', url: 'https://example.org/k',
      purpose_match: true, mechanism_match: true, implementation_match: false }], searched: 's' },
    design: { stress: [{ id: 'C1', survives: true, reason: 'r' }], experiments: [
      { candidate_ids: ['C1'], hypothesis: 'h', criterion: 'c', runs: [{ label: 'a', prompt: 'p1' }, { label: 'b', prompt: 'p2' }], judge_prompt: 'j' },
      { candidate_ids: ['C1'], hypothesis: 'h2', criterion: 'c2', runs: [{ label: 'a', prompt: 'p3' }], judge_prompt: 'j2' },
      { candidate_ids: ['C1'], hypothesis: 'h3', criterion: 'c3', runs: [{ label: 'a', prompt: 'p4' }], judge_prompt: 'j3' }] },
    run: 'output', judge: { verdict: 'PASS', reason: 'r' },
  }[kind]
}
const result = await (async () => {
""" + body + r"""
})()
fs.writeFileSync(process.argv[3], JSON.stringify(result))
fs.writeFileSync(process.argv[4], JSON.stringify(calls))
"""
open(sys.argv[2], "w", encoding="utf-8").write(harness)
PY
if command -v node >/dev/null; then
  printf 'digest\n' > "$SANDBOX/research.txt"
  jq --arg id "$(jq -r .run_id <<< "$PREP")" --rawfile r "$SANDBOX/research.txt" '{runId: $id, research: $r, skills: .skills}' <<< "$PREP" > "$SANDBOX/args.json"
  if node "$WF" "$SANDBOX/args.json" "$RUN/results.json" "$SANDBOX/calls.json"; then
    ok "Workflow script は mock の agent() で最後まで動く"
  else
    ng "Workflow script が mock で失敗した"
  fi
  if jq -e '.missing == ["gamma"] and (.results | length) == 4 and (.results[0].experiments | length) == 2' "$RUN/results.json" >/dev/null; then
    ok "probe が欠けた skill は missing に出し、実験は2件までに切る"
  else
    ng "Workflow の結果が不正: $(jq -c '{missing, n: (.results | length)}' "$RUN/results.json")"
  fi
  if jq -e '[.[] | select(.label | startswith("audit")) | .deny | index("WebSearch")] | all(. == null)' "$SANDBOX/calls.json" >/dev/null &&
    jq -e '[.[] | select(.label | startswith("audit") | not) | .deny | (index("WebSearch") != null and index("Edit") != null and index("mcp__*") != null)] | all' "$SANDBOX/calls.json" >/dev/null &&
    jq -e '[.[] | select(.label | startswith("audit")) | .deny | (index("Bash") != null and index("Write") != null)] | all' "$SANDBOX/calls.json" >/dev/null; then
    ok "web search を使えるのは監査役だけで、全 agent が Bash・Edit・Write を持たない"
  else
    ng "agent の tool 制限が不正"
  fi
  if jq -e '[.[] | select(.label | startswith("audit")) | .prompt | (contains("purpose: pu") and (contains("broken_assumption") or contains("predicted_benefit") or contains("failure_condition") | not))] | all' "$SANDBOX/calls.json" >/dev/null &&
    jq -e '[.[] | select(.label | startswith("judge")) | .prompt | contains("Pre-registered criterion (fixed before the runs)")] | all' "$SANDBOX/calls.json" >/dev/null &&
    jq -e '[.[] | select(.label | startswith("run")) | .prompt | IN("p1", "p2", "p3")] | all' "$SANDBOX/calls.json" >/dev/null; then
    ok "監査役には中立の3行だけを渡し、判定役には事前登録の基準を渡し、run には基準を渡さない"
  else
    ng "監査・判定・run の prompt が契約と合わない"
  fi
else
  ng "node が無いので Workflow script を検査できない"
fi

# ---- record
run "$TUNE" record "$RUN"
expect_rc "欠けた skill があれば record は失敗する" 1 "no valid result for: gamma"
jq --slurpfile r <(jq '.results[0] | .skill = "gamma"' "$RUN/results.json") '.results += $r | .missing = []' "$RUN/results.json" > "$SANDBOX/full.json"
jq '.results[0].audit.verdicts[0].url = ""' "$SANDBOX/full.json" > "$SANDBOX/bad.json"
run "$TUNE" record "$RUN" --results "$SANDBOX/bad.json"
expect_rc "url の無い KNOWN は失敗する" 1 "is KNOWN without a url and method"
jq '.results[0].experiments[0].verdict = "MAYBE"' "$SANDBOX/full.json" > "$SANDBOX/bad.json"
run "$TUNE" record "$RUN" --results "$SANDBOX/bad.json"
expect_rc "未定義の判定は失敗する" 1 "must be one of"
jq '.results[0].audit.verdicts = []' "$SANDBOX/full.json" > "$SANDBOX/bad.json"
run "$TUNE" record "$RUN" --results "$SANDBOX/bad.json"
expect_rc "監査の判定が無い候補は失敗する" 1 "no audit verdict for C1"
run "$TUNE" record "$RUN" --results "$SANDBOX/full.json"
expect_rc "揃った結果は記録する" 0 "RECORD OK: 5 skill(s)"
[[ -s "$RUN/skills/pair.json" ]] && ok "skill ごとの結果を書く" || ng "skills/pair.json が無い"

# ---- finish
run "$TUNE" finish "$RUN"
expect_rc "research と synthesis が無ければ finish は失敗する" 1 "research.md needs a non-empty '## Findings' section"
printf '## Findings\n\n- a fact. https://example.org (2026-10-11)\n\n## Coverage\n\nofficial docs\n' > "$RUN/research.md"
printf '## Summary\n\ns\n\n## Per skill\n\np\n\n## Not covered\n\nthree probes instead of five\n' > "$RUN/synthesis.md"
printf 'x\n' > "$TK/untracked.txt"
run "$TUNE" finish "$RUN"
expect_rc "toolkit の git status が変われば失敗する" 1 "changed since prepare"
rm "$TK/untracked.txt"
run "$TUNE" plan "$RUN"
expect_rc "finish 前の plan は失敗する" 1 "has not finished"
run "$TUNE" finish "$RUN"
expect_rc "finish は result を書く" 0 "FINISH OK"
if grep -qF '| pair | 1 | 1 | 1 / 0 / 0 | 2 / 0 / 0 |' "$RUN/result.md" && grep -qF 'three probes instead of five' "$RUN/result.md" &&
  jq -e --arg id "$(basename "$RUN")" '.last_finished.run_id == $id and .skills.alpha.run_id == $id' "$XDG_STATE_HOME/agents-toolkit/skill-tuneup/ledger.json" >/dev/null; then
  ok "result に skill ごとの集計と synthesis を書き、ledger を更新する"
else
  ng "result.md か ledger が不正"
fi
run "$TUNE" prepare --only alpha
if [[ "$RC" -eq 0 ]] && jq -e '.since != null and (.skills | length) == 1' <<< "$OUT" >/dev/null; then
  ok "次の prepare は前回の完了日を since に入れる"
else
  ng "since が入らない: $OUT"
fi

# ---- plan
run "$TUNE" plan "$RUN"
expect_rc "plan は PASS の候補と hygiene を示す" 0 "candidate C1 [KNOWN (known method: https://example.org/k)] m"
[[ "$OUT" == *"- hygiene [outdated] f | evidence: e | fix: x"* ]] && ok "plan は hygiene の指摘を示す" || ng "plan に hygiene が無い: $OUT"
printf 'changed\n' >> "$TK/shared/skills/pair/references/evidence.md"
run "$TUNE" plan "$RUN"
expect_rc "run の後に skill の file が変われば plan は失敗する" 1 "skill files changed since the run: pair"
git -C "$TK" checkout -q -- shared/skills/pair/references/evidence.md

# ---- static contract
SK="$REPO_ROOT/claude/skills/skill-tuneup/SKILL.md"
if grep -qx 'disable-model-invocation: true' "$SK" && grep -qF 'ask the user once before going on' "$SK" &&
  grep -qF 'It does not authorize commits, pushes, PRs' "$SK" && grep -qF 'No commit.' "$SK"; then
  ok "skill は手動起動だけで、起動前に一度確認し、commit や push を許可しない"
else
  ng "SKILL.md の契約が不正"
fi
if grep -qF '~/.claude/skills/break-consensus/references/probe-and-audit.md' "$SK" &&
  grep -qF 'three probes instead of five' "$REPO_ROOT/claude/skills/skill-tuneup/references/workflow.md"; then
  ok "per-skill の手順は break-consensus の probe-and-audit に従い、probe 数の差を記録する"
else
  ng "break-consensus への依存か probe 数の記録が無い"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
