---
name: model-routing
description: Use when making a high-risk delegation decision（アーキテクチャ・データ破壊・公開 API に関わる判断）, when parallel advisory opinions are needed (独立コンテキストの subagent + Claude), when running or monitoring a Claude peer session, or when verifying which model a subagent actually used. Codex側の owner 選択とルーティングの詳細運用規則。
---

# Model Routing 運用規則（詳細）

既定は「必要十分な単一 owner が完遂」であり、subagentはユーザーの明示依頼または適用skill・AGENTS.mdが要求する場合だけ使う。現行Codexはbuilt-in `default`・`worker`・`explorer`と、`~/.codex/agents/*.toml`またはprojectの`.codex/agents/*.toml`に置くnamed custom agentをサポートする。

## Model割り当て

- built-in `default`・`worker`: `[agents]`の`gpt-5.6-sol`/`high`
- `explorer`: `gpt-5.6-terra`/`medium`、read-only探索
- `reviewer`: `gpt-5.6-sol`/`high`、read-only code/security review
- `plan_reviewer`: `gpt-5.6-sol`/`high`、read-only計画review
- `deep_reasoner`: `gpt-5.6-sol`/`xhigh`、read-only高risk判断

custom agent fileの`model`・`model_reasoning_effort`を最優先し、次にspawn時の明示値、`[agents]` default、親設定の順で解決する。custom agent利用時にper-spawn modelを重ねず、agent fileの指定を尊重する。
named custom agentをspawnする場合はfull-history forkを併用せず、必要なcontextをpromptへ明示する。現行runtimeはcustom `agent_type`とfull-history forkの同時指定をrejectする。

## エスカレーション経路

- 標準モデルのownerで着手し、失敗が反復する・根本原因が不明・競合する複数仮説がある場合のみ`deep_reasoner`へ判断を委任する（判断のみ。実装はownerに戻す）
- 高リスク変更（アーキテクチャ・データ破壊・公開 API）は、実装後に `codex review`（独立コンテキストの検査）+ deterministic CI で判定する

## 高リスク判断の並列諮問

- `deep_reasoner`と、`claude-second-opinion` skill経由のClaudeへの相談を並行発行する
- **互いの回答を見せず** main が統合する（相違点と採否理由を明示）
- 並列化は独立仮説の比較が必要な場合だけ使う（金額削減ではなく wall-clock 短縮・独立性確保の手段）

## Claude 運用

- `claude-second-opinion` skill（`~/.agents/skills/claude-second-opinion/`）を使い、Claude Code Fable へ相談する
- 妥当な待機で結果が得られなければ`deep_reasoner`の回答のみで統合し、結論に「peer opinion欠落」と明記する
- Claude の役割は peer engineer（実装の下請けでもレビュアーでもない）

## 既存経路が優先

- PR 作成直後のセルフレビュー → `pr-review` skill（Post-PR コメント型規約、`codex review` ベース）
- PR 指摘への対応 → `$gh-review`
- 計画レビュー → `$plan-review`（`plan_reviewer`による独立review）
- generic code/security review → `reviewer`
- ドメイン固有の高リスク判断（コントラクト監査・ML品質監査等）: `deep_reasoner`に該当分野の判断基準を明示するか、Claude側に該当specialistがある場合は`claude-second-opinion`経由で相談する

generic `default`・`worker`への委任はこれらの代替ではない。

## ルーティングの検証（モデル自己申告は証明にならない）

- session logの`session_meta.source.subagent.thread_spawn`で対象childとparentを特定し、childの`turn_context.model`・`turn_context.effort`を確認する。message本文は検証に使わない
- routing異常時は`~/.codex/config.toml`の`[agents]` default、custom agent file、spawn時の明示値、CLI overrideの順に確認する
- `max_concurrent_threads_per_session`を使う。`max_threads`はlegacy aliasであり、`max_depth`はV1でのみ有効、V2では無視される
- named agentが見つからない場合は汎用agentへsilent fallbackせず、install状態を報告する
