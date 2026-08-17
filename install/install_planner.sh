#!/usr/bin/env bash
# Installs the PLANNER standing-role tab brief (plan-and-orchestrate, don't implement)
# plus the session-orchestration scripts it drives (spawn/tell/sessions/att/unspawn).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

bash "$(dirname "${BASH_SOURCE[0]}")/install_orchestration.sh"

link_into "roles/planner.md" "roles/planner.md"

ok "planner role installed"
warn "edit ~/.claude/roles/planner.md and replace <PROJECT NAME — edit this> with your project."
log ""
log "${c_bold}To make it a standing tab:${c_reset} in cmux, open a tab in your project's repo,"
log "rename it (exactly) ${c_bold}PLANNER${c_reset}, start Claude in it, and pin the tab."
