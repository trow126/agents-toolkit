#!/bin/bash
# Stop hook: enforce the /pursue completion check (see claude/bin/pursue-goal).
#
# exit 0 = stop allowed (no active goal, other session, or check passed)
# exit 2 = stop blocked; stderr tells Claude the failing check and how to continue
# exit 1 = non-blocking error; enforcement is optional and must not trap the session
set -euo pipefail

HOOK_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)" || { echo "pursue-stop-hook: cannot resolve hook directory" >&2; exit 1; }
HELPER="$HOOK_DIR/../bin/pursue-goal"
if [[ ! -x "$HELPER" ]]; then
    echo "pursue-stop-hook: helper is missing or not executable: $HELPER" >&2
    exit 1
fi
exec python3 "$HELPER" hook-stop
