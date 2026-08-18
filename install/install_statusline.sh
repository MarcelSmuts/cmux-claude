#!/usr/bin/env bash
# Installs the Claude Code statusline: a one-line status (model, cumulative session
# tokens, cost, context-window usage) shown at the bottom of every session. Symlinks the
# script into ~/.claude/ and points settings.json's statusLine at it.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

have jq || { err "jq is required (the statusline parses Claude Code's JSON with it)."; exit 1; }

link_into "statusline.sh" "statusline.sh"
chmod +x "$CLAUDE_DIR/statusline.sh"
merge_statusline "$CLAUDE_DIR/statusline.sh"

ok "statusline installed"
log ""
log "Restart your Claude Code sessions (or start a new one) to see it. The context"
log "figure turns ${c_yellow}yellow${c_reset} with a 😫 once usage passes 20%."
