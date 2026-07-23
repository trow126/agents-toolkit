# 安全性ルール（Claude Code 固有）

<!-- 障害調査は共有正本 ~/.agents/rules/failure-investigation.md、フレームワークの尊重は karpathy-guidelines.md §3 に統合済み（2026-07-23） -->

## Claude Code 運用

- `~/.claude/settings.json` および各プロジェクトの `.claude/settings.local.json` は Claude セッション内で直接編集しない。shell で編集してから Claude を再起動する

## 複合コマンド

- Bash コマンドで `&&`, `||`, `;`, `|` を避ける
  - 理由: 権限チェックは最初のコマンドにのみ適用され、後続のコマンドは許可リストをバイパスする
  - Ref: https://github.com/anthropics/claude-code/issues/16180 (Open)
- 独立した操作にはパラレルツールコールを使用する
- ネイティブツールを使用する: `grep` より Grep、`find` より Glob、`cat` より Read
