---
name: cross-critic
description: Read-only cross-model critique of a plan, preregistration, amendment, design, or hypothesis by a Codex critic, plus a Claude critic with --gate; you adopt or reject each merged finding with a reason. Use when the user invokes /cross-critic.
disable-model-invocation: true
argument-hint: "<document-path> [--gate]"
---

# /cross-critic

**Stop** before writing code, editing the document, or making any repository or external write; this skill only collects criticism and records your decision on each point. **Done** when `cross-critic finish` passes and you have reported the decision table with the path of `result.md`.

Read [`references/workflow.md`](references/workflow.md).

## Critics, not judges

The critics produce objections, oversights, alternative explanations, and alternatives. They never decide whether the document is right, and you never treat a short or empty finding list as approval. Evidence (2026-10 A/B experiments, `docs/eval/sandwich-ab-results.md` in agents-toolkit): blind reviewers of both providers flagged 0 of 8 known leaks, and the two providers agreed only moderately (Spearman 0.44). A second provider adds viewpoints; it is not a verdict.

## Modes

- `/cross-critic <document>`: one Codex critic (read-only sandbox). Use for ordinary plans, designs, and hypotheses.
- `/cross-critic <document> --gate`: the Codex critic plus a Claude critic. Use for important gates: preregistrations, amendments, plan reviews, and judgment gates of a roadmap. The Claude critic is the route's gate model, or the route's alternate model when you (the author) are the gate model; a document is never criticized by the model that wrote it.

Both modes send the document to other model sessions; use them only when the user asks (directly or through `/gh-roadmap-run --critic`). Routes are in [`references/critic-route.env`](references/critic-route.env).

## Required behavior

1. Target only documents: plans, preregistrations, amendments, designs, hypotheses. For code, use `/code-review` instead.
2. Put the document in a file (your scratchpad when it exists only in chat), without secrets or private data.
3. Launch `~/.claude/bin/cross-critic run <document> --author <your exact model id> [--gate]` from the main session with `Bash(run_in_background=true)`. Never wrap it in an Agent. Use `--dry-run` to show the commands first when the user asks.
4. On a failed critic, schema mismatch, or changed `git status`, report and stop; do not continue with one critic silently.
5. Complete `<run>/synthesis.md` from the template as `references/workflow.md` describes: merge duplicates, mark each row's source (one critic's label or `両方`), raise `両方` rows one priority level, and give every row `採用` or `不採用` with a concrete reason. Ignoring findings wholesale is not a valid synthesis.
6. Run `~/.claude/bin/cross-critic finish <run>` and fix the synthesis until it passes.
7. Report the decision table, what you will change because of the adopted rows, and the path of `result.md`. Changing the document is a separate step the user approves.
