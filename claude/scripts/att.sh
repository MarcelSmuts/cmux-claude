#!/usr/bin/env bash
# att.sh — focus a Claude tab (a cmux workspace) by branch/tab name: bring its window
# to the front and select the tab. Leaves it running; switch away any time.
#
# Usage:
#   att.sh <branch>
set -uo pipefail
. "$(dirname "$0")/session-lib.sh"

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "att: which tab? (see: sessions)" >&2; exit 2; }

sc_require_cmux || exit 1

LINE="$(sc_find_ws "$TARGET")" || LINE=""
[ -n "$LINE" ] || { echo "att: no tab '$TARGET'. (see: sessions)" >&2; exit 1; }
WIN="${LINE%%$'\t'*}"; REF="${LINE##*$'\t'}"

"$CMUX" focus-window --window "$WIN" >/dev/null 2>&1
"$CMUX" select-workspace --workspace "$REF" >/dev/null 2>&1
echo "att: focused '$TARGET'"
