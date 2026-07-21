#!/usr/bin/env bash
# test-agmsg-state-home.sh — shared/skills/agmsg/scripts/lib/storage.sh の
# state root 解決(XDG state ディレクトリ化 + legacy 互換)を検証する standalone テスト。
# サンドボックス HOME で env を隔離して行う。live の ~/.agents や実 state には一切触れない。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_STORAGE_SH="$SCRIPT_DIR/../shared/skills/agmsg/scripts/lib/storage.sh"
[ -f "$REAL_STORAGE_SH" ] || { echo "FAIL: storage.sh not found at $REAL_STORAGE_SH" >&2; exit 1; }

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

# 実 storage.sh を隔離した疑似 skill ツリーへコピーする。BASH_SOURCE 経由の skill_dir
# 解決(scripts/lib/storage.sh の親の親)がサンドボックス内で完結するようにするため —
# 実リポジトリのファイルを直接 source すると、実 skill_dir 配下の db/messages.db
# (live state)を legacy 判定に巻き込んでしまう。
SKILL_COPY="$SANDBOX/skill"
mkdir -p "$SKILL_COPY/scripts/lib"
cp "$REAL_STORAGE_SH" "$SKILL_COPY/scripts/lib/storage.sh"
STORAGE_SH="$SKILL_COPY/scripts/lib/storage.sh"

FAILURES=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (expected=$expected actual=$actual)" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (needle not found: $needle)" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# --- 1. デフォルトは ${XDG_STATE_HOME:-$HOME/.local/state}/agmsg ---
HOME1="$SANDBOX/home1"
mkdir -p "$HOME1"
out1="$(
  unset AGMSG_STATE_HOME AGMSG_STORAGE_PATH XDG_STATE_HOME SKILL_DIR
  export HOME="$HOME1"
  # shellcheck disable=SC1090
  source "$STORAGE_SH"
  agmsg_state_root
)"
assert_eq "デフォルトは ~/.local/state/agmsg に解決される" "$HOME1/.local/state/agmsg" "$out1"

# --- 2. XDG_STATE_HOME 設定時はそちらへ解決される ---
HOME2="$SANDBOX/home2"
XDG2="$SANDBOX/xdg2"
mkdir -p "$HOME2"
out2="$(
  unset AGMSG_STATE_HOME AGMSG_STORAGE_PATH SKILL_DIR
  export HOME="$HOME2"
  export XDG_STATE_HOME="$XDG2"
  # shellcheck disable=SC1090
  source "$STORAGE_SH"
  agmsg_state_root
)"
assert_eq "XDG_STATE_HOME 設定時はそちらへ解決される" "$XDG2/agmsg" "$out2"

# --- 3. AGMSG_STATE_HOME が最優先(AGMSG_STORAGE_PATH を除く) ---
HOME3="$SANDBOX/home3"
XDG3="$SANDBOX/xdg3"
STATE3="$SANDBOX/state3"
mkdir -p "$HOME3"
out3="$(
  unset AGMSG_STORAGE_PATH SKILL_DIR
  export HOME="$HOME3"
  export XDG_STATE_HOME="$XDG3"
  export AGMSG_STATE_HOME="$STATE3"
  # shellcheck disable=SC1090
  source "$STORAGE_SH"
  agmsg_state_root
)"
assert_eq "AGMSG_STATE_HOME は XDG_STATE_HOME より優先される" "$STATE3" "$out3"

