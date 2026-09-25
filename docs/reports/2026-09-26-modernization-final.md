# agents-toolkit 近代化の最終報告（2026-09-26）

指示書 §11 の形式で、Phase 0〜8（commit `9802582`〜`645b217`）をまとめる。baseline は近代化の前の `5d108ba` とする。決定の詳細は `docs/reports/owner-decisions.md`、各 Phase の検証の詳細は commit message と `docs/reports/` の各報告にある。

## 結論

- Phase 0〜8 を実装し、live に反映した。live の checkout の master は `645b217` で、push はしていない。
- §9 の完了条件はすべて満たした。根拠は「実行した検証」の表にある。
- live の状態:
  - `bootstrap.sh --check` の DRIFT は0件。
  - discovery の FAIL は0件で、WARN は haiku の退役予定（not-before 2026-10-15）の2件だけ。
  - managed の hash は `39a2490925354d094b55fe95dda7dc9ef74bb29639e1137b0c25ec0e63483d38` で、EX-003 と EX-004 の再承認の記録と一致している。
- モデルを呼ぶ試験（委任、`--cross`、replay eval、K15）は、integration 環境（host mini）でだけ行った。Claude の費用は合計で約 42.3 USD（Phase 4 約 1.7、Phase 6 約 3.3、Phase 5 約 37.3、Phase 8 は0）。
- GitHub の CI は、push していないのでまだ走っていない。同じ手順をローカルで実行し、すべて PASS した。

## owner 決定と反映状況（D1〜D12、EX の再承認、外部への送信）

| ID | 決定 | 反映 |
|---|---|---|
| D1 | Claude の main は Opus 5.5（Phase 5 の eval で fable/high と同じ成功率、費用は約1/2.9、時間は約1/1.8） | `claude/CLAUDE.md` の lead の行と routing 表の claude-main。live の `model` は `opus` |
| D2 | alias は managed の env pin で明示的に昇格させる | managed に4つ（fable、opus、sonnet、haiku）の pin。routing 表に claude-alias-* の4行 |
| D3 | 委任はユーザーの明示指示だけ（①）、毎 prompt の注入の削除（②）、subagent の起動条件の文の維持（③）、再委任は1回まで（④） | ① Phase 1。② 出力を Phase 1 で止め、登録と script を Phase 7 で削除。③ 維持。④ Phase 4 の gate |
| D4 | `/home/trow126/AGENTS.md` を issue-writing と `shared/rules/issue-completeness.md` に統合 | Phase 1 で統合。ファイルは owner が 2026-09-25 に撤去。既定以外の mode は discovery が WARN |
| D5 | live の設定を正本にする | Phase 7 で `claude/settings.json` と manifest の link を削除。validator は追跡と link を拒否する |
| D6 | 使われていない custom agent 9本と Claude 版の plan-review を削除 | Phase 1 |
| D7 | break-consensus の `--cross` を承認 | Phase 6。付録 C.5 の7項目が integration で PASS |
| D8 | Codex の launcher は `codex exec` の薄い launcher | Phase 4。integration で委任1件と `stopped` を確認。K17 により companion は profile 相当を渡せない |
| D9 | Claude の effort はモデルの既定値（Opus 5.5 は medium、Fable 5.1 は high） | live の `modelSettings` に設定し、top-level の `effortLevel: xhigh` を削除 |
| D10 | core-contract に follow-up とテストの規模の1行を追加 | Phase 1 |
| D11 | codex-plugin-cc を上流の 1.0.6 に戻す。`--resume-last` は使わない | owner が戻した（discovery でローカル変更0件）。skill に不使用を明記 |
| D12 | 費用の上限は1回 2 USD、Phase 4 は合計 15 USD、Phase 5 は合計 60 USD | Phase 4 約 1.7 USD。Phase 6 の C.5 は owner がこの1回に限り 3 USD まで許可し、推定 3.18 USD で超過した。Phase 5 は owner が1回の上限を 4 USD に上げ、合計約 37.3 USD |

