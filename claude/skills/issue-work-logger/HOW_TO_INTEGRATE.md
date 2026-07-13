# TodoWrite自動追跡の統合方法

## 概要

TodoWrite操作後に自動的に以下を実行する仕組みを実装しました：
1. `auto_logger.py` - タスク状態変化をnotes.mdに記録
2. `sync_progress.py` - GitHub Issueに進捗を同期

## 実装済みコンポーネント

### 1. track_todowrite.sh
**場所**: `~/.claude/skills/issue-work-logger/scripts/track_todowrite.sh`

**役割**: TodoWrite操作後に呼び出されるメインスクリプト

**入力**: stdin経由でTodoWrite状態（JSON）

**動作**:
```bash
export CURRENT_ISSUE_NUMBER=42
echo "$TODOWRITE_JSON" | ~/.claude/skills/issue-work-logger/scripts/track_todowrite.sh
```

### 2. todowrite_monitor.sh
**場所**: `~/.claude/skills/issue-work-logger/scripts/todowrite_monitor.sh`

**役割**: セッション開始時の初期化スクリプト

**使用方法**:
```bash
source ~/.claude/skills/issue-work-logger/scripts/todowrite_monitor.sh 42
```

## Claudeへの統合方法

### オプションA: /gh:issue workコマンドに組み込む（推奨）

`/gh:issue work`コマンド実行時に自動的に監視を開始：

```markdown
# /gh:issue work コマンドの実装内で

1. Issue解析（issue-parser skill）
2. TodoWrite変換（issue-todowrite-sync skill）
3. **監視開始**:
   ```bash
   source ~/.claude/skills/issue-work-logger/scripts/todowrite_monitor.sh $ISSUE_NUMBER
   ```
4. TodoWrite表示

# その後、TodoWrite操作の度に:
echo "$TODOWRITE_JSON" | ~/.claude/skills/issue-work-logger/scripts/track_todowrite.sh
```

### オプションB: Claudeの明示的呼び出し

TodoWrite操作後にClaude自身が呼び出す：

```python
# Claude内部の疑似コード
def on_todowrite_change(todowrite_state):
    if os.environ.get('CURRENT_ISSUE_NUMBER'):
        todowrite_json = json.dumps(todowrite_state)
        subprocess.run(
            ['bash', '-c', 'echo "$1" | ~/.claude/skills/issue-work-logger/scripts/track_todowrite.sh'],
            input=todowrite_json,
            env={'CURRENT_ISSUE_NUMBER': issue_number}
        )
```

### オプションC: 手動呼び出し

必要に応じてユーザーが明示的に呼び出す：

```bash
# Issue作業開始時
export CURRENT_ISSUE_NUMBER=42

# TodoWrite操作後に手動実行
/gh:issue sync 42
```

## 環境変数

スクリプトが必要とする環境変数：

```bash
export CURRENT_ISSUE_NUMBER=42        # 必須：現在作業中のIssue番号
export WORK_DIR=~/claudedocs/work     # オプション：作業ディレクトリ（デフォルト: ~/claudedocs/work）
```

## セッションストレージ

自動的に以下のファイルが作成・更新されます：

```
~/.claude/.session/
├── todowrite_state.json      # TodoWrite前回状態（auto_logger用）
└── issue_mapping.json         # Issue-TodoWriteマッピング（sync_progress用）
```

## 動作フロー

```
/gh:issue work 42
  ↓
セッション初期化（CURRENT_ISSUE_NUMBER=42を設定）
  ↓
TodoWrite操作（ユーザーがタスク変更）
  ↓
track_todowrite.sh が呼び出される
  ├─ auto_logger.py: notes.mdに記録
  └─ sync_progress.py: GitHub Issueを更新
```

## テスト方法

### 手動テスト

```bash
# 1. 環境設定
export CURRENT_ISSUE_NUMBER=999
mkdir -p ~/claudedocs/work

# 2. TodoWrite状態をシミュレート
cat <<'JSON' | ~/.claude/skills/issue-work-logger/scripts/track_todowrite.sh
[
  {"content": "Task 1: Test", "status": "completed", "activeForm": "Testing"}
]
JSON

# 3. 結果確認
cat ~/claudedocs/work/issue_999_notes.md
cat ~/.claude/.session/todowrite_state.json
```

### 統合テスト

```bash
cd ~/.claude/skills/issue-work-logger/scripts
bash test_auto_logger.sh
cd ~/.claude/skills/progress-tracker/scripts
bash test_sync_progress.sh
```

## 次のステップ

実際に動作させるには、Claudeが以下のいずれかを実装する必要があります：

1. **自動統合**（理想）:
   - TodoWriteツール使用後に自動的に`track_todowrite.sh`を呼び出す
   - `/gh:issue work`実行時にCURRENT_ISSUE_NUMBERを自動設定

2. **スキルベース統合**（現実的）:
   - `/gh:issue work`内で明示的にスクリプトを呼び出す
   - Claudeが「TodoWrite操作後にtrack_todowrite.shを実行する」ルールを持つ

3. **手動統合**（フォールバック）:
   - `/gh:issue sync`コマンドをユーザーが手動実行
   - 進捗更新が必要な時だけ呼び出す

## 実装状況

✅ **完全実装済み**:
- auto_logger.py（自動記録）
- sync_progress.py（GitHub同期）
- track_todowrite.sh（統合ラッパー）
- todowrite_monitor.sh（セッション初期化）
- 統合テストスイート

⚠️ **要統合**:
- Claude CodeがTodoWrite操作後に`track_todowrite.sh`を呼び出す仕組み
- `/gh:issue work`コマンドでのCURRENT_ISSUE_NUMBER自動設定

## トラブルシューティング

### 記録されない場合

1. 環境変数が設定されているか確認:
   ```bash
   echo $CURRENT_ISSUE_NUMBER
   ```

2. スクリプトが実行可能か確認:
   ```bash
   ls -l ~/.claude/skills/issue-work-logger/scripts/track_todowrite.sh
   ```

3. 手動で実行してエラーを確認:
   ```bash
   echo '[]' | ~/.claude/skills/issue-work-logger/scripts/track_todowrite.sh
   ```

### GitHub同期が失敗する場合

1. gh CLIがインストールされているか確認:
   ```bash
   gh --version
   ```

2. 認証されているか確認:
   ```bash
   gh auth status
   ```

3. Issueが存在するか確認:
   ```bash
   gh issue view $CURRENT_ISSUE_NUMBER
   ```
