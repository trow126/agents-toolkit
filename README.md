# agents-toolkit

AI エージェント設定の一元管理モノレポ(旧 claude-toolkit)。

## レイアウト

`claude/`・`codex/`・`shared/` は **source 専用**のディレクトリで、`~/.claude`・`~/.codex`・`~/.agents` に丸ごと symlink されることはない。`~/.claude` 等は実ディレクトリであり、`install/manifest.tsv` に列挙された個別ファイル・サブディレクトリだけが symlink される(詳細は後述のインストーラ節を参照)。

| ディレクトリ | 内容 | 実ディレクトリへの反映方法 |
|---|---|---|
| `claude/` | Claude Code 設定 source | `install/manifest.tsv` の各行が `~/.claude/` 配下へ個別 symlink |
| `codex/` | Codex CLI 設定 source | 同上(`~/.codex/` 配下) |
| `shared/` | エージェント横断の共有ルール正本 + `agmsg` skill source | 同上(`~/.agents/` 配下) |

credentials・sessions・cache・history 等の runtime データは source tree には入らず、各 vendor の実ディレクトリ(`~/.claude`・`~/.codex` 配下)へ直接書き込まれる。`agmsg` の DB/run/team 状態と skill の解析結果等の生成物は XDG state(`${XDG_STATE_HOME:-$HOME/.local/state}/agmsg/`、`${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/<skill-name>/`)へ書き込まれる。

## セットアップ(新マシン)

```bash
git clone https://github.com/trow126/agents-toolkit.git ~/agents-toolkit
cd ~/agents-toolkit
./bootstrap.sh --apply
```

## 既存マシンの移行(旧 whole-directory symlink 構成から)

`~/.claude`・`~/.codex`・`~/.agents` が repo を丸ごと指す symlink になっている旧構成のマシンでは、以下の手順で新構成へ移行する。

1. Claude Code・Codex CLI・`agmsg` のセッションをすべて終了する
2. `./scripts/migrate-layout.sh --dry-run` で移動計画を確認する(変更なし)
3. `./scripts/migrate-layout.sh --apply` を実行する。runtime データを実ディレクトリ/XDG state へ移し、`bootstrap.sh --apply` まで自動実行する(途中失敗時は自動 rollback)
4. 手動で rollback する場合は、`--apply` 実行時に出力される staging ディレクトリ(`$HOME/.agents-toolkit-migration-<timestamp>/`)内の `rollback.sh` を実行する: `bash <staging>/rollback.sh`

## インストーラ(`bootstrap.sh`)

```
Usage: bootstrap.sh [--check|--dry-run|--apply] [--overlay PATH]
  --check    manifest(+overlay)通りの symlink 状態を検証する(変更なし)
  --dry-run  --apply が行う操作を実行せず列挙する(変更なし)
  --apply    symlink を作成する(既定。引数なしも同じ)
  --overlay PATH  overlay root を明示指定する
```

### private overlay

案件固有のルーティング設定など、公開したくない machine 固有ファイルは公開 repo に置かず、private overlay に置く。overlay root(既定: `${AGENTS_TOOLKIT_OVERLAY:-${XDG_CONFIG_HOME:-$HOME/.config}/agents-toolkit/overlay}`)には公開 repo と同じ schema の `manifest.tsv` を置く。overlay は公開 manifest の後に読み込まれ、target 重複・root 外参照・壊れた source があれば公開設定を上書きせず fail-fast する。**credentials は overlay にも公開 repo にも置かない**(vendor の実ディレクトリまたは keyring に残す)。

## 共有ルールの更新

正本 `shared/rules/*.md` を編集後、`shared/bin/sync-shared-rules.sh --write` を実行して `codex/AGENTS.md` 等の消費先マーカー区間へ同期する(Claude 側は `@~/.agents/rules/*.md` を実行時 import するため同期不要)。ドリフトの検証だけ行う場合は `--check` を使う(差分があれば非ゼロ終了)。

## エージェント追加ルール

1. `<agent>/` ディレクトリを作成する(source 専用。実 config ディレクトリへは反映しない)
2. `install/manifest.tsv` に、追跡したい設定ファイル・ディレクトリごとに `mode<TAB>source<TAB>target` 行を追加する(`mode` は `link-file` または `link-dir`。**ディレクトリ丸ごと symlink は禁止** — runtime writer の混入を防ぐため、source 側で source/runtime を分離してから追加する)
3. ルート `.gitignore` に `<agent>/*` の default-deny + 追跡したい設定ファイルの allowlist を追加する
4. `./scripts/validate-layout.sh` を実行し、manifest 整合・manifest 外の tracked ファイルがないことを確認する

## 既知の例外

`link-dir` で個別 symlink された skill ディレクトリ配下には、Python 実行時に `__pycache__/` が生成されることがある。repo には追跡されないが自動削除もされない(`migrate-layout.sh` は best-effort で警告するのみ)。恒久的に避けたい場合は環境変数 `PYTHONDONTWRITEBYTECODE=1` を設定する。

## CI

`.github/workflows/ci.yml` が push・pull request ごとに、shell/JSON 構文検証・`scripts/validate-layout.sh`・`shared/bin/sync-shared-rules.sh --check`・`tests/test-*.sh`・全履歴 gitleaks スキャンを実行する。

## 注意

- このリポジトリは **public**。私的プロジェクト名・トークン・trust 設定(`codex/config.toml`)を追跡しない
- 新しい設定ファイルを追跡したい場合は、ルート `.gitignore` の allowlist と `install/manifest.tsv` の両方に明示追加する(default-deny のため自動では追跡されない)
- シークレットスキャン: コミット前は `githooks/pre-commit`(gitleaks)、CI では全履歴 gitleaks スキャンを実行する。ローカルのフック有効化手順は [claude/README.md](claude/README.md) を参照。GitHub 側の Secret Scanning + Push Protection も有効化済み
