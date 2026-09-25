# Owner decisions（owner 決定台帳）

## この台帳の位置づけ

- agents-toolkit 近代化改修（2026-09-25 開始）で使う owner 決定の正本。
- 出典の指示書は、owner が作成した「agents-toolkit近代化改修 指示書」（作成日 2026-09-25、repo 外）である。以下では「指示書」と呼ぶ。
- OD-1（`claude/CLAUDE.md:21`）と OD-5（`claude/CLAUDE.md:40`）の元の行は、Phase 2 と Phase 7 で書き換わる。そのため、Phase 0 以降はこの台帳の記載を正本とする。
- hash に拘束された artifact（EX-003 / EX-004）の承認記録は、引き続き `docs/reports/accepted-exceptions.md` を正本とする。この台帳は参照だけを持つ。
- 決定を変えるには、owner の明示的な承認が必要である。変更したときは、該当行の決定文、決定日、出典、反映状況を同じ変更で更新する。

## 記録済みの owner 決定（OD / EX）

指示書 §2.5 の表を、本文ごと転記した。

| ID | 決定 | 出典 |
|---|---|---|
| EX-003 | managed policy で bypassPermissions を既定にし、sandbox を無効にする。`claude/managed-settings.json` の SHA-256 に拘束する | `docs/reports/accepted-exceptions.md` |
| EX-004 | native memory を無効にする。`claude/settings.json` の SHA-256 に拘束する | 同上 |
| OD-1 | Claude の main は Fable（lead / advisor）。dynamic workflow の worker には opus を明示する | `claude/CLAUDE.md:21`（2026-09-25 時点） |
| OD-2 | 単一 owner の原則。無条件の handoff は廃止する | 要件書 `260722_2151_001.pdf` p.8-11。PDF は repo の外にあり、転写は `docs/requirements/requirements-transcription-260722.md` |
| OD-3 | 常設 agent を新たに追加しない。新しい skill は1つだけにする | 同上 |
| OD-4 | Claude の agent は tier alias を使う。full pin は waiver が無ければ FAIL にする | `scripts/validate-layout.sh` |
| OD-5 | Codex への委任は、main session から `codex-companion.mjs task` を Bash(run_in_background=true) で起動する。codex-rescue は hook で拒否する。**2026-09-25 に D8 で更新**: 起動するものを `~/.claude/bin/codex-delegate`（`codex exec` の薄い launcher）に替える。main session から Bash(run_in_background=true) で起動することと、codex-rescue の拒否は変えない | `claude/CLAUDE.md:40`（2026-09-25 時点）、`claude/hooks/pre-bash-validate-hook.sh`、D8 |
| OD-6 | break-consensus は manual-only とする | `docs/requirements/requirements-transcription-260722.md`（p.12–15「手動起動型」、§4.2 起動条件） |
| OD-7 | Claude の effort は、top-level の `effortLevel: xhigh` とする（D9 で置き換える予定） | `docs/reports/accepted-exceptions.md:25` |

- hash に拘束されたファイルを変更するときは、同じ変更の中で `accepted-exceptions.md` の再承認記録と hash を更新する。managed 側は sudo による再導入も必要になる。
- managed policy と hash 拘束ファイルの変更は、Phase 7 にまとめる。

## 決定済みの論点（D）

指示書 §5.1 の表を、本文ごと転記した。決定日はすべて 2026-09-25、出典は指示書 §5.1 である（D2、D7、D8、D12 は、§5.2 の未決定の論点に対する owner の回答）。`scripts/validate-layout.sh` の絶対 home path 検査に合わせ、指示書の `$HOME` 直下の AGENTS.md の絶対 path は `~/AGENTS.md` と表記した。

