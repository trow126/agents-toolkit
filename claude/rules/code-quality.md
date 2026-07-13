# コード品質ルール

## コード構成
- 言語/フレームワークの命名規則に従う
- 既存のプロジェクト構成パターンに合わせる
- 同一プロジェクト内で命名規則を混在させない

## 実装前品質ゲート
- 実装前に共有 learnings（`~/.agents/rules/learnings.md`）を確認する
- 型安全性: ゼロ除算、空配列、None ハンドリング、インデックス境界
- 言語固有ゲート（Ruff・ログ出力・Markdown 空行）は paths スコープ付き `rules/python.md` / `rules/markdown.md` に定義済み
