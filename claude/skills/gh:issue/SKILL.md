---
name: gh:issue
description: "GitHub Issueのライフサイクル管理（作成・完了）"
argument-hint: "<create|close> [issue-number]"
---

# GitHub Issue管理コマンド

Issueの作成と完了を担当するシンプルなコマンド。

**作業の開始・継続は `/gh:start` を使用してください。**

## 利用可能なコマンド

### create - 新しいIssueを作成

```bash
# 基本的な作成
/gh:issue create "Feature: User Authentication"

# ファイルから作成（推奨）
/gh:issue create --from-file claudedocs/brainstorm/auth_requirements.md

# ファイルパス直接指定（--from-fileと同等）
/gh:issue create claudedocs/brainstorm/auth_requirements.md

# 対話的に作成
/gh:issue create --interactive
```

**ファイルパス自動検出**:
引数が以下のパターンに該当する場合、`--from-file`と同等に扱う：
- `.md`拡張子を含む
- `/`または`\`を含むパス形式
- `claudedocs/`で始まる

**テンプレート自動選択**:
リポジトリに`.github/ISSUE_TEMPLATE/`がある場合、依頼内容から自動判定:
- "機能", "feature", "追加", "実装", "新規" → `--template feature.yml`
- "バグ", "bug", "エラー", "不具合", "修正" → `--template bug.yml`
- 上記以外 → `--template task.yml`
ユーザーによる`--template`指定は不要。

**処理フロー**:
1. Issue詳細の収集
2. GitHubに作成
   ```bash
   gh issue create --title "..." --body "..." --assignee "@me"
   ```
3. GitHub Projectsに追加（ステータス: "Todo"）
   ```bash
   source "$HOME/.claude/scripts/gh-projects-integration.sh"
   gh_projects_set_todo $ISSUE_NUMBER
   ```

**オプション**:
- `--from-file <path>`: ファイル内容をIssue本文として使用
- `--interactive`: 対話的に詳細を入力
- `--assignee <user>`: 担当者を指定（`@me`で自分）

---

### close - Issueを完了してクローズ

```bash
# Issueをクローズ
/gh:issue close 42

# 理由を指定
/gh:issue close 42 --reason completed

# 学習抽出スキップ
/gh:issue close 42 --no-retro
```

**処理フロー**:
1. **gh-retrospective.sh**（`--no-retro`がない場合）
   - Issue履歴分析
   - 関連PR検索（Closes #N対応）
   - **CodeRabbitレビュー分析**: 指摘件数・重要度分類
   - `claudedocs/learnings.md` に知見追記
2. 完了サマリーをコメント投稿
3. GitHub Projects更新（ステータス → "Done"）
4. Issueをクローズ
5. checkpoint削除
   ```
   delete_memory(memory_name="issue_{number}_checkpoint")
   ```
6. ブレインストーミングファイル削除（`--from-file`で使用した場合）

**オプション**:
- `--reason <completed|not_planned|duplicate>`: クローズ理由
- `--quiet`: 完了サマリーコメントをスキップ
- `--no-retro`: 学習抽出をスキップ
- `--keep-brainstorm`: ブレインストーミングファイルを保持

---

## 廃止されたサブコマンド

以下のサブコマンドは `/gh:start` に統合されました：

| 旧コマンド | 新しい方法 |
|-----------|-----------|
| `/gh:issue list` | `gh issue list --mine` |
| `/gh:issue view 42` | `gh issue view 42` |
| `/gh:issue work 42` | `/gh:start 42` |
| `/gh:issue status 42` | `gh issue view 42` |
| `/gh:issue sync 42` | 自動（/gh:start内） |

---

## GitHub Projects Integration

### ステータス自動更新
```bash
/gh:issue create   → Projects: "Todo"
/gh:start 42       → Projects: "In Progress"
/gh:issue close 42 → Projects: "Done"
```

### Graceful Degradation
GitHub Projects権限がない場合、自動的にラベルモードに切り替え:
- `status:todo`
- `status:in-progress`
- `status:done`

---

## ワークフロー

```bash
# 完全ワークフロー
/gh:issue create --from-file ...              # Issue作成
/gh:start 42                                   # 作業開始・継続
/gh:issue close 42                             # 完了
```

---

## エラー処理

- **GitHub CLI未検出**: インストール手順を提供
- **gitリポジトリ外**: `--repo`フラグを促す
- **Issue未発見**: 明確なエラーメッセージ

---

## 依存関係

- `gh` CLI (GitHub CLI) - 認証済み
- Gitリポジトリコンテキスト
- `gh-retrospective.sh`（closeのみ、~/.claude/bin/）

---

## 関連コマンド

```bash
/gh:issue create    # Issue作成（このコマンド）
/gh:start 42        # 作業開始・継続
/gh:issue close 42  # Issue完了（このコマンド）
```

---

## 実行指示

**あなたは今、`/gh:issue` コマンドを実行しています。**

ユーザーのコマンドを解析し、適切なサブコマンドを実行してください。

### create サブコマンド
1. **ファイルパス検出**: 引数が`.md`拡張子、パス形式（`/`含む）、`claudedocs/`で始まる場合は`--from-file`として扱う
2. **ファイル読み込み**（該当する場合）:
   - **🚨 重要**: ファイル内容は**一切省略せず完全に**使用する
   - タイトルはファイル内の最初の`#`見出しまたはファイル名から生成
   - 本文はファイル内容をそのまま使用（要約・短縮禁止）
3. **ラベル検証**: 利用可能なラベルを取得し、推論ラベルを検証
   ```bash
   gh label list --json name --jq '.[].name'
   ```
4. **ラベル自動推論**: タイトル+本文から推論（検証済みラベルのみ使用）
5. **タスク数確認**: 8個以上で警告表示（分割推奨）
6. **GitHub Issue作成**: `gh issue create`
   - **🚨 重要**: `--body`にはファイル内容を**完全に**渡す（省略禁止）
7. **GitHub Projects追加**: `gh_projects_set_todo`
8. **結果表示**: Issue番号とURL

**ラベルフォールバックマッピング**:
存在しないラベル推論時は以下で代替:

| 推論ラベル | フォールバック |
|-----------|---------------|
| type:feature | enhancement（存在する場合） |
| type:bug | bug（存在する場合） |
| type:* | スキップ（警告表示） |
| scope:* | スキップ（警告表示） |
| priority:* | スキップ（警告表示） |

**ラベルなし時**: 警告表示のみ、Issue作成は続行

### close サブコマンド
1. **gh-retrospective.sh実行**（`--no-retro`がない場合）
   - 関連PR検索 → CodeRabbitコメント取得 → learnings.md追記
2. 完了サマリーをコメント投稿
3. GitHub Projects更新: `gh_projects_set_done`
4. Issueクローズ: `gh issue close [number]`
5. checkpoint削除: `delete_memory(memory_name="issue_{number}_checkpoint")`
6. ブレインストーミングファイル削除（該当する場合）

### 廃止されたサブコマンドへの対応
- `work`, `list`, `view`, `status`, `sync` → エラー表示と代替手段の案内

---

**Last Updated**: 2025-12-05
**Version**: 2.0.0 (簡素化 - create/close のみ)
