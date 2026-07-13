#!/usr/bin/env python3
"""
GitHub Issue Parser
Extracts structured task data from GitHub Issue markdown.
Includes automatic label inference from title and body.
"""

import json
import re
import sys

# ========================================
# Label Inference Rules
# ========================================

LABEL_RULES = {
    # Type Labels (Priority: highest match wins)
    "type_labels": {
        "bug": {
            "keywords": ["bug", "バグ", "不一致", "問題", "エラー", "error", "fix", "修正", "解決", "調査"],
            "title_patterns": ["bug:", "fix:"],
            "priority": 1
        },
        "refactoring": {
            "keywords": ["refactor", "リファクタ", "統一", "整理", "クリーンアップ", "cleanup"],
            "title_patterns": ["refactor:"],
            "priority": 2
        },
        "enhancement": {
            "keywords": ["feature", "実装", "追加", "改善", "最適化", "向上", "新規", "enhancement"],
            "title_patterns": ["feature:", "enhancement:"],
            "priority": 3
        },
        "documentation": {
            "keywords": ["ドキュメント", "文書化", "documentation", "doc", "readme"],
            "title_patterns": ["docs:", "doc:"],
            "priority": 4
        },
        "question": {
            "keywords": ["調査", "検証", "質問", "question", "verify", "investigate"],
            "title_patterns": ["question:"],
            "priority": 5
        }
    },

    # Domain Labels (Multiple allowed)
    "domain_labels": {
        "ml-model": {
            "keywords": ["モデル", "model", "tabpfn", "catboost", "lstm", "transformer",
                        "gbdt", "ranker", "アンサンブル", "ensemble", "予測", "prediction",
                        "学習", "training", "nn", "neural", "realmLP"]
        },
        "data-pipeline": {
            "keywords": ["データ", "data", "特徴量", "feature", "パイプライン", "pipeline",
                        "処理", "processing", "取得", "fetch", "csv", "スクレイピング", "scraping"]
        },
        "performance": {
            "keywords": ["最適化", "optimization", "高速化", "速度", "speed", "メモリ", "memory",
                        "並列", "parallel", "gpu", "削減", "reduce", "oom", "batch", "高速", "fast"]
        },
        "analytics": {
            "keywords": ["評価", "evaluation", "分析", "analysis", "指標", "metric",
                        "統計", "statistics", "月別", "monthly", "検証", "verification"]
        },
        "infrastructure": {
            "keywords": ["環境", "environment", "cuda", "依存", "dependency", "インフラ",
                        "infrastructure", "setup", "config", "設定"]
        }
    },

    # Default label if no type label matches
    "default_type_label": "enhancement"
}


def infer_labels(title, body=""):
    """
    Infer GitHub labels from Issue title and body using rule-based pattern matching.

    Args:
        title: Issue title text
        body: Issue body text (optional)

    Returns:
        list: Inferred label names (1 type label + 0-3 domain labels)

    Algorithm:
        1. Tokenize title and body (lowercase, split)
        2. Check title prefixes first (highest priority)
        3. Keyword matching (title weight: 2x, body weight: 1x)
        4. Select type label by highest priority match
        5. Select domain labels by keyword threshold (≥2 matches)
    """
    labels = []

    # Normalize text
    title_lower = title.lower()
    body_lower = body.lower() if body else ""

    # Tokenize (split by whitespace and common punctuation)
    title_tokens = set(re.findall(r'\w+', title_lower))
    body_tokens = set(re.findall(r'\w+', body_lower)) if body else set()

    # ---- Type Label Selection ----
    type_label_matches = []

    for label, rules in LABEL_RULES["type_labels"].items():
        score = 0

        # Check title patterns first (strongest signal)
        for pattern in rules["title_patterns"]:
            if title_lower.startswith(pattern):
                score += 100  # Very high weight for explicit prefix
                break

        # Check keyword matches
        for keyword in rules["keywords"]:
            # Title match (weight: 2x)
            if keyword in title_tokens:
                score += 2
            # Body match (weight: 1x)
            if keyword in body_tokens:
                score += 1

        if score > 0:
            type_label_matches.append((label, rules["priority"], score))

    # Select type label: highest score, then lowest priority number (higher priority)
    if type_label_matches:
        # Sort by score (desc), then priority (asc)
        type_label_matches.sort(key=lambda x: (-x[2], x[1]))
        labels.append(type_label_matches[0][0])
    else:
        # Default label
        labels.append(LABEL_RULES["default_type_label"])

    # ---- Domain Label Selection ----
    domain_label_matches = []

    for label, rules in LABEL_RULES["domain_labels"].items():
        match_count = 0

        for keyword in rules["keywords"]:
            # Title match (weight: 2)
            if keyword in title_tokens:
                match_count += 2
            # Body match (weight: 1)
            elif keyword in body_tokens:
                match_count += 1

        # Threshold: at least 2 matches (could be 1 title match or 2 body matches)
        if match_count >= 2:
            domain_label_matches.append((label, match_count))

    # Sort by match count (desc) and take top 3
    domain_label_matches.sort(key=lambda x: -x[1])
    labels.extend([label for label, _ in domain_label_matches[:3]])

    return labels


