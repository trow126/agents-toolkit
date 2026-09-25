---
name: model-routing
description: Details Claude model assignment, supervision of an explicitly requested Codex delegation, and verification of the model a subagent actually used. Use when verifying routing or diagnosing a routing anomaly. CLAUDE.md「Ownerとrouting」の詳細運用規則。
user-invocable: true
---

# Model Routing 運用規則（詳細）

CLAUDE.md「Ownerとrouting」を補完する詳細手順。既定は「必要十分な最小コストの単一 owner が完遂」であり、以下は例外時にだけ使う。

- 停止条件: model割当の変更や、ユーザーが指示していないCodex委任が必要になったら、実施せずに報告して止まる
- 完了条件: 実際に使われたmodelを一次情報（transcript・workflow記録・companionのstatus）で確認して報告した時点

## Claude model割当

- Fableはmainのlead/advisorとして長期的な方針決定と統合を担当する
- exact-name overrideの`Explore`はfrontmatterのmodelを使い、read-only codebase探索だけを担当する
- dynamic workflowのanonymous workerは、生成scriptの各`agent()`でmodel optionに`opus`を明示する。dynamic workflow専用のglobal default keyはないため、親Fableの暗黙継承に依存しない
- built-in `general-purpose`はmain modelを継承する
- `CLAUDE_CODE_SUBAGENT_MODEL`は2.1.251以降、subagentの既定値として扱われ、全体の上書きには`_FORCE`付きの指定が要る。model割当はCLAUDE.mdとagent frontmatterで管理するため、どちらも設定しない

## 独立した検査と計画review

- Claude側にescalation用のagentは置かない（mainが最上位）
- 高リスク変更（アーキテクチャ・データ破壊・公開 API）は、deterministic CI と `/code-review` で差分を検査する
- 計画reviewはCodex版`plan-review`（ユーザーがCodexで実行する）か`/code-review`を使う

## Codex 委任（ユーザーの明示指示がある場合だけ）

- 委任はユーザーの明示指示（`/gh-codex-drive`・`/gh-roadmap-drive`・文面での委任指示）がある場合だけ行う。Claudeが自分の判断で委任を選ばない
- 委任したCodexは実装担当であり、Claudeは委任・監督・検証・最終統合を担当する
- 起動は`gh-codex-drive`のlaunch recipeに従い、main sessionから`codex-companion.mjs task`を`Bash(run_in_background=true)`で起動する。`codex:codex-rescue` Agentと`/codex:adversarial-review`を委任や諮問の代わりに起動しない
- 監督は`status`・`result`（`/codex:status`・`/codex:result`）で行う
- 検証に失敗したら同じ条件で1回だけ再委任し、2回目も失敗したら選択肢と推奨をユーザーに示す
- 接続・認証に問題があれば `/codex:setup` で確認する

## 既存経路が優先

- PR 作成後のレビュー → `/code-review <PR番号>`。PR へのコメント投稿はユーザーの明示指示で `/gh-pr --review-comment`
- PR 指摘への対応 → `/gh-review`
- 計画レビュー → Codex版`plan-review`か`/code-review`

## ルーティングの検証（モデル自己申告は証明にならない）

- エージェント起動表示の model 欄
- transcript（`~/.claude/projects/` の JSONL にある assistant メッセージの `model` フィールド）
- dynamic workflowは`~/.claude/projects/<project>/<session>/workflows/wf_*.json`の`workflowProgress[].model`を確認する。`defaultModel`はlead modelを示し、workerの実modelの証明にはならない
- routing 異常時は `CLAUDE_CODE_SUBAGENT_MODEL` 系の環境変数を最初に確認する（既定値として、または`_FORCE`付きで全体の上書きとして効く）
