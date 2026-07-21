# Claude Code 設定

# 汎用学習事項
@~/.agents/rules/learnings.md

# 共有ルール（正本: ~/.agents/rules/ — Codex と共有。正本編集後は ~/.agents/bin/sync-shared-rules.sh を実行）
@~/.agents/rules/karpathy-guidelines.md
@~/.agents/rules/no-fallback.md
@~/.agents/rules/git-safety.md
@~/.agents/rules/decision-integrity.md
@~/.agents/rules/quality-priority.md
@~/.agents/rules/scope-discipline.md
@~/.agents/rules/test-policy.md
@~/.agents/rules/git-workflow.md
@~/.agents/rules/failure-investigation.md
@~/.agents/rules/framework-respect.md
@~/.agents/rules/self-improvement.md
@~/.agents/rules/workspace-hygiene.md

# セッション初期化

- SessionStart hook が `git status` / `git branch` を systemMessage で自動注入する
- プロジェクトの高信号な教訓は `.claude/rules/**/project-learnings.md` からセッションごとに読み込み、新しい継続的な知見は native auto memory に保存する

# エージェントオーケストレーション

- 非自明なタスク（マルチステップ・クロスドメイン・新規プロジェクト）は `project-orchestrator` に相談して最適なスペシャリストを決定する
- スペシャリストが明白な単一ドメインタスク（例: `.sol` 編集 → `solidity-engineer`）はスキップ可
- machine-specific なプロジェクト→スペシャリストの高速ルーティングは untracked の `CLAUDE.local.md` に定義する（公開リポジトリに固有名を書かない）
- Agent Teams / `ultracode` は、3 本以上の独立した workstream に分割でき、並列化の利点が調整コストを明確に上回る大型タスクだけに使う。通常実装・単純調査・同一ファイルへの並列 write には使わない

# モデル役割分担（quota 運用）

main は Fable（quota 消費が重い）のため、直接作業は計画・分解・委任判断・結果統合・高難度判断に限定し、実作業はサブエージェントへ委任してモデル階層を下げる。ドメインスペシャリストが該当する場合は常に優先する。サブエージェントは再委任せず自タスクに専念する（本節と workflow.md の「>3 ステップ→Agent」は main セッションにのみ適用）。

| 役割 | モデル | 実行主体 |
|------|--------|---------|
| Orchestrator / 高難度判断 | Fable | main セッション |
| Deep reasoning（複雑設計・厄介なデバッグ・アルゴリズム） | Opus | `deep-reasoner` |
| 実装・機械的作業 | Sonnet | ドメインスペシャリスト or `fast-worker` |
| Independent peer（second opinion / rescue） | Codex | `codex-rescue` / `/codex:rescue` |

委任判断基準（1つでも該当すれば Fable が直接作業しない）:

- 手順が明確で判断分岐が少ない → Sonnet 層
- 推論が主体（設計・原因分析・アルゴリズム） → `deep-reasoner`
- 高リスク（アーキテクチャ・データ破壊・公開 API） → 判断は Fable が保持
- 大量のファイル探索・長い読み込み・大きな diff → main context に載せずサブエージェントに隔離

高リスク判断の並列諮問・Codex 連携・ルーティング検証の詳細手順は `model-routing` スキルを参照。

# コミュニケーションスタイル

- settings.json に `outputStyle` が設定されている場合はそのスタイルを排他使用し、以下を無視する
- 未設定時: 簡潔・事実ベース・実行可能な助言。前提・リスク・未検証事項を具体的に示し、不要なお世辞や過度な断定を避ける

# 起動運用

`claude` は常にプロジェクトディレクトリから起動する。`$HOME` 直下からの起動は禁止（cwd 全体スキャンで RSS 15-17GB・3 分超ハングの実測あり。`.claudeignore` は起動時スキャンに効かない: 2026-04-19 検証済み）。
