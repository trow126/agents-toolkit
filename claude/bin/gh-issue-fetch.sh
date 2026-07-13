#!/bin/bash
# gh-issue-fetch.sh - GitHub Issue取得・構造化
# Usage: gh-issue-fetch.sh <issue-number>
#        gh-issue-fetch.sh --active
#
# Issue内容を取得し、parse_issue.pyで構造化JSONを出力
# 出力: { issue_number, title, url, phases, tasks, statistics }

set -e

PARSER_SCRIPT="$HOME/.claude/skills/issue-parser/scripts/parse_issue.py"

show_help() {
    echo "gh-issue-fetch.sh - GitHub Issue取得・構造化"
    echo ""
    echo "Usage:"
    echo "  gh-issue-fetch.sh <issue-number>  # 指定Issueを取得"
    echo "  gh-issue-fetch.sh --active        # アクティブIssueを自動検出"
    echo ""
    echo "Output: 構造化JSON (stdout)"
    echo ""
    echo "Examples:"
    echo "  gh-issue-fetch.sh 42"
    echo "  gh-issue-fetch.sh --active | jq '.tasks'"
}

# ヘルプオプション
case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
esac

ISSUE_NUMBER="${1:-}"

# --active オプション: アサインされたオープンIssueを検出
if [[ "$ISSUE_NUMBER" == "--active" ]]; then
    ISSUE_NUMBER=$(gh issue list --assignee "@me" --state open --json number -q '.[0].number' 2>/dev/null || echo "")
    if [[ -z "$ISSUE_NUMBER" ]]; then
        echo '{"error": "No active issue found", "hint": "Check with: gh issue list --assignee @me --state open"}' >&2
        exit 1
    fi
    echo "Detected active issue: #${ISSUE_NUMBER}" >&2
fi

# 引数バリデーション
if [[ -z "$ISSUE_NUMBER" ]]; then
    show_help >&2
    exit 1
fi

if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo '{"error": "Invalid issue number", "received": "'"$ISSUE_NUMBER"'"}' >&2
    exit 1
fi

# パーサースクリプト存在確認
if [[ ! -f "$PARSER_SCRIPT" ]]; then
    echo '{"error": "Parser script not found", "path": "'"$PARSER_SCRIPT"'"}' >&2
    exit 1
fi

# Issue取得 + パース
# gh issue view は number,title,body,url,state を取得
ISSUE_DATA=$(gh issue view "$ISSUE_NUMBER" --json number,title,body,url,state 2>/dev/null)

if [[ -z "$ISSUE_DATA" ]]; then
    echo '{"error": "Issue not found", "issue_number": '"$ISSUE_NUMBER"'}' >&2
    exit 1
fi

# Issue状態チェック
ISSUE_STATE=$(echo "$ISSUE_DATA" | jq -r '.state')
if [[ "$ISSUE_STATE" == "CLOSED" ]]; then
    echo '{"error": "Issue is closed", "issue_number": '"$ISSUE_NUMBER"', "state": "CLOSED"}' >&2
    exit 1
fi

# パーサーで構造化
echo "$ISSUE_DATA" | python3 "$PARSER_SCRIPT"
