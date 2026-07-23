---
name: knowledge-audit
description: >
  Audit and compress claudedocs/learnings.md and technical_debt.md files.
  Removes redundancy, deduplicates patterns, and produces compressed pattern catalogs.
  Use when files are bloated, on "棚卸し", "audit learnings", "compress learnings",
  "prune learnings", "audit technical debt", or "knowledge audit".
---

# Knowledge Audit Skill

claudedocs/learnings.md と technical_debt.md の棚卸し・圧縮を実行する。

## When to Use

- `棚卸し` (standalone or with project name)
- `audit learnings` / `compress learnings` / `prune learnings`
- `audit technical debt`
- `knowledge audit`

---

## Scope Detection

1. **Explicit**: `棚卸し my-project` → target that project
2. **Auto-detect**: cwd contains `claudedocs/learnings.md` → target current project
3. **Discovery**: List all `claudedocs/learnings.md` and `technical_debt.md` with line counts, ask user to choose

```bash
find ~ -maxdepth 5 -name "learnings.md" -path "*/claudedocs/*" 2>/dev/null
find ~ -maxdepth 5 -name "technical_debt.md" -path "*/claudedocs/*" 2>/dev/null
```

---

## Mode A: learnings.md Audit

### Phase 1: Analysis (Read-Only)

#### Step 1: Detect File State

| State | Detection | Example |
|-------|-----------|---------|
| A: Raw only | No `# パターンカタログ` or numbered `# 1.` sections; only `## Issue #N:` entries | repo-alpha |
| B: Hybrid | Has pattern catalog section AND raw issue log entries below | repo-beta, repo-gamma |
| C: Compressed | Has `v2.0 (Compressed)` or version header; no raw issue entries | repo-delta (no action needed) |

#### Step 2: Classify Each Issue Entry

Parse `## Issue #N:` entries and classify:

| Category | Rule | Action |
|----------|------|--------|
| EMPTY | All retrospective fields blank, CodeRabbit = 0 | DELETE |
| BOILERPLATE | Has CodeRabbit data but retrospective is empty template | DELETE (extract CodeRabbit data first) |
| DUPLICATE | Findings match existing pattern catalog entries (same Ruff rule, same bug pattern) | MERGE issue reference into existing pattern |
| EXTRACT | Contains novel pattern, specific bug fix, estimation data, or reusable code reference | EXTRACT to new pattern catalog entry |

#### Step 3: Check Global Promotion

Compare extracted patterns against the candidate ledger `${XDG_STATE_HOME:-$HOME/.local/state}/agents-toolkit/knowledge-audit/promotion-candidates.md` (untracked; create from its header format if missing) and existing global knowledge:

- **Promote if**: pattern is generalizable (not domain-specific) AND appears in 2+ projects — evidenced by a ledger hit, an existing global entry, or direct observation in this audit
- **Register as candidate if**: generalizable but first sighting (1 project only) → append one line to the ledger: `- [slug] | 初出: <project> <YYYY-MM-DD> | <one-line summary>`
- **Do NOT promote**: domain-specific patterns (horse racing, DeFi, ML training specifics)

Promotion destinations (常時ロード削減方針に従い二股。いずれも共有正本 — 追記後 `~/.agents/bin/sync-shared-rules.sh` を実行):
- 言語/フレームワーク固有 (Ruff rules, Python idioms, async, pytest) → `~/.agents/rules/python-guidelines.md`
- 言語非依存 (CLI, git, ツール運用) → `~/.agents/rules/learnings.md`

#### Step 4: Generate Audit Report

```markdown
## 棚卸し分析レポート (YYYY-MM-DD)

### 対象: [project]/claudedocs/learnings.md
### ファイル状態: [A/B/C]

| 指標 | Before | After (予測) | 削減率 |
|------|--------|-------------|--------|
| 行数 | N | ~M | X% |
| Issueエントリ数 | N | 0 (索引化) | 100% |
| パターンカタログ項目 | N | M (+Δ new) | - |

### 処理内訳

| 分類 | 件数 | 対象 |
|------|------|------|
| 空エントリ削除 | N件 | Issue #X, #Y, #Z... |
| 重複パターン統合 | N件 | G004 (x5), TRY401 (x3)... |
| 新規パターン抽出 | N件 | [Pattern descriptions] |
| グローバル昇格候補 | N件 | [Patterns found in 2+ projects] |
```

