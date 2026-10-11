# Baseline probe and blind prior-art audit

Steps 1 and 4 of break-consensus. Both use fresh contexts (subagents started without this conversation or this skill), because the generating context can neither recall its own defaults nor judge its own novelty (evidence.md, 2026-10 section).

## Baseline probe (step 1)

1. Write the problem statement: the problem, constraints, and what is already known, without any candidate ideas.
2. Start five fresh contexts on the same model family as the generator, each with only the problem statement and this request: "What would you recommend doing? Give 6-10 concrete recommendations, one line each." In Claude Code, run each as a Workflow `agent()` with the problem statement in the prompt and `disallowedTools: ['Read', 'Grep', 'Glob', 'Bash', 'Edit', 'Write', 'NotebookEdit', 'WebSearch', 'WebFetch', 'Agent', 'Skill', 'mcp__*']`, so it cannot read the current implementation.
3. Cluster the answers by mechanism, not wording. Record how many of the five produced each cluster.
4. Start one more fresh context, isolated the same way, with the problem statement and the cluster list: "First name 6-10 distinct directions that no item in this list takes, one sentence each. Then give one concrete recommendation per direction." Cluster its recommendations as the second layer. (A single call that spreads directions first beats asking to differ from a list, per token: arXiv 2605.30150.)
5. The frozen baseline is both layers plus standard practice and the current implementation that the probes missed. Write each item as a named, concrete mechanism, not a generic category.

If a fresh context cannot be started, or the runtime refuses the spawn with those `disallowedTools`, stop and report it; do not fall back to listing the baseline from recall.

## Blind prior-art audit (step 4)

1. Rewrite every candidate as three short lines of similar length: purpose, mechanism, implementation. Drop its title, generation mechanism, predicted benefit, and any word that claims novelty or non-consensus.
2. Start one fresh context with web search and give it only the rewritten candidates and the one-paragraph problem context. Do not tell it where the candidates came from or how they were judged.
3. Ask it, for each candidate, to search by the mechanism in generic words and by any established method name it suspects, and to return one verdict:
   - `KNOWN`: substantially the same thing exists. Needs a source URL it opened or saw in results, the method name, and purpose / mechanism / implementation match (yes or no each).
   - `PARTIAL`: the same purpose or the same mechanism with a different core, with the same evidence.
   - `NOT_FOUND`: nothing found in this search. Never "novel".
4. Treat the verdicts this way in steps 5 and 6, and record what the audit searched so the reader can see its coverage:
   - `KNOWN` with both mechanism and implementation matching: not a non-consensus candidate. List it separately as "known method to adopt here", with its source.
   - `PARTIAL`, or `KNOWN` with only the purpose matching: stays a candidate, with the facet that differs from the source named.
   - `NOT_FOUND`: stays a candidate.
