---
name: break-consensus
description: "Generates non-consensus candidates: freezes the consensus baseline, breaks assumptions, checks prior art, and stress-tests survivors into reversible experiments. Use when the user explicitly invokes $break-consensus. Not for ordinary implementation."
---

# $break-consensus

**Stop** before any implementation, external write, or destructive experiment; this skill only explores and proposes. **Done** when you have returned the surviving candidates, each with its smallest reversible experiment.

## Modes

- In Codex: generate and test candidates in this session (the `--solo` behavior), with or without `--solo`.
- `--cross`: the cross-provider mode, the default only in Claude Code, which launches the Codex and Claude workers from its main session. In Codex, do not emulate it; tell the user to run `/break-consensus` in Claude Code, and stop.

For steps 1 and 4 follow [`../../break-consensus/references/probe-and-audit.md`](../../break-consensus/references/probe-and-audit.md). Read [`../../break-consensus/references/evidence.md`](../../break-consensus/references/evidence.md) only when the user asks why a step exists or when you update this skill.

1. Freeze the consensus baseline from observed answers, not recall: probe fresh contexts for their first answers and for the next layer beyond them, then add standard practice and the current implementation. These are exploration exclusions, not candidates.
2. Generate candidates through at least three distinct mechanisms: assumption inversion, transfer from a structurally different field, and a changed generation principle or objective.
3. Make each candidate operationally distinct; reject synonyms, cosmetic variations, and combinations of baseline ideas.
4. Check prior art with a blind auditor in a fresh context that sees each candidate only as purpose, mechanism, and implementation, with no claim of novelty. Accept "known" only with a source and a facet match, record "not found", never "novel", and handle each verdict as probe-and-audit.md defines.
5. Stress-test surviving ideas for feasibility, safety, reversibility, cost, and a falsifiable advantage.
6. Return only candidates that survive, each with its broken assumption, mechanism, predicted benefit, failure condition, and smallest reversible experiment.

This skill explores and proposes. It does not authorize implementation, external writes, destructive experiments, or bypassing normal quality and approval gates.
