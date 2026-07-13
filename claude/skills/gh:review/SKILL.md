---
name: gh:review
description: Use when processing review feedback on an existing PR（「レビュー対応して」「指摘を反映して」/gh:review <PR番号>）. 全レビューソース（CodeRabbit・セルフレビュー・Codex等）の指摘を統合処理し、修正・テスト・再プッシュまで一貫実行。
argument-hint: "[pr-number]"
---

# /gh:review - 統合レビュー対応コマンド

> **核心**: 全ソース（CodeRabbit・セルフレビュー・Codex等）のレビュー指摘を統合し、Issue要件・プロジェクト方針との整合性を確認してから対応

## Triggers
- CodeRabbitがPRにレビューコメントを投稿した後
- セルフレビュー（Automated Code Review）がPRコメントとして投稿された後
- Codex等の外部レビューボットがレビューを投稿した後
- レビュー指摘への対応が必要な時
- PR修正サイクルの実行

## Usage

```bash
# PR番号を指定してレビュー対応開始
/gh:review 17

# 特定の指摘のみ処理
/gh:review 17 --comments 1,3,5

# 自動採用モード（Trivial指摘のみ自動修正）
/gh:review 17 --auto-trivial

# ドライラン（修正内容を確認のみ）
/gh:review 17 --dry-run
```


> **詳細フェーズ説明**: Phase 0-6 の具体的な yaml ブロック・ASCII art 表示例・分析ポイント・連携ポイントは [`${CLAUDE_SKILL_DIR}/phases-reference.md`](./phases-reference.md) を参照。

## Options

```bash
--dry-run           # 修正内容を表示のみ（実行しない）
--auto-trivial      # Trivial指摘は自動採用
--auto-all          # 全指摘を自動採用（確認なし・危険）
--comments <1,2,3>  # 特定のコメントのみ処理
--source <cr,sr,cx> # ソースフィルタ（cr=CodeRabbit, sr=Self-Review, cx=Codex）
--skip-tests        # テスト実行をスキップ（非推奨）
--no-push           # コミットまでで停止（pushしない）
--no-debt-tracking  # 技術的負債記録をスキップ（非推奨）
```

## エラーハンドリング

```bash
# PRが見つからない
→ エラー「PR #N が見つかりません」

# レビューコメントがない
→ 「レビューコメントがありません。CodeRabbitのレビュー完了を待ってください」

# ブランチがローカルにない
→ git fetch && git checkout で自動取得

# テスト失敗
→ 失敗テストを表示、修正を促す
→ --skip-tests で続行可能（非推奨）

# 修正適用失敗
→ 手動修正を促す、該当ファイルを開く
```

## 実行指示

**あなたは今、`/gh:review` コマンドを実行しています。**

### 見逃し防止ルール

```yaml
絶対禁止事項:
  - ❌ 「対応済み」マークを見て自動スキップ
  - ❌ 「推奨」「Trivial」を確認なしでスキップ
  - ❌ Phase 3 の AskUserQuestion を省略
  - ❌ コメント件数を確認せず完了宣言

jq 構文ルール (gh api --jq):
  - ⚠️ 文字列スライス (.body[:600]) を含むオブジェクト構築では括弧の閉じ順に注意
  - ✅ 正: {body: (.body[:600])}  ← () が {} の内側で閉じる
  - ❌ 誤: {body: (.body[:600)}   ← ) と } が逆
  - ⚠️ 複雑な --jq は事前にシンプルな式で動作確認してから拡張する

必須確認事項:
  - ✅ 取得した全コメントを一覧表形式でユーザーに提示
  - ✅ 推奨アクションを提示し、AskUserQuestion で一括確認
  - ✅ 「対応済み」でもユーザーに報告
  - ✅ 完了前に対応サマリーを表示（採用/却下/スキップ件数）
```


### 必須実行フロー

```yaml
1. Phase 0: コンテキスト読み込み
   - PR情報取得（ブランチ名、関連Issue）
   - Issue要件取得
   - CLAUDE.md / docs/PLAN.md 読み込み
   - claudedocs/technical_debt.md 読み込み → 未対応件数表示
   - ローカルブランチ準備

2. Phase 1: レビューコメント取得（🔴 全件・全ソース取得必須）
   - gh api でインラインコメント取得（CodeRabbit, Codex等）
   - gh api でPRコメント取得 → "## Automated Code Review" をパース（Self-Review）
   - severity/category で分類
   - ソース別・合計コメント数を記録: "N件のコメントを取得（CR: X, SR: Y, CX: Z）"

3. Phase 2: 整合性分析（🔴 必須）
   - 各指摘に対して整合性分析
   - Issue要件との照合
   - プロジェクト方針との照合
   - 推奨アクション決定

4. Phase 3: ユーザー判断（🔴 必須・一括確認）
   - 全コメントを一覧表形式で表示
   - AskUserQuestion 1回で一括確認（推奨通り/個別調整/全採用/全スキップ）
   - 「個別に調整」選択時のみ詳細確認モードへ
   - 却下確定後に CodeRabbit へ一括返信

5. Phase 3.5: 技術的負債追跡（🔴 必須・取りこぼし防止）
   - 却下/スキップした指摘を claudedocs/technical_debt.md に記録
   - 「スコープ外」却下時はフォローアップIssue作成を確認
   - 負債サマリー表示（累計件数）

6. Phase 4: 修正適用
   - 採用した指摘を修正
   - 修正サマリー表示

7. Phase 5: 検証（🔴 必須）
   - ruff check
   - ruff format
   - pytest

8. Phase 6: コミット & プッシュ
   - 確認付きコミット
   - プッシュ
   - 最終チェックリスト確認:
     ```
     ✅ 全 N 件のコメントを確認済み
     ✅ 対応: X件 / スキップ: Y件 / 却下: Z件
     ✅ 技術的負債記録: Y+Z件を追記
     ```
   - 再レビュー待ち案内
```

## 関連コマンド

```bash
/gh:start 42        # Issue作業開始
/gh:pr              # PR作成
/gh:review 17       # レビュー対応（このコマンド）
/gh:issue close 42  # Issue完了・振り返り
```

## Tips

- **Trivial も記録**: 後回しにする場合は必ず technical_debt.md に記録
- **却下は理由を明記**: CodeRabbit への返信で次回レビュー改善
- **テスト必須**: 修正後は必ずテスト実行
- **再レビュー自動**: push すれば CodeRabbit が自動で再確認

---

**Last Updated**: 2026-03-20
**Version**: 2.0.0
**Changelog**: 
- v2.0.0 - 統合レビュー対応: セルフレビュー（Automated Code Review）・Codex等のマルチソース統合、ソース別フィルタ、重複検出、セルフレビュー固有判断基準
- v1.2.0 - Phase 3.5 技術的負債追跡を追加し、長期的な見落としを防止
- v1.1.0 - コメント見落とし防止のためのCRITICALセクションを追加（Phase 3 の強制実行）