- **EX の再承認**: EX-003 と EX-004 を 2026-09-25 に再承認した。EX-004 の artifact は `autoMemoryEnabled: false` を移した managed に変わり、2つの EX とも managed の hash に拘束される。
- **OD の置き換え**: OD-1 の「main は Fable」は D1 で、OD-7 の `effortLevel: xhigh` は D9 で置き換えた。OD-5 は D8 で exec の launcher に変わり、codex-rescue は managed の deny にした。
- **Phase ごとの実装判断**: P1-Q1〜Q3、P4-IT、P5-Q1〜Q3、P7-Q1〜Q4、P8-Q1〜Q2 は `owner-decisions.md` に記録した。
- **外部への送信**:
  - GitHub への書き込み（push、Issue、PR、comment）は一度も行っていない。
  - モデルの provider への送信は integration 環境でだけ行った。Phase 5 の eval では、private repo の過去の Issue と code を Claude と Codex に送った（owner が承認）。repo には匿名化した T1〜T6 だけを記録し、対応表は private overlay（追跡しない）に置いた。
  - `--cross` の brief は、別の provider（OpenAI）に送る。これは `skill-authority.tsv` の egress 列に書いてある。

## Phase ごとの変更

正本は手で編集するファイルを指す。生成物は script が作るファイルで、次の3つだけである。

- `codex/AGENTS.md` の `shared:` ブロック（`shared/bin/sync-shared-rules.sh` が作る）
- `docs/plans/2026-07-23-agents-toolkit-modernization.md` の metrics:after（`scripts/measure-metrics.sh` が作る）
- `tests/fixtures/skill-pair-drift/*.diff`（`tests/test-skill-pair-drift.sh --update` が作り、review してから commit する）

discovery の snapshot は追跡しない。

| Phase | path | 変更理由 |
|---|---|---|
| 0 | `docs/reports/owner-decisions.md` | 決定の台帳 |
| 1 | `claude/CLAUDE.md`、`shared/skills/claude-code/model-routing/SKILL.md` | §2.4-7 の矛盾を解消する（codex-rescue の起動、peer の扱い、`teammateDefaultModel`、SessionStart と Agent Teams の記述） |
| 1 | `claude/rules/settings-syntax.md`、`claude/hooks/pre-bash-validate-hook.sh`、`docs/reports/inventory-matrix.md`、`docs/reports/accepted-exceptions.md` | 「bypassPermissions では deny が効かない」という古い記述を直す |
| 1 | `shared/rules/core-contract.md` | D10 |
| 1 | `claude/skills/gh-codex-drive/references/codex-route.env`、`claude/skills/gh-codex-drive/SKILL.md`、`claude/skills/gh-roadmap-drive/SKILL.md` | model と effort を毎回明示する。`codex:gpt-5-4-prompting` への依存をやめる（§2.4-6） |
| 1 | `claude/hooks/pr-review-hook.sh` | 指示先を有効な skill にし、additionalContext で返す |
| 1 | `.claude/settings.json`（toolkit repo） | `claudeMdExcludes` で配布元の instruction を除外する（§2.4-2） |
| 1 | skill の frontmatter と `agents/openai.yaml` | manual-only を native の制御で指定する。紛らわしい4組の description を書き直す |
| 1 | `scripts/validate-layout.sh`、`.github/workflows/ci.yml`、`claude/hooks/lib/post_edit_lint.py`、`scripts/audit-context-runtime.sh` | §2.4-9 と §2.4-10 |
| 2 | `docs/contracts/model-routing.tsv`、`scripts/lib/check-model-routing.py`、`scripts/lib/scan-model-pins.py` | routing 表を正本にし、targets との一致とモデル名を検査する |
| 2 | `codex/skills/claude-second-opinion/scripts/ask-claude.sh` | route を変数にし、`--max-budget-usd` を付ける |
| 3 | `scripts/discover-runtime.sh`、`scripts/lib/discover_runtime.py`、`docs/runbooks/codex-cli-update.md`、`docs/reports/2026-09-25-codex-0.157.0-state.md` | read-only の discovery。K2 と K14 の記録 |
| 4 | `claude/bin/codex-delegate`、`codex-delegate-preflight`、`verify-delegation`、`delegation-evidence-check`、`delegation_common.py` | D8 の launcher、preflight、gate、gh-finish の確認 |
| 4 | `claude/skills/gh-codex-drive/references/`（契約と報告の schema、prompt の template）、`codex/profiles/toolkit-implementer.config.toml` | 契約と、Codex の実行時の設定 |
| 4 | `scripts/codex-profile-trust.py`、`docs/runbooks/integration-environment.md`、`docs/reports/2026-09-25-integration-phase4.md` | K11 の trust を `~/.codex/config.toml` に移す。integration の手順と結果 |
| 5 | `docs/contracts/model-routing.tsv`、`claude/CLAUDE.md`、`codex/agents/explorer.toml`、`codex/AGENTS.md`、`docs/eval/replay-tasks.md`、`docs/reports/2026-09-26-routing-eval.md` | D1、D9、P5-Q1〜Q3 |
| 6 | `claude/bin/break-consensus-cross`、`shared/skills/break-consensus/references/`、`codex/profiles/toolkit-divergent.config.toml`、`docs/contracts/skill-authority.tsv` | D7 の `--cross`。egress 列 |
| 7 | `claude/managed-settings.json`、`scripts/check-managed-policy.py`、`scripts/install-managed-policy.sh`、`scripts/check-runtime.sh`、`docs/reports/accepted-exceptions.md`、`docs/runbooks/governance-apply.md` | env pin、codex-rescue の deny、`autoMemoryEnabled`、version の下限 2.1.281、EX の再承認 |
| 8 | `shared/skills/gh-{issue,pr,review,start}/SKILL.md`、`install/manifest.tsv`、`tests/test-skill-pair-drift.sh` | §6.5 の統合と drift test |
| 8 | `docs/reports/rule-evidence.md`、`shared/rules/learnings.md`、`claude/rules/settings-syntax.md` | 日付付きの事実を docs に移す |
| 8 | `scripts/lib/discover_runtime.py` | 任意の項目（broker、hook の trust、features、skill 一覧のサイズ、prompt-input） |

