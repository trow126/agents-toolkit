# Phase 1 element inventory and 11-axis audit

Canonical machine-readable source: [`inventory-elements.tsv`](inventory-elements.tsv). Baseline is git commit `7d193c2`; after is the current tree. Each row is one independently identifiable operational element. `before_path` and `after_path` are used by `measure-metrics.sh` to count active review/progress/retrospective mechanisms and built-in-agent overlaps without grouping unlike elements.

The columns map directly to the requirement’s eleven axes: purpose; needed; built-in alternative; overlap; context load; false-positive risk; failure impact; verification; low-cost-model suitability; deterministic replacement; disposition. `archive_path` is evidence only and is never counted as active.

## Metric definitions

- **review/progress/retrospective mechanism**: an active agent, skill, hook, or helper whose primary purpose is generic plan/code/PR review, work-progress recording, or retrospective. Domain-specific implementation specialists are excluded; generic `code-reviewer` and the former generic `security-reviewer` are included. Counts are unique active paths.
- **built-in overlap**: a custom agent whose primary value is generic work/routing already covered by built-in general-purpose/orchestration plus model-tier selection. Counts are unique active paths.
- **session injection**: static always-on instructions plus the measured `SessionStart.systemMessage`; `PostCompact.systemMessage` is reported separately. Auto memory is disabled.
- **audit cardinality**: every row in the TSV represents one distinct operational file or independently configured mechanism. Validation/test scripts are individual rows rather than one grouped “test suite” row.

## agent

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| agent:ai-engineer | `claude/agents/ai-engineer.md` → `claude/agents/ai-engineer.md` | — | AI/ML production implementation | high | none / none | none | low / medium | frontmatter/schema + task review | partial / lint/tests supplement | keep |
| agent:blockchain-security-auditor | `claude/agents/blockchain-security-auditor.md` → `claude/agents/blockchain-security-auditor.md` | review | independent smart-contract security audit | high | none / domain-specific; not generic reviewer | none | over-reporting possible / high | read-only isolation + review output | no / SAST supplements only | keep |
| agent:code-reviewer | `claude/agents/code-reviewer.md` → `claude/agents/code-reviewer.md` | review-progress-retrospective | independent code/security review | high | none / security-reviewer merged here | none | duplicate findings / medium | read-only tool restriction + review tests | yes / lint/SAST supplements | merge/keep |
| agent:data-engineer | `claude/agents/data-engineer.md` → `claude/agents/data-engineer.md` | — | data pipeline design and implementation | high | none / none | none | low / medium | frontmatter/schema + task review | partial / data validation supplements | keep |
| agent:deep-reasoner | `claude/agents/deep-reasoner.md` → `claude/agents/deep-reasoner.md` | routing | high-risk architecture/root-cause reasoning | conditional | none / built-in general reasoning overlaps partially | none | overuse raises cost / medium | routing contract and owner review | no / no | keep with escalation-only routing |
| agent:explore | `-` → `claude/agents/explore.md` | builtin-override routing | read-only codebase exploration on Haiku | high | built-in Explore / intentional exact-name override | none | incomplete search findings / low | frontmatter + runtime transcript | yes / rg/static search partial | add intentional override |
| agent:fast-worker | `claude/agents/fast-worker.md` → `-` | builtin-overlap | low-cost generic worker | low | built-in general-purpose + tier alias / project-orchestrator | none | misrouting and handoff churn / low | path absence + metrics | yes / tier selection | delete |
| agent:model-qa-specialist | `claude/agents/model-qa-specialist.md` → `claude/agents/model-qa-specialist.md` | review | independent ML quality/fairness audit | high | none / none | none | false positives from incomplete evidence / high | read-only audit output | partial / evaluation scripts supplement | keep |
| agent:plan-reviewer-completeness | `claude/agents/plan-reviewer-completeness.md` → `claude/agents/plan-reviewer.md` | review-progress-retrospective | plan completeness review | medium | none / two sibling plan reviewers | none | triple-review cost / low | merged-agent contract | yes / no | merge |
| agent:plan-reviewer-critic | `claude/agents/plan-reviewer-critic.md` → `claude/agents/plan-reviewer.md` | review-progress-retrospective | plan critique | medium | none / two sibling plan reviewers | none | triple-review cost / low | merged-agent contract | yes / no | merge |
| agent:plan-reviewer-feasibility | `claude/agents/plan-reviewer-feasibility.md` → `claude/agents/plan-reviewer.md` | review-progress-retrospective | plan feasibility review | medium | none / two sibling plan reviewers | none | triple-review cost / low | merged-agent contract | yes / no | merge |
| agent:project-orchestrator | `claude/agents/project-orchestrator.md` → `-` | builtin-overlap routing | route every task through orchestration | low | single owner + built-in orchestration / fast-worker | none | unconditional delegation / medium | path absence + routing tests | yes / routing rules | delete |
| agent:security-reviewer | `claude/agents/security-reviewer.md` → `claude/agents/code-reviewer.md` | review-progress-retrospective | generic security review | medium | code-reviewer security checklist / code-reviewer | none | duplicate findings / medium | merged-agent contract | yes / SAST supplements | merge |
| agent:solidity-engineer | `claude/agents/solidity-engineer.md` → `claude/agents/solidity-engineer.md` | — | secure Solidity implementation | high | none / none | none | low / high | frontmatter/schema + domain tests | partial / forge/slither supplement | keep |
| agent:sre | `claude/agents/sre.md` → `claude/agents/sre.md` | — | reliability/observability implementation | high | none / none | none | low / high | frontmatter/schema + task tests | partial / monitoring tests supplement | keep |

