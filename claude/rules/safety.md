# 安全性ルール（Claude Code 固有）

<!-- 障害調査は共有正本 ~/.agents/rules/failure-investigation.md、フレームワークの尊重は karpathy-guidelines.md §3 に統合済み（2026-07-23） -->

## Claude Code 運用

- `~/.claude/settings.json` は Claude セッション内で直接編集しない。project / project-local settings へ permission・hook・sandbox を追加しない。owner policy は `claude/managed-settings.json` をレビューし、root-owned managed drop-in へ再導入する
- 現行 owner policy は `bypassPermissions` かつ sandbox 無効。permission deny、ask、sandbox filesystem/network を security boundary とみなさない
- pre-bash hook（`--amend` 共起 deny・`.env` literal 遮断）は **quote 正規化つき heuristic の事故防止層**であり、runtime 構築 path や未知の迂回を完全には遮断しない。Git workflow、シークレット非参照、外部変更の明示承認など上位ルールを直接守る

## 複合コマンド

- 現行仕様では Claude Code は `&&` `||` `;` `|` `|&` `&` 改行の各 separator を認識し、subcommand ごとに独立して permission 判定する（旧「先頭コマンドのみ判定」issue #16180 を security 根拠にしない。確認日 2026-07-23）
- 可読性・ログ・失敗箇所の分離のため、長い複合 chain は必要時だけ使う（style 方針であり security 要件ではない）
