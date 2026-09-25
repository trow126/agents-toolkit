# /break-consensus --cross

Opt-in cross-provider mode (owner decision D7). A Codex worker and a read-only Claude worker each generate candidates from the same brief without seeing each other; you then run the prior-art, stress-test, and experiment steps on their union. It is not a delegation, so the delegation contract (OD-5) does not apply. It is read-only: no repository file changes, no external writes, and no implementation.

**Stop** when `prepare`, `codex`, or `collect` fails, or a worker returns no output. Report the failure; do not silently continue with one provider.
**Done** when `finish` passes and you have reported the surviving candidates with the result path.

## Steps

1. Write the brief to a file outside the repository (your scratchpad or `/tmp`): the problem, constraints, what is already known, and what counts as useful. The brief goes to another model provider, so leave out secrets, credentials, and private data. By default the brief is the only input; attach repository excerpts only when the user asks.
2. Run `~/.claude/bin/break-consensus-cross prepare <brief>`. It copies the brief into a run directory under `~/.local/state/agents-toolkit/break-consensus/`, records its sha256, the `git status` of the current repository, and the hash of the global `~/.codex/AGENTS.md`, checks the route in `divergent-route.env` against the Codex catalog, and prints JSON with `run_dir`, `brief_sha256`, `claude_model`, `prompt_file`, and `schema_file`.
3. Read `prompt_file` and `schema_file`. In one message, launch both workers:
   - Bash with `run_in_background: true`: `~/.claude/bin/break-consensus-cross codex <run_dir>`. It runs `codex exec -C <empty temporary directory> --skip-git-repo-check -p toolkit-divergent -s read-only` with the route model and effort, `--json`, and `--output-schema`, and records the model, effort, sandbox, and cwd that Codex actually used.
   - Workflow with the script below and `args` `{"prompt": <prompt_file text>, "model": <claude_model>, "schema": <schema_file JSON>}`. You invoked this skill, so this is the explicit opt-in the Workflow tool requires.
4. When both have finished, write the Workflow result as JSON to `<run_dir>/claude-output.json` and run `~/.claude/bin/break-consensus-cross collect <run_dir>`. It checks both outputs against the schema and the brief hash, the prompt both workers received, the Codex route, sandbox, and empty cwd, and that `git status` is unchanged, then prints both candidate lists.
5. On the union of candidates, run steps 4–6 of the skill: check prior art, stress-test, and turn survivors into the smallest reversible experiment.
6. Write `<run_dir>/synthesis.md` with these sections, each non-empty:
   - `## Agreements`: candidates or baseline items both workers produced, matched by mechanism rather than wording.
   - `## Differences`: candidates only one worker produced, and baseline disagreements.
   - `## Decisions`: for every candidate, adopted or rejected and the reason (prior art found, failed stress test, duplicate).
   - `## Notes`: that the Codex worker also read the global `~/.codex/AGENTS.md` (hash in `run.json`) and the Claude worker the usual CLAUDE.md files, and any fallback you used.
7. Run `~/.claude/bin/break-consensus-cross finish <run_dir>`. It checks the sections and `git status` again and writes `<run_dir>/result.md` with your synthesis and both raw outputs.
8. Report the surviving candidates and the path of `result.md`. Do not score or converge the candidates, and do not start implementation; implementation is a separate workflow the user starts explicitly.

If the Workflow run fails with an `opts.disallowedTools` error, run the Claude worker with Agent instead: `subagent_type` `Explore` (Read, Grep, and Glob only), `model` `<claude_model>`, the same prompt, and a request to answer with only the JSON object. Record the fallback under `## Notes`.

## Worker prompt

`prepare` fills this template and writes it to `prompt_file`; both workers receive the same text.

```text
You are one of two independent divergent workers for a /break-consensus --cross run. A model from a different provider receives the same brief; you will not see its output, and it will not see yours.

Rules:
- Work only from the brief below. Do not read, search, create, or modify files, run commands, or contact external services.
- Do not score, rank, or converge the candidates, and do not plan or start an implementation.
- Answer with only the JSON object required by the output schema. Copy brief_sha256 exactly from the line below.

Steps:
1. List and freeze the consensus baseline: standard practice, the first solutions a language model is likely to produce, and any current approach the brief describes. These are exploration exclusions, not candidates.
2. Generate candidates through all three mechanisms: assumption_inversion (invert a load-bearing assumption), structural_transfer (transfer a mechanism from a structurally different field, with the correspondence stated), and changed_principle (change the generation principle or the objective).
3. Make each candidate operationally distinct. Reject synonyms, cosmetic variations, and combinations of baseline ideas.
4. For each candidate, give the broken assumption, the mechanism, the predicted benefit, and the observation that would show it fails.

brief_sha256: {{BRIEF_SHA256}}

<brief>
{{BRIEF}}
</brief>
```

## Claude worker workflow

```js
export const meta = {
  name: 'break-consensus-cross-claude',
  description: 'Read-only Claude divergent worker for /break-consensus --cross',
  phases: [{ title: 'Diverge' }],
}
phase('Diverge')
const result = await agent(args.prompt, {
  label: 'divergent-claude',
  phase: 'Diverge',
  model: args.model,
  schema: args.schema,
  disallowedTools: ['Bash', 'Edit', 'Write', 'NotebookEdit'],
})
if (!result) throw new Error('divergent-claude returned no output')
return result
```
