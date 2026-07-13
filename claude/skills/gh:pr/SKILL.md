---
name: gh:pr
description: "PR作成を自動化。ブランチ検出・差分解析・タイトル/本文生成・Issue連携・push制御を一括実行"
argument-hint: "[base-branch]"
allowed-tools:
  - Agent
  - Bash
  - Read
  - Glob
  - Grep
---

# /gh:pr - PR 作成スキル

> **原則**: PR作成に特化。セルフレビューは Hook+rules が自動トリガー。レビュー結果は PR コメントに投稿するだけで、修正は開始しない。

## 使い方

```bash
/gh:pr            # ベースブランチ自動検出 (main/master)
/gh:pr develop    # ベースブランチ指定
```

---

## 制約

- **Bash 複合コマンド禁止**: `&&`, `||`, `;`, `|` を使わない。各コマンドは独立実行
- **`gh pr create` は1回のみ実行**: 失敗時はコマンドを表示してユーザーに手動委譲（Hook 多重発火防止）
- **レビュー後の即時修正禁止**: Agent のレビュー結果を受け取って、そのまま Edit/Write/Bash で修正・追加コミット・追加 push を開始しない

---

## Phase 1: 事前チェック

1. **未コミットチェック**: `git status --porcelain` を実行
   - 変更あり → 変更内容を `git diff` で確認し、Conventional Commits 形式でコミットを実行してから続行
   - 変更なし → 次へ

2. **ブランチ確認**: `git branch --show-current` を実行
   - 空（HEAD detached）→ エラー停止: 「ブランチが検出できません。feature ブランチで作業してください」
   - `main` または `master` → 変更内容からブランチ名を生成し `git checkout -b <branch>` で feature ブランチを作成。未コミット変更があればコミットしてから続行

3. **既存 PR チェック**: `gh pr list --head <current-branch> --json number,url` を実行
   - PR が存在 → PR URL を表示して終了: 「既存の PR があります: <URL>」

4. **ベースブランチ決定**:
   - 引数あり → `git show-ref --verify refs/heads/<arg>` で存在確認
     - 存在しない → エラー停止: 「ベースブランチ '<name>' が見つかりません」
   - 引数なし → `git show-ref --verify refs/heads/main` を試行、失敗なら `refs/heads/master`
     - どちらも存在しない → エラー停止: 「main/master ブランチが見つかりません。ベースブランチを引数で指定してください」

5. **コミット確認**: `git log <base>..HEAD --oneline` を実行
   - 0件 → エラー停止: 「ベースブランチ '<base>' との差分がありません」

**完了条件**: ブランチ名、ベースブランチ、コミット一覧が確定

---

## Phase 2: PR 内容生成

1. **差分取得**: `git diff <base>..HEAD` で全差分取得

2. **コミット一覧**: `git log <base>..HEAD --oneline` でメッセージ一覧取得

3. **タイトル生成**:
   - 単一コミット → コミットメッセージの1行目をそのまま使用（70文字超は切り捨て）
   - 複数コミット → 最多出現の Conventional Commits プレフィックスを採用し、変更の要約を生成（70文字以内）

4. **Issue 連携**:
   - ブランチ名から Issue 番号を正規表現で抽出
     - パターン: `issue-(\d+)`, `(\d+)-`, `feat/(\d+)`, `fix/(\d+)` 等
   - 未検出 → `Closes #N` を省略
   - 検出 → `gh issue view <N> --json title,body` で Issue 情報取得（PR本文の参考に使用）

5. **PR 本文生成**:

```markdown
## Summary
- (差分とコミットメッセージから変更内容を1-3個のバレットポイントで要約)

## Test plan
- [ ] (テスト手順のチェックリスト)

Closes #N  ← Issue 検出時のみ
```

**完了条件**: タイトルと本文のドラフトが完成

---

## Phase 3: プッシュ

1. **プッシュ**: `git push -u origin <current-branch>` を実行（独立コマンド）
   - 成功 → Phase 4 へ
   - 失敗時の対応:
     - reject → 「リモートに変更があります。`git pull --rebase` 後に再実行してください」で停止
     - auth error → 「認証エラー。`gh auth status` で確認してください」で停止
     - その他 → エラー内容を表示、手動 push を提案して停止

**完了条件**: リモートブランチが最新

---

## Phase 4: PR 作成

1. **PR 作成**: 以下のコマンドを**1回のみ**実行（独立コマンド）

```bash
gh pr create --title "<タイトル>" --body "$(cat <<'EOF'
<本文>
EOF
)" --base <base-branch>
```

2. **成功時**:
   - PR URL を表示
   - Phase 5 へ進む

