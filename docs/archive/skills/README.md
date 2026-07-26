# アーカイブ済み skill

2026-07-23 の近代化（[docs/plans/2026-07-23-agents-toolkit-modernization.md](../../plans/2026-07-23-agents-toolkit-modernization.md)）でアクティブ構成から除外した skill。既存の archive 方針（削除ではなく `docs/archive/` へ退避）に従う。

| skill | 除外根拠 |
|---|---|
| `gh:coderabbit` | settings.json で `off`（利用実績なしの判断済み）。参照していた code-reviewer / security-reviewer は自己完結の統合 code-reviewer agent に置換 |
| `progress-tracker` | `off`。TodoWrite（廃止済み API）依存。進捗管理は built-in タスク管理と gh-start の同期フェーズで代替 |
| `issue-work-logger` | `off`。TodoWrite 依存の常時ログ機構。native auto memory と `claudedocs/learnings.md` で代替 |
| `issue-retrospective` | `off`。retrospective 系の重複（knowledge-audit が learnings の棚卸しを担当） |
| `issue-parser` | `off`。skill 本体は薄い wrapper のため archive。ただし決定論的パーサー `scripts/parse_issue.py` は `gh-issue-fetch.sh` の実行時依存のため `claude/bin/parse_issue.py` へ復帰済み（2026-07-23 レビュー ATK-001 対応。本 archive 内に scripts/ は残っていない） |
| `introspect` | `off`。メタ認知の一般助言のみで検証可能な手順なし |
| `token-efficiency` | `off`。旧 SuperClaude 系の記号圧縮。現行モデル・auto compact で不要 |
| `x-article-to-markdown` | `off`。X API 仕様変動に依存、利用実績なしの判断済み |
| `deep-research-mode` | 自動起動のみの行動修飾で、内容は一般助言（現行モデルの既定動作と重複） |
| `agmsg` runtime adapters（Antigravity、GitHub Copilot CLI、Gemini CLI、OpenCode） | agents-toolkitの正式対応をClaude Code/Codexに限定。汎用transport codeは保持するが、4 runtimeのcontext templateは配布・検証対象外 |

## 復元方法

1. 対象ディレクトリを `claude/skills/` へ戻す（`git mv`）
2. `install/manifest.tsv` に `link-dir` 行を追加する
3. `./scripts/validate-layout.sh` と `./bootstrap.sh --check` を確認する

注意: `gh:*` 名は Agent Skills 仕様（name は `a-z0-9-` のみ）に違反するため、復元時は `gh-*` へリネームする。TodoWrite 依存 skill は現行 API（TaskCreate/TaskUpdate）への書き換えが必要。

`agmsg` adapterを復元する場合は、templateを戻すだけでなく、正式対応runtimeとしてmanifest、consumer contract、deterministic test、実CLI discoveryを追加する。