#### Step 5: Ask for Confirmation

Display the audit report. Ask user to confirm before proceeding to Phase 2.

### Phase 2: Compression (Write)

**CRITICAL: UTF-8 safety**. All learnings files contain Japanese. Use UTF-8-safe Python transforms (`~/.claude/bin/uvw run python` in the Claude Code sandbox) or **Bash** `sed`. Verify output after editing Japanese files.

#### Step 0: Backup

```bash
cp claudedocs/learnings.md claudedocs/learnings.md.bak.$(date +%Y-%m-%d)
```

If inside a git repo, check `git status claudedocs/learnings.md` first. Warn if uncommitted changes.

#### Step 1: Build Compressed File

Follow a compressed v2.0 reference format (`~/projects/reference-project-a/claudedocs/learnings.md`):

```markdown
# Project Learnings vN.0 (Compressed)

[Project description]

> **vN.0 変更点**: XX,000トークン → ~YY,000トークン (ZZ%削減)
> - パターンカタログ形式に再編成
> - 空テンプレート・重複エントリ削除
> - コード例を参照形式に変換

---

# 1. パターンカタログ

## 1.1 [Category Name]

### P1: [Pattern Name] [#issue1, #issue2]

**問題**: [One-line problem description]

**解決策**:
```code
[Minimal code example or file:line reference]
```

**参照**: [file.py:line, file2.py]

---

# 2. 見積もりリファレンス

| タスクタイプ | 典型時間 | 要因 | 参照Issue |
|-------------|----------|------|-----------|
| ... | ... | ... | ... |

# 3. Issue索引

| # | 日付 | 概要 | 適用パターン |
|---|------|------|-------------|
| 42 | 2026-01-15 | Feature X | P1, P3 |
| ... | ... | ... | ... |

# 4. 再利用ファイル参照

| ファイル | 機能 | 参照Issue |
|----------|------|-----------|
| ... | ... | ... |

# 5. クイックリファレンス
```

#### Pattern Categorization Heuristics

| Content Signal | Category Name |
|---------------|---------------|
| CodeRabbit, Ruff, linter | コード品質・リンター対応 |
| IndexError, KeyError, type | 型・アクセス安全性 |
| async, Event, Queue | 非同期パターン |
| test, pytest, edge case | テスト設計 |
| config, YAML, path | 設定・パス管理 |
| performance, optimize | パフォーマンス |
| [project-specific terms] | [Project-specific category] |

#### Step 2: Write Compressed File

Use `Write` or Bash to write the new file, then verify UTF-8 output.

#### Step 3: Update Global Knowledge & Candidate Ledger

If Phase 1 Step 3 confirmed promotions or new candidates:
1. Promotions: 言語固有 → append to `~/.agents/rules/python-guidelines.md` / 言語非依存 → append to `~/.agents/rules/learnings.md`. Check the destination for an existing equivalent first; append as concise checklist item (not verbose entry), then run `~/.agents/bin/sync-shared-rules.sh`
2. Ledger maintenance: remove promoted patterns' lines from `promotion-candidates.md`, append new first-sighting candidates

#### Step 4: Insert Compression Note

Append to end of compressed learnings.md:

```markdown
<!-- COMPRESSION NOTE: knowledge-audit で圧縮済み。
新規エントリはパターンカタログ形式で追記:
### PN: [パターン名] [#issue]
**問題**: ...
**解決策**: ...
**参照**: ...
-->
```

#### Step 5: Completion Report

```markdown
## 棚卸し完了 (YYYY-MM-DD)

| 指標 | Before | After | 削減率 |
|------|--------|-------|--------|
| 行数 | N | M | X% |

### 変更内容
- パターンカタログ: N → M (+Δ 新規抽出)
- 空エントリ削除: N件
- 重複統合: N件
- Issue索引: N件を1テーブルに集約

### バックアップ
- claudedocs/learnings.md.bak.YYYY-MM-DD
```

---

## Mode B: technical_debt.md Audit

