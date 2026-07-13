# claude-toolkit

Claude Code の設定フレームワーク。GitHub Issue 駆動の開発ワークフロー、品質ゲート、カスタムスキルを提供する。

## 概要

`~/.claude/` ディレクトリに配置して使う Claude Code の設定一式。

- **GitHub Issue 駆動ワークフロー**: Issue 取得 → 実装 → コミット → 進捗同期の 4 フェーズ
- **カスタムスキル**: PR 作成、コードレビュー、ブランチ整理等 20 種
- **品質ゲート**: Ruff ルール準拠、型安全ガード、実装前チェックリスト
- **Git Worktree 統合**: Issue ごとに隔離された作業環境を自動構築
- **Hook 自動化**: PR 作成時の自動レビュー、テスト品質検証、Slack 通知

## ディレクトリ構成

```
~/.claude/
├── CLAUDE.md          # コア設定（モデル役割分担、エージェントルーティング）
├── LEARNINGS.md       # 汎用学習事項（言語固有は rules/ の paths スコープ）
├── settings.json      # Claude Code 設定（権限、Hook、モデル）
├── bin/               # CLI ツール
│   ├── gtr-start      # Git Worktree + Issue ワークフロー開始
│   ├── gtr-finish     # PR マージ後のクリーンアップ
│   ├── gh-issue-fetch.sh
│   ├── gh-progress-sync.sh
│   ├── gh-retrospective.sh
│   ├── project-locate # 高速ファイル検索
│   └── slack-notify   # Slack 通知 CLI
├── hooks/             # PostToolUse / Session Hook
├── rules/             # 品質・ワークフロールール
├── skills/            # カスタムスキル定義
└── scripts/           # GitHub Projects 連携等
```

## セットアップ

### 前提条件

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) がインストール済み
- [GitHub CLI](https://cli.github.com/) (`gh`) が認証済み
- (任意) Slack Incoming Webhook URL

### インストール

```bash
# 既存の ~/.claude をバックアップ
mv ~/.claude ~/.claude.bak

# クローン
git clone https://github.com/trow126/claude-toolkit.git ~/.claude

# マシン固有の設定（任意）
cp ~/.claude/settings.json ~/.claude/settings.local.json
# settings.local.json を環境に合わせて編集
```

### シークレットスキャン（コミットするマシンでは必須）

本リポジトリは public のため、コミット前に [gitleaks](https://github.com/gitleaks/gitleaks) でステージ済み差分をスキャンする。フック（`githooks/pre-commit`）は gitleaks 未インストール時にコミットを明示エラーで拒否する。

```bash
# gitleaks をインストール（例: v8.30.1 linux x64）
curl -sL https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz \
  | tar -xz -C ~/.local/bin gitleaks

# フックを有効化（リポジトリごとに一度）
git -C ~/.claude config core.hooksPath githooks
```

GitHub 側でも Secret Scanning + Push Protection を有効化済み（既知プロバイダのトークンは push 時にもブロックされる）。

### 外部スクリプト（任意）

`settings.json` の一部の Hook は同梱されていない外部スクリプトを参照する。これらは環境に合わせて自作するか、該当 Hook エントリを削除する。

| 参照先 | 用途 | 対応 |
|--------|------|------|
| `~/bin/suggest-claude-md-hook.sh` | セッション終了時に CLAUDE.md 更新提案 | 不要なら `SessionEnd` / `PreCompact` Hook を削除 |
| `~/bin/setup-test-quality.sh` | テスト品質ツーリング手動セットアップ | Hook は未検出時に案内を表示するのみ |

### Slack 通知

```bash
# 方法1: 環境変数
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."

# 方法2: 設定ファイル
echo "SLACK_WEBHOOK_URL=https://hooks.slack.com/services/..." > ~/.config/slack-notify.env
```

## スキル一覧

### GitHub ワークフロー

| スキル | 説明 |
|--------|------|
| `/gh:start` | Issue 駆動開発（取得→実装→コミット→同期） |
| `/gh:pr` | PR 自動作成（ブランチ検出、差分解析、Issue 連携） |
| `/gh:issue` | Issue ライフサイクル管理 |
| `/gh:review` | 統合コードレビュー（CodeRabbit + セルフレビュー） |
| `/gh:coderabbit` | Quality / Security / Performance 分析 |
| `/gh:index` | プロジェクト構造インデックス生成 |
| `/pr-review` | PR 作成直後のセルフレビューコメント投稿 |
| `/branch-cleanup` | マージ後のブランチ・worktree 整理 |

### プロセス自動化

| スキル | 説明 |
|--------|------|
| `/issue-parser` | Issue Markdown → 構造化タスク |
| `/issue-work-logger` | 作業ログ自動記録 |
| `/issue-retrospective` | 完了 Issue からの学習抽出 |
| `/progress-tracker` | タスク完了追跡 → Issue 同期 |

### 分析・ユーティリティ

| スキル | 説明 |
|--------|------|
| `/deep-research-mode` | 体系的調査モード |
| `/introspect` | メタ認知分析・エラー回復 |
| `/plan-review` | マルチパースペクティブ計画レビュー |
| `/model-routing` | モデル委任の詳細運用規則 |
| `/token-efficiency` | トークン圧縮コミュニケーション |
| `/knowledge-audit` | 学習事項の棚卸し・圧縮 |
| `/config-audit` | グローバル設定のベストプラクティス監査 |
| `/python-refactor-analysis` | リファクタ前の構造分析レポート生成 |

## カスタマイズ

### ルール

`rules/` ディレクトリ内の Markdown ファイルで品質基準やワークフローを定義。

- `code-quality.md` - 実装の完全性、No Fallback ポリシー
- `git-workflow.md` - Conventional Commits、Feature Branch 運用
- `karpathy-guidelines.md` - 前提明示、シンプルさ、外科的変更、成功条件駆動
- `safety.md` - 根本原因分析、体系的デバッグ
- `workflow.md` - タスクパターン、並列実行戦略

## ライセンス

[MIT](LICENSE)
