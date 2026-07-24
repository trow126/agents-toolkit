---
name: gh-index
description: Use when planning Issues for a project or when the user asks to survey/index the codebase（「プロジェクトを調査して」「インデックス化して」/gh-index）. プロジェクト構造を調査し Issue 作成の元ネタとなるナレッジインデックスを生成する（調査のみ・変更なし）。
---

# /gh-index - プロジェクトナレッジインデックス生成

> **コンセプト**: 調査のみ。出力はIssue作成のソース資料。プロジェクトの変更は行わない。

## Usage

```bash
/gh-index [target]    # 対象ディレクトリを分析（デフォルト: カレントディレクトリ）
/gh-index             # カレントディレクトリを分析
```

---

## 出力

単一ファイル: `claudedocs/project_index.md`

---

## ワークフロー（4フェーズ - 最大限の調査）

### Phase 1: Discovery（探索）

1. **プロジェクト全体スキャン**: ファイル検索 / 内容検索(grep相当) / ファイル読み込み / 必要最小限の `find` コマンド
2. **技術スタック検出**:
   - 言語: `.py`, `.ts`, `.js`, `.go`, `.rs` 等
   - フレームワーク: package.json, pyproject.toml, Cargo.toml
   - ビルドツール: Makefile, webpack.config, vite.config
3. **ドキュメント棚卸**: README, docs/, CHANGELOG, API docs
4. **エントリポイント**: main.*, index.*, src/*, app/*

```
調査手段:
- ファイル検索(`**/*` 相当)で全体構成を把握
- 内容検索で TODO/FIXME/依存関係パターンを検索
- ファイル読み込みで設定ファイルと主要コードを確認
- `find` コマンドは巨大リポジトリの件数確認など必要時のみ使用
```

---

### Phase 2: Deep Analysis（詳細分析）

1. **シンボル抽出**: 主要コードファイルを読み込み・内容検索で確認し、公開 class/function/API を抽出
2. **依存関係マッピング**:
   - 外部: requirements.txt, package.json の依存関係
   - 内部: import/require パターン
3. **アーキテクチャパターン**:
   - MVC, Clean Architecture, Domain-Driven
   - Monolith, Microservices, Monorepo
4. **品質メトリクス**:
   - 型ヒントカバレッジ（Python: mypy, TS: strict mode）
   - テストカバレッジ（tests/ ディレクトリ分析）
   - Docstring/JSDoc カバレッジ
5. **懸念事項検出**:
   - セキュリティ: ハードコードされた秘密情報、SQLインジェクションパターン
   - パフォーマンス: N+1クエリ、無制限ループ
   - 技術的負債: TODO/FIXME/HACK コメント

```
調査手段:
- 内容検索で `class|def|function|export|TODO|FIXME|HACK` を検索
- 内容検索で `password|secret|api_key|token` を検索
- ファイル読み込みで候補ファイルの周辺文脈を確認
```

---

### Phase 3: Indexing（インデックス化）

1. **構造のコンパイル**: 全調査結果をMarkdownに集約
2. **クロスリファレンス生成**: シンボルとその場所をリンク
3. **出力生成**: `claudedocs/project_index.md` に書き込み

---

### Phase 4: Issue Candidates（Issue候補）

1. **未ドキュメント領域**: ドキュメントのないファイル/シンボル
2. **改善推奨**: 品質ギャップ、テスト不足
3. **技術的負債**: TODO項目、非推奨パターン
4. **優先度分類**: 影響度に基づいてHigh/Medium/Low

---

## 出力フォーマット: project_index.md

```markdown
# Project Index: {project_name}

Generated: {timestamp}

## 概要

- Language: Python 3.11
- Framework: FastAPI
- Build: uv + pyproject.toml
- Test: pytest

## ディレクトリ構造

├── src/
│   ├── api/       # REST エンドポイント (12 files)
│   ├── core/      # ビジネスロジック (8 files)
│   └── models/    # データモデル (5 files)
├── tests/         # テストスイート (23 files)
└── docs/          # ドキュメント (2 files)

## 主要エントリポイント

| ファイル | 目的 |
|---------|------|
| src/main.py | アプリケーションエントリ |
| src/api/routes.py | ルート定義 |
| src/core/config.py | 設定 |

## コアシンボル

| シンボル | 場所 | 種別 | 説明 |
|---------|------|------|------|
| App | src/main.py:15 | Class | メインアプリケーション |
| UserService | src/core/users.py:28 | Class | ユーザービジネスロジック |
| get_user | src/api/users.py:42 | Function | ユーザー取得エンドポイント |

## 依存関係

### 外部

- fastapi: ^0.100.0
- pydantic: ^2.0.0
- sqlalchemy: ^2.0.0

### 内部モジュール依存関係

- src/api → src/core → src/models

## 品質メトリクス

| メトリクス | 値 | ステータス |
|-----------|-----|-----------|
| 型ヒントカバレッジ | 78% | ⚠️ |
| テストカバレッジ | 65% | ⚠️ |
| Docstringカバレッジ | 45% | ❌ |

## ドキュメント状況

| ドキュメント | ステータス | 備考 |
|-------------|-----------|------|
| README.md | ✅ | 存在、最新 |
| API docs | ❌ | 未作成 |
| Architecture | ❌ | 未作成 |

## 技術的負債

| 種別 | 件数 | 場所 |
|------|------|------|
| TODO | 12 | src/core/users.py:45, src/api/auth.py:23, ... |
| FIXME | 3 | src/models/order.py:78, ... |
| HACK | 1 | src/utils/cache.py:15 |

## セキュリティ懸念

| 問題 | 重要度 | 場所 |
|------|--------|------|
| ハードコードされたAPIキー | 🚨 High | src/config.py:12 |
| SQL文字列連結 | ⚠️ Medium | src/db/queries.py:34 |

## Issue候補

> Issue作成の元ネタ。優先度順。

### 高優先度

1. **APIドキュメント未作成**
   - 対象: src/api/ (全ファイル)
   - 影響: 開発者オンボーディングの遅延
   - Issue案: "docs: RESTエンドポイントのOpenAPIドキュメントを追加"

2. **セキュリティ: ハードコードされた認証情報**
   - 対象: src/config.py:12
   - 影響: コミット時のセキュリティ脆弱性
   - Issue案: "security: 認証情報を環境変数に移行"

### 中優先度

3. **core/ の型ヒントカバレッジ低下**
   - 対象: src/core/*.py (8 files)
   - 影響: IDE補完無効化、バグリスク
   - Issue案: "chore: コアビジネスロジックに型ヒントを追加"

4. **テストカバレッジギャップ**
   - 対象: src/core/users.py, src/core/orders.py
   - 影響: リファクタリング時のリグレッションリスク
   - Issue案: "test: ユーザーおよび注文サービスのユニットテストを追加"

### 低優先度

5. **Docstring未記述**
   - 対象: コードベースの55%
   - 影響: コード理解コスト
   - Issue案: "docs: パブリックAPIにDocstringを追加"

6. **技術的負債のクリーンアップ**
   - 対象: 16個のTODO/FIXME/HACK項目
   - 影響: メンテナンス負担の蓄積
   - Issue案: "chore: 技術的負債項目に対処"
```

