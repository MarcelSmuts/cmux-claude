#!/usr/bin/env bash
# session-role.sh — SessionStart hook: if this session runs in a cmux tab whose custom
# title matches a role file in ~/.claude/roles/ (title lowercased, non-alphanumerics
# to '-'), inject that file as additional context so the session knows its standing job.
# Silent no-op outside cmux, for untitled tabs, and for titles with no role file.
set -uo pipefail

ROLES_DIR="$HOME/.claude/roles"
[ -d "$ROLES_DIR" ] || exit 0
[ -n "${CMUX_WORKSPACE_ID:-}" ] || exit 0

CMUX="${CMUX_BUNDLED_CLI_PATH:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
[ -x "$CMUX" ] || CMUX="$(command -v cmux 2>/dev/null || true)"
{ [ -n "$CMUX" ] && [ -x "$CMUX" ]; } || exit 0

IDENT="$("$CMUX" --json identify 2>/dev/null)" || exit 0
WS_REF=$(printf '%s' "$IDENT" | jq -r '.caller.workspace_ref // empty')
WIN_REF=$(printf '%s' "$IDENT" | jq -r '.caller.window_ref // empty')
{ [ -n "$WS_REF" ] && [ -n "$WIN_REF" ]; } || exit 0

TITLE=$("$CMUX" --json list-workspaces --window "$WIN_REF" 2>/dev/null \
  | jq -r --arg ref "$WS_REF" '.workspaces[] | select(.ref == $ref) | .custom_title // empty')
[ -n "$TITLE" ] || exit 0

SLUG=$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')
[ -n "$SLUG" ] || exit 0
ROLE_FILE="$ROLES_DIR/$SLUG.md"
[ -f "$ROLE_FILE" ] || exit 0

jq -n --arg title "$TITLE" --rawfile brief "$ROLE_FILE" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("This session runs in the cmux tab \"" + $title + "\", which has a standing role:\n\n" + $brief)
  }
}'
