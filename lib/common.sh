#!/usr/bin/env bash
# common.sh — shared helpers for the install/*.sh component scripts. Source it; don't run it.
# shellcheck disable=SC2034  # the color palette below is consumed by the scripts that source this file
set -uo pipefail

# Resolve this file's own path whether it's sourced from bash or zsh. zsh doesn't set
# $BASH_SOURCE, so fall back to its %N prompt-expansion; guarded so bash never has to
# expand the zsh-only form.
# shellcheck disable=SC2296  # ${(%):-%N} is zsh syntax, reached only when bash's $BASH_SOURCE is unset
if [ -n "${BASH_SOURCE:-}" ]; then _common_self="${BASH_SOURCE[0]}"; else _common_self="${(%):-%N}"; fi
REPO_ROOT="$(cd "$(dirname "$_common_self")/.." && pwd)"
unset _common_self
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
PAYLOAD="$REPO_ROOT/claude"

c_bold=$'\033[1m'; c_dim=$'\033[2m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_reset=$'\033[0m'

log()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '%s!%s %s\n' "$c_yellow" "$c_reset" "$*" >&2; }
err()  { printf '%s✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }

confirm() {
  # confirm "question" [default: y] — returns 0 for yes.
  local prompt="$1" default="${2:-y}" reply
  local hint="y/N"; [ "$default" = "y" ] && hint="Y/n"
  read -r -p "$prompt [$hint] " reply </dev/tty
  reply="${reply:-$default}"
  case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# link_into <src-in-payload> <dest-under-CLAUDE_DIR>
# Symlinks so `git pull` in the repo keeps ~/.claude up to date. Backs up a real
# file/dir that's already there (once) instead of clobbering it.
link_into() {
  local src="$PAYLOAD/$1" dest="$CLAUDE_DIR/$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    rm -f "$dest"
  elif [ -e "$dest" ]; then
    local backup="$dest.pre-cmux-claude.bak"
    warn "backing up existing $dest -> $backup"
    rm -rf "$backup"
    mv "$dest" "$backup"
  fi
  ln -s "$src" "$dest"
  ok "linked $2"
}

# merge_session_start_hook <command-path> — idempotently adds a SessionStart hook entry
# to ~/.claude/settings.json pointing at <command-path>. Requires jq. Backs up settings.json
# once before the first write.
merge_session_start_hook() {
  local cmd="$1" settings="$CLAUDE_DIR/settings.json"
  have jq || { err "jq is required to edit $settings — install it (brew install jq) and re-run."; return 1; }
  mkdir -p "$CLAUDE_DIR"
  [ -f "$settings" ] || echo '{}' > "$settings"
  if jq -e --arg cmd "$cmd" \
      '(.hooks.SessionStart // [])[]?.hooks[]? | select(.command == $cmd)' \
      "$settings" >/dev/null 2>&1; then
    ok "SessionStart hook already present in settings.json"
    return 0
  fi
  cp "$settings" "$settings.pre-cmux-claude.bak"
  jq --arg cmd "$cmd" '
    .hooks //= {} |
    .hooks.SessionStart //= [] |
    .hooks.SessionStart += [{ hooks: [{ type: "command", command: $cmd, timeout: 10 }] }]
  ' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
  ok "added SessionStart hook to settings.json (backup at settings.json.pre-cmux-claude.bak)"
}

# Resolves the cmux CLI binary, preferring PATH, falling back to the app bundle.
# Echoes nothing (and returns non-zero) if it can't find one.
cmux_bin() {
  local b="/Applications/cmux.app/Contents/Resources/bin/cmux"
  have cmux && b="cmux"
  [ -x "$b" ] || b="$(command -v cmux 2>/dev/null || true)"
  { [ -n "$b" ] && [ -x "$b" ]; } || return 1
  echo "$b"
}

# create_standing_tab <TITLE> <default-cwd> [launch-cmd]
# Offers to open a new cmux tab titled <TITLE>, pointed at a directory (default
# <default-cwd>, overridable), launch <launch-cmd> (default "claude") in it, and pin
# it — so the SessionStart role-injection hook picks it up on its very first prompt.
# Only runs for the component whose install_*.sh calls it, and only after the user
# opts in here. Never fails the install: on any skip/error it prints the manual
# fallback (rename a tab yourself, start Claude, pin it) and returns 0.
create_standing_tab() {
  local title="$1" default_dir="${2:-$HOME}" launch="${3:-claude}" bin found dir out ref win
  manual() { log "  Do it by hand instead: open a tab, rename it (exactly) ${c_bold}$title${c_reset}, start Claude, and pin it."; }

  bin="$(cmux_bin)" || { warn "cmux CLI not found — skipping automatic tab creation for '$title'."; manual; return 0; }
  "$bin" ping >/dev/null 2>&1 \
    || { warn "cmux isn't running — skipping automatic tab creation for '$title'."; manual; return 0; }

  for win in $("$bin" --json list-windows 2>/dev/null | jq -r '.[].id'); do
    found="$("$bin" --json list-workspaces --window "$win" 2>/dev/null \
      | jq -r --arg t "$title" '.workspaces[] | select(.has_custom_title and .custom_title == $t) | .ref' | head -n1)"
    [ -n "$found" ] && { ok "a '$title' tab already exists — leaving it alone."; return 0; }
  done

  confirm "Create and pin a '$title' tab now?" "y" || { manual; return 0; }
  read -r -p "Directory for it to run in [$default_dir]: " dir </dev/tty
  dir="${dir:-$default_dir}"
  dir="$(cd "$dir" 2>/dev/null && pwd)" || { err "no such directory — skipping tab creation for '$title'."; manual; return 0; }

  out="$("$bin" new-workspace --name "$title" --cwd "$dir" --command "$launch" --focus false 2>&1)" \
    || { err "cmux new-workspace failed: $out"; manual; return 0; }
  ref="$(printf '%s\n' "$out" | grep -oE 'workspace:[0-9]+' | head -n1)"
  if [ -z "$ref" ]; then
    warn "created '$title' but couldn't resolve its ref to pin it — pin it manually in cmux."
    return 0
  fi
  if "$bin" workspace-action --workspace "$ref" --action pin >/dev/null 2>&1; then
    ok "created and pinned '$title' in $dir"
  else
    warn "created '$title' but pinning failed — pin it manually in cmux."
  fi
}
