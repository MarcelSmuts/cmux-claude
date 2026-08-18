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
# `ping` fails two very different ways, so split them: a rejected socket password needs
# a config fix, not "open cmux" — conflating them sends the user down the wrong path.
# Where cmux keeps its config. The socket password lives under .automation there.
CMUX_CONFIG="${CMUX_CONFIG:-$HOME/.config/cmux/cmux.json}"

# Re-arm the socket password after cmux has stripped it from its config.
#
# cmux reads automation.socketPassword out of cmux.json on startup and REMOVES the
# plaintext from the file. If it does not end up with a usable stored password, the
# app is left in password mode with nothing to match and every external CLI call
# fails — including this workflow's, since an agent shell has no CMUX_WORKSPACE_ID
# and so never gets the cmuxOnly fast path. Writing the value back and reloading
# restores it without restarting the app.
#
# Deliberately narrow: only the stripped state (mode is password, no password in the
# file) is repaired, from $CMUX_SOCKET_PASSWORD, which is the value the scripts
# authenticate with anyway. A password that is present but wrong is left alone —
# that is a mismatch to resolve by hand, not a value to overwrite. Set
# CMUX_SOCKET_PW_AUTOREPAIR= (empty) to disable.
sc_repair_socket_password() {
  # ${VAR-1}, not ${VAR:-1}: an explicitly-empty value must count as opting out.
  [ -n "${CMUX_SOCKET_PW_AUTOREPAIR-1}" ] || return 1
  [ -n "${CMUX_SOCKET_PASSWORD:-}" ] || return 1
  [ -f "$CMUX_CONFIG" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1

  # Only the stripped state: password mode on, no password left in the file.
  [ "$(jq -r '.automation.socketControlMode // ""' "$CMUX_CONFIG" 2>/dev/null)" = "password" ] || return 1
  [ -z "$(jq -r '.automation.socketPassword // ""' "$CMUX_CONFIG" 2>/dev/null)" ] || return 1

  local tmp
  # One stable backup name, not a timestamped pile: cmux keeps its own backup of the
  # pre-strip file, so all this needs to hold is the state immediately before we write.
  cp -p "$CMUX_CONFIG" "$CMUX_CONFIG.pre-autorepair.bak" 2>/dev/null || return 1
  tmp="$(mktemp "${TMPDIR:-/tmp}/cmux-config.XXXXXX")" || return 1
  chmod 600 "$tmp"
  # --arg keeps the password out of the filter (and out of any error message).
  if ! jq --arg pw "$CMUX_SOCKET_PASSWORD" '.automation.socketPassword = $pw' \
            "$CMUX_CONFIG" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"; return 1
  fi
  mv "$tmp" "$CMUX_CONFIG" || { rm -f "$tmp"; return 1; }

  "$CMUX" reload-config >/dev/null 2>&1 || return 1
  "$CMUX" ping >/dev/null 2>&1
}

sc_require_cmux() {
  command -v "$CMUX" >/dev/null 2>&1 \
    || { echo "cmux: '$CMUX' is not on PATH." >&2; return 1; }
  local out
  out="$("$CMUX" ping 2>&1)" && return 0
  case "$out" in
    *[Pp]assword*|*[Aa]uthentication*|*"Access denied"*)
      if sc_repair_socket_password; then
        echo "cmux: socket password had been stripped from $CMUX_CONFIG; re-armed it from \$CMUX_SOCKET_PASSWORD." >&2
        return 0
      fi
      echo "cmux: socket auth rejected — password mode is on but the CLI can't authenticate." >&2
      echo "      Give the app a password to match (\$CMUX_SOCKET_PASSWORD isn't enough on its own):" >&2
      echo "        set automation.socketPassword in $CMUX_CONFIG, then:  cmux reload-config" >&2
      echo "        (or set it in cmux Settings > Automation). Use the same value as \$CMUX_SOCKET_PASSWORD," >&2
      echo "        and export that in this shell so the re-arm above can run unattended next time." >&2
      ;;
    *)
      echo "cmux: app isn't running / socket unreachable — open cmux first." >&2
      ;;
  esac
  return 1
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
