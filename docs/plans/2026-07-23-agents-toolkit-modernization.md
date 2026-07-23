# agents-toolkit 近代化（2026-07-23）

2026 年時点の主要コーディングエージェント（Claude Code 2.1.x / Codex CLI）と Agent Skills 公式仕様に合わせた近代化。目的は (1) 初期エージェントの弱さを補うために継ぎ足された機構の証拠に基づく約 30% 縮約、(2) 手動起動型の革新探索 skill（`break-consensus`）の追加。

**改訂履歴**: v1（初回実装）→ 独立レビュー（REQUEST_CHANGES、指摘 ATK-001〜015）→ **v2（本版。全 15 件対応済み）**。対応内容は末尾「レビュー対応（v2）」を参照。

## Baseline（変更前の検証記録）

- 変更前 commit: `baseline: pristine agents-toolkit-master from zip`（本作業はその後続コミットとして記録）
- 変更前テスト: `scripts/validate-layout.sh` PASS / `sync-shared-rules.sh --check` OK / `tests/test-*.sh` 6 本 PASS / `python-refactor-analysis` pytest 20 passed
- **証跡**: [docs/reports/baseline-2026-07-23.txt](../reports/baseline-2026-07-23.txt)（実行コマンド・環境・exit code 付き。SHA-256: `7ec80713c1b631a5add4b03f4f4acd12bbe77f0b24dd896e3f39e94c94e27a58`）
- 検証環境: Claude Code 2.1.218 / node v22 / Codex CLI 未導入（Codex 側は公式ドキュメントでのみ検証）

## 計測（before → after）

**再計測は `scripts/measure-metrics.sh` を clean checkout で実行する**（定義はスクリプト冒頭に記載。バイト数は `wc -c`、対象は git 追跡ファイル、docs/・tests/ 除外）。トークン数は直接計測できないため文字数を代理指標とする（推定）。

| 指標 | before | after | 削減 |
|---|---|---|---|
| 常時ロード合計（両エージェント） | 43,068 bytes | 31,673 bytes | **−26.5%** |
| 　└ Codex（AGENTS.md） | 23,116 | 15,271 | **−33.9%** |
| 　└ Claude 合計¹ | 19,952 | 16,402 | −17.8% |
| 　　　CLAUDE.md | 3,980 | 3,444² | −13% |
| 　　　常時ロード rules（paths なし） | 3,667（4 file） | 2,104（2 file） | −43% |
| 　　　import される共有ルール | 12,305（13 本） | 10,854（9 本） | −12% |
| custom agent 数 | 14 | 9 | **−36%** |
| claude skill 数（active） | 21 | 13（break-consensus 込み） | **−38%** |
| hook script 数 / 登録数 | 9 / 9 | 7 / 8 | −22% / −11% |
| rule ファイル数（shared+claude） | 16 + 7 = 23 | 13 + 5 = 18 | −22% |
| **full model pin**（完全モデル名。settings + agents） | 1（settings の `claude-fable-5` + `effortLevel: high`） | **0**（`sonnet` / `medium` へ） | −100% |
| **tier alias**（agents frontmatter の sonnet/opus。pin と別指標） | 9 | 9（維持: version 非依存の役割指定） | ±0 |
| **無条件委譲**（gh-start タスクループの強制 Agent 呼び出し） | 1（タスク数 = handoff 数） | **0**（単一 owner 既定 + 条件付き委譲） | −100 % |
| 常時ロードされる learnings | 2 経路（CLAUDE.md import + AGENTS.md 埋め込み） | **0**（必要時参照 + knowledge-audit 遅延同期） | −100% |
| 同一原則の重複記述³ | 5 組 | 0 | −100% |

¹ CLAUDE.md + paths なし rules + import 共有ルール。² v2 で private routing 消費契約・learnings 参照条件を明文化したため v1（2,909）より微増。³ YAGNI、テスト網羅、テスト無効化禁止、No-Fallback、git 安全の各重複。

