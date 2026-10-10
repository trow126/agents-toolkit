# gh-roadmap-plan workflow

The pattern this skill encodes was used by hand for about 30 roadmaps (2025-12 to 2026-10: ChaoScale, keibaAI-v4, flashloan-liquidation-bot, keiba-market-exec, hl-pump-reversal, nk225-flow, kaizen-*, jev-trader, grid-lab, jp-bot-lab). The steps below keep what worked and fix what went wrong.

## §1 The brief

Write the brief to the scratchpad before any Issue body. It is the single source for the drafts.

- **Goal**: one sentence, the question the project answers or the state it reaches. Research projects phrase it as a question with a decision (「〜で稼げるかを判定する」), not as "build X".
- **Success measure and kill criteria**: what result closes the roadmap as a success, and what closes it as a negative result. Most research roadmaps end with 不採用 / 保留 / 打ち切り; that is a valid close and the parent must say so.
- **Decisions made**: each with the date and who decided (user or agent proposal accepted). Quote the user's words when short.
- **Constraints**: data sources, accounts, budget, runtime, machines, tax or legal conditions named in the source.
- **Non-goals**: what the source excluded, and what a neighbouring project already covers.
- **Open questions**: everything the source leaves undecided.
- **Related projects**: from §2.

When the source is the conversation, use only what was said or shown in it. Do not fill gaps with assumptions; list them as open questions.

## §2 Survey

- Run `~/.claude/bin/grok-digest projects` to list the repositories under home with their README heads. Read the ones whose purpose overlaps the goal (same market, data source, or method).
- For each overlapping project, record: what it already answered (results, verdicts), what can be reused (modules, data caches, tests), and whether the new work belongs there instead. A finished, preregistered study is not reopened; new work goes to a new project and links to it.
- Reused code is copied or ported in a scaffold sub-Issue with the source path and commit named; never depend on another project's working tree.
- With `--existing`: read the README, docs, the structure of the modules the change touches, the tests, and the open Issues from `check --existing`. A planned child that duplicates an open Issue references that Issue instead of re-creating it; mention it in the parent's scope.
- With `--existing`, use the repository's `.github/ISSUE_TEMPLATE` when `templates --dir <repo>` shows one.

## §3 Open decisions

Ask before drafting when the answer changes what the children say: target (market, symbol, pair, module), data source, venue or account, scope boundary, budget, or whether to merge into an existing project. Drafting first and rewriting every body afterwards (grid-lab 2026-10-10: data source and currency pair decided after 10 Issues existed) is the failure to avoid.

- Ask all of them in one batch, each with a recommended option and its reason.
- A decision that can only be made with evidence the roadmap itself produces (go/no-go after a backtest, choosing a venue after measuring costs) is not asked now. It becomes a child titled with 【判断ゲート】, whose body lists the options, the evidence it waits for, and the criteria. `/gh-roadmap-run` stops there.
- Defaults that need no question: private repository, kebab-case name in the style of the user's existing projects, Python with uv when the related projects use it. State each default in the report.

## §4 Order and size of the children

- Typical size is 5 to 12 children. Split a child when it has two independent completion criteria; merge children that cannot be verified separately.
- Usual order for a research project: preregistration (hypothesis, periods, metrics, kill criteria fixed before data is seen) → scaffold and ported parts → data acquisition and quality checks → cost model → baseline → candidate methods → out-of-sample or walk-forward evaluation with the go/no-go gate → forward or paper test. For a refactor: characterization tests first, then changes in dependency order, then cleanup.
- Write dependencies explicitly in the parent (which child waits for which) and mark children that may run in parallel.
- Time-critical or long-running data collection that later children need starts as early as its dependencies allow.

## §5 Manifest and creation

- One file per body in the scratchpad (`issues/<key>.md`) and `issues/manifest.json`; the helper usage (`gh-roadmap-plan --help`) defines the schema.
- Keys are short lowercase names (`prereg`, `scaffold`, `data`); the parent key is `roadmap`.
- `create --dry-run` validates the placeholders, the parent checklist order, and the parent reference in every child. `create` prints the numbers and URLs; build the report from that output, not from the plan.
- If `create` fails midway, do not create Issues by hand. Fix the cause and rerun; the state file `manifest.json.state.json` records what exists.
