#!/usr/bin/env bash
# validate-layout.sh — repo構造の最終validator(構造更新計画 Phase 6)
# tracked ファイルと、cutover後のlink-dir配下を対象に、禁止runtime名・絶対home path・manifest整合・
# manifest外のtracked file・未消費shared rule・未許可artifactを検査する。fail-fastせず違反を全件列挙してから
# 非ゼロ終了する。危険設定(bypassPermissions・danger-full-access)は非致命WARNとして表示するのみ。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$REPO_ROOT/install/manifest.tsv"
SYNC_SCRIPT="$REPO_ROOT/shared/bin/sync-shared-rules.sh"
CLAUDE_MD="$REPO_ROOT/claude/CLAUDE.md"

cd "$REPO_ROOT"

violations=0
fail() {
  echo "FAIL: $*" >&2
  violations=$((violations + 1))
}
warn() {
  echo "WARN: $*"
}

# =========================================================================
# 1. 禁止runtime名(追跡ファイルに含まれてはならない)
# =========================================================================
echo "== 1. forbidden tracked runtime names =="
FORBIDDEN_BASENAMES=(
  ".credentials.json" "auth.json" "history.jsonl" "session_index.jsonl"
  "installation_id" "messages.db" "settings.local.json" "CLAUDE.local.md" "default.rules"
)
FORBIDDEN_PATHS=("codex/config.toml" "codex/gh.config.toml")

while IFS= read -r f; do
  base="$(basename "$f")"
  for n in "${FORBIDDEN_BASENAMES[@]}"; do
    [[ "$base" == "$n" ]] && fail "forbidden runtime name tracked: $f"
  done
  case "$base" in
    *.sqlite | *.sqlite-*) fail "forbidden runtime name tracked: $f" ;;
  esac
  for p in "${FORBIDDEN_PATHS[@]}"; do
    [[ "$f" == "$p" ]] && fail "forbidden runtime path tracked: $f"
  done
done < <(git ls-files)

