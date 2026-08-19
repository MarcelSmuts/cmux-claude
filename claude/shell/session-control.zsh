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
#   planner [claude args…]               relaunch Claude here on the planner model
#   planner <name> [<repo-path>]         open a new "PLANNER: <name>" tab in a repo
#
# Thin wrappers over ~/.claude/scripts/*.sh — the scripts hold the logic and work
# from any shell; these just save you typing `bash ~/.claude/scripts/…`. Plain POSIX
# function syntax, so sourcing this from bash works too.
spawn()    { bash "$HOME/.claude/scripts/spawn.sh"    "$@"; }
tell()     { bash "$HOME/.claude/scripts/tell.sh"     "$@"; }
sessions() { bash "$HOME/.claude/scripts/sessions.sh" "$@"; }
att()      { bash "$HOME/.claude/scripts/att.sh"      "$@"; }
unspawn()  { bash "$HOME/.claude/scripts/unspawn.sh"  "$@"; }

# planner — plan-and-orchestrate sessions on the planner model (fable by default;
# PLANNER_MODEL overrides, PLANNER_MODEL= for the settings.json default — the same
# resolution as install_planner.sh). Two forms:
#
#   planner                 Relaunch Claude in place on the planner model — run this
#   planner -<flag>…        inside your pinned PLANNER tab to restart Claude there
#                           without the model regressing to the settings.json default.
#                           Extra args pass through to claude; the role brief is loaded
#                           from the *tab title*, not from this command.
#   planner <name> [path]   Open a NEW cmux tab titled "PLANNER: <name>" in <path>
#                           (default: the current repo), with Claude on the planner
#                           model. No worktree — a planner sits in the repo's main
#                           checkout so it can see .scratch/ and stay on the default
#                           branch. Doesn't steal focus; reach it with
#                           `tell "PLANNER: <name>" "…"` / `att "PLANNER: <name>"`.
planner() {
  case "${1-}" in
    ''|-*)
      [ -n "${PLANNER_MODEL-fable}" ] && set -- --model "${PLANNER_MODEL-fable}" "$@"
      claude "$@"
      ;;
    *)
      _planner_name="$1"; shift
      _planner_dir="${1:-$PWD}"
      _planner_model="${PLANNER_MODEL-fable}"
      # Pass the resolved model explicitly so spawn's opus default doesn't apply; when
      # PLANNER_MODEL is empty, hand spawn SPAWN_MODEL= so it too uses the settings default.
      if [ -n "$_planner_model" ]; then
        bash "$HOME/.claude/scripts/spawn.sh" "PLANNER: $_planner_name" --dir "$_planner_dir" --model "$_planner_model"
      else
        SPAWN_MODEL= bash "$HOME/.claude/scripts/spawn.sh" "PLANNER: $_planner_name" --dir "$_planner_dir"
      fi
      unset _planner_name _planner_dir _planner_model
      ;;
  esac
}
