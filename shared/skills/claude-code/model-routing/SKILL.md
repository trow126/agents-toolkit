---
name: model-routing
description: Details Claude model assignment, the read-only-only use of Codex (it never implements), and verification of the model a subagent actually used. Use when verifying routing or diagnosing a routing anomaly. CLAUDE.md「Ownerとrouting」の詳細運用規則。
user-invocable: true
---

# Model Routing 運用規則（詳細）

CLAUDE.md「Ownerとrouting」を補完する詳細手順。既定は「必要十分な最小コストの単一 owner が完遂」であり、以下は例外時にだけ使う。

- 停止条件: model割当の変更や、Codexへの実装委任が必要に見えたら、実施せずに報告して止まる
- 完了条件: 実際に使われたmodelを一次情報（transcript・workflow記録・Codexのexec JSONL）で確認して報告した時点

## Claude model割当

- mainはlead/advisorとして長期的な方針決定と統合を担当する（modelはCLAUDE.mdのlead）
- exact-name overrideの`Explore`はfrontmatterのmodelを使い、read-only codebase探索だけを担当する
- dynamic workflowのanonymous workerは、生成scriptの各`agent()`のmodel optionにCLAUDE.mdのworker modelを明示する。dynamic workflow専用のglobal default keyはないため、親modelの暗黙継承に依存しない
- built-in `general-purpose`はmain modelを継承する
- `CLAUDE_CODE_SUBAGENT_MODEL`はsubagentの既定値として扱われ、全体の上書きには`_FORCE`付きの指定が要る。model割当はCLAUDE.mdとagent frontmatterで管理するため、どちらも設定しない

## 独立した検査と計画review

- Claude側にescalation用のagentは置かない（mainが最上位）
- 高リスク変更（アーキテクチャ・データ破壊・公開 API）は、deterministic CI と `/code-review` で差分を検査する
- 計画reviewはCodex版`plan-review`（ユーザーがCodexで実行する）か`/code-review`を使う
- `/break-consensus`はユーザーが起動した場合だけ使う。既定で別provider（Codex）のworkerにもbriefを渡す（D13。`--solo`で渡さない）。委任ではなくread-onlyで、実装には移らない
- 計画・事前登録・amendment・設計・仮説への異系統の批判は、ユーザーが明示した場合だけ`/cross-critic`（重要ゲートは`--gate`）を使う。批判役であり判定役ではない

## Codex は実装しない

- Codexへ実装を委任しない（owner決定 2026-10-11、Issue #14）。2026-10のA/B実験（`docs/eval/sandwich-ab-results.md`・`sandwich-ab-d-results.md`）で、Codex実装はClaude単独より費用が下がらず時間が3〜6倍だった。実装はClaudeが行い、Issueは`/gh-test-first`・`/gh-roadmap-run`でテスト先行にする
- Codexを使うのはread-onlyの批評・諮問（`/cross-critic`・`/break-consensus`・`plan-review`）だけで、main sessionから起動する。`codex:codex-rescue` Agentと`/codex:adversarial-review`を諮問の代わりに起動しない
- ユーザーがCodexでの実装を求めたら、実施せずにこの決定を伝えて止まる
- 接続・認証に問題があれば `/codex:setup` で確認する

## 既存経路が優先

- PR 作成後のレビュー → `/code-review <PR番号>`。PR へのコメント投稿はユーザーの明示指示で `/code-review <PR番号> --comment`
- 計画レビュー → Codex版`plan-review`か`/code-review`

## ルーティングの検証（モデル自己申告は証明にならない）

- エージェント起動表示の model 欄
- transcript（`~/.claude/projects/` の JSONL にある assistant メッセージの `model` フィールド）
- dynamic workflowは`~/.claude/projects/<project>/<session>/workflows/wf_*.json`の`workflowProgress[].model`を確認する。`defaultModel`はlead modelを示し、workerの実modelの証明にはならない
- routing 異常時は `CLAUDE_CODE_SUBAGENT_MODEL` 系の環境変数を最初に確認する（既定値として、または`_FORCE`付きで全体の上書きとして効く）
