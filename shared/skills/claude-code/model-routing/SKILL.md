---
name: model-routing
description: Details Claude model assignment, the read-only-only use of Codex (it never implements), and verification of the model a subagent actually used. Use when verifying routing or diagnosing a routing anomaly. CLAUDE.md「Ownerとrouting」の詳細運用規則。
user-invocable: true
---

# Model Routing 運用規則（詳細）

CLAUDE.md「Ownerとrouting」を補完する詳細手順。既定は「必要十分な最小コストの単一 owner が完遂」である。model割当節は常に適用する。検証・諮問・Codex関連の節は該当時だけ使う。

- 停止条件: model割当や設定を書き換える操作、またはCodexへの委任（read-onlyの批評・諮問を除く）が必要に見えたら、実施せずに報告して止まる
- transcript・`wf_*.json`・Codexのexec JSONL・環境変数・agent fileの読み取りは承認なしで行う
- 完了条件（検証・異常診断時のみ適用）: 実際に使われたmodelを一次情報（transcript・workflow記録・Codexのexec JSONL）で確認して報告した時点

## Claude model割当

- mainはlead/advisorとして長期的な方針決定と統合を担当する（modelはCLAUDE.mdのlead）
- exact-name overrideの`Explore`はfrontmatterのmodelを使い、read-only codebase探索だけを担当する
- dynamic workflowのanonymous workerは、生成scriptの各`agent()`のmodel optionにCLAUDE.mdのworker modelを明示し、親modelの暗黙継承に依存しない
- built-in `general-purpose`はmain modelを継承する
- fork subagent（`subagent_type: "fork"`）は`claude -p`・Agent SDK・desktop・VS Codeで既定有効（`CLAUDE_CODE_FORK_SUBAGENT=0`で無効）。親contextを引き継ぎ親modelを継承する前提でルーティング管理・検証の対象に含め（別modelの明示割当は求めない）、実modelはそのtranscriptで確認する
- `CLAUDE_CODE_SUBAGENT_MODEL`はsubagentの既定値として扱われ、全体の上書きには`CLAUDE_CODE_SUBAGENT_MODEL_FORCE`が要る。model割当はCLAUDE.mdとagent frontmatterで管理するため、これらと`CLAUDE_CODE_SUBAGENT_EFFORT`（他に指定がないときのsubagent effort）・`CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL`（全workflow agentを1つのmodelに揃える）は設定しない
- mainと異なるmodelのsubagentは、sessionのeffortではなく、そのmodelの保存済みまたは既定のeffortで動く（v2.1.317以降）。親とのeffort差だけでは異常としない

## 独立した検査と計画review

- Claude側にescalation用のagentは置かない（mainが最上位）
- 高リスク変更（アーキテクチャ・データ破壊・公開 API）は、deterministic CI と `/code-review` で差分を検査する
- 計画reviewはCodex版`plan-review`（ユーザーがCodexで実行する）か`/code-review`を使う
- `/break-consensus`はユーザーが起動した場合だけ使う。既定で別provider（Codex）のworkerにもbriefを渡す（owner決定D13: `docs/reports/owner-decisions.md`。`--solo`で渡さない）。委任ではなくread-onlyで、実装には移らない
- 計画・事前登録・amendment・設計・仮説への異系統の批判は、ユーザーが明示した場合だけ`/cross-critic`（重要ゲートは`--gate`）を使う。批判役であり判定役ではない

## Codex は実装しない

- Codexへは実装を委任しない。ただしread-onlyの批評・諮問は例外とし（owner決定 2026-10-11、Issue #14）、`/cross-critic`・`/break-consensus`は前節の条件のもとmain sessionから起動してよい（Codex版`plan-review`は前節のとおりユーザーがCodexで実行する）。2026-10のA/B実験（`docs/eval/sandwich-ab-results.md`・`docs/eval/sandwich-ab-d-results.md`）で、Codex実装はClaude単独より費用が下がらず時間が3〜6倍だった。実装はClaudeが行い、Issueは`/gh-test-first`・`/gh-roadmap-run`でテスト先行にする
- `codex:codex-rescue` Agentと`/codex:adversarial-review`を諮問の代わりに起動しない
- ユーザーがCodexでの実装を求めたら、実施せずにこの決定を伝えて止まる
- 接続・認証に問題があれば `/codex:setup` で確認する

## 既存経路が優先

- PR 作成後のレビュー → `/code-review <PR番号>`。PR へのコメント投稿はユーザーの明示指示で `/code-review <PR番号> --comment`
- 計画レビュー → Codex版`plan-review`か`/code-review`

## ルーティングの検証（モデル自己申告は証明にならない）

- 実測したtranscript・設定値がこのskillや公式docsの記述と食い違う場合は実測を優先し、食い違った記述をstale候補として報告する
- エージェント起動表示の model 欄（補助的な目安。一次情報ではなく、検証済みの根拠には使わない）
- transcript（`~/.claude/projects/` の JSONL にある assistant メッセージの `model` フィールド）。その agent の全 assistant 行の `model` の異なり値を数える。実modelでない合成行の値（`<synthetic>`。API errorや中断時に書かれる）を除いた異なり値が1種類で、設定されたmodelと一致するときだけ検証済みとする。設定と違う1種類は割当の不一致として報告し、2種類以上は途中のfallbackかresume時の切替として別に分類して報告する。0種類（対象行なし、または全行が`<synthetic>`等）は未検証とし、実model応答なし（API error・中断・未実行等）として、割当の不一致やfallback・resume時の切替と区別して報告する（served modelを全行で集計する既知の方法: https://yurukusa.github.io/cc-safe-setup/claude-code-which-model-served.html）
- Claude Code 2.1.316未満のtranscriptで、再開後のnested subagentだけがmain modelに変わっている場合は既知の不具合（v2.1.316で修正）として記録し、設定層の異常と区別する
- dynamic workflowは`~/.claude/projects/<project>/<session>/workflows/wf_*.json`の`workflowProgress[].model`を確認する。`defaultModel`はlead modelを示し、workerの実modelの証明にはならない
- Codexのexec JSONLは出力先・形式が呼び出し経路に依存しうるため、実際に生成されたファイルと実modelを示すフィールドを実測で特定して確認する
- routing 異常時は次の順に確認する。設定されたmodelは親の実modelの証拠にならない
  1. 親sessionのtranscriptにある実model（fallbackを含む）
  2. `CLAUDE_CODE_SUBAGENT_MODEL`（既定値として効く）・`CLAUDE_CODE_SUBAGENT_MODEL_FORCE`（全体の上書きとして効く）・`CLAUDE_CODE_SUBAGENT_EFFORT`・`CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL`
  3. agent frontmatter、または`agent()`のmodel option
