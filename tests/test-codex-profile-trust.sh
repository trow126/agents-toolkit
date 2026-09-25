#!/usr/bin/env bash
# K11: scripts/codex-profile-trust.py moves the hook and project trust that Codex writes into a
# toolkit profile over to $CODEX_HOME/config.toml and restores the profile from git HEAD.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOL="$REPO_ROOT/scripts/codex-profile-trust.py"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
ok() { echo "ok: $1"; }
ng() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}
export PYTHONDONTWRITEBYTECODE=1

REPO="$SANDBOX/repo"
HOME_CODEX="$SANDBOX/codex-home"
PROFILE="codex/profiles/toolkit-implementer.config.toml"
mkdir -p "$REPO/codex/profiles" "$HOME_CODEX"
cp "$REPO_ROOT/$PROFILE" "$REPO/$PROFILE"
git -C "$REPO" init -q -b main
git -C "$REPO" -c user.email=fixture@example.invalid -c user.name=Fixture add -A
git -C "$REPO" -c user.email=fixture@example.invalid -c user.name=Fixture -c commit.gpgsign=false commit -q -m base
printf 'model = "gpt-6-astra"\n\n[projects."/work/a"]\ntrust_level = "trusted"\n' > "$HOME_CODEX/config.toml"

trust() { # <hash> — what Codex appends after the owner trusts the hook in `codex -p toolkit-implementer`
  cat >> "$REPO/$PROFILE" <<EOF

[hooks.state]

[hooks.state."/home/u/.codex/toolkit-implementer.config.toml:post_tool_use:0:0"]
trusted_hash = "sha256:$1"

[projects."/home/u/agents-toolkit"]
trust_level = "trusted"

[tui.model_availability_nux]
gpt-6-astra = 2
EOF
}
RC=0; OUT=""
run() { RC=0; OUT="$(python3 "$TOOL" --repo "$REPO" --codex-home "$HOME_CODEX" "$@" 2>&1)" || RC=$?; }
expect() { if [[ "$RC" -eq "$2" && "$OUT" == *"$3"* ]]; then ok "$1"; else ng "$1 (rc=$RC): $OUT"; fi; }
toml() { python3 -c 'import sys,tomllib,json; print(json.dumps(tomllib.load(open(sys.argv[1],"rb")), sort_keys=True))' "$1"; }

run --check
expect "clean profile passes --check" 0 "carry no local Codex state"

trust aaaa
run --check
expect "--check reports the local state" 1 "carries local Codex state: hooks.state (1), projects (1), tui"
[[ -n "$(git -C "$REPO" status --porcelain)" ]] && ok "--check changes nothing" || ng "--check restored the profile"

run
expect "moves the trust and restores the profile" 0 "RESTORED: $PROFILE"
[[ -z "$(git -C "$REPO" status --porcelain)" ]] && ok "profile is back to HEAD" || ng "profile still dirty"
state="$(toml "$HOME_CODEX/config.toml")"
if jq -e '.hooks.state["/home/u/.codex/toolkit-implementer.config.toml:post_tool_use:0:0"].trusted_hash == "sha256:aaaa"
  and .projects["/home/u/agents-toolkit"].trust_level == "trusted" and .projects["/work/a"].trust_level == "trusted"
  and .model == "gpt-6-astra" and (has("tui") | not)' <<< "$state" >/dev/null; then
  ok "config.toml gets the hook and project trust, keeps its own keys, and drops the UI state"
else
  ng "config.toml content: $state"
fi

run
expect "second run is a no-op" 0 "carry no local Codex state"

trust bbbb
run
expect "re-trust after a hook change" 0 "MOVED"
if [[ "$(grep -c 'toolkit-implementer.config.toml:post_tool_use:0:0' "$HOME_CODEX/config.toml")" -eq 1 ]] &&
  jq -e '.hooks.state["/home/u/.codex/toolkit-implementer.config.toml:post_tool_use:0:0"].trusted_hash == "sha256:bbbb"' <<< "$(toml "$HOME_CODEX/config.toml")" >/dev/null; then
  ok "a new trust hash replaces the old table"
else
  ng "hook trust table duplicated or stale: $(cat "$HOME_CODEX/config.toml")"
fi

sed -i 's/You are the implementer/You are an implementer/' "$REPO/$PROFILE"
trust cccc
cp "$HOME_CODEX/config.toml" "$SANDBOX/before.toml"
run
expect "other local edits are left alone" 1 "has local edits other than Codex state"
cmp -s "$SANDBOX/before.toml" "$HOME_CODEX/config.toml" && ok "config.toml untouched on refusal" || ng "config.toml changed on refusal"

echo
if [[ "$FAILURES" -eq 0 ]]; then
  echo "PASS: all assertions succeeded"
  exit 0
else
  echo "FAIL: $FAILURES assertion(s) failed" >&2
  exit 1
fi
