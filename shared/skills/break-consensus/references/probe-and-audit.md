# Baseline probe and blind prior-art audit

Steps 1 and 4 of break-consensus. Both use fresh contexts (subagents started without this conversation or this skill), because the generating context can neither recall its own defaults nor judge its own novelty (evidence.md, 2026-10 section).

## Baseline probe (step 1)

1. Write the problem statement: the problem, constraints, and what is already known, without any candidate ideas.
2. Start five fresh contexts on the same model family as the generator, each with only the problem statement and this request: "What would you recommend doing? Give 6-10 concrete recommendations, one line each." No tools beyond reading the statement.
3. Cluster the answers by mechanism, not wording. Record how many of the five produced each cluster.
4. Start one more fresh context with the problem statement and the cluster list: "Give 6-10 further recommendations that differ from every item in this list, not variants or combinations of them." Cluster its answers as the second layer.
5. The frozen baseline is both layers plus standard practice and the current implementation that the probes missed. Write each item as a named, concrete mechanism, not a generic category.

If a fresh context cannot be started, stop and report it; do not fall back to listing the baseline from recall.

## Blind prior-art audit (step 4)

1. Rewrite every candidate as three short lines of similar length: purpose, mechanism, implementation. Drop its title, generation mechanism, predicted benefit, and any word that claims novelty or non-consensus.
2. Start one fresh context with web search and give it only the rewritten candidates and the one-paragraph problem context. Do not tell it where the candidates came from or how they were judged.
3. Ask it, for each candidate, to search by the mechanism in generic words and by any established method name it suspects, and to return one verdict:
   - `KNOWN`: substantially the same thing exists. Needs a source URL it opened or saw in results, the method name, and purpose / mechanism / implementation match (yes or no each).
   - `PARTIAL`: the same purpose or the same mechanism with a different core, with the same evidence.
   - `NOT_FOUND`: nothing found in this search. Never "novel".
4. Use the verdicts in step 5: a `KNOWN` candidate survives only as "adopt the known method here" with its source named; record what the audit searched so the reader can see its coverage.
