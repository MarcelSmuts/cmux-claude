#!/usr/bin/env bash
# Installs the PLANNER standing-role tab brief (plan-and-orchestrate, don't implement)
# plus the session-orchestration scripts it drives (spawn/tell/sessions/att/unspawn).
set -uo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

bash "$(dirname "${BASH_SOURCE[0]}")/install_orchestration.sh"

link_into "roles/planner.md" "roles/planner.md"

ok "planner role installed"

# The planner plans and orchestrates rather than writing code, so it runs on fable by
# default (the workers it spawns default to opus — see spawn.sh). Override with
# PLANNER_MODEL, or PLANNER_MODEL= to launch on the settings.json default.
PLANNER_MODEL="${PLANNER_MODEL-fable}"
PLANNER_CMD="claude"; [ -n "$PLANNER_MODEL" ] && PLANNER_CMD="claude --model $PLANNER_MODEL"

log ""
log "${c_bold}Standing tab:${c_reset} a pinned cmux tab named ${c_bold}PLANNER${c_reset} running Claude"
log "on the ${c_bold}${PLANNER_MODEL:-settings.json default}${c_reset} model, in your project's repo"
log "(unlike Micromanage/Todo, this one is project-specific)."
DEFAULT_DIR="$HOME"
git -C "$PWD" rev-parse --git-dir >/dev/null 2>&1 && DEFAULT_DIR="$PWD"
create_standing_tab "PLANNER" "$DEFAULT_DIR" "$PLANNER_CMD"

log ""
log "Need more than one planner? With the ${c_bold}shell${c_reset} component installed,"
log "${c_bold}planner <name> [<repo-path>]${c_reset} opens a ${c_bold}PLANNER: <name>${c_reset} tab anchored to a repo,"
log "on the planner model, with the same brief. A planner lists its own spawned workers"
log "with ${c_bold}sessions.sh --mine${c_reset}."
