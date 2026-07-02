# Claude Code 設定

# コア動作フラグ
@FLAGS.md

# プロジェクト学習事項と品質ゲート
@LEARNINGS.md

# Karpathy-Inspired 実装行動規律
@rules/karpathy-guidelines.md

# PR 作成後レビュー規約
@rules/pr-review.md

# セッション初期化 (SessionStart hook で自動実行)

SessionStart hook が git 情報を systemMessage で自動注入:

1. `git status` + `git branch` → hook が自動実行
2. プロジェクトの `claudedocs/learnings.md` → 必要に応じて確認

# ツール選択マトリクス
| タスク種別 | 最適ツール | 代替手段 |
|-----------|-----------|----------|
| 深い分析 | Sequential MCP | ネイティブ推論 |
| シンボル操作 | Grep / Read / Glob | 手動検索 |
| ドキュメント参照 | Context7 MCP | Web検索 |
| 複数ファイル編集 | 並列 Edit (パラレルツールコール) | 逐次Edit |
| インフラ構成 | WebFetch (公式ドキュメント) | 推測禁止 |

# ===================================================
# エージェントオーケストレーション
# ===================================================

非自明なタスクでは、`project-orchestrator` エージェントに相談して最適なスペシャリストを決定すること。

**既知プロジェクトルーティング**（公開テンプレート）:

公開リポジトリには machine-specific なプロジェクト名やパスを含めないこと。
必要な高速パスは untracked な `CLAUDE.local.md` に定義する。

| リポジトリ種別 | スペシャリスト |
|-------------|---------------|
| ML / data platform | `ai-engineer`, `data-engineer`, `sre` |
| Model research / QA | `ai-engineer`, `model-qa-specialist`, `data-engineer` |
| Solidity / DeFi | `solidity-engineer`, `blockchain-security-auditor`, `sre`, `data-engineer` |

**未知・新規プロジェクト**: オーケストレーターが設定ファイルからプロジェクトドメインを自動検出し、ドメイン-エージェントマトリクス経由でルーティングする。

**オーケストレーターを使うべき場面**: マルチステップタスク、クロスドメイン作業、新規プロジェクト、どのスペシャリストが適切か不明な場合。
**スキップしてよい場面**: スペシャリストが明白な単一ドメインタスク（例: `.sol` 編集 → `solidity-engineer`）。

# ===================================================
# モデル役割分担（quota 運用）
# ===================================================

**方針**（main セッション向け規則。サブエージェントは再委任せず自タスクに専念する — rules/workflow.md の「>3 ステップ→Agent」規則や上記オーケストレーション節の相談規則も main にのみ適用）: main は Fable（quota 消費が重い）のため、Fable の直接作業は計画・分解・委任判断・結果統合・高難度判断に限定し、実作業はサブエージェントへ委任してモデル階層を下げる。上記「エージェントオーケストレーション」（ドメイン軸: 誰に任せるか）と直交するモデル軸（どの計算資源を使うか）のルーティングであり、**ドメインスペシャリストが該当する場合は常にそちらを優先**する（既存スペシャリストの frontmatter model pin がこの階層を既に実装している）。

**役割マトリクス**:

| 役割 | モデル | 実行主体 | 対象 |
|------|--------|---------|------|
| Orchestrator | Fable | main セッション | 計画・分解・委任判断・統合・高難度判断 |
| Advisor | Fable / Opus | main セッション or `deep-reasoner` | 重要判断・別角度の確認（高リスクは下記の並列諮問） |
| Deep reasoning | Opus | `deep-reasoner` | 複雑設計・厄介なデバッグ・アルゴリズム設計 |
| Implementation / Mechanical | Sonnet | ドメインスペシャリスト or `fast-worker` | boilerplate・テスト・フォーマット・リネーム・単純編集・日常実装 |
| Independent peer | Codex | Codex plugin（`/codex:rescue`・`codex-rescue` エージェント） | 別モデル系統からの second opinion / 行き詰まり時の rescue。reviewer ではなく peer engineer |

**委任判断基準**（1つでも該当すれば Fable が直接作業しない）:

- タスク性質: 手順が明確で判断分岐が少ない → Sonnet 層。推論が主体（設計・原因分析・アルゴリズム） → `deep-reasoner`
- リスク: 低リスク（可逆・テストで検証可能） → Sonnet 層へ委任。高リスク（アーキテクチャ・データ破壊・公開 API） → 判断は Fable が保持し、必要に応じて並列諮問
- トークン規模: 大量のファイル探索・長い読み込み・大きな diff 生成は main context に載せずサブエージェントに隔離する（context は lean に保つ: 課題文・対象パス・成功条件のみ渡す）

**運用規則**:

- 高リスク判断の並列諮問: `deep-reasoner` 起動と `/codex:adversarial-review`（設計検証）または `codex-rescue` エージェント起動を並行発行し、**互いの回答を見せず** Fable が統合する（相違点と採否理由を明示）
- Codex 実行はバックグラウンドになりうる（`/codex:status` で監視、`/codex:result` で取得）。妥当な待機で結果が得られなければ Opus の回答のみを用いて Fable が統合し、結論に「peer opinion 欠落」と明記する
- Codex の役割は peer engineer（実装の下請けでもレビュアーでもない）。接続・認証に問題があれば `/codex:setup` で確認する
- 既存経路が優先: PR レビュー → PR 作成後レビュー規約 / 計画レビュー → `/plan-review` / コントラクト監査 → `blockchain-security-auditor` / ML 監査 → `model-qa-specialist`（`deep-reasoner` はこれらの代替ではない）
- フラグとの区別: `--think` 系は同一モデル内の思考予算、本節はモデル選択。`--delegate` は規模基準の並列化、本節は性質基準のルーティング（相補・非矛盾）。ツール選択マトリクスの「深い分析→Sequential MCP」は main 自身の統合判断向けで、`deep-reasoner` に委任した推論は同エージェント内のネイティブ推論で行う
- 検証（モデル自己申告は証明にならない）: ルーティングの正しさは応答本文ではなく、エージェント起動表示の model・transcript（`~/.claude/projects/` の JSONL にある assistant メッセージの `model` フィールド）・`session-report` スキル・usage dashboard で確認する。routing 異常時は `CLAUDE_CODE_SUBAGENT_MODEL` 環境変数を最初に確認する（設定されていると全 frontmatter pin を上書きする仕様）

# ===================================================
# コミュニケーションスタイル
# ===================================================

**出力スタイル優先**: settings.json に `outputStyle` が設定されている場合、そのスタイルを排他的に使用し、以下のデフォルトコミュニケーションモードを無視すること。

**デフォルトコミュニケーションモード**（出力スタイル未設定時）:

- 簡潔、事実ベース、実行可能な助言を優先する
- 前提・リスク・未検証事項は具体的に示す
- 不要なお世辞や過度な断定を避ける
- 実装・検証・次の判断がしやすい順序で答える

# ===================================================
# UTF-8 Bug Workaround (履歴的注意事項)
# ===================================================

**状態**: Issue #14405 は 2026-04-18 に CLOSED。Claude Code 最新版では修正済み。

**旧バグ**: v2.0.70 以降の一部バージョンで、日本語を含む文字列スライスが char boundary 違反で panic。

**現在の運用**:
- 最新版 (v2.1.x 系) では Edit/Write ツールを日本語ファイルにも使用可
- 万が一 panic が再発した場合のフォールバック: UTF-8 を明示した `uv run python` 変換 or `sed`

Ref: https://github.com/anthropics/claude-code/issues/14405 (CLOSED 2026-04-18)

# ===================================================
# 起動運用
# ===================================================

**原則**: `claude` は常にプロジェクトディレクトリから起動する。`$HOME` 直下からの起動は禁止。

**理由**: `$HOME` 配下には大規模プロジェクトが並存し（machine-specific なリポジトリ詳細は untracked な `CLAUDE.local.md` 参照）、Claude Code は cwd 全体をスキャンする。`.claudeignore` は起動時スキャンに効かないことが 2026-04-19 の調査で確認済み（lsof で検証）。

**症状（home 起動時）**: RSS 15-17GB、CPU 200s+、3 分以上のハング。

**推奨**: 作業対象のプロジェクトに `cd` してから `claude` を起動する。

# ===================================================
# グローバル安全ガードレール
# ===================================================

- main/master への force-push 禁止
- 本番データ/データベースの削除禁止
- シークレットを含む .env ファイルの変更禁止
- `claude` を `$HOME` 直下から起動しない（上記「起動運用」参照）
