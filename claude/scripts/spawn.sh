#!/usr/bin/env bash
# spawn.sh — open a new Claude Code tab (a cmux WORKSPACE) in its own git worktree,
# and optionally hand it an opening instruction.
#
# The non-interactive, scriptable sibling of `ccw`: same worktree paths and tab
# names, but it never steals focus (the new tab appears in the tab bar without
# switching your view), it waits for Claude's input box to come up before typing,
# and it can send a first prompt. Safe to call from another Claude session or a hook.
#
# Usage:
#   spawn.sh <branch> ["first instruction"] [--base <ref>] [--install]
#            [--dir <path>] [--no-wait] [--attach] [--model <model>] [--effort <level>]
#
#   <branch>             tab name + new branch off the repo's default branch,
#                        fetched fresh from origin (override with --base)
#   "first instruction"  optional; typed into Claude once it is ready
#   --dir <path>         run in <path> as-is instead of creating a worktree
#   --no-wait            don't wait for Claude's prompt before returning/sending
#   --attach             switch focus to the new tab after starting (else stays put)
#   --model <model>      launch Claude on this model (alias or full id); omit to
#                        use the settings.json default
#   --effort <level>     launch Claude at this effort (low|medium|high|xhigh);
#                        omit to use the settings.json default
#   --base / --install   passed through to new-worktree.sh
#
# Env: CCW_LAUNCH_CMD (default: claude), SPAWN_READY_TIMEOUT (default: 30 seconds).
set -uo pipefail
# shellcheck source=session-lib.sh
. "$(dirname "$0")/session-lib.sh"

LAUNCH="${CCW_LAUNCH_CMD:-claude}"
READY_TIMEOUT="${SPAWN_READY_TIMEOUT:-30}"
BRANCH=""; PROMPT=""; USE_DIR=""; NO_WAIT=0; ATTACH=0
WT_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)     USE_DIR="${2:-}"; shift ;;
    --no-wait) NO_WAIT=1 ;;
    --attach)  ATTACH=1 ;;
    --model)   LAUNCH="$LAUNCH --model ${2:?spawn: --model needs a value}"; shift ;;
    --effort)  LAUNCH="$LAUNCH --effort ${2:?spawn: --effort needs a value}"; shift ;;
    --base)    WT_ARGS+=(--base "${2:-}"); shift ;;
    --install) WT_ARGS+=(--install) ;;
    --help|-h) sed -n '2,27p' "$0"; exit 0 ;;
    -*)        echo "spawn: unknown flag: $1" >&2; exit 2 ;;
    *) if   [ -z "$BRANCH" ]; then BRANCH="$1"
       elif [ -z "$PROMPT" ]; then PROMPT="$1"
       else echo "spawn: unexpected argument: $1" >&2; exit 2; fi ;;
  esac
  shift
done
[ -n "$BRANCH" ] || { echo "spawn: need a <branch>/label. Try --help." >&2; exit 2; }

sc_require_cmux || exit 1

# Where does it run?
if [ -n "$USE_DIR" ]; then
  WT="$(cd "$USE_DIR" 2>/dev/null && pwd)" || { echo "spawn: no such dir: $USE_DIR" >&2; exit 1; }
  MAIN="$(sc_main_repo "$WT")" || MAIN="$WT"
else
  MAIN="$(sc_main_repo "$PWD")" || { echo "spawn: not inside a git repo (use --dir <path>)." >&2; exit 1; }
  WT="$MAIN/.claude/worktrees/$BRANCH"
fi

if [ -n "$(sc_ws_ref "$BRANCH")" ]; then
  echo "spawn: a tab named '$BRANCH' is already open." >&2
  echo "       Talk to it:  tell $BRANCH \"...\"   ·   focus it:  ccw $BRANCH" >&2
  exit 1
fi

# Create the worktree unless we were pointed at an existing --dir.
if [ -z "$USE_DIR" ]; then
  if [ -d "$WT" ]; then
    echo "spawn: reusing existing worktree $WT"
  else
    NW="$MAIN/.cursor/commands/new-worktree.sh"
    [ -f "$NW" ] || NW="$HOME/.claude/scripts/new-worktree.sh"
    bash "$NW" "$BRANCH" "${WT_ARGS[@]+"${WT_ARGS[@]}"}" || exit 1
  fi
fi

# Add the tab. --command launches Claude in it; --focus stays put unless --attach,
# so the caller's view doesn't jump.
FOCUS=false; [ "$ATTACH" -eq 1 ] && FOCUS=true
OUT="$("$CMUX" new-workspace --name "$BRANCH" --cwd "$WT" --command "$LAUNCH" --focus "$FOCUS" 2>&1)" \
  || { echo "spawn: cmux new-workspace failed: $OUT" >&2; exit 1; }
REF="$(printf '%s\n' "$OUT" | grep -oE 'workspace:[0-9]+' | head -n1)"
[ -n "$REF" ] || REF="$(sc_ws_ref "$BRANCH")"
[ -n "$REF" ] || { echo "spawn: opened the workspace but couldn't resolve its ref." >&2; exit 1; }
echo "spawn: opened tab '$BRANCH' in $WT"

# Wait for Claude's input box, so a first prompt lands in the box and not in boot noise.
if [ "$NO_WAIT" -eq 0 ]; then
  ready=0 waited=0
  while [ "$waited" -lt "$READY_TIMEOUT" ]; do
    if "$CMUX" read-screen --workspace "$REF" 2>/dev/null \
         | grep -Eq '\? for shortcuts|esc to interrupt|╭─'; then ready=1; break; fi
    sleep 1; waited=$((waited + 1))
  done
  [ "$ready" -eq 1 ] || echo "spawn: ⚠️  Claude didn't look ready after ${READY_TIMEOUT}s; continuing anyway." >&2
fi

# Hand over the opening instruction: type it, then submit with Enter.
if [ -n "$PROMPT" ]; then
  "$CMUX" send --workspace "$REF" -- "$PROMPT" >/dev/null 2>&1
  "$CMUX" send-key --workspace "$REF" enter >/dev/null 2>&1
  echo "spawn: sent opening instruction to '$BRANCH'"
fi

if [ "$ATTACH" -eq 1 ]; then
  read -r WIN _ < <(sc_find_ws "$BRANCH")
  [ -n "${WIN:-}" ] && "$CMUX" focus-window --window "$WIN" >/dev/null 2>&1
  "$CMUX" select-workspace --workspace "$REF" >/dev/null 2>&1
else
  echo "spawn: it's a cmux tab — focus it with  ccw $BRANCH / att $BRANCH   ·   direct it with  tell $BRANCH \"...\""
fi
