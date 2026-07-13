# phases-reference.md - /gh:review 詳細フェーズ参照

> このファイルは /gh:review の詳細フェーズ参照です。実行指示・必須フローは SKILL.md を参照してください。

## Behavioral Flow

### Phase 0: コンテキスト読み込み

```yaml
1. PR情報取得:
   gh pr view <number> --json headRefName,body,title
   → PRブランチ名、関連Issue番号を抽出

2. 関連Issue取得（"Closes #N" から）:
   gh issue view <N> --json body,title
   → Issue要件を取得

3. プロジェクト方針読み込み:
   - CLAUDE.md（コーディング規約）
   - docs/PLAN.md（アーキテクチャ方針）
   - .coderabbit.yaml（レビュー設定）

4. 技術的負債状況確認:
   claudedocs/technical_debt.md を読み込み
   → 未対応件数を表示:
   ┌──────────────────────────────────────┐
   │ ⚠️ 技術的負債: 12件の未対応指摘あり  │
   │   - Critical: 2件                   │
   │   - High: 5件                       │
   │   - Medium: 5件                     │
   └──────────────────────────────────────┘

5. ローカルブランチ準備:
   git fetch origin <branch>
   git checkout <branch>
   # または worktree の場合は cd
```

### Phase 1: レビューコメント取得（マルチソース）

```yaml
5. レビューソース別取得:

   a. インラインレビューコメント（CodeRabbit, Codex等）:
      gh api repos/{owner}/{repo}/pulls/{number}/comments
      → source: コメント author から判定
        - "coderabbitai" → "CodeRabbit"
        - "chatgpt-codex-connector" → "Codex"
        - その他 → author名

   b. PRコメント（セルフレビュー等）:
      gh api repos/{owner}/{repo}/issues/{number}/comments
      → "## Automated Code Review" ヘッダーを含むコメントを検出
      → source: "Self-Review"

6. セルフレビューコメントのパース:

   "## Automated Code Review" コメントから構造化データを抽出:

   a. 「要修正」テーブル:
      severity: major/critical（修正必須）
      → 各行から {箇所, 問題, 推奨対応} を抽出

   b. 「改善提案」テーブル:
      severity: minor（任意採用）
      → 各行から {箇所, 提案, 理由} を抽出

   c. 「確認事項」リスト:
      severity: info（設計判断の確認）
      → 各項目を question として抽出

   ※ 「なし」「修正済み」等の場合はスキップ

7. コメント分類（全ソース統合）:
   - Potential issue (🟡 Minor, 🔴 Major)
   - Nitpick (🔵 Trivial)
   - Question (ℹ️ Info)
   - Suggestion

8. 各コメントを構造化:
   {
     id: "comment_id",
     source: "CodeRabbit",  # CodeRabbit, Self-Review, Codex, etc.
     path: "src/data/realtime.py",
     line: 276,
     severity: "minor",  # trivial, minor, major, critical, info
     category: "bug",    # bug, style, performance, security, design
     body: "asyncio.create_task の参照を保持...",
     suggested_fix: "diff code block if present"
   }

9. ソース別サマリー表示:
   ┌────────────────────────────────────────┐
   │ 📥 レビュー取得完了                    │
   │   CodeRabbit:   4件（inline comments） │
   │   Self-Review:  3件（要修正0/提案2/確認1）│
   │   Codex:        2件（inline comments） │
   │   合計:         9件                    │
   └────────────────────────────────────────┘
```

### Phase 2: 整合性分析（各指摘に対して）

```yaml
8. 🔴 整合性分析（必須・各指摘に対して実行）:

   a. Issue要件との整合性:
      - 指摘が Issue の要件範囲内か
      - 修正が Issue の成果物に影響するか
      - スコープ外の変更を要求していないか

   b. プロジェクト方針との整合性:
      - CLAUDE.md のコーディング規約に沿うか
      - アーキテクチャ方針と矛盾しないか
      - 既存パターンと一貫性があるか

   c. 技術的妥当性:
      - 指摘内容が技術的に正しいか
      - 副作用やリグレッションのリスク
      - 修正コストと効果のバランス

9. 推奨アクション決定:

   採用 (accept):
     - バグ修正（技術的に正しい指摘）
     - セキュリティ問題
     - 明確なパフォーマンス改善
     - プロジェクト規約違反の修正

   検討 (discuss):
     - 大規模リファクタリング提案
     - トレードオフのある変更
     - Issue スコープ境界の変更

   却下 (reject):
     - Issue スコープ外
     - プロジェクト方針と矛盾
     - 過度な最適化要求
     - 誤った指摘（false positive）
```

