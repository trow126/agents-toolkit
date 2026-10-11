---
name: skill-tuneup
description: "Strengthens and modernizes every toolkit skill in one run: shared research on current official guidance, a break-consensus pass per skill, and pre-registered experiments; --apply implements what passed. Use when the user explicitly invokes /skill-tuneup. Not for hand-editing one skill or for ordinary implementation."
disable-model-invocation: true
argument-hint: "[--only <skill,...>] | --apply <run-dir>"
---

# /skill-tuneup

**Stop** before any repository write in the default mode, and before any commit, push, or external write in every mode. **Done** when `skill-tuneup finish` passes and you have reported the per-skill results with the run path (default), or when the passing items are implemented and the checks pass (`--apply`).

## Modes

- default: every skill the toolkit ships (both runtimes) in one run: shared research, a break-consensus pass per skill in a Workflow, pre-registered experiments, and a report. Writes only its run directory under `~/.local/state/agents-toolkit/skill-tuneup/`.
- `--only <skill,...>`: the default flow restricted to the named skills.
- `--apply <run-dir>`: implement the items of a finished run whose experiment passed, plus its hygiene findings, with tests. Follow [`references/apply.md`](references/apply.md). No commit.

## Default flow

1. Run `~/.claude/bin/skill-tuneup prepare [--only <skill,...>]`. It inventories the skills, creates the run directory, and prints the skill list and the estimated number of agents; it refuses Claude Code older than 2.1.296 and prints `--only` batches when the skills could exceed the Workflow limit of 1,000 agents. Show the count and the estimate and ask the user once before going on; the run is large. The Workflow's large-workflow warning is expected and is not a reason to stop.
2. Shared research, once for all skills: follow [`references/research.md`](references/research.md) and write `<run_dir>/research.md`.
3. Launch the Workflow in [`references/workflow.md`](references/workflow.md) with the `args` it describes. You invoked this skill, so this is the explicit opt-in the Workflow tool requires.
4. Write the Workflow result to `<run_dir>/results.json` and run `~/.claude/bin/skill-tuneup record <run_dir>`. It validates every skill's result and fails on a missing skill or an unsupported verdict; rerun only the failed skills with `--only`, do not hand-write results.
5. Write `<run_dir>/synthesis.md` with non-empty `## Summary`, `## Per skill`, and `## Not covered` sections (name there every skill whose miner found no invocation), then run `~/.claude/bin/skill-tuneup finish <run_dir>`.
6. Report, per skill: hygiene findings, candidates with their audit verdict, each experiment's pre-registered criterion and verdict, and what `--apply` would implement. Do not rank skills or candidates beyond that.

The per-skill pass is a frozen `--solo` copy of break-consensus steps 1–5 in [`references/workflow.md`](references/workflow.md); its tests check it against `~/.claude/skills/break-consensus/references/probe-and-audit.md`. Workflow agents cannot launch the Codex worker; say so in the report. Name `/break-consensus` (cross by default) only for a skill whose surviving candidates all fall inside one baseline cluster or whose change is high-risk, since different models converge on each other and a cross-provider run does not guarantee diversity (arXiv 2510.22954).

This skill explores, tests, and with `--apply` edits files. It does not authorize commits, pushes, PRs, or bypassing normal quality and approval gates.
