# agents-toolkit 構造移行: entry分類表

`claude/`・`codex/`・`shared/` 直下（tracked/untrackedが混在するdirectoryは第2階層まで）の全entryを
`source`・`runtime`・`private overlay`・`archive/delete candidate` に分類する。
[構造更新計画](../plans/2026-07-21-agents-toolkit-structure-update-plan.md) Phase 1の成果物。

判定方法: `source` は `git ls-files` で追跡されているかどうか、`runtime`/`private overlay`/`archive` は
`.gitignore` の分類コメントと実体の性質（credentials・session・cache・生成物か、保持すべきmachine固有設定か）で判断した。

## claude/

| entry | 分類 | migration時の扱い | 判断根拠 |
|---|---|---|---|
| `claude/.claudeignore` | source | stays in repo | git追跡された起動scanの除外設定 |
| `claude/.gitignore` | source | stays in repo | git追跡されたignore定義 |
| `claude/CLAUDE.md` | source | stays in repo | git追跡された常時規約 |
| `claude/LICENSE` | source | 完了済み: root `LICENSE` へ移動済み（`claude/LICENSE`は現存しない） | Phase 5作業により`git mv`相当で移動済みと現物確認（`ls`で不在、root `LICENSE`存在を確認） |
| `claude/README.md` | source | stays in repo | git追跡されたドキュメント |
| `claude/settings.json` | source | stays in repo | git追跡された共有設定 |
| `claude/statusline.sh` | source | stays in repo | git追跡されたscript |
| `claude/agents/` | source | stays in repo | 14ファイル全てgit追跡（agent定義） |
| `claude/bin/` | source | stays in repo | 7ファイル全てgit追跡（helper script） |
| `claude/githooks/` | source | stays in repo | git追跡されたgitleaks pre-commit hook |
| `claude/hooks/` | source | stays in repo | 9ファイル全てgit追跡。`*.original`退避ファイルは現状未生成 |
| `claude/output-styles/` | source | stays in repo | 4ファイル全てgit追跡 |
| `claude/rules/` | source | stays in repo | 7ファイル全てgit追跡（path-scoped rules） |
| `claude/scripts/` | source | stays in repo | 1ファイルgit追跡 |
| `claude/skills/`（下記混在4件を除く） | source | stays in repo | 大部分のskillはSKILL.md等がgit追跡されたsource一式 |
| `claude/skills/config-audit/audit-history.jsonl` | runtime | move to XDG state (`${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/config-audit/`) | `.gitignore`に「machine-local tracking data」と明記された生成物 |
| `claude/skills/knowledge-audit/promotion-candidates.md` | runtime | move to XDG state (`${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/knowledge-audit/`) | `.gitignore`に明記されたskill生成物 |
| `claude/skills/python-refactor-analysis/.analysis/` | runtime | move to XDG state (`${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/python-refactor-analysis/`) | `.gitignore`に明記された解析結果生成物。現状ディレクトリ自体は未生成 |
| `claude/skills/x-article-to-markdown/__pycache__/` | archive/delete candidate | delete（再生成可能なPythonバイトコードcache、移行対象外） | git非追跡・`__pycache__`は実行時に再生成される |
| `claude/claudedocs/2026-07-13-*.md` | source | 完了済み: `docs/archive/2026-07-13-agents-toolkit-monorepo-migration-plan.md` へ移動済み | Phase 5作業により移動済みと現物確認（`docs/archive/`配下に存在、`claude/claudedocs/`直下には不在） |
| `claude/claudedocs/reviews/` | runtime | move to real dir | plan-reviewスキルの書き込み先は`~/.claude/claudedocs/reviews/`（スキルパッケージ外）で、cutover後は実directory側の同pathに書かれ続ける。XDG stateへ移すとskillの読み書き先と実体が食い違うためrealディレクトリへ残す。`claudedocs`自体はmanifestのlink対象にしない前提 |
| `claude/.github/workflows/sync-issues-to-project.yml` | archive/delete candidate | 完了済み: `docs/archive/sync-issues-to-project.yml.disabled` へarchive・無効化済み | Phase 5作業によりarchive済みと現物確認（`claude/.github/`配下には不在、`docs/archive/`に`.disabled`拡張子で存在） |
| `claude/CLAUDE.local.md` | private routing | move to XDG config | user-levelの`~/.claude/CLAUDE.local.md`はClaude Codeのdocumented load pathではない。`${XDG_CONFIG_HOME:-$HOME/.config}/agents-toolkit/private-routing.md`へ移し、存在時だけ明示参照する（2026-07-23 近代化で project-orchestrator agent は削除。消費契約は claude/CLAUDE.md「private routing」節が定義: specialist 選択時に owner が存在確認して参照する opt-in active config）。project固有指示は各project rootの`CLAUDE.local.md`へ置く |
| `claude/settings.local.json` | private overlay | move to real dir | vendorが`~/.claude/settings.local.json`を実pathで読むmachine固有settings override。cutover後のrepoはsource専用になるため実directoryへ移す。外部overlay（`~/.config/agents-toolkit/overlay`）管理へ昇格するかは後続のユーザー判断 |
| `claude/.credentials.json` | runtime | move to real dir | OAuth credentials本体。secret値のため repo配下に置くべきでない |
| `claude/history.jsonl` | runtime | move to real dir | 会話履歴（4MB超）、`.gitignore`でsession/temporaryデータと明記 |
| `claude/stats-cache.json` | runtime | move to real dir | `.gitignore`明記のsession cache |
| `claude/gh-pr-status-cache.json` | runtime | move to real dir | `.gitignore`明記のruntime cache |
| `claude/.last-update-result.json` | runtime | move to real dir | `.gitignore`明記のauto-generated runtime data |
| `claude/.last-cleanup` | runtime | move to real dir | `.gitignore`明記のruntime marker |
| `claude/daemon.log` | runtime | move to real dir | `.gitignore`明記のruntime log |
| `claude/daemon.lock` | runtime | move to real dir | `.gitignore`明記のruntime lock |
| `claude/daemon.status.json` | runtime | move to real dir | `.gitignore`明記のruntime status |
| `claude/backups/` | runtime | move to real dir | `.gitignore`明記のsession/temporaryデータ |
| `claude/cache/` | runtime | move to real dir | `.gitignore`明記のcache |
| `claude/daemon/` | runtime | move to real dir | daemon実行時状態 |
| `claude/debug/` | runtime | move to real dir | `.gitignore`明記のdebugデータ |
| `claude/downloads/` | runtime | move to real dir | `.gitignore`明記のruntimeデータ |
| `claude/file-history/` | runtime | move to real dir | `.gitignore`明記のsession/temporaryデータ |
| `claude/ide/` | runtime | move to real dir | `.gitignore`明記のruntimeデータ |
| `claude/jobs/` | runtime | move to real dir | `.gitignore`明記のruntime生成物 |
| `claude/paste-cache/` | runtime | move to real dir | `.gitignore`明記のsession/temporaryデータ |
| `claude/plans/` | runtime | move to real dir | `.gitignore`明記のruntime生成物（plan mode出力） |
| `claude/plugins/` | runtime | move to real dir | `.gitignore`明記のplugin cache |
| `claude/projects/` | runtime | move to real dir | `.gitignore`明記のsession/memoryデータ |
| `claude/remote/` | runtime | move to real dir | `.gitignore`明記のruntime生成物 |
| `claude/session-env/` | runtime | move to real dir | `.gitignore`明記のsession/temporaryデータ |
| `claude/sessions/` | runtime | move to real dir | `.gitignore`明記のsession/temporaryデータ |
| `claude/shell-snapshots/` | runtime | move to real dir | `.gitignore`明記のsession/temporaryデータ |
| `claude/tasks/` | runtime | move to real dir | `.gitignore`明記のruntime生成物 |
| `claude/teams/` | runtime | move to real dir | `.gitignore`明記のagent teams runtime状態 |
| `claude/tmp/` | runtime | move to real dir | `.gitignore`明記のsession/temporaryデータ |
| `claude/.agents/` | archive/delete candidate | archive | 中身空・git非追跡・用途不明の残存directory |
| `claude/.codex/` | archive/delete candidate | archive | 中身空・git非追跡・用途不明の残存directory |

