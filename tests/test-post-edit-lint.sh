#!/usr/bin/env bash
# test-post-edit-lint.sh — PostToolUse Edit/Write lint feedback の fixture tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK="$REPO_ROOT/claude/hooks/post-edit-lint-hook.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

STDOUT_FILE="$SANDBOX/stdout"
STDERR_FILE="$SANDBOX/stderr"
FAILURES=0
CASE_RC=0

ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

run_raw() {
  local input="$1"
  : > "$STDOUT_FILE"
  : > "$STDERR_FILE"
  set +e
  printf '%s' "$input" | "$HOOK" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  CASE_RC=${PIPESTATUS[1]}
  set -e
}

run_hook() {
  local tool_name="$1" file_path="$2" input
  input="$(jq -n --arg tool "$tool_name" --arg path "$file_path" '{
    hook_event_name: "PostToolUse",
    tool_name: $tool,
    tool_input: {file_path: $path}
  }')"
  run_raw "$input"
}

assert_stdout_empty() {
  local desc="$1"
  if [[ ! -s "$STDOUT_FILE" ]]; then
    ok "$desc: stdout は空"
  else
    ng "$desc: stdout に出力された: $(<"$STDOUT_FILE")"
  fi
}

expect_violation() {
  local desc="$1" tool_name="$2" file_path="$3" expected="$4"
  run_hook "$tool_name" "$file_path"
  if [[ "$CASE_RC" -eq 2 ]]; then
    ok "$desc: exit 2"
  else
    ng "$desc: expected exit 2, got $CASE_RC"
  fi
  if grep -Fq "$expected" "$STDERR_FILE"; then
    ok "$desc: 違反理由を表示"
  else
    ng "$desc: stderr に期待した違反理由がない"
  fi
  if grep -Fq '意図的な場合はレポートにその理由を書くこと。' "$STDERR_FILE"; then
    ok "$desc: 意図的な場合の案内を表示"
  else
    ng "$desc: 意図的な場合の案内がない"
  fi
  assert_stdout_empty "$desc"
}

expect_pass() {
  local desc="$1" tool_name="$2" file_path="$3"
  run_hook "$tool_name" "$file_path"
  if [[ "$CASE_RC" -eq 0 ]]; then
    ok "$desc: exit 0"
  else
    ng "$desc: expected exit 0, got $CASE_RC"
  fi
  if [[ ! -s "$STDERR_FILE" ]]; then
    ok "$desc: stderr は空"
  else
    ng "$desc: stderr に出力された: $(<"$STDERR_FILE")"
  fi
  assert_stdout_empty "$desc"
}

# ---- H-001: Markdown の見出し・テーブル・fenced code block ----
cat > "$SANDBOX/broken-heading.md" <<'MD'
本文
# 見出し

本文
MD
expect_violation \
  "空行のない Markdown 見出し" Edit "$SANDBOX/broken-heading.md" \
  "post-edit-lint: $SANDBOX/broken-heading.md:2: Markdown 見出しの前に空行がありません — 見出しの直前に空行を追加する"

cat > "$SANDBOX/broken-table.md" <<'MD'
本文
| key | value |
|---|---|

本文
MD
expect_violation \
  "空行のない Markdown テーブル" Write "$SANDBOX/broken-table.md" \
  "post-edit-lint: $SANDBOX/broken-table.md:2: Markdown テーブルの前に空行がありません — テーブルの直前に空行を追加する"

cat > "$SANDBOX/broken-fence.md" <<'MD'
本文
```text
sample
```

本文
MD
expect_violation \
  "空行のない Markdown コードブロック" Edit "$SANDBOX/broken-fence.md" \
  "post-edit-lint: $SANDBOX/broken-fence.md:2: Markdown コードブロックの前に空行がありません — コードブロックの直前に空行を追加する"

cat > "$SANDBOX/clean.md" <<'MD'
---
title: fixture
# front matter 内は無視
| front matter 内も無視 |
---
# 見出し

本文

| key | value |
|---|---|

```text
# code block 内は無視
| code block 内も無視 |
```

本文
MD
expect_pass "clean Markdown と除外領域" Edit "$SANDBOX/clean.md"

# ---- H-002: Python syntax ----
cat > "$SANDBOX/broken.py" <<'PY'
def broken(:
    pass
PY
expect_violation \
  "Python SyntaxError" Edit "$SANDBOX/broken.py" \
  "post-edit-lint: $SANDBOX/broken.py:1: Python 構文エラー: invalid syntax — 構文を修正して ast.parse が成功する状態にする"

cat > "$SANDBOX/valid.py" <<'PY'
def valid() -> int:
    return 1
PY
expect_pass "valid Python" Write "$SANDBOX/valid.py"

# ---- H-003: Claude settings permission syntax ----
mkdir -p "$SANDBOX/project/.claude"
cat > "$SANDBOX/project/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "deny": [
      "Bash:*"
    ]
  }
}
JSON
expect_violation \
  "deny の Tool:*" Edit "$SANDBOX/project/.claude/settings.json" \
  "post-edit-lint: $SANDBOX/project/.claude/settings.json:4: permissions.deny の \"Bash:*\" は無効な Tool:* 構文です — \":*\" を外して \"Bash\" の形式にする"

