#!/usr/bin/env bash
# sessions.sh — list the Claude tabs (named cmux workspaces), one per line, marking
# the active tab. These are the tabs `tell` and `att` can reach.
set -uo pipefail
# shellcheck source=session-lib.sh
. "$(dirname "$0")/session-lib.sh"
sc_require_cmux || exit 1

SEL="$("$CMUX" current-workspace 2>/dev/null | grep -oE 'workspace:[0-9]+' | head -n1)"
FOUND=0
for win in $("$CMUX" --json list-windows 2>/dev/null | jq -r '.[].id'); do
  while IFS=$'\t' read -r ref title dir; do
    [ -n "$ref" ] || continue
    FOUND=1
    mark=""; [ "$ref" = "$SEL" ] && mark="  ● active"
    printf '%s\t%s\t%s%s\n' "$ref" "$title" "$dir" "$mark"
  done < <("$CMUX" --json list-workspaces --window "$win" 2>/dev/null \
             | jq -r '.workspaces[] | select(.has_custom_title) | [.ref, .custom_title, .current_directory] | @tsv')
done
[ "$FOUND" -eq 1 ] || echo "no Claude tabs open yet — spawn one with:  spawn <branch>"
