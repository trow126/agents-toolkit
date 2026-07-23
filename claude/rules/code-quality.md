# コード品質ルール（Claude Code 固有）

## コード構成

- 言語/フレームワークの命名規則に従い、既存のプロジェクト構成パターンに合わせる（同一プロジェクト内で混在させない）

## 品質ゲート

- 実装前に共有 learnings（`~/.agents/rules/learnings.md`）を確認する
- 型安全性: ゼロ除算、空配列、None ハンドリング、インデックス境界
- タスク完了前に lint/typecheck を実行し、完了報告には実行した検証の実出力を含める
- 言語固有ゲート（Ruff・Markdown 空行）は paths スコープ付き `rules/python.md` / `rules/markdown.md` に定義済み

## プロジェクト記録

- プロジェクト固有の教訓は `claudedocs/learnings.md`、Claude 固有ドキュメントは `claudedocs/` に置く（対応 Issue クローズ後の `claudedocs/brainstorm/*.md` は削除する）
- 外部 memory 操作・共有ルール更新は自動実行しない。記録先の判断と承認境界は共有正本 `~/.agents/rules/self-improvement.md` に従う
