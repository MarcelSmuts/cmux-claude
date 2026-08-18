#!/usr/bin/env bash
# unspawn.sh — tear down a Claude tab opened via spawn/ccw: close its cmux workspace
# and (by default) remove the worktree + branch it ran in, plus its per-worktree test
# database in repos that have one. The inverse of spawn.sh.
# Address it by branch/tab name.
#
# When no live tab is found we still treat the argument as a branch label, so a
# worktree left behind after Claude exited can still be cleaned up.
#
# Safety: pinned tabs are left alone, worktree removal refuses when the worktree has
# uncommitted/untracked files, and the branch is deleted only when fully merged. Re-run
# with --force to override all three. --keep-worktree closes only the tab and leaves the
# worktree in place.
#
# Usage:
#   unspawn.sh <branch> [--keep-worktree] [--force]
set -uo pipefail
# shellcheck source=session-lib.sh
. "$(dirname "$0")/session-lib.sh"

TARGET=""; KEEP_WT=0; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-worktree) KEEP_WT=1 ;;
    --force)         FORCE=1 ;;
    --help|-h)       sed -n '2,15p' "$0"; exit 0 ;;
    -*)              echo "unspawn: unknown flag: $1" >&2; exit 2 ;;
    *) if [ -z "$TARGET" ]; then TARGET="$1"
       else echo "unspawn: unexpected argument: $1" >&2; exit 2; fi ;;
  esac
  shift
done
[ -n "$TARGET" ] || { echo "unspawn: usage: unspawn <branch> [--keep-worktree] [--force]" >&2; exit 2; }

MAIN="$(sc_main_repo "$PWD" 2>/dev/null)" || MAIN=""
BRANCH="$TARGET"

# 1) Close the tab (workspace), if one is live. Worktree cleanup still runs even when
#    cmux isn't reachable, so a leftover worktree can be removed headless.
HIT=""; WIN=""; REF=""
sc_require_cmux 2>/dev/null && HIT="$(sc_find_ws "$BRANCH")"
if [ -n "$HIT" ]; then
  WIN="${HIT%%$'\t'*}"; REF="${HIT##*$'\t'}"
  # A pinned tab is one you meant to keep — a standing role tab, not a spawned worktree —
  # and cmux refuses to close it. Unpinning is a --force move, not one to make for you.
  PINNED="$("$CMUX" --json list-workspaces --window "$WIN" 2>/dev/null \
    | jq -r --arg B "$BRANCH" '.workspaces[] | select(.has_custom_title and .custom_title == $B) | .pinned' \
    | head -n1)"
  if [ "$PINNED" = "true" ]; then
    if [ "$FORCE" -eq 1 ]; then
      "$CMUX" workspace-action --workspace "$REF" --window "$WIN" --action unpin >/dev/null 2>&1 \
        || echo "unspawn: could not unpin tab '$BRANCH'" >&2
    else
      echo "unspawn: tab '$BRANCH' is pinned; left it open. Unpin it in cmux, or re-run with --force." >&2
      exit 1
    fi
  fi
  # cmux's own message is the useful one when a close is refused, so don't swallow it.
  if err="$("$CMUX" close-workspace --workspace "$REF" --window "$WIN" 2>&1 >/dev/null)"; then
    echo "unspawn: closed tab '$BRANCH'"
  else
    # The worktree may still be in use by that tab, so don't go on to delete it.
    echo "unspawn: could not close tab '$BRANCH'${err:+ — $err}" >&2
    exit 1
  fi
else
  echo "unspawn: no live tab '$BRANCH' (already exited?)"
fi

# The tab is gone (or was already), so drop its spawn-ownership row.
sc_unregister_spawn "$BRANCH"

# Stop here if we were only asked to close the tab.
[ "$KEEP_WT" -eq 1 ] && exit 0
[ -n "$MAIN" ] || { echo "unspawn: not inside a git repo, so can't resolve the worktree for '$BRANCH'." >&2; exit 1; }
case "$BRANCH" in
  master|main) echo "unspawn: refusing to delete protected branch '$BRANCH'." >&2; exit 1 ;;
esac

# 2) Remove the worktree.
WT="$MAIN/.claude/worktrees/$BRANCH"
if [ -d "$WT" ]; then
  rm_args=(worktree remove "$WT"); [ "$FORCE" -eq 1 ] && rm_args=(worktree remove --force "$WT")
  if git -C "$MAIN" "${rm_args[@]}" 2>/dev/null; then
    echo "unspawn: removed worktree $WT"
  else
    echo "unspawn: worktree $WT has uncommitted/untracked files (or is locked)." >&2
    echo "         Re-run with --force to discard it." >&2
    exit 1
  fi
else
  echo "unspawn: no worktree at $WT"
fi

# The worktree's own integration-test database goes with it, in repos that ship
# .cursor/commands/worktree-test-db.sh; the helper refuses to touch anything
# outside its test_wt_* prefix.
TESTDB="$MAIN/.cursor/commands/worktree-test-db.sh"
[ -f "$TESTDB" ] && bash "$TESTDB" drop "$BRANCH"

# 3) Delete the branch: safe (-d, merged only) unless --force (-D).
if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  del=-d; [ "$FORCE" -eq 1 ] && del=-D
  if git -C "$MAIN" branch "$del" "$BRANCH" 2>/dev/null; then
    echo "unspawn: deleted branch '$BRANCH'"
  else
    echo "unspawn: branch '$BRANCH' isn't fully merged; kept it. Re-run with --force to delete." >&2
  fi
fi
