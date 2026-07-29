---
name: break-consensus
description: Manual-only innovation exploration. Use only when the user explicitly invokes /break-consensus or asks for non-consensus ideas, assumption-breaking, or alternatives outside standard practice. Do not use for ordinary implementation, debugging, refactoring, or fact lookup.
---

# /break-consensus

Read [`references/evidence.md`](references/evidence.md).

1. List and freeze the consensus baseline: standard practice, the first solutions an LLM is likely to produce, and the current implementation. These are exploration exclusions, not candidates.
2. Generate candidates through at least three distinct mechanisms: assumption inversion, transfer from a structurally different field, and a changed generation principle or objective.
3. Make each candidate operationally distinct; reject synonyms, cosmetic variations, and combinations of baseline ideas.
4. Independently check prior art and adjacent implementations. Separate genuinely unusual mechanisms from unfamiliar naming.
5. Stress-test surviving ideas for feasibility, safety, reversibility, cost, and a falsifiable advantage.
6. Return only candidates that survive, each with its broken assumption, mechanism, predicted benefit, failure condition, and smallest reversible experiment.

This skill explores and proposes. It does not authorize implementation, external writes, destructive experiments, or bypassing normal quality and approval gates.
