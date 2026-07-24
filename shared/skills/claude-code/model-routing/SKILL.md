---
name: model-routing
description: Use when making a high-risk delegation decision（アーキテクチャ・データ破壊・公開 API に関わる判断）, when parallel advisory opinions are needed (deep-reasoner + Codex), when running or monitoring a Codex peer session, or when verifying which model a subagent actually used. CLAUDE.md「owner 選択とルーティング」の詳細運用規則。
user-invocable: true
---

# Model Routing 運用規則（詳細）

CLAUDE.md「owner 選択とルーティング（コスト方針）」を補完する詳細手順。既定は「必要十分な最小コストの単一 owner が完遂」であり、以下は例外時にだけ使う。

## エスカレーション経路

- 標準モデルの owner で着手し、失敗が反復する・根本原因が不明・競合する複数仮説がある場合のみ `deep-reasoner` に判断を諮る（判断のみ。実装は owner に戻す）
- 高リスク変更（アーキテクチャ・データ破壊・公開 API）は、実装後に `code-reviewer` / `plan-reviewer` の独立検査 + deterministic CI で判定する

## 高リスク判断の並列諮問

- `deep-reasoner` 起動と `/codex:adversarial-review`（設計検証）または `codex-rescue` エージェント起動を並行発行する
- **互いの回答を見せず** main が統合する（相違点と採否理由を明示）
- 並列化は独立仮説の比較が必要な場合だけ使う（金額削減ではなく wall-clock 短縮・独立性確保の手段）

## Codex 運用

- Codex 実行はバックグラウンドになりうる（`/codex:status` で監視、`/codex:result` で取得）
- 妥当な待機で結果が得られなければ deep-reasoner の回答のみで統合し、結論に「peer opinion 欠落」と明記する
- Codex の役割は peer engineer（実装の下請けでもレビュアーでもない）
- 接続・認証に問題があれば `/codex:setup` で確認する

## 既存経路が優先

- PR 作成直後のセルフレビュー → `pr-review` スキル（Post-PR コメント型規約）
- PR 指摘への対応 → `/gh-review`
- 計画レビュー → `/plan-review`（`plan-reviewer` agent）
- コントラクト監査 → `blockchain-security-auditor`
- ML 監査 → `model-qa-specialist`

`deep-reasoner` はこれらの代替ではない。

## ルーティングの検証（モデル自己申告は証明にならない）

- エージェント起動表示の model 欄
- transcript（`~/.claude/projects/` の JSONL にある assistant メッセージの `model` フィールド）
- routing 異常時は `CLAUDE_CODE_SUBAGENT_MODEL` 環境変数を最初に確認する（設定されていると全 frontmatter pin を上書きする仕様）
