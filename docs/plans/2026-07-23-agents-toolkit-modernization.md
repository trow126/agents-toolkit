# agents-toolkit 近代化（2026-07-23）

2026 年時点の主要コーディングエージェント（Claude Code 2.1.x / Codex CLI）と Agent Skills 公式仕様に合わせた近代化。目的は (1) 継ぎ足された機構の証拠に基づく約 30% 縮約、(2) 手動起動型の革新探索 skill（`break-consensus`）の追加。

**改訂履歴**: v1（初回実装）→ レビュー1（ATK-001〜015）→ v2 → 再レビュー（ATK-004/006/007/011・H-001〜005）→ v3 → 統合再レビュー（REQUEST_CHANGES: H-007・ATK-004・H-006・H-001・ATK-006・H-008）→ v4 → 統合再レビュー2（REQUEST_CHANGES: H-009・H-007・ATK-004・H-011・H-001・H-010・ATK-006・ATK-007）→ v5 → 統合再レビュー3（REQUEST_CHANGES: H-012・H-013・H-007・H-011・H-014・H-015・H-016・H-017）→ v6 → 統合再レビュー4（REQUEST_CHANGES: H-018・H-019・H-007・H-011・H-014・H-013・H-016・H-017 — 合成後の実効ポリシー検査）→ v7 → 適合性レビュー（REQUEST_CHANGES: B-01・C-01・H-01・H-02・M-01・M-02・M-03 — 要件適合と unsandboxed egress）→ **v8（本版。static に検証可能な全指摘を実装反映。live 実機項目は未検証事項、要件書の完全版照合 B-01 は所有者提示待ち）**。対応内訳は末尾「レビュー対応履歴」。**本文は現在状態（current state）を記述し、過去版の設計は「レビュー対応履歴」に SUPERSEDED として残す。**

## Baseline（変更前の検証記録）

- 変更前 commit: `baseline: pristine agents-toolkit-master from zip`
- **証跡**: [docs/reports/baseline-2026-07-23.txt](../reports/baseline-2026-07-23.txt)（SHA-256: `7ec80713c1b631a5add4b03f4f4acd12bbe77f0b24dd896e3f39e94c94e27a58`）
- 証跡の範囲に関する明示例外（H-003）: baseline 証跡は「実行コマンド・環境・exit code・各テスト末尾 3 行」の**要約証跡として受入**とする。全 stdout/stderr が必要な調査では、baseline commit を checkout して同コマンドを再実行する（テストは冪等・自己完結）
- 検証環境: Claude Code 2.1.218 / node v22 / Codex CLI 未導入（Codex 側は公式ドキュメントでのみ検証）

## 計測（before → after）

**再現手順（1 コマンド）**: `scripts/measure-metrics.sh --before-ref <baseline-commit> --after-ref HEAD`（改名前 `gh:start` / 改名後 `gh-start` 両 layout を自動認識。単一 tree は `--repo <dir>`。期待値テスト: `tests/test-measure-metrics.sh`）。以下の表は同スクリプトの実測値（バイト数 = `wc -c`、推定トークンの代理指標）。

| 指標（script の出力 key） | before | after | 削減 |
|---|---|---|---|
| combined_always_on_total | 43,068 | 33,934 | **−21.2%** |
| 　codex_agents_md_bytes / lines | 23,116 / 375 | 15,271 / 208 | **−33.9% / −45%** |
| 　claude_always_on_total | 19,952 | 18,663¹ | −6.5% |
| 　claude_md_lines（root CLAUDE.md 行数） | 59 | 47 | −20% |
| 　claude_always_rules_lines（常時 rules 合計行数） | 68 | 32 | −53% |
| custom_agents | 14 | 9 | **−36%** |
| claude_skills | 21 | 13 | **−38%** |
| codex_skills | 4 | 5² | +1 |
| hook_scripts / hook_registrations | 9 / 9 | 7 / 8 | −22% / −11% |
| shared_rules + claude_rules | 16 + 7 | 13 + 5 | −22% |
| output_styles（PDF 3.6: 明示選択時のみ・keep） | 4 | 4 | ±0 |
| full_model_pins | 1 | **0** | −100% |
| tier_aliases（agent frontmatter。pin と別指標） | **14** | 9 | −36% |
| unconditional_delegation_gh_start | 1 | **0** | −100% |
| always_on_learnings_paths | 2 | **0** | −100% |
| progress/review/retrospective 機構（skill 3 + hook 2。inventory-matrix §6） | 5 | **0** | −100% |
| custom↔built-in agent 重複（同上） | 2 | **0** | −100% |
| duplicated_principles_greppable（script 判定 3 シグネチャ） | 3 | **0** | −100% |
| 同・手動評価分³ | 2 | 0 | −100% |