| ID | 論点 | 決定 |
|---|---|---|
| D3 | 委任の位置づけ | ① Codex への委任は、ユーザーが明示的に指示したときに限る。明示的な指示とは、`/gh-codex-drive` や `/gh-roadmap-drive` を呼ぶこと、または文面で Codex への実装の委任を指示することを指す。Claude が自分の判断で委任を選ぶことはしない<br>② 毎 prompt に注入している2行（`claude/hooks/prompt-submit-hook.sh`）は削除する。同じ内容は core-contract と `claude/CLAUDE.md:19` にある。出力は Phase 1 で止め、hook の登録は Phase 7 で外す<br>③ `codex/AGENTS.md` にある subagent の起動条件の文は維持する<br>④ 再委任は1回までとする |
| D4 | mode と `~/AGENTS.md`（`$HOME` 直下の AGENTS.md） | `~/AGENTS.md` の内容を issue-writing skill と `shared/rules/issue-completeness.md` に統合し、ファイルは owner が撤去する。mode は既定の or-mode のままとし、managed には書かない。既定値以外になったら、discovery が WARN を出す |
| D5 | live の設定と repo のどちらを正本にするか | live を正本とする。UI が書き換えるキー（model、modelSettings、skillOverrides、pluginConfigs、claude.ai 同期の設定）は repo で管理せず、drift は WARN にする。Phase 7 で次を行う<br>・`claude/settings.json` から model を削除する<br>・effortLevel を D9 に合わせる<br>・manifest の `link-file claude/settings.json` を外す<br>・EX-004 を再承認する<br>`autoMemoryEnabled:false` は、discovery が FAIL として監視する |
| D6 | 使われていない agent | Explore 以外の custom agent 9本（ai-engineer、blockchain-security-auditor、code-reviewer、data-engineer、deep-reasoner、model-qa-specialist、plan-reviewer、solidity-engineer、sre）と、Claude 版の plan-review skill の配布をやめる（Phase 1）。これらはどの環境でも使われていない。計画のレビューには、Codex 版の plan-review か `/code-review` を使う |
| D10 | core-contract への追加 | 次の1行を加える:「既存のバグや範囲外の問題は修正せず、follow-up として報告する。テストの規模は、タスクと既存の慣習に見合うものにする」（Fable 5.1 の公式 guidance に基づく） |
| D11 | codex-plugin-cc のローカル変更 | 上流版の 1.0.6 に戻す（ローカル変更は破棄する。作業は owner が行う）。session ID は明示しない。gh-codex-drive は `--resume-last` を使わない。status に他の session の job が混ざることは許容する |
| D7 | break-consensus を cross-provider にするか | 承認する。Phase 6 で `/break-consensus --cross` を opt-in の read-only モードとして実装し、`docs/requirements/requirements-transcription-260722.md` の「実装マッピング（非規範）」節を更新する（2026-09-25、この作業 session で owner が選択） |
| D8 | Codex の launcher | `codex exec` の薄い launcher にする。profile（`-p toolkit-implementer`）、`--output-schema`、catalog の全 effort を使う。そのために pre-bash-validate-hook と OD-5 を更新し、inline hook の trust は owner が integration 環境と live の両方で付与する。K11 と K17 は Phase 4 の integration で確認し、結果によって再評価する（2026-09-25、この作業 session で owner が選択。実装者の推奨は companion の継続だった） |
| D12 | 費用の上限 | モデルを呼ぶ試験は、1回あたり 2 USD、Phase 4 で合計 15 USD、Phase 5 で合計 60 USD までとする。Claude は `--max-budget-usd` で上限をかける。`codex exec` には USD の上限が無いので、実行回数で管理する（2026-09-25、この作業 session で owner が選択） |
| D2 | alias の方針 | managed の env pin（`ANTHROPIC_DEFAULT_{OPUS,FABLE,SONNET,HAIKU}_MODEL`）で alias の解決先を固定し、明示的に昇格させる。agent の frontmatter は alias のままにし、OD-4 と両立させる。env pin は managed の変更なので、routing 表の該当行とあわせて Phase 7 で入れる（2026-09-25、この作業 session で owner が推奨案を選択） |

## 未決定の論点（D）

指示書 §5.2 の表を転記した。実装者が「決める時期」までに推奨を提示し、owner が「承認」か「変更」を返す。決定したら「決定済みの論点」へ移し、決定日と出典を書く。

| ID | 論点 | 選択肢 | 推奨 | 決める時期 | 状態 |
|---|---|---|---|---|---|
| D1 | Claude の main モデル | Fable 5.1 を維持する / Opus 5.5 を main にし、Fable を advisor か昇格先にする（advisor は experimental で、Anthropic API でしか使えない。同意と feature flag が無いと、何も表示されずに無効になる） | Phase 5 の eval で決める | Phase 5 | 未決定 |
| D9 | Claude の effort（OD-7 を置き換える） | xhigh 一律 / モデルごとの `modelSettings` | 後者。方針は、公式のベストプラクティスに従ってモデルの既定 effort を使うこと（Fable 5.1 は high、Opus 5.5 は medium）。値は Phase 5 の sweep で確定し、置き場所は D5 に従う。Phase 7 までは、repo の `effortLevel: xhigh` も live の値も変えない | Phase 5 で決め、Phase 7 で適用する | 未決定 |

