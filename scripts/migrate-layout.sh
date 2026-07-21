#!/usr/bin/env bash
# migrate-layout.sh — whole-directory symlink構成(旧)から個別symlink構成(新)への移行script
# 構造更新計画 Phase 3/4。~/.claude・~/.codex・~/.agents が repo を丸ごと指すsymlinkである状態から、
# それぞれを実directoryへ戻し、git追跡source以外(credentials・sessions・cache等のruntime)を
# 実directory側 or XDG state側へ移動し、bootstrap.sh(install/manifest.tsv)による個別symlinkへ
# 移行する。
#
# Usage:
#   migrate-layout.sh --dry-run   移動計画を列挙するだけで一切変更しない
#   migrate-layout.sh --apply     実際に移行する(途中失敗時は自動rollback)
#
# 環境変数:
#   AGENTS_TOOLKIT_REPO           repo root(既定: このscriptの位置から算出)
#   AGENTS_TOOLKIT_HOME           $HOME相当(既定: $HOME。テストでsandboxを指すために使う)
#   AGENTS_TOOLKIT_MIGRATE_FORCE  1でactive session検出を自己責任でスキップ
# -E(errtrace): ERR trapがfunction内の失敗にも伝播するようにする(既定では
# 関数内のコマンド失敗はERR trapを発火しない、というbashの仕様への対処)
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: migrate-layout.sh (--dry-run|--apply)
  --dry-run  移動計画を列挙するだけで一切変更しない
  --apply    実際に移行する(途中失敗時は自動rollback)
EOF
}

MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --apply) MODE="apply"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "ERROR: 不明な引数: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done
if [[ -z "$MODE" ]]; then
  echo "ERROR: --dry-run または --apply のどちらかが必須です" >&2
  usage >&2
  exit 2
fi

if [[ -n "${AGENTS_TOOLKIT_REPO:-}" ]]; then
  REPO="$(cd "$AGENTS_TOOLKIT_REPO" && pwd -P)"
else
  REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fi
AT_HOME="${AGENTS_TOOLKIT_HOME:-$HOME}"
XDG_STATE="${XDG_STATE_HOME:-$AT_HOME/.local/state}"
XDG_CONFIG="${XDG_CONFIG_HOME:-$AT_HOME/.config}"
MANIFEST="$REPO/install/manifest.tsv"
FORCE="${AGENTS_TOOLKIT_MIGRATE_FORCE:-0}"

ROOTS=(claude codex shared)

real_name_for() {
  case "$1" in
    claude) echo ".claude" ;;
    codex) echo ".codex" ;;
    shared) echo ".agents" ;;
  esac
}

# ============================================================
# preflight 1: ~/.claude ~/.codex ~/.agents が repo を指す whole-directory symlink であること
# ============================================================
check_symlinks() {
  local root real target expected current
  for root in "${ROOTS[@]}"; do
    real="$(real_name_for "$root")"
    target="$AT_HOME/$real"
    expected="$REPO/$root"
    if [[ ! -L "$target" ]]; then
      echo "ERROR: preflight(symlink): $target は symlink ではありません(旧構成ではない、または既にmigration済みの可能性)" >&2
      exit 1
    fi
    current="$(readlink "$target")"
    if [[ "$current" != "$expected" ]]; then
      echo "ERROR: preflight(symlink): $target は想定と異なる場所を指しています(現在: $current / 期待: $expected)" >&2
      exit 1
    fi
    echo "ok: preflight(symlink) $target -> $expected"
  done
}

# ============================================================
# preflight 2: install/manifest.tsv が存在しparseできること(link-dir sourceの一覧も取得する)
# ============================================================
declare -a LINKDIR_SOURCES=()

