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
| OD-1 | Claude の main は Fable（lead / advisor）。dynamic workflow の worker には opus を明示する（main は D1 で Opus 5.5 に置き換えた。2026-09-26） | `claude/CLAUDE.md:21`（2026-09-25 時点） |
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
| D1 | Claude の main モデル | Opus 5.5 を main にする。Phase 5 の replay eval（6題材）で fable/high と同じ成功率で、費用は約1/2.9、時間は約1/1.8。opus での互換性（hook、deny、完了通知）も確認した。`claude/CLAUDE.md` の lead の行と routing 表の claude-main を変え、live のモデルは owner が `/model` で選ぶ（D5）。OD-1 の「main は Fable」を置き換える（2026-09-26、この作業 session で owner が選択） |
| D9 | Claude の effort（OD-7 を置き換える） | モデルの既定値を使う（Fable 5.1 は high、Opus 5.5 は medium）。xhigh は Phase 5 の eval で high より遅く高く、良くもならなかった。値は owner が live の `modelSettings` に設定する（D5）（2026-09-26、この作業 session で owner が選択） |
| P5-Q1 | Codex の実装担当の route | gpt-6-astra/medium を維持する（low、sol/medium との差は出なかった）（2026-09-26） |
| P5-Q2 | Codex の explorer | gpt-5.6-terra から gpt-6-luna（medium）に変える（2026-09-26） |
| P5-Q3 | `--cross` の Claude worker | main が opus になったので、fable に変える（2026-09-26） |

## 未決定の論点（D）

指示書 §5.2 の表を転記した。実装者が「決める時期」までに推奨を提示し、owner が「承認」か「変更」を返す。決定したら「決定済みの論点」へ移し、決定日と出典を書く。

2026-09-26 時点で未決定の論点は無い（D1 と D9 は Phase 5 の eval の後に決定した）。

## Phase 1 の実装判断

2026-09-25 に owner が、Phase 1 計画に対する問いに回答した（この作業 session での選択）。

| ID | 論点 | 決定 |
|---|---|---|
| P1-Q1 | pr-review を一本化するか | 案A。pr-review を両方の runtime から外し、`gh-pr --review-comment` に一本化する。PostToolUse の pr-review-hook は、`/code-review <PR>` によるレビューと、ユーザーの明示指示による `/gh-pr --review-comment` を案内するだけにする |
| P1-Q2 | `bootstrap.sh` の `STALE_CLAUDE_SKILLS` への追加 | 承認。`plan-review` と `pr-review`（旧 source `shared/skills/claude-code/<name>`）を加え、live に残った link を `--check` で DRIFT として検出する |
| P1-Q3 | Slack 通知の opt-out env の名前 | 承認。`AGENTS_TOOLKIT_SLACK_NOTIFY=off` |
| P7-Q1 | session-init と post-compact の hook | 両方を削除する（登録、script、`emit_system_message.py`、test）。systemMessage は user にだけ表示され、モデルは system prompt の gitStatus で同じ情報を得ている（2026-09-25） |
| P7-Q2 | manifest の link を外した後の `claude/settings.json` | repo から削除する。live の `~/.claude/settings.json` を正本とし、validator は repo での追跡と manifest の link を拒否する（2026-09-25） |
| P7-Q3 | D2 の env pin の対象 | fable、opus、sonnet、haiku の4つすべて。sonnet は CLI 2.1.282 の内蔵 model 一覧の `claude-sonnet-5`（2026-09-25） |
| P4-IT | Phase 4 の integration 環境 | host `mini` 本体を使う（使い捨ての distro の代わり）。設定を退避し、候補の managed を machine 全体に入れ、live と同じ settings、Codex の既定値、plugin に揃える。結果は `docs/reports/2026-09-25-integration-phase4.md`（2026-09-25） |
| P8-Q1 | 統合した gh-start の description | Claude 専用の skill（gh-codex-drive、gh-finish）を「Not for」から外し、`Not for gh-pr or gh-review.` にする（2026-09-26） |
| P8-Q2 | Phase 8 の受入の環境 | mini を再構築して受入を行い、終わったら再び片づける。モデルを呼ぶ試験は Phase 4 と Phase 6 の結果を使う（2026-09-26） |
| P8-Q3 | Codex の reviewer、plan_reviewer、deep_reasoner（gpt-5.6-sol、役割付きの spawn は1回だけ） | reviewer と deep_reasoner の配布をやめる。独立 review は組み込みの `codex review`、高 risk の判断は owner が行い、独立した意見は claude-second-opinion で得る（deep_reasoner は main より前の世代で、escalate が逆転していた。§2.4-7）。plan_reviewer は plan-review skill が起動するので残し、同じ系列の後継の gpt-6-sol/high に上げる（§12 の Level 1）（2026-09-26） |
| P8-Q4 | Codex の組み込みの default と worker（live の `[agents]`） | gpt-5.6-sol/high から、同じ系列の後継の gpt-6-sol/high に揃える（§12 の Level 1。P8-Q3 の plan_reviewer と同じ）。live の `~/.codex/config.toml` は owner の指示で変更し、変更前の file は `~/.local/state/agents-toolkit/backup/` に退避した（2026-09-26） |
| P8-Q5 | K10（`codex/AGENTS.md` を core-contract への symlink にするか） | 採らない。Codex 0.157.0 が常時読む instruction は `~/.codex/AGENTS.md` の1つだけで、`@path` や include を展開しない（一時 CODEX_HOME の `codex debug prompt-input` で確認）。symlink にするには Codex 固有の約16行（言語、Task 別規約、routing、GitHub、Runtime）を別の常時読込先に移す必要があるが、core-contract に移すと Claude の常時注入に Codex の routing が入り、live の `config.toml` の `developer_instructions` に移すと repo の管理と validator の検査から外れ、skill に移すと常時の指示ではなくなる。marker の区間の sync を維持する（2026-09-26） |
| P8-Q6 | K3 と K8 の確認 | integration で行う。K8 の上限は 4 USD。K8 の suite は repo に残し（`scripts/build-skill-trigger-eval.py`）、description や version が変わったときに測り直す。結果は `docs/reports/2026-09-26-k3-k8.md`（2026-09-26） |
| P7-Q4 | EX-004 が拘束する artifact | `autoMemoryEnabled: false` を managed に移し、policy で強制する。artifact は `claude/managed-settings.json` の hash で、EX-003 と同時に再承認する。discovery は実効値（managed が優先）を FAIL で監視する（2026-09-25） |