## always-on-instruction

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| mechanism:root-claude | `claude/CLAUDE.md` → `claude/CLAUDE.md` | always-on | repository purpose, commands, shared constraints and routing summary | high | built-in project memory partially / detailed skills/rules moved out | always-on | stale instruction / high | byte/line metrics + validation | n/a / no | shrink/keep |
| mechanism:root-codex | `codex/AGENTS.md` → `codex/AGENTS.md` | always-on | Codex repository instructions | high | none / Python guidance moved to reference | always-on | stale instruction / high | byte/line metrics | n/a / no | shrink/keep |

## archive

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| archive:obsolete-skills | `active skill directories listed above` → `-` (archive `docs/archive/skills/`) | archive | retain removed skill history without runtime loading | optional | git history / none | none | stale reuse / low | archive path + stale scan | n/a / yes | archive |

## ci

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| mechanism:ci | `.github/workflows/ci.yml` → `.github/workflows/ci.yml` | — | execute deterministic validation and tests | high | GitHub Actions / local scripts | per change | environment mismatch / high | workflow + local parity | n/a / yes | expand |
| mechanism:precommit | `claude/githooks/pre-commit` → `claude/githooks/pre-commit` | — | gitleaks pre-commit gate | high | none / CI secret scanning partial | per commit | tool missing / medium | bootstrap hooksPath + syntax | n/a / yes | keep |

## claude-rule

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-rule:code-quality | `claude/rules/code-quality.md` → `shared/skills/implementation-quality/SKILL.md` | — | general code-quality guidance | high | partial / implementation-quality | on demand | low / medium | skill contract + runtime discovery | n/a / lint/validator partial | merge/lazy |
| claude-rule:markdown | `claude/rules/markdown.md` → `claude/rules/markdown.md` | — | Markdown conventions | high | partial / none | path-scoped | low / medium | validator/sync | n/a / lint/validator partial | keep |
| claude-rule:python | `claude/rules/python.md` → `claude/rules/python.md` | — | Python conventions | high | partial / python-quality reference partial | path-scoped | low / medium | validator/sync | n/a / lint/validator partial | keep |
| claude-rule:safety | `claude/rules/safety.md` → `claude/CLAUDE.md` | — | Claude-specific safety constraints | high | partial / core contract + managed policy | always-on small | low / medium | validator/sync | n/a / lint/validator partial | merge/core |
| claude-rule:settings-syntax | `claude/rules/settings-syntax.md` → `claude/rules/settings-syntax.md` | — | settings syntax/scope knowledge | high | partial / validator supplements | path-scoped | low / medium | validator/sync | n/a / lint/validator partial | keep |
| claude-rule:workflow | `claude/rules/workflow.md` → `-` | — | general workflow instructions | low | partial / shared rules overlap | always-on | low / medium | validator/sync | n/a / lint/validator partial | merge/delete |
| claude-rule:workspace | `claude/rules/workspace.md` → `-` | — | workspace hygiene | low | partial / shared workspace-hygiene | always-on | low / medium | validator/sync | n/a / lint/validator partial | merge/delete |

