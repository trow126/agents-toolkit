#!/usr/bin/env bash
# storage.sh — resolve where agmsg persists runtime state: the sqlite message
# store (messages.db), the run/ directory (pidfiles, locks, watermarks...) and
# the teams/ directory (team configs).
#
# Scope: path resolution only — where state is persisted. This is NOT a
# storage-driver interface; it just centralizes the path resolution that was
# previously duplicated across the script set.
#
# State root resolution order (agmsg_state_root):
#   1. AGMSG_STATE_HOME              — explicit override (env)
#   2. legacy skill-dir state        — only when AGMSG_STATE_HOME is unset, the
#                                      XDG location has no persistent state yet,
#                                      AND a legacy DB/config/team exists under
#                                      the skill directory (pre-migration installs).
#                                      Prints a one-line stderr warning.
#   3. ${XDG_STATE_HOME:-$HOME/.local/state}/agmsg — default
#
# AGMSG_STORAGE_PATH remains a DB-directory-only override (back-compat): when
# set, it wins for messages.db specifically but does NOT move run/ or teams/,
# which still resolve from the state root above. Priority for the DB path is
# therefore: AGMSG_STORAGE_PATH > AGMSG_STATE_HOME > legacy detection > XDG default.

# Guard against double-source: this file is sourced both directly by entry
# scripts and transitively via actas-lock.sh / resolve-project.sh /
# instance-id.sh.
[ -n "${_AGMSG_STORAGE_SH:-}" ] && return 0
_AGMSG_STORAGE_SH=1

# Internal: echo the agmsg skill directory. Used only for legacy-state
# detection — the actual state root lives outside the skill tree.
#
# Resolution:
#   1. BASH_SOURCE[0]     — derive from this file's own path (standard case)
#   2. SKILL_DIR env var  — set by callers before sourcing (sandbox fallback;
#                           Claude Code sandbox runs Bash via pipe/eval, so
#                           BASH_SOURCE is not populated)
_agmsg_skill_dir() {
  if [ -n "${BASH_SOURCE[0]:-}" ]; then
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s\n' "$(cd "$lib_dir/../.." && pwd)"
    return
  fi
  if [ -n "${SKILL_DIR:-}" ]; then
    printf '%s\n' "$SKILL_DIR"
    return
  fi
  echo "Error: cannot resolve skill dir (BASH_SOURCE and SKILL_DIR both empty)" >&2
  return 1
}

# Echo the state root directory — the parent of db/, run/, teams/. See the
# resolution order above. Emits a one-line stderr warning the first time the
# legacy branch is taken (once per process).
_AGMSG_STATE_ROOT_WARNED=

_agmsg_has_persistent_state() {
  local root="$1"
  [ -f "$root/db/messages.db" ] && return 0
  [ -f "$root/db/config.yaml" ] && return 0
  [ -n "$(find "$root/teams" -mindepth 2 -maxdepth 2 -name config.json -print -quit 2>/dev/null)" ] && return 0
  return 1
}

agmsg_state_root() {
  if [ -n "${AGMSG_STATE_HOME:-}" ]; then
    printf '%s\n' "${AGMSG_STATE_HOME%/}"
    return
  fi

  local xdg_root="${XDG_STATE_HOME:-$HOME/.local/state}/agmsg"
  local skill_dir
  skill_dir="$(_agmsg_skill_dir)" || return 1
  local legacy_has_state=0 xdg_has_state=0
  _agmsg_has_persistent_state "$skill_dir" && legacy_has_state=1
  _agmsg_has_persistent_state "$xdg_root" && xdg_has_state=1

  if [ "$legacy_has_state" -eq 1 ] && [ "$xdg_has_state" -eq 1 ]; then
    echo "Error: agmsg persistent state がlegacy ($skill_dir) とXDG ($xdg_root) の両方にあります。自動選択せず、migration/mergeを完了してください。" >&2
    return 1
  fi

  if [ "$legacy_has_state" -eq 1 ]; then
    if [ -z "$_AGMSG_STATE_ROOT_WARNED" ]; then
      _AGMSG_STATE_ROOT_WARNED=1
      echo "agmsg: legacy state を使用中 ($skill_dir)。migration script 実行後に XDG state ($xdg_root) へ移行されます。" >&2
    fi
    printf '%s\n' "$skill_dir"
    return
  fi

  printf '%s\n' "$xdg_root"
}