**典型 task の handoff 定義**: 「明確な小規模 Issue を `/gh-start` で処理する際の実装委譲回数」。before = タスクごとに `general-purpose` へ委譲（N タスク = N handoff、SKILL.md が無条件強制）。after = 0（owner 完遂。委譲は context isolation / specialist / independent verification / parallelism の明示該当時のみで、理由を checkpoint に記録）。静的検証: `tests/test-gh-start-contract.sh`。

## Evidence matrix（Phase 2 調査の要約）

情報源優先順位は公式 docs > 公式 repo > Agent Skills 一次仕様 > OSS > 記事。

| # | 判断 | 一次情報（確認日 2026-07-23） | 結論・採否 | 確信度 |
|---|---|---|---|---|
| 1 | CLAUDE.md は 200 行以下推奨、@import・path-scoped rules は公式機能 | code.claude.com/docs/en/memory | 常時ロードを縮約 | 高 |
| 2 | skill `name` は `a-z0-9-`・64 字以内・親 dir 名一致（コロン不可） | agentskills.io/specification | `gh:*` 5 skill を `gh-*` へ改名 | 高 |
| 3 | SKILL.md ≤500 行、description ≤1024 字。`allowed-tools` は **space 区切り文字列**（experimental） | agentskills.io/specification | 全 active skill を space 区切りへ統一し、validator check 9 で機械検査（core spec 準拠の検査対象: name/description/allowed-tools 形式。`argument-hint` 等は Claude Code vendor extension として別扱い） | 高 |
| 4 | `disable-model-invocation: true` で手動起動限定にできる | code.claude.com/docs/en/skills | break-consensus に採用 | 高 |
| 5 | `skillOverrides: off` は実在する設定 | 同上 | off の 8 skill は「利用しない判断済み」の実測証拠 → archive | 高 |
| 6 | TodoWrite は廃止（TaskCreate/TaskUpdate へ）、MultiEdit は現行 docs に存在しない | 公式 docs + GitHub issues | 依存記述・skill を archive/削除 | 中〜高 |
| 7 | subagent frontmatter の tier alias（sonnet/opus 等）・isolation・maxTurns は公式 | code.claude.com/docs/en/sub-agents | tier alias は version 非依存のため維持（full pin とは区別して計測） | 高 |
| 8 | built-in agents: Explore / Plan / general-purpose | 同上 | routing-only orchestrator は不要 | 高 |
| 9 | Agent Teams は experimental・既定無効・token 消費大 | code.claude.com/docs/en/agent-teams | **共有設定の常時有効化を撤去**。settings.local.json での opt-in に変更 | 高 |
| 10 | `bypassPermissions` は prompt injection への保護なし。sandbox は `allowUnsandboxedCommands: false` で hard gate | code.claude.com/docs/en/permission-modes, /sandboxing | **共有既定を default + sandbox 有効 + unsandboxed 禁止へ変更**。危険設定は waiver 必須の fatal 検査に | 高 |
| 11 | model alias: sonnet = daily coding、opus = complex reasoning。低 effort = 低コスト | code.claude.com/docs/en/model-config | **共有既定を `sonnet` + `medium` へ**。完全モデル名 pin は共有設定から排除 | 高 |
| 12 | auto memory は GA | code.claude.com/docs/en/memory | learnings の常時注入を全廃（必要時参照 + auto memory） | 高 |
| 13 | Codex user skills は `~/.agents/skills`、hooks.json 公式サポート、AGENTS.md は連結 32KiB 上限 | developers.openai.com/codex/* | python-quality skill を同所へ。AGENTS.md 15.3KB へ縮約 | 高 |
| 14 | output styles は現行サポート | code.claude.com/docs/en/output-styles | opt-in のまま維持（常時コスト 0） | 高 |
| 15 | 発想均質化・novelty 監査・実験変換の実証研究 | break-consensus references/evidence.md | 各 Stage の設計根拠 | 高 |

未検証事項: (a) TodoWrite→TaskCreate の公式移行文書は未発見（第三者情報 + 実装観察、確信度 85%）。(b) AGENTS.md 内の Codex plugin `approval_mode = "approve"` 記法は公式 docs で確認できず（ユーザー環境の実設定注記として現状維持）。(c) `claude/rules/safety.md` の複合コマンド権限バイパス（issue #16180）の現在状態は未確認のため保持。(d) sandbox 有効化後の WSL2 実機での動作は本環境では検証不能（不可時は failIfUnavailable: false により通常 permission flow へフォールバック）。

## 縮約の実施内容と根拠（Phase 3）

### 3.1 常時コンテキスト

- **CLAUDE.md**: モデル名固定の役割表・「main は直接作業しない」規定・「>3 step→Agent」規定・communication style 節を撤去し、「必要十分な最小コストの単一 owner が完遂」原則へ置換。learnings の常時 import を廃止（必要時参照 + `/knowledge-audit` 遅延同期）
- **claude/rules**: `workflow.md`（TodoWrite/MultiEdit 前提・step 数委任）と `workspace.md` を削除し、生存項目を `code-quality.md` へ統合
- **codex/AGENTS.md**: python-guidelines → `python-quality` skill、issue-completeness → `issue-writing` skill、learnings → 必要時参照へ遅延化。scope-discipline / framework-respect / git-safety は統合により除去

### 3.2 default routing と実行時既定値

規則（CLAUDE.md）と実行時既定（settings.json）を一致させた:

- settings.json: `model: sonnet`（旧: `claude-fable-5`）、`effortLevel: medium`（旧: high）、`permissions.defaultMode: default`（旧: bypassPermissions）、sandbox 有効 + `allowUnsandboxedCommands: false`、`skipDangerousModePermissionPrompt` 削除、Agent Teams 環境変数削除
- 高価モデル・高 effort への昇格は `model-routing` skill の条件（反復失敗・根本原因不明・競合仮説）でのみ行い、実装は標準モデルの owner に戻す
- 危険設定を共有既定に残す場合は `docs/waivers/settings-waivers.tsv` の期限付き waiver 行が必須（なければ `validate-layout.sh` が FAIL）。machine-local の緩和は untracked の `settings.local.json` で行う

### 3.3 agents（14 → 9）

| agent | 処置 | 根拠 |
|---|---|---|
| fast-worker / project-orchestrator | 削除 | 単なる worker / routing-only orchestrator。単一 owner 既定で不要 |
| plan-reviewer-{completeness,critic,feasibility} | 1 体へ統合（plan-reviewer） | 同一対象への 3 視点 reviewer。3 handoff → 1。観点は統合定義に保持 |
| security-reviewer | code-reviewer へ統合 | 検出パターンの正本が archive 対象 skill だった。自己完結の統合基準に置換 |
| deep-reasoner | 維持 | reasoning model が判断し標準モデルが実装する経路の判断役 |
| ドメインスペシャリスト 6 体 | 維持 | 実在する専門領域（Python ML/データ + Solidity DeFi）。数合わせで削除しない |

### 3.4 skills（claude 21 → 13、codex 4 → 5）

- archive（9 本 → `docs/archive/skills/`）: off 済み 8 本 + deep-research-mode。決定論的パーサー `parse_issue.py` は skill ではなく**ランタイム utility として `claude/bin/` に存置**（`gh-issue-fetch.sh` の実行時依存。ATK-001）
- 改名: `gh:*` → `gh-*`（Agent Skills 仕様準拠。呼び出しは `/gh-pr` 等に変わる）
- gh-start: 単一 owner 既定 + 条件付き委譲（理由の checkpoint 記録必須）に改訂
- 追加: `break-consensus`（新規挙動）、`python-quality`（AGENTS.md からの移設。3.6 参照）

### 3.5 hooks（9 → 7）

- 削除: `test-quality-hook.sh`（助言のみ・CI と重複・repo 外依存）、`user-prompt-submit-hook.sh`（毎ターン learnings 注入 = 廃止対象パターン。未登録 dead code）
- 維持: pre-bash-validate / config-change（モデル指示では保証できない決定論的制約）、session-init / post-compact（最小状態注入）、pr-review（ライフサイクル検出）、slack-notify（確定イベント通知）、herdr-agent-state（外部ツール管理・自己無効化ガード付き）

### 3.6 skill directory 純増 2 件の例外記録（ATK-010）

PDF の「新しい skill を 1 つだけ追加」に対し、active skill directory の純増は 2 件:

- `claude/skills/break-consensus`（**新規挙動** — PDF Phase 4 が指定する 1 件）
- `codex/skills/python-quality`（**既存指示の移設** — AGENTS.md に常時インラインだった python-guidelines の遅延ロード先。新規挙動なし。Codex に path-scoped rules 機構がないため、skill が唯一の遅延ロード単位）

分類: added directory 2 / relocated content 1 / **new behavior 1**。python-quality を AGENTS.md へ戻すと常時ロード +3.2KB（縮約目標と衝突）のため、移設例外として記録する。**承認: 要件所有者が 2026-07-23 に例外を承認済み**（「例外で良い」）。

### 3.7 private routing の消費契約（ATK-011）

- status: **opt-in active config**（deprecated archive ではない）
- 配置: untracked `${XDG_CONFIG_HOME:-~/.config}/agents-toolkit/private-routing.md`（migration が旧 `claude/CLAUDE.local.md` から移動）
- 消費者: owner（main セッション）。契約は claude/CLAUDE.md「private routing」節に定義 — specialist 選択時に存在確認し、存在する場合のみ該当 project 節を参照。不在時はエラーにせず原則ベースで判断
- 検証: 移動は `tests/test-migration.sh`、参照契約の文書存在は validator check 10 の対象 tree に含まれる CLAUDE.md 本文で担保

## Phase 4: break-consensus skill

`claude/skills/break-consensus/`（SKILL.md + references/evidence.md）。手動起動限定（`disable-model-invocation: true` + 禁止場面明記）。新規常設 agent なし（built-in Explore / deep-reasoner / plan-reviewer を再利用）。

Stage 構成: 1 Problem Frame → 2 Consensus Map（合意領域を封鎖 baseline 化） → 3 Assumption Destruction → 4 Remote Mechanism Transfer（構造対応 6 項目が採用条件） → 5 Forced Heterogeneity（生成原理タグ重複禁止） → 6 **Novelty Audit（standard/deep は別 context の独立 auditor 必須。入力契約でアンカリング防止: 動作原理・入出力・主張・観測可能差分のみを渡し、生成 rationale・期待評価は渡さない。light は「独立性なし」を成果物に明示）** → 7 Falsifiable Experiment（事前固定の反証条件） → 採用候補のみ通常実装経路へ。

## 検証（v2 時点）

- shell 構文（bash -n 全 .sh）/ JSON（jq）: PASS
- `scripts/validate-layout.sh`（check 8 危険設定 fatal・check 9 skill schema・check 10 stale reference を含む 10 検査）: PASS
- `sync-shared-rules.sh --check`: OK
- `tests/test-*.sh` 7 本（新規 `test-gh-start-contract.sh` 含む）: PASS
- `python-refactor-analysis` pytest: 20 passed
- bootstrap e2e（clean HOME `--apply` → `--check`）: PASS（`test-gh-start-contract.sh` 内で fake gh による `/gh-start` 経路の end-to-end も検証）
- `scripts/package-release.sh --check`（release lint）: PASS
- `scripts/measure-metrics.sh`: 本レポートの表と一致

## 運用上の注意（breaking changes）

1. スラッシュコマンド改名: `/gh:pr` → `/gh-pr` 等
2. **settings.json の既定値変更**: model `sonnet` / effort `medium` / sandbox 有効（`allowUnsandboxedCommands: false`）/ Agent Teams 無効 / `skipDangerousModePermissionPrompt` 削除。`defaultMode: bypassPermissions` は**要件所有者の決定（2026-07-23）により期限付き waiver（`docs/waivers/settings-waivers.tsv`、expires 2027-07-23）とともに共有既定へ復帰** — validator check 8 は waiver 有効期間中 WARN 扱い、期限切れで FAIL に転じ再判断を強制する。旧構成と異なり sandbox が有効なため、防御レイヤーは以前より厚い。sandbox が有効に動作する machine で unsandboxable なコマンドの拒否が実務を妨げる場合は、`allowUnsandboxedCommands` の waiver 追加または `settings.local.json` での調整を検討する
3. 削除 agent（fast-worker / project-orchestrator / plan-reviewer-* / security-reviewer）を参照する private 設定があれば更新が必要
4. Codex の Python 品質ゲートは `python-quality` skill の自動発火に依存（明示起動は `$python-quality`）
5. 復元はすべて `docs/archive/skills/` + git 履歴から可能

## レビュー対応（v2）

| ID | 対応 |
|---|---|
| ATK-001 | `parse_issue.py` を `claude/bin/` へ復帰、`gh-issue-fetch.sh` を SCRIPT_DIR 相対解決に変更、gh-start Technical Details / `gtr-start` の旧参照更新、`tests/test-gh-start-contract.sh` で fake gh e2e + パーサー欠落時の非ゼロ終了 + 旧参照ゼロを検証 |
| ATK-002 | settings を `sonnet` + `medium` へ。full pin は validator check 8 の検査対象（full-model-pin）に追加。エスカレーション条件は model-routing に集約 |
| ATK-003 | gh-start Phase 2 を単一 owner 既定に改訂。委譲は 4 条件の明示該当時のみ + checkpoint に理由記録。無条件テンプレート 0 を静的テストで担保 |
| ATK-004 | skipDangerousModePermissionPrompt / allowUnsandboxedCommands / sandbox 無効を共有設定から除去し、check 8 を waiver 必須の fatal に変更（期限付き waiver TSV、fixture テスト付き）。bypassPermissions のみ要件所有者の決定（2026-07-23）で期限付き waiver とともに共有既定へ復帰（sandbox 有効化は維持） |
| ATK-005 | learnings の CLAUDE.md import と AGENTS.md 埋め込みを廃止。必要時参照 + knowledge-audit skill への遅延同期に変更（計測: 常時ロード learnings 0） |
| ATK-006 | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` を共有設定から削除。settings.local.json での opt-in を CLAUDE.md に明記 |
| ATK-007 | `scripts/measure-metrics.sh` を同梱（定義付き）。full pin / tier alias / 無条件委譲を分離計測し、本レポートの表を再計測値で更新 |
| ATK-008 | Stage 6 を別 context auditor 必須（standard/deep）に改訂。入力契約（rationale 不渡し）と出力要件（検索式・範囲・最近傍・根拠・未検証範囲）を明記。light は独立性なしを明示 |
| ATK-009 | 全 active skill の `allowed-tools` を space 区切りへ統一。validator check 9（name/dir 一致・名前規則・description 長・allowed-tools 形式）を追加、fixture テスト付き。「適合」主張を core spec 検査範囲と vendor extension に分離 |
| ATK-010 | 純増 2 件を「new behavior 1 + relocated content 1」として本レポート 3.6 に例外記録。要件所有者が 2026-07-23 に承認済み |
| ATK-011 | private-routing を opt-in active config と一意定義し、消費者・起動条件・不在時挙動を CLAUDE.md に明文化。classification.md の旧記述を更新 |
| ATK-012 | baseline 証跡を `docs/reports/baseline-2026-07-23.txt` として同梱（SHA-256 記載） |
| ATK-013 | safety.md / gtr-start / gh-start / classification.md の stale 参照を修正。validator check 10（stale reference、fixture テスト付き）を追加し再発を CI で検出 |
| ATK-014 | gitleaks 導入手順を「保存 → 公式 checksums 照合 → 成功時のみ展開」に変更 |
| ATK-015 | `scripts/package-release.sh`（git archive + 禁止 entry lint）を追加し CI に組込み。配布 archive から .git/・cache を排除 |