### Phase 3: ユーザー判断（一括確認）

```yaml
10. 全指摘を一覧表示（ソース統合）:

    ┌──────────────────────────────────────────────────────────────────────┐
    │ 📋 レビュー指摘一覧 (9件)  [CR=CodeRabbit, SR=Self-Review, CX=Codex]│
    ├─────┬──────┬───────────────────────┬────────┬────────┬──────────────┤
    │ #   │ Src  │ ファイル:行           │ 重要度 │ 整合性 │ 推奨         │
    ├─────┼──────┼───────────────────────┼────────┼────────┼──────────────┤
    │ 1   │ CR   │ realtime.py:276       │ 🟡 Minor│ ✅     │ 採用        │
    │ 2   │ CR   │ realtime.py:392       │ 🟡 Minor│ ✅     │ 採用        │
    │ 3   │ CR   │ stream_data.py:118    │ 🔵 Triv │ ✅     │ スキップ    │
    │ 4   │ SR   │ simulator.py:164      │ 🟡 Minor│ ✅     │ 検討        │
    │ 5   │ SR   │ test_asset_meta...:*  │ 🔵 Triv │ ✅     │ スキップ    │
    │ 6   │ SR   │ types.py:27           │ 🔵 Triv │ ✅     │ スキップ    │
    │ 7   │ SR   │ （確認事項）          │ ℹ️ Info │ —      │ 回答のみ    │
    │ 8   │ CX   │ auth.py:45            │ 🟡 Minor│ ⚠️ 外  │ 却下        │
    │ 9   │ CX   │ stream_data.py:317    │ 🟡 Minor│ ✅     │ 採用        │
    └─────┴──────┴───────────────────────┴────────┴────────┴──────────────┘

    各指摘の詳細（折りたたみ表示・ソース別アイコン付き）:
    
    <details>
    <summary>#1 [CR] realtime.py:276 - asyncio.create_task 参照保持</summary>
    
    🏷️ ソース: CodeRabbit (inline comment)
    💬 指摘内容: asyncio.create_task の参照を保持する必要あり
    📋 Issue整合性: ✅ 接続安定性要件に直接関連
    📐 方針整合性: ✅ CLAUDE.md のエラーハンドリング方針
    📝 修正案: `self._task = asyncio.create_task(...)`
    </details>
    
    <details>
    <summary>#4 [SR] simulator.py:164 - debt-only アセットの軽量 fetch 分離</summary>
    
    🏷️ ソース: Self-Review (改善提案)
    💬 指摘内容: debt-only アセットは liquidation_bonus 不要なので軽量 fetch に分離可能
    📋 Issue整合性: ✅ パフォーマンス最適化の範囲内
    📐 方針整合性: ⚠️ 現状 Aave V3 では実質差なし（premature optimization 注意）
    📝 修正案: パフォーマンス測定後に判断
    </details>
    
    <details>
    <summary>#7 [SR] （確認事項）- unique_assets の設計判断</summary>
    
    🏷️ ソース: Self-Review (確認事項)
    💬 確認内容: unique_assets に全 debt アセットを含める設計の妥当性
    📋 対応: 設計判断の回答（コード修正不要）
    📝 回答案: multi-protocol 拡張を見越した意図的な設計
    </details>
    
    （以下同様に全件表示）

11. AskUserQuestion（1回のみ・一括確認）:

    "上記の推奨アクションで進めますか？"
    
    選択肢:
      - 推奨通り実行（採用3件、スキップ3件、却下1件、回答のみ1件、検討1件）
      - 個別に調整する → 詳細確認モードへ（後述）
      - 全て採用
      - 全てスキップ
      - ソース別にフィルタ（例: Self-Reviewのみ処理）

12. 「個別に調整する」選択時のみ詳細確認:

    AskUserQuestion（multiSelect: true）:
    "変更したい指摘を選択してください"
    
    選択肢:
      - #1 realtime.py:276 [現在: 採用] → 却下に変更
      - #3 stream_data.py:118 [現在: スキップ] → 採用に変更
      - #4 auth.py:45 [現在: 却下] → 採用に変更
      - #5 util.py:120 [現在: スキップ] → 採用に変更
    
    ※ 却下に変更した指摘は理由入力を求める

13. 却下指摘への返信（ソース別にまとめて実行）:

    a. CodeRabbit 指摘の却下返信:
    gh pr comment <number> --body "
    @coderabbitai
    以下の指摘について対応を見送ります:
    **auth.py:45** - Issue #8 スコープ外のため
    フォローアップは Issue #XX で対応予定です。
    "

    b. セルフレビュー指摘の却下/スキップ:
    → 返信不要（自己生成コメントのため）
    → technical_debt.md への記録のみ

    c. Codex/その他ボット指摘の却下返信:
    gh pr comment <number> --body "
    以下のレビュー指摘について対応を見送ります:
    **[ファイル:行]** - [理由]
    "
```