**方針**: 各項目を「実装すべきか」判断してから削減。ステータス更新だけでなくアクション判断を含む。

### Phase 1: Item Evaluation

#### Step 1: Parse Current Entries

Read `claudedocs/technical_debt.md` and identify:
- 未解決スキップ項目 (open skip items)
- 却下アーカイブ (rejected archive)
- 解決済みアーカイブ (resolved archive)

#### Step 2: Evaluate Each Unresolved Item

For each unresolved item:

1. **Check Issue/PR status**:
```bash
gh issue view <number> --json state,closedAt
gh pr view <number> --json state,mergedAt
```

2. **Check if code pattern still exists**:
```bash
grep -n "pattern" path/to/file.py
```

3. **Classify with action judgment**:

| Result | Classification | Action |
|--------|---------------|--------|
| Issue closed, code fixed | 解決済み | Move to archive |
| Code deleted entirely | 解決済み (該当なし) | Move to archive |
| Still valid, should implement | 対応すべき | Propose Issue creation |
| Valid but YAGNI | 方針判断 | Move to project policy section |
| Stale / cannot reproduce | 削除 | Remove with note |

#### Step 3: Present Results to User

Show classification results and ask user to confirm each action judgment.

### Phase 2: Update

1. Execute user-confirmed actions (move items, update statuses)
2. For items classified as "対応すべき", propose `gh issue create` commands
3. Add audit entry following the mature audit format:

```markdown
### 第N回棚卸し（YYYY-MM-DD）

PR #AAA〜#BBB の追跡項目を精査:

| 分類 | 件数 | 対応 |
|------|------|------|
| 新規追記 → 解決済み | N件 | [details] |
| 新規追記 → 却下アーカイブ | N件 | [details] |
| 未解決 → 対応すべき (Issue提案) | N件 | [details] |
| 未解決 → YAGNI (方針記録) | N件 | [details] |
| 未解決 → 現状維持 | N件 | [details] |
```

4. Update summary table and `最終更新` date

**Reference model**: `~/projects/reference-project-b/claudedocs/technical_debt.md` (multiple audit rounds documented)

---

## Safety

- **Backup**: Always `cp` before modification
- **User confirmation**: Show audit report before any writes
- **UTF-8 safety**: Use UTF-8-safe transforms or Bash sed for Japanese files and verify output
- **Git check**: `git status` before modification if in a repo
- **No data loss**: Issue index preserves all issue references; patterns are compressed, not deleted

---

## Reference Models

| Purpose | File | Lines |
|---------|------|-------|
| Compressed learnings | `~/projects/reference-project-a/claudedocs/learnings.md` | 635 |
| Mature technical debt audit | `~/projects/reference-project-b/claudedocs/technical_debt.md` | 254 |
| Global learnings checklist | `~/.agents/rules/learnings.md` | - |

## 共有 learnings の現在値（棚卸し対象スナップショット）

<!-- 正本: ~/.agents/rules/learnings.md（編集は正本側で行い、~/.agents/bin/sync-shared-rules.sh --write で同期する） -->
<!-- BEGIN shared:learnings -->
## 汎用学習事項（Learnings）

言語非依存・プロジェクト非依存の教訓。言語固有の品質ゲートは共有正本 `python-guidelines.md` 等に定義する。

### CLI操作の注意点

- **jqスライス括弧順序**: `(.body[:400])` の閉じ括弧は内側から `]` → `)` → `}` → `]`。誤: `(.body[:400)}]`、正: `(.body[:400])}]`

### 実行環境の注意点

- **systemd user service の PATH は最小構成**: 外部 CLI（claude/codex 等）は絶対パスを設定で明示し、検証は `systemctl --user show-environment` の PATH を再現して行う (理由: シェルでの成功は偽陰性になる。複数プロジェクトで独立に再発)
- **プロセス並列 × ライブラリ内スレッドの積で CPU 飽和**: 並列 chunk/ワーカー実行時は `OMP_NUM_THREADS=1 MKL_NUM_THREADS=1` や n_jobs 制限でスレッドを明示制限する (理由: torch/BLAS は既定で全コア分のスレッドを作る。複数プロジェクトで独立に再発)
<!-- END shared:learnings -->
