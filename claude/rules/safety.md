# 安全性ルール（Claude Code 固有）

<!-- 障害調査は共有正本 ~/.agents/rules/failure-investigation.md、フレームワークの尊重は karpathy-guidelines.md §3 に統合済み（2026-07-23） -->

## Claude Code 運用

- `~/.claude/settings.json` および各プロジェクトの `.claude/settings.local.json` は Claude セッション内で直接編集しない。shell で編集してから Claude を再起動する

## 複合コマンド

- 現行仕様では Claude Code は `&&` `||` `;` `|` `|&` `&` 改行の各 separator を認識し、subcommand ごとに独立して permission 判定する（旧「先頭コマンドのみ判定」issue #16180 を security 根拠にしない。確認日 2026-07-23）
- 可読性・ログ・失敗箇所の分離のため、長い複合 chain は必要時だけ使う（style 方針であり security 要件ではない）
- 独立した操作にはパラレルツールコールを使用する
- ネイティブツールを使用する: `grep` より Grep、`find` より Glob、`cat` より Read
