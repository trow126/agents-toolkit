---
name: issue-retrospective
description: Use when a GitHub Issue was just closed or the user asks for a retrospective（「振り返りして」「retrospective」「学習事項を抽出して」）. Extract learnings from completed Issues and record them as Issue comments and claudedocs/learnings.md (project, gitignored).
allowed-tools: Bash, Read, Write, Edit
---

# Issue Retrospective Skill

Extracts learnings and patterns from completed GitHub Issues to improve future development workflows.

## What This Skill Does

Analyzes completed Issues to extract:
- **Timeline Insights**: Actual duration vs estimated complexity
- **Task Patterns**: Which tasks took longer than expected
- **Blockers Identified**: Technical challenges encountered
- **Success Patterns**: Effective approaches and solutions
- **Process Improvements**: Recommendations for future work

Automatically records learnings in:
1. **GitHub Issue comment**: Structured retrospective visible in the Issue itself
2. **claudedocs/learnings.md**: Project-wide patterns for future reference

## When to Use

This skill automatically activates when you:
- Execute `/gh:issue close <number>`
- Say "extract learnings from Issue #42"
- Request "retrospective on completed Issue"
- Mention "analyze what we learned from Issue"

You can also explicitly invoke with: **"use issue-retrospective skill for Issue #42"**

## How It Works

### Input

Requires Issue number to analyze:
```
Issue #42: Feature: User Authentication
```

### Process

#### 1. **Fetch Issue History**
```bash
# Get Issue metadata
gh issue view <number> --json number,title,createdAt,closedAt,body,comments

# Get associated commits (if PR was created)
gh pr list --search "Closes #<number>" --json number,commits
```

#### 2. **Analyze Timeline**
- Calculate actual duration: `closedAt - createdAt`
- Extract task count from Issue body
- Identify completion pace from comment timestamps
- Detect blockers from comment keywords ("blocked", "stuck", "issue", "problem")

#### 3. **Extract Learnings**

**Task Analysis**:
```yaml
completed_tasks:
  - "API implementation"
  - "Frontend components"
  - "Database schema"

task_insights:
  faster_than_expected: []
  slower_than_expected: ["API implementation (auth complexity)"]
  blocked: []
```

**Success Patterns**:
- Approaches that worked well
- Tools/techniques that accelerated work
- Code patterns that were reusable

**Blockers & Challenges**:
- Technical difficulties encountered
- Missing dependencies discovered
- Scope changes needed

**Process Improvements**:
- Better estimation needed for X
- Consider Y approach next time
- Document Z pattern for reuse

#### 4. **Generate Structured Retrospective**

Create structured markdown retrospective:

```markdown
## 📊 振り返り (Issue #42)

**期間**: 3日間 (2025-11-01 → 2025-11-04)
**完了タスク**: 3/3 (100%)

### ✅ うまくいったこと
- JWT実装はAuth0パターンに従ってスムーズに進んだ
- コンポーネントファーストアプローチ（UI先行）により並行作業が可能
- TDD（テスト駆動開発）でエッジケースを早期に発見

### 🚧 課題・ブロッカー
- **トークンリフレッシュ機構**が予想より複雑（+1日）
- CORS設定にインフラ知識が必要だった
- API仕様書不足で統合が遅延（→ドキュメント作成で解決）

### 💡 次回への改善提案
- 見積もりにインフラセットアップ時間を+20%計上
- 再利用可能なトークンリフレッシュミドルウェアパターンを作成
- CORS設定をドキュメント化して参照可能に

### 📦 再利用可能なパターン
- `src/middleware/auth.js`: JWT検証ミドルウェア
- `src/utils/tokenRefresh.js`: トークンリフレッシュフロー
```

#### 5. **Post Retrospective Comment to GitHub Issue**

```bash
# Post structured retrospective as Issue comment
gh issue comment <number> --body "$(cat <<'EOF'
[Generated retrospective markdown]
EOF
)"
```

#### 6. **Update claudedocs/learnings.md**

Check if file exists, create if needed, then append learnings:

```bash
# Create claudedocs directory if needed
mkdir -p claudedocs

# Check if learnings.md exists
if [ ! -f claudedocs/learnings.md ]; then
  # Create initial structure
  cat > claudedocs/learnings.md <<'EOF'
# Project Learnings

Project-wide patterns and insights extracted from completed Issues.

---

EOF
fi

# Append new learnings
cat >> claudedocs/learnings.md <<'EOF'
## Issue #42: Feature: User Authentication (2025-11-04)

**Duration**: 3 days

### Authentication Patterns
- JWT with refresh tokens is our standard approach
- Auth0 patterns work well for our stack
- Token refresh adds ~1 day complexity

### Estimation Insights
- Infrastructure setup: +20% to estimates
- Auth features: typically 2-4 days

### Reusable Code
- `src/middleware/auth.js`: JWT validation middleware
- `src/utils/tokenRefresh.js`: Token refresh logic

---

EOF
```

