# Issue design for a roadmap

`gh-roadmap-plan templates` prints the completeness rule and the skeletons. Their exact headings are authoritative; this file adds what a roadmap needs on top of them. Write the bodies in the language of the source conversation or documents.

## Parent (backlog/umbrella)

Title: `ロードマップ: <goal>` (or the repository's existing convention). Sections are the umbrella skeleton's, filled as follows.

- **Purpose / 目的**: the goal and the success measure from the brief, and what a negative result means (the roadmap closes with that verdict recorded).
- **Exact scope / 対象範囲**: repository, data, period, instruments or modules; the decisions made, each with date and who decided; related projects and what is reused from each.
- **Child work items / 子Issue**: one line per child, in execution order, exactly `- [ ] {{#key}} <short title>` (this is the checklist `/gh-roadmap-run` reads and checks off). After the list, a dependency note (`{{#data}} は {{#scaffold}} の後`, parallel children) and which children are 【判断ゲート】.
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

Research-specific rules:

- The preregistration child fixes hypotheses, sample periods (exploration vs. held-out), metrics, costs, and kill criteria before any evaluation child runs; evaluation children cite it and may not change it.
- Evaluation children use the held-out period once and say so.
- Cost assumptions (spread, commission, slippage, swap, tax) are explicit numbers with their source, or are the output of a named child.

Judgment gates:

- Title starts with 【判断ゲート】. The body lists the options, the evidence each needs (with the children that produce it), the decision criteria, and `担当: ユーザー`.
- Nothing after a gate may assume its outcome; children that depend on a particular outcome say so in their 前提.

## Final check before `create`

- Can each child be closed from its body alone?
- Does every cross-reference use `{{#key}}`, never a guessed number?
- Are all decisions from the brief recorded in the parent, and every open decision either asked or turned into a gate?
- Does the parent say how a negative result closes the roadmap?
