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
- マージ規則: **scalar 値は高優先スコープが override** し、**array-valued settings は一般にスコープ間で連結・重複排除**される。permission rules（allow/ask/deny）だけでなく、`sandbox.filesystem.allowWrite` 等の filesystem arrays、`sandbox.credentials` の deny arrays、network arrays も連結される（＝低優先スコープの deny/ask は高優先スコープから除去できない。feature 固有の例外は当該公式仕様を優先）
- 運用方針: 許可は user settings `~/.claude/settings.json` に一元管理、プロジェクト側は permissions なしで運用
