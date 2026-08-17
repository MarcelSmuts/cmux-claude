#!/usr/bin/env bash
# Installs the micromanage skill (session-status table + local dashboard UI) and its
# standing-role tab brief.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

have jq   || { err "jq is required (brew install jq)."; exit 1; }
have node || warn "node wasn't found — the interactive dashboard (scripts/ui.sh) needs it; the plain-text table still works without it."

bash "$(dirname "${BASH_SOURCE[0]}")/install_orchestration.sh"

link_into "skills/micromanage" "skills/micromanage"
link_into "roles/micromanage.md" "roles/micromanage.md"

ok "micromanage installed"
log ""
log "${c_bold}Standing tab:${c_reset} a pinned cmux tab named ${c_bold}MICROMANAGE${c_reset} running Claude — the"
log "SessionStart hook greets it with its role automatically. It's project-agnostic, so"
log "any directory works (default: your home directory)."
create_standing_tab "MICROMANAGE" "$HOME"
log ""
log "Or use it ad hoc any time, from any session: ${c_dim}bash ~/.claude/skills/micromanage/scripts/ui.sh${c_reset}"