## claude-skill

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-skill:branch-cleanup | `claude/skills/branch-cleanup/SKILL.md` → `claude/skills/branch-cleanup/SKILL.md` | — | branch cleanup workflow | medium | none / none | manual-only | wrong branch deletion / medium | skill schema + permission ask | yes / git checks | keep |
| claude-skill:break-consensus | `-` → `shared/skills/claude-code/break-consensus/SKILL.md` | innovation | manual innovation exploration | required | none / none | manual-only | inappropriate use / low | manual-only flag + novelty audit | partial / no | add |
| claude-skill:config-audit | `claude/skills/config-audit/SKILL.md` → `shared/skills/claude-code/config-audit/SKILL.md` | review | configuration audit | medium | none / validate-layout overlaps partially | manual-only | false warning / low | validator + skill schema | yes / validator primary | keep |
| claude-skill:deep-research-mode | `claude/skills/deep-research-mode/SKILL.md` → `-` (archive `docs/archive/skills/deep-research-mode/SKILL.md`) | — | generic deep research mode | low | built-in exploration / model-routing | manual-only | overresearch / low | archive presence | yes / no | archive |
| claude-skill:gh:coderabbit | `claude/skills/gh:coderabbit/SKILL.md` → `-` (archive `docs/archive/skills/gh:coderabbit/SKILL.md`) | review-progress-retrospective | external PR review integration | low | none / pr-review | manual-only | external dependency drift / low | archive presence | yes / no | archive |
| claude-skill:gh:index | `claude/skills/gh:index/SKILL.md` → `shared/skills/gh-index/SKILL.md` | — | GitHub workflow index | medium | none / none | manual-only | stale command names / low | skill schema + stale scan | yes / no | rename/keep |
| claude-skill:gh:issue | `claude/skills/gh:issue/SKILL.md` → `shared/skills/claude-code/gh-issue/SKILL.md` | — | issue workflow | high | none / none | manual-only | external action confusion / medium | contract tests + ask rules | yes / gh CLI helper | rename/keep |
| claude-skill:gh:pr | `claude/skills/gh:pr/SKILL.md` → `shared/skills/claude-code/gh-pr/SKILL.md` | — | pull-request workflow | high | none / none | manual-only | external side effect / high | ask rules + skill schema | yes / gh CLI | rename/keep |
| claude-skill:gh:review | `claude/skills/gh:review/SKILL.md` → `shared/skills/claude-code/gh-review/SKILL.md` | review-progress-retrospective | PR review workflow | high | none / pr-review overlap limited to entrypoint | manual-only | duplicate review / low | skill schema + review contract | yes / deterministic checks first | rename/keep |
| claude-skill:gh:start | `claude/skills/gh:start/SKILL.md` → `shared/skills/claude-code/gh-start/SKILL.md` | routing | issue start/implementation owner workflow | high | none / project-orchestrator/fast-worker removed | manual-only | handoff churn / medium | test-gh-start-contract | yes / gh-issue-fetch | rename/simplify |
| claude-skill:introspect | `claude/skills/introspect/SKILL.md` → `-` (archive `docs/archive/skills/introspect/SKILL.md`) | — | agent self-analysis | low | normal response / none | manual-only | unverifiable output / low | archive presence | yes / no | archive |
| claude-skill:issue-parser | `claude/skills/issue-parser/SKILL.md` → `claude/bin/parse_issue.py` (archive `docs/archive/skills/issue-parser/SKILL.md`) | — | issue body parsing | high | none / gh-issue embedded use | manual-only | parse error / high | runtime smoke | yes / yes: script | relocate |
| claude-skill:issue-retrospective | `claude/skills/issue-retrospective/SKILL.md` → `-` (archive `docs/archive/skills/issue-retrospective/SKILL.md`) | review-progress-retrospective | issue retrospective record | low | Task/memory features / issue-work-logger/progress-tracker | manual-only | log bloat / low | archive presence | yes / partial | archive |
| claude-skill:issue-work-logger | `claude/skills/issue-work-logger/SKILL.md` → `-` (archive `docs/archive/skills/issue-work-logger/SKILL.md`) | review-progress-retrospective | continuous issue work logging | low | Task/memory features / issue-retrospective/progress-tracker | manual/event | log bloat / low | archive presence | yes / partial | archive |
| claude-skill:knowledge-audit | `claude/skills/knowledge-audit/SKILL.md` → `shared/skills/knowledge-audit/SKILL.md` | — | curate learned guidance on demand | medium | none / shared learnings | manual-only | promotion of weak guidance / low | manual audit contract | yes / partial | keep/lazy |
| claude-skill:model-routing | `claude/skills/model-routing/SKILL.md` → `shared/skills/claude-code/model-routing/SKILL.md` | routing | detailed owner/model routing | high | none / CLAUDE.md contains summary only | manual-only | over-escalation / medium | routing contract | yes / no | keep/lazy |
| claude-skill:plan-review | `claude/skills/plan-review/SKILL.md` → `shared/skills/claude-code/plan-review/SKILL.md` | review-progress-retrospective | invoke independent plan review | high | none / plan-reviewer is executor not duplicate | manual-only | duplicate review / low | skill/agent contract | yes / deterministic checks first | keep |
| claude-skill:pr-review | `claude/skills/pr-review/SKILL.md` → `shared/skills/claude-code/pr-review/SKILL.md` | review-progress-retrospective | PR review process | high | none / gh-review entrypoint overlap controlled | manual-only | duplicate review / low | skill schema | yes / deterministic checks first | keep |
| claude-skill:progress-tracker | `claude/skills/progress-tracker/SKILL.md` → `-` (archive `docs/archive/skills/progress-tracker/SKILL.md`) | review-progress-retrospective | task progress tracking | low | native task tracking / issue logger/retrospective | manual/event | context/log bloat / low | archive presence | yes / yes | archive |
| claude-skill:python-refactor-analysis | `claude/skills/python-refactor-analysis/SKILL.md` → `shared/skills/python-refactor-analysis/SKILL.md` | — | deterministic Python refactor analysis | high | none / none | manual-only | analysis false positive / medium | pytest suite | yes / yes: analyzer | keep |
| claude-skill:token-efficiency | `claude/skills/token-efficiency/SKILL.md` → `-` (archive `docs/archive/skills/token-efficiency/SKILL.md`) | — | token-saving advice | low | modern model/context management / CLAUDE.md brevity guidance | manual-only | overcompression / low | archive presence | yes / no | archive |
| claude-skill:x-article-to-markdown | `claude/skills/x-article-to-markdown/SKILL.md` → `-` (archive `docs/archive/skills/x-article-to-markdown/SKILL.md`) | — | convert X article to Markdown | low | none / none | manual-only | network/content drift / low | archive presence | yes / partial | archive |

