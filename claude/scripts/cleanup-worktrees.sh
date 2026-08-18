#!/usr/bin/env bash

# cleanup-worktrees.sh — remove git worktrees whose work appears to be done:
#   - Backing branch's PR is MERGED or CLOSED on GitHub, OR
#   - Backing branch is fully merged into origin/master (or origin/main)
#
# The teardown counterpart to new-worktree.sh; both operate on the worktrees under
# <main-repo>/.claude/worktrees/. Run from the main repo (not from inside a worktree).
#
# Safe-by-default:
#   - Never touches the main worktree
#   - Skips removal if the worktree has uncommitted changes — reports it instead
#   - Skips removal if both PR-state and merged-into-base checks are inconclusive
#   - If gh is unavailable, falls back to merged-into-base check only

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
MAIN_WORKTREE="$REPO_ROOT"

cd "$MAIN_WORKTREE" || exit 1

# Always start by pruning git's internal references to deleted worktrees
git worktree prune

# Determine the base branch ref to use for the "merged into base" check
BASE_REF=""
if git rev-parse --verify --quiet origin/master >/dev/null; then
    BASE_REF="origin/master"
elif git rev-parse --verify --quiet origin/main >/dev/null; then
    BASE_REF="origin/main"
fi

HAS_GH=0
if command -v gh >/dev/null 2>&1; then
    HAS_GH=1
fi

if [ "$HAS_GH" -eq 0 ] && [ -z "$BASE_REF" ]; then
    echo "Neither gh CLI nor origin/master|main is available — cannot determine cleanup safety. Aborting."
    exit 1
fi

REMOVED=0
KEPT=0
DIRTY=0
INCONCLUSIVE=0

# Collect worktree info into a temp file so the while-read loop runs in the
# current shell (counters survive). Each line: <path>\t<head>\t<branch_ref>
TMP_LIST=$(mktemp)
trap 'rm -f "$TMP_LIST"' EXIT

git worktree list --porcelain | awk '
    /^worktree /  { path = substr($0, 10); head = ""; branch = ""; next }
    /^HEAD /      { head = $2; next }
    /^branch /    { branch = $2; next }
    /^detached$/  { next }
    /^bare$/      { path = ""; next }
    /^$/          { if (path && head) print path "\t" head "\t" branch; path = ""; head = ""; branch = ""; next }
    END           { if (path && head) print path "\t" head "\t" branch }
' > "$TMP_LIST"

while IFS=$'\t' read -r wt_path wt_head wt_branch_ref; do
    [ -n "$wt_path" ] || continue
    if [ "$wt_path" = "$MAIN_WORKTREE" ]; then
        continue
    fi
    if [ ! -d "$wt_path" ]; then
        continue
    fi

    if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
        echo "⚠️  Dirty worktree — skipping: $wt_path"
        DIRTY=$((DIRTY + 1))
        continue
    fi

    branch_name="${wt_branch_ref#refs/heads/}"

    decision=""
    reason=""

    if [ "$HAS_GH" -eq 1 ] && [ -n "$branch_name" ]; then
        pr_info=$(gh pr list --head "$branch_name" --state all --limit 1 --json number,state 2>/dev/null || echo "")
        if [ -n "$pr_info" ] && [ "$pr_info" != "[]" ]; then
            pr_state=$(echo "$pr_info" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
            pr_number=$(echo "$pr_info" | grep -o '"number":[0-9]*' | head -1 | cut -d':' -f2)
            case "$pr_state" in
                MERGED|CLOSED)
                    decision="remove"
                    reason="PR #${pr_number} is ${pr_state}"
                    ;;
                OPEN|DRAFT)
                    decision="keep"
                    reason="PR #${pr_number} is ${pr_state}"
                    ;;
            esac
        fi
    fi

    if [ -z "$decision" ] && [ -n "$BASE_REF" ]; then
        if git merge-base --is-ancestor "$wt_head" "$BASE_REF" 2>/dev/null; then
            decision="remove"
            reason="HEAD is merged into ${BASE_REF}"
        fi
    fi

    case "$decision" in
        remove)
            echo "🗑  Removing worktree (${reason}): $wt_path"
            git worktree remove --force "$wt_path"
            REMOVED=$((REMOVED + 1))
            ;;
        keep)
            echo "✓  Keeping worktree (${reason}): $wt_path"
            KEPT=$((KEPT + 1))
            ;;
        *)
            echo "❓ Inconclusive (no PR found and not merged into base) — keeping: $wt_path"
            INCONCLUSIVE=$((INCONCLUSIVE + 1))
            ;;
    esac
done < "$TMP_LIST"

echo ""
echo "Cleanup summary: removed=$REMOVED, kept=$KEPT, dirty-skipped=$DIRTY, inconclusive=$INCONCLUSIVE"