## codex/

| entry | 分類 | migration時の扱い | 判断根拠 |
|---|---|---|---|
| `codex/AGENTS.md` | source | stays in repo | allowlistでgit追跡された常時規約 |
| `codex/herdr-agent-state.sh` | source | stays in repo | allowlistでgit追跡されたscript |
| `codex/hooks.json` | source | stays in repo | allowlistでgit追跡された設定 |
| `codex/rules/issue_completeness_policy.md` | archive/delete candidate | 完了済み: 廃止・削除済み（`codex/rules/`配下に現存しない） | Phase 5作業により削除済みと現物確認（`find`で該当なし、`git status`上も削除記録） |
| `codex/rules/default.rules` | private overlay | move to real dir | vendorが`~/.codex/rules/default.rules`を実pathで読むmachine固有承認キャッシュ。cutover後のrepoはsource専用になるため実directoryへ移す。外部overlay（`~/.config/agents-toolkit/overlay`）管理へ昇格するかは後続のユーザー判断 |
| `codex/skills/claude-second-opinion/` | source | stays in repo | allowlistでgit追跡されたskill一式 |
| `codex/skills/doctor/` | source | stays in repo | allowlistでgit追跡されたskill一式 |
| `codex/skills/issue-writing/` | source | stays in repo | allowlistでgit追跡されたskill一式 |
| `codex/skills/kaggle/`（`shared/__pycache__`を除く） | source | stays in repo | allowlistでgit追跡されたskill一式 |
| `codex/skills/kaggle/shared/__pycache__/` | archive/delete candidate | delete（再生成可能なPythonバイトコードcache、移行対象外） | git非追跡・実行時に再生成される |
| `codex/skills/.system/` | runtime | move to real dir | allowlist対象外で自動除外される、Codex CLI管理の未監査/組み込みskill directory |
| `codex/auth.json` | runtime | move to real dir | OAuth credentials本体。二重防御でも明示除外 |
| `codex/config.toml` | private overlay | move to real dir | vendorが`~/.codex/config.toml`を実pathで読むmachine固有の動作設定（model/profile等）。cutover後のrepoはsource専用になるため実directoryへ移す。外部overlay（`~/.config/agents-toolkit/overlay`）管理へ昇格するかは後続のユーザー判断 |
| `codex/gh.config.toml` | private overlay | move to real dir | vendorが`~/.codex/gh.config.toml`を実pathで読むGitHub CLI連携のmachine固有設定。cutover後のrepoはsource専用になるため実directoryへ移す。外部overlay（`~/.config/agents-toolkit/overlay`）管理へ昇格するかは後続のユーザー判断 |
| `codex/goals_1.sqlite` | runtime | move to real dir | 二重防御でも明示除外されたSQLite runtime state |
| `codex/logs_2.sqlite`, `codex/logs_2.sqlite-shm`, `codex/logs_2.sqlite-wal` | runtime | move to real dir | 二重防御でも明示除外されたSQLite runtime log（86MB超） |
| `codex/memories_1.sqlite` | runtime | move to real dir | 二重防御でも明示除外されたmemory SQLite |
| `codex/state_5.sqlite` | runtime | move to real dir | 二重防御でも明示除外されたSQLite runtime state |
| `codex/history.jsonl` | runtime | move to real dir | 二重防御でも明示除外された会話履歴 |
| `codex/session_index.jsonl` | runtime | move to real dir | 二重防御でも明示除外されたsession index |
| `codex/installation_id` | runtime | move to real dir | 二重防御でも明示除外されたinstallation識別子 |
| `codex/models_cache.json` | runtime | move to real dir | modelメタデータcache |
| `codex/version.json` | runtime | move to real dir | runtime version marker |
| `codex/.personality_migration` | runtime | move to real dir | Codex CLI内部migration marker |
| `codex/backups/` | runtime | move to real dir | 旧config自動backup |
| `codex/cache/` | runtime | move to real dir | runtime cache |
| `codex/ipc/` | runtime | move to real dir | 実行時IPC socket/state |
| `codex/log/` | runtime | move to real dir | runtime log |
| `codex/memories/` | runtime | move to real dir | memory runtime state |
| `codex/plugins/` | runtime | move to real dir | plugin cache |
| `codex/sessions/` | runtime | move to real dir | session runtime data |
| `codex/shell_snapshots/` | runtime | move to real dir | shell snapshot runtime data |
| `codex/tmp/` | runtime | move to real dir | 一時ファイル |
| `codex/.tmp/` | runtime | move to real dir | plugin syncの一時clone/lock（`plugins/.git`を含む） |

