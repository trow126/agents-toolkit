# agents-toolkit 近代化（2026-07-23）

2026 年時点の主要コーディングエージェント（Claude Code 2.1.x / Codex CLI）と Agent Skills 公式仕様に合わせた近代化。目的は (1) 継ぎ足された機構の証拠に基づく約 30% 縮約、(2) 手動起動型の革新探索 skill（`break-consensus`）の追加。

**改訂履歴**: v1（初回実装）→ レビュー1（ATK-001〜015）→ v2 → 再レビュー（ATK-004/006/007/011・H-001〜005）→ v3 → 統合再レビュー（REQUEST_CHANGES: H-007・ATK-004・H-006・H-001・ATK-006・H-008）→ v4 → 統合再レビュー2（REQUEST_CHANGES: H-009・H-007・ATK-004・H-011・H-001・H-010・ATK-006・ATK-007）→ **v5（本版。要件所有者の決定により bypass launcher を廃止し、残件を全件反映）**。対応内訳は末尾「レビュー対応履歴」。

## Baseline（変更前の検証記録）

- 変更前 commit: `baseline: pristine agents-toolkit-master from zip`
- **証跡**: [docs/reports/baseline-2026-07-23.txt](../reports/baseline-2026-07-23.txt)（SHA-256: `7ec80713c1b631a5add4b03f4f4acd12bbe77f0b24dd896e3f39e94c94e27a58`）
- 証跡の範囲に関する明示例外（H-003）: baseline 証跡は「実行コマンド・環境・exit code・各テスト末尾 3 行」の**要約証跡として受入**とする。全 stdout/stderr が必要な調査では、baseline commit を checkout して同コマンドを再実行する（テストは冪等・自己完結）
- 検証環境: Claude Code 2.1.218 / node v22 / Codex CLI 未導入（Codex 側は公式ドキュメントでのみ検証）

## 計測（before → after）

**再現手順（1 コマンド）**: `scripts/measure-metrics.sh --before-ref <baseline-commit> --after-ref HEAD`（改名前 `gh:start` / 改名後 `gh-start` 両 layout を自動認識。単一 tree は `--repo <dir>`。期待値テスト: `tests/test-measure-metrics.sh`）。以下の表は同スクリプトの実測値（バイト数 = `wc -c`、推定トークンの代理指標）。

| 指標（script の出力 key） | before | after | 削減 |
|---|---|---|---|
| combined_always_on_total | 43,068 | 32,637 | **−24.2%** |
| 　codex_agents_md_bytes | 23,116 | 15,271 | **−33.9%** |
| 　claude_always_on_total | 19,952 | 17,366¹ | −13.0% |
| custom_agents | 14 | 9 | **−36%** |
| claude_skills | 21 | 13 | **−38%** |
| codex_skills | 4 | 5² | +1 |
| hook_scripts / hook_registrations | 9 / 9 | 7 / 8 | −22% / −11% |
| shared_rules + claude_rules | 16 + 7 | 13 + 5 | −22% |
| full_model_pins（settings + agent frontmatter + TOML） | 1 | **0** | −100% |
| tier_aliases（agent frontmatter。pin と別指標） | **14** | 9 | −36% |
| unconditional_delegation_gh_start | 1 | **0** | −100% |
| always_on_learnings_paths | 2 | **0** | −100% |
| duplicated_principles_greppable（script 判定 3 シグネチャ） | 3 | **0** | −100% |
| 同・手動評価分³ | 2 | 0 | −100% |

削減率の丸め: 小数 1 桁（四捨五入）。after 値の機械照合用ブロック（`tests/test-report-consistency.sh` が `measure-metrics.sh --repo .` と verbatim 照合し、stale なら CI が失敗する — ATK-007）:

<!-- BEGIN metrics:after -->
```
claude_md_bytes: 4380
claude_always_rules_bytes: 2132
claude_always_on_total: 17366
codex_agents_md_bytes: 15271
combined_always_on_total: 32637
custom_agents: 9
claude_skills: 13
codex_skills: 5
hook_scripts: 7
hook_registrations: 8
shared_rules: 13
claude_rules: 5
full_model_pins: 0
tier_aliases: 9
unconditional_delegation_gh_start: 0
always_on_learnings_paths: 0
```
<!-- END metrics:after -->

¹ v3-v5 で private routing 契約・permission 方針の明文化により CLAUDE.md は 4,380 bytes（v1 の 2,909 から増）。削減は rules 統合・import 削減・learnings 遅延化による。² python-quality は AGENTS.md からの移設（3.6 の承認済み例外）。³ grep で機械判定できない 2 組 = YAGNI の意味重複と git 安全（rule 文 vs settings deny）。統合・削除済みだが判定は手動評価であることを明記する。

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
| 8 | documented scope に user-level `settings.local.json` は**存在しない**（user は `~/.claude/settings.json`、local は `<project>/.claude/settings.local.json`）。マージ規則は scalar override / **array-valued settings は一般に連結・重複排除**（v4 で行 14 に精緻化。当初の「permission のみマージ」という要約は v4 で訂正済み） | code.claude.com/docs/en/settings | 誤った scope 記述を全修正（README / rules / classification） | 高 |
| 9 | model alias: sonnet = daily coding、低 effort = 低コスト | code.claude.com/docs/en/model-config | 共有既定 `sonnet` + `medium` | 高 |
| 10 | Codex user skills は `~/.agents/skills`、AGENTS.md 連結 32KiB 上限 | developers.openai.com/codex/* | python-quality を同所へ、AGENTS.md 15.3KB | 高 |
| 11 | 発想均質化・novelty 監査・実験変換の実証研究 | break-consensus references/evidence.md | Stage 設計根拠 | 高 |
| 12 | bare `Read`/`Edit`/`WebFetch` は全対象に match。`Bash(git *)` は push も match。ask rule は bypassPermissions 中も prompt を強制。`--dangerously-skip-permissions` 相当のセッションは container/VM/sandbox-runtime 内で起動すべき | code.claude.com/docs/en/permissions, /permission-modes, /sandbox-environments | H-007 の permission 全面縮小 + ask gate。bypass は srt 隔離必須化 | 高 |
| 13 | `@anthropic-ai/sandbox-runtime`（srt）は Claude Code プロセス全体（tools・MCP・hooks）を隔離。`srt [--settings file] <command>`、設定は network.allowedDomains / filesystem.{denyRead,allowWrite} 等。beta research preview | code.claude.com/docs/en/sandbox-environments + sandbox-runtime README | claude-bypass の隔離 runtime に採用（設定 template 同梱） | 高 |
| 14 | settings の array-valued settings は一般にスコープ間で連結・重複排除（permissions に限らず sandbox filesystem/credentials/network arrays も）。scalar は高優先 override | code.claude.com/docs/en/settings, /sandboxing | settings-syntax.md を修正（ATK-006） | 高 |

未検証事項: (a) TodoWrite→TaskCreate の公式移行文書（確信度 85%）。(b) Codex plugin `approval_mode` 記法（ユーザー実設定の注記として維持）。(c) issue #16180 の現況。(d) sandbox fail-closed 構成の WSL2 実機動作（bubblewrap/socat 導入が前提。README に導入手順を明記）。

## 縮約の実施内容（Phase 3、v5 時点の最終状態）

### 3.1 常時コンテキスト

- CLAUDE.md: モデル固定表・常時委任規定を撤去し「最小コスト単一 owner」原則へ。learnings の常時 import 廃止（必要時参照 + `/knowledge-audit` 遅延同期）
- claude/rules: workflow.md / workspace.md を統合削除。settings-syntax.md は公式の scope・マージ仕様に合わせて全面修正
- codex/AGENTS.md: python-guidelines / issue-completeness / learnings を遅延化。−33.9%

### 3.2 実行時既定値と permission policy（ATK-002/004/006・H-006/007 最終形）

`claude/settings.json`（source of truth と本節は一致する）:

- `model: "sonnet"` / `effortLevel: "medium"`（full model pin 0。validator と metrics は**対応構文を限定した共有 scanner**（canonical block-style frontmatter + JSON + tomllib TOML。quoted/literal 値対応）で横断検査し、**非対応構文・decode 不能は明示エラーで fail-closed**（黙って 0 件と報告しない — H-001） ）
- `permissions.defaultMode: "default"`（無条件 bypass なし）
- **permissions.allow（H-007/H-011 対応で最終縮小）**: bare tool・`Bash(git|gh|curl *)` に加え、v5 で **runner wildcard（`npm *`/`pnpm *`/`bun *`/`uv run *`/env 系）と破壊的 git subcommand（checkout/switch/branch/stash/worktree/pull）の allow も全廃**。残る allow は read-only git/gh・`git add`/`git commit`（amend 除く）・narrow runner（`npm run test|lint|build`、`uv run pytest|ruff|mypy`）・安全な unix utility・workspace 限定 `Read(**)`/`Edit(**)`（**`Write(**)` は現行仕様で match しない path rule のため撤去し、file-edit policy は `Edit(**)` に一本化 — H-010**）・ドメイン限定 WebFetch。allow 外のコマンドは sandbox auto-allow（sandbox 内・workspace 限定）で走る
- **permissions.ask（55 rule）**: 外部副作用（`git push`・`gh pr|issue|release|repo|api|workflow` の変更系・`curl`・registry mutation `npm publish|unpublish|deprecate|owner|access|dist-tag|token|login`）+ **任意 package 実行（`npx`/`npm exec`/`npm x`/`pnpm dlx`/`bunx`）** + **破壊的 git 操作（`checkout`/`switch`/`stash`/`worktree`/`pull`/`rebase`/`commit --amend`/`branch -D|-d|-m|-M|--delete|--force`）**。deny > ask > allow のため sandbox auto-allow 中も明示 prompt を強制する
- `sandbox`: `enabled: true` / `failIfUnavailable: true`（fail-closed） / `allowUnsandboxedCommands: false` / `credentials.files` で `~/.ssh` 等 8 path の read deny / **`credentials.envVars` で GITHUB_TOKEN・GH_TOKEN・NPM_TOKEN・ANTHROPIC_API_KEY・AWS_* 等 9 変数を sandboxed subprocess から deny** / `network.allowedDomains` で sandboxed Bash の egress を 6 domain に限定
- Agent Teams 環境変数なし（opt-in は shell profile の `export`）
- 危険設定・broad allow を共有既定へ戻す場合は waiver 必須。**waiver 自体も schema 検査**（5 列非空・実在日・`docs/waivers/environments.txt` の承認済み environment のみ。不正行は未使用でも FAIL — H-008）

**bypassPermissions の扱い（v5 = launcher 廃止）**: v4 の srt launcher に対し、統合再レビュー2 は (a) srt 実行体の bootstrap trust（PATH/npx 解決・version 未固定 — H-009）、(b) srt profile の境界の広さ（home read・`~/.claude` write・GitHub/npm/PyPI egress — ATK-004）を BLOCKING と判定した。完全対応には固定版 srt の検証付き配布・一時 HOME・credential broker・実 WSL2 での live adversarial integration test が必要で、個人 dotfiles で維持するのは過剰と判断し、**要件所有者の決定（2026-07-23）で launcher・profile・template・専用テストを全て削除**した。共有設定に `disableBypassPermissionsMode: "disable"`（レビュー推奨の安全側既定）を追加し、validator の stale-reference 検査へ bypass 関連名を登録して再導入を検出する。**H-009 と ATK-004 は対象機構の廃止により解消**。低プロンプト運用は sandbox auto-allow + workspace 限定 allow が担い（日常 Bash・編集は prompt なし）、prompt は外部副作用・破壊的操作の ask のみ。bypass が不可欠な作業は公式 dev container（default-deny firewall 付き）等の隔離環境で行う。

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

## 検証（v5 時点）

- shell 構文（bash -n 全 .sh）/ JSON（jq）: PASS
- `scripts/validate-layout.sh`（10 検査。構造的 pin scan・broad-allow 検査・waiver schema 検査を含む。WARN 0 件）: PASS
- `sync-shared-rules.sh --check`: OK
- `tests/test-*.sh` **10 本**（bypass テスト削除・report-consistency テスト追加）: PASS（negative fixture: quoted YAML・literal TOML pin / quoted-key・invalid-UTF-8 の scanner fail-closed / runner wildcard・unsupported path rule / broad allow / waiver schema 4 種 / stale report 数値 をすべて拒否することを含む）
- `python-refactor-analysis` pytest: 20 passed
- bootstrap e2e（clean HOME、test-gh-start-contract 内）: PASS
- `scripts/package-release.sh --check`: PASS
- `scripts/measure-metrics.sh --before-ref <baseline> --after-ref HEAD`: 本レポートの表と一致

## 運用上の注意（breaking changes / 導入手順）

1. スラッシュコマンド改名: `/gh:pr` → `/gh-pr` 等
2. **patch の適用は `git am` を使う**（H-002）: `git am agents-toolkit-modernization-final.patch`。mailbox 形式の複数 commit series のため、`git apply` は rename を跨ぐ 2 通目以降で失敗する（正常動作）。単一 diff が必要なら `git diff <baseline>..HEAD` を生成する
3. **settings 既定値**: sonnet / medium / defaultMode default / sandbox fail-closed。Linux・WSL2 では `sudo apt-get install bubblewrap socat` が必要（未導入だと起動拒否 = 仕様どおりの fail-closed）
4. **低プロンプト運用（bypass なし）**: bypassPermissions は共有設定で無効（v5 決定）。日常の Bash は sandbox auto-allow で prompt なし、project 内の読み書きは `Read(**)`/`Edit(**)` で prompt なし。prompt が出るのは外部副作用（push・PR/issue 作成・`gh api`・`curl`・registry 操作・`npx` 等）と破壊的 git 操作の ask のみ。特定の ask を恒常的に allow へ移す場合は意図の記録を伴う（waiver 相当のコミット履歴）。無人運用が必要な場合は公式 devcontainer 等の隔離環境を使う
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
| H-001 | validator check 8 の full-model-pin 検査を agent frontmatter と TOML へ拡張し、fixture テストを追加（v4 で構造的 scanner に置換） |
| H-002 | patch 適用方法（`git am`）を本レポート運用上の注意 2 に明記 |
| H-003 | baseline 証跡を「要約証跡で受入」とする明示例外を Baseline 節に記録 |
| H-004 | test-gh-start-contract の実体（runtime smoke + 静的契約検査）へ記述を訂正 |
| H-005 | 本レポートを v3 として全面改訂し、settings・metrics・テスト名の記述を source of truth と一致させた |

### 統合再レビュー → v4（H-007・ATK-004・H-006・H-001・ATK-006・H-008）

| ID | v4 対応 |
|---|---|
| H-007 | permissions.allow を全面縮小: bare file/web tool と `Bash(git\|gh\|curl *)` を全廃し、workspace 限定 `Read(**)`/`Edit(**)`/`Write(**)`・read-only/local subcommand の個別 allow・ドメイン限定 WebFetch へ。外部副作用 25 種を ask 化（bypass 中も prompt 強制）。`sandbox.credentials.envVars`（9 secret 変数 deny）と `sandbox.network.allowedDomains` を追加。validator に broad-allow 検査 + negative fixture を追加 |
| ATK-004 | claude-bypass を srt（sandbox-runtime）による**全プロセス隔離起動**に変更（tools・MCP・hooks を同一 OS 境界へ）。srt 不在・設定不在は起動拒否。claude へ CLI `--settings` で固定 profile（sandbox pin + ask gate）を注入し、project/local からの境界解除を防止。srt 設定 template（credential denyRead・network allowlist・最小 allowWrite）を同梱 |
| H-006 | WSL 判定を `microsoft-standard` 署名に厳格化し WSL1 を明示拒否。環境変数 seam（AGENTS_TOOLKIT_BYPASS_*）を production から全廃し、検証ロジックを `lib/bypass-gate.sh` へ分離（テストは dependency injection）。marker を umask 077（600）+ schema=1 + 期限 180 日で作成し、使用時に所有者・権限・schema・期限を検査。WSL1/spoof/root/tampered marker の negative test を追加 |
| H-001 | model pin/alias 検査を構造的 scanner（`scripts/lib/scan-model-pins.py`: YAML frontmatter・JSON・tomllib による TOML parse + quote/comment 正規化）へ統一し、validator と measure-metrics で共有。quoted YAML・literal TOML の fixture を両テストに追加 |
| ATK-006 | settings-syntax.md を「scalar override / array-valued settings は一般に連結・重複排除」へ修正（v5 でレポート内の旧「permission のみマージ」記述も全箇所訂正） |
| H-008 | waiver TSV の schema 検査を validator に追加: 5 列非空・実在日（YYYY-MM-DD の正規化一致）・`docs/waivers/environments.txt` allowlist 内の environment のみ有効。不正行は未使用でも FAIL。列数不足・空 reason・不正日付・未承認 environment の negative fixture を追加 |

### 統合再レビュー2 → v5（H-009・H-007・ATK-004・H-011・H-001・H-010・ATK-006・ATK-007）

| ID | v5 対応 |
|---|---|
| H-009 / ATK-004 | **bypass launcher の廃止**（要件所有者決定）。claude-bypass・bypass-gate・bypass-profile・srt template・専用テストを削除し、`disableBypassPermissionsMode: "disable"` を共有既定に追加。stale-reference 検査に bypass 関連名を登録。両指摘は対象機構の廃止により解消（bypass が必要な作業は公式 devcontainer 等の隔離環境へ） |
| H-007 | runner wildcard（`npm *`/`pnpm *`/`bun *`/`uv run *`/env 系）を allow から全廃し、narrow runner（`npm run test|lint|build`・`uv run pytest|ruff|mypy`）のみ allow。任意 package 実行（npx/npm exec/npm x/pnpm dlx/bunx）と registry mutation（unpublish/deprecate/owner/access/dist-tag/token/login/adduser）を ask 化。validator の broad-allow 検査を runner wildcard へ拡張し negative fixture を追加 |
| H-011 | 破壊的 local git（checkout/switch/stash/worktree/pull/rebase/`commit --amend`/`branch -D|-d|-m|-M|--delete|--force`）を allow から撤去し ask 化（sandbox auto-allow 中も prompt 強制）。allow に残る git は read-only + add/commit のみ |
| H-001 | scanner を「対応構文を限定した parser」と明示し、非対応構文（quoted key・flow mapping）・invalid UTF-8 を**明示エラーで非ゼロ終了**に変更。measure-metrics の `2>/dev/null || true` を撤去し scanner 失敗で全体を fail-closed（0 件出力しない）。quoted-key/flow/invalid-UTF-8 の negative fixture を validator・metrics 両テストへ追加 |
| H-010 | `Write(**)` を削除（現行仕様で file permission check に match する path rule は Read/Edit のみ）。file-edit policy は `Edit(**)` に一本化し、validator に `Write(...)`/`NotebookEdit(...)`/`Glob(...)` path rule の拒否検査 + fixture を追加 |
| ATK-006 | レポート内に残っていた旧「permission のみマージ」記述（evidence 行・v3 履歴）を全箇所「scalar override / array 連結・重複排除」へ訂正し、履歴には v4 訂正済みと明記 |
| ATK-007 | after 計測値を最終 HEAD で再計測して表を更新（combined 32,637 / claude 17,366 / claude_md 4,380、丸め規則明記）。レポートに machine-readable な metrics:after ブロックを埋め込み、`tests/test-report-consistency.sh` が実測と verbatim 照合（stale なら CI 失敗。stale fixture の self-check 付き） |
