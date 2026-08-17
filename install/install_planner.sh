#!/usr/bin/env bash
# Installs the PLANNER standing-role tab brief (plan-and-orchestrate, don't implement)
# plus the session-orchestration scripts it drives (spawn/tell/sessions/att/unspawn).
set -uo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

bash "$(dirname "${BASH_SOURCE[0]}")/install_orchestration.sh"

link_into "roles/planner.md" "roles/planner.md"

ok "planner role installed"
warn "edit ~/.claude/roles/planner.md and replace <PROJECT NAME — edit this> with your project."
log ""
log "${c_bold}Standing tab:${c_reset} a pinned cmux tab named ${c_bold}PLANNER${c_reset} running Claude, in your"
log "project's repo (unlike Micromanage/Todo, this one is project-specific)."
DEFAULT_DIR="$HOME"
git -C "$PWD" rev-parse --git-dir >/dev/null 2>&1 && DEFAULT_DIR="$PWD"
create_standing_tab "PLANNER" "$DEFAULT_DIR"
