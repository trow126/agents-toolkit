---
name: config-audit
description: >
  グローバル設定 (~/.claude/) の最新ベストプラクティス監査と改善提案。
  公式ドキュメント・GitHub・海外記事を調査し、問題検出と新機能活用を提案。
  Use on "config audit", "設定監査", "check my config", "audit settings".
argument-hint: "[category]"
---

# Config Audit

`~/.claude/` のグローバル設定を最新ベストプラクティスと突き合わせ、**問題検出 + 新機能による改善提案** を実行する。

## 2軸の監査

- **守り (Compliance)**: deprecated パターン、セキュリティ欠如、構文エラーの検出
- **攻め (Improvement)**: 新しく追加された公式機能で既存設定を改善できる機会の提案

---

## Arguments

- `/config-audit` — 全カテゴリでフル監査（公式ドキュメント + GitHub + 海外記事）
- `/config-audit <category>` — 特定カテゴリのみ実行

`$ARGUMENTS` のパース:
- 文字列がある → カテゴリ名として解釈
- 空 → 全カテゴリでフル監査

有効なカテゴリ名:

| Name | Scope |
|------|-------|
| `settings` | settings.json の構文・フィールド |
| `hooks` | Hook 種別・構造 |
| `deprecated` | 廃止パターン検出 |
| `features` | 新機能活用の機会 |
| `agents` | Agent 定義の品質 |
| `skills` | Skill 定義の品質 |
| `claude-md` | CLAUDE.md の構造 |
| `rules` | Rules の構成 |
| `security` | deny リスト・クレデンシャル |
| `mcp` | MCP サーバー設定 |

---

## Phase 1: Web Research（動的ベストプラクティス取得）

Phase 2（設定読み取り）と並行して実行する。
2つの Agent を常に並列起動する。

### Agent 1: 公式ドキュメント（必須）

Agent ツールで起動:
- `subagent_type`: `general-purpose`
- 目的: 公式ドキュメントから最新ベストプラクティスと新機能を抽出

プロンプトに含める内容:

```
Claude Code の公式ドキュメントを調査し、設定に関する最新のベストプラクティスと全機能を抽出してください。
これはリサーチタスクです。コードの編集は行わないでください。

Step 1: WebSearch で以下を検索し、公式ドキュメントの現在のURLを特定してください。
URLはハードコードせず、必ず検索で見つけてください。

- site:docs.anthropic.com claude code settings
- site:docs.anthropic.com claude code security
- site:docs.anthropic.com claude code hooks
- site:docs.anthropic.com claude code skills
- site:docs.anthropic.com claude code agents
- site:docs.anthropic.com claude code memory CLAUDE.md

Step 2: 見つかった各ページを WebFetch で取得してください。

Step 3: 各ページから以下を抽出してください:
1. 全設定フィールド名とデフォルト値の一覧
2. 新機能・新フィールド（最近追加されたもの）
3. deprecated / 廃止された機能とその代替
4. permission 構文の仕様（allow/deny/ask のパターン）
5. フロントマターフィールドの完全なリスト（skills, agents それぞれ）
6. Hook イベント種別の完全なリスト
7. 明示されたベストプラクティスや推奨構成
8. セキュリティ推奨事項

出力フォーマット:
カテゴリ別に構造化して返してください。各項目にソースURLを付記してください。
```

**エラーハンドリング**:
- WebSearch で URL が見つからない → 該当カテゴリを `SKIPPED (source unavailable)` としてレポート
- WebFetch 失敗 → WebSearch の snippet 情報で代替
- **Agent 1 が完全失敗（公式ドキュメントゼロ取得）→ 動的カテゴリ（`settings`, `hooks`, `deprecated`, `features`）を `SKIPPED (official sources unavailable)` として記録し、静的カテゴリ監査は継続**

### Agent 2: 海外記事・GitHub・コミュニティ（任意 — 失敗しても続行）

