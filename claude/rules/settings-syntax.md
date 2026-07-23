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
- documented scope: managed > CLI 引数 > project local（`<project>/.claude/settings.local.json`）> project > user（`~/.claude/settings.json`）。**user-level の `~/.claude/settings.local.json` という scope は存在しない**
- permission rules（allow/ask/deny）はスコープ間で**マージ（連結）**される。それ以外の大半の設定はスカラー値として高優先スコープが**置換**する
- 運用方針: 許可は user settings `~/.claude/settings.json` に一元管理、プロジェクト側は permissions なしで運用
