---
name: gh-start
description: "GitHub Issue駆動開発（v4）。Issue取得→実装→コミット→同期の4フェーズで確実に実行。"
argument-hint: "<issue-number>"
allowed-tools: Bash Read Glob Grep Edit Write Agent TaskCreate TaskUpdate TaskList
---

# /gh-start - GitHub Issue駆動開発

> **原則**: GitHub Issue = SSOT、TaskCreate = 進捗追跡、逐次実行 = 確実性

## Usage

```bash
/gh-start 42        # Issue #42 で作業開始
/gh-start           # アクティブIssue自動検出
```

---

## Phase 1: Fetch (Issue取得)

1. **checkpoint確認**: `.claude/checkpoints/issue_{N}_checkpoint.md` を確認
   - checkpoint存在 → レジュームを提案（残タスクのみ実行）
   - checkpoint不在 → 新規実行

2. **Issue取得**: `gh-issue-fetch.sh ${ISSUE_NUMBER}` を実行

3. **出力確認**: JSON形式で tasks, statistics を取得

4. **エラー時**: Issue番号確認を促す

```bash
# 実行コマンド
gh-issue-fetch.sh 42
```

**成功条件**: exit 0 + 有効なJSON + state == "open"

5. **checkpoint初期化**: `.claude/checkpoints/issue_{N}_checkpoint.md` にタスク一覧・状態を保存

---

## Phase 2: Execute (実装)

1. **TaskCreate構築**:
   - pending タスクのみ抽出
   - 各タスクに subject, description, activeForm を設定

2. **逐次実行** (タスクごとに):
   - TaskUpdate → `in_progress` に更新
   - **現在の owner（このセッション）が自分で実装・テスト・修正まで完遂する**（既定。委譲しない）
   - 完了後 → TaskUpdate → `completed` に更新
   - checkpoint更新: `.claude/checkpoints/issue_{N}_checkpoint.md` に完了タスクを記録

3. **エラー時**: エラー内容を表示して停止（checkpointは保存済みなので次回レジューム可能）

**逐次実行の理由**:
Issueタスクは暗黙的な順序依存を持つことが多い（タスク2がタスク1のコードに依存する等）。
確実性を優先し、1タスクずつ完了させる。

**委譲の条件（例外）**:
タスク数・ステップ数は委譲理由にならない。以下のいずれかに**明示的に該当する場合のみ** Agent tool を使い、該当理由と委譲先を checkpoint に 1 行記録する:

- **context isolation**: 大量の read-only 探索・長大ファイル読み込みが main context を汚染する → built-in Explore
- **specialist expertise**: 該当ドメインの高リスク・専門作業（CLAUDE.md のドメインスペシャリスト該当時のみ）
- **independent verification**: 高リスク変更の独立監査が必要 → `code-reviewer`（read-only。実装はさせない）
- **useful parallelism**: 相互依存のない独立検証を並行比較する場合のみ

委譲した場合も、結果の統合・最終検証・commit は owner が行う。委譲エージェントがエラーを返した場合、ユーザーに報告して指示を待つ。

---

## Phase 3: Commit (コミット)

全タスク完了後、変更をコミットする。

1. **差分確認**: `git status` と `git diff` で変更内容を確認
2. **lint/format**: プロジェクトのlint/formatツールを実行（存在する場合）
3. **自己検証** (`~/.agents/rules/learnings.md` ゲート):
   - No Fallbackポリシー違反がないか（`except: pass`, catch-all）
   - 型安全ガード（ゼロ除算、空配列、None処理）
   - テストが存在する場合、`uv run pytest` が通るか
4. **ステージング**: 変更ファイルを `git add` でステージング
5. **コミット**: Conventional Commits形式でコミット
   - コミットメッセージにIssue番号を含める
   - 例: `feat: implement user authentication (#42)`

```bash
# コミットメッセージ例
git commit -m "$(cat <<'EOF'
feat: {変更の要約} (#{ISSUE_NUMBER})

{タスク完了の詳細}

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4: Sync (GitHub同期)

1. **進捗更新**: `gh-progress-sync.sh --json '{...}'` で GitHub Issue に進捗コメント投稿
2. **チェックボックス更新**: 完了タスクを `[x]` にマーク
3. **全完了時**: 完了報告のみ行う（PR作成はしない）
   - 「全タスクが完了しました。変更内容を確認してください。」
   - PR作成はユーザーが明示的に依頼した場合のみ実行

```bash
# 進捗同期
gh-progress-sync.sh --json '{"issue": 42, "completed": [1,2], "total": 5, "task_name": "Task name"}'

# タスク個別チェック
gh-progress-sync.sh --check-task 42 "Implement login button"
```

---

## Error Handling

| フェーズ | エラー | 対応 |
|----------|--------|------|
| Fetch | Issue not found | Issue番号を確認してください |
| Fetch | Issue closed | 既にクローズ済みです |
| Execute | 実装失敗 | checkpointを保存して停止。次回 `/gh-start` でレジューム可能 |
| Commit | lint失敗 | 修正してから再コミット |
| Sync | コメント失敗 | `gh issue comment` で手動投稿してください |

---

## Examples

### 基本的な使い方
```
User: /gh-start 42

Claude:
1. [Checkpoint] 既存checkpoint確認 → なし（新規実行）
2. [Fetch] gh-issue-fetch.sh 42 実行
3. [Parse] 5タスク検出 (3 pending)
4. [Checkpoint] issue_42_checkpoint 保存
5. [TaskCreate] 3タスクを登録
6. [Execute] Task 1 開始...
   ... Task 1 完了 → checkpoint更新
   Task 2 開始...
   ... Task 2 完了 → checkpoint更新
   Task 3 開始...
   ... Task 3 完了 → checkpoint更新
7. [Commit] git add + git commit
8. [Sync] GitHub更新完了
9. [Done] 全タスクが完了しました。変更内容を確認してください。
```

### レジューム
```
User: /gh-start 42

Claude:
1. [Checkpoint] issue_42_checkpoint 検出
   → 5タスク中2タスク完了済み。残り3タスクを継続しますか？
2. [Execute] Task 3 から再開...
```

---

## Related Commands

- `/gh-issue` - Issue管理（作成・クローズ）
- `/gh-pr` - PR作成
- `/gh-review` - CodeRabbitレビュー対応

---

## Technical Details

**Scripts**:
- `~/.claude/bin/gh-issue-fetch.sh` - Issue取得・パース
- `~/.claude/bin/gh-progress-sync.sh` - GitHub同期
- `~/.claude/bin/parse_issue.py` - Markdownパース（gh-issue-fetch.sh が同一ディレクトリから解決）

**依存**:
- `gh` CLI (GitHub CLI)
- `jq` (JSONパース)
- `python3` (パーサースクリプト)
- ローカルcheckpoint: `.claude/checkpoints/issue_{N}_checkpoint.md`
