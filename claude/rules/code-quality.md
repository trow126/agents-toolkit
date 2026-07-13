# コード品質ルール

## 共有正本の適用（CLAUDE.md で import 済み）
- No Fallback: `~/.agents/rules/no-fallback.md`
- 実装スコープと完全性: `~/.agents/rules/scope-discipline.md`
- テスト方針: `~/.agents/rules/test-policy.md`

## コード構成
- 言語/フレームワークの命名規則に従う
- 既存のプロジェクト構成パターンに合わせる
- 同一プロジェクト内で命名規則を混在させない

## 実装前品質ゲート
- 実装前に LEARNINGS.md を確認する
- 型安全性: ゼロ除算、空配列、None ハンドリング、インデックス境界
- 言語固有ゲート（Ruff・ログ出力・Markdown 空行）は paths スコープ付き `rules/python.md` / `rules/markdown.md` に定義済み