## live への反映（2026-09-26）

`modernize/phase-4`、`phase-6`、`phase-7`（Phase 5 の決定を含む）を、`docs/runbooks/governance-apply.md` の手順で live に反映した（live の master は `505246f` から `6b4c714` へ fast-forward）。

- managed: owner が sudo で導入した（hash `39a249092535…`、EX-003 と EX-004 は 2026-09-25 に再承認済み）。
- link: `~/.codex/toolkit-implementer.config.toml` と `~/.codex/toolkit-divergent.config.toml` を手で作った。`bootstrap.sh --check` の DRIFT は0件（Phase 1 から残っていた `~/.claude/settings.json` の DRIFT も、manifest から外したので解消した）。
- Codex の hook の trust: owner が付与し、`scripts/codex-profile-trust.py` で `~/.codex/config.toml` に移した（TUI の trust は live の checkout の profile を書き換えるため）。
- live の `settings.json`（D5、D1、D9）: `model` を `opus` にし、top-level の `effortLevel: xhigh` を削除した。`modelSettings` は Opus 5.5 が medium、Fable 5.1 が high（owner が `/model` で設定）。変更前の file は `~/.local/state/agents-toolkit/backup/` に退避した。
- discovery: FAIL 0。WARN は haiku の退役予定（not-before 2026-10-15、Level 1 の候補）の2件だけ。

下の表の「live 未反映」の記述は、上の反映で解消した（表は各 Phase の実装時点の記録として残す）。

Phase 8（`645b217`）: K15 を integration で確認し（Codex 2回）、mini を組み直して受入を行った（`--check` の DRIFT 0件、全 test、discovery の FAIL 0件、audit の13項目、Case 9、11、13。モデルを呼ぶ費用は0）。mini は元に戻した。live の master を `645b217` へ fast-forward し、統合した4つの skill の link 8本を手で張り替えた。live の `--check` の DRIFT は0件、discovery の FAIL は0件。最終報告は `docs/reports/2026-09-26-modernization-final.md`。

skillOverrides（2026-09-26）: owner の指示で、live の `~/.claude/settings.json` で off だった gh-review、gh-index、python-refactor-analysis を user-invocable-only に変えた（§6.5。D5 により live が正本）。

