# agents-toolkit 近代化（2026-07-23）

2026 年時点の主要コーディングエージェント（Claude Code 2.1.x / Codex CLI）と Agent Skills 公式仕様に合わせた近代化。目的は (1) 継ぎ足された機構の証拠に基づく約 30% 縮約、(2) 手動起動型の革新探索 skill（`break-consensus`）の追加。

**改訂履歴**: v1（初回実装）→ レビュー1（REQUEST_CHANGES、ATK-001〜015）→ v2（全件対応）→ 再レビュー（REQUEST_CHANGES: ATK-004/006/007/011 未解消・H-001〜005）→ **v3（本版。再レビュー指摘を全件反映）**。対応内訳は末尾「レビュー対応履歴」。

## Baseline（変更前の検証記録）

- 変更前 commit: `baseline: pristine agents-toolkit-master from zip`
- **証跡**: [docs/reports/baseline-2026-07-23.txt](../reports/baseline-2026-07-23.txt)（SHA-256: `7ec80713c1b631a5add4b03f4f4acd12bbe77f0b24dd896e3f39e94c94e27a58`）
- 証跡の範囲に関する明示例外（H-003）: baseline 証跡は「実行コマンド・環境・exit code・各テスト末尾 3 行」の**要約証跡として受入**とする。全 stdout/stderr が必要な調査では、baseline commit を checkout して同コマンドを再実行する（テストは冪等・自己完結）
- 検証環境: Claude Code 2.1.218 / node v22 / Codex CLI 未導入（Codex 側は公式ドキュメントでのみ検証）

## 計測（before → after）

**再現手順（1 コマンド）**: `scripts/measure-metrics.sh --before-ref <baseline-commit> --after-ref HEAD`（改名前 `gh:start` / 改名後 `gh-start` 両 layout を自動認識。単一 tree は `--repo <dir>`。期待値テスト: `tests/test-measure-metrics.sh`）。以下の表は同スクリプトの実測値（バイト数 = `wc -c`、推定トークンの代理指標）。

| 指標（script の出力 key） | before | after | 削減 |
|---|---|---|---|
| combined_always_on_total | 43,068 | 32,464 | **−24.6%** |
| 　codex_agents_md_bytes | 23,116 | 15,271 | **−33.9%** |
| 　claude_always_on_total | 19,952 | 17,193¹ | −13.8% |
| custom_agents | 14 | 9 | **−36%** |
| claude_skills | 21 | 13 | **−38%** |
| codex_skills | 4 | 5² | +1 |
| hook_scripts / hook_registrations | 9 / 9 | 7 / 8 | −22% / −11% |
| shared_rules + claude_rules | 16 + 7 | 13 + 5 | −22% |
| **full_model_pins**（settings + agent frontmatter + TOML の完全モデル名） | 1 | **0** | −100% |
| **tier_aliases**（agent frontmatter の sonnet/opus 等。pin と別指標） | **14** | 9 | −36% |
| **unconditional_delegation_gh_start**（タスクループの無条件 Agent 委譲） | 1 | **0** | −100% |
| **always_on_learnings_paths**（常時ロードされる learnings 経路） | 2 | **0** | −100% |
| duplicated_principles_greppable（script 判定 3 シグネチャ） | 3 | **0** | −100% |
| 同・手動評価分³ | 2 | 0 | −100% |

¹ v3 で private routing 契約・claude-bypass 運用の明文化により CLAUDE.md は 4,207 bytes（v1 の 2,909 から増）。削減は rules 統合・import 削減・learnings 遅延化による。² python-quality は AGENTS.md からの移設（3.6 の承認済み例外）。³ grep で機械判定できない 2 組 = YAGNI の意味重複（karpathy §2 vs 旧 scope-discipline）と git 安全（旧 git-safety の rule 文 vs settings deny list）。統合・削除済みだが判定は手動評価であることを明記する。

**典型 task の handoff 定義**: 「明確な小規模 Issue を `/gh-start` で処理する際の実装委譲回数」。before = SKILL.md がタスクごとの `general-purpose` 委譲を無条件強制（N タスク = N handoff。script の unconditional_delegation_gh_start = 1 が該当テンプレートの存在を示す）。after = 0（owner 完遂既定。委譲は 4 条件の明示該当時のみ + checkpoint に理由記録）。検証: `tests/test-gh-start-contract.sh`（**内容: gh-issue-fetch の runtime smoke + gh-start SKILL の静的契約検査**。Claude Code 本体の skill 起動〜実装までを駆動する integration test ではない — H-004 対応の正確な名称）。