### Phase 3.5: 技術的負債追跡（必須）

```yaml
12. 却下/スキップした指摘を記録（🔴 CRITICAL - 取りこぼし防止）:

    記録対象:
      - 却下した指摘（reject）
      - スキップした指摘（skip）
      - 「スコープ外」として見送った指摘

    claudedocs/technical_debt.md に追記:
    ```markdown
    ## PR #17 (2026-01-27)
    
    ### 却下
    | ファイル | 行 | 重要度 | 指摘内容 | 却下理由 |
    |----------|-----|--------|----------|----------|
    | src/auth.py | 45 | 🟡 Minor | 入力バリデーション追加 | Issue #8 スコープ外 |
    
    ### スキップ（後で対応）
    | ファイル | 行 | 重要度 | 指摘内容 |
    |----------|-----|--------|----------|
    | src/util.py | 120 | 🔵 Trivial | docstring追加 |
    ```

13. 🔴 「スコープ外」却下時の追加確認:

    技術的に正しい指摘を「スコープ外」で却下する場合:

    AskUserQuestion:
      "⚠️ 技術的に正しい指摘をスコープ外で却下します。
       
       指摘: src/auth.py:45 - 入力バリデーション追加
       
       フォローアップ対応:
       1. 新規Issueを作成する（推奨）
       2. technical_debt.md に記録のみ
       3. 対応不要（本当に不要な場合のみ）"

    新規Issue作成時:
      gh issue create --title "Tech debt: [指摘内容]" \
        --body "元PR: #17\n元指摘: [内容]\n理由: スコープ外\n\n対応方針: TBD"

14. 負債サマリー表示:
    ┌──────────────────────────────────────────┐
    │ 📊 技術的負債更新                        │
    │                                          │
    │ 今回追加: 3件                            │
    │   - 却下: 1件（→ Issue #45 作成済み）   │
    │   - スキップ: 2件                        │
    │                                          │
    │ 累計未対応: 15件（+3）                   │
    │   ⚠️ 20件超過で警告レベル上昇           │
    └──────────────────────────────────────────┘
```

### Phase 4: 修正適用

```yaml
12. 採用した指摘を適用:

    for comment in accepted_comments:
      if comment.suggested_fix:
        # 提案された diff を適用
        apply_suggested_fix(comment)
      else:
        # 手動で修正実装
        implement_fix(comment)

      # 修正後にファイル内容を確認
      verify_fix(comment.path)

13. 修正サマリー表示:
    ✅ Applied 4/6 fixes:
    - src/data/realtime.py:276 - asyncio.create_task 参照保持
    - src/data/realtime.py:392 - 同上
    - src/data/realtime.py:399 - 同上
    - scripts/stream_data.py:317 - signal_handler タスク参照

    ⏭️ Skipped 2/6:
    - scripts/stream_data.py:118 - asyncio.Event (Trivial)
    - scripts/stream_data.py:213 - 冗長チェック (Trivial)
```