## 反映状況

| ID | 反映する Phase | 状態（2026-09-25） |
|---|---|---|
| D3 | ① ② 出力停止 ④: Phase 1 / ② 登録解除: Phase 7 / ④ の gate: Phase 4 | ①②④: Phase 1 で反映。④ の gate は Phase 4 branch。② の登録解除は Phase 7 branch で準備（script と test も削除。managed の適用待ち） |
| D4 | 統合: Phase 1 / 撤去: owner / WARN: Phase 3 | 統合: 反映済み。撤去: 2026-09-25 に実施（`~/.local/state/agents-toolkit/backup/` へ退避）。WARN: Phase 3 の discovery で実装 |
| D2 | routing 表の作成: Phase 2 / env pin の導入と該当行の commit: Phase 7 | routing 表: Phase 2 で作成。env pin: Phase 7 branch で managed に4つ入れ、routing 表に claude-alias-* の4行を加えた（managed の適用待ち） |
| D5 | discovery の WARN / FAIL: Phase 3 / settings と manifest: Phase 7 | Phase 7 branch で `claude/settings.json` を削除し、manifest の link を外した（P7-Q2）。discovery は live の symlink を旧構成として WARN し、`autoMemoryEnabled` は managed を優先して FAIL で監視する。effort は D9 に従い owner が live の `modelSettings` で設定する |
| D6 | Phase 1 | Phase 1 branch で反映（live 未反映。`~/.claude/skills/plan-review` の link 削除は owner） |
| D10 | Phase 1 | Phase 1 branch で反映（live 未反映） |
| D11 | 上流版への復帰: owner / `--resume-last` 不使用の確認: Phase 1 | 不使用を確認し、gh-codex-drive と gh-roadmap-drive に明記した（Phase 1 branch）。上流版への復帰は owner |
| OD-1 | routing 表の targets（claude-main、claude-workflow-worker）: Phase 2 | Phase 2 branch で反映。`claude/CLAUDE.md` の lead の行と worker の行を分け、それぞれを routing 表の target にした（決定の内容は変えていない） |
| OD-5 | launcher の変更（D8）: Phase 4 / codex-rescue 禁止文の削除と managed deny: Phase 7 | launcher の変更は Phase 4 branch。managed の deny `Agent(codex:codex-rescue)` と `claude/CLAUDE.md` の禁止文の削除は Phase 7 branch で準備（K3 は integration で確認） |
| D7 | Phase 6 | Phase 6 branch で静的な部分を実装（live 未反映。phase-4 の上に作ったので、phase-4 の後に取り込む）。route は divergent-claude が opus、divergent-codex が gpt-6-astra/medium、`skill-authority.tsv` の egress 列は別の model provider への送信を表す（いずれも 2026-09-25、この作業 session で owner が選択）。K18 は静的には使える（2.1.282 に `agent()` の `opts.disallowedTools` が実装されている。model 向けの API 説明には載っていない）。integration（mini、2026-09-25）で C.5 の7項目と K18 の実行時の確認が PASS した（`docs/reports/2026-09-25-integration-phase4.md`） |
| D8 | Phase 4 | Phase 4 branch で実装し、integration で検証した（委任1件、`stopped`、K11）。K17 により companion は profile 相当を渡せないので、exec の launcher を維持する（2026-09-25）。live はまだ companion のまま |
| D12 | Phase 4 と Phase 5 の integration での試験 | Phase 4: Claude 約 1.7 USD（上限 15 USD）、Codex 5回。Phase 6: K18 約 0.08 USD、C.5 約 3.18 USD（owner がこの1回に限り 3 USD まで許可、推定で超過）、Codex 1回。Phase 5: Claude 約 37.3 USD（上限 60 USD。owner が1回の上限を 4 USD に引き上げた）、Codex は実装担当 22回と explorer 6回（`docs/reports/2026-09-26-routing-eval.md`）。Phase 8: K15 の確認に Codex 2回（Claude は使っていない）。Phase 8 の後: K8 約 2.53 USD（上限 4 USD）、K3 約 0.15 USD |
| OD-7 | D9 で置き換える: Phase 7 | repo の `effortLevel: xhigh` は `claude/settings.json` とともに削除（P7-Q2）。D9（2026-09-26）により、owner が live の `modelSettings` をモデルの既定値（Opus 5.5 は medium）に設定する |
