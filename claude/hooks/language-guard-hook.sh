#!/bin/bash
# Stop and PreToolUse(AskUserQuestion) hook: keep replies in the configured language (see lib/language_guard.py).
#
# exit 0 = allow, exit 2 = block (stderr tells Claude to rewrite in Japanese; a Stop is blocked at most
# once per turn), exit 1 = non-blocking internal error; the guard is optional and must not trap a session.
set -euo pipefail

HOOK_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)" || { echo "language-guard-hook: cannot resolve hook directory" >&2; exit 1; }
exec python3 -I "$HOOK_DIR/lib/language_guard.py"
