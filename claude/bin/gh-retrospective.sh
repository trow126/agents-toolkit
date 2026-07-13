#!/bin/bash
# gh-retrospective.sh - Issue振り返りとCodeRabbitレビュー分析
# Usage: gh-retrospective.sh <issue-number> [--output <file>] [--quiet]
#
# PRマージ後のIssue振り返りを実行:
# 1. Issue詳細取得
# 2. 関連PR検索
# 3. CodeRabbitレビューコメント取得・分析
# 4. learnings.mdに記録

set -e

show_help() {
    echo "gh-retrospective.sh - Issue振り返りとCodeRabbitレビュー分析"
    echo ""
    echo "Usage: gh-retrospective.sh <issue-number> [options]"
    echo ""
    echo "Options:"
    echo "  -o, --output <file>  出力先ファイル（デフォルト: claudedocs/learnings.md）"
    echo "  -q, --quiet          サマリー表示を抑制"
    echo "  --json               JSON形式で出力"
    echo "  -h, --help           このヘルプを表示"
    echo ""
    echo "Examples:"
    echo "  gh-retrospective.sh 42"
    echo "  gh-retrospective.sh 42 --output /tmp/retro.md"
}

# デフォルト値
ISSUE_NUMBER=""
OUTPUT_FILE=""
QUIET=false
JSON_OUTPUT=false