## shared/

| entry | 分類 | migration時の扱い | 判断根拠 |
|---|---|---|---|
| `shared/bin/sync-shared-rules.sh` | source | stays in repo | git追跡されたscript |
| `shared/rules/` | source | stays in repo | 16ファイル全てgit追跡された共有rules正本 |
| `shared/skills/agmsg/`（`db/`・`run/`・`teams/`を除く: `SKILL.md`・`VERSION`・`.agmsg`・`agents/`・`scripts/`・`templates/`） | source | stays in repo | git追跡されたskill一式 |
| `shared/skills/agmsg/db/` | runtime | move to XDG state (`${XDG_STATE_HOME:-$HOME/.local/state}/agmsg`) | `.gitignore`に「agmsg スキルのランタイム状態」と明記されたDB |
| `shared/skills/agmsg/run/` | runtime | move to XDG state (`${XDG_STATE_HOME:-$HOME/.local/state}/agmsg`) | `.gitignore`に明記されたruntime lock/socket |
| `shared/skills/agmsg/teams/` | runtime | move to XDG state (`${XDG_STATE_HOME:-$HOME/.local/state}/agmsg`) | `.gitignore`に明記されたteam runtime状態 |

## 分類サマリ

| 分類 | claude/ | codex/ | shared/ | 合計 |
|---|---|---|---|---|
| source | 16 | 7 | 3 | 26 |
| runtime | 32 | 22 | 3 | 57 |
| private overlay | 2 | 3 | 0 | 5 |
| archive/delete candidate | 4 | 2 | 0 | 6 |

