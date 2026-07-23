# agents-toolkit 近代化（2026-07-23）

2026 年時点の主要コーディングエージェント（Claude Code 2.1.x / Codex CLI）と Agent Skills 公式仕様に合わせた近代化。目的は (1) 初期エージェントの弱さを補うために継ぎ足された機構の証拠に基づく約 30% 縮約、(2) 手動起動型の革新探索 skill（`break-consensus`）の追加。

## Baseline（変更前の検証記録）

- 変更前 commit: `baseline: pristine agents-toolkit-master from zip`（本作業はその直後のコミットとして記録）
- 変更前テスト: `scripts/validate-layout.sh` PASS / `sync-shared-rules.sh --check` OK / `tests/test-*.sh` 6 本 PASS / `python-refactor-analysis` pytest 20 passed（詳細ログは作業環境の `reports/baseline-tests.txt`）
- 検証環境: Claude Code 2.1.218 / node v22 / Codex CLI 未導入（Codex 側は公式ドキュメントでのみ検証）

## 計測（before → after）

トークン数は直接計測できないため文字数・行数を代理指標とする（すべて「推定」。`wc -c` バイト数）。

| 指標 | before | after | 削減 |
|---|---|---|---|
| Codex 常時ロード（AGENTS.md） | 23,116 chars / 375 行 | 16,065 chars / 219 行 | **−30.5%** |
| Claude 常時ロード合計¹ | 19,952 chars | 16,744 chars | −16.1% |
| 　└ CLAUDE.md | 3,980 / 59 行 | 2,909 / 37 行 | −27% |
| 　└ 常時ロード rules（paths なし） | 3,667（4 file） | 1,954（2 file） | −47% |
| 　└ import される共有ルール | 12,305（13 本） | 11,881（10 本） | −3%² |
| 両エージェント常時ロード合計 | 43,068 chars | 32,809 chars | **−23.8%** |
| custom agent 数 | 14 | 9 | **−36%** |
| claude skill 数 | 21 | 13（+break-consensus 込み） | **−38%** |
| hook script 数 / 登録数 | 9 / 8 | 7 / 7 | −22% / −13% |
| rule ファイル数（shared+claude） | 16 + 7 = 23 | 13 + 5 = 18 | −22% |
| model 名固定の常設 routing 規則 | 表 1 + 判断基準 4 項 + 「常に委任」規定 | 0（原則ベースへ置換） | −100% |
| 同一原則の重複記述³ | 5 組 | 0 | −100% |
| 典型 task の強制 handoff | 常時 1+（main 直接作業禁止・>3 step 委任・plan-review 3 agent） | 0（単一 owner 完遂・plan-review 1 agent） | — |

¹ CLAUDE.md + paths なし rules + import 共有ルール。² 大型ルール（decision-integrity 2,936 chars・karpathy 統合先）は「数合わせで価値ある機構を削除しない」原則により保持したため、文字数削減は構成要素の統合分のみ。³ YAGNI（karpathy§2 vs scope-discipline）、テスト網羅（test-policy vs python-guidelines#7）、テスト無効化禁止（test-policy vs failure-investigation）、No-Fallback（no-fallback vs python-guidelines#10）、git 安全（git-safety vs git-workflow/settings deny）。

## Evidence matrix（Phase 2 調査の要約）

情報源優先順位は公式 docs > 公式 repo > Agent Skills 一次仕様 > OSS > 記事。各判断: 判断 / 現行 / 一次情報 / 採否 / 確信度。

