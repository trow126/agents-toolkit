#!/usr/bin/env bash
# package-release.sh — 配布用 archive を git archive で生成し、禁止 entry がないことを lint する
# (2026-07-23 レビュー ATK-015: 配布物へ .git/・cache・bytecode・runtime state を混入させない)
#
# 使い方:
#   package-release.sh            dist/agents-toolkit-<shortsha>.zip を生成し lint する
#   package-release.sh --check    一時ディレクトリに生成して lint だけ行い、成果物は残さない(CI 用)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

MODE="${1:---build}"
case "$MODE" in
  --build | --check) ;;
  *)
    echo "ERROR: unknown mode '$MODE' (expected --build or --check)" >&2
    exit 1
    ;;
esac

SHORTSHA="$(git rev-parse --short HEAD)"
if [[ "$MODE" == "--check" ]]; then
  OUTDIR="$(mktemp -d)"
  trap 'rm -rf "$OUTDIR"' EXIT
else
  OUTDIR="$REPO_ROOT/dist"
  mkdir -p "$OUTDIR"
fi
ARCHIVE="$OUTDIR/agents-toolkit-$SHORTSHA.zip"

# git archive は tracked ファイルのみを含む(.git/・untracked・ignored を構造的に除外)
git archive --format=zip --prefix="agents-toolkit/" -o "$ARCHIVE" HEAD

# release lint: 禁止 entry の検出(defense-in-depth。git archive 由来なら通常 0 件)
FORBIDDEN='(^|/)\.git(/|$)|(^|/)\.pytest_cache/|(^|/)__pycache__/|\.pyc$|(^|/)\.venv/|(^|/)node_modules/|(^|/)\.mypy_cache/|(^|/)\.ruff_cache/|\.credentials|history\.jsonl$|settings\.local\.json$|CLAUDE\.local\.md$'
listing="$(unzip -Z1 "$ARCHIVE")"
bad="$(echo "$listing" | grep -E "$FORBIDDEN" || true)"
if [[ -n "$bad" ]]; then
  echo "FAIL: forbidden entries in release archive:" >&2
  echo "$bad" >&2
  exit 1
fi

entries="$(echo "$listing" | wc -l)"
sha256="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
echo "PASS: release archive is clean ($entries entries)"
echo "archive: $ARCHIVE"
echo "sha256: $sha256"
