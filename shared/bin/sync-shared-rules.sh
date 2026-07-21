#!/usr/bin/env bash
# sync-shared-rules.sh — shared/rules/ の正本を各消費ファイルのマーカー区間へ同期する
# 正本を編集したら本スクリプトを実行する。マーカー: <!-- BEGIN shared:NAME --> / <!-- END shared:NAME -->
#
# 使い方:
#   sync-shared-rules.sh --check   全区間が正本と一致するか検証する（drift があれば列挙し非ゼロ終了、ファイルは変更しない）
#   sync-shared-rules.sh --write   同期を実行する
#   sync-shared-rules.sh           引数なしは後方互換のため --write と同じ
set -euo pipefail

# repo root は本スクリプト自身の位置から解決する（$HOME 依存にしない。
# ~/.agents/bin/ 経由の symlink 呼び出しでも CI checkout でも同じロジックで動く）
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RULES_DIR="$REPO_ROOT/shared/rules"

if [[ $# -gt 1 ]]; then
  echo "ERROR: too many arguments (expected: [--check|--write])" >&2
  exit 1
fi

MODE="${1:---write}"
case "$MODE" in
  --check | --write) ;;
  *)
    echo "ERROR: unknown mode '$MODE' (expected --check or --write)" >&2
    exit 1
    ;;
esac

# 同期対応表: 1行 = NAME<TAB>repo相対target
SYNC_MAP=$(cat <<'EOF'
karpathy-guidelines	codex/AGENTS.md
no-fallback	codex/AGENTS.md
git-safety	codex/AGENTS.md
decision-integrity	codex/AGENTS.md
quality-priority	codex/AGENTS.md
scope-discipline	codex/AGENTS.md
test-policy	codex/AGENTS.md
git-workflow	codex/AGENTS.md
learnings	codex/AGENTS.md
python-guidelines	codex/AGENTS.md
python-guidelines	claude/rules/python.md
failure-investigation	codex/AGENTS.md
framework-respect	codex/AGENTS.md
self-improvement	codex/AGENTS.md
workspace-hygiene	codex/AGENTS.md
markdown-rules	codex/AGENTS.md
markdown-rules	claude/rules/markdown.md
issue-completeness	codex/AGENTS.md
EOF
)

drift_found=0

# target 内の marker 整合性を検証する（BEGIN欠落・END欠落・区間重複・BEGIN/END逆転をエラーにする）
validate_markers() {
  local target="$1"
  local name="$2"
  local begin="<!-- BEGIN shared:$name -->"
  local end="<!-- END shared:$name -->"
  local begin_count end_count begin_line end_line

  begin_count=$(grep -cF "$begin" "$target" || true)
  end_count=$(grep -cF "$end" "$target" || true)

  if [[ "$begin_count" -eq 0 ]]; then
    echo "ERROR: marker '$begin' not found in $target" >&2
    exit 1
  fi
  if [[ "$end_count" -eq 0 ]]; then
    echo "ERROR: marker '$end' not found in $target" >&2
    exit 1
  fi
  if [[ "$begin_count" -gt 1 || "$end_count" -gt 1 ]]; then
    echo "ERROR: duplicate marker region for shared:$name in $target" >&2
    exit 1
  fi

  begin_line=$(grep -nF "$begin" "$target" | head -1 | cut -d: -f1)
  end_line=$(grep -nF "$end" "$target" | head -1 | cut -d: -f1)
  if [[ "$end_line" -le "$begin_line" ]]; then
    echo "ERROR: marker order inverted for shared:$name in $target (END at line $end_line <= BEGIN at line $begin_line)" >&2
    exit 1
  fi
}

sync_block() {
  local name="$1"
  local target_rel="$2"
  local target="$REPO_ROOT/$target_rel"
  local src="$RULES_DIR/$name.md"
  local begin="<!-- BEGIN shared:$name -->"
  local end="<!-- END shared:$name -->"

  if [[ ! -f "$src" ]]; then
    echo "ERROR: canonical file not found: $src" >&2
    exit 1
  fi
  if [[ ! -f "$target" ]]; then
    echo "ERROR: target file not found: $target" >&2
    exit 1
  fi

  validate_markers "$target" "$name"

  # 同一ディレクトリ内に一時ファイルを作り mv で atomic に置換する
  local tmp
  tmp="$(mktemp "$target.XXXXXX")"
  awk -v begin="$begin" -v end="$end" -v src="$src" '
    $0 == begin {
      print
      while ((getline line < src) > 0) print line
      close(src)
      skipping = 1
      next
    }
    $0 == end { skipping = 0 }
    !skipping { print }
  ' "$target" > "$tmp"

  if [[ "$MODE" == "--check" ]]; then
    if ! diff -q "$target" "$tmp" > /dev/null 2>&1; then
      echo "DRIFT: shared:$name -> $target_rel"
      drift_found=1
    fi
    rm -f "$tmp"
  else
    mv "$tmp" "$target"
    echo "synced shared:$name -> $target_rel"
  fi
}

while IFS=$'\t' read -r name target_rel; do
  [[ -z "$name" ]] && continue
  sync_block "$name" "$target_rel"
done <<< "$SYNC_MAP"

if [[ "$MODE" == "--check" ]]; then
  if [[ "$drift_found" -ne 0 ]]; then
    echo "ERROR: drift detected (see DRIFT lines above). run with --write to sync." >&2
    exit 1
  fi
  echo "OK: all synced blocks match canonical sources"
fi