| # | 判断 | 一次情報（確認日 2026-07-23） | 結論・採否 | 確信度 |
|---|---|---|---|---|
| 1 | CLAUDE.md は 200 行以下推奨、@import・path-scoped rules（`paths:` frontmatter）は公式機能 | code.claude.com/docs/en/memory | 現行構成は既に公式準拠。常時ロードを縮約 | 高 |
| 2 | skill `name` は `a-z0-9-` のみ・64 字以内・親ディレクトリ名と一致（コロン不可。`:` は plugin/nested の namespace 区切り） | agentskills.io/specification | `gh:*` 5 skill を `gh-*` へ改名（採用） | 高 |
| 3 | SKILL.md は 500 行 / 5,000 token 以下、description ≤1024 字、scripts/references/assets 構成 | agentskills.io/specification + best-practices | 全 skill 適合。break-consensus も準拠（115 行） | 高 |
| 4 | `disable-model-invocation: true` で手動起動限定にできる | code.claude.com/docs/en/skills | break-consensus の手動起動保証に採用 | 高 |
| 5 | `skillOverrides: off` は実在する設定 | code.claude.com/docs/en/skills | off の 8 skill は「利用しない判断済み」の実測証拠 → archive | 高 |
| 6 | TodoWrite は廃止（TaskCreate/TaskUpdate へ）、MultiEdit は現行 docs に存在しない | 公式 docs + GitHub issues | TodoWrite/MultiEdit 依存の記述・skill を archive/削除（採用） | 中〜高 |
| 7 | subagent frontmatter の `model: sonnet/opus/haiku/fable/inherit`・`isolation: worktree`・`maxTurns` は公式 | code.claude.com/docs/en/sub-agents | agent 定義の tier alias 指定は維持（version 固定ではない） | 高 |
| 8 | built-in agents: Explore / Plan / general-purpose | 同上 | 汎用探索は built-in Explore を使用。routing-only orchestrator は不要 | 高 |
| 9 | Agent Teams は依然 experimental | code.claude.com/docs/en/agent-teams | 抑制ルールを 1 行に縮約して維持 | 高 |
| 10 | Hooks: SessionStart/PreToolUse/PostToolUse/PostCompact/ConfigChange/Notification/Stop 等すべて公式イベント | code.claude.com/docs/en/hooks | 既存 hook の registration は有効。整理は重複・助言性で判断 | 高 |
| 11 | auto memory は GA（MEMORY.md、autoMemoryEnabled） | code.claude.com/docs/en/memory | 学習事項の常時注入 hook は不要 → 削除。auto memory + claudedocs/learnings.md に一本化 | 高 |
| 12 | Codex user skills は `~/.agents/skills`（クロスエージェント合意事実上の標準）、hooks.json は公式サポート | developers.openai.com/codex/skills, /hooks | 現行 manifest の配置は正しい。python-quality skill を同所へ追加 | 高 |
| 13 | Codex AGENTS.md はグローバル+repo 連結で既定 32KiB 上限 | developers.openai.com/codex/guides/agents-md | 23KiB は上限内だが縮約価値あり → 16KiB へ | 高 |
| 14 | output styles は現行サポート（deprecated ではない） | code.claude.com/docs/en/output-styles | 4 styles は opt-in のまま維持（常時コスト 0、品質規則と未混在） | 高 |
| 15 | 発想の均質化・novelty 監査・実験変換の実証研究 | evidence.md（arXiv/Nature/Science Advances 等 30 件） | break-consensus の各 Stage 設計根拠として採用 | 高 |

未検証事項: (a) TodoWrite→TaskCreate の公式移行文書は未発見（第三者情報 + 実装観察。確信度 85%）。(b) AGENTS.md 内の Codex plugin `approval_mode = "approve"` 記法は公式 docs で確認できず（ユーザー環境の実設定注記として現状維持・本作業では変更しない）。(c) `claude/rules/safety.md` の複合コマンド権限バイパス（issue #16180）の現在の open/closed 状態は未確認のため保持。

## 縮約の実施内容と根拠（Phase 3）

### 3.1 常時コンテキスト

- **CLAUDE.md**: モデル名固定の役割表・「main は直接作業しない」規定・「>3 step→Agent」規定・毎回の委任判断手順・communication style 節を撤去し、「必要十分な最小コストの単一 owner が完遂」原則 + 例外経路（隔離/エスカレーション/独立検証）に置換。orchestration 節は orchestrator 廃止に伴い削除
- **claude/rules**: `workflow.md`（TodoWrite/MultiEdit 前提・step 数委任・30 分 checkpoint 等の旧世代運用）と `workspace.md` を削除し、生存項目（lint/typecheck・claudedocs 配置・記録の承認境界）を `code-quality.md` へ統合
- **codex/AGENTS.md**: python-guidelines（3.2KB）を `python-quality` skill へ、issue-completeness（3.1KB）を `issue-writing` skill へ遅延ロード化。scope-discipline / framework-respect / git-safety は統合により除去

### 3.2 default routing

PDF 指定の既定原則をそのまま採用（単一 owner 完遂 / owner≠最高性能モデル / 同一 context 再利用時は handoff しない / 大量探索のみ隔離 / 独立仮説比較のみ並列化 / reviewer・specialist・高価モデルは条件付き / 失敗後エスカレーション可 / 再委任原則禁止 / step 数を基準にしない）。詳細は `model-routing` skill に集約。

### 3.3 agents（14 → 9）

| agent | 処置 | 根拠 |
|---|---|---|
| fast-worker | 削除 | 「単なる fast worker」。単一 owner 既定で不要。強制 handoff の主要因 |
| project-orchestrator | 削除 | 「routing だけを行う orchestrator」。8.2KB の常設ルーティング表。原則ベース + private-routing.md で代替 |
| plan-reviewer-{completeness,critic,feasibility} | 1 体へ統合（plan-reviewer） | 同じ対象を少し違う観点で見る 3 reviewer。3 handoff → 1。観点は統合定義に全て保持 |
| security-reviewer | code-reviewer へ統合 | 検出パターンの正本が archive 対象の gh:coderabbit だった。自己完結の統合レビュー基準に置換（worktree isolation は統合先へ継承） |
| deep-reasoner | 維持（説明更新） | 「reasoning model が判断し標準モデルが実装」経路の判断役。escalation 条件を明記 |
| ai-engineer / data-engineer / solidity-engineer / sre / model-qa-specialist / blockchain-security-auditor | 維持 | 実在する専門領域（ユーザーの常用領域: Python ML/データ + Solidity DeFi）。数合わせで削除しない |

