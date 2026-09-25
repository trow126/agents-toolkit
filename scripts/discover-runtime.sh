#!/usr/bin/env bash
# discover-runtime.sh — runtime / model の変化を read-only で取得し、routing 表と照合する
# （2026-09-25 近代化 Phase 3）。設定は変更せず、snapshot だけを
# ${XDG_STATE_HOME:-~/.local/state}/agents-toolkit/runtime-snapshot.json に書く。
# FAIL があれば exit 1。Issue は起票しない。
#
# 使い方: scripts/discover-runtime.sh [--no-write] [--online]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/lib/discover_runtime.py" "$@"
