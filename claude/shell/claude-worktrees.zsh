# ccw — "Claude Code Worktree": open one cmux TAB per worktree. Each Claude runs as a
# workspace in cmux, named after its branch, so it shows in your tab bar and survives
# the terminal closing or a VS Code reload. Refocus any time with ccw <branch>.
#
#   ccw <branch>            create/open worktree <branch>, focus its Claude tab
#   ccw <branch> --base X   pass through to new-worktree.sh (branch off ref X)
#   ccw <branch> --install  pass through (npm ci instead of symlinking node_modules)
#   ccw                     list the open Claude tabs
#   ccw --list              list this repo's worktrees (● = open tab)
#   ccw --prune             remove finished worktrees (via cleanup-worktrees.sh)
#
# Leave a tab without killing it: select another tab or close the terminal — the
# workspace and Claude keep running. To end one: exit Claude in the tab, or
# `unspawn <branch>`.
#
# The zsh companion to spawn/tell/sessions/att/unspawn: same model (a cmux workspace
# whose custom_title is <branch>, running Claude in <main-repo>/.claude/worktrees/<branch>),
# so all of them address the same tabs by branch name. Worktree creation is delegated to
# ~/.claude/scripts/new-worktree.sh; pruning to ~/.claude/scripts/cleanup-worktrees.sh.
# Env: CCW_LAUNCH_CMD (default: claude), CCW_NO_ATTACH=1 (open the tab but don't focus it).

# Echo "<window-id>\t<workspace-ref>" for the cmux tab named $1 (empty if none).
_ccw_find() {
  emulate -L zsh
  local branch="$1" w hit
  export CMUX_QUIET=1
  for w in ${(f)"$(cmux --json list-windows 2>/dev/null | jq -r '.[].id')"}; do
    hit="$(cmux --json list-workspaces --window "$w" 2>/dev/null \
            | jq -r --arg B "$branch" --arg W "$w" \
                '.workspaces[] | select(.has_custom_title and .custom_title == $B) | "\($W)\t\(.ref)"' | head -n1)"
    [[ -n "$hit" ]] && { print -r -- "$hit"; return 0; }
  done
  return 1
}

ccw() {
  emulate -L zsh
  local root main wt branch launch line win ref out common
  launch="${CCW_LAUNCH_CMD:-claude}"
  export CMUX_QUIET=1

  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ccw: not inside a git repository" >&2; return 1; }

  # Resolve the MAIN checkout even when called from inside a worktree.
  common="$(git rev-parse --git-common-dir 2>/dev/null)"
  case "$common" in /*) ;; *) common="$PWD/$common" ;; esac
  main="$(cd "$(dirname "$common")" && pwd)"

  # Subcommands: list worktrees / prune finished ones.
  case "$1" in
    --list | -l)
      local wtdir="$main/.claude/worktrees" _l _p _n
      echo "worktrees (● = open tab):"
      for _l in ${(f)"$(git -C "$main" worktree list --porcelain 2>/dev/null)"}; do
        [[ "$_l" == worktree\ * ]] || continue
        _p="${_l#worktree }"
        [[ "$_p" == "$wtdir/"* ]] || continue
        _n="${_p#$wtdir/}"
        if [[ -n "$(_ccw_find "$_n")" ]]; then echo "  ● $_n"; else echo "    $_n"; fi
      done
      return
      ;;
    --prune)
      local cw="$HOME/.claude/scripts/cleanup-worktrees.sh"
      if [[ -x "$cw" ]]; then
        (cd "$main" && bash "$cw")
      else
        echo "ccw: cleanup-worktrees.sh not found at ~/.claude/scripts/ — install the Planner/orchestration component" >&2
        return 1
      fi
      return
      ;;
  esac

  # No branch: list the open tabs.
  if [[ -z "$1" ]]; then
    bash "$HOME/.claude/scripts/sessions.sh"
    return
  fi

  branch="$1"; shift
  wt="$main/.claude/worktrees/$branch"

  # Create the worktree if it isn't there yet.
  if [[ -d "$wt" ]]; then
    echo "ccw: reusing worktree $wt"
  else
    bash "$HOME/.claude/scripts/new-worktree.sh" "$branch" "$@" || return 1
  fi

  cmux ping >/dev/null 2>&1 || { echo "ccw: cmux app isn't running — open cmux first" >&2; return 1; }

  # Reuse the existing tab or open a new one (launching Claude).
  line="$(_ccw_find "$branch")"
  if [[ -n "$line" ]]; then
    echo "ccw: refocusing tab '$branch'"
    win="${line%%$'\t'*}"; ref="${line##*$'\t'}"
  else
    out="$(cmux new-workspace --name "$branch" --cwd "$wt" --command "$launch" --focus true 2>&1)" \
      || { echo "ccw: cmux new-workspace failed: $out" >&2; return 1; }
    ref="workspace:${${out##*workspace:}%%[^0-9]*}"
    echo "ccw: opened tab '$branch'"
    line="$(_ccw_find "$branch")"; win="${line%%$'\t'*}"
  fi

  [[ -n "$CCW_NO_ATTACH" ]] && return
  [[ -n "$win" ]] && cmux focus-window --window "$win" >/dev/null 2>&1
  [[ -n "$ref" ]] && cmux select-workspace --workspace "$ref" >/dev/null 2>&1
}

# Tab-completion: `ccw <TAB>` offers existing worktree names + subcommands.
_ccw() {
  (( CURRENT == 2 )) || return 0
  local common main wtdir _l _p
  common="$(git rev-parse --git-common-dir 2>/dev/null)" || return 0
  [[ "$common" = /* ]] || common="$PWD/$common"
  main="${common:h}"
  wtdir="$main/.claude/worktrees"
  local -a names
  for _l in ${(f)"$(git -C "$main" worktree list --porcelain 2>/dev/null)"}; do
    [[ "$_l" == worktree\ * ]] || continue
    _p="${_l#worktree }"
    [[ "$_p" == "$wtdir/"* ]] || continue
    names+=("${_p#$wtdir/}")
  done
  compadd -- --list --prune
  compadd -a names
}
compdef _ccw ccw 2>/dev/null
