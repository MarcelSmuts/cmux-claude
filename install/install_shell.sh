#!/usr/bin/env bash
# Installs the zsh shell integration: the `ccw` worktree-tab command (with tab
# completion) plus `spawn`/`tell`/`sessions`/`att`/`unspawn` convenience functions,
# sourced from your ~/.zshrc so they're available in every shell. Pulls in the
# orchestration scripts they drive (installs them if not already present).
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

bash "$(dirname "${BASH_SOURCE[0]}")/install_orchestration.sh"

link_into "shell/claude-worktrees.zsh" "shell/claude-worktrees.zsh"
link_into "shell/session-control.zsh" "shell/session-control.zsh"

# Wire the source block into ~/.zshrc, idempotently. Marked with a fence so a later
# uninstall (or re-run) can find it; backs the rc up once before the first edit.
RC="${ZDOTDIR:-$HOME}/.zshrc"
BEGIN="# >>> cmux-claude shell integration >>>"
END="# <<< cmux-claude shell integration <<<"

if [ -f "$RC" ] && grep -qF "$BEGIN" "$RC"; then
  ok "shell integration already sourced from $RC"
else
  [ -f "$RC" ] && cp "$RC" "$RC.pre-cmux-claude.bak"
  {
    echo ""
    echo "$BEGIN"
    echo "# ccw + spawn/tell/sessions/att/unspawn. compinit is needed for ccw's completion."
    echo 'whence compdef >/dev/null 2>&1 || { autoload -Uz compinit && compinit -i; }'
    echo 'for _f in "$HOME/.claude/shell/claude-worktrees.zsh" "$HOME/.claude/shell/session-control.zsh"; do'
    echo '  [ -f "$_f" ] && source "$_f"'
    echo 'done; unset _f'
    echo "$END"
  } >> "$RC"
  if [ -f "$RC.pre-cmux-claude.bak" ]; then
    ok "added shell integration to $RC (backup at $RC.pre-cmux-claude.bak)"
  else
    ok "created $RC with the shell integration"
  fi
fi

ok "shell integration installed"
log ""
log "Open a new terminal (or ${c_dim}source $RC${c_reset}) to get:"
log "  ${c_bold}ccw${c_reset} <branch>         open/focus a worktree tab (Tab-completes existing worktrees)"
log "  ${c_bold}spawn${c_reset} <branch> \"…\"    open a worktree tab without stealing focus"
log "  ${c_bold}tell${c_reset} <branch> \"…\"     send an instruction to a tab"
log "  ${c_bold}sessions${c_reset}             list open tabs   ·   ${c_bold}att${c_reset} <branch> focus one"
log "  ${c_bold}unspawn${c_reset} <branch>     close a tab + remove its worktree"
