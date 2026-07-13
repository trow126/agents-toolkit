# agents-toolkit モノレポ統合設計

日付: 2026-07-13
ステータス: 承認済み(Codex + deep-reasoner 並列諮問で検証済み)

## 目的

AI エージェント設定(~/.claude / ~/.codex / ~/.agents)を単一の public リポジトリで一元管理し、将来のエージェント追加に統一パターンで対応できるようにする。

現状の問題: 共有ルール正本 ~/.agents/rules/ と Codex 設定 ~/.codex/ が git 未管理。新マシンで claude-toolkit を clone しても CLAUDE.md の `@~/.agents/rules/*.md` import が解決できず、欠落 import は黙って無視されるため気づけない。

## 決定事項

- 中立モノレポに統合(public、claude-toolkit を rename して履歴保持)
- リポジトリ名: `agents-toolkit`、worktree: `~/agents-toolkit`(native ext4 上、確認済み)
- 接続方式: 全エージェント「ディレクトリ丸ごと symlink + runtime を .gitignore で明示除外」に統一

## 最終形

```
~/agents-toolkit/
├── shared/        ← 現 ~/.agents 丸ごと(rules/, skills/, bin/sync-shared-rules.sh)
├── claude/        ← 現 ~/.claude 丸ごと(109 追跡ファイル + gitignored runtime)
├── codex/         ← 現 ~/.codex 丸ごと(AGENTS.md, hooks.json, rules/, skills/ 等を追跡)
├── bootstrap.sh   ← 冪等 symlink 作成スクリプト(新マシンセットアップ用)
├── .gitignore     ← ルートでエージェント別 runtime glob を明示除外
└── README.md      ← レイアウトとエージェント追加ルールを記載

symlink:
~/.claude → ~/agents-toolkit/claude
~/.agents → ~/agents-toolkit/shared
~/.codex  → ~/agents-toolkit/codex
```

CLAUDE.md の `@~/.agents/rules/*.md` import と sync-shared-rules.sh のパスは symlink 経由で無変更のまま動作する。

## 追跡範囲(public 前提)

- 追跡: 現 claude-toolkit の追跡ファイル一式、shared/ 一式、codex/ の設定ファイル(AGENTS.md, hooks.json, rules/, skills/, herdr-agent-state.sh ※監査後)
- 除外(.gitignore に明示エントリ): codex/config.toml(実プロジェクト名入り trust 設定)、auth.json、gh.config.toml、`*.sqlite*`、sessions/、history.jsonl、memories/、installation_id、log/、logs*、cache/、tmp/、backups/、shell_snapshots/、version.json、goals/state 系
- コミット前監査: codex/AGENTS.md 全文・codex/skills/・herdr-agent-state.sh に私的プロジェクト名・トークン・機微パスがないこと(リポジトリは既に public)

## 必須修正(諮問で検出)

1. **sync-shared-rules.sh の `mv "$tmp" "$target"` → `cp "$tmp" "$target"`**: mv は symlink ターゲットを通常ファイルで置換して symlink を黙って破壊する(deep-reasoner が実測)。丸ごと symlink 方式では AGENTS.md は実ファイルになるため直接のブロッカーではないが、防御的に修正する。

## 移行手順(要点)

1. 未 push commit を push → GitHub 上で claude-toolkit → agents-toolkit に rename(旧 URL は自動リダイレクト)
2. 移行スクリプトを用意(実行はしない)
3. **最終切替は Claude Code・Codex・cron/hooks を全停止した素のシェルから実行**(sqlite-wal の open handle 破損回避): dir 移動 → git mv(content 変更なしの純 rename 単独コミット、`git log --follow` 追従性確保)→ shared/, codex/ 取り込み → symlink 3本作成
4. スモークテスト(バックアップ削除前): Claude 起動で hooks 発火・@import 解決・memory 書込、Codex 起動・設定読込。symlink 化 config dir の realpath 解決問題はここで最終検証
5. ロールバック: symlink 削除 + dir を元の位置に戻すだけ

## エージェント追加ルール(README に記載)

新しいエージェント追加時: `<agent>/` ディレクトリを作成し、config dir を丸ごと symlink + runtime glob を .gitignore に追加 + bootstrap.sh に symlink 1行追加。per-file symlink は使わない(設定ファイル追加に追随できず配布漏れが起きるため)。

## 検証記録(並列諮問)

- Codex(adversarial review): 修正すべき7項目 → per-file symlink 廃止・stow 採用・ext4 確認・履歴監査・明示 gitignore・cron 停止・統一ルール明文化
- deep-reasoner(Opus): 進めてよい+必須修正1件(sync スクリプトの mv バグ、実測)。bare repo + $HOME worktree は誤 `git add -A` の爆発半径を理由に棄却
- 統合判断: ~/.codex 丸ごと symlink 採用により Codex の per-file 懸念と deep-reasoner の mv バグの両方が構造的に解消。symlink 3本のみとなったため stow は不採用(per-file 前提の推奨だった)。CODEX_HOME は実在確認済みだが env 伝播不要な symlink を優先
- 棄却済み代替案: bare repo + $HOME worktree、chezmoi、GNU stow、.agents のみ独立リポジトリ化
