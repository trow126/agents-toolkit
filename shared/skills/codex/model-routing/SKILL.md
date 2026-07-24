---
name: model-routing
description: Use when making a high-risk delegation decision（アーキテクチャ・データ破壊・公開 API に関わる判断）, when parallel advisory opinions are needed (独立コンテキストの subagent + Claude), when running or monitoring a Claude peer session, or when verifying which model a subagent actually used. Codex側の owner 選択とルーティングの詳細運用規則。
---

# Model Routing 運用規則（詳細）

既定は「必要十分な最小コストの単一 owner が完遂」であり、以下は例外時にだけ使う。Codex には Claude Code の `deep-reasoner`/`code-reviewer`/`plan-reviewer` のような named subagent のレジストリがないため、委任は `codex exec`/`codex review`（独立コンテキストの汎用 subagent、`[agents] max_threads`/`max_depth` で並列数・深さを制御）に役割をプロンプトで与える形で行う。

## エスカレーション経路

- 標準モデルの owner で着手し、失敗が反復する・根本原因が不明・競合する複数仮説がある場合のみ `codex exec` に判断特化のプロンプト（コードは書かせず判定のみ求める）を渡して独立コンテキストで審査させる（判断のみ。実装は owner に戻す）
- 高リスク変更（アーキテクチャ・データ破壊・公開 API）は、実装後に `codex review`（独立コンテキストの検査）+ deterministic CI で判定する

## 高リスク判断の並列諮問

- `codex exec` での判断特化レビューと、`claude-second-opinion` skill 経由の Claude への相談を並行発行する
- **互いの回答を見せず** main が統合する（相違点と採否理由を明示）
- 並列化は独立仮説の比較が必要な場合だけ使う（金額削減ではなく wall-clock 短縮・独立性確保の手段）

## Claude 運用

- `claude-second-opinion` skill（`~/.agents/skills/claude-second-opinion/`）を使い、Claude Code Fable へ相談する
- 妥当な待機で結果が得られなければ `codex exec` の回答のみで統合し、結論に「peer opinion 欠落」と明記する
- Claude の役割は peer engineer（実装の下請けでもレビュアーでもない）

## 既存経路が優先

- PR 作成直後のセルフレビュー → `pr-review` skill（Post-PR コメント型規約、`codex review` ベース）
- PR 指摘への対応 → `$gh-review`
- 計画レビュー → `$plan-review`（`codex exec` による独立レビュー）
- ドメイン固有の高リスク判断（コントラクト監査・ML品質監査等）: Codex には named domain specialist がないため、`codex exec` に該当分野の判断基準をプロンプトで明示するか、Claude 側に該当 specialist（`blockchain-security-auditor`・`model-qa-specialist` 等）がある場合は `claude-second-opinion` 経由で相談する

`codex exec` への一般委任はこれらの代替ではない。

## ルーティングの検証（モデル自己申告は証明にならない）

- `codex debug prompt-input` や実行時のモデル表示
- セッションログ（`~/.codex/sessions/` 配下の rollout JSONL にある実際に使用されたモデル）
- routing 異常時は `~/.codex/config.toml` の `model` / `model_reasoning_effort` 設定と `-c model=...` オーバーライドの有無を最初に確認する（CLIオーバーライドは設定ファイルの値を上書きする仕様）
