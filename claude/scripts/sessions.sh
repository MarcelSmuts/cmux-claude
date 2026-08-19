#!/usr/bin/env bash
# sessions.sh — list the Claude tabs (named cmux workspaces), one per line, marking the
# active tab and, from the spawn-ownership registry, which tab spawned each (OWNER, '-'
# when unknown). These are the tabs `tell` and `att` can reach.
#
# Usage:
#   sessions.sh [--mine]
#   --mine   show only tabs spawned BY this tab (a planner's own workers)
set -uo pipefail
# shellcheck source=session-lib.sh
. "$(dirname "$0")/session-lib.sh"

MINE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --mine)    MINE=1 ;;
    --help|-h) sed -n '2,13p' "$0"; exit 0 ;;
    -*)        echo "sessions: unknown flag: $1" >&2; exit 2 ;;
    *)         echo "sessions: unexpected argument: $1" >&2; exit 2 ;;
  esac
  shift
done

sc_require_cmux || exit 1

SELF=""
if [ "$MINE" -eq 1 ]; then
  SELF="$(sc_self_title 2>/dev/null || true)"
  [ -n "$SELF" ] || { echo "sessions: --mine must run inside a cmux tab (couldn't resolve this tab's title)." >&2; exit 1; }
fi

SEL="$("$CMUX" current-workspace 2>/dev/null | grep -oE 'workspace:[0-9]+' | head -n1)"
FOUND=0
for win in $("$CMUX" --json list-windows 2>/dev/null | jq -r '.[].id'); do
  while IFS=$'\t' read -r ref title dir; do
    [ -n "$ref" ] || continue
    owner="$(sc_owner_of "$title")"; [ -n "$owner" ] || owner="-"
    [ "$MINE" -eq 1 ] && [ "$owner" != "$SELF" ] && continue
    FOUND=1
    mark=""; [ "$ref" = "$SEL" ] && mark="  ● active"
    printf '%s\t%s\t%s\t%s%s\n' "$ref" "$title" "$owner" "$dir" "$mark"
  done < <("$CMUX" --json list-workspaces --window "$win" 2>/dev/null \
             | jq -r '.workspaces[] | select(.has_custom_title) | [.ref, .custom_title, .current_directory] | @tsv')
done
if [ "$FOUND" -eq 0 ]; then
  if [ "$MINE" -eq 1 ]; then
    echo "no tabs spawned by '$SELF' yet — spawn one with:  spawn <branch>"
  else
    echo "no Claude tabs open yet — spawn one with:  spawn <branch>"
  fi
fi
