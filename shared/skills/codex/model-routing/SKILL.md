---
name: model-routing
description: Use when making a high-risk decision（アーキテクチャ・データ破壊・公開 API に関わる判断）, when a Claude opinion is needed, when running or monitoring a Claude peer session, or when verifying which model a subagent actually used. Codex側の owner 選択とルーティングの詳細運用規則。
---

# Model Routing 運用規則（詳細）

既定は「必要十分な単一 owner が完遂」であり、subagentはユーザーの明示依頼または適用skill・AGENTS.mdが要求する場合だけ使う。現行Codexはbuilt-in `default`・`worker`・`explorer`と、`~/.codex/agents/*.toml`またはprojectの`.codex/agents/*.toml`に置くnamed custom agentをサポートする。

- 停止条件: named agentが見つからない、またはmodel割当の変更が必要な場合は、fallbackせずに報告して止まる
- 完了条件: 実際に使われたmodel・effortをsession logの`turn_context`で確認して報告した時点

## Model割り当て

- built-in `default`・`worker`: `[agents]`の既定model・effort（AGENTS.mdに記載）
- `explorer`: read-only探索
- `plan_reviewer`: read-only計画review（`$plan-review`が起動する）
- named agentのmodel・effortは各agent file（`~/.codex/agents/*.toml`）に従う。値の正本はtoolkitのrouting表である

custom agent fileの`model`・`model_reasoning_effort`を最優先し、次にspawn時の明示値、`[agents]` default、親設定の順で解決する。custom agent利用時にper-spawn modelを重ねず、agent fileの指定を尊重する。
named custom agentをspawnする場合はfull-history forkを併用せず、必要なcontextをpromptへ明示する。現行runtimeはcustom `agent_type`とfull-history forkの同時指定をrejectする。

## 高リスク判断

- 失敗が反復する・根本原因が不明・競合する複数仮説がある場合も、判断はownerが行う。判断を別のagentへ委任しない
- 独立した意見が必要な場合だけ、`claude-second-opinion` skill経由でClaudeに相談する。ownerの暫定結論は見せず、問題とcontextだけを渡す
- ownerが自分の結論とClaudeの回答を統合する（相違点と採否理由を明示）
- 高リスク変更（アーキテクチャ・データ破壊・公開 API）は、実装後に `codex review`（独立コンテキストの検査）+ deterministic CI で判定する

## Claude 運用

- `claude-second-opinion` skill（`~/.agents/skills/claude-second-opinion/`）を使い、Claude Code へ相談する
- 妥当な待機で結果が得られなければownerの判断だけで結論を出し、「peer opinion欠落」と明記する
- Claude の役割は peer engineer（実装の下請けでもレビュアーでもない）

## 既存経路が優先

- PR へのレビューコメント投稿 → ユーザーの明示指示で `$gh-pr --review-comment`（`codex review` ベース）
- PR 指摘への対応 → `$gh-review`
- 計画レビュー → `$plan-review`（`plan_reviewer`による独立review）
- generic code/security review → 組み込みの`codex review`（TUIでは`/review`）
- ドメイン固有の高リスク判断（コントラクト監査・ML品質監査等）: ownerが該当分野の判断基準を明示して判断する

generic `default`・`worker`への委任はこれらの代替ではない。

## ルーティングの検証（モデル自己申告は証明にならない）

- session logの`session_meta.source.subagent.thread_spawn`で対象childとparentを特定し、childの`turn_context.model`・`turn_context.effort`を確認する。message本文は検証に使わない
- routing異常時は`~/.codex/config.toml`の`[agents]` default、custom agent file、spawn時の明示値、CLI overrideの順に確認する
- `max_concurrent_threads_per_session`を使う。`max_threads`はlegacy aliasであり、`max_depth`はV1でのみ有効、V2では無視される
- named agentが見つからない場合は汎用agentへsilent fallbackせず、install状態を報告する
