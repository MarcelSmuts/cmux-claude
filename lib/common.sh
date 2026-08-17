#!/usr/bin/env bash
# common.sh — shared helpers for the install/*.sh component scripts. Source it; don't run it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
