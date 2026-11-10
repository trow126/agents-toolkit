# Issue design for a roadmap

`gh-roadmap-plan templates` prints the completeness rule (`~/.agents/rules/issue-completeness.md`) and the skeletons. Their exact headings are authoritative; this file adds what a roadmap needs on top of them. Write the bodies in the language of the source conversation or documents.

## Parent (backlog/umbrella)

Title: `ロードマップ: <goal>` (or the repository's existing convention). Sections are the umbrella skeleton's, filled as follows.

- **Purpose / 目的**: the goal and the success measure from the brief, and what a negative result means (the roadmap closes with that verdict recorded).
- **Exact scope / 対象範囲**: repository, data, period, instruments or modules; the decisions made, each with date and who decided; related projects and what is reused from each.
- **Child work items / 子Issue**: one line per child, in execution order, exactly `- [ ] {{#key}} <short title>` (this is the checklist `/gh-roadmap-run` reads and checks off). After the list, a dependency note (`{{#data}} は {{#scaffold}} の後`, parallel children), which children are 【判断ゲート】, and the abort line of each child that has one (below). Existing open Issues that the roadmap relies on are listed under the scope, not in this checklist.
- **Non-goals / 非目標**: from the brief, including what neighbouring projects already cover.
- **Close conditions / クローズ条件**: all children closed, plus the final verdict written to a named file (for example `docs/research/<topic>/summary.md`) and posted on the parent. Include the negative-result close.
- **Tracking or verification notes / 追跡または検証メモ**: open items that are not decisions (license terms to confirm, data to wait for), and how progress is tracked (`/gh-roadmap-run {{#roadmap}} --status`).

## Children

Pick the skeleton per child: implementation for code and pipelines, investigation/validation for preregistration, measurement, evaluation, and gates.

Every child body:

- references the parent in its first line: `親 Issue: {{#roadmap}}`.
- states its dependencies with placeholders (`前提: {{#scaffold}} が完了していること`).
- stands alone: an implementer decides completion from this body only. Restate the facts it needs from the brief (paths, symbols, periods, thresholds) instead of "see the discussion".
- defines success by the final persisted or user-visible state: files written, rows stored with counts, a report at a named path, a verdict recorded. A command exiting 0 is not success.
- lists verification commands that can actually be run, including a real smoke run when the child touches external data or long computation.
- names its non-goals, especially the work that belongs to a later child.
- with `--existing`, gives the commit at which its paths and symbols were checked, and says in one line: where this body and the current code disagree on a path or symbol, the code wins and the implementer notes the difference on the Issue.
- data, cost, and baseline children may add one abort line: `中止条件: <observable result fixed before data is seen>` (for example, fewer than N usable rows, or a cost floor above the target edge). It names a result that makes the rest of the roadmap pointless. `/gh-roadmap-run` stops there and shows the result to the user; it never skips ahead on its own.

Research-specific rules:

- The preregistration child fixes hypotheses, sample periods (exploration vs. held-out), metrics, costs, and kill criteria before any evaluation child runs; evaluation children cite it and may not change it.
- Evaluation children use the held-out period once and say so.
- Cost assumptions (spread, commission, slippage, swap, tax) are explicit numbers with their source, or are the output of a named child.

Judgment gates:

- Title starts with 【判断ゲート】. The body lists the options, the evidence each needs (with the children that produce it), the decision criteria, and `担当: ユーザー`.
- Nothing after a gate may assume its outcome; children that depend on a particular outcome say so in their 前提, using the option's name as the gate body writes it.
- Give every option a short, unique name. `/gh-roadmap-run` records the user's decision under `## 決定` at the end of the gate's own body (not in a comment) and checks dependent children's 前提 against it; do not write a `## 決定` section in the draft.

## Final check before `create`

- Can each child be closed from its body alone? Check it with a cold read (zero-context validation, https://sharedcontext.ai/skills/external/whykusanagi/zero-context-validation): use one reader per child body. Each reader is a fresh read-only context that receives exactly one body, placeholders unresolved, and sees no brief, no conversation, and no other body; a roadmap with N children uses N readers (in Claude Code an `Explore` subagent, never `subagent_type: "fork"`, which inherits this conversation; pass the body inline and tell it not to open the scratchpad directory or any other `issues/*.md`). Ask for the completion state it would aim for and the first verification command it would run. Revise the body when either differs materially from its own success criterion and commands, or when the reader names a missing fact; probe each body once. Where no fresh context can be started (for example in Codex), skip the cold read and the loophole probe and say so in the report.
- Loophole probe: ask the same fresh reader a second question about the same body: the cheapest state that meets its success criterion and verification commands without achieving the child's purpose (for example a file written with zero rows, a report with no verdict). Revise the body when the reader names a concrete state that no sentence of the body rules out; a state that needs deliberate fabrication no criterion could exclude needs no change.
- Pre-mortem (prospective hindsight, Klein, HBR 2007): imagine the roadmap's Issues later had to be closed and created again elsewhere or in another order, and write up to 3 concrete reasons why (wrong repository, a child that assumes a gate outcome, a missing data dependency). Check each against the brief; fix it, or show it to the user next to the plan table before `init` or `create`.
- Does every cross-reference use `{{#key}}`, never a guessed number?
- Are all decisions from the brief recorded in the parent? Every decision is one of: made by the user, an agent proposal the user accepted, a stated default of workflow §3, or a 【判断ゲート】 child. An agent proposal the user has not accepted, including one that arose while drafting, is an open decision: ask it before `create`.
- Does the parent say how a negative result closes the roadmap?
