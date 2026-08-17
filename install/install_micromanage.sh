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
log "${c_bold}To make it a standing tab:${c_reset} in cmux, open a new tab, rename it (exactly) ${c_bold}MICROMANAGE${c_reset},"
log "start Claude in it, and pin the tab. The SessionStart hook will greet it with its role"
log "automatically whenever a Claude session starts there — see roles/micromanage.md."
log "Or use it ad hoc any time, from any session: ${c_dim}bash ~/.claude/skills/micromanage/scripts/ui.sh${c_reset}"