## shared-skill

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| shared-skill:git-operations | `-` → `shared/skills/git-operations/SKILL.md` | — | mode-separated generic Git operation router | high | none / dedicated gh and cleanup skills | on demand | wrong authority inference / high | authority contract + runtime discovery | yes / git checks | add/lazy |
| shared-skill:implementation-quality | `-` → `shared/skills/implementation-quality/SKILL.md` | — | context-sensitive quality rule router | high | none / path rules and deterministic checks | on demand | missed quality gate / high | consumer contract + runtime discovery | yes / lint and tests | add/lazy |

## codex-skill

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| codex-skill:claude-second-opinion | `codex/skills/claude-second-opinion/SKILL.md` → `codex/skills/claude-second-opinion/SKILL.md` | — | request an isolated Claude second opinion | medium | none / none | manual-only | low / medium | skill schema | yes / scripts where available | keep |
| codex-skill:doctor | `codex/skills/doctor/SKILL.md` → `codex/skills/doctor/SKILL.md` | — | diagnose Codex environment/configuration | medium | none / none | manual-only | low / medium | skill schema | yes / scripts where available | keep |
| codex-skill:issue-writing | `codex/skills/issue-writing/SKILL.md` → `codex/skills/issue-writing/SKILL.md` | — | write structured issues | medium | none / none | manual-only | low / medium | skill schema | yes / scripts where available | keep |
| codex-skill:kaggle | `codex/skills/kaggle/SKILL.md` → `codex/skills/kaggle/SKILL.md` | — | Kaggle workflows and modules | medium | none / none | manual-only | low / medium | skill schema | yes / scripts where available | keep |

## helper/external

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| helper:agmsg | `shared/skills/agmsg/SKILL.md` → `shared/skills/agmsg/SKILL.md` | runtime-state external-local | Claude Code/Codex local message transport; generic engine compatibility preserved | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | keep |
| helper:codex-herdr-state | `codex/herdr-agent-state.sh` → `codex/herdr-agent-state.sh` | external-herdr runtime-state | publish Codex agent state to Herdr | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | keep |
| helper:emit-system-message | `-` → `claude/hooks/lib/emit_system_message.py` | runtime-state | emit JSON-safe bounded hook systemMessage output | high | none / none | SessionStart/PostCompact | truncation at byte bound / medium | test-hook-context + hook metrics | n/a / yes | add/keep |
| helper:gh-issue-fetch | `claude/bin/gh-issue-fetch.sh` → `claude/bin/gh-issue-fetch.sh` | external-github | fetch issue data through approved gh invocation | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | keep |
| helper:gh-progress-sync | `claude/bin/gh-progress-sync.sh` → `claude/bin/gh-progress-sync.sh` | external-github review-progress-retrospective | synchronize issue progress | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | keep |
| helper:gh-projects-integration | `claude/scripts/gh-projects-integration.sh` → `claude/scripts/gh-projects-integration.sh` | external-github | GitHub Projects integration | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | keep |
| helper:gh-retrospective | `claude/bin/gh-retrospective.sh` → `claude/bin/gh-retrospective.sh` | external-github review-progress-retrospective | write issue retrospective when explicitly invoked | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | keep |
| helper:gtr-finish | `claude/bin/gtr-finish` → `claude/bin/gtr-finish` | runtime-state | finish git worktree workflow | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | keep |
| helper:gtr-start | `claude/bin/gtr-start` → `claude/bin/gtr-start` | runtime-state | start git worktree workflow | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | keep |
| helper:parse-issue | `claude/skills/issue-parser/SKILL.md` → `claude/bin/parse_issue.py` | runtime-utility | deterministically parse issue body | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | relocate |
| helper:private-routing-locate | `-` → `claude/bin/private-routing-locate` | private-routing runtime-state | locate opt-in private routing file without reading content | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | add |
| helper:project-locate | `claude/bin/project-locate` → `claude/bin/project-locate` | runtime-state | resolve project root deterministically | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | keep |
| helper:project-policy-gate | `-` → `claude/bin/project-policy-gate` | runtime-state | reject project/local settings that reserve managed security surfaces | high | none / none | every Bash call/runtime check | project security customization intentionally rejected / high | test-managed-policy + pre-bash + runtime doctor | n/a / yes | add/keep |
| helper:slack-notify | `claude/bin/slack-notify` → `claude/bin/slack-notify` | external-slack | send explicit Slack notification | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | keep |
| helper:statusline | `claude/statusline.sh` → `claude/statusline.sh` | runtime-state | render local status line | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | keep |
| helper:uvw | `-` → `claude/bin/uvw` | runtime-utility | isolate uv mutable state in a temporary tree | conditional | none / none | on demand/event | external/runtime failure / medium | script tests or syntax | n/a / yes | add |