# --- 4. AGMSG_STORAGE_PATH は DB ディレクトリだけを上書きする ---
HOME4="$SANDBOX/home4"
DBOVERRIDE4="$SANDBOX/custom-db-dir"
mkdir -p "$HOME4"
db4="$(
  unset AGMSG_STATE_HOME XDG_STATE_HOME SKILL_DIR
  export HOME="$HOME4"
  export AGMSG_STORAGE_PATH="$DBOVERRIDE4"
  # shellcheck disable=SC1090
  source "$STORAGE_SH"
  agmsg_storage_dir
)"
run4="$(
  unset AGMSG_STATE_HOME XDG_STATE_HOME SKILL_DIR
  export HOME="$HOME4"
  export AGMSG_STORAGE_PATH="$DBOVERRIDE4"
  # shellcheck disable=SC1090
  source "$STORAGE_SH"
  agmsg_run_dir
)"
teams4="$(
  unset AGMSG_STATE_HOME XDG_STATE_HOME SKILL_DIR
  export HOME="$HOME4"
  export AGMSG_STORAGE_PATH="$DBOVERRIDE4"
  # shellcheck disable=SC1090
  source "$STORAGE_SH"
  agmsg_teams_dir
)"
assert_eq "AGMSG_STORAGE_PATH は DB dir を上書きする" "$DBOVERRIDE4" "$db4"
assert_eq "AGMSG_STORAGE_PATH 設定時も run dir は state root のまま" "$HOME4/.local/state/agmsg/run" "$run4"
assert_eq "AGMSG_STORAGE_PATH 設定時も teams dir は state root のまま" "$HOME4/.local/state/agmsg/teams" "$teams4"

# --- 5. legacy 検出: skill dir 内に legacy db があり XDG 側に無ければ legacy が選ばれ、警告が出る ---
HOME5="$SANDBOX/home5"
mkdir -p "$HOME5" "$SKILL_COPY/db"
: > "$SKILL_COPY/db/messages.db"
{
  out5="$(
    unset AGMSG_STATE_HOME AGMSG_STORAGE_PATH XDG_STATE_HOME SKILL_DIR
    export HOME="$HOME5"
    # shellcheck disable=SC1090
    source "$STORAGE_SH"
    agmsg_state_root
  )"
} 2> "$SANDBOX/legacy.stderr"
err5="$(cat "$SANDBOX/legacy.stderr")"
assert_eq "legacy db が存在すれば skill dir が state root として選ばれる" "$SKILL_COPY" "$out5"
assert_contains "legacy 使用時に stderr へ警告が出る" "$err5" "legacy"

# 後始末: 以降のテストの legacy 検出に影響しないよう legacy db を消す。
rm -f "$SKILL_COPY/db/messages.db"

# --- 6. legacy teams-only/config-onlyもpersistent stateとして検出する ---
HOME6A="$SANDBOX/home6a"
mkdir -p "$HOME6A" "$SKILL_COPY/teams/team-a"
echo '{"name":"team-a","agents":{}}' > "$SKILL_COPY/teams/team-a/config.json"
{
  out6a="$(
    unset AGMSG_STATE_HOME AGMSG_STORAGE_PATH XDG_STATE_HOME SKILL_DIR
    export HOME="$HOME6A"
    # shellcheck disable=SC1090
    source "$STORAGE_SH"
    agmsg_state_root
  )"
} 2> "$SANDBOX/legacy-teams.stderr"
assert_eq "legacy teams-only stateでも skill dirが選ばれる" "$SKILL_COPY" "$out6a"
rm -rf "$SKILL_COPY/teams"

HOME6B="$SANDBOX/home6b"
mkdir -p "$HOME6B" "$SKILL_COPY/db"
echo 'hook.check_interval: 30' > "$SKILL_COPY/db/config.yaml"
{
  out6b="$(
    unset AGMSG_STATE_HOME AGMSG_STORAGE_PATH XDG_STATE_HOME SKILL_DIR
    export HOME="$HOME6B"
    # shellcheck disable=SC1090
    source "$STORAGE_SH"
    agmsg_state_root
  )"
} 2> "$SANDBOX/legacy-config.stderr"
assert_eq "legacy config-only stateでも skill dirが選ばれる" "$SKILL_COPY" "$out6b"
rm -f "$SKILL_COPY/db/config.yaml"