# Echo the directory that holds (or will hold) the message store.
# AGMSG_STORAGE_PATH is a DB-directory-only override — it does not affect
# agmsg_run_dir/agmsg_teams_dir below.
agmsg_storage_dir() {
  if [ -n "${AGMSG_STORAGE_PATH:-}" ]; then
    # Strip a single trailing slash for a stable join with the filename.
    printf '%s\n' "${AGMSG_STORAGE_PATH%/}"
    return
  fi
  local root
  root="$(agmsg_state_root)" || return 1
  printf '%s/db\n' "$root"
}

# Echo the run/ directory (pidfiles, locks, watermarks, readiness sentinels).
agmsg_run_dir() {
  local root
  root="$(agmsg_state_root)" || return 1
  printf '%s/run\n' "$root"
}

# Echo the teams/ directory (per-team config.json).
agmsg_teams_dir() {
  local root
  root="$(agmsg_state_root)" || return 1
  printf '%s/teams\n' "$root"
}

# Echo the full path to messages.db.
agmsg_db_path() {
  local storage_dir
  storage_dir="$(agmsg_storage_dir)" || return 1
  printf '%s/messages.db\n' "$storage_dir"
}

# Run sqlite3 against the message store with a busy_timeout, so a writer that
# finds the DB locked WAITS for it instead of failing immediately with
# SQLITE_BUSY. WAL (set at init) lets readers and a single writer coexist, but
# concurrent writers still serialize; with the default busy_timeout=0 a leader
# fanning a job out to N members would lose all but one write — and silently,
# since the failed sends just exit non-zero. All DB-backed call sites go through
# this wrapper. In-memory JSON parsing (`sqlite3 :memory:`) does not need it —
# it has no file lock to contend for. Override the timeout via
# $AGMSG_BUSY_TIMEOUT (milliseconds). See #114.
#
# Uses the `.timeout` dot-command rather than `PRAGMA busy_timeout=N`: the
# PRAGMA returns its value as a row, which sqlite3 would print to stdout and
# corrupt every SELECT's output (and the watch stream). `.timeout` sets the
# same busy timeout silently.
# sqlite3 >= 3.50 renders control bytes in CLI output using caret notation —
# the char(31) record separator becomes the two literal chars "^_", and a CR
# becomes "^M". That breaks the `IFS=$'\x1f' read` field splitting in
# inbox/check-inbox/history and the monitor watch stream (#102), the same
# sqlite3 >= 3.50 escaping behaviour behind #143. `-escape off` restores the
# raw bytes. Older sqlite3 (< 3.50) doesn't know the option (and emits raw bytes
# anyway), so probe once and only pass the flag when the build accepts it.
_AGMSG_ESCAPE_FLAG=
_AGMSG_ESCAPE_PROBED=
_agmsg_escape_flag() {
  if [ -z "$_AGMSG_ESCAPE_PROBED" ]; then
    _AGMSG_ESCAPE_PROBED=1
    if sqlite3 -escape off :memory: "SELECT 1;" >/dev/null 2>&1; then
      _AGMSG_ESCAPE_FLAG="-escape off"
    fi
  fi
  printf '%s' "$_AGMSG_ESCAPE_FLAG"
}

agmsg_sqlite() {
  # shellcheck disable=SC2046  # intentional split: "-escape off" → two args, or none
  sqlite3 $(_agmsg_escape_flag) -cmd ".timeout ${AGMSG_BUSY_TIMEOUT:-5000}" "$@"
}
