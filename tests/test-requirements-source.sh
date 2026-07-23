#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERIFY="$REPO_ROOT/scripts/verify-requirements-source.sh"
MANIFEST="$REPO_ROOT/docs/requirements/source-manifest.sha256"
TRANSCRIPTION="$REPO_ROOT/docs/requirements/requirements-transcription-260722.md"
SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT
FAILURES=0
ok(){ echo "ok: $1"; }; ng(){ echo "FAIL: $1" >&2; FAILURES=$((FAILURES+1)); }
sha="$(awk '{print $1; exit}' "$MANIFEST")"
if [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then ok "source manifest has SHA-256"; else ng "invalid source manifest hash"; fi
if grep -qF "$sha" "$TRANSCRIPTION"; then ok "transcription references manifest hash"; else ng "transcription hash mismatch"; fi
printf 'fixture\n' > "$SANDBOX/source.pdf"
if command -v sha256sum >/dev/null 2>&1; then fsha="$(sha256sum "$SANDBOX/source.pdf" | awk '{print $1}')"; else fsha="$(shasum -a 256 "$SANDBOX/source.pdf" | awk '{print $1}')"; fi
printf '%s  source.pdf\n' "$fsha" > "$SANDBOX/manifest"
if AGENTS_TOOLKIT_TESTING=1 "$VERIFY" --manifest "$SANDBOX/manifest" "$SANDBOX/source.pdf" >/dev/null; then ok "matching source verifies"; else ng "matching source rejected"; fi
printf 'tampered\n' >> "$SANDBOX/source.pdf"
if ! AGENTS_TOOLKIT_TESTING=1 "$VERIFY" --manifest "$SANDBOX/manifest" "$SANDBOX/source.pdf" >/dev/null 2>&1; then ok "hash mismatch is rejected"; else ng "hash mismatch accepted"; fi
printf '\n'; if [[ "$FAILURES" -eq 0 ]]; then echo "PASS: all assertions succeeded"; exit 0; fi; echo "FAIL: $FAILURES assertion(s) failed" >&2; exit 1