# =========================================================================
# 2. 絶対home path(docs/archive/と意図的に絶対pathを使うfixtureは除外)
# =========================================================================
echo "== 2. absolute home paths =="
while IFS= read -r f; do
  case "$f" in
    docs/archive/* | tests/*) continue ;;
  esac
  [[ -f "$f" ]] || continue
  matches="$(grep -InoE '/home/[A-Za-z0-9][A-Za-z0-9_.-]*' "$f" || true)"
  [[ -z "$matches" ]] && continue
  while IFS=: read -r lineno match; do
    fail "absolute home path in $f:$lineno: $match"
  done <<< "$matches"
done < <(git ls-files)

# =========================================================================
# 3. manifest整合(3列固定・source実在+tracked・target重複なし)
# =========================================================================
echo "== 3. manifest integrity =="
declare -a MANIFEST_MODE=()
declare -a MANIFEST_SRC=()
declare -a MANIFEST_TARGET=()
declare -A SEEN_TARGETS=()
line_no=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line_no=$((line_no + 1))
  [[ -z "$line" ]] && continue
  [[ "$line" == \#* ]] && continue

  field_count=$(awk -F'\t' '{print NF}' <<< "$line")
  if [[ "$field_count" -ne 3 ]]; then
    fail "install/manifest.tsv:$line_no: mode<TAB>source<TAB>target の3列が必要です(実際: ${field_count}列)"
    continue
  fi

  IFS=$'\t' read -r mode src target <<< "$line"

  case "$mode" in
    link-file)
      if [[ ! -f "$REPO_ROOT/$src" ]]; then
        fail "install/manifest.tsv:$line_no: source ファイルが存在しません: $src"
      elif ! git ls-files --error-unmatch -- "$src" > /dev/null 2>&1; then
        fail "install/manifest.tsv:$line_no: source が git 追跡されていません: $src"
      fi
      ;;
    link-dir)
      if [[ ! -d "$REPO_ROOT/$src" ]]; then
        fail "install/manifest.tsv:$line_no: source ディレクトリが存在しません: $src"
      elif [[ -z "$(git ls-files -- "$src")" ]]; then
        fail "install/manifest.tsv:$line_no: source ディレクトリに git 追跡ファイルがありません: $src"
      fi
      ;;
    *)
      fail "install/manifest.tsv:$line_no: 不明な mode '$mode'"
      continue
      ;;
  esac

  if [[ -e "$REPO_ROOT/$src" || -L "$REPO_ROOT/$src" ]]; then
    src_real="$(realpath -e -- "$REPO_ROOT/$src")"
    if [[ "$src_real" != "$REPO_ROOT" && "$src_real" != "$REPO_ROOT/"* ]]; then
      fail "install/manifest.tsv:$line_no: source の実体がrepo外を指しています: $src -> $src_real"
    fi
  fi

  if [[ -n "${SEEN_TARGETS[$target]:-}" ]]; then
    fail "install/manifest.tsv:$line_no: target が重複しています: $target (既存: ${SEEN_TARGETS[$target]})"
  fi
  SEEN_TARGETS["$target"]="line $line_no"

  MANIFEST_MODE+=("$mode")
  MANIFEST_SRC+=("$src")
  MANIFEST_TARGET+=("$target")
done < "$MANIFEST"

for ((i = 0; i < ${#MANIFEST_TARGET[@]}; i++)); do
  for ((j = i + 1; j < ${#MANIFEST_TARGET[@]}; j++)); do
    a="${MANIFEST_TARGET[$i]%/}"
    b="${MANIFEST_TARGET[$j]%/}"
    if [[ "$a" == "$b/"* || "$b" == "$a/"* ]]; then
      fail "manifest targets overlap: $a / $b"
    fi
  done
done

while IFS= read -r f; do
  [[ -L "$f" ]] || continue
  if ! link_real="$(realpath -e -- "$f" 2>/dev/null)"; then
    fail "tracked symlink is broken: $f -> $(readlink "$f")"
  elif [[ "$link_real" != "$REPO_ROOT" && "$link_real" != "$REPO_ROOT/"* ]]; then
    fail "tracked symlink points outside repo: $f -> $link_real"
  fi
done < <(git ls-files)

# =========================================================================
# 4. manifest外のtracked file(claude/・codex/・shared/ 配下)
# =========================================================================
echo "== 4. tracked files outside manifest coverage =="
ALLOWLIST_EXACT=("claude/.gitignore" "claude/README.md")
ALLOWLIST_PREFIX=("claude/githooks/")

is_covered() {
  local f="$1" e p i m s
  for e in "${ALLOWLIST_EXACT[@]}"; do
    [[ "$f" == "$e" ]] && return 0
  done
  for p in "${ALLOWLIST_PREFIX[@]}"; do
    [[ "$f" == "$p"* ]] && return 0
  done
  for ((i = 0; i < ${#MANIFEST_MODE[@]}; i++)); do
    m="${MANIFEST_MODE[$i]}"
    s="${MANIFEST_SRC[$i]}"
    if [[ "$m" == "link-file" && "$f" == "$s" ]]; then
      return 0
    fi
    if [[ "$m" == "link-dir" && "$f" == "$s/"* ]]; then
      return 0
    fi
  done
  return 1
}

while IFS= read -r f; do
  case "$f" in
    claude/* | codex/* | shared/*) ;;
    *) continue ;;
  esac
  # 未commitの削除(index上はtrackedだがworking treeに実体がない)は
  # git ls-files ベースの本checkでは対象外とする(CIのfresh checkoutでは発生しない)
  [[ -f "$f" ]] || continue
  if ! is_covered "$f"; then
    fail "tracked file not covered by manifest or allowlist: $f"
  fi
done < <(git ls-files)

# =========================================================================
# 5. generic agentにprivate project固有sectionを置かない
# =========================================================================
echo "== 5. private project sections in generic agents =="
while IFS= read -r f; do
  if grep -nF 'Primary Focus（プロジェクト固有）' "$f" >/dev/null; then
    fail "project-specific section in generic agent: $f"
  fi
done < <(git ls-files 'claude/agents/*.md')

# =========================================================================
# 6. source tree配下の未許可local artifact
#    旧whole-directory symlink構成ではmigration対象が意図的にrepo内にあるためskipし、
#    cutover後とCIのfresh checkoutで検査する。
# =========================================================================
echo "== 6. local artifacts under source trees =="
old_layout=false
old_layout_count=0
for pair in ".claude:claude" ".codex:codex" ".agents:shared"; do
  home_name="${pair%%:*}"
  repo_name="${pair#*:}"
  if [[ -L "${AGENTS_TOOLKIT_HOME:-$HOME}/$home_name" ]] && \
     [[ "$(readlink -f "${AGENTS_TOOLKIT_HOME:-$HOME}/$home_name")" == "$REPO_ROOT/$repo_name" ]]; then
    old_layout_count=$((old_layout_count + 1))
  fi
done
if [[ "$old_layout_count" -eq 3 ]]; then
  old_layout=true
elif [[ "$old_layout_count" -gt 0 ]]; then
  fail "partial old layout detected: expected 0 or 3 whole-directory symlinks, found $old_layout_count"
fi

if [[ "$old_layout" == "true" ]]; then
  warn "旧whole-directory symlink構成のためlocal artifact検査をskipします。migration後に再実行してください"
else
  declare -A SEEN_LOCAL_ARTIFACTS=()
  while IFS= read -r -d '' f; do
    [[ -n "${SEEN_LOCAL_ARTIFACTS[$f]:-}" ]] && continue
    SEEN_LOCAL_ARTIFACTS["$f"]=1
    case "/$f/" in
      */.venv/* | */.mypy_cache/* | */.pytest_cache/* | */.ruff_cache/* | */__pycache__/*) ;;
      *) fail "unapproved local artifact under source tree: $f" ;;
    esac
  done < <(
    {
      git ls-files --others --exclude-standard -z -- claude codex shared
      git ls-files --others --ignored --exclude-standard -z -- claude codex shared
    }
  )
fi

# =========================================================================
# 7. 未消費shared rule(SYNC_MAP または claude/CLAUDE.md import のどちらにも登場しない)
# =========================================================================
echo "== 7. unconsumed shared rules =="
SYNC_NAMES="$(sed -n "/^SYNC_MAP=\$(cat <<'EOF'\$/,/^EOF\$/p" "$SYNC_SCRIPT" | sed '1d;$d' | awk -F'\t' '{print $1}' | sort -u)"
CLAUDE_MD_NAMES="$(grep -oE '@~/\.agents/rules/[A-Za-z0-9_-]+\.md' "$CLAUDE_MD" | sed -E 's#@~/\.agents/rules/##; s/\.md$//' | sort -u)"

for rule_file in "$REPO_ROOT"/shared/rules/*.md; do
  name="$(basename "$rule_file" .md)"
  if ! grep -qxF "$name" <<< "$SYNC_NAMES" && ! grep -qxF "$name" <<< "$CLAUDE_MD_NAMES"; then
    fail "shared rule not consumed by SYNC_MAP or claude/CLAUDE.md import: shared/rules/$name.md"
  fi
done

# =========================================================================
# 8. 危険設定の警告(非致命、exit codeに影響しない)
# =========================================================================
echo "== 8. dangerous settings (non-fatal warnings) =="
for f in claude/settings.json codex/config.toml codex/gh.config.toml; do
  [[ -f "$f" ]] || continue
  matches="$(grep -InoE 'bypassPermissions|danger-full-access' "$f" || true)"
  [[ -z "$matches" ]] && continue
  while IFS=: read -r lineno content; do
    warn "$f:$lineno: $content"
  done <<< "$matches"
done

echo
if [[ "$violations" -eq 0 ]]; then
  echo "PASS: no layout violations found"
  exit 0
fi
echo "FAIL: $violations violation(s) found" >&2
exit 1