check_manifest() {
  if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: preflight(manifest): manifest が見つかりません: $MANIFEST" >&2
    exit 1
  fi
  local line_no=0 line mode src target field_count src_real
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    field_count="$(awk -F'\t' '{print NF}' <<< "$line")"
    if [[ "$field_count" -ne 3 ]]; then
      echo "ERROR: preflight(manifest): $MANIFEST:$line_no: mode<TAB>source<TAB>target の3列が必要です(実際: ${field_count}列)" >&2
      exit 1
    fi
    IFS=$'\t' read -r mode src target <<< "$line"
    case "$mode" in
      link-file|link-dir) ;;
      *)
        echo "ERROR: preflight(manifest): $MANIFEST:$line_no: 不明な mode '$mode'" >&2
        exit 1
        ;;
    esac
    if [[ -z "$src" || -z "$target" ]]; then
      echo "ERROR: preflight(manifest): $MANIFEST:$line_no: source・target は空にできません" >&2
      exit 1
    fi
    if [[ ! -e "$REPO/$src" && ! -L "$REPO/$src" ]]; then
      echo "ERROR: preflight(manifest): $MANIFEST:$line_no: sourceが存在しません: $src" >&2
      exit 1
    fi
    src_real="$(realpath -e -- "$REPO/$src")"
    if [[ "$src_real" != "$REPO" && "$src_real" != "$REPO/"* ]]; then
      echo "ERROR: preflight(manifest): $MANIFEST:$line_no: sourceの実体がrepo外です: $src -> $src_real" >&2
      exit 1
    fi
    if [[ "$mode" == "link-dir" ]]; then
      LINKDIR_SOURCES+=("$src")
    fi
  done < "$MANIFEST"
  echo "ok: preflight(manifest) $MANIFEST (link-dir source ${#LINKDIR_SOURCES[@]}件)"
}