---

## Tool Integration

| フェーズ | 手段 | 目的 |
|---------|-------------|------|
| Discovery | ファイル検索 / `find` | フルディレクトリスキャン |
| Discovery | ファイル検索 / ファイル読み込み | 設定/ドキュメントファイルの特定 |
| Analysis | 内容検索 / ファイル読み込み | コードシンボルの抽出 |
| Analysis | 内容検索 | パターン/懸念事項の検出 |
| Output | ファイル書き込み | project_index.md の書き込み |

---

## 自動検出ルール

### 言語検出

| ファイルパターン | 言語 |
|----------------|------|
| `*.py`, `pyproject.toml` | Python |
| `*.ts`, `*.tsx`, `tsconfig.json` | TypeScript |
| `*.js`, `*.jsx`, `package.json` | JavaScript |
| `*.go`, `go.mod` | Go |
| `*.rs`, `Cargo.toml` | Rust |
| `*.java`, `pom.xml` | Java |

### フレームワーク検出

| 指標 | フレームワーク |
|------|--------------|
| fastapi in deps | FastAPI |
| django in deps | Django |
| flask in deps | Flask |
| react in deps | React |
| vue in deps | Vue |
| next in deps | Next.js |
| express in deps | Express |

---

## 境界

### やること ✅

- プロジェクト構造の最大深度調査
- シンボル抽出と依存関係分析
- 品質メトリクスの計算
- 優先度付きIssue候補の特定
- `claudedocs/project_index.md` への出力

### やらないこと ❌

- プロジェクトファイルの変更
- 既存ドキュメントの編集
- Issueの自動作成（レビュー後に手動で実施）
- テストやビルドコマンドの実行
- コード変更

---

## 使用例

### 基本的な使い方

```
User: /gh-index

Assistant:
1. [Discovery] プロジェクト構造をスキャン中...
   - 検出: Python プロジェクト (pyproject.toml)
   - フレームワーク: FastAPI
   - 45 ソースファイル、23 テストファイル

2. [Analysis] シンボルを抽出中...
   - 12 クラス、45 関数を分析
   - 型カバレッジ: 78%
   - テストカバレッジ: 65%

3. [Indexing] インデックスを生成中...
   - claudedocs/project_index.md に書き込み

4. [Issue Candidates] 6件の候補を特定
   - High: 2 (API docs, security)
   - Medium: 2 (types, tests)
   - Low: 2 (docstrings, tech debt)

✅ インデックス生成完了: claudedocs/project_index.md
→ 候補を確認し、/gh-issue create でIssueを作成してください
```

### ディレクトリ指定

```
User: /gh-index src/

Assistant:
1. [Discovery] src/ のみをスキャン中...
   ...
```

---

## 関連コマンド

```bash
/gh-index              # プロジェクトインデックスを生成（このコマンド）
                       ↓
/gh-issue create       # 候補からIssueを作成
                       ↓
/gh-start 42           # Issueの作業を開始
```

---

## 実行指示

**あなたは今 `/gh-index` を実行しています。**

以下の手順に従ってください:

1. **対象ディレクトリを確認**:
   - 引数あり: 指定ディレクトリを対象にする
   - 引数なし: ユーザーのカレントディレクトリを対象にする

2. **Phase 1 - Discovery**:
   - ファイル検索でファイル構成を確認
   - 必要時のみ `find` コマンドで件数や深さを確認
   - 設定ファイルから言語/フレームワークを検出
   - ドキュメントファイルの棚卸

3. **Phase 2 - Analysis**:
   - 主要コードファイルを読み込み・内容検索で確認
   - 内容検索でTODO/FIXME/セキュリティ懸念を検出
   - 品質メトリクスを計算

4. **Phase 3 - Indexing**:
   - 調査結果をMarkdown形式にコンパイル
   - `claudedocs/` ディレクトリの存在を確認
   - `claudedocs/project_index.md` に書き込み

5. **Phase 4 - Issue Candidates**:
   - 影響度に基づいて調査結果を優先度付け
   - Issue タイトル案を生成
   - 出力ファイルに含める

6. **レポート**:
   - 調査結果のサマリー
   - 生成ファイルへのパス
   - Issueのレビューと作成を促す

---

**Last Updated**: 2026-01-26
**Version**: 1.0.0