## hook

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| hook:config-change-hook | `claude/hooks/config-change-hook.sh` → `claude/hooks/config-change-hook.sh` | — | block unsafe user/project settings changes during a live session | high | partial / rules/CI where noted | event-only | low / medium | managed registration + project-policy fixtures | yes / config-change | keep |
| hook:herdr-agent-state | `claude/hooks/herdr-agent-state.sh` → `claude/hooks/herdr-agent-state.sh` | — | update Herdr agent state | high | partial / rules/CI where noted | event-only | external socket/state drift / low | syntax/registration | yes / runtime script | keep |
| hook:post-compact-hook | `claude/hooks/post-compact-hook.sh` → `claude/hooks/post-compact-hook.sh` | — | restore bounded repository orientation after compaction | high | partial / rules/CI where noted | PostCompact systemMessage | low / low | JSON + byte-bound test | yes / script | keep/bound |
| hook:pr-review-hook | `claude/hooks/pr-review-hook.sh` → `claude/hooks/pr-review-hook.sh` | review-progress-retrospective | trigger PR review notification/check | high | partial / rules/CI where noted | PostToolUse Bash | false positives / low | syntax/registration | yes / script | keep |
| hook:pre-bash-validate-hook | `claude/hooks/pre-bash-validate-hook.sh` → `claude/hooks/pre-bash-validate-hook.sh` | — | block unsafe project policy plus common dangerous command/path literals | high | partial / rules/CI where noted | every Bash call | over-block by design / medium | PreToolUse negative fixtures + command/path tests | yes / heuristic only; no complete lower boundary | keep/harden |
| hook:session-init-hook | `claude/hooks/session-init-hook.sh` → `claude/hooks/session-init-hook.sh` | — | inject bounded repository orientation | high | partial / rules/CI where noted | SessionStart systemMessage | low / low | JSON + byte-bound test | yes / script | keep/bound |
| hook:slack-notify-hook | `claude/hooks/slack-notify-hook.sh` → `claude/hooks/slack-notify-hook.sh` | — | send explicit lifecycle notifications to Slack | high | partial / rules/CI where noted | event-only | network/config failure / low | syntax/registration | yes / script | keep |
| hook:test-quality-hook | `claude/hooks/test-quality-hook.sh` → `-` | review-progress-retrospective | model-based test quality advice after tools | low | partial / rules/CI where noted | frequent | high false positives / low | path absence | n/a / CI/rules | delete |
| hook:user-prompt-submit-hook | `claude/hooks/user-prompt-submit-hook.sh` → `-` | — | inject prompt-time advice | low | partial / rules/CI where noted | every prompt | context pollution / low | path absence | n/a / root rules | delete |

## install

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| mechanism:bootstrap | `bootstrap.sh` → `bootstrap.sh` | — | install links only after managed policy/runtime checks | high | none / migration overlaps limited | install-time | partial install / high | test-bootstrap | n/a / yes | harden |
| mechanism:managed-installer | `-` → `scripts/install-managed-policy.sh` | — | install exact root-owned managed policy drop-in | high | none / bootstrap calls it | install-time | wrong target/permissions / high | test-managed-policy/bootstrap | n/a / yes | add |
| mechanism:manifest | `install/manifest.tsv` → `install/manifest.tsv` | — | public symlink installation map | high | none / none | install-time | target collision / high | bootstrap/validator tests | n/a / yes | keep |

