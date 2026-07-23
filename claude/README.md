# claude

[agents-toolkit](../README.md) モノレポ内の Claude Code 設定ソース（`install/manifest.tsv` により `~/.claude` 配下へ個別 symlink）。GitHub Issue 駆動の開発ワークフロー、品質ゲート、カスタムスキルを提供する。

## 概要

`~/.claude/` として利用される Claude Code の設定一式。汎用ルールの正本は `shared/rules/`（`~/.agents/rules/` symlink）にあり、`CLAUDE.md` から `@~/.agents/rules/*.md` で実行時 import する。

- **owner 選択とルーティング**: 必要十分な最小コストの単一 owner が完遂する既定 + 例外時のエスカレーション（`deep-reasoner`）・独立検証（`code-reviewer` / `plan-reviewer`）
- **GitHub Issue 駆動ワークフロー**: Issue 取得 → 実装 → コミット → 進捗同期
- **品質ゲート**: Ruff ルール準拠、型安全ガード、path-scoped rules（`rules/python.md` 等）
- **Hook 自動化**: git context 注入、危険コマンド遮断、PR 作成検出、Slack 通知
- **革新探索**: 手動起動専用の `/break-consensus`（合意封鎖型アイデア探索）

## ディレクトリ構成

```
~/.claude/
├── CLAUDE.md          # コア設定（共有ルール import、owner 選択とルーティング）
├── settings.json      # Claude Code 設定（権限、Hook、モデル）
├── bin/               # CLI ツール（gtr-start / gtr-finish / slack-notify 等）
├── hooks/             # PreToolUse / PostToolUse / Session Hook
├── rules/             # Claude 固有ルール（常時: code-quality, safety / path-scoped: python, markdown, settings-syntax）
├── agents/            # サブエージェント定義（domain specialist + deep-reasoner + reviewer）
├── skills/            # カスタムスキル定義
└── scripts/           # GitHub Projects 連携等
```

## セットアップ

### 前提条件