## Evidence matrix（要約）

| # | 判断 | 一次情報（確認日 2026-07-23） | 結論・採否 | 確信度 |
|---|---|---|---|---|
| 1 | CLAUDE.md ≤200 行推奨、@import・path-scoped rules は公式 | code.claude.com/docs/en/memory | 常時ロード縮約 | 高 |
| 2 | skill name は `a-z0-9-`（コロン不可） | agentskills.io/specification | `gh:*` → `gh-*` 改名 | 高 |
| 3 | `allowed-tools` は space 区切り文字列（experimental） | 同上 | 全 active skill 統一 + validator check 9 | 高 |
| 4 | `disable-model-invocation: true` は公式 | code.claude.com/docs/en/skills | break-consensus の手動起動保証 | 高 |
| 5 | TodoWrite 廃止・MultiEdit 非掲載 | 公式 docs + GitHub issues | 依存 skill を archive | 中〜高 |
| 6 | Agent Teams は experimental・既定無効・token 消費大 | code.claude.com/docs/en/agent-teams | 共有有効化を撤去。opt-in は shell 環境変数 | 高 |
| 7 | `bypassPermissions` は prompt injection 保護なし。`failIfUnavailable: false` は**警告後に unsandboxed 実行**（fail-open）、`true` は起動拒否（fail-closed）。`sandbox.credentials.files` の deny が公式（v2.1.187+）。既定 read policy は credential file を読める | code.claude.com/docs/en/sandboxing, /permission-modes | 共有既定を default + failIfUnavailable: true + credentials deny へ。bypass は環境検証ゲート付き launcher に隔離 | 高 |
| 8 | documented scope に user-level `settings.local.json` は**存在しない**（user は `~/.claude/settings.json`、local は `<project>/.claude/settings.local.json`）。permission rules はスコープ間**マージ**、他はスカラー置換 | code.claude.com/docs/en/settings | 誤った scope 記述を全修正（README / rules / classification） | 高 |
| 9 | model alias: sonnet = daily coding、低 effort = 低コスト | code.claude.com/docs/en/model-config | 共有既定 `sonnet` + `medium` | 高 |
| 10 | Codex user skills は `~/.agents/skills`、AGENTS.md 連結 32KiB 上限 | developers.openai.com/codex/* | python-quality を同所へ、AGENTS.md 15.3KB | 高 |
| 11 | 発想均質化・novelty 監査・実験変換の実証研究 | break-consensus references/evidence.md | Stage 設計根拠 | 高 |

未検証事項: (a) TodoWrite→TaskCreate の公式移行文書（確信度 85%）。(b) Codex plugin `approval_mode` 記法（ユーザー実設定の注記として維持）。(c) issue #16180 の現況。(d) sandbox fail-closed 構成の WSL2 実機動作（bubblewrap/socat 導入が前提。README に導入手順を明記）。

## 縮約の実施内容（Phase 3、v3 時点の最終状態）

### 3.1 常時コンテキスト

- CLAUDE.md: モデル固定表・常時委任規定を撤去し「最小コスト単一 owner」原則へ。learnings の常時 import 廃止（必要時参照 + `/knowledge-audit` 遅延同期）
- claude/rules: workflow.md / workspace.md を統合削除。settings-syntax.md は公式の scope・マージ仕様に合わせて全面修正
- codex/AGENTS.md: python-guidelines / issue-completeness / learnings を遅延化。−33.9%

### 3.2 実行時既定値（ATK-002/004/006 最終形）

`claude/settings.json`（source of truth と本節は一致する）:

- `model: "sonnet"` / `effortLevel: "medium"`（完全モデル名 pin 0。validator check 8 が settings・agent frontmatter・TOML を横断検査 — H-001）
- `permissions.defaultMode: "default"`（**無条件 bypass なし**）
- `sandbox`: `enabled: true` / **`failIfUnavailable: true`（fail-closed: sandbox 不可なら警告続行ではなく起動拒否）** / `allowUnsandboxedCommands: false` / `credentials.files` で `~/.ssh`・`~/.aws`・`~/.gnupg`・`~/.kube`・`~/.docker/config.json`・`~/.git-credentials`・`~/.npmrc`・`~/.pypirc` の read を deny
- Agent Teams 環境変数なし（opt-in は当該 machine の shell profile で `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`）
- 危険設定を共有既定へ戻す場合は `docs/waivers/settings-waivers.tsv` の期限付き waiver が必須（期限切れ・無 waiver は validator FAIL。fixture テスト付き）

**bypassPermissions の扱い（要件所有者の要求「bypassPermissions は必要」への v3 回答）**: 共有既定には置かず、**環境検証ゲート付き launcher `claude/bin/claude-bypass`** に隔離した。`--enable-this-machine` が (1) WSL2（/proc/version の microsoft 署名）と (2) 非 root を検証して machine-local marker（`${XDG_CONFIG_HOME:-$HOME/.config}/agents-toolkit/bypass-approved`。untracked・配布されない）を作成し、以後 `claude-bypass` が同じ検証を**毎回実行時に**行った上で `claude --permission-mode bypassPermissions` を exec する。検証不成立時は bypass せず非ゼロ終了（fail-closed）。テスト: `tests/test-claude-bypass.sh`（marker なし / 非 WSL / root / 正常系の 6 ケース）。これは意図しない bypass 配布を防ぐ policy gate であり、ローカル攻撃者への security boundary ではない（そちらは sandbox / VM の責務）。

### 3.3 agents（14 → 9）/ 3.4 skills（21 → 13）/ 3.5 hooks（9 → 7）

v2 から変更なし（fast-worker / project-orchestrator 削除、plan-reviewer 3→1、security-reviewer 統合、9 skill archive、`gh:*`→`gh-*`、test-quality / user-prompt-submit hook 削除）。`parse_issue.py` は runtime utility として `claude/bin/` に存置（ATK-001）。

### 3.6 skill directory 純増 2 件の例外記録（ATK-010 — ACCEPTED EXCEPTION）

- `claude/skills/break-consensus`（new behavior — PDF Phase 4 指定の 1 件）
- `codex/skills/python-quality`（relocated content — AGENTS.md 常時インラインの遅延ロード先。新規挙動なし）

分類: added directory 2 / relocated 1 / new behavior 1。**要件所有者が 2026-07-23 に承認**（「例外で良い」）。再レビューでも ACCEPTED EXCEPTION と判定。

### 3.7 private routing の消費契約（ATK-011 最終形）

- status: **opt-in active config**
- 配置: `${XDG_CONFIG_HOME:-$HOME/.config}/agents-toolkit/private-routing.md`（tilde 展開バグを修正し `$HOME` 表記へ）
- 消費者・起動条件: specialist 選択時に owner が resolver `claude/bin/private-routing-locate`（存在時 path + exit 0 / 不在時 exit 1・無出力）で確認し、存在時のみ該当 project 節を参照
- **優先順位**: 1. 安全制約・permission・tool restriction → 2. ユーザー明示指定 → 3. private routing の project mapping → 4. 汎用ドメイン routing 原則 → 5. 標準の単一 owner 既定
- 不在時挙動: 非エラーで 4→5 に fallback。private 内容を成果物・ログ・外部へ出力しない
- テスト: `tests/test-private-routing-contract.sh` — 契約 5 項目の静的検査（priority 欠落 fixture で非ゼロ終了することも検証）+ dummy mapping fixture で resolver が migration 後 path を選択すること + 不在時の非エラー分岐

## Phase 4: break-consensus skill

v2 から変更なし（手動起動限定、Stage 1-7、standard/deep は別 context の独立 novelty auditor 必須 + rationale 不渡しの入力契約、light は独立性なしを明示）。

## 検証（v3 時点）

- shell 構文（bash -n 全 .sh）/ JSON（jq）: PASS
- `scripts/validate-layout.sh`（10 検査 + H-001 の pin 横断検査。WARN 0 件）: PASS
- `sync-shared-rules.sh --check`: OK
- `tests/test-*.sh` **10 本**（新規: test-claude-bypass / test-private-routing-contract / test-measure-metrics）: PASS
- `python-refactor-analysis` pytest: 20 passed
- bootstrap e2e（clean HOME、test-gh-start-contract 内）: PASS
- `scripts/package-release.sh --check`: PASS
- `scripts/measure-metrics.sh --before-ref <baseline> --after-ref HEAD`: 本レポートの表と一致

## 運用上の注意（breaking changes / 導入手順）

1. スラッシュコマンド改名: `/gh:pr` → `/gh-pr` 等
2. **patch の適用は `git am` を使う**（H-002）: `git am agents-toolkit-modernization-final.patch`。mailbox 形式の複数 commit series のため、`git apply` は rename を跨ぐ 2 通目以降で失敗する（正常動作）。単一 diff が必要なら `git diff <baseline>..HEAD` を生成する
3. **settings 既定値**: sonnet / medium / defaultMode default / sandbox fail-closed。Linux・WSL2 では `sudo apt-get install bubblewrap socat` が必要（未導入だと起動拒否 = 仕様どおりの fail-closed）
4. **承認プロンプトなし運用**: `~/.claude/bin/claude-bypass --enable-this-machine` → 以後 `claude-bypass` で起動（WSL2・非 root を毎回検証）。shell alias 化する場合は `alias claude=claude-bypass` 相当を当該 machine の shell profile に置く
5. machine 固有差分の置き場: project 差分 = `<project>/.claude/settings.local.json` / machine 全体の env 系 = shell profile / user settings の恒久差分 = symlink の実ファイル化（`bootstrap.sh --check` が deviation を報告）。**`~/.claude/settings.local.json` は Claude Code に読まれないため使わない**
6. 削除 agent を参照する private 設定があれば更新。復元は `docs/archive/skills/` + git 履歴から可能

## レビュー対応履歴

### レビュー1 → v2（ATK-001〜015）

ATK-001 parser 復帰 + e2e / ATK-002 sonnet+medium / ATK-003 単一 owner 化 / ATK-005 learnings 遅延化 / ATK-008 auditor 分離 / ATK-009 allowed-tools 統一 + schema 検査 / ATK-012 baseline 証跡 / ATK-013 stale 参照修正 + check 10 / ATK-014 checksum 照合 / ATK-015 git archive 配布（再レビューで CLOSED 判定）。ATK-010 は承認済み例外。

### 再レビュー → v3（残存 4 件 + H-001〜005）

| ID | v3 対応 |
|---|---|
| ATK-004 | 共有既定から bypassPermissions を除去（waiver 行も削除）。`failIfUnavailable: true` で fail-open を排除。`sandbox.credentials.files` で credential read を deny。bypass は環境検証ゲート付き `claude-bypass` launcher（machine-local marker + WSL2 + 非 root を毎回実行時検証、fail-closed）に隔離し、6 ケースのテストを追加 |
| ATK-006 | `~/.claude/settings.local.json`（非 documented scope）への参照を README / CLAUDE.md / classification.md から全廃し、documented scope（user / project / project local）と正しい置き場を明記。Agent Teams opt-in は shell 環境変数へ。settings-syntax.md を「permission rules はマージ・他はスカラー置換」の公式仕様に修正 |
| ATK-007 | measure-metrics.sh を before/after 比較対応（--before-ref/--after-ref、改名前後の両 layout 認識、find ベースで .git 不要）に書き換え。**tier alias を 14→9 に訂正**。重複原則は greppable 3 組を script 判定 + 2 組を手動評価と明記。fixture 期待値テスト（test-measure-metrics.sh）を追加 |
| ATK-011 | 優先順位 5 段を CLAUDE.md に明文化。resolver（private-routing-locate）を追加して消費契約を実行可能にし、契約 5 項目 + 欠落 fixture + dummy mapping resolver 選択のテストを追加。XDG fallback の tilde 展開バグを修正 |
| H-001 | validator check 8 の full-model-pin 検査を agent frontmatter（`model: claude-*`）と TOML（`model = "claude-*"`）へ拡張し、fixture テストを追加 |
| H-002 | patch 適用方法（`git am`）を本レポート運用上の注意 2 に明記 |
| H-003 | baseline 証跡を「要約証跡で受入」とする明示例外を Baseline 節に記録 |
| H-004 | test-gh-start-contract の実体（runtime smoke + 静的契約検査）へ記述を訂正 |
| H-005 | 本レポートを v3 として全面改訂し、settings・metrics・テスト名の記述を source of truth と一致させた |