### rules と Skills の移行

| 旧 path | 新 path | 理由 |
|---|---|---|
| `shared/skills/claude-code/gh-{issue,pr,review,start}/SKILL.md` と `shared/skills/codex/gh-*/SKILL.md` | `shared/skills/gh-{issue,pr,review,start}/SKILL.md`（references と同じ directory） | runtime 間の重複を統合する（Phase 8） |
| `shared/skills/{claude-code,codex}/pr-review/` | 削除。`gh-pr --review-comment` に一本化 | P1-Q1 |
| `shared/skills/claude-code/plan-review/` | 削除（Codex 版は残す） | D6 |
| `claude/agents/` の9本（ai-engineer、blockchain-security-auditor、code-reviewer、data-engineer、deep-reasoner、model-qa-specialist、plan-reviewer、solidity-engineer、sre） | 削除（explore.md だけ残す） | D6 |
| `/home/trow126/AGENTS.md` | `codex/skills/issue-writing/`、`shared/rules/issue-completeness.md` | D4 |
| `codex/references/python-quality.md` | `shared/rules/python-guidelines.md` | 重複した品質規則を1本にする |
| `claude/settings.json` | 削除（live の `~/.claude/settings.json` が正本） | D5、P7-Q2 |
| `claude/hooks/{session-init,post-compact,prompt-submit}-hook.sh`、`claude/hooks/lib/emit_system_message.py` | 削除 | P7-Q1、D3② |
| `shared/rules/learnings.md` と `claude/rules/settings-syntax.md` の日付と version | `docs/reports/rule-evidence.md` | §6.1 |

## 実行した検証（command / result）