## legacy

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| legacy:whole-directory-links | `~/.claude -> repo/claude; ~/.codex -> repo/codex; ~/.agents -> repo/shared` → `-` | legacy | legacy install layout | no | manifest links / new manifest | always coupled runtime/source | repo pollution / high | migration/validator tests | n/a / yes | remove via migration |

## migration

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| mechanism:migration | `scripts/migrate-layout.sh` → `scripts/migrate-layout.sh` | — | migrate legacy whole-directory links without reading secrets | high | none / bootstrap cutover related | manual | data loss if wrong / high | test-migration | n/a / yes | keep |
| mechanism:record-inventory | `scripts/record-migration-inventory.sh` → `scripts/record-migration-inventory.sh` | — | record path/type inventory without secret contents | medium | none / classification report | manual | metadata omission / medium | fixture test via migration suite | n/a / yes | keep |

## output-style

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| output-style:darasan | `claude/output-styles/darasan.md` → `claude/output-styles/darasan.md` | — | optional darasan response style | optional | default style / none | manual selection only | style leakage / low | path presence | n/a / no | keep opt-in |
| output-style:hiyos | `claude/output-styles/hiyos.md` → `claude/output-styles/hiyos.md` | — | optional hiyos response style | optional | default style / none | manual selection only | style leakage / low | path presence | n/a / no | keep opt-in |
| output-style:kuroko | `claude/output-styles/kuroko.md` → `claude/output-styles/kuroko.md` | — | optional kuroko response style | optional | default style / none | manual selection only | style leakage / low | path presence | n/a / no | keep opt-in |
| output-style:ojosama | `claude/output-styles/ojosama.md` → `claude/output-styles/ojosama.md` | — | optional ojosama response style | optional | default style / none | manual selection only | style leakage / low | path presence | n/a / no | keep opt-in |

## private-overlay

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| runtime:overlay-manifest | `-` → `${XDG_CONFIG_HOME:-$HOME/.config}/agents-toolkit/overlay/manifest.tsv` | private-overlay | install machine-specific non-secret overlay links | optional | none / none | install-time | target collision / high | bootstrap overlay tests | n/a / yes | keep external |
| runtime:private-routing | `claude/CLAUDE.local.md` → `${XDG_CONFIG_HOME:-$HOME/.config}/agents-toolkit/private-routing.md` | private-routing | machine-specific specialist routing, read only when selected | optional | none / none | on demand | stale mapping / medium | resolver contract test | n/a / path resolver | relocate outside repo |

## reference

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| codex-reference:python-quality | `-` → `codex/references/python-quality.md` | lazy | Python quality guidance loaded only when needed | high | none / formerly inline in AGENTS.md | on-demand | low / low | sync-shared-rules --check | yes / lint supplements | relocate from AGENTS.md; not a skill |

## settings

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| mechanism:codex-hooks | `codex/hooks.json` → `codex/hooks.json` | — | Codex hook registrations | medium | none / none | event-only | runtime mismatch / medium | JSON validation | n/a / yes | keep |
| mechanism:managed-hooks | `claude/settings.json` → `claude/managed-settings.json` | — | only audited toolkit hooks are loaded | high | managed hook lock / project/plugin hooks blocked | session/event | blocked third-party plugin hooks / medium | policy checker + registration count | n/a / yes | relocate/harden |
| mechanism:managed-permissions | `-` → `claude/managed-settings.json` | — | non-overridable owner-selected bypassPermissions default | high | managed settings official feature / permission rules skipped by bypass | session configuration | no permission enforcement / high | policy checker + installer + live doctor | n/a / yes | add managed policy |
| mechanism:managed-sandbox | `claude/settings.json` → `claude/managed-settings.json` | — | record owner-selected disabled sandbox policy | high | native sandbox available / user-scope policy superseded | session configuration | no filesystem or network isolation / high | policy checker + installer | n/a / yes | relocate/disable by owner decision |
| mechanism:user-settings | `claude/settings.json` → `claude/settings.json` | — | non-security user preferences, model alias and plugin choices | high | none / security policy removed to managed scope | session configuration | plugin/config drift / medium | JSON + policy checker | n/a / yes | split/keep |

