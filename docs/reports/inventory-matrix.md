# Phase 1 要素別監査表（inventory matrix — 2026-07-24、適合性レビュー M-02 対応）

要件書 Phase 1 の 11 軸（①目的 ②現在の必要性 ③組み込み代替 ④重複 ⑤常時 context 消費 ⑥誤作動/false positive ⑦失敗時影響 ⑧検証可能性 ⑨低コストモデル適性 ⑩deterministic 置換 ⑪処置）で、baseline（commit `6c980f1`）の全要素を評価した記録。処置の実装 commit は `b39f215`（初回縮約）以降のレビュー対応 commit 系列。凡例: 処置 = keep / merge / delete / archive / lazy（遅延ロード化）/ relocate。evidence 列は報告書（`docs/plans/2026-07-23-agents-toolkit-modernization.md`）の節番号または migration 記録（`docs/migration/classification.md`）。

列は 11 軸を圧縮表記する: **目的 / 必要 / 組込代替 / 重複 / 常時消費 / 誤作動 / 失敗影響 / 検証 / 低コスト適性 / 決定論置換 / 処置**。

## 1. custom agents（baseline 14 → 9）

| path | 目的 | 必要 | 組込代替 | 重複 | 常時消費 | 誤作動 | 失敗影響 | 検証 | 低コスト適性 | 決定論置換 | 処置 | evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| fast-worker | 軽作業の低コスト委任 | 低 | **有: model tier alias + built-in general-purpose** | project-orchestrator | 無(定義のみ) | 誤 routing 誘発 | 低 | 可 | 本体が代替 | tier 指定で置換 | **delete** | §3.3 / classification |
| project-orchestrator | 多段委任の統括 | 低 | **有: 単一 owner + built-in orchestration** | 常時委任 anti-pattern | 無 | 過剰委任・コスト増 | 中 | 困難 | 不適 | routing 原則で置換 | **delete** | §3.3 |
| plan-reviewer-completeness | 計画の網羅レビュー | 中 | 無 | critic/feasibility と 3 分割重複 | 無 | 三重起動でコスト増 | 低 | 可 | 適 | 不可 | **merge → plan-reviewer** | §3.3 |
| plan-reviewer-critic | 計画の批判レビュー | 中 | 無 | 同上 | 無 | 同上 | 低 | 可 | 適 | 不可 | **merge → plan-reviewer** | §3.3 |
| plan-reviewer-feasibility | 実現可能性レビュー | 中 | 無 | 同上 | 無 | 同上 | 低 | 可 | 適 | 不可 | **merge → plan-reviewer** | §3.3 |
| security-reviewer | 汎用 security レビュー | 中 | 部分(built-in review 慣行) | code-reviewer と大部分重複 | 無 | 二重指摘 | 低 | 可 | 適 | lint/SAST が補完 | **merge → code-reviewer** | §3.3 |
| code-reviewer | 独立コードレビュー | 高 | 無(独立 context が価値) | なし(統合後) | 無 | 低 | 低 | 可 | 適 | 不可 | keep | §3.3 |
| deep-reasoner | 難問の reasoning 委任 | 高 | 無 | なし | 無 | 過剰使用でコスト増(条件を明文化) | 低 | 可 | 不適(高コスト前提) | 不可 | keep(起動条件を限定) | §3.3 |
| ai-engineer | ML ドメイン専門作業 | 高(所有 project 由来) | 無 | なし | 無 | 低 | 中 | 可 | 部分 | 不可 | keep(**full model pin は撤去** → tier alias) | §3.2 |
| data-engineer / model-qa-specialist / sre / solidity-engineer / blockchain-security-auditor | 各ドメイン高リスク作業 | 高 | 無 | なし | 無 | 低 | 中〜高 | 可 | 部分 | 不可 | keep(高リスク・専門作業限定を CLAUDE.md に明文化) | §3.3 |

## 2. Claude skills（baseline 21 → 13）

