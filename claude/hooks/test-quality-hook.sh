#!/bin/bash
# PostToolUse hook: テスト品質の自動検証
#
# Edit/Write で Python ファイルが変更された際に動作:
#   1. プロジェクトにテスト品質ツーリングがなければ通知
#   2. テストファイル変更時は品質チェック実行を通知
#
# 全プロジェクト共通。ターミナル表示で人間にも見える。
# Data is passed via stdin as JSON, not environment variables.

INPUT=$(cat)

# Python ファイルか判定
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

if [[ "$FILE_PATH" != *.py ]]; then
    exit 0
fi

# プロジェクトルートを推定（pyproject.toml の位置）
PROJECT_DIR=$(dirname "$FILE_PATH")
while [ "$PROJECT_DIR" != "/" ] && [ ! -f "$PROJECT_DIR/pyproject.toml" ]; do
    PROJECT_DIR=$(dirname "$PROJECT_DIR")
done

if [ ! -f "$PROJECT_DIR/pyproject.toml" ]; then
    exit 0
fi

# ── 1. テスト品質ツーリングの有無を判定 ──
if ! grep -q "hypothesis" "$PROJECT_DIR/pyproject.toml" 2>/dev/null; then
    echo "[test-quality] テスト品質ツーリング未検出。必要なら ~/bin/setup-test-quality.sh を手動実行してください"
    exit 0
fi

# ── 2. セットアップ済みプロジェクトでの通知 ──
BASENAME=$(basename "$FILE_PATH")
if echo "$BASENAME" | grep -qE '^test_'; then
    # テストファイル変更 → 品質チェック実行を通知
    MSGS=()

    if [ -f "$PROJECT_DIR/tests/test_cross_boundary_invariants.py" ]; then
        MSGS+=("  uv run pytest -m cross_boundary -v")
    fi

    if [ -f "$PROJECT_DIR/Makefile" ] && grep -q "mutation-test" "$PROJECT_DIR/Makefile" 2>/dev/null; then
        MSGS+=("  make mutation-test-critical")
    fi

    if [ ${#MSGS[@]} -gt 0 ]; then
        echo "[test-quality] テストファイル変更検出。品質チェック推奨:"
        for msg in "${MSGS[@]}"; do
            echo "$msg"
        done
    fi
else
    # 実装ファイル変更 → 不変条件テストの存在を確認
    # tests/ 配下に対応するテストファイルがあるか
    IMPL_NAME="${BASENAME%.py}"
    TEST_FILE="$PROJECT_DIR/tests/test_${IMPL_NAME}.py"

    if [ -f "$TEST_FILE" ]; then
        # 対応テストあり → cross_boundary marker が含まれているか確認
        if ! grep -q "cross_boundary" "$TEST_FILE" 2>/dev/null; then
            echo "[test-quality] 実装変更: $BASENAME → テスト $TEST_FILE に cross_boundary 不変条件テストがありません"
        fi
    fi
fi
