#!/usr/bin/env bash
# bootstrap.sh — install/manifest.tsv に従って設定ディレクトリの symlink を作成する(冪等)
# 新マシンセットアップ: git clone <repo> ~/agents-toolkit && bash ~/agents-toolkit/bootstrap.sh
set -euo pipefail

REPO_DIR="$(cd "${AGENTS_TOOLKIT_REPO:-$(dirname "${BASH_SOURCE[0]}")}" && pwd -P)"
MANIFEST="$REPO_DIR/install/manifest.tsv"
OVERLAY_ROOT="${AGENTS_TOOLKIT_OVERLAY:-${XDG_CONFIG_HOME:-$HOME/.config}/agents-toolkit/overlay}"

MODE="apply"
usage() {
  cat <<'EOF'
Usage: bootstrap.sh [--check|--dry-run|--apply] [--overlay PATH]
  --check    manifest(+overlay)通りの symlink 状態を検証する(変更なし)
  --dry-run  --apply が行う操作を実行せず列挙する(変更なし)
  --apply    symlink を作成する(既定。引数なしも同じ)
  --overlay PATH  overlay root を明示指定する
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    --apply) MODE="apply"; shift ;;
    --overlay)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --overlay には PATH を指定してください" >&2
        exit 1
      fi
      OVERLAY_ROOT="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "ERROR: 不明な引数: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

declare -a ENTRY_MODE=()
declare -a ENTRY_SRC=()
declare -a ENTRY_TARGET=()
declare -A SEEN_TARGETS=()

# 2026-07-23 の archive 前に配布され、source removal 後も user skill
# directory に残った toolkit-owned symlink。cleanup は broken link・既知名・
# current repo の旧 source target が完全一致する場合だけに限定する。
STALE_CLAUDE_SKILLS=(
  "deep-research-mode"
  "gh:coderabbit"
  "gh:index"
  "gh:issue"
  "gh:pr"
  "gh:review"
  "gh:start"
  "introspect"
  "issue-parser"
  "issue-retrospective"
  "issue-work-logger"
  "progress-tracker"
  "token-efficiency"
  "x-article-to-markdown"
)

