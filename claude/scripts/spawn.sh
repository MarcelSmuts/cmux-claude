#!/usr/bin/env bash
# spawn.sh — open a new Claude Code tab (a cmux WORKSPACE) in its own git worktree,
# and optionally hand it an opening instruction.
#
# The non-interactive, scriptable sibling of `ccw`: same worktree paths and tab
# names, but it never steals focus (the new tab appears in the tab bar without
# switching your view), it waits for Claude's input box to come up before typing,
# verifies the instruction actually landed (one automatic resend if not), and
# serializes worktree creation so parallel spawns can't race git's ref lock.
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
#                        default to opus (SPAWN_MODEL= uses the settings default)
#   --effort <level>     launch Claude at this effort (low|medium|high|xhigh);
#                        omit to use the settings.json default
#   --base / --install   passed through to new-worktree.sh
#
# Env: CCW_LAUNCH_CMD (default: claude), SPAWN_MODEL (default: opus), SPAWN_READY_TIMEOUT (default: 30s).
#      SPAWN_VERIFY_TIMEOUT (default: 30 seconds).
set -uo pipefail
# shellcheck source=session-lib.sh
. "$(dirname "$0")/session-lib.sh"

LAUNCH="${CCW_LAUNCH_CMD:-claude}"
READY_TIMEOUT="${SPAWN_READY_TIMEOUT:-90}"
VERIFY_TIMEOUT="${SPAWN_VERIFY_TIMEOUT:-30}"
SPAWN_EPOCH=$(( $(date +%s) - 5 ))
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
    --help|-h) sed -n '2,29p' "$0"; exit 0 ;;
    -*)        echo "spawn: unknown flag: $1" >&2; exit 2 ;;
    *) if   [ -z "$BRANCH" ]; then BRANCH="$1"
       elif [ -z "$PROMPT" ]; then PROMPT="$1"
       else echo "spawn: unexpected argument: $1" >&2; exit 2; fi ;;
  esac
  shift
done
[ -n "$BRANCH" ] || { echo "spawn: need a <branch>/label. Try --help." >&2; exit 2; }

# Default spawned sessions to opus unless a model was already chosen — via --model
# above or a CCW_LAUNCH_CMD that names one. Effort is intentionally left at the
# settings.json default. Set SPAWN_MODEL= (empty) to use that default model too.
SPAWN_MODEL="${SPAWN_MODEL-opus}"
case "$LAUNCH" in
  *--model*) ;;
  *) [ -n "$SPAWN_MODEL" ] && LAUNCH="$LAUNCH --model $SPAWN_MODEL" ;;
esac

sc_require_cmux || exit 1

# Where does it run?
if [ -n "$USE_DIR" ]; then
  WT="$(cd "$USE_DIR" 2>/dev/null && pwd)" || { echo "spawn: no such dir: $USE_DIR" >&2; exit 1; }
  MAIN="$(sc_main_repo "$WT")" || MAIN="$WT"
else
  MAIN="$(sc_main_repo "$PWD")" || { echo "spawn: not inside a git repo (use --dir <path>)." >&2; exit 1; }
  WT="$MAIN/.claude/worktrees/$BRANCH"
fi
# The repo is derived from cwd unless --dir was given; say so loudly, since a
# spawn meant for a different repo is a silent footgun.
echo "spawn: repo: $MAIN"

if [ -n "$(sc_ws_ref "$BRANCH")" ]; then
  echo "spawn: a tab named '$BRANCH' is already open." >&2
  echo "       Talk to it:  tell $BRANCH \"...\"   ·   focus it:  ccw $BRANCH" >&2
  exit 1
fi

# Worktree creation lock: parallel spawns race git's ref lock during fetch, so
# only one worktree gets created at a time. Stale locks (>10 min) are broken.
WT_LOCK="$HOME/.claude/locks/spawn-worktree.lock"
wt_lock() {
  mkdir -p "$HOME/.claude/locks"
  local waited=0
  while ! mkdir "$WT_LOCK" 2>/dev/null; do
    if [ -d "$WT_LOCK" ] && [ $(( $(date +%s) - $(stat -f %m "$WT_LOCK" 2>/dev/null || echo 0) )) -gt 600 ]; then
      rmdir "$WT_LOCK" 2>/dev/null && continue
    fi
    if [ "$waited" -ge 180 ]; then
      echo "spawn: timed out waiting for worktree lock ($WT_LOCK); remove it if no other spawn is running." >&2
      return 1
    fi
    sleep 2; waited=$((waited + 2))
  done
  trap 'rmdir "$WT_LOCK" 2>/dev/null' EXIT
}
wt_unlock() { rmdir "$WT_LOCK" 2>/dev/null; trap - EXIT; }