## shared-rule

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| shared-rule:decision-integrity | `shared/rules/decision-integrity.md` → `shared/rules/core-contract.md` | always-on | decision-integrity shared guidance | high | partial / core contract | imported or embedded | low / medium | sync + context metrics | n/a / lint/managed policy partial | merge/core |
| shared-rule:failure-investigation | `shared/rules/failure-investigation.md` → `shared/rules/failure-investigation.md` | — | failure-investigation shared guidance | high | partial / none | imported or embedded as configured | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | keep |
| shared-rule:framework-respect | `shared/rules/framework-respect.md` → `-` | — | framework-respect shared guidance | medium | partial / documented merge | imported or embedded as configured | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | merge into karpathy-guidelines |
| shared-rule:git-safety | `shared/rules/git-safety.md` → `-` | — | git-safety shared guidance | medium | partial / documented merge | imported or embedded as configured | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | merge into git-workflow + managed policy |
| shared-rule:git-workflow | `shared/rules/git-workflow.md` → `shared/rules/git-workflow.md` | — | git-workflow shared guidance | high | partial / none | imported or embedded as configured | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | keep |
| shared-rule:issue-completeness | `shared/rules/issue-completeness.md` → `shared/rules/issue-completeness.md` | — | issue-completeness shared guidance | high | partial / none | not imported by default | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | keep |
| shared-rule:karpathy-guidelines | `shared/rules/karpathy-guidelines.md` → `shared/rules/core-contract.md` | always-on | scoped implementation discipline | high | partial / core contract | imported or embedded | low / medium | sync + context metrics | n/a / lint/managed policy partial | merge/core |
| shared-rule:learnings | `shared/rules/learnings.md` → `shared/rules/learnings.md` | — | learnings shared guidance | high | partial / none | not imported by default | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | keep/lazy |
| shared-rule:markdown-rules | `shared/rules/markdown-rules.md` → `shared/rules/markdown-rules.md` | — | markdown-rules shared guidance | high | partial / none | imported or embedded as configured | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | keep |
| shared-rule:no-fallback | `shared/rules/no-fallback.md` → `shared/rules/no-fallback.md` | — | no-fallback shared guidance | high | partial / none | imported or embedded as configured | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | keep |
| shared-rule:python-guidelines | `shared/rules/python-guidelines.md` → `shared/rules/python-guidelines.md` | — | python-guidelines shared guidance | high | partial / none | not imported by default | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | keep |
| shared-rule:quality-priority | `shared/rules/quality-priority.md` → `shared/rules/core-contract.md` | always-on | quality priority guidance | high | partial / core contract | imported or embedded | low / medium | sync + context metrics | n/a / lint/managed policy partial | merge/core |
| shared-rule:scope-discipline | `shared/rules/scope-discipline.md` → `-` | — | scope-discipline shared guidance | medium | partial / documented merge | imported or embedded as configured | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | merge into decision-integrity |
| shared-rule:self-improvement | `shared/rules/self-improvement.md` → `shared/rules/self-improvement.md` | — | self-improvement shared guidance | high | partial / none | imported or embedded as configured | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | keep |
| shared-rule:test-policy | `shared/rules/test-policy.md` → `shared/rules/test-policy.md` | — | test-policy shared guidance | high | partial / none | imported or embedded as configured | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | keep |
| shared-rule:workspace-hygiene | `shared/rules/workspace-hygiene.md` → `shared/rules/workspace-hygiene.md` | — | workspace-hygiene shared guidance | high | partial / none | imported or embedded as configured | low / medium | sync check + grep metrics | n/a / lint/managed policy partial | keep |

## contract

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| contract:context-consumers | `-` → `docs/contracts/context-consumers.tsv` | — | context load and consumer declaration | high | none / validator parsing | change-time | stale consumer / high | validator negative fixtures | n/a / yes | add |
| contract:skill-authority | `-` → `docs/contracts/skill-authority.tsv` | — | skill mode side-effect contract | high | none / tool approval supplements | change-time | authority drift / high | validator + workflow tests | n/a / yes | add |