### 3.4 skills（claude 21 → 13、codex 4 → 5）

- archive（9 本 → `docs/archive/skills/`、根拠は同所 README）: settings.json で off 済みの 8 本（gh:coderabbit, progress-tracker, issue-retrospective, issue-parser, issue-work-logger, introspect, token-efficiency, x-article-to-markdown。off = 利用しない判断の実測証拠）+ deep-research-mode（一般助言のみの薄い wrapper）
- 改名（Agent Skills 仕様準拠）: `gh:index/issue/pr/review/start` → `gh-index/issue/pr/review/start`。**呼び出しは `/gh-pr` 等に変わる**
- 追加: `break-consensus`（Phase 4）、`python-quality`（codex 遅延ロード先。新機能ではなく AGENTS.md からの移設）
- 更新: plan-review（1 agent 化）、model-routing（新原則の詳細）、pr-review（改名参照）

### 3.5 hooks（9 → 7）

- 削除: `test-quality-hook.sh`（モデルが判断可能な助言のみ・CI/test-policy と重複・repo 外 `~/bin/setup-test-quality.sh` 依存）、`user-prompt-submit-hook.sh`（毎ターン learnings 注入 = 廃止対象パターンの実装。settings.json に未登録の dead code でもあった）
- 維持: pre-bash-validate（.env 読取遮断等、モデル指示では保証できない決定論的制約）、config-change（settings 編集遮断）、session-init / post-compact（最小限の状態注入）、pr-review（ライフサイクル検出）、slack-notify（確定イベント通知）、herdr-agent-state（外部ツール管理・自己無効化ガード付き）

### 3.6 output styles

4 種は明示選択時のみロードされる趣味的 style（常時コスト 0・品質/routing 規則と未混在）のため維持。default 未設定の現状を既定とする。

## Phase 4: break-consensus skill

`claude/skills/break-consensus/`（SKILL.md 115 行 + references/evidence.md）。手動起動限定（`disable-model-invocation: true` + 禁止場面の明記）。新規常設 agent は追加せず、built-in Explore / deep-reasoner / plan-reviewer を再利用。

Stage 構成: 1 Problem Frame → 2 Consensus Map（合意領域を concept cluster 化し baseline として封鎖） → 3 Assumption Destruction（9 操作 + 探索空間変化の説明義務） → 4 Remote Mechanism Transfer（構造対応 6 項目の抽出を採用条件に） → 5 Forced Heterogeneity（生成原理タグの重複禁止、3-7 候補） → 6 Novelty Audit（機構ベース検索による独立調査。「新規らしい」=「調査範囲で未発見」まで） → 7 Falsifiable Experiment(事前固定の反証条件付き最小実験) → 採用候補のみ通常実装経路へ。

差別化（2026-07-23 の独立調査済み）: superpowers/brainstorming（要件明確化ゲート）・ADHD skill（並列 diverge+critic）等の既存 skill に、合意封鎖・原理 quota・検索 novelty 監査・実験変換を end-to-end で持つものはない。名称衝突なし。独自部分（合意封鎖・原理 quota）は直接実証のない仮説であることを evidence.md に明示し、反証手順も記載。

## 検証（Phase 5）

- shell 構文（bash -n 全 .sh）/ JSON（jq）: PASS
- `scripts/validate-layout.sh`: PASS（警告は従来からの bypassPermissions のみ）
- `sync-shared-rules.sh --check`: OK
- `tests/test-*.sh` 6 本: PASS
- `python-refactor-analysis` pytest: 20 passed
- bootstrap e2e（一時 HOME へ `--apply` → `--check`）: PASS: all 35 manifest entries are correctly linked

## 運用上の注意（breaking changes）

1. スラッシュコマンド改名: `/gh:pr` → `/gh-pr` 等（旧名は動かない）
2. 削除 agent（fast-worker / project-orchestrator / plan-reviewer-* / security-reviewer）を参照する private 設定（`private-routing.md`・CLAUDE.local.md）があれば更新が必要
3. Codex で Python 品質ゲートは常時ロードではなく `python-quality` skill の自動発火に依存する（発火しない場合は `$python-quality` で明示起動）
4. 復元はすべて `docs/archive/skills/` + git 履歴から可能
