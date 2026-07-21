# agents-toolkit 構造更新計画

## Summary

2026-07-21 時点の結論は次のとおり。

- `shared/` に agent-neutral なルール・skill正本を置き、`claude/`・`codex/` に固有設定を置く論理構造は妥当。
- 一方、各directoryを `~/.claude`・`~/.codex`・`~/.agents` へ丸ごとsymlinkする物理構造は不適切。現在もcredentials、sessions、cacheなど約1.4 GBのruntimeが公開repo配下へ入り込んでいる。
- repositoryはPUBLICのまま維持し、案件・machine固有情報は外部のprivate overlayへ分離する。
- `chezmoi` は導入せず、既存の `bootstrap.sh` をmanifest式installerへ発展させる。
- sandbox・approvalの既定値は変更せず、危険な設定を検出して警告する。

この方針は、Codexが `CODEX_HOME` に設定とruntimeを共存させ、user skillの配置先として `~/.agents/skills` を定めていること、Claude Codeも `~/.claude` にcredentials・sessions・pluginsなどを書き込むことに基づく。[Codex best practices](https://learn.chatgpt.com/guides/best-practices)、[Codex環境変数](https://learn.chatgpt.com/docs/config-file/environment-variables)、[Codex skills](https://learn.chatgpt.com/docs/build-skills)、[Claude Code directory](https://code.claude.com/docs/en/claude-directory)、[Claude Code features](https://code.claude.com/docs/en/features-overview)

個別symlinkと冪等bootstrapは [holman/dotfiles](https://github.com/holman/dotfiles)・[thoughtbot/dotfiles](https://github.com/thoughtbot/dotfiles)、source/runtime分離は [chezmoi](https://www.chezmoi.io/user-guide/setup/) と整合する。`git clean -X` はignored fileも削除するため、`.gitignore` はruntime保護境界として扱わない。[git-clean](https://git-scm.com/docs/git-clean.html)

## Implementation Changes

各Phaseは前のPhaseの完了条件を満たしてから着手する。特に、runtimeを書き込むdirectoryを `link-dir` する前に、その書き込み先をsource tree外へ移す。

### Phase 1: 移行前inventoryとrollback基盤

- `claude/`・`codex/`・`shared/` の全entryを `source`・`runtime`・`private overlay`・`archive/delete candidate` に分類し、移行対象表を固定する。
- credentials、sessions、history、cache、logs、plugin cache、memory、SQLite、生成物の現在path・容量・所有権・symlink targetをread-onlyで記録する。内容やsecret値は記録しない。
- 一時HOMEのfixtureで旧whole-directory symlink構成を再現し、runtime保持、途中失敗、rollbackを先にテストできる基盤を作る。
- live migrationの停止条件を、未分類entry、書き込み可能なsource directory、容量不足、異なるsymlink、active Claude/Codex/agmsg sessionとする。

### Phase 2: runtime writerのsource tree外移行

- `agmsg` に `AGMSG_STATE_HOME` を追加し、既定を `${XDG_STATE_HOME:-$HOME/.local/state}/agmsg`、配下を `db/`・`run/`・`teams/` とする。既存の `AGMSG_STORAGE_PATH` はDB限定overrideとして互換維持する。
- skill package内にaudit履歴・解析結果・一時fileを書き込む処理を洗い出し、`${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/<skill-name>/` へ移す。
- `link-dir` は、対象subtreeにruntime writerがないことを検証できる場合だけ許可する。移行できないdirectoryは、state外出しが完了するまで個別の `link-file` とする。
- Phase完了条件を「通常実行とround-trip testの後も、tracked source treeへ新しいruntime fileが生成されないこと」とする。

### Phase 3: manifest installer・overlay・migration tooling

- `install/manifest.tsv` を追加し、各行を `mode<TAB>source<TAB>target` とする。`mode` は `link-file` または検証済みdirectory向けの `link-dir`、`source` はmanifest基準の相対path、`target` は `$HOME` 基準の相対pathに限定する。
- Claudeのrules・agents・hooks・skills、CodexのAGENTS・hooks・user skills、shared rules・`agmsg`をmanifestで明示する。Codex user skillsの実配置先は公式に合わせて `~/.agents/skills/<name>` とする。
- private overlayは `${AGENTS_TOOLKIT_OVERLAY:-${XDG_CONFIG_HOME:-$HOME/.config}/agents-toolkit/overlay}` とし、同じschemaの `manifest.tsv` を持たせる。公開manifestの後に読み込み、target重複・root外参照・壊れたsourceは上書きせずfail-fastする。
- `bootstrap.sh` に `--check`・`--dry-run`・`--apply`・`--overlay PATH` を追加する。引数なしは後方互換のため `--apply` とし、既存実体や異なるsymlinkは自動上書きしない。
- whole-directory symlinkから移行する専用scriptに `--dry-run` と `--apply` を設ける。明示対象だけをtimestamp付きstagingへ同一filesystem上で移動し、操作logと逆操作を生成する。途中失敗時は旧symlink構成へ戻す。
- 一時HOMEでinstallerの冪等性とmigration/rollbackを通すまで、live runtimeへ適用しない。

### Phase 4: live runtime cutover

- Claude/Codex/agmsg sessionをすべて終了した通常shellからmigration scriptを実行し、`~/.claude`・`~/.codex`・`~/.agents` を実directoryへ戻す。
- vendor runtime・credentialsを実directoryへ移し、manifestにある追跡対象だけを個別symlinkする。credentialsはprivate overlayにもrepoにも置かず、vendor runtimeまたはkeyringに残す。
- cutover直後に認証、skill discovery、hook読込、AGENTS/CLAUDE rule chain、agmsg DB/team/historyを確認する。失敗した場合は内容修正を始めず、生成済み逆操作で旧構成へ戻す。
- 稼働中のagent sessionからlive cutoverを実行しない。

### Phase 5: 内容・private境界・source of truthの整理

- `shared/rules/issue-completeness.md` はagent-neutralな完了要件だけに縮小する。全repositoryで必要なCodex側のtriggerと不変条件はglobal正本 `codex/AGENTS.md`（install先 `~/.codex/AGENTS.md`）の同期markerへ置き、正確なIssue見出しや手順は `issue-writing` skillへ集約する。Codexはglobal `~/.codex/AGENTS.md` とGit root以下のproject-level `AGENTS.md`を別layerとして探索する。[OpenAI公式 AGENTS.md discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- 読み込まれていない `codex/rules/issue_completeness_policy.md` は廃止し、shared ruleのconsumer対応をdata化する。同期scriptに `--check` と `--write` を追加し、markerの欠落・重複・逆転を検出してatomic renameする。
- Claudeの常時規約は `CLAUDE.md`・path-scoped rules、手順や大量の参照情報はskills、独立作業はagents、決定的guardrailはhooksへ配置する。
- 案件名・絶対path・案件固有の監査focusを汎用agent定義から外し、外部overlayのon-demand skillまたは各projectの `CLAUDE.local.md` へ保存する。
- staleな旧`claude-toolkit`説明、存在しない`LEARNINGS.md`参照、hard-codedな個人home path、古いmigration文書を更新またはrootの `docs/archive/` へ移す。
- MIT licenseをroot `LICENSE`へ移す。GitHubはrootの標準名をlicense検出対象とする。[GitHub license guidance](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/adding-a-license-to-a-repository)
- `claude/.github/workflows/sync-issues-to-project.yml` はrootへ移すと外部Project自動作成が突然有効になるため、archiveして無効のままにする。別途明示承認があるまでworkflow化しない。

### Phase 6: CI・最終validator・文書化

- root `.github/workflows/ci.yml` を追加し、`permissions: contents: read`、外部Actionのfull commit SHA固定、shell/JSON検証、layout検証、rule同期check、skill tests、全履歴gitleaksを実行する。[GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use)
- `scripts/validate-layout.sh` で、禁止runtime名、credentials、private project名、絶対home path、壊れた参照、未消費shared rule、manifest外のtracked fileを検出する。
- READMEへsource/runtime/overlayの責務、installer interface、migration/rollback、rule更新手順を記載する。
- 現在のsecret scanningとpush protectionは維持する。sandbox・`bypassPermissions`・`danger-full-access` は変更せず、local auditで警告と該当設定sourceを表示する。

## Test Plan

- 一時HOMEで新規install、2回目の冪等実行、異なるsymlink、既存実体、欠損source、重複target、overlayなし・あり・不正pathを検証する。
- migration fixtureでcredentials、sessions、plugins、cache、Codex memories、agmsg DB/team/runが保持され、source treeへruntimeが再生成されないことを確認する。
- `AGMSG_STATE_HOME`、legacy `AGMSG_STORAGE_PATH`、同時writer、既存DB round-tripを検証する。
- shared ruleを意図的に変更したfixtureで `--check` がdriftを検出し、`--write` 後に全consumerが一致することを確認する。
- `bash -n`、`jq`、既存の対象skill test、gitleaks、`git diff --check`を通す。
- cutover後にClaude/Codexの認証、skill discovery、hook読込、AGENTS/CLAUDE rule chain、agmsg履歴を実動確認する。
- `git status --ignored` と `git clean -ndX` で、認証・session・memory・DBがrepo内の削除候補にならないことを受け入れ条件とする。

## Assumptions

- repositoryはPUBLIC・MITのまま維持する。
- private overlayのremote作成や公開は行わない。必要ならユーザーが別途private Git repositoryとして管理する。
- sandbox・approval・plugin有効状態の挙動変更は今回のscope外とし、警告だけ追加する。
- GitHub Project同期workflow、repository設定、branch rulesetなど外部状態は変更しない。
- `claude-second-opinion` の応答品質・semantic validation改善は別タスクとし、本計画では変更しない。
- 実装時も明示依頼なしにcommitしない。
