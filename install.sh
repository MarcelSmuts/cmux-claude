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

# Three parallel indexed arrays, not one associative array: macOS ships bash 3.2, which
# has no `declare -A`, and this installer is macOS-only — so it has to run under the
# system bash. Index i describes one component across all three: KEYS[i] names its
# install/install_<key>.sh, LABELS[i] is its menu text, SELECTED[i] is 0/1. The menu
# numbers users type are just i+1, so keep the three in the same order.
KEYS=(cmux cmux_hooks micromanage planner shell todo daily_recap)
LABELS=(
  "cmux — the terminal app itself (Homebrew cask, skip if already installed)"
  "cmux hooks setup — wires cmux's git/PR/port sidebar into Claude Code + other CLI agents"
  "Micromanage — session-status skill + standing tab + local dashboard"
  "Planner — standing plan-and-orchestrate tab (spawn/tell/sessions/att/unspawn)"
  "Shell integration — zsh ccw + spawn/tell/sessions/att/unspawn functions (sourced from ~/.zshrc)"
  "Todo — rolling follow-up list, standing tab + local dashboard"
  "Daily Recap — add-on to Todo: full standup recap (asks which sources)"
)
if [ "${#KEYS[@]}" -ne "${#LABELS[@]}" ]; then
  err "install.sh: KEYS and LABELS are out of sync (${#KEYS[@]} vs ${#LABELS[@]})."
  exit 1
fi
SELECTED=()
for i in "${!KEYS[@]}"; do SELECTED[i]=0; done

render() {
  log ""
  local i mark
  for i in "${!KEYS[@]}"; do
    mark=" "; [ "${SELECTED[i]}" = "1" ] && mark="x"
    printf '  %s[%s]%s %d) %s\n' "$c_bold" "$mark" "$c_reset" "$((i + 1))" "${LABELS[i]}"
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
      a|A) for i in "${!KEYS[@]}"; do SELECTED[i]=1; done ;;
      *)
        for n in $input; do
          [[ "$n" =~ ^[0-9]+$ ]] || continue
          idx=$((n - 1))
          if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#KEYS[@]}" ]; then continue; fi
          if [ "${SELECTED[idx]}" = "1" ]; then SELECTED[idx]=0; else SELECTED[idx]=1; fi
        done
        ;;
    esac
  done
else
  err "not running in a terminal — pass component flags instead, e.g.: ./install.sh --todo --micromanage"
  ANY=0
  for i in "${!KEYS[@]}"; do
    flag="--${KEYS[i]//_/-}"
    for a in "$@"; do [ "$a" = "$flag" ] && { SELECTED[i]=1; ANY=1; }; done
  done
  [ "$ANY" -eq 1 ] || exit 1
fi

CHOSEN=()
for i in "${!KEYS[@]}"; do [ "${SELECTED[i]}" = "1" ] && CHOSEN+=("$i"); done
[ "${#CHOSEN[@]}" -gt 0 ] || { log "nothing selected — exiting."; exit 0; }

NAMES=()
for i in "${CHOSEN[@]}"; do NAMES+=("${KEYS[i]}"); done
log ""
log "${c_bold}Installing:${c_reset} ${NAMES[*]}"
for i in "${CHOSEN[@]}"; do
  log ""
  log "${c_bold}── ${LABELS[i]}${c_reset}"
  bash "install/install_${KEYS[i]}.sh"
done

log ""
ok "done. Restart any open Claude Code session for new skills/roles to be picked up."
