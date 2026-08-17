# session-control — spawn / tell / sessions / att / unspawn: open, direct, list,
# focus and tear down Claude Code tabs from anywhere. Companion to ccw; shares its
# worktree paths and cmux workspaces, so ccw and these reach the same tabs.
#
#   spawn <branch> ["first instruction"] [--base X] [--install] [--dir PATH]
#                                        open a new tab (+ worktree), no focus steal
#   tell  <branch> "instruction" [--force]           type an instruction into a tab
#   sessions                             list the open tabs
#   att   <branch>                       focus a tab (switch away to leave it running)
#   unspawn <branch> [--keep-worktree] [--force]
#                                        close the tab + remove the worktree/branch
#
# Thin wrappers over ~/.claude/scripts/*.sh — the scripts hold the logic and work
# from any shell; these just save you typing `bash ~/.claude/scripts/…`. Plain POSIX
# function syntax, so sourcing this from bash works too.
spawn()    { bash "$HOME/.claude/scripts/spawn.sh"    "$@"; }
tell()     { bash "$HOME/.claude/scripts/tell.sh"     "$@"; }
sessions() { bash "$HOME/.claude/scripts/sessions.sh" "$@"; }
att()      { bash "$HOME/.claude/scripts/att.sh"      "$@"; }
unspawn()  { bash "$HOME/.claude/scripts/unspawn.sh"  "$@"; }
