# agents-toolkit

AI エージェント設定の一元管理モノレポ(旧 claude-toolkit)。

## レイアウト

| ディレクトリ | 実体の利用パス | 内容 |
|---|---|---|
| `claude/` | `~/.claude` (symlink) | Claude Code 設定。runtime 除外は `claude/.gitignore` |
| `codex/` | `~/.codex` (symlink) | Codex CLI 設定。ルート `.gitignore` の whitelist 方式で default-deny |
| `shared/` | `~/.agents` (symlink) | エージェント横断の共有ルール正本 + sync スクリプト |

## セットアップ(新マシン)

```bash
git clone https://github.com/trow126/agents-toolkit.git ~/agents-toolkit
bash ~/agents-toolkit/bootstrap.sh
```

## 共有ルールの更新

正本 `shared/rules/*.md` を編集後、`shared/bin/sync-shared-rules.sh` を実行して
`codex/AGENTS.md` のマーカー区間へ同期する(Claude 側は `@~/.agents/rules/*.md` を実行時 import)。

## エージェント追加ルール

1. `<agent>/` ディレクトリを作成し、config ディレクトリを**丸ごと** symlink する(per-file symlink は設定ファイル追加に追随できないため禁止)
2. ルート `.gitignore` に `<agent>/*` の default-deny + 設定ファイルの allowlist を追加
3. `bootstrap.sh` に `link` を1行追加

## 注意

- このリポジトリは **public**。私的プロジェクト名・トークン・trust 設定(`codex/config.toml`)を追跡しない
- 新しい設定ファイルを追跡したい場合はルート `.gitignore` の allowlist に明示追加する(default-deny のため自動では追跡されない)