| path | 目的 | 必要 | 組込代替 | 重複 | 常時消費 | 誤作動 | 失敗影響 | 検証 | 低コスト適性 | 決定論置換 | 処置 | evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| gh:start / gh:pr / gh:issue / gh:review / gh:index | GitHub workflow 定型化 | 高 | 無 | なし | 無(手動) | 低 | 中 | contract test | 適 | 部分(gh CLI) | keep(**gh-\* へ改名**・gh-start の無条件委任撤去) | §3.4 / ATK-003 |
| gh:coderabbit | 外部レビューツール連携 | 低(未使用) | 無 | pr-review | 無 | 中 | 低 | 不可(外部依存) | 適 | 不可 | **archive** | classification |
| deep-research-mode | 調査モード切替 | 低 | **有: built-in Explore/plan mode** | model-routing | 無 | 中 | 低 | 困難 | 適 | 不可 | **archive** | classification |
| introspect | 自己分析出力 | 低 | 有(通常応答で可) | なし | 無 | 低 | 低 | 困難 | 適 | 不可 | **archive** | classification |
| issue-parser | issue 本文の構造化 | 高(runtime 依存) | 無 | gh:issue 内蔵 | 無 | 低 | 高(gh-issue が壊れる) | unit test | 適 | **有: script 化** | **relocate → claude/bin/parse_issue.py**(skill 削除) | ATK-001 |
| issue-retrospective / issue-work-logger / progress-tracker | 進捗・振り返り記録 | 低 | **有: native auto memory + TaskCreate 系** | 3 skill 相互重複 | 無 | 記録肥大 | 低 | 困難 | 適 | 部分 | **archive**(3 件) | classification |
| token-efficiency | token 節約指針 | 低 | 有(モデル改善で不要) | CLAUDE.md 原則 | 無 | 過剰圧縮で品質低下 | 低 | 困難 | 適 | 不可 | **archive** | classification |
| x-article-to-markdown | X 記事変換 | 低(単発用途) | 無 | なし | 無 | 低 | 低 | 可 | 適 | 部分 | **archive** | classification |
| branch-cleanup | 安全な branch 掃除 | 中 | 無 | なし | 無 | 誤削除(ask gate で緩和) | 中 | test | 適 | **半: script 主体** | keep | §3.4 |
| config-audit | 設定監査 | 中 | 無 | validate-layout と分担 | 無 | 低 | 低 | validator | 適 | **有: validate-layout が主担** | keep(validator へ委譲部分を明記) | §3.4 |
| knowledge-audit | learnings 棚卸し | 高(learnings 遅延化の対) | 部分(auto memory) | なし | 無 | 低 | 低 | 可 | 適 | 部分 | keep | ATK-005 |
| model-routing | routing 詳細手順 | 高 | 無 | CLAUDE.md(要約のみ常時) | 無(skill 側は遅延) | 低 | 低 | contract test | 適 | 不可 | keep(常時分は CLAUDE.md へ圧縮) | §3.1 |
| plan-review / pr-review | レビュー手順 | 高 | 無 | なし(agent と役割分離) | 無 | 低 | 低 | 可 | 適 | 不可 | keep | §3.4 |
| python-refactor-analysis | 決定論的リファクタ分析 | 高 | 無 | なし | 無 | 低 | 低 | **pytest 20** | 適 | **本体が deterministic tool** | keep | §3.4 |
| break-consensus | 革新探索(Phase 4) | 新規要件 | 無 | なし(novelty audit で担保) | 無(手動限定) | 誤発動(手動限定で遮断) | 低 | novelty audit + 反証実験 | 部分 | 不可 | **add(要件指定の 1 件)** | Phase 4 |

## 3. codex skills（baseline 4 → 5）

| path | 目的 | 必要 | 組込代替 | 重複 | 常時消費 | 誤作動 | 失敗影響 | 検証 | 低コスト適性 | 決定論置換 | 処置 | evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude-second-opinion / doctor / issue-writing / kaggle | Codex 側 workflow | 中〜高 | 無 | なし | 無 | 低 | 低〜中 | 部分 | 適 | 部分 | keep | §3.4 |
| python-quality | Python 規約の遅延ロード | 高 | 無 | AGENTS.md 常時インラインと重複していた | **削減: 常時 → 遅延** | 低 | 低 | sync --check | 適 | 部分 | **relocate ← AGENTS.md**(純増 1。EX-001 承認済み例外) | §3.6 / EX-001 |

## 4. hooks（baseline 9 → 7）

| path | 目的 | 必要 | 組込代替 | 重複 | 常時消費 | 誤作動 | 失敗影響 | 検証 | 低コスト適性 | 決定論置換 | 処置 | evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| test-quality-hook | test 品質の事後検査 | 低 | **有: test-policy rule + CI** | test-policy rule | 毎 tool call | false positive 多 | 低 | 困難 | — | **有: CI/lint** | **delete** | classification |
| user-prompt-submit-hook | prompt 前処理 | 低 | 有(CLAUDE.md 原則) | CLAUDE.md | 毎 prompt | 中 | 低 | 困難 | — | 不可 | **delete** | classification |
| pre-bash-validate-hook | 危険 command の事故防止 | 高 | 部分(**boundary は permission/sandbox 側**) | permission deny と役割分担 | 毎 Bash call(軽量) | **over-block 側に設計**(literal 共起) | 中(block 誤り) | **33 assertion test** | — | **有: 最終境界は sandbox/permission**(hook は heuristic 層と再定義) | keep(fail-closed 化・quote 正規化) | H-011/H-014 |
| session-init-hook | git 状態の自動注入 | 高 | 無 | なし | session 毎(小) | 低 | 低 | test | — | **本体が deterministic** | keep | §3.5 |
| config-change-hook / post-compact-hook / pr-review-hook / slack-notify-hook / herdr-agent-state | 設定変更検知・compact 後復元・PR 通知・状態記録 | 中 | 無 | なし | event 時のみ | 低 | 低 | 部分 | — | 本体 script | keep | §3.5 |

## 5. rules（claude 7 → 5、shared 16 → 13）

