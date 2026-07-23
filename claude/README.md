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
- user settings 自体の恒久差分 → 当該 machine で symlink を実ファイル化して編集する（`bootstrap.sh --check` が差分を報告する。意図した deviation として管理する）

### 低プロンプト運用と bypassPermissions の方針

bypassPermissions モードは、公式ガイダンス上 container / VM / sandbox-runtime 等の隔離環境向けであり、host 常用に必要な条件（隔離境界の信頼できる bootstrap・workspace 限定 read/write・最小 egress・live 統合検証）を個人 dotfiles で維持し続けるのは過剰なため、**本 toolkit では配布せず、共有設定で無効化している**（`disableBypassPermissionsMode: "disable"`。2026-07-23 レビュー H-009/ATK-004 を受けた要件所有者の決定）。

日常の低プロンプト運用は bypass なしで成立する:

- **sandbox auto-allow**（sandbox 有効時の既定）: sandbox 内で実行できる Bash は prompt なしで走る
- **sandbox の境界（read と write を区別する）**: **write は workspace + session temp に限定**（OS-level 強制）。**read は既定で host 全体に及ぶ**ため、user 設定の `filesystem.denyRead` で `~/.config`・`~/.local/state|share`・`~/.cache`・`~/.claude`・`~/.codex`・`~/.agents` 等の private tree を deny し、`credentials.files` で既知 credential を deny している。**workspace-only read が必要なプロジェクトでは** [docs/templates/project-sandbox-settings.json](../docs/templates/project-sandbox-settings.json) を当該プロジェクトの `.claude/settings.json` へ追加する（user 設定の `.` は `~/.claude` に解決されるため project 側にしか置けない）
- **network egress**: 事前許可 domain ゼロ — `sandbox.network.allowedDomains` を置かず、**`WebFetch(domain:...)` allow も置かない**（WebFetch allow は sandbox Bash の network domain も pre-allow するため: 公式 sandboxing docs。validator が和集合 0 件を恒久検査する）。全 domain が session 内初回 prompt を経る（child process の外部送信も同様）。`gh` は `excludedCommands` により sandbox 外で実行され、permission rule（read-only allow / mutation ask）で gate される
- **workspace 限定の file 許可**（`Read(**)` / `Edit(**)`）: project 内の読み書きは prompt なし（project 外は通常フロー）
- **uv は `~/.claude/bin/uvw` を経由する**: uv の既定 cache/data/config path（`~/.cache/uv` 等）は sandbox の write 境界外かつ denyRead 下のため、素の `uv run` は sandbox 内で起動前に失敗する。uvw は可変 state を session temp（sandbox 内の `$TMPDIR`）へ固定してから uv を exec する（private tree の denyRead は緩和しない）
- **`.env` の read は OS-level で deny**: `Read(//**/.env)` 等の絶対 path deny が sandbox filesystem へ統合され、shell からの動的 path 構築（base64 復号・変数連結・`python open()` 等）でも実アクセスが拒否される。hook はその手前の literal（quote 分割含む）事故防止層。`.env.example` も対象になるため、参照したい場合は `env.example` 等へ改名するか waiver を登録する
- prompt が出るのは、**外部副作用**（`git push`・PR/issue 作成・`gh api`・`curl`・registry 操作・`npx` 等の任意 package 実行）・**破壊的 git 操作**（checkout/switch/stash/worktree/pull/`branch -D`）・**permission 前置迂回になり得る形**（`git -c*`・`git -C*`・`git --git-dir*`・`git config`）・**初回の network domain** のみ。`git commit --amend` は hook が「git と `--amend` の literal 共起」で deny する（quote 正規化つき heuristic の事故防止層。runtime 構築による迂回は hook の対象外で、公開履歴の保護は push の ask/deny が担う。history rewrite は手動操作）
- **git 運用の制約**: `.git/config`・`.git/hooks/**` への write は deny のため、`git config`（local）・`git init`・`git remote add` は sandbox 内で失敗する。これらは手動 shell で行う（`git add`/`git commit`/`git fetch` 等の通常 workflow は `.git` へ書けるため影響しない。linked worktree の共有 `.git` も公式仕様で commit 可能・hooks/config のみ deny）

導入後の環境検査は 2 経路で行う: `./bootstrap.sh --apply` / `--check` が `scripts/check-runtime.sh --soft-missing` を自動実行し（custom XDG・下限未満 version・prerelease を fail-closed で拒否。claude CLI 未導入のみ NOTE 続行）、Claude Code 導入後に `scripts/check-runtime.sh` を単体実行して確定させる（検証済み下限 2.1.218 stable。prerelease は検証対象外として拒否）。なお user settings に version floor を書ける documented key は存在しない（managed 配備の `requiredMinimumVersion` は fail-open 設計）ため、この doctor が toolkit の version gate である。bypass が不可欠な作業（完全無人運用など）は、公式の [dev container](https://code.claude.com/docs/en/devcontainer)（default-deny firewall 付き）等の隔離環境で行う。

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