Agent ツールで起動:
- `subagent_type`: `general-purpose`
- 目的: コミュニティの実践知と他ユーザーの設定例を収集

プロンプトに含める内容:

```
Claude Code の設定に関する最新のベストプラクティスをWeb調査してください。
これはリサーチタスクです。コードの編集は行わないでください。

以下の検索を実行してください:

1. WebSearch: "Claude Code" best practices configuration settings 2026
2. WebSearch: "Claude Code" CLAUDE.md tips setup guide 2026
3. WebSearch: "Claude Code" hooks permissions security guide 2026
4. WebSearch: site:github.com ".claude" settings.json
5. WebSearch: site:github.com anthropics/claude-code discussions
6. WebSearch: "Claude Code" new features changelog 2026
7. WebSearch: "Claude Code" configuration anti-patterns mistakes

上位の有望な結果を WebFetch で取得し、以下を抽出:
- 公式ドキュメントにない実践的なパターン
- 他のパワーユーザーの settings.json, CLAUDE.md, hooks の設定例
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
- 全検索失敗 → レポートに `Agent 2: FAILED` を記録し、公式ドキュメントのみで監査続行

---

## Phase 2: Read Current Configuration（現在の設定収集）

Phase 1 と並行してメインコンテキストが直接実行する。Agent は使わない。

読み取り対象:
1. `~/.claude/settings.json` — 全内容を Read
2. `~/.claude/CLAUDE.md` — 全内容を Read（サイズ確認含む）
3. `~/.claude/rules/*.md` — Glob でファイル一覧取得、各ファイルの先頭10行を Read（frontmatter確認）、Bash `wc -l` でサイズ
4. `~/.claude/agents/*.md` — 同上
5. `~/.claude/skills/*/` — Glob でスキルディレクトリ一覧取得。各ディレクトリについて `SKILL.md` の有無を確認し、存在する場合のみ先頭10行を Read
6. `~/.claude/hooks/*.sh` — Glob で一覧、Bash `ls -la` で実行権限確認
7. `~/.claude/.mcp.json` — Read（存在しない場合は「未作成」と記録）
8. `~/.claude/.claudeignore` — Read（存在しない場合は「未作成」と記録）
9. `${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/config-audit/audit-history.jsonl` — 存在する場合は末尾数件を Read し、直近の比較可能な1件を前回差分用に保持

**ファイル不在時**: 「未作成（推奨構成なし）」としてレポートに記録。サイレントスキップ禁止。
`SKILL.md` がないスキルディレクトリも一覧から落とさず、Phase 3 で必ず `CRITICAL` 判定対象に含める。

---

## Phase 3: Compare & Audit（比較分析）

Phase 1 と Phase 2 の両方が完了してから実行する。

### 動的カテゴリ（Web調査結果と突き合わせ）

#### 1. settings — settings.json 構文・フィールド
- 公式で定義された全フィールドと現在の設定を比較
- deprecated permission 構文の検出（例: `Bash(git:*)` コロン構文）
- 新しく追加されたフィールドの欠如

#### 2. hooks — Hook 種別・構造
- 公式で定義された全 Hook イベントと現在の設定を比較
- 新しく追加された Hook 種別の活用機会
- matcher, timeout, if フィールドの推奨パターン

#### 3. deprecated — 廃止パターン検出
- 公式で廃止とされたパターンが残存していないか
- 旧 permission 構文など、公式で明示的に deprecated / 廃止とされたもののみ対象

#### 4. features — 新機能活用の機会（攻め）
- 公式ドキュメントに記載され、ユーザーが未使用の機能を全て列挙
- 各機能の用途と、ユーザーの現設定にどう適用できるかを具体的に提案
- 例: 新フロントマターフィールド、新 hook イベント、sandbox、新 settings フィールド

### 静的カテゴリ（SKILL.md 内ルールで判定）

#### 5. agents — Agent 定義の品質
各 `~/.claude/agents/*.md` に対して:
- YAML frontmatter (`---`) の存在 → WARNING if missing
- `name:` フィールド → WARNING if missing
- `description:` フィールド → WARNING if missing
- `tools:` による制限 → INFO if missing

#### 6. skills — Skill 定義の品質
各 `~/.claude/skills/*/` ディレクトリに対して:
- SKILL.md ファイル存在 → CRITICAL if missing
- YAML frontmatter 存在 → WARNING if missing
- `name:` フィールド → 任意。未指定時はディレクトリ名にフォールバックするため finding なし
- `description:` フィールド → WARNING if missing
- ファイルサイズ 500行超 → WARNING

#### 7. claude-md — CLAUDE.md の構造
- ファイルサイズ 200行以内 → WARNING if exceeded
- `@import` による分割活用 → INFO
- 安全ガードレール記載 → WARNING if missing
- ハードコードされた絶対パス (`/home/`) → WARNING

#### 8. rules — Rules の構成
- 必須ルール存在: safety, code-quality, workflow → WARNING if missing
- 言語固有ルールに `paths:` frontmatter → INFO if missing
- 個別ファイルサイズ 100行超 → INFO

#### 9. security — deny リスト・クレデンシャル
deny リスト必須パターン:
- `Bash(rm -rf /)`, `Bash(rm -rf ~)` → WARNING if missing
- `Bash(git push --force *)`, `Bash(git push -f *)` → WARNING if missing
- `Bash(git reset --hard *)` → WARNING if missing
- `Bash(sudo *)` → WARNING if missing
- `Read(.env)`, `Read(.env.*)` → WARNING if missing
- `Write(.git/**)` → WARNING if missing
- `"Bash"` 単体が allow にある（全コマンド許可） → WARNING
- `.mcp.json` に平文クレデンシャル → CRITICAL

#### 10. mcp — MCP サーバー設定
- 平文クレデンシャル不在 → CRITICAL if found
- 環境変数 `$` / `${...}` 使用 → INFO

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

- 差分セクションは Phase 2 で読み込んだ `audit-history.jsonl` の直近エントリがある場合のみ出力する
- 履歴がない場合は `初回実行` と明記し、数値を推測で埋めない
- `git log` は `~/.claude/` が git 管理されている場合のみ補助情報として付与する

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
| agents | Static | ... | ... |
| skills | Static | ... | ... |
| claude-md | Static | ... | ... |
| rules | Static | ... | ... |
| security | Static | ... | ... |
| mcp | Static | ... | ... |

**Score**: X CRITICAL | Y WARNING | Z INFO | W OPPORTUNITY

## 前回との差分（audit-history.jsonl に前回データがある場合のみ）

| 指標 | 前回 (YYYY-MM-DD) | 今回 | 変化 |
|------|-------------------|------|------|
| CRITICAL | N | M | +/-X |
| WARNING | N | M | +/-X |
| OPPORTUNITY | N | M | +/-X |

設定変更: `git log --since="<前回日付>" --oneline ~/.claude/` の出力（git管理時）

## Issues（修正すべき問題）

### [CRITICAL] Category: 詳細
**Finding**: 問題の説明
**Source**: [URL]
**Location**: ~/.claude/file:line
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

1. `${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/config-audit/audit-history.jsonl` に追記:
```json
{"date":"YYYY-MM-DD","sources":{"official":N,"github":N,"blog":N,"failed":N},"scores":{"critical":N,"warning":N,"info":N,"opportunity":N},"git_hash":"<HEAD of ~/.claude/ if git managed>"}
```

2. `audit-history.jsonl` への追記結果をレポート末尾に記録

---

## Safety

- **読み取り専用**: 設定ファイルの変更は一切行わない
- **ファイル不在**: サイレントスキップ禁止、レポートに記録
- **Web調査失敗**: 公式 Agent が完全失敗しても静的カテゴリ監査は続行し、動的カテゴリのみ `SKIPPED` とする
- **Bash**: 複合コマンド (`&&`, `||`) 禁止。各コマンドを個別に実行