- [Claude Code](https://code.claude.com/docs) がインストール済み
- [GitHub CLI](https://cli.github.com/) (`gh`) が認証済み
- (任意) Slack Incoming Webhook URL

### インストール

agents-toolkit モノレポのルートで `./bootstrap.sh --apply` を実行すると、`install/manifest.tsv` に従って `~/.claude` 配下の各ファイル・ディレクトリが `claude/` 配下の対応 source へ個別 symlink される（詳細はルート [README.md](../README.md) 参照）。

sandbox（既定で有効・`failIfUnavailable: true` の fail-closed 構成）のため、Linux / WSL2 では依存パッケージが必要:

```bash
sudo apt-get install bubblewrap socat   # Ubuntu/Debian。未導入だと Claude Code が起動を拒否する
```

### マシン固有の設定差分

Claude Code の documented scope は user（`~/.claude/settings.json`）/ project（`<project>/.claude/settings.json`）/ project local（`<project>/.claude/settings.local.json`）で、**user-level の `settings.local.json` は存在しない**。machine 固有の差分は次のいずれかで扱う:

- project 単位の差分 → 各プロジェクトの `.claude/settings.local.json`（gitignored）
- machine 全体の環境変数系 opt-in（Agent Teams 等） → その machine の shell profile で `export`
- 承認プロンプトなし運用（bypassPermissions） → 共有設定は変更せず、**全プロセス隔離付き launcher** を使う（下記）
- 上記で表現できない user settings 自体の恒久差分 → 当該 machine で symlink を実ファイル化して編集する（`bootstrap.sh --check` が差分を報告する。意図した deviation として管理する）

### claude-bypass（全プロセス隔離内の bypassPermissions）

`bypassPermissions` は permission prompt を原則スキップするため、公式ガイダンスに従い **Claude Code プロセス全体（built-in tools・MCP・hooks を含む）を隔離境界内で起動する場合のみ**使う。`claude-bypass` launcher は [`@anthropic-ai/sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime)（srt。beta research preview）で全プロセスを Seatbelt/bubblewrap 境界に収容し、次をすべて満たすときだけ起動する（不成立なら bypass せず非ゼロ終了）:

1. WSL2（kernel の `microsoft-standard` 署名。WSL1 は明示拒否）かつ非 root — 実 `/proc/version`・実 `id -u` に固定で、環境変数では差し替え不能
2. machine-local opt-in marker（600・schema・期限 180 日。`--enable-this-machine` で作成）
3. srt が導入済みで、machine-local の srt 設定（credential denyRead + network allowlist + 最小 allowWrite）が存在する
4. claude へ固定 security profile（`bypass-profile.json`: sandbox pin + 外部副作用の ask gate）を CLI `--settings` で注入 — CLI scope は project/local より優先のため project 側から境界を弱められない

```bash
npm install -g @anthropic-ai/sandbox-runtime        # 必須依存（全プロセス隔離）
~/.claude/bin/claude-bypass --enable-this-machine   # 環境検証 + srt 設定生成 + opt-in（期限付き）
~/.claude/bin/claude-bypass                          # 検証成功時のみ srt 隔離内で bypass 起動
```

git push・PR/issue/release 作成・`gh api`・`curl` 等の**外部副作用は ask rule により bypass 中でも明示 prompt** になる（PDF の「明示要求なしに push・PR・外部投稿をしない」の permission-layer 強制。頻用の read-only git/gh subcommand は個別 allow 済み）。

### シークレットスキャン（コミットするマシンでは必須）

本リポジトリは public のため、コミット前に [gitleaks](https://github.com/gitleaks/gitleaks) でステージ済み差分をスキャンする。フック（`githooks/pre-commit`）は gitleaks 未インストール時にコミットを明示エラーで拒否する。

```bash
# gitleaks をインストール（例: v8.30.1 linux x64。MIT License）
# 1) version 固定 artifact を一旦ファイルへ保存（stream 直結の tar 展開はしない）
curl -fL -o /tmp/gitleaks.tar.gz \
  https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz

# 2) 公式 release ページの checksums ファイルと照合し、成功した場合のみ展開
curl -fL -o /tmp/gitleaks_checksums.txt \
  https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_checksums.txt
(cd /tmp && grep "gitleaks_8.30.1_linux_x64.tar.gz" gitleaks_checksums.txt | sha256sum -c -) \
  && tar -xzf /tmp/gitleaks.tar.gz -C ~/.local/bin gitleaks

# フックを有効化（`./bootstrap.sh --apply` 実行時に自動設定される。手動で設定し直す場合）
git -C ~/agents-toolkit config core.hooksPath claude/githooks
```

checksum 照合が失敗した場合は展開せず、ダウンロード元と経路を確認する（OS パッケージマネージャ経由の導入も可）。

GitHub 側でも Secret Scanning + Push Protection を有効化済み（既知プロバイダのトークンは push 時にもブロックされる）。

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
| `/gh-start` | Issue 駆動開発（取得→実装→コミット→同期） |
| `/gh-pr` | PR 自動作成（ブランチ検出、差分解析、Issue 連携） |
| `/gh-issue` | Issue ライフサイクル管理 |
| `/gh-review` | PR レビュー指摘への統合対応 |
| `/gh-index` | プロジェクト構造インデックス生成 |
| `/pr-review` | PR 作成直後のセルフレビューコメント投稿 |
| `/branch-cleanup` | マージ後のブランチ・worktree 整理 |

### 分析・ユーティリティ

| スキル | 説明 |
|--------|------|
| `/break-consensus` | 合意封鎖型の革新探索（手動起動専用） |
| `/plan-review` | 実行前計画レビュー（`plan-reviewer` agent） |
| `/model-routing` | エスカレーション・並列諮問・Codex peer 連携の詳細規則 |
| `/knowledge-audit` | 学習事項の棚卸し・圧縮 |
| `/config-audit` | グローバル設定のベストプラクティス監査 |
| `/python-refactor-analysis` | リファクタ前の構造分析レポート生成 |

旧 skill（`gh:coderabbit`・`progress-tracker`・`issue-*` 系・`introspect`・`token-efficiency`・`x-article-to-markdown`・`deep-research-mode`）は 2026-07-23 に [docs/archive/skills/](../docs/archive/skills/) へ退避（根拠と復元手順は同ディレクトリの README 参照）。skill 名は Agent Skills 仕様に合わせ `gh:*` → `gh-*` に改名済み。

## カスタマイズ

### ルール

`rules/` ディレクトリ内の Markdown ファイルで Claude Code 固有の品質基準を定義（言語非依存の共有ルールは `shared/rules/` を参照）。

- `code-quality.md` - 品質ゲート・プロジェクト記録（常時ロード）
- `safety.md` - Claude Code 運用の安全制約（常時ロード）
- `python.md` / `markdown.md` / `settings-syntax.md` - paths frontmatter による path-scoped ロード

## ライセンス

[MIT](../LICENSE)