| command / 手順 | 環境 | result |
|---|---|---|
| `bash -n`、`py_compile`、`jq empty`、`scripts/validate-layout.sh`、`scripts/package-release.sh --check`、`shared/bin/sync-shared-rules.sh --check`、`scripts/lint-distributed-markdown.sh`、`tests/test-*.sh`（28本）、`test-ask-claude.sh`、pytest、gitleaks | authoring（`645b217`） | すべて PASS |
| 一時 HOME での `bootstrap.sh --dry-run` | authoring | 統合した4つの skill を、同じ source から両方の runtime に link する予定を確認 |
| K15: symlink の skill の相対参照（`../../X/references` と symlink の `references/`）。`codex exec`、明示的な起動と暗黙的な起動の2回 | mini | 両方 PASS。Codex は path を正規化せずに shell に渡し、kernel が実体側で解決する |
| 受入: managed の導入、`bootstrap.sh --apply` と `--check` | mini | DRIFT 0件 |
| 受入: validate-layout と全 test | mini | PASS。失敗0件 |
| 受入: discovery | mini | FAIL 0件。prompt-input の core contract は1回 |
| 受入: `scripts/audit-context-runtime.sh` | mini | 13項目が PASS（superpowers を無効の状態で入れて、live と揃えた） |
| Case 11、13、9: `claude -p "/context" --max-budget-usd 0.000001` | mini | どれも num_turns 0、費用 0。Memory files は `~/.claude/CLAUDE.md` と core-contract の各1回（repo の外、clone の中、`claude/` の中） |
| 委任1件、`stopped`、K6、K7、K11、K17、K18、C.2 | mini（Phase 4） | PASS（`2026-09-25-integration-phase4.md`） |
| 付録 C.5（`--cross`） | mini（Phase 6） | 7項目が PASS |
| replay eval（6題材 T1〜T6、条件ごと） | mini（Phase 5） | どの条件も 6/6。explorer は terra 8/8、luna 7/8（`2026-09-26-routing-eval.md`） |
| live: fast-forward の後に `bootstrap.sh --check`、validate-layout、`sync --check`、discovery | live | DRIFT 0件、PASS、OK、FAIL 0件（WARN は haiku の2件）。Codex の hook は2つとも trust 済み |

## 移行前後の比較（baseline との差）

`scripts/measure-metrics.sh` で `5d108ba`（前）と `645b217`（後）を測った。

| 指標 | 前 | 後 |
|---|---|---|
| Claude の常時注入（CLAUDE.md と import） | 4,413 bytes | 4,544 bytes |
| Codex の `AGENTS.md` | 3,334 bytes | 3,510 bytes |
| 常時注入の合計（2 runtime） | 7,747 bytes | 8,054 bytes |
| session 開始時の Claude への注入（最大） | 4,925 bytes | 4,544 bytes |
| 毎 prompt の注入（UserPromptSubmit、最大） | 256 bytes | 0 |
| SessionStart / PostCompact の systemMessage（最大） | 512 / 512 bytes | 0 / 0 |
| custom agent | 10 | 1 |
| 配布する skill（Claude / Codex） | 20 / 20 | 18 / 19 |
| skill の entrypoint（数 / bytes） | 32 / 77,054 | 25 / 66,510 |
| hook の script / 登録 | 9 / 11 | 6 / 8 |
| routing 表の行 / targets の外のモデル名 | なし / 未計測 | 16 / 0 |
| managed の deny | 87 | 88（codex-rescue） |

常時注入が増えたのは、core-contract に D10 の1行を加えたことと、`codex/AGENTS.md` の各行を routing の target にするために分けたためである。一方で、毎 prompt の注入と systemMessage は無くなった。Codex が prompt で一覧する skill は14件（manual-only を除く）で、一覧の部分は 6,712字である。

## live 設定の drift（D5 の結果と、残っている差分）

- `~/.claude/settings.json` は通常ファイルで、これが正本である。repo には追跡も link も無い。
- 値は `model: opus`、`modelSettings` が Opus 5.5 は medium、Fable 5.1 は high。top-level の `effortLevel` は無い。
- 変更前の file は `~/.local/state/agents-toolkit/backup/` に退避してある。
- `skillOverrides`: agmsg は削除済み。gh-pr と config-audit は user-invocable-only。**gh-review、gh-index、python-refactor-analysis は off のまま**である。§6.5 では、off を name-only か user-invocable-only に変えるのは owner の作業になっている。
- Codex: `~/.codex/config.toml` の既定と `[agents]` は routing 表と一致している。profile の hook の trust は `config.toml` にある。trust を移す前の file は `~/.local/state/agents-toolkit/backup/codex-config.toml.before-trust-move` に退避してある。
- discovery の WARN は、haiku の退役予定の2件（claude-explore と claude-alias-haiku、not-before 2026-10-15）だけである。日付が発表されたら Level 1（routing 表の行の更新）として扱う。

## 未対応事項と未検証事項

