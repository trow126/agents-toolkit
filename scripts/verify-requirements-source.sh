#!/usr/bin/env bash
# Verify an external requirements PDF against the content-addressed manifest.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
MANIFEST="$REPO_ROOT/docs/requirements/source-manifest.sha256"

if [[ "${1:-}" == "--manifest" ]]; then
  if [[ "${AGENTS_TOOLKIT_TESTING:-0}" != "1" || $# -ne 3 ]]; then
    echo "ERROR: --manifest is test-only and requires AGENTS_TOOLKIT_TESTING=1" >&2
    exit 1
  fi
  MANIFEST="$2"
  shift 2
fi
if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/verify-requirements-source.sh /path/to/260722_2151_001.pdf" >&2
  exit 1
fi
pdf="$1"
[[ -f "$MANIFEST" ]] || { echo "ERROR: manifest not found: $MANIFEST" >&2; exit 1; }
[[ -f "$pdf" ]] || { echo "ERROR: file not found: $pdf" >&2; exit 1; }
expected="$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$MANIFEST")"
name="$(awk 'NF && $1 !~ /^#/ {$1=""; sub(/^  */, ""); print; exit}' "$MANIFEST")"
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { echo "ERROR: invalid source manifest: $MANIFEST" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$pdf" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$pdf" | awk '{print $1}')"
fi
if [[ "$actual" != "$expected" ]]; then
  echo "ERROR: requirements source hash mismatch" >&2
  echo "expected: $expected  $name" >&2
  echo "actual:   $actual  $pdf" >&2
  exit 1
fi
echo "OK: requirements source matches $name (sha256=$actual)"