# 引数解析
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            if [[ -z "$ISSUE_NUMBER" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                ISSUE_NUMBER="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$ISSUE_NUMBER" ]; then
    echo "Error: Issue number required"
    show_help
    exit 1
fi

# リポジトリ情報取得
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    echo "Error: Not in a git repository"
    exit 1
fi

REPO_INFO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
if [ -z "$REPO_INFO" ]; then
    echo "Error: Could not get repository info"
    exit 1
fi

# デフォルト出力先
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="${REPO_ROOT}/claudedocs/learnings.md"
fi

# 出力ディレクトリ作成
mkdir -p "$(dirname "$OUTPUT_FILE")"

[ "$QUIET" != true ] && echo "📝 Retrospective for Issue #${ISSUE_NUMBER}"
[ "$QUIET" != true ] && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Issue詳細取得
[ "$QUIET" != true ] && echo "📋 Fetching Issue #${ISSUE_NUMBER}..."
ISSUE_DATA=$(gh issue view "$ISSUE_NUMBER" --json title,state,closedAt,body,labels 2>/dev/null)
if [ -z "$ISSUE_DATA" ]; then
    echo "Error: Issue #${ISSUE_NUMBER} not found"
    exit 1
fi

ISSUE_TITLE=$(echo "$ISSUE_DATA" | jq -r '.title')
ISSUE_STATE=$(echo "$ISSUE_DATA" | jq -r '.state')
ISSUE_CLOSED_AT=$(echo "$ISSUE_DATA" | jq -r '.closedAt // "N/A"')
ISSUE_LABELS=$(echo "$ISSUE_DATA" | jq -r '.labels[].name' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')

[ "$QUIET" != true ] && echo "   Title: $ISSUE_TITLE"
[ "$QUIET" != true ] && echo "   State: $ISSUE_STATE"

# 2. 関連PR検索（このIssueをクローズしたPR）
[ "$QUIET" != true ] && echo "🔍 Searching for related PR..."

# GitHub APIでIssueをクローズしたPRを直接取得
PR_DATA=$(gh api "repos/${REPO_INFO}/issues/${ISSUE_NUMBER}/timeline" --jq '[.[] | select(.event == "cross-referenced" and .source.issue.pull_request != null) | .source.issue | {number: .number, title: .title, url: .html_url}] | .[0:1]' 2>/dev/null || echo "[]")

# フォールバック: ブランチ名で検索（issue-N パターン）
if [ -z "$PR_DATA" ] || [ "$PR_DATA" = "[]" ] || [ "$PR_DATA" = "null" ]; then
    PR_DATA=$(gh pr list --repo "${REPO_INFO}" --state merged --head "issue-${ISSUE_NUMBER}" --json number,title,url --limit 1 2>/dev/null || echo "[]")
fi

# フォールバック2: PR本文に "Closes #N" を含むもの
if [ -z "$PR_DATA" ] || [ "$PR_DATA" = "[]" ] || [ "$PR_DATA" = "null" ]; then
    PR_DATA=$(gh pr list --repo "${REPO_INFO}" --state merged --json number,title,url,body --limit 20 2>/dev/null | jq "[.[] | select(.body | test(\"[Cc]loses #${ISSUE_NUMBER}|[Ff]ixes #${ISSUE_NUMBER}|[Rr]esolves #${ISSUE_NUMBER}\"))] | .[0:1]" 2>/dev/null || echo "[]")
fi

PR_NUMBER=""
PR_TITLE=""
PR_URL=""
if [ -n "$PR_DATA" ] && [ "$PR_DATA" != "[]" ] && [ "$PR_DATA" != "null" ]; then
    PR_NUMBER=$(echo "$PR_DATA" | jq -r '.[0].number // empty' | tr -d '[:space:]')
    PR_TITLE=$(echo "$PR_DATA" | jq -r '.[0].title // empty')
    PR_URL=$(echo "$PR_DATA" | jq -r '.[0].url // empty')
    # URLが現在のリポジトリのものか確認
    if [ -n "$PR_URL" ] && echo "$PR_URL" | grep -q "${REPO_INFO}"; then
        [ "$QUIET" != true ] && echo "   Found PR #${PR_NUMBER}: ${PR_TITLE}"
    else
        [ "$QUIET" != true ] && echo "   No related PR found in this repo"
        PR_NUMBER=""
        PR_TITLE=""
        PR_URL=""
    fi
else
    [ "$QUIET" != true ] && echo "   No related PR found"
fi

# 3. CodeRabbitレビューコメント取得
CODERABBIT_COMMENTS=""
CODERABBIT_COUNT=0
CODERABBIT_SUMMARY=""

if [ -n "$PR_NUMBER" ]; then
    [ "$QUIET" != true ] && echo "🐰 Fetching CodeRabbit review comments..."

    # PRコメント取得（CodeRabbitのもの）
    REVIEW_COMMENTS=$(gh api "repos/${REPO_INFO}/pulls/${PR_NUMBER}/comments" --jq '[.[] | select(.user.login == "coderabbitai[bot]" or .user.login == "coderabbitai") | {path: .path, line: .line, body: .body}]' 2>/dev/null || echo "[]")

    CODERABBIT_COUNT=$(echo "$REVIEW_COMMENTS" | jq 'length')

    if [ "$CODERABBIT_COUNT" -gt 0 ]; then
        [ "$QUIET" != true ] && echo "   Found ${CODERABBIT_COUNT} CodeRabbit comments"

        # コメントを分類（Severity別）
        CRITICAL_COUNT=$(echo "$REVIEW_COMMENTS" | jq '[.[] | select(.body | test("Potential issue|⚠️"; "i"))] | length')
        NITPICK_COUNT=$(echo "$REVIEW_COMMENTS" | jq '[.[] | select(.body | test("Nitpick|🔵"; "i"))] | length')

        # 主要な指摘を抽出（最初の500文字）
        CODERABBIT_COMMENTS=$(echo "$REVIEW_COMMENTS" | jq -r '.[0:5] | .[] | "- **\(.path):\(.line // "N/A")**: \(.body[0:200] | gsub("\n"; " "))..."')

        CODERABBIT_SUMMARY="CodeRabbit指摘: ${CODERABBIT_COUNT}件 (Critical: ${CRITICAL_COUNT}, Nitpick: ${NITPICK_COUNT})"
    else
        [ "$QUIET" != true ] && echo "   No CodeRabbit comments found"
        CODERABBIT_SUMMARY="CodeRabbit指摘: なし"
    fi
fi

# 4. 振り返りレポート生成
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
REPORT=""

if [ "$JSON_OUTPUT" = true ]; then
    # JSON出力
    REPORT=$(cat <<EOF
{
  "issue_number": ${ISSUE_NUMBER},
  "issue_title": "${ISSUE_TITLE}",
  "issue_state": "${ISSUE_STATE}",
  "pr_number": ${PR_NUMBER:-null},
  "pr_title": "${PR_TITLE}",
  "pr_url": "${PR_URL}",
  "coderabbit_count": ${CODERABBIT_COUNT},
  "timestamp": "${TIMESTAMP}"
}
EOF
)
    echo "$REPORT"
else
    # Markdown出力
    REPORT=$(cat <<EOF

---

## Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

**日時**: ${TIMESTAMP}
**状態**: ${ISSUE_STATE}
**ラベル**: ${ISSUE_LABELS:-なし}

### 関連PR

EOF
)

    if [ -n "$PR_NUMBER" ]; then
        REPORT+="- PR #${PR_NUMBER}: ${PR_TITLE}
- URL: ${PR_URL}
"
    else
        REPORT+="- 関連PRなし
"
    fi

    REPORT+="
### CodeRabbitレビュー分析

${CODERABBIT_SUMMARY}
"

    if [ "$CODERABBIT_COUNT" -gt 0 ]; then
        REPORT+="
#### 主な指摘事項

${CODERABBIT_COMMENTS}

#### 学んだこと

- [ ] 上記の指摘を今後のコードに反映する
- [ ] 同様のパターンがないか確認する
"
    fi

    REPORT+="
### 振り返り

- **うまくいったこと**:
- **改善点**:
- **次回への教訓**:

"

    # ファイルに追記
    if [ ! -f "$OUTPUT_FILE" ]; then
        echo "# 開発振り返りログ" > "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "Issue完了時の振り返りと学習記録。" >> "$OUTPUT_FILE"
    fi

    echo "$REPORT" >> "$OUTPUT_FILE"

    [ "$QUIET" != true ] && echo ""
    [ "$QUIET" != true ] && echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    [ "$QUIET" != true ] && echo "✅ Retrospective saved to: ${OUTPUT_FILE}"
    [ "$QUIET" != true ] && echo ""
    [ "$QUIET" != true ] && echo "Summary:"
    [ "$QUIET" != true ] && echo "  Issue: #${ISSUE_NUMBER} - ${ISSUE_TITLE}"
    [ "$QUIET" != true ] && [ -n "$PR_NUMBER" ] && echo "  PR: #${PR_NUMBER}"
    [ "$QUIET" != true ] && echo "  ${CODERABBIT_SUMMARY}"
fi
