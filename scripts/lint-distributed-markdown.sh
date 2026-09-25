#!/usr/bin/env bash
# lint-distributed-markdown.sh — install/manifest.tsv で配布される tracked Markdown に
# claude/hooks/lib/post_edit_lint.py（PostToolUse lint hook と同じ判定）をかける。
# 違反を全件列挙してから非ゼロ終了する。
#
# 使い方: scripts/lint-distributed-markdown.sh [--repo PATH]
#   --repo PATH  検査対象の repo（既定: 本 script の repo）。lint 本体は常に本 script の repo のものを使う
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT="$TOOLKIT_ROOT/claude/hooks/lib/post_edit_lint.py"
TARGET_ROOT="$TOOLKIT_ROOT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "ERROR: --repo requires a path" >&2; exit 1; }
      TARGET_ROOT="$(cd "$2" && pwd)"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

MANIFEST="$TARGET_ROOT/install/manifest.tsv"
[[ -f "$MANIFEST" ]] || { echo "ERROR: manifest not found: $MANIFEST" >&2; exit 1; }
[[ -f "$LINT" ]] || { echo "ERROR: lint not found: $LINT" >&2; exit 1; }

mapfile -t FILES < <(
  while IFS=$'\t' read -r mode source _target; do
    [[ -z "$mode" || "$mode" == \#* ]] && continue
    case "$mode" in
      link-file) git -C "$TARGET_ROOT" ls-files -- "$source" ;;
      link-dir) git -C "$TARGET_ROOT" ls-files -- "$source/" ;;
    esac
  done < "$MANIFEST" | grep -E '\.md$' | sort -u
)

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "ERROR: no distributed Markdown found under $TARGET_ROOT" >&2
  exit 1
fi

violations=0
for rel in "${FILES[@]}"; do
  if ! python3 "$LINT" "$TARGET_ROOT/$rel"; then
    violations=$((violations + 1))
  fi
done

if [[ "$violations" -eq 0 ]]; then
  echo "PASS: ${#FILES[@]} distributed Markdown files are lint-clean"
  exit 0
fi
echo "FAIL: $violations of ${#FILES[@]} distributed Markdown files have lint violations" >&2
exit 1
