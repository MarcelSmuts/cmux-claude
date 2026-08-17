#!/usr/bin/env bash
# Installs the session-orchestration scripts (spawn/tell/sessions/att/unspawn/new-worktree)
# and the role-tab injection hook that the Micromanage/Planner/Todo standing tabs rely on.
# A dependency of those three, not usually picked on its own.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

have jq || { err "jq is required (brew install jq)."; exit 1; }

for f in spawn.sh tell.sh sessions.sh att.sh unspawn.sh session-lib.sh session-role.sh new-worktree.sh cleanup-worktrees.sh; do
  link_into "scripts/$f" "scripts/$f"
  chmod +x "$CLAUDE_DIR/scripts/$f"
done

mkdir -p "$CLAUDE_DIR/roles"
merge_session_start_hook "$CLAUDE_DIR/scripts/session-role.sh"

ok "orchestration scripts installed to ~/.claude/scripts/"
log "  To call spawn/tell/sessions/att/unspawn (and ccw) by name, install the ${c_bold}shell${c_reset}"
log "  component (adds zsh functions + completion). Or add the dir to your PATH:"
log "    ${c_dim}echo 'export PATH=\"\$HOME/.claude/scripts:\$PATH\"' >> ~/.zshrc${c_reset}"
