#!/usr/bin/env bash
# Installs the standalone todo skill (rolling list + local dashboard, no external
# service dependency) and its standing-role tab brief.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

have python3 || { err "python3 is required (backs the todo dashboard's local server)."; exit 1; }

bash "$(dirname "${BASH_SOURCE[0]}")/install_orchestration.sh"

link_into "skills/todo" "skills/todo"
link_into "roles/todo.md" "roles/todo.md"
chmod +x "$CLAUDE_DIR/skills/todo/scripts/"*.sh "$CLAUDE_DIR/skills/todo/scripts/"*.py

ok "todo skill installed"
log ""
log "${c_bold}Standing tab:${c_reset} a pinned cmux tab named ${c_bold}TODO${c_reset} running Claude — project-agnostic,"
log "so any directory works (default: your home directory)."
create_standing_tab "TODO" "$HOME"
log ""
log "Open the dashboard any time: ${c_dim}bash ~/.claude/skills/todo/scripts/todos-server.sh${c_reset}"
log ""
log "Want the full standup recap (GitHub/Slack/calendar/meetings) feeding this list"
log "automatically? Run this installer again and add the ${c_bold}daily-recap${c_reset} add-on."