is_under_linkdir_source() {
  local rel="$1" s
  for s in "${LINKDIR_SOURCES[@]}"; do
    if [[ "$rel" == "$s" || "$rel" == "$s"/* ]]; then
      return 0
    fi
  done
  return 1
}

# ============================================================
# 移動計画の構築
#   git ls-files/status で tracked/untracked/mixed を判定し、untracked/ignoredを
#   例外ルール(skill-state XDG化・agmsg XDG化・local開発artifact残置・
#   旧nested configのarchive退避)に照らして分類する。どれにも該当しない untracked/ignored は
#   「runtime/private overlay を実directoryへ移動」する一般則の対象とする。
#   git から不可視な directory(nested git repo等)は unclassified として中断する。
# ============================================================
declare -a PLAN_SRC=()    # repo root相対path
declare -a PLAN_DST=()    # 絶対path(最終目的地)
declare -a PLAN_KIND=()   # move(実directoryへ) | state(XDG state) | config(XDG config)
declare -a WARN_PYCACHE=()
declare -a WARN_DEV_ARTIFACTS=()
declare -a UNCLASSIFIED=()

classify_kind() {
  local rel="$1" abs="$REPO/$1"
  if [[ -d "$abs" ]]; then
    local tracked_n untracked_n
    tracked_n="$(git -C "$REPO" ls-files -- "$rel" | wc -l)"
    untracked_n="$(git -C "$REPO" status --porcelain --ignored=matching -- "$rel" | wc -l)"
    if [[ "$tracked_n" -gt 0 && "$untracked_n" -gt 0 ]]; then
      echo "mixed"
    elif [[ "$tracked_n" -gt 0 ]]; then
      echo "tracked"
    elif [[ "$untracked_n" -eq 0 ]] && [[ -n "$(find "$abs" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
      # tracked/untracked ともに0件だが実体は存在する = git から不可視(nested repo等)
      echo "opaque"
    else
      echo "untracked"
    fi
  else
    if git -C "$REPO" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
      echo "tracked"
    else
      echo "untracked"
    fi
  fi
}

classify_action() {
  local rel="$1" base
  base="$(basename "$rel")"

  # 例外3: skill state(固定path、存在する場合のみ)
  case "$rel" in
    claude/skills/config-audit/audit-history.jsonl)
      PLAN_SRC+=("$rel"); PLAN_DST+=("$XDG_STATE/agents-toolkit/config-audit/audit-history.jsonl"); PLAN_KIND+=("state")
      return ;;
    claude/skills/knowledge-audit/promotion-candidates.md)
      PLAN_SRC+=("$rel"); PLAN_DST+=("$XDG_STATE/agents-toolkit/knowledge-audit/promotion-candidates.md"); PLAN_KIND+=("state")
      return ;;
    claude/skills/python-refactor-analysis/.analysis)
      PLAN_SRC+=("$rel"); PLAN_DST+=("$XDG_STATE/agents-toolkit/python-refactor-analysis/.analysis"); PLAN_KIND+=("state")
      return ;;
    claude/CLAUDE.local.md)
      PLAN_SRC+=("$rel"); PLAN_DST+=("$XDG_CONFIG/agents-toolkit/private-routing.md"); PLAN_KIND+=("config")
      return ;;
  esac

  # 例外2: agmsg runtime state
  if [[ "$rel" == shared/skills/agmsg/* ]]; then
    case "$base" in
      db|run|teams)
        PLAN_SRC+=("$rel"); PLAN_DST+=("$XDG_STATE/agmsg/$base"); PLAN_KIND+=("state")
        return ;;
    esac
  fi

  # source treeで許容するのは、gitignore済みのlocal開発artifactだけ。
  # vendor runtimeや用途不明のentryはこのallowlistへ混ぜない。
  case "$base" in
    .venv|.mypy_cache|.pytest_cache|.ruff_cache|__pycache__)
      WARN_DEV_ARTIFACTS+=("$rel")
      [[ "$base" == "__pycache__" ]] && WARN_PYCACHE+=("$rel")
      return 0 ;;
  esac

  # 旧nested config候補は削除せず、source tree外のmigration archiveへ退避する。
  case "$rel" in
    claude/.agents|claude/.codex)
      PLAN_SRC+=("$rel"); PLAN_DST+=("$XDG_STATE/agents-toolkit/migration-archive/$rel"); PLAN_KIND+=("state")
      return ;;
  esac

  # manifest の link-dir source 配下にある未知のuntracked entryは、install後も
  # source treeへ書き込まれるため自動移動せずpreflight違反として停止する。
  if is_under_linkdir_source "$rel"; then
    UNCLASSIFIED+=("$rel (link-dir source配下の未許可artifact)")
    return
  fi

  # 一般則: runtime / private overlay → 実directoryの同相対pathへ移動
  local root="${rel%%/*}" under="${rel#*/}" real
  real="$(real_name_for "$root")"
  PLAN_SRC+=("$rel"); PLAN_DST+=("$AT_HOME/$real/$under"); PLAN_KIND+=("move")
}

# untracked判定されたdirectoryが、実は内部にexception対象(skill state・agmsg・
# link-dir source)を含みうる場合はtrue。classify_kindはgit的に「配下すべてuntracked」を
# 一つのkindにまとめてしまうため、これが無いと例えば shared/skills(全untracked)配下の
# shared/skills/agmsg/db がexception判定されないまま丸ごとmoveされてしまう。
should_force_recurse() {
  local rel="$1" s
  for s in \
    "claude/skills/config-audit/audit-history.jsonl" \
    "claude/skills/knowledge-audit/promotion-candidates.md" \
    "claude/skills/python-refactor-analysis/.analysis"
  do
    if [[ "$s" == "$rel" || "$s" == "$rel"/* ]]; then
      return 0
    fi
  done
  if [[ "shared/skills/agmsg" == "$rel" || "shared/skills/agmsg" == "$rel"/* ]]; then
    return 0
  fi
  for s in "${LINKDIR_SOURCES[@]}"; do
    if [[ "$s" == "$rel"/* ]]; then
      return 0
    fi
  done
  return 1
}

recurse_children() {
  local rel="$1" child name
  for child in "$REPO/$rel"/* "$REPO/$rel"/.[!.]* "$REPO/$rel"/..?*; do
    [[ -e "$child" || -L "$child" ]] || continue
    name="$(basename "$child")"
    walk "$rel/$name"
  done
}

walk() {
  local rel="$1" kind
  kind="$(classify_kind "$rel")"
  case "$kind" in
    tracked) : ;;  # git追跡source、repoに残す
    mixed)
      recurse_children "$rel"
      ;;
    untracked)
      if [[ -d "$REPO/$rel" ]] && should_force_recurse "$rel"; then
        recurse_children "$rel"
      else
        classify_action "$rel"
      fi
      ;;
    opaque)
      UNCLASSIFIED+=("$rel (git から不可視: nested git repo等の可能性)")
      ;;
  esac
}

build_plan() {
  local root
  for root in "${ROOTS[@]}"; do
    recurse_children "$root"
  done
}

# ============================================================
# preflight 5: 未分類entry検出
# ============================================================
check_unclassified() {
  if [[ "${#UNCLASSIFIED[@]}" -gt 0 ]]; then
    echo "ERROR: preflight(未分類entry): 移動計画でカバーされないentryがあります。分類してから再実行してください:" >&2
    printf '  - %s\n' "${UNCLASSIFIED[@]}" >&2
    exit 1
  fi
  echo "ok: preflight(未分類entry) なし"
}

# ============================================================
# preflight 3: staging先(=AT_HOME)・XDG state先の空き容量
# ============================================================
TOTAL_HOME_BYTES=0
TOTAL_XDG_BYTES=0
TOTAL_CONFIG_BYTES=0

avail_bytes() {
  local dir="$1"
  while [[ ! -d "$dir" ]]; do dir="$(dirname "$dir")"; done
  df --output=avail -B1 "$dir" | tail -n1 | tr -d ' '
}

check_capacity() {
  local i sz
  TOTAL_HOME_BYTES=0
  TOTAL_XDG_BYTES=0
  TOTAL_CONFIG_BYTES=0
  for i in "${!PLAN_SRC[@]}"; do
    sz="$(du -sb "$REPO/${PLAN_SRC[$i]}" 2>/dev/null | cut -f1)"
    sz="${sz:-0}"
    case "${PLAN_KIND[$i]}" in
      state) TOTAL_XDG_BYTES=$((TOTAL_XDG_BYTES + sz)) ;;
      config) TOTAL_CONFIG_BYTES=$((TOTAL_CONFIG_BYTES + sz)) ;;
      move) TOTAL_HOME_BYTES=$((TOTAL_HOME_BYTES + sz)) ;;
    esac
  done
  local total_all=$((TOTAL_HOME_BYTES + TOTAL_XDG_BYTES + TOTAL_CONFIG_BYTES))

  # 全entryはまずAT_HOME配下のstagingを経由するため、AT_HOME側は合計を要求する
  local avail_home
  avail_home="$(avail_bytes "$AT_HOME")"
  if [[ "$avail_home" -lt "$total_all" ]]; then
    echo "ERROR: preflight(容量): $AT_HOME の空き容量不足(必要: ${total_all} bytes, 空き: ${avail_home} bytes)" >&2
    exit 1
  fi

  if [[ "$TOTAL_XDG_BYTES" -gt 0 ]]; then
    local avail_xdg
    avail_xdg="$(avail_bytes "$XDG_STATE")"
    if [[ "$avail_xdg" -lt "$TOTAL_XDG_BYTES" ]]; then
      echo "ERROR: preflight(容量): $XDG_STATE の空き容量不足(必要: ${TOTAL_XDG_BYTES} bytes, 空き: ${avail_xdg} bytes)" >&2
      exit 1
    fi
  fi
  if [[ "$TOTAL_CONFIG_BYTES" -gt 0 ]]; then
    local avail_config
    avail_config="$(avail_bytes "$XDG_CONFIG")"
    if [[ "$avail_config" -lt "$TOTAL_CONFIG_BYTES" ]]; then
      echo "ERROR: preflight(容量): $XDG_CONFIG の空き容量不足(必要: ${TOTAL_CONFIG_BYTES} bytes, 空き: ${avail_config} bytes)" >&2
      exit 1
    fi
  fi
  echo "ok: preflight(容量) 必要 ${total_all} bytes(うちstate ${TOTAL_XDG_BYTES} bytes / config ${TOTAL_CONFIG_BYTES} bytes)"
}

# XDG側の既存stateを上書き・入れ子化しない。HOME側のmove先は旧whole-directory
# symlinkを外した直後に新規作成する空directory配下なので、ここではexternal先を検査する。
check_destination_collisions() {
  local i j dst other parent
  for i in "${!PLAN_DST[@]}"; do
    dst="${PLAN_DST[$i]}"
    for j in "${!PLAN_DST[@]}"; do
      [[ "$i" == "$j" ]] && continue
      other="${PLAN_DST[$j]}"
      if [[ "$dst" == "$other" || "$dst" == "$other/"* ]]; then
        echo "ERROR: preflight(destination): 移行先が重複または親子関係です: $dst / $other" >&2
        exit 1
      fi
    done
    [[ "${PLAN_KIND[$i]}" == "move" ]] && continue
    if [[ -e "$dst" || -L "$dst" ]]; then
      echo "ERROR: preflight(destination): 移行先が既に存在します: $dst" >&2
      exit 1
    fi
    parent="$(dirname "$dst")"
    while [[ ! -e "$parent" && ! -L "$parent" ]]; do
      parent="$(dirname "$parent")"
    done
    if [[ ! -d "$parent" || ! -w "$parent" ]]; then
      echo "ERROR: preflight(destination): 移行先の親に書き込めません: $parent" >&2
      exit 1
    fi
  done
  echo "ok: preflight(destination) 衝突なし"
}

# ============================================================
# preflight 4: active session検出
# ============================================================
check_active_sessions() {
  if [[ "$FORCE" == "1" ]]; then
    echo "WARN: AGENTS_TOOLKIT_MIGRATE_FORCE=1 — active session検出を自己責任でスキップします" >&2
    return
  fi
  local found=() pid
  while read -r pid; do [[ -n "$pid" ]] && found+=("claude(pid=$pid)"); done < <(pgrep -x claude 2>/dev/null || true)
  while read -r pid; do [[ -n "$pid" ]] && found+=("codex(pid=$pid)"); done < <(pgrep -x codex 2>/dev/null || true)
  while read -r pid; do [[ -n "$pid" ]] && found+=("agmsg-watch(pid=$pid)"); done < <(pgrep -f 'agmsg/scripts/watch\.sh' 2>/dev/null || true)
  if [[ "${#found[@]}" -gt 0 ]]; then
    echo "ERROR: preflight(active session): 実行中のセッションを検出しました。すべて終了してから再実行してください(自己責任で続行する場合は AGENTS_TOOLKIT_MIGRATE_FORCE=1):" >&2
    printf '  - %s\n' "${found[@]}" >&2
    exit 1
  fi
  echo "ok: preflight(active session) なし"
}

# ============================================================
# dry-run出力
# ============================================================
print_plan() {
  echo
  echo "=== migrate-layout.sh 移動計画 (mode=$MODE) ==="
  echo "REPO=$REPO"
  echo "AT_HOME=$AT_HOME"
  echo "XDG_STATE=$XDG_STATE"
  echo "XDG_CONFIG=$XDG_CONFIG"
  echo "staging(--apply時に生成): $AT_HOME/.agents-toolkit-migration-<random>/"
  echo
  echo "--- 移動対象 (${#PLAN_SRC[@]} entries, 必要容量 $((TOTAL_HOME_BYTES + TOTAL_XDG_BYTES + TOTAL_CONFIG_BYTES)) bytes) ---"
  local i
  for i in "${!PLAN_SRC[@]}"; do
    printf '[%s] %s -> %s\n' "${PLAN_KIND[$i]}" "$REPO/${PLAN_SRC[$i]}" "${PLAN_DST[$i]}"
  done
  echo
  echo "--- symlink削除 / 実ディレクトリ化 ---"
  local root real
  for root in "${ROOTS[@]}"; do
    real="$(real_name_for "$root")"
    printf 'rm %s/%s (symlink -> %s)\n' "$AT_HOME" "$real" "$REPO/$root"
    printf 'mkdir %s/%s\n' "$AT_HOME" "$real"
  done
  echo
  if [[ "${#WARN_PYCACHE[@]}" -gt 0 ]]; then
    echo "--- 情報: __pycache__ (許可済みlocal開発artifact、移動対象外) ---"
    printf '  %s\n' "${WARN_PYCACHE[@]}"
  fi
  if [[ "${#WARN_DEV_ARTIFACTS[@]}" -gt 0 ]]; then
    echo "--- 情報: 許可済みlocal開発artifact (残置) ---"
    printf '  %s\n' "${WARN_DEV_ARTIFACTS[@]}"
  fi
  echo
  echo "実行後: bash $REPO/bootstrap.sh --apply (個別symlink作成) / --check (検証)"
}

# ============================================================
# --apply: 操作log・逆操作script(LIFO)を書きながら2段階でmvする
# ============================================================
STAGING=""
OP_LOG=""
REVERSE_SCRIPT=""
ROLLED_BACK=0

log_op() {
  echo "$(date -Iseconds) $*" >> "$OP_LOG"
}

# 逆操作script先頭(shebang+set -e+comment、常に3行)の直後へ新しい逆操作を追記する
# = 実行の都度先頭へ挿入することでLIFO(直近の操作から逆順に実行)になる
prepend_reverse_op() {
  local op_line="$1" tmp
  tmp="$(mktemp)"
  { head -n 3 "$REVERSE_SCRIPT"; echo "$op_line"; tail -n +4 "$REVERSE_SCRIPT"; } > "$tmp"
  mv "$tmp" "$REVERSE_SCRIPT"
  chmod +x "$REVERSE_SCRIPT"
}

do_move() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  # undoを操作前に永続化する(write-ahead)。mv自体が失敗した場合はdstが
  # 存在しないので条件付きundoは何もしない。
  prepend_reverse_op "if [[ -e '$dst' || -L '$dst' ]]; then mv '$dst' '$src'; fi"
  mv "$src" "$dst"
  log_op "mv '$src' -> '$dst'"
}

on_error() {
  if [[ "$ROLLED_BACK" -eq 1 ]]; then
    return
  fi
  ROLLED_BACK=1
  echo "ERROR: migration中に失敗しました。逆操作scriptを実行して旧構成(whole-directory symlink)へ復元します: $REVERSE_SCRIPT" >&2
  if bash "$REVERSE_SCRIPT"; then
    echo "旧構成へ復元しました" >&2
  else
    echo "ERROR: rollbackにも失敗しました。手動確認が必要です: $REVERSE_SCRIPT / $OP_LOG" >&2
  fi
  exit 1
}

apply_migration() {
  STAGING="$(mktemp -d "$AT_HOME/.agents-toolkit-migration-XXXXXXXXXX")"
  OP_LOG="$STAGING/operations.log"
  REVERSE_SCRIPT="$STAGING/rollback.sh"
  : > "$OP_LOG"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo '# 自動生成: migrate-layout.sh 逆操作script(LIFO順、旧whole-directory symlink構成へ復元)'
  } > "$REVERSE_SCRIPT"
  chmod +x "$REVERSE_SCRIPT"

  echo "staging: $STAGING"

  trap on_error ERR

  # stage1: 移動対象をstagingへ(repoからの相対path構造を維持)
  local i
  for i in "${!PLAN_SRC[@]}"; do
    do_move "$REPO/${PLAN_SRC[$i]}" "$STAGING/src/${PLAN_SRC[$i]}"
  done

  # stage2-a: 3つのwhole-directory symlinkを削除し実ディレクトリを作る
  local root real target link_target
  for root in "${ROOTS[@]}"; do
    real="$(real_name_for "$root")"
    target="$AT_HOME/$real"
    link_target="$(readlink "$target")"
    prepend_reverse_op "if [[ ! -e '$target' && ! -L '$target' ]]; then ln -s '$link_target' '$target'; fi"
    rm "$target"
    log_op "rm symlink $target (-> $link_target)"

    prepend_reverse_op "if [[ -d '$target' && ! -L '$target' ]]; then rm -rf '$target'; fi"
    mkdir "$target"
    log_op "mkdir $target"
    # rm -rf: このLIFO位置に到達する時点で、このscriptが追跡した移動分は
    # 先行する逆操作(このprepend_reverse_opより後に積まれた=先に実行される)で
    # 既にstagingへ戻っている。bootstrap.sh --apply済みなら個別symlinkが
    # 残っているが、それらはrepo側を指すだけなのでrm -rfで消してよい
    echo "ok: $target を実ディレクトリ化"
  done

  # stage2-b: stagingから最終位置(実directory または XDG state)へ
  for i in "${!PLAN_SRC[@]}"; do
    do_move "$STAGING/src/${PLAN_SRC[$i]}" "${PLAN_DST[$i]}"
  done

  echo
  echo "=== bash $REPO/bootstrap.sh --apply ==="
  HOME="$AT_HOME" AGENTS_TOOLKIT_REPO="$REPO" bash "$REPO/bootstrap.sh" --apply

  echo
  echo "=== bash $REPO/bootstrap.sh --check ==="
  HOME="$AT_HOME" AGENTS_TOOLKIT_REPO="$REPO" bash "$REPO/bootstrap.sh" --check
  for root in "${ROOTS[@]}"; do
    real="$(real_name_for "$root")"
    if [[ -L "$AT_HOME/$real" ]]; then
      echo "ERROR: $AT_HOME/$real がsymlinkのままです" >&2
      return 1
    fi
  done

  # bootstrap検証までをtransaction範囲とする。commit後に旧構成へ戻すと、
  # 移行後に生成されたruntimeを消し得るため、危険な逆操作は無効化する。
  local disabled_rollback
  disabled_rollback="$(mktemp "$STAGING/rollback-disabled-XXXXXXXXXX")"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo 'echo "ERROR: migrationはcommit済みです。移行後のruntimeを保護するため自動rollbackは実行できません。operations.logを確認して手動で退避してください。" >&2'
    echo 'exit 1'
  } > "$disabled_rollback"
  chmod +x "$disabled_rollback"
  log_op "commit: bootstrap apply/check succeeded; rollback disabled"
  # 同一staging directory内のatomic rename。失敗時はまだERR trapが有効で、
  # 元の逆操作scriptにより旧構成へ戻る。
  mv "$disabled_rollback" "$REVERSE_SCRIPT"
  trap - ERR

  echo
  echo "=== summary ==="
  echo "移動 entry 数: ${#PLAN_SRC[@]}"
  echo "情報(__pycache__残置): ${#WARN_PYCACHE[@]}"
  [[ "${#WARN_PYCACHE[@]}" -gt 0 ]] && printf '  %s\n' "${WARN_PYCACHE[@]}"
  echo "情報(許可済みlocal開発artifact残置): ${#WARN_DEV_ARTIFACTS[@]}"
  [[ "${#WARN_DEV_ARTIFACTS[@]}" -gt 0 ]] && printf '  %s\n' "${WARN_DEV_ARTIFACTS[@]}"
  echo "操作log: $OP_LOG"
  echo "rollback: transaction commit済みのため無効化 ($REVERSE_SCRIPT)"
}

# ============================================================
# main
# ============================================================
check_symlinks
check_manifest
build_plan
check_capacity
check_active_sessions
check_unclassified
check_destination_collisions

case "$MODE" in
  dry-run)
    print_plan
    exit 0
    ;;
  apply)
    apply_migration
    exit 0
    ;;
esac
