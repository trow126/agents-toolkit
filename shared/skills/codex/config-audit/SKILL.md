---
name: config-audit
description: >
  グローバル設定 (~/.codex/) の最新ベストプラクティス監査と改善提案。
  公式ドキュメント・GitHub・海外記事を調査し、問題検出と新機能活用を提案。
  Use on "config audit", "設定監査", "check my config", "audit settings".
---

# Config Audit

`~/.codex/` のグローバル設定を最新ベストプラクティスと突き合わせ、**問題検出 + 新機能による改善提案** を実行する。

## 2軸の監査

- **守り (Compliance)**: deprecated パターン、セキュリティ欠如、構文エラーの検出
- **攻め (Improvement)**: 新しく追加された公式機能で既存設定を改善できる機会の提案

---

## Arguments

- `$config-audit` — 全カテゴリでフル監査（公式ドキュメント + GitHub + 海外記事）
- `$config-audit <category>` — 特定カテゴリのみ実行

`$ARGUMENTS` のパース:
- 文字列がある → カテゴリ名として解釈
- 空 → 全カテゴリでフル監査

有効なカテゴリ名:

| Name | Scope |
|------|-------|
| `settings` | config.toml の構文・フィールド |
| `hooks` | Hook 種別・構造（hooks.json） |
| `deprecated` | 廃止パターン検出 |
| `features` | 新機能活用の機会 |
| `profiles` | config.toml の profile 定義の品質 |
| `skills` | Skill 定義の品質 |
| `agents-md` | AGENTS.md の構造 |
| `rules` | Rules の構成 |
| `security` | sandbox/approval/trust 設定 |
| `mcp` | MCP サーバー設定 |

---

## Phase 1: Web Research（動的ベストプラクティス取得）

Phase 2（設定読み取り）と並行して実行する。
2つの独立コンテキストの調査タスクを常に並列起動する（`codex exec`。read-only、コード編集はさせない）。

### 調査 1: 公式ドキュメント（必須）

`codex exec` に以下を指示して起動:

```
Codex CLI の公式ドキュメントを調査し、設定に関する最新のベストプラクティスと全機能を抽出してください。
これはリサーチタスクです。コードの編集は行わないでください。

Step 1: 利用可能なら OpenAI Docs MCP ツール（search_openai_docs / fetch_openai_doc）で
Codex CLI の設定・セキュリティ・hooks・skills・profiles に関する公式ページを検索してください。
利用できない場合は WebSearch で developers.openai.com 配下の該当ページを検索してください。
URLはハードコードせず、必ず検索で見つけてください。

Step 2: Codex 自身の自己知識（manual helper 相当のセルフドキュメント）でも
config.toml のスキーマ・フィーチャーフラグ・hooks.json の仕様を確認してください。

Step 3: 各ソースから以下を抽出してください:
1. 全設定フィールド名とデフォルト値の一覧（config.toml）
2. 新機能・新フィーチャーフラグ（最近追加されたもの）
3. deprecated / 廃止された機能とその代替
4. sandbox/approval/trust 設定の仕様
5. skill frontmatter フィールドの完全なリスト
6. Hook イベント種別の完全なリスト（hooks.json）
7. 明示されたベストプラクティスや推奨構成
8. セキュリティ推奨事項

出力フォーマット:
カテゴリ別に構造化して返してください。各項目にソースURLを付記してください。
```

**エラーハンドリング**:
- 検索で URL が見つからない → 該当カテゴリを `SKIPPED (source unavailable)` としてレポート
- 取得失敗 → WebSearch の snippet 情報で代替
- **調査1が完全失敗（公式ドキュメントゼロ取得）→ 動的カテゴリ（`settings`, `hooks`, `deprecated`, `features`）を `SKIPPED (official sources unavailable)` として記録し、静的カテゴリ監査は継続**

### 調査 2: 海外記事・GitHub・コミュニティ（任意 — 失敗しても続行）

`codex exec` に以下を指示して起動:

```
Codex CLI の設定に関する最新のベストプラクティスをWeb調査してください。
これはリサーチタスクです。コードの編集は行わないでください。

以下の検索を実行してください:

1. WebSearch: "Codex CLI" best practices configuration settings 2026
2. WebSearch: "Codex CLI" AGENTS.md tips setup guide 2026
3. WebSearch: "Codex CLI" hooks sandbox security guide 2026
4. WebSearch: site:github.com ".codex" config.toml
5. WebSearch: site:github.com openai/codex discussions
6. WebSearch: "Codex CLI" new features changelog 2026
7. WebSearch: "Codex CLI" configuration anti-patterns mistakes

上位の有望な結果を取得し、以下を抽出:
- 公式ドキュメントにない実践的なパターン
- 他のパワーユーザーの config.toml, AGENTS.md, hooks.json の設定例
- GitHub Issues/Discussions で報告されたバグや workaround
- 新機能の具体的な活用事例

品質フィルター:
- 2026年以降のコンテンツのみ採用
- 個人ブログの主観は INFO 扱い
- GitHub Issue/Discussion の技術的知見は WARNING 候補

出力フォーマット:
カテゴリ別に構造化し、各項目にソースURLと日付を付記してください。
```

**エラーハンドリング**:
- 全検索失敗 → レポートに `調査2: FAILED` を記録し、公式ドキュメントのみで監査続行

---

## Phase 2: Read Current Configuration（現在の設定収集）

Phase 1 と並行してメインコンテキストが直接実行する。独立コンテキストの委任は使わない。

読み取り対象:
1. `~/.codex/config.toml` — 全内容を読み込み（`[mcp_servers]`, `[agents]`, `[features]`, profile 定義を含む）
2. `~/.codex/AGENTS.md` — 全内容を読み込み（サイズ確認含む）
3. `~/.codex/rules/*.md` — ファイル一覧取得、各ファイルの先頭10行を読み込み（frontmatter確認）、`wc -l` でサイズ
4. `~/.agents/skills/*/` — ディレクトリ一覧取得。各ディレクトリについて `SKILL.md` の有無を確認し、存在する場合のみ先頭10行を読み込み
5. `~/.codex/hooks.json` — 読み込み（存在しない場合は「未作成」と記録）
6. `~/.codex/config.toml` 内の `[mcp_servers]` セクション — 平文クレデンシャルの有無を確認
7. `${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/config-audit/audit-history-codex.jsonl` — 存在する場合は末尾数件を読み込み、直近の比較可能な1件を前回差分用に保持

**ファイル不在時**: 「未作成（推奨構成なし）」としてレポートに記録。サイレントスキップ禁止。
`SKILL.md` がないスキルディレクトリも一覧から落とさず、Phase 3 で必ず `CRITICAL` 判定対象に含める。

---

## Phase 3: Compare & Audit（比較分析）

Phase 1 と Phase 2 の両方が完了してから実行する。

### 動的カテゴリ（Web調査結果と突き合わせ）

#### 1. settings — config.toml 構文・フィールド
- 公式で定義された全フィールドと現在の設定を比較
- deprecated な設定キー・フィーチャーフラグの検出
- 新しく追加されたフィールドの欠如

#### 2. hooks — Hook 種別・構造（hooks.json）
- 公式で定義された全 Hook イベントと現在の設定を比較
- 新しく追加された Hook 種別の活用機会
- timeout, type フィールドの推奨パターン

#### 3. deprecated — 廃止パターン検出
- 公式で廃止とされたパターンが残存していないか
- `codex features list` で `stage: removed` になっているフラグが `config.toml` で明示 enable されていないか

#### 4. features — 新機能活用の機会（攻め）
- 公式ドキュメントに記載され、ユーザーが未使用の機能を全て列挙
- 各機能の用途と、ユーザーの現設定にどう適用できるかを具体的に提案
- 例: 新フィーチャーフラグ、新 hook イベント、新しい sandbox モード、新 profile 活用

### 静的カテゴリ（SKILL.md 内ルールで判定）

#### 5. profiles — config.toml の profile 定義の品質
`~/.codex/config.toml` の `[profiles.*]` に対して:
- profile ごとに model / reasoning effort が明示されているか → INFO if missing
- 用途不明な profile（説明コメントがない）→ INFO

#### 6. skills — Skill 定義の品質
`~/.agents/skills/*/` の各ディレクトリに対して:
- SKILL.md ファイル存在 → CRITICAL if missing
- YAML frontmatter 存在 → WARNING if missing
- `name:` フィールド → 任意。未指定時はディレクトリ名にフォールバックするため finding なし
- `description:` フィールド → WARNING if missing
- ファイルサイズ 500行超 → WARNING

#### 7. agents-md — AGENTS.md の構造
- ファイルサイズ 200行以内 → WARNING if exceeded
- ハードコードされた絶対パス (`/home/`) → WARNING
- 安全ガードレール記載 → WARNING if missing

#### 8. rules — Rules の構成
- 必須ルール存在: safety相当, code-quality相当 → WARNING if missing
- 個別ファイルサイズ 100行超 → INFO