# Create the worktree unless we were pointed at an existing --dir.
if [ -z "$USE_DIR" ]; then
  wt_lock || exit 1
  if [ -d "$WT" ]; then
    echo "spawn: reusing existing worktree $WT"
  else
    NW="$MAIN/.cursor/commands/new-worktree.sh"
    [ -f "$NW" ] || NW="$HOME/.claude/scripts/new-worktree.sh"
    bash "$NW" "$BRANCH" "${WT_ARGS[@]+"${WT_ARGS[@]}"}" || { wt_unlock; exit 1; }
  fi
  # Repos that ship .cursor/commands/worktree-test-db.sh give each worktree its
  # own integration-test database so sibling branches' migrations can't collide;
  # skipped when the repo has no such script. Idempotent, so it also covers a
  # reused worktree and a repo whose new-worktree.sh predates the helper.
  TESTDB="$MAIN/.cursor/commands/worktree-test-db.sh"
  if [ -f "$TESTDB" ] && [ -f "$WT/.env" ]; then
    bash "$TESTDB" create "$BRANCH" "$WT"
  fi
  wt_unlock
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

# Wait for Claude's input box, so a prompt lands in the box and not in boot noise.
# Markers cover the current UI (mode footer) and older UIs, since the old-only
# pattern is why every spawn used to "look not ready" and warn at the timeout.
wait_ready() {
  local waited=0
  while [ "$waited" -lt "$READY_TIMEOUT" ]; do
    if "$CMUX" read-screen --workspace "$REF" 2>/dev/null \
         | grep -Eq 'shift\+tab to cycle|auto mode|esc to interrupt|\? for shortcuts|╭─'; then return 0; fi
    sleep 1; waited=$((waited + 1))
  done
  return 1
}

# Did the instruction actually register? True if the tab is busy working
# ("esc to interrupt") or its session transcript has recorded a user turn
# since this spawn started. The transcript check catches prompts that finish
# faster than the screen poll.
prompt_landed() {
  "$CMUX" read-screen --workspace "$REF" 2>/dev/null | grep -q 'esc to interrupt' && return 0
  local pdir f
  pdir="$HOME/.claude/projects/$(printf '%s' "$WT" | sed 's#[/.]#-#g')"
  [ -d "$pdir" ] || return 1
  for f in "$pdir"/*.jsonl; do
    [ -f "$f" ] || continue
    [ "$(stat -f %m "$f" 2>/dev/null || echo 0)" -ge "$SPAWN_EPOCH" ] || continue
    grep -q '"type":"user"' "$f" && return 0
  done
  return 1
}

verify_prompt() {
  local waited=0
  while [ "$waited" -lt "$VERIFY_TIMEOUT" ]; do
    prompt_landed && return 0
    sleep 2; waited=$((waited + 2))
  done
  return 1
}

send_prompt() {
  "$CMUX" send --workspace "$REF" -- "$PROMPT" >/dev/null 2>&1
  "$CMUX" send-key --workspace "$REF" enter >/dev/null 2>&1
}

if [ "$NO_WAIT" -eq 0 ]; then
  wait_ready || echo "spawn: ⚠️  Claude didn't look ready after ${READY_TIMEOUT}s; continuing anyway." >&2
fi

# Hand over the opening instruction, then confirm it registered; resend once if not.
if [ -n "$PROMPT" ]; then
  send_prompt
  if verify_prompt; then
    echo "spawn: sent opening instruction to '$BRANCH' (verified)"
  else
    echo "spawn: instruction didn't register; waiting for readiness and resending once..." >&2
    wait_ready
    if prompt_landed; then
      echo "spawn: instruction registered late for '$BRANCH' (no resend needed)"
    else
      send_prompt
      if verify_prompt; then
        echo "spawn: resend verified for '$BRANCH'"
      else
        echo "spawn: ⚠️  could not confirm the instruction landed in '$BRANCH'." >&2
        echo "       Inspect:  bash ~/.claude/scripts/att.sh $BRANCH   ·   resend:  bash ~/.claude/scripts/tell.sh $BRANCH \"...\"" >&2
      fi
    fi
  fi
fi

if [ "$ATTACH" -eq 1 ]; then
  read -r WIN _ < <(sc_find_ws "$BRANCH")
  [ -n "${WIN:-}" ] && "$CMUX" focus-window --window "$WIN" >/dev/null 2>&1
  "$CMUX" select-workspace --workspace "$REF" >/dev/null 2>&1
else
  echo "spawn: it's a cmux tab — focus it with  ccw $BRANCH / att $BRANCH   ·   direct it with  tell $BRANCH \"...\""
fi
