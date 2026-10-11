# Per-skill Workflow

One pipeline item per skill, no barrier between skills. The script is a frozen `--solo` copy of break-consensus steps 1–5 (`~/.claude/skills/break-consensus/references/probe-and-audit.md` for steps 1 and 4): baseline probe (step 1), a transcript miner, generation (steps 2–3) plus a hygiene review against the shared research, blind prior-art audit (step 4), stress test (step 5), and up to two pre-registered experiments whose criterion is fixed before their runs start. `tests/test-skill-tuneup.sh` checks the second-layer request and the verdict names against `probe-and-audit.md`; when break-consensus changes them, change this script in the same commit.

Deviations from `probe-and-audit.md`, recorded in `synthesis.md` under `## Not covered`:

- Probe count: three probes instead of five, to keep a whole-toolkit run affordable. In the 2026-10-11 probe experiment the main clusters appeared in all five probes, so three still capture the mode.
- Probes get the skill's file paths instead of a written problem statement and keep Read, Grep, and Glob, because the skill's files are the problem. The no-file-tools isolation of `probe-and-audit.md` applies to break-consensus's own probes.

Every agent is narrowed with `agent({disallowedTools})`. The `agent()` reference does not list that option; Claude Code 2.1.296 honors it and refuses a spawn it cannot narrow, and `skill-tuneup prepare` refuses older versions.

The miner (session-transcript friction mining, the known method the 2026-10-12 run adopted) reads local Claude Code and Codex transcripts for invocations of the skill and returns deviations with file, line, and a short redacted quote. When it finds no invocation, the skill runs on the probe-based flow alone, and `synthesis.md` names it under `## Not covered`.

Agents per skill: 3 probes, 1 cluster, 1 second layer, 1 miner, 1 generator, then 1 auditor and 1 designer when there are candidates, and per experiment up to 3 runs and 1 judge, so 7 to 17. `skill-tuneup prepare` prints the total estimate.

## Args

`{"runId": <run id>, "research": <text of research.md>, "skills": <the "skills" array printed by prepare>}`. Each skill has `name`, `description`, `deprecated`, and `files` (absolute paths of its entrypoints and references).

## Script

