#!/usr/bin/env bash
# install.sh — interactive installer for cmux-claude. Pick what you want; nothing
# happens for a component you don't select. Safe to re-run any time (every step is
# idempotent and backs up anything it would otherwise overwrite).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
# shellcheck source=lib/common.sh
. "lib/common.sh"

log "${c_bold}cmux-claude installer${c_reset}"
log "${c_dim}https://github.com/MarcelSmuts/cmux-claude${c_reset}"
log ""

if [ "$(uname -s)" != "Darwin" ]; then
  err "cmux is macOS-only today; this installer won't work on $(uname -s)."
  exit 1
fi

KEYS=(cmux cmux_hooks micromanage planner shell todo daily_recap)
declare -A LABEL=(
  [cmux]="cmux — the terminal app itself (Homebrew cask, skip if already installed)"
  [cmux_hooks]="cmux hooks setup — wires cmux's git/PR/port sidebar into Claude Code + other CLI agents"
  [micromanage]="Micromanage — session-status skill + standing tab + local dashboard"
  [planner]="Planner — standing plan-and-orchestrate tab (spawn/tell/sessions/att/unspawn)"
  [shell]="Shell integration — zsh ccw + spawn/tell/sessions/att/unspawn functions (sourced from ~/.zshrc)"
  [todo]="Todo — rolling follow-up list, standing tab + local dashboard"
  [daily_recap]="Daily Recap — add-on to Todo: full standup recap (asks which sources)"
)
declare -A SELECTED=()

render() {
  log ""
  local i=1
  for k in "${KEYS[@]}"; do
    local mark=" "; [ "${SELECTED[$k]:-0}" = "1" ] && mark="x"
    printf '  %s[%s]%s %d) %s\n' "$c_bold" "$mark" "$c_reset" "$i" "${LABEL[$k]}"
    i=$((i + 1))
  done
  log ""
  log "Type numbers to toggle (space-separated), 'a' for all, or Enter to install the selection."
}

if [ -t 0 ]; then
  while true; do
    render
    read -r -p "> " input </dev/tty
    case "$input" in
      "") break ;;
      a|A) for k in "${KEYS[@]}"; do SELECTED[$k]=1; done ;;
      *)
        for n in $input; do
          [[ "$n" =~ ^[0-9]+$ ]] || continue
          idx=$((n - 1))
          [ "$idx" -ge 0 ] && [ "$idx" -lt "${#KEYS[@]}" ] || continue
          k="${KEYS[$idx]}"
          if [ "${SELECTED[$k]:-0}" = "1" ]; then SELECTED[$k]=0; else SELECTED[$k]=1; fi
        done
        ;;
    esac
  done
else
  err "not running in a terminal — pass component flags instead, e.g.: ./install.sh --todo --micromanage"
  ANY=0
  for k in "${KEYS[@]}"; do
    flag="--${k//_/-}"
    for a in "$@"; do [ "$a" = "$flag" ] && { SELECTED[$k]=1; ANY=1; }; done
  done
  [ "$ANY" -eq 1 ] || exit 1
fi

CHOSEN=()
for k in "${KEYS[@]}"; do [ "${SELECTED[$k]:-0}" = "1" ] && CHOSEN+=("$k"); done
[ "${#CHOSEN[@]}" -gt 0 ] || { log "nothing selected — exiting."; exit 0; }

log ""
log "${c_bold}Installing:${c_reset} ${CHOSEN[*]}"
for k in "${CHOSEN[@]}"; do
  log ""
  log "${c_bold}── ${LABEL[$k]}${c_reset}"
  bash "install/install_${k}.sh"
done

log ""
ok "done. Restart any open Claude Code session for new skills/roles to be picked up."