cat > "$SANDBOX/project/.claude/settings.local.json" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(npm run test*)"
    ]
  }
}
JSON
expect_violation \
  "allow の no-space wildcard" Edit "$SANDBOX/project/.claude/settings.local.json" \
  "post-edit-lint: $SANDBOX/project/.claude/settings.local.json:4: permissions.allow の \"Bash(npm run test*)\" は no-space wildcard です — word boundary のある trailing space-star に直す"

cat > "$SANDBOX/project/.claude/managed-settings.json" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(git *)"
    ]
  }
}
JSON
expect_pass "legacy-equivalent と canonical wildcard" Edit "$SANDBOX/project/.claude/managed-settings.json"

cat > "$SANDBOX/project/.claude/managed-settings.json" <<'JSON'
{
  "permissions": {
    "allow": [
      "Edit(**)",
      "Read(**)",
      "Read(src/**)"
    ]
  }
}
JSON
expect_pass "file tool の path glob（Edit(**)・Read(**)）は no-space wildcard とみなさない" Edit "$SANDBOX/project/.claude/managed-settings.json"

# ---- Codex apply_patch PostToolUse mode（toolkit-implementer profile の inline hook）----
LINT_PY="$REPO_ROOT/claude/hooks/lib/post_edit_lint.py"
mkdir -p "$SANDBOX/codex"
printf '# Title\nno blank line\n' > "$SANDBOX/codex/bad.md"
printf '# Title\n\nfine\n' > "$SANDBOX/codex/good.md"
patch_input() {
  jq -n --arg cwd "$SANDBOX/codex" --arg cmd "$1" \
    '{hook_event_name: "PostToolUse", tool_name: "apply_patch", cwd: $cwd, tool_input: {command: $cmd}}'
}
rc=0; out="$(patch_input $'*** Begin Patch\n*** Update File: bad.md\n@@\n-x\n+y\n*** End Patch' | python3 "$LINT_PY" --apply-patch-hook 2>&1)" || rc=$?
if [[ "$rc" -eq 2 && "$out" == *"post-edit-lint: bad.md:1: Markdown 見出しの後に空行がありません"* ]]; then
  ok "apply_patch hook: 違反は exit 2 と stderr で返す"
else
  ng "apply_patch hook: expected exit 2 with violation, got $rc: $out"
fi
rc=0; out="$(patch_input $'*** Begin Patch\n*** Add File: good.md\n+# Title\n*** End Patch' | python3 "$LINT_PY" --apply-patch-hook 2>&1)" || rc=$?
if [[ "$rc" -eq 0 && -z "$out" ]]; then ok "apply_patch hook: 違反なしは exit 0"; else ng "apply_patch hook: clean file got $rc: $out"; fi
rc=0; out="$(printf 'not-json' | python3 "$LINT_PY" --apply-patch-hook 2>&1)" || rc=$?
if [[ "$rc" -eq 0 ]]; then ok "apply_patch hook: 不正な入力は fail-open"; else ng "apply_patch hook: malformed input got $rc"; fi

# ---- routing と fail-open internal errors ----
printf 'not linted\n' > "$SANDBOX/notes.txt"
expect_pass "対象外 extension" Edit "$SANDBOX/notes.txt"
expect_pass "Read tool" Read "$SANDBOX/broken-heading.md"

run_raw '{not-json'
if [[ "$CASE_RC" -eq 0 && ! -s "$STDERR_FILE" ]]; then
  ok "非 JSON stdin は silent exit 0"
else
  ng "非 JSON stdin: expected silent exit 0, got $CASE_RC"
fi
assert_stdout_empty "非 JSON stdin"

expect_pass "missing file" Edit "$SANDBOX/deleted.md"

MINBIN="$SANDBOX/minbin"
mkdir -p "$MINBIN"
ln -s "$(command -v jq)" "$MINBIN/jq"
ln -s "$(command -v cat)" "$MINBIN/cat"
missing_python_input="$(jq -n --arg path "$SANDBOX/broken-heading.md" '{
  tool_name: "Edit", tool_input: {file_path: $path}
}')"
: > "$STDOUT_FILE"
: > "$STDERR_FILE"
set +e
printf '%s' "$missing_python_input" \
  | PATH="$MINBIN" "$HOOK" >"$STDOUT_FILE" 2>"$STDERR_FILE"
CASE_RC=${PIPESTATUS[1]}
set -e
if [[ "$CASE_RC" -eq 0 && ! -s "$STDERR_FILE" ]]; then
  ok "python3 欠落は silent exit 0"
else
  ng "python3 欠落: expected silent exit 0, got $CASE_RC"
fi
assert_stdout_empty "python3 欠落"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
fi
echo "FAIL: $FAILURES assertion(s) failed" >&2
exit 1