```js
export const meta = {
  name: 'skill-tuneup',
  description: 'Per-skill break-consensus pass (solo) with blind prior-art audit and pre-registered experiments',
  phases: [
    { title: 'Probe' }, { title: 'Mine' }, { title: 'Generate' }, { title: 'Audit' }, { title: 'Design' }, { title: 'Experiment' },
  ],
}
const READ_ONLY = ['Bash', 'Edit', 'Write', 'NotebookEdit', 'WebSearch', 'WebFetch', 'mcp__*']
const AUDITOR = ['Bash', 'Edit', 'Write', 'NotebookEdit', 'mcp__*']
const PROBES = 3
const MAX_EXPERIMENTS = 2
const MAX_RUNS = 3
const STR = { type: 'string' }
const TEXT = { type: 'string', minLength: 1 }
const LIST = { type: 'array', items: STR }
const obj = (properties) => ({ type: 'object', additionalProperties: false, properties, required: Object.keys(properties) })
const CLUSTERS = obj({ clusters: { type: 'array', items: obj({ name: STR, probes: { type: 'integer' } }) } })
const LAYER = obj({ directions: LIST, recommendations: LIST })
const MINED = obj({
  status: { type: 'string', enum: ['found', 'none_found', 'no_transcripts'] },
  deviations: { type: 'array', items: obj({
    file: TEXT, line: { type: 'integer', minimum: 1 }, quote: { type: 'string', minLength: 1, maxLength: 300 },
    kind: { type: 'string', enum: ['skipped_check', 'claimed_not_done', 'user_correction'] }, summary: TEXT }) },
  searched: TEXT,
})
const GENERATED = obj({
  hygiene: { type: 'array', items: obj({
    kind: { type: 'string', enum: ['outdated', 'contract_gap', 'bug', 'evidence_error', 'other'] },
    effect: { type: 'string', enum: ['remove', 'correct', 'add'] },
    finding: STR, evidence: STR, fix: STR }) },
  candidates: { type: 'array', items: obj({
    id: STR,
    generation_mechanism: { type: 'string', enum: ['assumption_inversion', 'structural_transfer', 'changed_principle'] },
    broken_assumption: STR, mechanism: STR, predicted_benefit: STR, failure_condition: STR,
    purpose_line: STR, mechanism_line: STR, implementation_line: STR }) },
})
const AUDIT = obj({
  verdicts: { type: 'array', items: obj({
    id: STR, verdict: { type: 'string', enum: ['KNOWN', 'PARTIAL', 'NOT_FOUND'] }, method: STR, url: STR,
    purpose_match: { type: 'boolean' }, mechanism_match: { type: 'boolean' }, implementation_match: { type: 'boolean' } }) },
  searched: STR,
})
// Mirrors references/result.schema.json, so a designer answer that record would reject is retried here instead.
const DESIGN = obj({
  stress: { type: 'array', items: obj({ id: STR, survives: { type: 'boolean' }, reason: TEXT }) },
  experiments: { type: 'array', maxItems: MAX_EXPERIMENTS, items: obj({
    candidate_ids: { type: 'array', minItems: 1, items: STR }, hypothesis: TEXT, criterion: TEXT,
    runs: { type: 'array', minItems: 1, maxItems: MAX_RUNS, items: obj({ label: STR, prompt: TEXT }) }, judge_prompt: TEXT }) },
})
const VERDICT = obj({ verdict: { type: 'string', enum: ['PASS', 'FAIL', 'INCONCLUSIVE'] }, reason: STR })

const fileList = (s) => s.files.map((f) => `- ${f}`).join('\n')
const readOnly = (label, phase, extra) => ({ label, phase, disallowedTools: READ_ONLY, ...(extra || {}) })
const deviationList = (m) => m.deviations.map((d) => `- [${d.kind}] ${d.file}:${d.line} "${d.quote}" — ${d.summary}`).join('\n')

const results = await pipeline(args.skills,
  async (s) => {
    const answers = (await parallel(Array.from({ length: PROBES }, (_, i) => () => agent(
      `Read only these files of one agent skill:\n${fileList(s)}\n\nWhat would you change to make this skill stronger or more current? Give 6-10 concrete recommendations, one line each, as a numbered list. Nothing else.`,
      readOnly(`probe ${i + 1}: ${s.name}`, 'Probe'))))).filter(Boolean)
    if (answers.length < PROBES) throw new Error(`${s.name}: ${PROBES - answers.length} probe(s) returned no output`)
    const clustered = await agent(
      `Below are ${PROBES} independent answers to "what would you change in this agent skill?". Cluster them by mechanism, not wording. Name each cluster as a concrete mechanism and count how many answers contain it.\n\n${answers.map((a, i) => `## Answer ${i + 1}\n${a}`).join('\n\n')}`,
      readOnly(`cluster: ${s.name}`, 'Probe', { schema: CLUSTERS }))
    const layer = await agent(
      `Read only these files of one agent skill:\n${fileList(s)}\n\nOther reviewers already recommended the following:\n${clustered.clusters.map((c) => `- ${c.name}`).join('\n')}\n\nFirst name 6-10 distinct directions that no item in this list takes, one sentence each. Then give one concrete recommendation per direction.`,
      readOnly(`layer 2: ${s.name}`, 'Probe', { schema: LAYER }))
    return { probes: answers, baseline: { clusters: clustered.clusters, second_layer: layer.recommendations } }
  },
  async (prev, s) => {
    const mined = await agent(
      `You mine local session transcripts for how one agent skill was actually used. Skill: ${s.name} — ${s.description}\nIts files:\n${fileList(s)}\n\nSearch read-only and Grep first: Claude Code transcripts under ~/.claude/projects/ (**/*.jsonl, including subagents/) and Codex sessions under ~/.codex/sessions/ (**/*.jsonl). An invocation is "/${s.name}", "$${s.name}", or a read of "skills/${s.name}/SKILL.md". Read only around the hits, in at most the 10 most recent session files that contain one.\n\nList concrete deviations from what the skill's files require: skipped_check (a prerequisite or check it requires was skipped), claimed_not_done (a step reported as done that the transcript shows was not done), user_correction (the user corrected how the agent handled this skill). For each: file (absolute path), line (1-based line in that file), quote (at most 200 characters copied from that line, with secrets, tokens, email addresses, and personal names replaced by [redacted]), kind, and summary. status: found when you list at least one deviation, none_found when invocations exist but show no deviation, no_transcripts when you found no invocation. In searched, say which directories and patterns you searched and how many session files had a hit.`,
      readOnly(`mine: ${s.name}`, 'Mine', { schema: MINED }))
    return { ...prev, mined }
  },
  async (prev, s) => {
    const observed = prev.mined.status === 'found'
      ? `Deviations observed in local session transcripts (cite them as file:line when a finding or candidate addresses one):\n${deviationList(prev.mined)}`
      : `No deviation was observed in local session transcripts (${prev.mined.status}); do not claim anything about real use.`
    const generated = await agent(
      `You run steps 2-3 of break-consensus, plus a hygiene review, for one agent skill${s.deprecated ? ' (marked deprecated: weigh hygiene over new candidates)' : ''}.\n\nRead only these files:\n${fileList(s)}\n\nFrozen baseline (exploration exclusions, not candidates):\n${prev.baseline.clusters.map((c) => `- ${c.name}`).join('\n')}\n${prev.baseline.second_layer.map((r) => `- ${r}`).join('\n')}\n\n${observed}\n\nShared research digest (current official guidance and research, with sources):\n${args.research}\n\n(a) hygiene: specific problems only: guidance outdated against the digest (cite the digest line), contract gaps, bugs, and wrong or superseded evidence. Give evidence as file:line or a source, and a concrete fix. effect: remove (delete stale or duplicated text), correct (fix wrong text in place), or add (a new instruction or step). An add fix is applied without an experiment only when its evidence names the digest line that mandates it.\n(b) candidates: generate through all three mechanisms (assumption_inversion, structural_transfer with the correspondence stated, changed_principle). Make each operationally distinct; reject synonyms, cosmetic variations, and combinations of baseline items. For each, also write purpose_line, mechanism_line, and implementation_line: three neutral lines of similar length with no word claiming novelty.`,
      readOnly(`generate: ${s.name}`, 'Generate', { schema: GENERATED }))
    return { ...prev, generated }
  },
  async (prev, s) => {
    const candidates = prev.generated.candidates
    if (!candidates.length) return { ...prev, audit: { verdicts: [], searched: 'no candidates' } }
    const audit = await agent(
      `You are a prior-art auditor. Context: changes proposed for an agent skill whose purpose is: ${s.description}\n\nCandidates:\n${candidates.map((c) => `${c.id}\n  purpose: ${c.purpose_line}\n  mechanism: ${c.mechanism_line}\n  implementation: ${c.implementation_line}`).join('\n')}\n\nFor each, search the web by the mechanism in generic words and by any established method name you suspect. Verdict KNOWN (substantially the same thing exists) or PARTIAL (same purpose or same mechanism, different core) needs a url you opened or saw in results, the method name, and purpose/mechanism/implementation match. Otherwise NOT_FOUND with empty method and url; never call anything novel. In searched, say what you searched.`,
      { label: `audit: ${s.name}`, phase: 'Audit', schema: AUDIT, disallowedTools: AUDITOR })
    return { ...prev, audit }
  },
  async (prev, s) => {
    const done = (stress, experiments) => ({
      skill: s.name, probe_count: prev.probes.length, probes: prev.probes, baseline: prev.baseline, mined: prev.mined,
      hygiene: prev.generated.hygiene, candidates: prev.generated.candidates, audit: prev.audit, stress, experiments,
    })
    if (!prev.generated.candidates.length) return done([], [])
    const design = await agent(
      `Step 5 of break-consensus and experiment design for one agent skill. Its files:\n${fileList(s)}\n\nCandidates:\n${JSON.stringify(prev.generated.candidates)}\n\nPrior-art verdicts:\n${JSON.stringify(prev.audit.verdicts)}\n\nHygiene findings:\n${JSON.stringify(prev.generated.hygiene)}\n\n(1) stress: test every candidate for feasibility, safety, reversibility, cost, and a falsifiable advantage. A KNOWN candidate survives only as "adopt the known method".\n(2) experiments: at most ${MAX_EXPERIMENTS} cheap read-only experiments on surviving candidates whose outcome would most change what gets implemented. criterion is the observation that fails the hypothesis, fixed now. runs: at most ${MAX_RUNS} self-contained prompts for fresh agents that can only read files; give variants different conditions; never tell a run the hypothesis or the expected result. judge_prompt: how a judge compares the run outputs against the criterion. Return no experiments when none can be tested this way.`,
      readOnly(`design: ${s.name}`, 'Design', { schema: DESIGN }))
    if (design.experiments.length > MAX_EXPERIMENTS) log(`${s.name}: kept ${MAX_EXPERIMENTS} of ${design.experiments.length} experiments`)
    const experiments = (await parallel(design.experiments.slice(0, MAX_EXPERIMENTS).map((e, k) => async () => {
      if (e.runs.length > MAX_RUNS) log(`${s.name} experiment ${k + 1}: kept ${MAX_RUNS} of ${e.runs.length} runs`)
      const runs = e.runs.slice(0, MAX_RUNS)
      const outputs = await parallel(runs.map((r) => () => agent(r.prompt, readOnly(`run ${k + 1}/${r.label}: ${s.name}`, 'Experiment'))))
      const judged = await agent(
        `${e.judge_prompt}\n\nPre-registered criterion (fixed before the runs): ${e.criterion}\n\n${runs.map((r, j) => `## ${r.label}\n${outputs[j] || '(no output)'}`).join('\n\n')}`,
        readOnly(`judge ${k + 1}: ${s.name}`, 'Experiment', { schema: VERDICT }))
      return { ...e, runs, outputs: outputs.map((o) => o || ''),
        verdict: judged ? judged.verdict : 'INCONCLUSIVE', verdict_reason: judged ? judged.reason : 'judge returned no output' }
    }))).filter(Boolean)
    return done(design.stress, experiments)
  })

const missing = args.skills.filter((s, i) => !results[i]).map((s) => s.name)
if (missing.length) log(`no result for: ${missing.join(', ')}`)
return { run_id: args.runId, results: results.filter(Boolean), missing }
```
