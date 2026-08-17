#!/usr/bin/env bash
# session-lib.sh — shared helpers for spawn/tell/sessions/unspawn/att on cmux.
#
# Model: every Claude tab is a WORKSPACE in cmux (a tab-like group inside a cmux
# window). Each workspace is named after its branch (its cmux custom_title) and runs
# Claude in that branch's worktree, so ccw, spawn, tell, sessions, att and unspawn
# all address the same tabs by branch name:
#   tab           = a cmux workspace whose custom_title is <branch>
#   worktree path = <main-repo>/.claude/worktrees/<branch>
# cmux addresses workspaces by ref (workspace:N) / index / UUID, never by name, so we
# resolve <branch> -> ref by matching custom_title across every window.
# Source this; don't execute it.

export CMUX_QUIET="${CMUX_QUIET:-1}"   # silence cmux's legacy-alias notices
CMUX="${CMUX_BIN:-cmux}"

# Resolve the MAIN checkout from a dir inside a repo OR a worktree. Echoes the path;
# returns non-zero (and echoes nothing) when the dir isn't a git checkout.
sc_main_repo() {
  local base common
  base="${1:-$PWD}"
  common="$(git -C "$base" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$common" in /*) ;; *) common="$base/$common" ;; esac
  (cd "$(dirname "$common")" 2>/dev/null && pwd) || return 1
}

# Fail early, with a clear message, when the cmux app / control socket is unreachable.
sc_require_cmux() {
  command -v "$CMUX" >/dev/null 2>&1 \
    || { echo "cmux: '$CMUX' is not on PATH." >&2; return 1; }
  "$CMUX" ping >/dev/null 2>&1 \
    || { echo "cmux: app isn't running / socket unreachable — open cmux first." >&2; return 1; }
}

# Echo "<window-id>\t<workspace-ref>" for the workspace whose custom_title == $1,
# searching every window. Non-zero + empty output when there is no match.
sc_find_ws() {
  local branch="$1" win hit
  for win in $("$CMUX" --json list-windows 2>/dev/null | jq -r '.[].id'); do
    hit="$("$CMUX" --json list-workspaces --window "$win" 2>/dev/null \
            | jq -r --arg B "$branch" --arg W "$win" \
                '.workspaces[] | select(.has_custom_title and .custom_title == $B) | "\($W)\t\(.ref)"' \
            | head -n1)"
    [ -n "$hit" ] && { printf '%s\n' "$hit"; return 0; }
  done
  return 1
}

# Convenience: just the workspace ref for branch $1 (empty when none).
sc_ws_ref() { sc_find_ws "$1" | cut -f2; }
