---
paths:
  - "**/settings.json"
  - "**/settings.local.json"
---

# Claude Code Settings 構文ルール

## Permission 構文

- `Bash:*`, `Read:*`, `WebFetch:*` は**無効な構文**
- ツール全体を許可するには `"Bash"`, `"Read"` 等（`:*` なし）
- 引数プレフィックスマッチ: `Bash(git *)` (space-star)。`Bash(git:*)` は deprecated
- Ref: https://github.com/anthropics/claude-code/issues/3428

## Settings 階層

- 評価順: deny > ask > allow
- 配列設定はスコープ間でマージされる（仕様）
- プロジェクト `settings.local.json` に permissions があるとグローバルを置換する
- 運用方針: 許可はグローバル `~/.claude/settings.json` に一元管理、プロジェクト側は permissions なしで運用