def parse_issue(body, title, number, url=""):
    """
    Parse GitHub Issue markdown to extract tasks and phases.

    Args:
        body: Issue markdown body
        title: Issue title
        number: Issue number
        url: Issue URL

    Returns:
        dict: Structured issue data with phases and tasks
    """
    phases = []
    tasks = []
    current_phase = None
    task_id = 1

    lines = body.split('\n') if body else []

    for line in lines:
        # Phase detection (## headings)
        if line.startswith('## '):
            current_phase = line[3:].strip()
            if current_phase and current_phase not in phases:
                phases.append(current_phase)

        # Task detection (- [ ] or - [x] checkboxes)
        match = re.match(r'- \[([ xX])\] (.+)', line.strip())
        if match:
            completed = match.group(1).lower() == 'x'
            task_text = match.group(2).strip()

            tasks.append({
                'id': task_id,
                'phase': current_phase if current_phase else 'General',
                'text': task_text,
                'completed': completed,
                'status': 'completed' if completed else 'pending'
            })
            task_id += 1

    # Calculate statistics
    total_tasks = len(tasks)
    completed_tasks = sum(1 for t in tasks if t['completed'])
    pending_tasks = total_tasks - completed_tasks
    completion_percentage = (completed_tasks / total_tasks * 100) if total_tasks > 0 else 0

    # Task count analysis for Issue splitting recommendations
    split_urgency = None
    split_recommended = False
    recommended_issue_count = 1

    if pending_tasks >= 15:
        split_urgency = "high"
        split_recommended = True
        # Recommend 5-8 tasks per Issue
        recommended_issue_count = (pending_tasks + 7) // 8
    elif pending_tasks >= 12:
        split_urgency = "medium"
        split_recommended = True
        recommended_issue_count = (pending_tasks + 7) // 8
    elif pending_tasks >= 8:
        split_urgency = "low"
        # Not strictly recommended, but flag for user awareness

    # Infer labels from title and body
    inferred_labels = infer_labels(title, body)

    return {
        'issue_number': number,
        'title': title,
        'url': url,
        'phases': phases,
        'tasks': tasks,
        'inferred_labels': inferred_labels,
        'statistics': {
            'total_tasks': total_tasks,
            'completed_tasks': completed_tasks,
            'pending_tasks': pending_tasks,
            'completion_percentage': round(completion_percentage, 1),
            'split_recommended': split_recommended,
            'split_urgency': split_urgency,
            'recommended_issue_count': recommended_issue_count
        }
    }


def main():
    """
    Main entry point.
    Expects JSON input from stdin with: body, title, number, url
    """
    try:
        # Read JSON from stdin
        data = json.load(sys.stdin)

        body = data.get('body', '')
        title = data.get('title', '')
        number = data.get('number', 0)
        url = data.get('url', '')

        # Parse issue
        result = parse_issue(body, title, number, url)

        # Output JSON
        print(json.dumps(result, indent=2, ensure_ascii=False))

        return 0

    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input - {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