# manifest 1ファイルを読み込み、検証しつつ ENTRY_* 配列へ追加する(fail-fast)
# $1=manifest file, $2=origin (public|overlay, エラーメッセージ用), $3=source解決の基準root
load_manifest_file() {
  local file="$1" origin="$2" src_root="$3"
  local line_no=0
  local line mode src target field_count
  local src_root_abs
  src_root_abs="$(cd "$src_root" && pwd -P)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    field_count="$(awk -F'\t' '{print NF}' <<< "$line")"
    if [[ "$field_count" -ne 3 ]]; then
      echo "ERROR: $file:$line_no: mode<TAB>source<TAB>target の3列が必要です(実際: ${field_count}列)" >&2
      exit 1
    fi
    IFS=$'\t' read -r mode src target <<< "$line"
    if [[ -z "$mode" || -z "$src" || -z "$target" ]]; then
      echo "ERROR: $file:$line_no: mode・source・target は空にできません" >&2
      exit 1
    fi

    case "$mode" in
      link-file|link-dir) ;;
      *)
        echo "ERROR: $file:$line_no: 不明な mode '$mode' (link-file または link-dir)" >&2
        exit 1
        ;;
    esac

    if [[ "$src" == /* ]]; then
      echo "ERROR: $file:$line_no: source は絶対 path にできません: $src" >&2
      exit 1
    fi
    if [[ "$src" == *".."* ]]; then
      echo "ERROR: $file:$line_no: source に .. を含めることはできません: $src" >&2
      exit 1
    fi
    if [[ "$target" == /* ]]; then
      echo "ERROR: $file:$line_no: target は絶対 path にできません: $target" >&2
      exit 1
    fi
    if [[ "$target" == *".."* ]]; then
      echo "ERROR: $file:$line_no: target に .. を含めることはできません: $target" >&2
      exit 1
    fi

    local src_abs="$src_root_abs/$src"
    if [[ "$mode" == "link-file" ]]; then
      if [[ -d "$src_abs" ]]; then
        echo "ERROR: $file:$line_no: mode=link-file ですが source はディレクトリです: $src_abs" >&2
        exit 1
      fi
      if [[ ! -f "$src_abs" ]]; then
        echo "ERROR: $file:$line_no: source ファイルが存在しません: $src_abs" >&2
        exit 1
      fi
    else
      if [[ ! -d "$src_abs" ]]; then
        echo "ERROR: $file:$line_no: source ディレクトリが存在しません: $src_abs" >&2
        exit 1
      fi
    fi

    local src_real
    src_real="$(realpath -e -- "$src_abs")"
    if [[ "$src_real" != "$src_root_abs" && "$src_real" != "$src_root_abs/"* ]]; then
      echo "ERROR: $file:$line_no: source の実体が source root 外を指しています: $src_abs -> $src_real" >&2
      exit 1
    fi

    if [[ -n "${SEEN_TARGETS[$target]:-}" ]]; then
      echo "ERROR: target が重複しています: $target (既存: ${SEEN_TARGETS[$target]} / 今回: $origin:$file:$line_no)" >&2
      exit 1
    fi
    SEEN_TARGETS["$target"]="$origin:$file:$line_no"

    ENTRY_MODE+=("$mode")
    ENTRY_SRC+=("$src_abs")
    ENTRY_TARGET+=("$target")
  done < "$file"
}

# target同士が親子関係だと、親のsymlink作成後に子targetを書き込む際、
# source tree側へ意図せず書き込む可能性があるため禁止する。
check_target_topology() {
  local i j a b
  for ((i = 0; i < ${#ENTRY_TARGET[@]}; i++)); do
    a="${ENTRY_TARGET[$i]%/}"
    for ((j = i + 1; j < ${#ENTRY_TARGET[@]}; j++)); do
      b="${ENTRY_TARGET[$j]%/}"
      if [[ "$a" == "$b/"* || "$b" == "$a/"* ]]; then
        echo "ERROR: target が親子関係になっています: $a / $b" >&2
        exit 1
      fi
    done
  done
}

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: manifest が見つかりません: $MANIFEST" >&2
  exit 1
fi
load_manifest_file "$MANIFEST" "public" "$REPO_DIR"

OVERLAY_MANIFEST="$OVERLAY_ROOT/manifest.tsv"
if [[ -f "$OVERLAY_MANIFEST" ]]; then
  load_manifest_file "$OVERLAY_MANIFEST" "overlay" "$OVERLAY_ROOT"
fi
check_target_topology

# 旧whole-directory symlink構成(未migration)を検出する。target の先頭path要素
# ($HOME/.claude 等)が repo を指す symlink のままだと、mkdir -p や ln -s が
# repo内の実体へ直接書き込んでしまうため、その前に検出してエラーにする。
guard_not_old_layout() {
  local target="$1"
  local top="${target%%/*}"
  local top_path="$HOME/$top"

  if [[ -L "$top_path" ]]; then
    local resolved
    resolved="$(readlink -f "$top_path" 2>/dev/null || true)"
    if [[ -n "$resolved" && "$resolved" == "$REPO_DIR"* ]]; then
      echo "ERROR: $top_path は repo ($REPO_DIR) を指す symlink です(旧構成が未 migration)。scripts/migrate-layout.sh を先に実行してください" >&2
      exit 1
    fi
  fi
}

# 2026-07-24 の誤った共有化では、Codex が発見しない SKILL.md 単体 symlink を
# 実ディレクトリ内へ配布していた。現在の variant directory link へ安全に更新できるのは、
# その旧 generated topology と完全一致し、ユーザー所有の内容が一切ない場合だけとする。
is_legacy_shared_skill_dir() {
  local target_abs="$1" src_abs="$2"
  local rel agent_kind skill_name old_skill_src entries

  [[ -d "$target_abs" && ! -L "$target_abs" ]] || return 1
  [[ "$src_abs" == "$REPO_DIR/shared/skills/"* ]] || return 1

  rel="${src_abs#"$REPO_DIR/shared/skills/"}"
  agent_kind="${rel%%/*}"
  skill_name="${rel#*/}"
  [[ "$skill_name" != "$rel" && "$skill_name" != */* ]] || return 1

  case "$agent_kind" in
    claude-code) old_skill_src="$REPO_DIR/shared/skills/$skill_name/templates/cmd.claude-code.md" ;;
    codex) old_skill_src="$REPO_DIR/shared/skills/$skill_name/templates/cmd.codex.md" ;;
    *) return 1 ;;
  esac

  entries="$(find "$target_abs" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)"
  if [[ "$entries" != "SKILL.md" && "$entries" != $'SKILL.md\nreferences' ]]; then
    return 1
  fi
  [[ -L "$target_abs/SKILL.md" ]] || return 1
  [[ "$(readlink "$target_abs/SKILL.md")" == "$old_skill_src" ]] || return 1

  if [[ "$entries" == $'SKILL.md\nreferences' ]]; then
    [[ -L "$target_abs/references" ]] || return 1
    [[ "$(readlink "$target_abs/references")" == "$REPO_DIR/shared/skills/$skill_name/references" ]] || return 1
  fi
}

# archive 済み Claude skill の旧 generated symlink かを厳密に判定する。
# 実体が復元済みの link、別 repo、相対 target、通常 file/directory は対象外。
is_stale_claude_skill_link() {
  local target_abs="$1" skill_name="$2"
  [[ -L "$target_abs" && ! -e "$target_abs" ]] || return 1
  [[ "$(readlink "$target_abs")" == "$REPO_DIR/claude/skills/$skill_name" ]]
}

handle_stale_claude_skill_links() {
  local action="$1"
  local skill_name target_abs count=0

  for skill_name in "${STALE_CLAUDE_SKILLS[@]}"; do
    target_abs="$HOME/.claude/skills/$skill_name"
    is_stale_claude_skill_link "$target_abs" "$skill_name" || continue
    count=$((count + 1))
    case "$action" in
      check)
        echo "DRIFT: stale toolkit symlink: $target_abs -> $(readlink "$target_abs")"
        ;;
      dry-run)
        echo "would unlink stale toolkit symlink: $target_abs -> $(readlink "$target_abs")"
        ;;
      apply)
        unlink "$target_abs"
        echo "unlinked stale toolkit symlink: $target_abs"
        ;;
      *)
        echo "ERROR: unknown stale-link action: $action" >&2
        exit 1
        ;;
    esac
  done

  STALE_CLAUDE_SKILL_COUNT="$count"
}

# 1エントリ分の symlink 状態を検証し、apply=true なら実際に symlink を作成する
link_entry() {
  local target_abs="$1" src_abs="$2" apply="$3"

  if [[ -L "$target_abs" ]]; then
    local current
    current="$(readlink "$target_abs")"
    if [[ "$current" == "$src_abs" ]]; then
      echo "ok: $target_abs -> $src_abs"
      return 0
    fi
    echo "ERROR: $target_abs は別の場所 ($current) を指す symlink です" >&2
    exit 1
  fi
  if [[ -e "$target_abs" ]]; then
    if is_legacy_shared_skill_dir "$target_abs" "$src_abs"; then
      if [[ "$apply" == "true" ]]; then
        local legacy_backup="$target_abs.agents-toolkit-legacy.$$"
        if [[ -e "$legacy_backup" || -L "$legacy_backup" ]]; then
          echo "ERROR: legacy skill migration の退避先が既に存在します: $legacy_backup" >&2
          exit 1
        fi
        mv "$target_abs" "$legacy_backup"
        if ! ln -s "$src_abs" "$target_abs"; then
          mv "$legacy_backup" "$target_abs"
          echo "ERROR: legacy skill migration に失敗したため旧 directory を復元しました: $target_abs" >&2
          exit 1
        fi
        [[ -L "$legacy_backup/references" ]] && unlink "$legacy_backup/references"
        unlink "$legacy_backup/SKILL.md"
        rmdir "$legacy_backup"
        echo "migrated: $target_abs -> $src_abs"
      else
        echo "would migrate legacy skill links: $target_abs -> $src_abs"
      fi
      return 0
    fi
    echo "ERROR: $target_abs に実体が存在します。手動で退避してから再実行してください" >&2
    exit 1
  fi

  if [[ "$apply" == "true" ]]; then
    mkdir -p "$(dirname "$target_abs")"
    ln -s "$src_abs" "$target_abs"
    echo "linked: $target_abs -> $src_abs"
  else
    echo "would link: $target_abs -> $src_abs"
  fi
}

# 1件目を作成する前に全targetを確認し、後半の衝突によるpartial installを防ぐ。
preflight_targets() {
  local i target target_abs src_abs current parent
  for ((i = 0; i < ${#ENTRY_MODE[@]}; i++)); do
    target="${ENTRY_TARGET[$i]}"
    target_abs="$HOME/$target"
    src_abs="${ENTRY_SRC[$i]}"
    guard_not_old_layout "$target"

    if [[ -L "$target_abs" ]]; then
      current="$(readlink "$target_abs")"
      if [[ "$current" != "$src_abs" ]]; then
        echo "ERROR: $target_abs は別の場所 ($current) を指す symlink です" >&2
        exit 1
      fi
      continue
    fi
    if [[ -e "$target_abs" ]]; then
      if is_legacy_shared_skill_dir "$target_abs" "$src_abs"; then
        continue
      fi
      echo "ERROR: $target_abs に実体が存在します。手動で退避してから再実行してください" >&2
      exit 1
    fi

    parent="$(dirname "$target_abs")"
    while [[ ! -e "$parent" && ! -L "$parent" ]]; do
      parent="$(dirname "$parent")"
    done
    if [[ ! -d "$parent" ]]; then
      echo "ERROR: target の親pathがディレクトリではありません: $parent" >&2
      exit 1
    fi
    if [[ ! -w "$parent" ]]; then
      echo "ERROR: target の作成先に書き込み権限がありません: $parent" >&2
      exit 1
    fi
  done
}

run_apply_or_dryrun() {
  local apply="$1"
  local i
  preflight_targets
  if [[ "$apply" == "true" ]]; then
    handle_stale_claude_skill_links "apply"
  else
    handle_stale_claude_skill_links "dry-run"
  fi
  for ((i = 0; i < ${#ENTRY_MODE[@]}; i++)); do
    local target="${ENTRY_TARGET[$i]}"
    link_entry "$HOME/$target" "${ENTRY_SRC[$i]}" "$apply"
  done
}

run_check() {
  local i problems=0
  for ((i = 0; i < ${#ENTRY_MODE[@]}; i++)); do
    local target="${ENTRY_TARGET[$i]}"
    local target_abs="$HOME/$target"
    local src_abs="${ENTRY_SRC[$i]}"

    guard_not_old_layout "$target"

    if [[ -L "$target_abs" ]]; then
      local current
      current="$(readlink "$target_abs")"
      if [[ "$current" == "$src_abs" ]]; then
        echo "ok: $target_abs -> $src_abs"
      else
        echo "DRIFT: $target_abs は別の場所 ($current) を指しています(期待: $src_abs)"
        problems=$((problems + 1))
      fi
    elif [[ -e "$target_abs" ]]; then
      echo "DRIFT: $target_abs に実体が存在します(symlink ではありません)"
      problems=$((problems + 1))
    else
      echo "DRIFT: $target_abs が存在しません(期待: -> $src_abs)"
      problems=$((problems + 1))
    fi
  done

  handle_stale_claude_skill_links "check"
  problems=$((problems + STALE_CLAUDE_SKILL_COUNT))

  echo
  if [[ "$problems" -eq 0 ]]; then
    echo "PASS: all ${#ENTRY_MODE[@]} manifest entries are correctly linked"
    return 0
  fi
  echo "FAIL: $problems entries drifted" >&2
  return 1
}

# Security policy is installed in Claude Code's OS-managed scope. User/project
# settings cannot replace it; bootstrap refuses to install user links until the
# exact managed policy is present. A test-only target override is deliberately
# gated behind AGENTS_TOOLKIT_TESTING=1.
run_managed_policy_check() {
  local args=(--check)
  if [[ "${AGENTS_TOOLKIT_TESTING:-0}" == "1" && -n "${AGENTS_TOOLKIT_MANAGED_POLICY_TARGET:-}" ]]; then
    args+=(--target "$AGENTS_TOOLKIT_MANAGED_POLICY_TARGET")
  fi
  "$REPO_DIR/scripts/install-managed-policy.sh" "${args[@]}"
}

# runtime / 環境前提の doctor(H-013/H-017/H-03/M-05)。check・apply の両経路で強制する。
# claude CLI 欠落は --soft-missing により NOTE 続行(codex 専用マシン)。
# custom XDG・下限未満 version・prerelease は例外なく fail-closed。
run_doctor() {
  "$REPO_DIR/scripts/check-runtime.sh" --soft-missing
}

case "$MODE" in
  check)
    run_managed_policy_check
    run_doctor
    rc=0
    run_check || rc=$?
    exit "$rc"
    ;;
  dry-run)
    run_apply_or_dryrun "false"
    exit 0
    ;;
  apply)
    run_managed_policy_check
    run_doctor
    run_apply_or_dryrun "true"
    # gitleaks pre-commit hook の有効化(core.hooksPath は .git/config 保存のためマシンごとに必要)
    # -e: worktree 等で .git がファイルの場合も対応
    if [[ -e "$REPO_DIR/.git" ]]; then
      git -C "$REPO_DIR" config core.hooksPath claude/githooks
      echo "hooksPath: claude/githooks"
    fi
    exit 0
    ;;
esac