## live migrationの停止条件

以下のいずれかに該当する場合、live migration（Phase 4のcutover）を実行しない。

- **未分類entryの存在**: `claude/`・`codex/`・`shared/` 直下（または混在が判明した第2階層）に、この分類表へ記載されていないentryが1つでも存在する。
- **書き込み可能なsource directoryへのruntime writer残存**: `source`分類のdirectory配下に、実行時に書き込まれるfile（新規untracked file・変更されたtracked file以外の生成物）が確認される。特に`claude/skills/`・`codex/skills/`・`shared/skills/agmsg/`配下は、round-trip testで新規runtime fileが生成されないことを確認するまで対象外とする。
- **移動先容量不足**: `${XDG_STATE_HOME:-$HOME/.local/state}` および実directory移行先のfilesystemに、移行対象runtimeの総容量（`claude/`約947M、`codex/`約490M）を超える空き容量がない。
- **symlink構成が想定と異なる**: `~/.claude`・`~/.codex`・`~/.agents` が、それぞれ`<repo>/claude`・`<repo>/codex`・`<repo>/shared`を指すsymlink以外（実directory・別pathへのsymlink・存在しない等）になっている。
- **activeなsessionの存在**: Claude Code・Codex CLI・agmsgのいずれかが起動中（プロセス・lock file・活動中socketの存在）である。