削減率の丸め: 小数 1 桁（四捨五入）。after 値と permission policy の機械照合用ブロック（`tests/test-report-consistency.sh` が `measure-metrics.sh --repo .` と verbatim 照合し、stale なら CI が失敗する — ATK-007/H-016。**permission 件数と bypass lockout もここが正**）:

<!-- BEGIN metrics:after -->
```
claude_md_bytes: 4995
claude_md_lines: 47
claude_always_rules_bytes: 2814
claude_always_rules_lines: 32
claude_always_on_total: 18663
codex_agents_md_bytes: 15271
codex_agents_md_lines: 208
combined_always_on_total: 33934
custom_agents: 9
claude_skills: 13
codex_skills: 5
hook_scripts: 7
hook_registrations: 8
shared_rules: 13
claude_rules: 5
output_styles: 4
full_model_pins: 0
tier_aliases: 9
permissions_allow_count: 38
permissions_ask_count: 66
permissions_deny_count: 87
bypass_lockout_ok: yes
effective_preallowed_domains_count: 0
unsandboxed_query_capable_allows: 0
auto_memory_enabled: yes
unconditional_delegation_gh_start: 0
always_on_learnings_paths: 0
```
<!-- END metrics:after -->

¹ v3-v8 で private routing 契約・permission/sandbox 方針・sandbox/uv/gh 運用制約の明文化により CLAUDE.md は 4,995 bytes（v1 の 2,909 から増）。レビュー主導の安全契約文書化を優先し、縮約は rules 統合・import 削減・learnings 遅延化で確保した（combined −21.2% は「約 30% は方向性・数合わせで価値ある機構を削らない」の範囲内と判断。適合性レビューも同解釈で単独不合格理由としないと判定）。なお常時コンテキストには本表の static 計測に加え native auto memory が session 単位で加算され得る（EX-002。導入直後 0・実測は実機項目）。² python-quality は AGENTS.md からの移設（3.6 の承認済み例外）。³ 手動評価 2 組の内訳は v2 と同じ。

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
| 7 | `bypassPermissions` は prompt injection 保護なし。`failIfUnavailable: false` は**警告後に unsandboxed 実行**（fail-open）、`true` は起動拒否（fail-closed）。`sandbox.credentials.files` の deny が公式（v2.1.187+）。既定 read policy は credential file を読める | code.claude.com/docs/en/sandboxing, /permission-modes | 共有既定を default + failIfUnavailable: true + credentials deny へ（**launcher 隔離の記述は SUPERSEDED — v5 で launcher 廃止**） | 高 |
| 8 | documented scope に user-level `settings.local.json` は**存在しない**（user は `~/.claude/settings.json`、local は `<project>/.claude/settings.local.json`）。マージ規則は scalar override / **array-valued settings は一般に連結・重複排除**（v4 で行 14 に精緻化。当初の「permission のみマージ」という要約は v4 で訂正済み） | code.claude.com/docs/en/settings | 誤った scope 記述を全修正（README / rules / classification） | 高 |
| 9 | model alias: sonnet = daily coding、低 effort = 低コスト | code.claude.com/docs/en/model-config | 共有既定 `sonnet` + `medium` | 高 |
| 10 | Codex user skills は `~/.agents/skills`、AGENTS.md 連結 32KiB 上限 | developers.openai.com/codex/* | python-quality を同所へ、AGENTS.md 15.3KB | 高 |
| 11 | 発想均質化・novelty 監査・実験変換の実証研究 | break-consensus references/evidence.md | Stage 設計根拠 | 高 |
| 12 | bare `Read`/`Edit`/`WebFetch` は全対象に match。`Bash(git *)` は push も match。ask rule は bypassPermissions 中も prompt を強制。`--dangerously-skip-permissions` 相当のセッションは container/VM/sandbox-runtime 内で起動すべき | code.claude.com/docs/en/permissions, /permission-modes, /sandbox-environments | H-007 の permission 全面縮小 + ask gate（**srt 隔離必須化は SUPERSEDED — v5 で launcher 廃止し bypass 自体を lockout**） | 高 |
| 13 | `@anthropic-ai/sandbox-runtime`（srt）は Claude Code プロセス全体（tools・MCP・hooks）を隔離。`srt [--settings file] <command>`、設定は network.allowedDomains / filesystem.{denyRead,allowWrite} 等。beta research preview | code.claude.com/docs/en/sandbox-environments + sandbox-runtime README | **SUPERSEDED**: v4 で採用したが v5 で launcher ごと廃止（歴史的記録として保持） | 高 |
| 14 | settings の array-valued settings は一般にスコープ間で連結・重複排除（permissions に限らず sandbox filesystem/credentials/network arrays も）。scalar は高優先 override | code.claude.com/docs/en/settings, /sandboxing | settings-syntax.md を修正（ATK-006） | 高 |

未検証事項（すべて実機依存。`scripts/check-runtime.sh`（bootstrap --check/--apply が自動実行）+ README の手動チェックリストで補完）: (a) TodoWrite→TaskCreate の公式移行文書（確信度 85%）。(b) Codex plugin `approval_mode` 記法。(c) **live Claude Code での lockout 実挙動**（`--permission-mode bypassPermissions` の拒否・startup warning 0 件）。(d) **WSL2 実機での sandbox denyRead/egress の OS-level 強制**。(e) **実 sandbox 内の workflow 統合検証**: `git add`/通常 `git commit` の成功（.git 狭域 deny との共存）・**allowRead 経由の helper 起動（`~/.claude/bin/uvw run --frozen pytest -q`・`~/.claude/bin/private-routing-locate` — H-01 smoke）**・`Read(//**/.env)` deny の OS-level 遮断（literal 以外の動的 path 構築を含む）・全 domain の初回 prompt（child process の egress 含む）・**gh read 系の ask prompt 動作（C-01）**。(f) **auto memory の session 開始時注入量の実測**（EX-002。導入直後は 0）。(g) **Codex CLI 実機 smoke**（`approval_mode` 記法の確定を含む）。(c)-(g) は本環境（Claude Code sandbox 実行不可・非 WSL2・Codex 未導入）では検証不能のため、導入時に実機で確認する（適合性レビュー受入条件 8・9 / final_4 §9 に対応）。

## 縮約の実施内容（Phase 3、v7 時点の最終状態）

### 3.1 常時コンテキスト

- CLAUDE.md: モデル固定表・常時委任規定を撤去し「最小コスト単一 owner」原則へ。learnings の常時 import 廃止（必要時参照 + `/knowledge-audit` 遅延同期）
- claude/rules: workflow.md / workspace.md を統合削除。settings-syntax.md は公式の scope・マージ仕様に合わせて全面修正
- codex/AGENTS.md: python-guidelines / issue-completeness / learnings を遅延化。−33.9%

### 3.2 実行時既定値と permission / sandbox policy（v7 最終形。source of truth と一致）

前提となる合成 semantics（final_4 レビューで検証。公式 sandboxing docs）: **`Read()`/`Edit()` の deny path は sandbox filesystem へ統合され OS-level で child process にも適用される**。**`WebFetch(domain:...)` allow は sandbox Bash の network domain も pre-allow する**。個別 rule ではなくこの合成後の実効ポリシーを validator と metrics block が恒久検査する。

- `model: "sonnet"` / `effortLevel: "medium"`。model pin/alias は共有 scanner（**対応構文限定 parser** — 非対応構文・decode 不能は明示エラーで fail-closed）で検査
- **bypass lockout（H-012）**: `permissions.disableBypassPermissionsMode: "disable"` を **documented path（permissions 配下）** に配置。旧 root 配置と非公式 root キー（`skipAutoPermissionPrompt` 等）は撤去。validator が「permissions 配下・値 disable・root 誤配置なし」を構造検査し、欠落/誤配置/誤値の negative fixture 付き
- **permissions.allow（38 rule）**: read-only git・`git add`/`git commit`・`~/.claude/bin/uvw run pytest|ruff|mypy`（sandbox 互換 uv wrapper — H-019）・安全 utility・workspace 限定 `Read(**)`/`Edit(**)`・WebSearch。**`WebFetch(domain:)` allow はゼロ**（network pre-allow に連動するため — H-007）。**素の `uv run` allow もゼロ**（validator が拒否）。**`gh` の allow は固定 argv の `gh auth status` のみ**（audited exact list。excludedCommands の gh は sandbox domain prompt を経ないため、query・引数を運べる形は read 系含め allow しない — 適合性レビュー C-01。validator が excludedCommands∩allow を恒久検査し、metrics `unsandboxed_query_capable_allows: 0` で機械照合）
- **permissions.ask（66 rule）**: 外部副作用（push・PR/issue/release/repo/api/workflow・curl・registry mutation）・**gh の read 系全般（search/issue list|view/pr list|view|diff|checks/repo view/run list|view — 任意 query・引数の外部送信を承認で gate）**・任意 package 実行（npx/npm exec/pnpm dlx/bunx）・破壊的 git（checkout/switch/stash/worktree/pull/rebase/branch -D 等）・**permission 前置迂回になり得る形（`git -c*`・`git -C*`・`git --git-dir*`・`git --work-tree*`・`git config` — H-011）**
- **permissions.deny（87 rule）**: 従来の破壊的操作・credential read に加え、**`.git` は狭域保護**（`Edit(.git/config)`・`Edit(.git/hooks/**)` のみ。旧 `Edit(.git/**)` は sandbox 統合で `git add`/`git commit` の index.lock 書込を阻害するため撤去 — H-018。linked worktree の共有 `.git` も公式仕様が commit write を許可し hooks/config を deny）、**`.env` は machine 全域の OS-level read 境界**（`Read(//**/.env)`・`Read(//**/.env.*)` 等の絶対 path deny → sandbox 統合。動的 path 構築や sibling repo の secret も実アクセスで拒否 — H-014）、**shell 再評価の遮断**（既存 `bash *` に加え `sh *`・`zsh *`・`dash *`）
- **hook の位置づけ（H-011/H-014 再定義）**: `pre-bash-validate-hook` は **quote 正規化つき raw-string heuristic の「事故・平易迂回の防止層」であり security boundary ではない**（argv parser ではない — 旧記述を訂正）。fail-closed（jq 欠落・malformed JSON・schema 不一致 = exit 2）。`git commit --amend` は「git 語と `--amend` token の共起」で deny し、final_4 の回避 7 形（command/variable substitution・quote 分割・git alias・nested shell）を全て block（fixture 付き）。literal が現れない runtime 構築（base64 復号等）は hook の対象外で、`.env` は OS 境界・history 保護は push の ask/deny が最終防衛（公開履歴が保護対象。local amend は reflog で復元可能）。テスト: `tests/test-pre-bash-hook.sh`（33 assertion。scope 明示テスト含む）
- **sandbox（H-013/H-01。read と write を区別）**: write = workspace + session temp（OS-level）。**read は既定 host-wide のため** `filesystem.denyRead` で `~/.config`・`~/.local/state|share`・`~/.cache`・`~/.claude`・`~/.claude.json`・`~/.codex`・`~/.agents` を deny + `credentials.files` 8 path + `credentials.envVars` 9 変数。deny tree のうち sandbox 内実行に必要な subtree のみ `allowRead` で狭く再開（`~/.claude/bin`・`~/.claude/skills`・`~/.config/agents-toolkit` — helper/skill script/private routing 消費 path。settings 本体・session 履歴は deny のまま。validator が deny↔allowRead の整合を presence contract で検査 — 適合性レビュー H-01）。**custom XDG は fail-closed で非対応**（denyRead は literal path のため。`scripts/check-runtime.sh` が bootstrap --check/--apply で XDG 既定値を検査し、逸脱は明示エラー。受容は `--accept-custom-xdg` + waiver 記録 + denyRead への絶対 path 追加）。workspace-only read が必要な project は同梱 template を project 設定へ（user 設定の `.` は ~/.claude に解決されるため project 側にのみ置ける — 公式 recipe）
- **uv の sandbox 互換（H-019）**: uv の既定 cache/data/config（`~/.cache/uv`・`~/.local/share/uv`・`~/.config/uv`）は write 境界外かつ denyRead 下のため、**`~/.claude/bin/uvw`** が可変 state（UV_CACHE_DIR / UV_PYTHON_INSTALL_DIR / UV_TOOL_DIR / XDG_CONFIG_HOME）を session temp（sandbox 内 `$TMPDIR`）へ固定して exec する。**denyRead は緩和しない**。rules/skills/テスト手順は uvw 経由へ統一（skill 同梱 script・Makefile は portability のため同一前処理を vendoring。CI 等 sandbox 外は素の uv で可）。テスト: `tests/test-uvw.sh`
- **network egress（H-007 最終形）**: **effective pre-allowed domain = 0 件**（`sandbox.network.allowedDomains` なし **かつ** `WebFetch(domain:)` allow なし。validator が和集合を計測し 0 件を強制、metrics block の `effective_preallowed_domains_count` で機械照合）。全 domain（github.com 含む）が session 内初回 prompt を経て、child process の外部送信も同様。broad domain 常時許可による domain-fronting/exfil 経路（公式 docs の警告）を残さない
- 危険設定・broad allow の再導入は waiver 必須（schema 検査付き）。**runtime 互換（H-017）**: `scripts/check-runtime.sh` を bootstrap --check/--apply が自動実行（claude 欠落のみ NOTE 続行）。検証済み下限 2.1.218 **stable**（prerelease は拒否・future major は NOTE）。user settings に version floor の documented key は存在しない（`minimumVersion` は settings 参照に無く、managed の `requiredMinimumVersion` は fail-open 設計）ため、この doctor が version gate である
- **auto memory（適合性レビュー M-01 — accepted exception EX-002）**: `autoMemoryEnabled: true` を維持する。learnings 常時 import（2 経路 → 0）の受け皿としての設計判断で、metrics に `auto_memory_enabled: yes` を明示計上する。注入量は machine 蓄積依存で static 計測不能（導入直後 0）のため実機チェックリスト項目とし、蓄積内容は agent 自身の知見（credential・private routing・runtime state の読込ではない）である旨を [docs/reports/accepted-exceptions.md](../reports/accepted-exceptions.md) に記録
- **監査証跡（適合性レビュー M-02/M-03/B-01）**: Phase 1 の 11 軸要素別監査は [docs/reports/inventory-matrix.md](../reports/inventory-matrix.md)、例外承認台帳は [docs/reports/accepted-exceptions.md](../reports/accepted-exceptions.md)（EX-001 skill 純増 / EX-002 auto memory）、要件書の versioned 転写と**原本切れの確定所見**（p.15 は Stage 5 冒頭 2 行で終了。実装 Stage 6–7 は §4.1 目的からの導出）は [docs/requirements/requirements-transcription-260722.md](../requirements/requirements-transcription-260722.md)

**bypassPermissions の経緯（履歴）**: v3 で waiver 付き共有既定 → v4 で srt launcher 隔離 → **v5 で launcher 廃止 + lockout（現在状態）**。詳細は「レビュー対応履歴」。

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

## 検証（v7 時点）

- shell 構文（bash -n 全 .sh）/ JSON（jq）: PASS
- `scripts/validate-layout.sh`（**11 検査**。構造的 pin scan・broad-allow 検査・waiver schema 検査・実効ポリシー検査（.git 全体 deny 拒否 / effective pre-allowed domain 0 件 / 素の uv allow 拒否 / .git 狭域・.env OS 境界の presence contract / **excludedCommands∩allow の unsandboxed egress 拒否（C-01） / denyRead↔allowRead の helper 整合（H-01） / 直接実行 script の executable bit（H-02）**）を含む。WARN 0 件）: PASS
- `sync-shared-rules.sh --check`: OK
- `tests/test-*.sh` **13 本**（CI と同じ直接実行方式 `"$t"` でも全 PASS — H-02）: PASS（negative fixture: lockout 欠落/誤配置/誤値 / no-space runner wildcard / quoted・literal pin / scanner fail-closed / broad allow / `Edit(.git/**)` deny / WebFetch 由来 pre-allow / 素の uv allow / presence contract 欠落 / **unsandboxed gh allow（audited list の誤検出なしを含む） / allowRead 欠落 / 非実行 test script** / waiver schema 4 種 / stale report 数値 / hook の malformed input・jq 欠落・nested .env・quote 分割・amend 回避 7 形 / doctor の下限未満・prerelease・custom XDG 拒否 をすべて検出することを含む）
- `python-refactor-analysis` pytest: 20 passed
- bootstrap e2e（clean HOME、test-gh-start-contract 内。doctor 統合込み）: PASS
- `scripts/package-release.sh --check`: PASS
- `scripts/measure-metrics.sh --before-ref <baseline> --after-ref HEAD`: 本レポートの表と一致

## 運用上の注意（breaking changes / 導入手順）

1. スラッシュコマンド改名: `/gh:pr` → `/gh-pr` 等
2. **patch の適用は `git am` を使う**（H-002）: `git am agents-toolkit-modernization-final.patch`。mailbox 形式の複数 commit series のため、`git apply` は rename を跨ぐ 2 通目以降で失敗する（正常動作）。単一 diff が必要なら `git diff <baseline>..HEAD` を生成する。**配布名の正**: 配布 artifact は常に固定名 `agents-toolkit-modernization-final.patch` / `agents-toolkit-modernized-final.zip` / `modernization-report-final.md` で、受領側の保存時 rename（`final_4` 等の連番付与）があり得る。同一性は本レポートではなく SHA-256 で照合する（H-016）
3. **settings 既定値**: sonnet / medium / defaultMode default / sandbox fail-closed。Linux・WSL2 では `sudo apt-get install bubblewrap socat` が必要（未導入だと起動拒否 = 仕様どおりの fail-closed）
4. **低プロンプト運用（bypass なし）**: bypassPermissions は共有設定で無効（v5 決定）。日常の Bash は sandbox auto-allow で prompt なし、project 内の読み書きは `Read(**)`/`Edit(**)` で prompt なし。prompt が出るのは外部副作用（push・PR/issue 作成・`gh api`・`curl`・registry 操作・`npx` 等）・破壊的 git 操作・`git -c*` 等の前置形の ask・**network domain の session 内初回**のみ（WebFetch 含め事前許可 domain ゼロのため、docs 参照等も初回 1 回 prompt される）。特定の ask を恒常的に allow へ移す場合は意図の記録を伴う（waiver 相当のコミット履歴）。無人運用が必要な場合は公式 devcontainer 等の隔離環境を使う
5. **sandbox 内の運用制約（v7/v8）**: uv は `~/.claude/bin/uvw` 経由（素の `uv run` は cache 初期化で失敗する）。`git config`（local）・`git init`・`git remote add` は `.git/config`・`.git/hooks` の deny により sandbox 内で失敗するため手動 shell で行う（`git add`/`git commit`/`git fetch` は影響なし）。`.env` 系 file（`.env.example` 含む）は machine 全域で read deny — 参照が必要なら `env.example` へ改名するか waiver を登録する。`git commit --amend` は hook が deny（手動操作）。commit message 等に literal `--amend` を含む git コマンドも over-block 側に倒して deny される（安全側の設計判断）。**`gh` は auth status 以外すべて prompt される**（read 系含む — C-01。gh-start/gh-review 等の skill 実行時は gh call ごとに承認が必要。頻用 pattern は prompt の「今後も許可」で session 内に記憶させる運用）
6. machine 固有差分の置き場: project 差分 = `<project>/.claude/settings.local.json` / machine 全体の env 系 = shell profile / user settings の恒久差分 = symlink の実ファイル化（`bootstrap.sh --check` が deviation を報告）。**`~/.claude/settings.local.json` は Claude Code に読まれないため使わない**。**custom XDG は非対応**（doctor が fail-closed で検出。受容は waiver + denyRead 絶対 path 追加 + `--accept-custom-xdg`）
7. 削除 agent を参照する private 設定があれば更新。復元は `docs/archive/skills/` + git 履歴から可能

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

### 統合再レビュー3 → v6（H-012〜H-017・H-007/H-011/ATK-004 再対応）

| ID | v6 対応 |
|---|---|
| H-012 | lockout を documented path（`permissions.disableBypassPermissionsMode`）へ移動し、非公式 root キー（`skipAutoPermissionPrompt`・root の disableAutoMode/disableBypassPermissionsMode）を撤去。validator に「permissions 配下・値 disable・root 誤配置なし」の構造検査 + 欠落/誤配置/誤値 fixture を追加。live 実機での拒否確認は未検証事項として明記 |
| H-013 / ATK-004 | sandbox read 境界を明示: `filesystem.denyRead` で private tree 8 系統を deny、`~/.config/gh` の一般 allowRead を撤去（gh は excludedCommands で sandbox 外 + permission gate）。workspace-only read の project template を同梱し、README/レポートを「write=workspace 限定・read=denyRead 方式」の正確な記述へ修正 |
| H-007 | no-space runner wildcard（`npm run test*` 等）を全廃 + validator 拒否検査。事前許可 egress domain を全廃し、child process の外部送信も sandbox の初回 domain prompt を経る構成へ（既知 domain への無承認 exfil chain を遮断） |
| H-011 | `git commit --amend` を hook の order 非依存 argv 判定で deterministic に deny（`-S --amend`・`git -c`/`-C` 前置 fixture 付き）。ask の string-prefix には依存しない |
| H-014 | pre-bash-validate-hook を fail-closed 化: jq 欠落・malformed JSON・command 欠落/空 = exit 2。`.env` 検査を path-aware 化（nested `config/.env`・wc/readlink/file 等の reader・redirection）。専用テスト（21 assertion）を追加し CI 実行 |
| H-015 | safety.md の複合コマンド根拠を現行仕様（separator ごとに独立判定）へ修正し style 方針と明記。settings-syntax.md の `:*` を「末尾でのみ space-star と同等の legacy-equivalent」へ修正 |
| H-016 | classification.md の claude-bypass 案内を REMOVED 注記へ置換。evidence matrix の launcher 採用行に SUPERSEDED を明記し、本文=現在状態 / 履歴=SUPERSEDED の分離方針を宣言。permission 件数・bypass lockout を metrics block（機械照合対象）に追加し、prose の件数は block を正とする |
| H-017 | `scripts/check-runtime.sh`（doctor）を追加: 検証済み下限 2.1.218 を `claude --version` で検査し、下限未満は明示エラー（silent continuation なし）。startup warning 0 件の目視確認を案内。README の導入手順に組込み |

### 統合再レビュー4 → v7（H-018・H-019・H-007/H-011/H-014/H-013/H-016/H-017 — 合成後の実効ポリシー）

| ID | v7 対応 |
|---|---|
| H-018 | `Edit(.git/**)` deny を撤去（Read/Edit deny → sandbox filesystem 統合により `git add`/`git commit` の `.git/index.lock` 作成を OS-level で阻害していた）。保護は `Edit(.git/config)`・`Edit(.git/hooks/**)` の狭域 deny に置換（公式の linked-worktree built-in 保護と同じ stance）。validator に「broad .git deny 拒否 + 狭域 deny presence contract」検査と negative fixture を追加。副作用（`git config`/`git init`/`git remote add` の sandbox 内失敗）は運用制約として文書化。実 sandbox 内の add/commit 成功は実機検証項目（未検証事項 (e)） |
| H-019 | sandbox 互換 uv wrapper `claude/bin/uvw` を新設: UV_CACHE_DIR / UV_PYTHON_INSTALL_DIR / UV_TOOL_DIR / XDG_CONFIG_HOME を session temp（sandbox 内 `$TMPDIR`）配下へ固定して `exec uv`（既存環境変数は尊重・denyRead は緩和しない）。allow rule・rules・skills・テスト手順を uvw 経由へ統一し、素の `uv run` allow は validator が拒否。skill 同梱 script / Makefile は同一前処理を vendoring（portability）。専用テスト `tests/test-uvw.sh` を追加 |
| H-007 | `WebFetch(domain:...)` allow 5 件を全撤去（WebFetch allow が sandbox Bash の network domain も pre-allow するため「事前許可 domain ゼロ」と矛盾していた）。validator が effective pre-allowed domains（`sandbox.network.allowedDomains` ∪ `WebFetch(domain:)` allow）の和集合 0 件を強制し、metrics block に `effective_preallowed_domains_count` を追加（report consistency test の照合対象） |
| H-011 | amend gate を「argv parser」と呼ぶ誤記述を訂正し、**quote 正規化つき heuristic（事故・平易迂回の防止層）** として再定義。判定を「git 語 × `--amend` token の共起」（over-block 側）へ書き換え、final_4 の回避 7 形（substitution・変数・quote 分割・alias 2 形・nested shell）を全て deny（fixture 化）。加えて `sh *`/`zsh *`/`dash *` deny と `git -c*`/`-C*`/`--git-dir*`/`--work-tree*`/`git config` ask で shell 再評価・前置迂回の permission 層 gate を追加。security boundary は push の ask/deny（公開履歴の保護）と sandbox に置く |
| H-014 | `.env` 保護の最終境界を filesystem policy へ移動: `Read(//**/.env)`・`Read(//**/.env.*)`・`Edit(//**/.env)`・`Edit(//**/.env.*)` の絶対 path deny → sandbox 統合により、動的 path 構築（base64/chr/変数連結）や sibling repo の secret も OS-level で read 拒否。hook は quote 正規化により literal 分割形（`.e""nv`）まで担当し、対象外領域を scope テストとして明示。validator に presence contract を追加 |
| H-013 | custom XDG を fail-closed で非対応化: doctor が XDG_CONFIG/STATE/DATA/CACHE_HOME の既定値逸脱を検出しエラー（受容は `--accept-custom-xdg` + waiver + denyRead 絶対 path 追加）。bootstrap --check/--apply が doctor を自動実行。workspace-only read template は導入契約として README/レポートに明記（scope: user-wide denyRead = 既定 XDG の private tree / workspace 相対境界 = project 設定のみ） |
| H-016 | 「v5 時点」見出し・「事前許可 domain なし」保証・「argv 判定」表現・metrics 件数を v7 実効ポリシーへ同期。配布名の固定と受領側 rename の扱い（SHA-256 照合が正）を明記。metrics block に effective_preallowed_domains_count を追加し consistency test の対象へ |
| H-017 | doctor を bootstrap --check/--apply へ統合（claude 欠落のみ `--soft-missing` NOTE 続行）。prerelease（`-beta` 等）を semver 識別で拒否・future major は NOTE。専用テスト `tests/test-check-runtime.sh` を追加。user settings への `minimumVersion` 追加は**採用しない**: 当該 key は settings 参照に存在せず（2026-07-24 確認）、unknown key は startup warning 0 件契約に反する。managed 配備では `requiredMinimumVersion`（fail-open 設計である点に注意）が利用可能。startup warning 0 件・lockout 拒否の実機 smoke は未検証事項 (c) |

### 適合性レビュー → v8（B-01・C-01・H-01・H-02・M-01・M-02・M-03）

| ID | v8 対応 |
|---|---|
| B-01 | 原本切れを再読で確定（p.15 は Stage 5 冒頭 2 行 + 下半分空白で終了）。versioned 転写 [docs/requirements/requirements-transcription-260722.md](../requirements/requirements-transcription-260722.md) を追加し、実装 Stage 6–7 が §4.1 目的の明文（既視感排除・反証可能性評価・最小実験変換）からの導出であることを明記。**完全版要件書の提示は所有者依頼中**（提示後に Stage 5 後半以降を一対一照合） |
| C-01 | `gh` の read 系 allow 10 件（search/issue list|view/pr list|view|diff|checks/repo view/run list|view）を全て ask へ移動（allow は固定 argv の `gh auth status` のみ）。validator に「excludedCommands の command word と交差する allow は audited exact list 以外 fail」検査 + fixture（audited の誤検出なし含む）を追加。metrics に `unsandboxed_query_capable_allows: 0` を追加し consistency test の照合対象へ |
| H-01 | `sandbox.filesystem.allowRead` を追加（`~/.claude/bin`・`~/.claude/skills`・`~/.config/agents-toolkit` — deny tree 内で sandbox 内実行に必要な最小 subtree の再開。公式仕様の「narrower allow が denied region を再開する」挙動）。validator に deny↔allowRead の presence contract + fixture を追加。実 sandbox での helper 起動 smoke は未検証事項 (e) に追加 |
| H-02 | `tests/test-check-runtime.sh`・`tests/test-uvw.sh` の git mode を 100755 へ修正（`git update-index --chmod=+x`）。validator に check 11「直接実行 surface（tests/test-\*.sh・scripts/\*.sh・hooks・bin・bootstrap）の executable bit」を追加 + 非実行 fixture。検証は CI と同じ直接実行方式で全 13 本 PASS を確認 |
| M-01 | `autoMemoryEnabled: true` を accepted exception **EX-002** として台帳化（learnings 常時 import 廃止の受け皿という設計判断・禁止対象との境界・失効条件を記録）。metrics に `auto_memory_enabled` を追加。注入量実測は実機項目 (f) |
| M-02 | Phase 1 の 11 軸要素別監査表 [docs/reports/inventory-matrix.md](../reports/inventory-matrix.md) を追加（baseline 全要素: agents 14 / skills 21+4 / hooks 9 / rules 7+16 / styles 4 / routing 機構。progress-review 機構 5→0・built-in 重複 2→0 の集計含む）。measure-metrics に行数系 key（claude_md_lines / claude_always_rules_lines / codex_agents_md_lines）を追加し、output_styles を報告表へ掲載 |
| M-03 | 例外承認台帳 [docs/reports/accepted-exceptions.md](../reports/accepted-exceptions.md) を追加（EX-001: skill 純増の承認 — 承認者・2026-07-23 の発言「例外で良い」・対象 path・理由・失効条件。会話ログからの転記である旨を明示し、再レビューでの受入 = 追認と定義） |
