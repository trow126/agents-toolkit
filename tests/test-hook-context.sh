#!/usr/bin/env bash
# Phase 7: no managed hook injects per-prompt text or emits systemMessage-only JSON at session
# start or after compaction (D3, appendix C Phase 7), and the metrics report zero injection.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANAGED="$REPO_ROOT/claude/managed-settings.json"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
ok(){ echo "ok: $1"; }
ng(){ echo "FAIL: $1" >&2; FAILURES=$((FAILURES+1)); }

events="$(jq -r '.hooks | keys[]' "$MANAGED" | paste -sd ' ' -)"
if ! jq -e '.hooks | has("UserPromptSubmit") or has("PostCompact")' "$MANAGED" >/dev/null; then
  ok "UserPromptSubmit と PostCompact を登録しない ($events)"
else
  ng "UserPromptSubmit / PostCompact が登録されている ($events)"
fi
for script in prompt-submit-hook.sh session-init-hook.sh post-compact-hook.sh lib/emit_system_message.py; do
  if [[ ! -e "$REPO_ROOT/claude/hooks/$script" ]] && ! grep -qF "$script" "$MANAGED"; then
    ok "$script は削除され、登録も無い"
  else
    ng "$script が残っている"
  fi
done

# Every remaining SessionStart hook is silent outside its integration (no systemMessage-only JSON).
mapfile -t session_hooks < <(jq -r '.hooks.SessionStart[]?.hooks[]?.command' "$MANAGED")
for command in "${session_hooks[@]}"; do
  expanded="${command//\~/$REPO_ROOT/claude}"
  expanded="${expanded//\$HOME\/.claude/$REPO_ROOT/claude}"
  out="$(printf '{"hook_event_name":"SessionStart","source":"startup"}' | env -u HERDR_ENV HOME="$SANDBOX" bash -c "$expanded" 2>/dev/null || true)"
  if [[ -z "$out" ]] || ! jq -e 'type == "object" and has("systemMessage") and (keys - ["systemMessage"] | length == 0)' <<< "$out" >/dev/null 2>&1; then
    ok "SessionStart hook は systemMessage だけの JSON を出さない: $command"
  else
    ng "SessionStart hook が systemMessage だけの JSON を出した: $command"
  fi
done

metrics="$(python3 "$REPO_ROOT/scripts/measure-hook-injection.py" "$REPO_ROOT")"
for key in session_start_system_message_typical_bytes session_start_system_message_max_bytes \
  post_compact_system_message_typical_bytes post_compact_system_message_max_bytes \
  user_prompt_submit_injection_typical_bytes user_prompt_submit_injection_max_bytes; do
  if grep -qxF "$key: 0" <<< "$metrics"; then ok "metrics reports $key: 0"; else ng "metric $key is not 0"; fi
done

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then echo "PASS: all assertions succeeded"; exit 0; fi
echo "FAIL: $FAILURES assertion(s) failed" >&2; exit 1