#### 9. security — sandbox/approval/trust 設定
- `approval_policy = "never"` かつ `sandbox_mode = "danger-full-access"` の組み合わせ → WARNING（意図的な高信頼設定か確認を促す。既定で誤りとはしない）
- `.env` 等クレデンシャルファイルへの読み取り制限がない → WARNING
- `[mcp_servers]` に平文クレデンシャル → CRITICAL

#### 10. mcp — MCP サーバー設定
- 平文クレデンシャル不在 → CRITICAL if found
- 環境変数参照（`${...}` 等）使用 → INFO

---

## Phase 4: Report（レポート出力）

### Severity ルール

| Severity | 基準 | ソース |
|----------|------|--------|
| CRITICAL | 公式で非推奨/廃止、セキュリティリスク | 公式ドキュメント |
| WARNING | 公式推奨に反する | 公式ドキュメント + GitHub Issues |
| INFO | コミュニティ推奨、軽微な改善 | ブログ・記事・GitHub |
| OPPORTUNITY | 新機能による改善機会 | 公式ドキュメント（+ 記事の活用事例） |

### レポートフォーマット

- 差分セクションは Phase 2 で読み込んだ `audit-history-codex.jsonl` の直近エントリがある場合のみ出力する
- 履歴がない場合は `初回実行` と明記し、数値を推測で埋めない
- `git log` は `~/.codex/` が git 管理されている場合のみ補助情報として付与する

```markdown
# Config Audit Report (YYYY-MM-DD)

## 調査ソース

| Source | URL | Status | Date |
|--------|-----|--------|------|
| 公式: Settings | [検索で見つけたURL] | OK/FAILED | YYYY-MM-DD |
| 公式: Security | ... | OK | ... |
| GitHub: [title] | [url] | OK | [date] |
| 記事: [title] | [url] | OK | [date] |

## Summary

| Category | Type | Status | Findings |
|----------|------|--------|----------|
| settings | Dynamic | PASS/WARN/FAIL | N issues |
| hooks | Dynamic | ... | ... |
| deprecated | Dynamic | ... | ... |
| features | Dynamic | - | N opportunities |
| profiles | Static | ... | ... |
| skills | Static | ... | ... |
| agents-md | Static | ... | ... |
| rules | Static | ... | ... |
| security | Static | ... | ... |
| mcp | Static | ... | ... |

**Score**: X CRITICAL | Y WARNING | Z INFO | W OPPORTUNITY

## 前回との差分（audit-history-codex.jsonl に前回データがある場合のみ）

| 指標 | 前回 (YYYY-MM-DD) | 今回 | 変化 |
|------|-------------------|------|------|
| CRITICAL | N | M | +/-X |
| WARNING | N | M | +/-X |
| OPPORTUNITY | N | M | +/-X |

設定変更: `git log --since="<前回日付>" --oneline ~/.codex/` の出力（git管理時）

## Issues（修正すべき問題）

### [CRITICAL] Category: 詳細
**Finding**: 問題の説明
**Source**: [URL]
**Location**: ~/.codex/file:line
**Recommendation**: 具体的な修正方法

### [WARNING] ...

### [INFO] ...

## Opportunities（新機能による改善提案）

### [OPPORTUNITY] 機能名
**Source**: [公式ドキュメントURL]
**現状**: ユーザーの現設定における状態
**提案**: この機能をどう活用できるか
**影響**: 何が改善されるか

## Actions Summary

| Priority | Count | Type |
|----------|-------|------|
| CRITICAL | N | Must fix |
| WARNING | N | Should fix |
| INFO | N | Consider |
| OPPORTUNITY | N | New feature adoption |
```

### 永続化

1. `${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/config-audit/audit-history-codex.jsonl` に追記:
```json
{"date":"YYYY-MM-DD","sources":{"official":N,"github":N,"blog":N,"failed":N},"scores":{"critical":N,"warning":N,"info":N,"opportunity":N},"git_hash":"<HEAD of ~/.codex/ if git managed>"}
```

2. `audit-history-codex.jsonl` への追記結果をレポート末尾に記録

---

## Safety

- **読み取り専用**: 設定ファイルの変更は一切行わない
- **ファイル不在**: サイレントスキップ禁止、レポートに記録
- **Web調査失敗**: 公式調査が完全失敗しても静的カテゴリ監査は続行し、動的カテゴリのみ `SKIPPED` とする
- **Bash**: 複合コマンド (`&&`, `||`) 禁止。各コマンドを個別に実行
