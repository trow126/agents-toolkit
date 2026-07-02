---
name: model-routing
description: Use when making a high-risk delegation decision（アーキテクチャ・データ破壊・公開 API に関わる判断）, when parallel advisory opinions are needed (deep-reasoner + Codex), when running or monitoring a Codex peer session, or when verifying which model a subagent actually used. CLAUDE.md のモデル役割分担の詳細運用規則。
user-invocable: true
---

# Model Routing 運用規則（詳細）

CLAUDE.md「モデル役割分担」の要約テーブルを補完する詳細手順。委任の基本方針は CLAUDE.md 側が正。

## 高リスク判断の並列諮問

- `deep-reasoner` 起動と `/codex:adversarial-review`（設計検証）または `codex-rescue` エージェント起動を並行発行する
- **互いの回答を見せず** Fable が統合する（相違点と採否理由を明示）

## Codex 運用

- Codex 実行はバックグラウンドになりうる（`/codex:status` で監視、`/codex:result` で取得）
- 妥当な待機で結果が得られなければ Opus の回答のみを用いて Fable が統合し、結論に「peer opinion 欠落」と明記する
- Codex の役割は peer engineer（実装の下請けでもレビュアーでもない）
- 接続・認証に問題があれば `/codex:setup` で確認する

## 既存経路が優先

- PR レビュー → `pr-review` スキル（Post-PRコメント型規約）
- 計画レビュー → `/plan-review`
- コントラクト監査 → `blockchain-security-auditor`
- ML 監査 → `model-qa-specialist`

`deep-reasoner` はこれらの代替ではない。

## ルーティングの検証（モデル自己申告は証明にならない）

- エージェント起動表示の model 欄
- transcript（`~/.claude/projects/` の JSONL にある assistant メッセージの `model` フィールド）
- `session-report` スキル / usage dashboard
- routing 異常時は `CLAUDE_CODE_SUBAGENT_MODEL` 環境変数を最初に確認する（設定されていると全 frontmatter pin を上書きする仕様）