| path | 目的 | 必要 | 組込代替 | 重複 | 常時消費 | 誤作動 | 失敗影響 | 検証 | 低コスト適性 | 決定論置換 | 処置 | evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude/rules/workflow.md | 作業手順原則 | 低 | 部分 | karpathy/decision-integrity と重複 | **常時** | — | 低 | — | — | 不可 | **merge → 共有 rules** | §3.1 |
| claude/rules/workspace.md | workspace 衛生 | 低 | 無 | workspace-hygiene(shared)と重複 | **常時** | — | 低 | — | — | 不可 | **merge → workspace-hygiene** | §3.1 |
| claude/rules/code-quality.md / markdown.md / python.md | 言語・書式規約 | 高 | 無 | なし(path-scoped) | **無: paths frontmatter で scoped** | 低 | 低 | sync --check | — | lint が補完 | keep(path-scoped 維持) | §3.1 |
| claude/rules/safety.md / settings-syntax.md | Claude Code 固有安全・構文知識 | 高 | 無 | なし | safety は常時(小)・settings-syntax は path-scoped | 低 | 高(誤設定防止) | validator | — | 部分(validator) | keep(現行仕様へ全面改訂) | H-015 |
| shared/rules/framework-respect.md | framework 尊重 | 中 | 無 | karpathy-guidelines §3 と重複 | 常時 | — | 低 | — | — | 不可 | **merge → karpathy §3** | §3.1 |
| shared/rules/git-safety.md | git 危険操作抑止 | 中 | **有: permission ask/deny が deterministic 代替** | git-workflow と重複 | 常時 | — | 中 | — | — | **有: settings 側へ** | **merge → git-workflow + settings gate** | §3.1 |
| shared/rules/scope-discipline.md | scope 逸脱防止 | 中 | 部分 | decision-integrity と重複 | 常時 | — | 低 | — | — | 不可 | **merge → decision-integrity** | §3.1 |
| shared/rules/learnings.md | 蓄積知見 | 中 | **有: native auto memory** | auto memory | **常時 import 2 経路 → 0** | 肥大で context 圧迫 | 低 | knowledge-audit | — | 不可 | **lazy**(必要時参照 + auto memory 移行。EX-002) | ATK-005 / EX-002 |
| shared/rules/その他 12 件(karpathy / no-fallback / decision-integrity / quality-priority / test-policy / git-workflow / failure-investigation / self-improvement / workspace-hygiene / markdown-rules / python-guidelines / issue-completeness) | 中核原則・規約 | 高 | 無 | なし(統合後) | 常時 9 件 + 遅延/配布 3 件 | 低 | 中 | sync --check + CI | — | 不可 | keep(統合先として維持) | §3.1 |

## 6. output styles（4 → 4）と routing 機構

| 要素 | 目的 | 必要 | 組込代替 | 重複 | 常時消費 | 誤作動 | 失敗影響 | 検証 | 低コスト適性 | 決定論置換 | 処置 | evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| output-styles 4 件(darasan/hiyos/kuroko/ojosama) | 趣味的口調 style | 低(娯楽) | — | なし | **無(明示選択時のみ)** | 品質規則と混在すると有害 | 低 | — | — | — | keep(**PDF 3.6 準拠: default style 常用・明示選択時のみ・品質/routing 規則と分離**) | PDF §3.6 |
| full model pin(ai-engineer の opus 固定) | 特定 model 固定 | 低 | **有: tier alias** | — | — | 陳腐化・コスト固定 | 中 | scanner | — | **有: alias** | **delete(pin 1 → 0)** | ATK-002 |
| /gh-start の無条件 general-purpose 委任 | 全 issue の定型委任 | 低 | **有: 単一 owner 原則** | — | — | 常時 handoff コスト | 中 | contract test | — | routing 原則 | **delete(無条件委任 1 → 0)** | ATK-003 |
| learnings 常時 import(CLAUDE.md/AGENTS.md の 2 経路) | 知見の常時注入 | 低 | **有: auto memory + 必要時参照** | learnings.md | **常時 2 → 0** | context 肥大 | 低 | metrics | — | 不可 | **lazy** | ATK-005 |
| progress/review/retrospective 機構(進捗系 skill 3 + test-quality/user-prompt hook 2) | 進捗・品質の常設監視 | 低 | **有: TaskCreate 系・native memory・CI** | 相互重複 | hook 2 件は毎 event | false positive | 低 | — | — | CI/lint | **delete/archive(5 → 0)** | classification |
| custom agent と built-in の重複(fast-worker↔general-purpose・project-orchestrator↔built-in orchestration) | — | — | — | **重複 2 → 0** | — | — | — | — | — | — | **delete** | §3.3 |

## 集計（機械計測は metrics block が正）

- 常時注入量の完全な推定: `combined_always_on_total`（機械計測）+ native auto memory（**機械計測不能**: machine 蓄積依存。導入直後は 0。accepted exception EX-002 と実機チェックリストで管理）
- 行数系: `claude_md_lines` / `claude_always_rules_lines` / `codex_agents_md_lines` を measure-metrics.sh に追加済み（報告書 metrics block 参照）
- progress/review/retrospective 機構数: 5 → 0（上表）
- custom↔built-in agent 重複件数: 2 → 0（上表）
- output_styles: 4 → 4（keep。報告書の計測表にも掲載）
