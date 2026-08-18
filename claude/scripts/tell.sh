#!/usr/bin/env bash
# tell.sh — type an instruction into a running Claude tab (a cmux workspace, opened
# via spawn/ccw) and submit it. Address it by branch/tab name.
#
# Safety: refuses to send when the tab looks like it's showing a permission /
# selection prompt, where your text + Enter would answer it for you. Look, then
# re-run with --force if you really mean to.
#
# Usage:
#   tell.sh <branch> "instruction" [--force] [--no-enter]
set -uo pipefail
# shellcheck source=session-lib.sh
. "$(dirname "$0")/session-lib.sh"

TARGET=""; MSG=""; FORCE=0; ENTER=1
while [ $# -gt 0 ]; do
  case "$1" in
    --force)    FORCE=1 ;;
    --no-enter) ENTER=0 ;;
    --help|-h)  sed -n '2,12p' "$0"; exit 0 ;;
    -*)         echo "tell: unknown flag: $1" >&2; exit 2 ;;
    *) if   [ -z "$TARGET" ]; then TARGET="$1"
       elif [ -z "$MSG" ];    then MSG="$1"
       else echo "tell: unexpected argument: $1" >&2; exit 2; fi ;;
  esac
  shift
done
if [ -z "$TARGET" ] || [ -z "$MSG" ]; then
  echo "tell: usage: tell <branch> \"instruction\"" >&2; exit 2
fi

sc_require_cmux || exit 1

# Resolve TARGET to its workspace ref.
REF="$(sc_ws_ref "$TARGET")"
if [ -z "$REF" ]; then
  echo "tell: no live tab named '$TARGET'. Open tabs:" >&2
  bash "$(dirname "$0")/sessions.sh" >&2 2>/dev/null || true
  exit 1
fi

# Guard: don't answer a permission / selection prompt for the user.
if [ "$FORCE" -eq 0 ] \
   && "$CMUX" read-screen --workspace "$REF" 2>/dev/null \
        | grep -qE 'Do you want to proceed|No, and tell Claude|Yes, and don.t ask|❯ *[0-9]+\.'; then
  echo "tell: '$TARGET' looks like it's waiting on a permission/selection prompt." >&2
  echo "      Refusing so your message can't pick an option. Re-run with --force once you've checked." >&2
  exit 3
fi

"$CMUX" send --workspace "$REF" -- "$MSG" >/dev/null 2>&1
[ "$ENTER" -eq 1 ] && "$CMUX" send-key --workspace "$REF" enter >/dev/null 2>&1
echo "tell: sent to '$TARGET'"