- **K3（部分確認）**: managed の deny `Agent(codex:codex-rescue)` を置くと、その type が Agent tool の説明から消えることは確認した。実際の呼び出しは PreToolUse の hook が先に拒否するので、bypass の下で deny だけで拒否されるかは切り分けていない。
- **Codex の reviewer、plan_reviewer、deep_reasoner**: どれも gpt-5.6-sol のままで、main の gpt-6-astra より前の世代である（§2.4-7 の Codex 側）。役割を付けた spawn は K13 で1回しか使われていないので、Phase 5 では評価していない。routing 表の値は「現状値」のままである。
- **Codex で cwd を `codex/` にした場合の二重注入**: 既知の制約として残す（validate-layout が WARN を出す）。
- **任意の項目で行わなかったもの**: K10（`codex/AGENTS.md` の symlink 化。core-contract の変更が要る）、K8（`claude plugin eval`）、managed の Stop hook（evidence の無い完了報告は観測されていないので、追加の条件を満たしていない）。
- **discovery の hook の trust**: 比べているのは、toolkit が計算した hook の定義の hash である。Codex の `trusted_hash` の計算方法は再現していない。定義が変わったのに trust が変わっていないことは検出できる。
- **Phase 8 の受入でモデルを呼ぶ試験**: 委任、`stopped`、C.5 は、Phase 8 で変えていない経路なので、Phase 4 と Phase 6 の結果を使った。
- **GitHub の CI**: push していないので、まだ走っていない。live の master と `modernize/phase-4`〜`phase-8` の branch は未 push である。
- **integration の記録**: mini の `~/.local/state/agents-toolkit-it-backup/2025092{5,6}/cleanup/` には、private repo の Issue の本文と clone（Phase 5）が入っている。削除するかどうかは owner が決める。
- **§6.5 の空ディレクトリ18個**: live には残っていない（あるのは Claude Code が実行時に作る `.cc-writes` の2つだけ）。

## rollback 方法

live の master で、戻したい Phase までの commit を新しい順に `git revert` し、下の表の手作業を行う。後の commit が前の commit に依存しているので、途中の Phase だけを戻すときは衝突を確かめながら進める。どの場合も、最後に `./bootstrap.sh --check` と `./scripts/discover-runtime.sh` で確認する。live の `settings.json` を退避して `bootstrap.sh --apply` を実行することはしない（§4.4）。

| commit（新しい順） | 内容 | revert の後の手作業 |
|---|---|---|
| `645b217` | Phase 8 | 下の command で、8本の link を旧 path に戻す |
| `81eee42` | live への反映の記録 | なし |
| `6b4c714` | Phase 5（D1、D9、routing） | live の settings を `~/.local/state/agents-toolkit/backup/settings.json.before-d9-20260926T014721` から戻す（owner） |
| `c893785`、`e1b002c` | Phase 6 と Phase 4 の integration の修正 | なし |
| `2e3f457` | Phase 7（managed） | owner が sudo で `install-managed-policy.sh --apply` を実行し、旧い policy を入れる。旧い policy は削除した hook を登録しているので、revert で hook の script が戻ったことを先に確かめる。EX-003 と EX-004 の記録は revert で旧い hash に戻る。manifest に `claude/settings.json` の link が戻るので、`--check` の DRIFT はその1件になる（Phase 7 の前と同じ） |
| `a4d3c3c` | Phase 6（`--cross`） | `~/.codex/toolkit-divergent.config.toml` の link を削除する |
| `b752bd0`、`7562a32` | Phase 4（委任）と D7、D8、D12 の記録 | `~/.codex/toolkit-implementer.config.toml` の link を削除し、Codex の trust を `~/.local/state/agents-toolkit/backup/codex-config.toml.before-trust-move` から戻す |
| `505246f`、`9e9bc6b` | Phase 3（discovery） | なし（snapshot は追跡していない） |
| `11415ee`、`f2ad282` | Phase 2（routing 表）と D2 の記録 | なし |
| `06c892b` | Phase 1 | 削除した agent と skill の link を、`--check` の DRIFT を見ながら手で作る |
| `9802582` | Phase 0（台帳） | なし |

```bash
for s in gh-issue gh-pr gh-review gh-start; do
  ln -sfn ~/agents-toolkit/shared/skills/claude-code/$s ~/.claude/skills/$s
  ln -sfn ~/agents-toolkit/shared/skills/codex/$s ~/.agents/skills/$s
done
```
