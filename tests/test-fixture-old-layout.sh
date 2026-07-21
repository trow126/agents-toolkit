#!/usr/bin/env bash
# test-fixture-old-layout.sh — tests/lib/fixture-old-layout.sh のstandaloneテスト
# fixtureが構築でき、symlinkが正しく解決され、tracked/untrackedがgitで判定できることを検証する。
# 実$HOMEには一切触れない。失敗時は非ゼロexitで終了する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/fixture-old-layout.sh
source "$SCRIPT_DIR/lib/fixture-old-layout.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAILURES=0

assert_true() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_false() {
  local desc="$1"
  shift
  if ! "$@" >/dev/null 2>&1; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (expected=$expected actual=$actual)" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

build_old_layout "$SANDBOX"

REPO="$SANDBOX/agents-toolkit"

# --- fixtureが構築できる ---
assert_true "repo agents-toolkit/claude が存在する" test -d "$REPO/claude"
assert_true "repo agents-toolkit/codex が存在する" test -d "$REPO/codex"
assert_true "repo agents-toolkit/shared が存在する" test -d "$REPO/shared"
assert_true "repo が git init 済み" test -d "$REPO/.git"

# --- symlinkが正しく解決される ---
assert_true "\$HOME/.claude が symlink" test -L "$SANDBOX/home/.claude"
assert_true "\$HOME/.codex が symlink" test -L "$SANDBOX/home/.codex"
assert_true "\$HOME/.agents が symlink" test -L "$SANDBOX/home/.agents"
assert_eq "\$HOME/.claude の解決先" "$REPO/claude" "$(readlink -f "$SANDBOX/home/.claude")"
assert_eq "\$HOME/.codex の解決先" "$REPO/codex" "$(readlink -f "$SANDBOX/home/.codex")"
assert_eq "\$HOME/.agents の解決先" "$REPO/shared" "$(readlink -f "$SANDBOX/home/.agents")"

# --- tracked/untrackedがgitで判定できる ---
assert_true "claude/CLAUDE.md は tracked" \
  git -C "$REPO" ls-files --error-unmatch claude/CLAUDE.md
assert_true "claude/rules/sample.md は tracked" \
  git -C "$REPO" ls-files --error-unmatch claude/rules/sample.md
assert_true "codex/AGENTS.md は tracked" \
  git -C "$REPO" ls-files --error-unmatch codex/AGENTS.md
assert_true "codex/skills/sample-skill/SKILL.md は tracked" \
  git -C "$REPO" ls-files --error-unmatch codex/skills/sample-skill/SKILL.md
assert_true "shared/rules/sample.md は tracked" \
  git -C "$REPO" ls-files --error-unmatch shared/rules/sample.md

assert_false "claude/.credentials.json は untracked" \
  git -C "$REPO" ls-files --error-unmatch claude/.credentials.json
assert_false "claude/projects/p1/x.jsonl は untracked" \
  git -C "$REPO" ls-files --error-unmatch claude/projects/p1/x.jsonl
assert_false "codex/auth.json は untracked" \
  git -C "$REPO" ls-files --error-unmatch codex/auth.json
assert_false "codex/state.sqlite は untracked" \
  git -C "$REPO" ls-files --error-unmatch codex/state.sqlite
assert_false "shared/skills/agmsg/db/messages.db は untracked" \
  git -C "$REPO" ls-files --error-unmatch shared/skills/agmsg/db/messages.db

# untracked疑似runtimeの内容がダミーであることの確認(secret値を書かないfixtureの検証)
assert_eq "claude/.credentials.json の内容はダミー" "FAKE" "$(cat "$REPO/claude/.credentials.json")"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
