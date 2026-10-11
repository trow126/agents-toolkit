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
| `gh-codex-drive` | 2026-10-11 除外（Issue #14）。Codex へ実装を委任しない owner 決定。2026-10 の A/B（`docs/eval/sandwich-ab-results.md`・`sandwich-ab-d-results.md`）で REJECT。後継は `gh-test-first`。launcher・gate（`claude/bin` の委任 4 本）と implementer profile は git history にだけ残す |
| `gh-roadmap-drive` | 2026-10-11 除外（Issue #14）。同上。後継は `gh-roadmap-run` |
| `gh-index` | 2026-10-12 除外（owner 決定 D14）。旧 source `shared/skills/gh-index`。両 runtime で利用実績なし。Issue 計画の起点は `gh-roadmap-plan` |
| `knowledge-audit` | 2026-10-12 除外（D14）。旧 source `shared/skills/knowledge-audit`。両 runtime で利用実績なし。唯一の読み手だった `shared/rules/self-improvement.md` も削除し、git history にだけ残す |
| `python-refactor-analysis` | 2026-10-12 除外（D14）。旧 source `shared/skills/python-refactor-analysis`。両 runtime で利用実績なし。CI の pytest step も外した（復元時は `uv run --frozen pytest -q` の step を戻す） |
| `kaggle` | 2026-10-12 除外（D14）。旧 source `codex/skills/kaggle`（Codex 専用）。利用実績なし。復元時は `.gitignore` の `!codex/skills/kaggle/` allowlist も戻す |
| `gh-start` | 2026-10-12 除外（owner 決定 D15）。旧 source `shared/skills/gh-start`。Issue 実装は `gh-test-first`。runtime 契約 test は `tests/test-gh-issue-fetch.sh` へ縮小した（gh-start の静的契約は git history にだけ残す） |
| `gh-pr` | 2026-10-12 除外（D15）。旧 source `shared/skills/gh-pr`。PR へのコメント投稿は `/code-review <PR番号> --comment`（`pr-review-hook.sh` の案内も変更） |
| `gh-review` | 2026-10-12 除外（D15）。旧 source `shared/skills/gh-review` |
| `gh-issue` | 2026-10-12 除外（D15）。旧 source `shared/skills/gh-issue`。`claude/bin/gh-issue-fetch.sh` は gh-test-first・gh-roadmap-run・gh-finish が使うので残す |
| `issue-writing` | 2026-10-12 除外（D15）。旧 source `codex/skills/issue-writing`（両 runtime へ link）。Issue 本文の規則は `~/.agents/rules/issue-completeness.md` と `gh-roadmap-plan templates` が担う。復元時は `.gitignore` の allowlist も戻す |
| `config-audit` | 2026-10-12 除外（D15）。旧 source `shared/skills/claude-code/config-audit`・`shared/skills/codex/config-audit` と共有の `shared/skills/config-audit/references`。archive 内は `claude-code/`・`codex/`・`references/` に分け、symlink はそのまま解決する。skill-pair drift fixture も `skill-pair-drift.diff` として同梱（復元時は `tests/fixtures/skill-pair-drift/config-audit.diff` へ戻し、test の `PAIRS` に加える） |
| `claude-second-opinion` | 2026-10-12 除外（D15）。旧 source `codex/skills/claude-second-opinion`（Codex 専用）。Codex から Claude への相談は CLI 直接。CI の `test-ask-claude.sh` step も外した（復元時は戻す） |
| `doctor` | 2026-10-12 除外（D15）。旧 source `codex/skills/doctor`（Codex 専用）。復元時は `.gitignore` の allowlist も戻す |

`agmsg`（cross-agent messaging skill）は 2026-09-08 に skill 本体ごと削除した（最終利用 2026-06-23、以降 Claude Code / Codex のどちらからも呼ばれていない）。本 archive に退避していた 4 runtime 向け context template も同時に削除し、archive には残していない。

## 復元方法

1. 対象ディレクトリを旧 source（既定は `claude/skills/`。表に旧 source を書いたものはその path）へ戻す（`git mv`）。`bootstrap.sh` の stale link 一覧からも外す
2. `install/manifest.tsv` に `link-dir` 行を追加する
3. `./scripts/validate-layout.sh` と `./bootstrap.sh --check` を確認する

注意: `gh:*` 名は Agent Skills 仕様（name は `a-z0-9-` のみ）に違反するため、復元時は `gh-*` へリネームする。TodoWrite 依存 skill は現行 API（TaskCreate/TaskUpdate）への書き換えが必要。