## validation

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| mechanism:hook-metrics | `-` → `scripts/measure-hook-injection.py` | — | measure controlled hook systemMessage bytes and bound | high | none / metrics invokes | release-time | fixture drift / low | test-hook-context | n/a / yes | add |
| mechanism:context-runtime-audit | `-` → `scripts/audit-context-runtime.sh` | context-runtime | verify effective Claude/Codex memory, plugin, symlink, and skill discovery state | high | vendor plugin/feature listing / bootstrap/check-runtime partial | post-bootstrap/live acceptance | vendor CLI output drift / high | test-audit-context-runtime/live run | zero-inference Claude probe / yes | add |
| mechanism:metrics | `-` → `scripts/measure-metrics.sh` | — | reproducible before/after metrics including injection bytes | high | none / report consistency | release-time | stale classification / medium | test-measure-metrics/report consistency | n/a / yes | add/expand |
| mechanism:model-pin-scanner | `-` → `scripts/lib/scan-model-pins.py` | — | parse supported YAML/JSON/TOML model routing syntax fail-closed | high | none / none | on demand/event | low / high | validator and metric negative fixtures | n/a / yes | add/keep |
| mechanism:package | `-` → `scripts/package-release.sh` | — | git-archive package and release lint | high | git archive / none | release-time | artifact contamination / high | package --check | n/a / yes | add |
| mechanism:policy-checker | `-` → `scripts/check-managed-policy.py` | — | validate managed/user split and reject project/local security policy surfaces | high | none / installer shares checker | install/CI | schema drift / high | test-managed-policy negative fixtures | n/a / yes | add |
| mechanism:runtime-doctor | `-` → `scripts/check-runtime.sh` | — | fail closed on unsupported XDG/runtime versions | high | claude doctor partial / none | install/session check | environment false positive / medium | test-check-runtime | n/a / yes | add/harden |
| mechanism:source-verifier | `-` → `scripts/verify-requirements-source.sh` | — | verify external PDF against source manifest | high | sha256 tool / none | review-time | wrong source file / high | test-requirements-source | n/a / yes | add |
| mechanism:sync-rules | `shared/bin/sync-shared-rules.sh` → `shared/bin/sync-shared-rules.sh` | — | synchronize shared rules into consumer documents | high | none / manual copies | release-time | stale embeds / medium | test-sync-shared-rules | n/a / yes | keep/harden |
| mechanism:validator | `scripts/validate-layout.sh` → `scripts/validate-layout.sh` | — | deterministic structure/security/release contract gate | high | none / config-audit skill delegates | CI | false positive / high | test-validate-layout | n/a / yes | expand |

## validation-test

| id | before → after | tags | purpose | needed | built-in / overlap | context | false positive / failure | verification | low-cost / deterministic | disposition |
|---|---|---|---|---|---|---|---|---|---|---|
| validation:fixture-old-layout-lib | `tests/lib/fixture-old-layout.sh` → `tests/lib/fixture-old-layout.sh` | — | construct deterministic legacy layout fixtures | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | keep |
| validation:test-agmsg-state-home | `tests/test-agmsg-state-home.sh` → `tests/test-agmsg-state-home.sh` | — | verify agmsg runtime state stays outside the repository | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | keep |
| validation:test-audit-context-runtime | `-` → `tests/test-audit-context-runtime.sh` | context-runtime | verify runtime audit parsing, discovery, plugin, and broken-link failures | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | add |
| validation:test-bootstrap | `tests/test-bootstrap.sh` → `tests/test-bootstrap.sh` | — | verify manifest installation, managed-policy prerequisite, and drift handling | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | keep |
| validation:test-check-runtime | `-` → `tests/test-check-runtime.sh` | — | verify runtime version, XDG, and project-policy fail-closed gates | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | add |
| validation:test-fixture-old-layout | `tests/test-fixture-old-layout.sh` → `tests/test-fixture-old-layout.sh` | — | provide legacy-layout migration fixture assertions | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | keep |
| validation:test-gh-start-contract | `-` → `tests/test-gh-start-contract.sh` | — | verify gh-start single-owner and issue parser contracts | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | add |
| validation:test-hook-context | `-` → `tests/test-hook-context.sh` | — | verify bounded JSON-safe SessionStart/PostCompact messages | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | add |
| validation:test-managed-policy | `-` → `tests/test-managed-policy.sh` | — | verify managed policy installation and lower-scope rejection | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | add |
| validation:test-measure-metrics | `-` → `tests/test-measure-metrics.sh` | — | verify reproducible metrics and fail-closed model scanner | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | add |
| validation:test-migration | `tests/test-migration.sh` → `tests/test-migration.sh` | — | verify legacy migration and managed-policy integration | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | keep |
| validation:test-pre-bash-hook | `-` → `tests/test-pre-bash-hook.sh` | — | verify PreToolUse project-policy, .env, amend, and device guards | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | add |
| validation:test-private-routing-contract | `-` → `tests/test-private-routing-contract.sh` | — | verify private-routing locator and priority contract | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | add |
| validation:test-report-consistency | `-` → `tests/test-report-consistency.sh` | — | verify report metrics match measured source of truth | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | add |
| validation:test-requirements-source | `-` → `tests/test-requirements-source.sh` | — | verify content-addressed requirements source identity | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | add |
| validation:test-sync-shared-rules | `tests/test-sync-shared-rules.sh` → `tests/test-sync-shared-rules.sh` | — | verify generated shared-rule sections are synchronized | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | keep |
| validation:test-uvw | `-` → `tests/test-uvw.sh` | — | verify sandbox-compatible uv state relocation | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | add |
| validation:test-validate-layout | `tests/test-validate-layout.sh` → `tests/test-validate-layout.sh` | — | verify validator positive and negative fixtures | high | none / none | CI/test-only | fixture drift / medium | direct CI execution | n/a / yes | keep |