## Phase 1 の実装判断

2026-09-25 に owner が、Phase 1 計画に対する問いに回答した（この作業 session での選択）。

| ID | 論点 | 決定 |
|---|---|---|
| P1-Q1 | pr-review を一本化するか | 案A。pr-review を両方の runtime から外し、`gh-pr --review-comment` に一本化する。PostToolUse の pr-review-hook は、`/code-review <PR>` によるレビューと、ユーザーの明示指示による `/gh-pr --review-comment` を案内するだけにする |
| P1-Q2 | `bootstrap.sh` の `STALE_CLAUDE_SKILLS` への追加 | 承認。`plan-review` と `pr-review`（旧 source `shared/skills/claude-code/<name>`）を加え、live に残った link を `--check` で DRIFT として検出する |
| P1-Q3 | Slack 通知の opt-out env の名前 | 承認。`AGENTS_TOOLKIT_SLACK_NOTIFY=off` |

## 反映状況

| ID | 反映する Phase | 状態（2026-09-25） |
|---|---|---|
| D3 | ① ② 出力停止 ④: Phase 1 / ② 登録解除: Phase 7 / ④ の gate: Phase 4 | ①②④: Phase 1 branch で反映（live 未反映）。② の登録解除と ④ の gate は未反映 |
| D4 | 統合: Phase 1 / 撤去: owner / WARN: Phase 3 | 統合: 反映済み。撤去: 2026-09-25 に実施（`~/.local/state/agents-toolkit/backup/` へ退避）。WARN: Phase 3 の discovery で実装 |
| D2 | routing 表の作成: Phase 2 / env pin の導入と該当行の commit: Phase 7 | routing 表: Phase 2 branch で作成（env pin の検査は実装済みで、対象は現状0件）。env pin は未反映 |
| D5 | discovery の WARN / FAIL: Phase 3 / settings と manifest: Phase 7 | discovery の WARN（UI キーと settings の drift）と FAIL（`autoMemoryEnabled`）: Phase 3 で実装。settings と manifest は未反映 |
| D6 | Phase 1 | Phase 1 branch で反映（live 未反映。`~/.claude/skills/plan-review` の link 削除は owner） |
| D10 | Phase 1 | Phase 1 branch で反映（live 未反映） |
| D11 | 上流版への復帰: owner / `--resume-last` 不使用の確認: Phase 1 | 不使用を確認し、gh-codex-drive と gh-roadmap-drive に明記した（Phase 1 branch）。上流版への復帰は owner |
| OD-1 | routing 表の targets（claude-main、claude-workflow-worker）: Phase 2 | Phase 2 branch で反映。`claude/CLAUDE.md` の lead の行と worker の行を分け、それぞれを routing 表の target にした（決定の内容は変えていない） |
| OD-5 | launcher の変更（D8）: Phase 4 / codex-rescue 禁止文の削除と managed deny: Phase 7 | launcher の変更は Phase 4 branch で実装する（integration で検証が通るまで live には取り込まない）。codex-rescue の部分は現行のまま |
| D7 | Phase 6 | Phase 6 branch で静的な部分を実装（live 未反映。phase-4 の上に作ったので、phase-4 の後に取り込む）。route は divergent-claude が opus、divergent-codex が gpt-6-astra/medium、`skill-authority.tsv` の egress 列は別の model provider への送信を表す（いずれも 2026-09-25、この作業 session で owner が選択）。K18 は静的には使える（2.1.282 に `agent()` の `opts.disallowedTools` が実装されている。model 向けの API 説明には載っていない）。C.5 の実行と K18 の実行時の確認は integration 待ち |
| D8 | Phase 4 | Phase 4 branch で実装する（live は、integration で検証が通るまで companion のまま） |
| D12 | Phase 4 と Phase 5 の integration での試験 | 未適用（integration 環境の準備待ち） |
| OD-7 | D9 で置き換える: Phase 7 | 現行の値のまま |
