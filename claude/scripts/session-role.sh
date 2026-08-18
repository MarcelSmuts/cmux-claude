#!/usr/bin/env bash
# session-role.sh — SessionStart hook: if this session runs in a cmux tab whose custom
# title matches a role file in ~/.claude/roles/ (title lowercased, non-alphanumerics
# to '-'), inject that file as additional context so the session knows its standing job.
# For a qualified title like "PLANNER: viz", when the exact slug ("planner-viz") has no
# file it falls back to the part before the first ':' ("planner"), so one role file can
# serve many qualified tabs; the qualifier is surfaced to the session. Exact slug wins,
# so a hand-written roles/planner-viz.md still overrides the generic role for that tab.
# Silent no-op outside cmux, for untitled tabs, and for titles with no role file.
set -uo pipefail
. "$(dirname "$0")/session-lib.sh"

ROLES_DIR="$HOME/.claude/roles"
[ -d "$ROLES_DIR" ] || exit 0

TITLE="$(sc_self_title)" || exit 0
[ -n "$TITLE" ] || exit 0

SLUG="$(sc_slugify "$TITLE")"
[ -n "$SLUG" ] || exit 0
ROLE_FILE="$ROLES_DIR/$SLUG.md"

# Fallback for qualified titles ("ROLE: qualifier"): retry with the role before the ':'.
QUALIFIER=""
if [ ! -f "$ROLE_FILE" ]; then
  case "$TITLE" in
    *:*)
      PSLUG="$(sc_slugify "${TITLE%%:*}")"
      [ -n "$PSLUG" ] || exit 0
      ROLE_FILE="$ROLES_DIR/$PSLUG.md"
      QUALIFIER="$(printf '%s' "${TITLE#*:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      ;;
  esac
fi
[ -f "$ROLE_FILE" ] || exit 0

jq -n --arg title "$TITLE" --arg qualifier "$QUALIFIER" --rawfile brief "$ROLE_FILE" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: (
      "This session runs in the cmux tab \"" + $title + "\", which has a standing role:\n\n" + $brief
      + (if $qualifier != "" then "\n\nYour qualifier within this role is \"" + $qualifier + "\"." else "" end)
    )
  }
}'
