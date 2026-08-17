#!/usr/bin/env bash
# Installs the daily-recap add-on to the todo skill: full standup recap across
# whichever sources the user picks, plus support for their own custom sources.
set -uo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

have jq || { err "jq is required (brew install jq)."; exit 1; }

if [ ! -d "$CLAUDE_DIR/skills/todo" ]; then
  log "daily-recap is an add-on to the todo skill — installing that first."
  bash "$(dirname "${BASH_SOURCE[0]}")/install_todo.sh"
fi

link_into "skills/daily-recap" "skills/daily-recap"
chmod +x "$CLAUDE_DIR/skills/daily-recap/scripts/"*.sh

CONFIG_SH="$CLAUDE_DIR/skills/todo/scripts/config.sh"

log ""
log "${c_bold}Which sources should the daily recap pull from?${c_reset} (each needs its own"
log "access already set up — a Claude-managed connector for Calendar/Wispr Flow, the"
log "\`gh\` CLI logged in for GitHub, a Slack MCP server for Slack.)"
log ""

declare -a KEYS=(github slack calendar wispr claude_sessions)
declare -a LABELS=(
  "GitHub — PRs, commits, reviews (needs the gh CLI, logged in)"
  "Slack — sent/mentioned messages + your Later list (needs a Slack MCP server)"
  "Google Calendar — the day's meetings (needs the Calendar connector)"
  "Wispr Flow — recorded-meeting transcripts + scratchpad notes (needs the Wispr Flow connector)"
  "Local Claude Code sessions on this machine (no setup needed)"
)
SELECTED=()
for i in "${!KEYS[@]}"; do
  if confirm "Enable ${LABELS[$i]}?" "y"; then
    SELECTED+=("${KEYS[$i]}")
  fi
done
SOURCES="$(IFS=,; echo "${SELECTED[*]}")"

if [ -z "$SOURCES" ]; then
  warn "no sources selected — daily-recap will have nothing to pull until you re-run"
  warn "\`bash ~/.claude/skills/todo/scripts/config.sh init --sources <list> --force\`"
fi

log ""
if confirm "Add a custom source of your own (a freeform instruction the recap will follow)?" "n"; then
  CUSTOM_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/cmux-claude/custom-sources.md"
  mkdir -p "$(dirname "$CUSTOM_FILE")"
  read -r -p "Source name (e.g. 'Linear tickets'): " CS_NAME </dev/tty
  read -r -p "Instructions for pulling that day's activity from it: " CS_INSTR </dev/tty
  if [ -n "$CS_NAME" ] && [ -n "$CS_INSTR" ]; then
    { echo ""; echo "## $CS_NAME"; echo ""; echo "$CS_INSTR"; } >> "$CUSTOM_FILE"
    ok "added '$CS_NAME' to $CUSTOM_FILE — add more any time by editing that file directly"
  fi
fi

# Identity fields: reuse whatever the todo skill's config already has (github_login,
# timezone, etc.); only sources needs setting/updating here. `init --force` preserves
# unspecified fields (see config.sh), so this never blanks out an existing config.
GH_LOGIN="$(gh api user --jq .login 2>/dev/null || true)"
TZ_DETECT=""
[ -L /etc/localtime ] && TZ_DETECT="$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')"
bash "$CONFIG_SH" init --github-login "$GH_LOGIN" --timezone "$TZ_DETECT" --sources "$SOURCES" --force >/dev/null

ok "daily-recap installed — sources: ${SOURCES:-none}"
if [[ ",$SOURCES," == *,slack,* ]]; then
  warn "Slack needs your Slack user id — first time you run a recap, read it from any"
  warn "Slack MCP tool's own description and save it: bash ~/.claude/skills/todo/scripts/config.sh init --slack-id U... --force"
fi
log ""
log "Ask any Claude session: \"give me my daily recap\" (or \"quick recap\" for the fast,"
log "summary-only mode). It reads/writes the same list as the TODO tab."
