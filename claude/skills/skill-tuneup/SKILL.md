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

1. Run `~/.claude/bin/skill-tuneup prepare [--only <skill,...>]`. It inventories the skills, creates the run directory, and prints the skill list and the estimated number of agents. Show the count and the estimate and ask the user once before going on; the run is large.
2. Shared research, once for all skills: follow [`references/research.md`](references/research.md) and write `<run_dir>/research.md`.
3. Launch the Workflow in [`references/workflow.md`](references/workflow.md) with the `args` it describes. You invoked this skill, so this is the explicit opt-in the Workflow tool requires.
4. Write the Workflow result to `<run_dir>/results.json` and run `~/.claude/bin/skill-tuneup record <run_dir>`. It validates every skill's result and fails on a missing skill or an unsupported verdict; rerun only the failed skills with `--only`, do not hand-write results.
5. Write `<run_dir>/synthesis.md` with non-empty `## Summary`, `## Per skill`, and `## Not covered` sections, then run `~/.claude/bin/skill-tuneup finish <run_dir>`.
6. Report, per skill: hygiene findings, candidates with their audit verdict, each experiment's pre-registered criterion and verdict, and what `--apply` would implement. Do not rank skills or candidates beyond that.

The per-skill pass is break-consensus in its `--solo` form, owned by that skill: read `~/.claude/skills/break-consensus/SKILL.md` and `~/.claude/skills/break-consensus/references/probe-and-audit.md` (it sets `disable-model-invocation: true`, so read the files instead of loading it). Workflow agents cannot launch the Codex worker. Say so in the report and name `/break-consensus` (cross by default) for any skill that needs the cross-provider pass.

This skill explores, tests, and with `--apply` edits files. It does not authorize commits, pushes, PRs, or bypassing normal quality and approval gates.
