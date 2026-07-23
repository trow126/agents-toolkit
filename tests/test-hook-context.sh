#!/usr/bin/env bash
# Bounded SessionStart/PostCompact systemMessage output and metric coverage.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
ok(){ echo "ok: $1"; }
ng(){ echo "FAIL: $1" >&2; FAILURES=$((FAILURES+1)); }

REPO="$SANDBOX/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b "feature/$(printf 'x%.0s' {1..180})"
git -C "$REPO" config user.email fixture@example.invalid
git -C "$REPO" config user.name Fixture
git -C "$REPO" config commit.gpgsign false
printf 'base\n' > "$REPO/$(printf 'long-file-%.0s' {1..12}).txt"
git -C "$REPO" add .
git -C "$REPO" commit -q -m "$(printf 'long-subject-%.0s' {1..40})"
printf 'change\n' >> "$REPO/$(find "$REPO" -maxdepth 1 -type f -printf '%f\n' | head -1)"

for hook in session-init-hook.sh post-compact-hook.sh; do
  if [[ "$hook" == post-compact-hook.sh ]]; then git -C "$REPO" add .; fi
  out="$(cd "$REPO" && "$REPO_ROOT/claude/hooks/$hook")"
  bytes="$(printf '%s\n' "$out" | wc -c)"
  if python3 -c 'import json,sys; d=json.load(sys.stdin); assert isinstance(d.get("systemMessage"),str)' <<< "$out"; then ok "$hook emits valid systemMessage JSON"; else ng "$hook JSON"; fi
  if [[ "$bytes" -le 512 ]]; then ok "$hook output is <=512 bytes ($bytes)"; else ng "$hook exceeded 512 bytes ($bytes)"; fi
done

NON_GIT="$SANDBOX/non-git"
for _ in {1..40}; do NON_GIT="$NON_GIT/cwd-segment"; done
mkdir -p "$NON_GIT"
out="$(cd "$NON_GIT" && "$REPO_ROOT/claude/hooks/session-init-hook.sh")"
bytes="$(printf '%s\n' "$out" | wc -c)"
if [[ "$bytes" -le 512 ]]; then ok "non-git CWD output is bounded"; else ng "non-git CWD output exceeded bound"; fi

metrics="$(python3 "$REPO_ROOT/scripts/measure-hook-injection.py" "$REPO_ROOT")"
for expected in \
  'session_start_system_message_max_bytes: 512' \
  'post_compact_system_message_max_bytes: 512'; do
  if grep -qxF "$expected" <<< "$metrics"; then ok "metrics reports $expected"; else ng "missing metric $expected"; fi
done
for key in session_start_system_message_typical_bytes post_compact_system_message_typical_bytes; do
  value="$(awk -F': ' -v k="$key" '$1==k{print $2}' <<< "$metrics")"
  if [[ "$value" =~ ^[1-9][0-9]*$ && "$value" -le 512 ]]; then ok "$key is numeric and bounded ($value)"; else ng "$key invalid ($value)"; fi
done

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then echo "PASS: all assertions succeeded"; exit 0; fi
echo "FAIL: $FAILURES assertion(s) failed" >&2; exit 1