### Output Format

```markdown
## 📊 Issue #42 Retrospective Complete

**Duration**: 3 days (2025-11-01 → 2025-11-04)
**Tasks Completed**: 3/3 (100%)

### ✅ Success Patterns
- JWT implementation following Auth0 patterns worked smoothly
- Component-first approach enabled parallel work
- Test-driven development caught edge cases early

### 🚧 Challenges
- Token refresh mechanism more complex than estimated (+1 day)
- CORS configuration required infrastructure knowledge

### 💡 Improvements
- Allocate more time for infrastructure setup in estimates
- Create reusable token refresh middleware pattern
- Document CORS setup for future reference

### 📦 Reusable Patterns
- `src/middleware/auth.js`: JWT validation middleware
- `src/utils/tokenRefresh.js`: Token refresh logic

**Retrospective recorded**: ✅
- GitHub Issue #42 comment posted
- `claudedocs/learnings.md` updated
```

## Usage Examples

### Example 1: Automatic Invocation via /gh:issue close
```
User: "/gh:issue close 42"
Claude:
  1. Uses issue-retrospective skill automatically
  2. Analyzes Issue #42 history
  3. Extracts learnings
  4. Stores learnings in local project docs
  5. Displays retrospective summary
  6. Proceeds to close Issue
```

### Example 2: Explicit Retrospective Without Closing
```
User: "Use issue-retrospective skill for Issue #123 but don't close it yet"
Claude:
  1. Analyzes Issue #123
  2. Extracts learnings
  3. Stores learnings in local project docs
  4. Displays retrospective
  5. Issue remains open
```

### Example 3: Pattern Recognition Across Issues
```
User: "What have we learned about authentication implementations?"
Claude:
  1. Reads claudedocs/learnings.md
  2. Filters authentication-related learnings
  3. Synthesizes patterns from multiple retrospectives
  4. Provides consolidated insights
```

## Error Handling

- **Issue Not Found**: Returns error if Issue doesn't exist or is inaccessible
- **No Comments**: Still analyzes task completion, notes lack of communication
- **Open Issue**: Can analyze open Issues but notes learnings are incomplete
- **No Tasks**: Extracts learnings from description and comments only
- **GitHub Comment Failure**: Reports error but continues with Issue close workflow
- **File Write Failure**: Reports error but continues with Issue close workflow

## Files

- `SKILL.md`: This documentation

## Dependencies

- `gh` CLI (GitHub CLI) - Required for Issue comment posting
- `mkdir`, `cat` - Standard Unix tools for file operations
- Python/scripts: **None** (Pure Claude analysis)

## Integration Points

This skill is designed to work with:
- **/gh:issue close**: Primary integration point (auto-invokes before close)
- **claudedocs/learnings.md**: Project-wide learning accumulation
- **progress-tracker**: Can analyze progress patterns from tracked data
- **issue-parser**: Uses same Issue structure understanding

## Output Destinations

### 1. GitHub Issue Comment (Per-Issue)
Posted as structured markdown comment to the Issue before closing:

```markdown
## 📊 振り返り (Issue #<number>)

**期間**: <duration> (<start_date> → <end_date>)
**完了タスク**: <completed>/<total> (<percentage>%)

### ✅ うまくいったこと
- <success_pattern_1>
- <success_pattern_2>

### 🚧 課題・ブロッカー
- <challenge_1>
- <challenge_2>

### 💡 次回への改善提案
- <improvement_1>
- <improvement_2>

### 📦 再利用可能なパターン
- `<file_path>`: <description>
```

### 2. claudedocs/learnings.md (Project-Wide)
Appended to project learnings file:

```markdown
## Issue #<number>: <title> (<completion_date>)

**Duration**: <duration_days> days

### <Domain> Patterns
- <pattern_1>
- <pattern_2>

### Estimation Insights
- <insight_1>
- <insight_2>

### Reusable Code
- `<file_path>`: <description>

---
```

## Continuous Improvement Cycle

```
Issue Complete
    ↓
issue-retrospective extracts learnings
    ↓
GitHub Issue comment + claudedocs/learnings.md
    ↓
Future Issues benefit from patterns
    ↓
Better estimates, fewer blockers
    ↓
Continuous improvement
```

## Testing

Test the skill with a completed Issue:

```bash
# Manual test
User: "Use issue-retrospective skill for Issue #1"

# Verify GitHub comment was posted
gh issue view 1 --comments

# Verify learnings were appended
cat claudedocs/learnings.md
```

Expected:
- Retrospective comment visible in Issue #1
- claudedocs/learnings.md contains new entry for Issue #1
