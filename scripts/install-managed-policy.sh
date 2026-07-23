#!/usr/bin/env bash
# install-managed-policy.sh — Claude Code managed security policy installer/checker.
# Security-critical settings are copied to the documented OS-managed drop-in
# directory. bootstrap refuses to link user settings until this exact policy is
# installed, so project/local settings cannot replace the security boundary.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SOURCE="$REPO_ROOT/claude/managed-settings.json"
USER_SETTINGS="$REPO_ROOT/claude/settings.json"
POLICY_CHECK="$SCRIPT_DIR/check-managed-policy.py"
MODE="check"
TARGET_OVERRIDE=""

usage() {
  cat <<'USAGE'
Usage: scripts/install-managed-policy.sh [--check|--apply|--print-target]

  --check         Verify the OS-managed policy is installed exactly (default).
  --apply         Install/update the policy. Use sudo outside test mode.
  --print-target  Print the documented target path for this OS.

A non-system --target is accepted only with AGENTS_TOOLKIT_TESTING=1 for tests.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --apply) MODE="apply"; shift ;;
    --print-target) MODE="print"; shift ;;
    --target)
      if [[ "${AGENTS_TOOLKIT_TESTING:-0}" != "1" ]]; then
        echo "ERROR: --target is test-only (requires AGENTS_TOOLKIT_TESTING=1)" >&2
        exit 1
      fi
      [[ $# -ge 2 ]] || { echo "ERROR: --target requires PATH" >&2; exit 1; }
      TARGET_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

for required in "$SOURCE" "$USER_SETTINGS" "$POLICY_CHECK"; do
  if [[ ! -f "$required" ]]; then
    echo "ERROR: required policy input is missing: $required" >&2
    exit 1
  fi
done

# Validate both halves before touching the system. This also prevents a future
# change from moving security keys back into the lower-precedence user file.
python3 "$POLICY_CHECK" --user "$USER_SETTINGS" --managed "$SOURCE" >/dev/null

if [[ -n "$TARGET_OVERRIDE" ]]; then
  TARGET="$TARGET_OVERRIDE"
  TEST_MODE="true"
else
  TEST_MODE="false"
  case "$(uname -s)" in
    Linux)
      TARGET="/etc/claude-code/managed-settings.d/20-agents-toolkit-security.json"
      ;;
    Darwin)
      TARGET="/Library/Application Support/ClaudeCode/managed-settings.d/20-agents-toolkit-security.json"
      ;;
    *)
      echo "ERROR: unsupported OS for file-based managed settings: $(uname -s)" >&2
      echo "Use the platform's documented MDM/registry managed-settings mechanism." >&2
      exit 1
      ;;
  esac
fi

if [[ "$MODE" == "print" ]]; then
  printf '%s\n' "$TARGET"
  exit 0
fi

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
source_sha="$(sha256_file "$SOURCE")"

check_target() {
  if [[ -L "$TARGET" ]]; then
    echo "ERROR: managed policy target must not be a symlink: $TARGET" >&2
    return 1
  fi
  if [[ ! -f "$TARGET" ]]; then
    echo "ERROR: managed policy is not installed: $TARGET" >&2
    echo "Run: sudo $SCRIPT_DIR/install-managed-policy.sh --apply" >&2
    return 1
  fi
  if ! cmp -s "$SOURCE" "$TARGET"; then
    echo "ERROR: managed policy drift: $TARGET differs from $SOURCE" >&2
    echo "Run: sudo $SCRIPT_DIR/install-managed-policy.sh --apply" >&2
    return 1
  fi

  local mode owner
  mode="$(stat -c '%a' "$TARGET" 2>/dev/null || stat -f '%Lp' "$TARGET")"
  owner="$(stat -c '%u' "$TARGET" 2>/dev/null || stat -f '%u' "$TARGET")"
  if (( (8#$mode & 8#022) != 0 )); then
    echo "ERROR: managed policy is group/world writable (mode $mode): $TARGET" >&2
    return 1
  fi
  if [[ "$TEST_MODE" != "true" && "$owner" != "0" ]]; then
    echo "ERROR: managed policy must be root-owned (uid=$owner): $TARGET" >&2
    return 1
  fi
  echo "OK: managed security policy installed ($TARGET, sha256=$source_sha)"
}

case "$MODE" in
  check)
    check_target
    ;;
  apply)
    if [[ "$TEST_MODE" != "true" && "$EUID" -ne 0 ]]; then
      echo "ERROR: installing managed settings requires root privileges." >&2
      echo "Run: sudo $SCRIPT_DIR/install-managed-policy.sh --apply" >&2
      exit 1
    fi
    parent="$(dirname "$TARGET")"
    install -d -m 0755 "$parent"
    if [[ -L "$TARGET" ]]; then
      echo "ERROR: refusing to overwrite symlink target: $TARGET" >&2
      exit 1
    fi
    install -m 0644 "$SOURCE" "$TARGET"
    check_target
    ;;
  *)
    echo "ERROR: internal mode error: $MODE" >&2
    exit 1
    ;;
esac
