# Per-skill Workflow

One pipeline item per skill, no barrier between skills. Each item runs break-consensus in its `--solo` form: baseline probe (step 1), generation (steps 2–3) plus a hygiene review against the shared research, blind prior-art audit (step 4), stress test (step 5), and up to two pre-registered experiments whose criterion is fixed before their runs start.

Deviation from `probe-and-audit.md`: three probes instead of five, to keep a whole-toolkit run affordable. In the 2026-10-11 probe experiment the main clusters appeared in all five probes, so three still capture the mode; the second layer is unchanged. Record the deviation in `synthesis.md` under `## Not covered`.

Agents per skill: 3 probes, 1 cluster, 1 second layer, 1 generator, 1 auditor, 1 designer, and per experiment up to 3 runs and 1 judge, so 8 to 16. `skill-tuneup prepare` prints the total estimate.

## Args

`{"runId": <run id>, "research": <text of research.md>, "skills": <the "skills" array printed by prepare>}`. Each skill has `name`, `description`, `deprecated`, and `files` (absolute paths of its entrypoints and references).

## Script

```js
export const meta = {
  name: 'skill-tuneup',
  description: 'Per-skill break-consensus pass (solo) with blind prior-art audit and pre-registered experiments',
  phases: [
    { title: 'Probe' }, { title: 'Generate' }, { title: 'Audit' }, { title: 'Design' }, { title: 'Experiment' },
  ],
}
const READ_ONLY = ['Bash', 'Edit', 'Write', 'NotebookEdit', 'WebSearch', 'WebFetch', 'mcp__*']
const AUDITOR = ['Bash', 'Edit', 'Write', 'NotebookEdit', 'mcp__*']
const PROBES = 3
const MAX_EXPERIMENTS = 2
const MAX_RUNS = 3
const STR = { type: 'string' }
const LIST = { type: 'array', items: STR }
const obj = (properties) => ({ type: 'object', additionalProperties: false, properties, required: Object.keys(properties) })
const CLUSTERS = obj({ clusters: { type: 'array', items: obj({ name: STR, probes: { type: 'integer' } }) } })
const LAYER = obj({ recommendations: LIST })
const GENERATED = obj({
  hygiene: { type: 'array', items: obj({
    kind: { type: 'string', enum: ['outdated', 'contract_gap', 'bug', 'evidence_error', 'other'] },
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
const DESIGN = obj({
  stress: { type: 'array', items: obj({ id: STR, survives: { type: 'boolean' }, reason: STR }) },
  experiments: { type: 'array', items: obj({
    candidate_ids: LIST, hypothesis: STR, criterion: STR,
    runs: { type: 'array', items: obj({ label: STR, prompt: STR }) }, judge_prompt: STR }) },
})
const VERDICT = obj({ verdict: { type: 'string', enum: ['PASS', 'FAIL', 'INCONCLUSIVE'] }, reason: STR })

const fileList = (s) => s.files.map((f) => `- ${f}`).join('\n')
const readOnly = (label, phase, extra) => ({ label, phase, disallowedTools: READ_ONLY, ...(extra || {}) })

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
      `Read only these files of one agent skill:\n${fileList(s)}\n\nOther reviewers already recommended the following:\n${clustered.clusters.map((c) => `- ${c.name}`).join('\n')}\n\nGive 6-10 further recommendations that differ from every item in that list, not variants or combinations of them.`,
      readOnly(`layer 2: ${s.name}`, 'Probe', { schema: LAYER }))
    return { probes: answers, baseline: { clusters: clustered.clusters, second_layer: layer.recommendations } }
  },
  async (prev, s) => {
    const generated = await agent(
      `You run steps 2-3 of break-consensus, plus a hygiene review, for one agent skill${s.deprecated ? ' (marked deprecated: weigh hygiene over new candidates)' : ''}.\n\nRead only these files:\n${fileList(s)}\n\nFrozen baseline (exploration exclusions, not candidates):\n${prev.baseline.clusters.map((c) => `- ${c.name}`).join('\n')}\n${prev.baseline.second_layer.map((r) => `- ${r}`).join('\n')}\n\nShared research digest (current official guidance and research, with sources):\n${args.research}\n\n(a) hygiene: specific problems only: guidance outdated against the digest (cite the digest line), contract gaps, bugs, and wrong or superseded evidence. Give evidence as file:line or a source, and a concrete fix.\n(b) candidates: generate through all three mechanisms (assumption_inversion, structural_transfer with the correspondence stated, changed_principle). Make each operationally distinct; reject synonyms, cosmetic variations, and combinations of baseline items. For each, also write purpose_line, mechanism_line, and implementation_line: three neutral lines of similar length with no word claiming novelty.`,
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
    return {
      skill: s.name, probe_count: prev.probes.length, probes: prev.probes, baseline: prev.baseline,
      hygiene: prev.generated.hygiene, candidates: prev.generated.candidates, audit: prev.audit,
      stress: design.stress, experiments,
    }
  })

const missing = args.skills.filter((s, i) => !results[i]).map((s) => s.name)
if (missing.length) log(`no result for: ${missing.join(', ')}`)
return { run_id: args.runId, results: results.filter(Boolean), missing }
```