# --- 7. legacyとXDGの両方にpersistent stateがあれば曖昧さを隠さず失敗する ---
HOME7="$SANDBOX/home7"
XDG7="$SANDBOX/xdg7"
mkdir -p "$HOME7" "$SKILL_COPY/teams/team-a" "$XDG7/agmsg/db"
echo '{"name":"team-a","agents":{}}' > "$SKILL_COPY/teams/team-a/config.json"
: > "$XDG7/agmsg/db/messages.db"
rc7=0
{
  out7="$(
    unset AGMSG_STATE_HOME AGMSG_STORAGE_PATH SKILL_DIR
    export HOME="$HOME7" XDG_STATE_HOME="$XDG7"
    # shellcheck disable=SC1090
    source "$STORAGE_SH"
    agmsg_state_root
  )"
} 2> "$SANDBOX/split-state.stderr" || rc7=$?
assert_eq "legacy/XDG split stateは非ゼロ終了" "1" "$rc7"
assert_contains "split stateは両方のpathを示す" "$(cat "$SANDBOX/split-state.stderr")" "両方"
assert_eq "split state時はpathを返さない" "" "$out7"
rc7_run=0
{
  out7_run="$(
    unset AGMSG_STATE_HOME AGMSG_STORAGE_PATH SKILL_DIR
    export HOME="$HOME7" XDG_STATE_HOME="$XDG7"
    # shellcheck disable=SC1090
    source "$STORAGE_SH"
    agmsg_run_dir
  )"
} 2> "$SANDBOX/split-run.stderr" || rc7_run=$?
assert_eq "split stateの失敗はrun dir resolverでも伝播する" "1" "$rc7_run"
assert_eq "split state時にrun dirの偽pathを返さない" "" "$out7_run"
rm -rf "$SKILL_COPY/teams" "$XDG7"

# --- 8. round-trip: 解決したパスにファイルを書き、再解決して同じ内容が読める ---
HOME6="$SANDBOX/home6"
mkdir -p "$HOME6"
if command -v sqlite3 >/dev/null 2>&1; then
  (
    unset AGMSG_STATE_HOME AGMSG_STORAGE_PATH XDG_STATE_HOME SKILL_DIR
    export HOME="$HOME6"
    # shellcheck disable=SC1090
    source "$STORAGE_SH"
    db="$(agmsg_db_path)"
    mkdir -p "$(dirname "$db")"
    agmsg_sqlite "$db" "CREATE TABLE t (v TEXT); INSERT INTO t VALUES ('roundtrip');"
  )
  roundtrip_val="$(
    unset AGMSG_STATE_HOME AGMSG_STORAGE_PATH XDG_STATE_HOME SKILL_DIR
    export HOME="$HOME6"
    # shellcheck disable=SC1090
    source "$STORAGE_SH"
    db="$(agmsg_db_path)"
    agmsg_sqlite "$db" "SELECT v FROM t;"
  )"
  assert_eq "sqlite3 round-trip: 書き込んだ値が再解決後に読める" "roundtrip" "$roundtrip_val"
else
  (
    unset AGMSG_STATE_HOME AGMSG_STORAGE_PATH XDG_STATE_HOME SKILL_DIR
    export HOME="$HOME6"
    # shellcheck disable=SC1090
    source "$STORAGE_SH"
    db="$(agmsg_db_path)"
    mkdir -p "$(dirname "$db")"
    printf 'roundtrip' > "$db"
  )
  roundtrip_val="$(
    unset AGMSG_STATE_HOME AGMSG_STORAGE_PATH XDG_STATE_HOME SKILL_DIR
    export HOME="$HOME6"
    # shellcheck disable=SC1090
    source "$STORAGE_SH"
    db="$(agmsg_db_path)"
    cat "$db"
  )"
  assert_eq "file round-trip: 書き込んだ値が再解決後に読める(sqlite3 なし)" "roundtrip" "$roundtrip_val"
fi

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