### Phase 5: 検証

```yaml
14. Lint チェック:
    uv run ruff check src/ scripts/

    エラー時:
    - 自動修正可能 → uv run ruff check --fix
    - 手動修正必要 → 該当箇所を表示

15. フォーマットチェック:
    uv run ruff format --check src/ scripts/

    差分あり → uv run ruff format src/ scripts/

16. テスト実行:
    uv run pytest tests/ -v

    失敗時:
    - 失敗テストを表示
    - 修正箇所との関連を分析
    - 追加修正が必要か判断

17. 検証結果サマリー:
    ✅ Lint: passed
    ✅ Format: passed
    ✅ Tests: 56 passed in 1.2s
```

### Phase 6: コミット & プッシュ

```yaml
18. 確認付きコミット:

    AskUserQuestion:
      "📋 コミット・プッシュを実行しますか？

       修正ファイル: 3 files
       テスト: ✅ All passed

       コミットメッセージ:
       fix(data): Address CodeRabbit review comments

       - Hold asyncio.create_task references to prevent GC
       - Fix signal handler task reference

       1. 実行する（推奨）
       2. メッセージ編集
       3. スキップ"

19. コミット実行:
    git add <modified_files>
    git commit -m "<message>"

20. プッシュ:
    git push origin <branch>

21. 完了メッセージ:
    ✅ Changes pushed to origin/issue-8

    CodeRabbit が自動で再レビューを開始します。
    確認: https://github.com/owner/repo/pull/17

    次のステップ:
    - 再レビュー結果を待つ
    - 追加指摘があれば /gh:review 17 を再実行
    - レビュー通過後 gh pr merge 17
```

## 連携ポイント

```yaml
レビューソース:
  CodeRabbit:
    - gh api pulls/{n}/comments: インラインレビューコメント取得
    - gh pr comment: 却下理由の返信（@coderabbitai メンション）
  Self-Review:
    - gh api issues/{n}/comments: PRコメントから "## Automated Code Review" を検出
    - パース対象: 要修正テーブル、改善提案テーブル、確認事項リスト
    - 返信不要（自己生成のため）
  Codex/その他:
    - gh api pulls/{n}/reviews: レビューコメント取得
    - author で自動判定: "chatgpt-codex-connector" → Codex

Issue連携:
  - PR body から "Closes #N" を抽出
  - Issue 要件との整合性確認

プロジェクト文脈:
  - CLAUDE.md: コーディング規約
  - docs/PLAN.md: アーキテクチャ方針
  - .coderabbit.yaml: レビュー設定

検証ツール:
  - ruff check/format: Lint・フォーマット
  - pytest: テスト実行
```

### 指摘分析のポイント

```yaml
採用すべき指摘（全ソース共通）:
  - バグ（GC、メモリリーク、競合状態）
  - セキュリティ（入力検証、認証）
  - 明確なパフォーマンス問題
  - 規約違反（型ヒント欠落、docstring不足）

検討が必要な指摘:
  - アーキテクチャ変更を伴う提案
  - 大規模リファクタリング
  - Issue スコープ境界

却下候補の指摘:
  - Issue スコープ外の機能追加
  - 過度な最適化（premature optimization）
  - プロジェクト方針と矛盾する変更
  - 誤検知（false positive）

セルフレビュー固有の判断基準:
  要修正テーブル:
    - 「なし」「修正済み」→ 自動スキップ（対応不要）
    - 具体的な指摘あり → 原則採用（自己検出バグ）
  改善提案テーブル:
    - 「現状問題なし」注記あり → スキップ（後日対応）
    - 明確な改善 → 採用
    - 「パフォーマンス測定後に判断」等 → 検討（条件付き）
  確認事項リスト:
    - 設計判断の確認 → 回答のみ（コード修正不要）
    - 「回答のみ」として処理し、PRコメントで設計意図を回答

ソース間の重複検出:
  - 同一ファイル:行 への指摘が複数ソースから来た場合
    → 重複マーク付きで1つに統合
    → 最も具体的な修正案を採用
```