3. **失敗時**:
   - エラー内容を表示
   - 実行すべきコマンドを表示してユーザーに手動実行を委譲
   - **リトライしない**（Hook 多重発火防止）

**完了条件**: PR URL が取得でき、PR 番号取得へ進める

---

## Phase 5: セルフレビューコメント投稿

> **必須ゲート**: PR 作成後は、`## Automated Code Review` コメントを PR に投稿するまで `/gh:pr` を完了してはならない。コメント投稿後は修正を始めず、ユーザー入力待ちで停止する。

1. **PR 番号取得**: `gh pr view --json number -q '.number'` を実行
   - 取得失敗 → PR URL とエラー内容を表示し、「セルフレビューコメント未投稿」で停止

2. **差分取得**: `gh pr diff <PR番号>` を実行
   - 取得失敗 → エラー内容を表示し、「セルフレビューコメント未投稿」で停止

3. **別コンテキストレビュー**: `Agent` でコードレビューを実施
   - 観点: バグ、セキュリティ、パフォーマンス、可読性、テスト漏れ
   - 出力形式は `pr-review` スキル（skills/pr-review/SKILL.md）の `## Automated Code Review` テンプレートに従う
   - 指摘がない場合も、要修正「なし」としてコメント本文を生成する
   - Agent にはレビューコメント本文の生成だけを依頼し、修正実装を依頼しない

4. **PR コメント投稿**: `gh pr comment <PR番号> --body '<レビュー結果>'` を実行
   - 投稿成功 → PR URL とセルフレビューコメント投稿完了を表示して停止
   - 投稿失敗 → エラー内容と投稿用コマンドを表示し、「セルフレビューコメント未投稿」で停止

5. **修正の扱い**:
   - セルフレビューコメント投稿前に、レビュー結果をその場で修正してはならない
   - 重大な問題が見つかった場合も、PR コメント投稿後に「未修正の指摘あり」と報告するだけに留める
   - 投稿後の修正は `/gh:review <PR番号>` またはユーザーの明示指示が次に来た場合のみ、追加コミットとして対応する
   - `/gh:pr` の同一実行内で、レビュー結果を理由にファイル編集・テスト実行・追加コミット・追加 push を行ってはならない

**完了条件**: PR に `## Automated Code Review` コメントが投稿済みで、修正作業を開始せず停止している

---

## エラーハンドリング

| 状態 | 対応 |
|------|------|
| 未コミットの変更あり | 変更内容を確認し、Conventional Commits 形式でコミットしてから続行 |
| HEAD detached | 「feature ブランチで作業してください」で停止 |
| main/master ブランチ | 変更内容からブランチ名を生成し feature ブランチを作成、コミットして続行 |
| 既存 PR あり | PR URL を表示して終了 |
| ベースブランチが存在しない | 「ベースブランチ '<name>' が見つかりません」で停止 |
| コミットなし | 「ベースブランチとの差分がありません」で停止 |
| push 失敗: reject | 「リモートに変更があります。`git pull --rebase` 後に再実行してください」 |
| push 失敗: auth error | 「認証エラー。`gh auth status` で確認してください」 |
| push 失敗: その他 | エラー内容を表示、手動 push を提案 |
| PR 作成失敗 | エラー内容とコマンドを表示。ユーザーに手動実行を委譲 |
| セルフレビューコメント投稿失敗 | エラー内容と投稿用コマンドを表示。「セルフレビューコメント未投稿」と明記して停止 |

---

## 使用例

```
# 基本
User: /gh:pr
Claude:
1. [チェック] 未コミット変更なし、ブランチ: feature/add-auth、既存PRなし
2. [ベース] main (自動検出)、3コミット
3. [生成] タイトル: "feat: add user authentication (#42)"
4. [確認] タイトル・本文をユーザーに表示
5. [push] git push -u origin feature/add-auth
6. [PR作成] gh pr create 実行 → PR URL 表示
7. [レビュー] Agent で別コンテキストレビュー
8. [コメント] gh pr comment で "## Automated Code Review" を投稿して停止

# gh:start との連携
User: /gh:start 42   → Issue #42 の作業完了
User: /gh:pr          → PR 作成
→ Hook + Phase 5 がセルフレビューコメント投稿を要求
→ 問題発見時は /gh:review で対応
```

---

## 関連コマンド

```
/gh:start 42    → Issue 駆動開発（実装・コミット）
/gh:pr          → PR 作成（本スキル）
                   ↓ Hook が自動レビュー
/gh:review      → レビュー指摘への対応
/gh:issue close → Issue クローズ・振り返り
```
