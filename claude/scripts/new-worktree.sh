#!/bin/bash

# new-worktree.sh — create an isolated, ready-to-use git worktree off the repo's
# fresh default branch.
#
# The setup counterpart to cleanup-worktrees.sh. One command gives you a worktree with:
#   - a new branch off the latest base (the repo's default branch unless --base is given)
#   - node_modules available (symlinked from the main checkout by default; --install for npm ci)
#   - .env copied from the main checkout
# so tsc / mocha / the pre-push hook all run immediately.
#
# Worktrees live under <main-repo>/.claude/worktrees/<branch> (a gitignored path),
# which is where review-pr and cleanup-worktrees already look.
#
# Usage:
#   new-worktree.sh <branch-name>
#   new-worktree.sh <branch-name> --base origin/some-branch
#   new-worktree.sh <branch-name> --install      # npm ci in the worktree instead of symlinking
#
# Run from the main repo or any worktree.

set -uo pipefail

BRANCH=""
BASE=""
BASE_EXPLICIT=0
INSTALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --base)    BASE="${2:-}"; BASE_EXPLICIT=1; shift ;;
        --install) INSTALL=1 ;;
        --help|-h) sed -n '3,24p' "$0"; exit 0 ;;
        -*)        echo "Unknown flag: $1" >&2; exit 2 ;;
        *)
            if [ -z "$BRANCH" ]; then
                BRANCH="$1"
            else
                echo "Unexpected extra argument: $1" >&2; exit 2
            fi
            ;;
    esac
    shift
done

if [ -z "$BRANCH" ]; then
    echo "No branch name given. Usage: new-worktree.sh <branch-name> [--base <ref>] [--install]" >&2
    exit 2
fi

# Resolve the main checkout, regardless of whether we are run from it or a worktree.
# --git-common-dir points at the main repo's .git for both; its parent is the main checkout.
COMMON="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)"
if [ -z "$COMMON" ]; then
    echo "Not inside a git checkout." >&2
    exit 1
fi
MAIN_REPO="$(dirname "$COMMON")"
cd "$MAIN_REPO"

# Default the base to the repo's own default branch (main vs master vs ...), so this
# works in any repo without needing --base. An explicit --base always wins.
if [ "$BASE_EXPLICIT" -eq 0 ]; then
    HEAD_REF="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
    if [ -n "$HEAD_REF" ]; then
        BASE="$HEAD_REF"
    else
        BASE="origin/master"
        for _c in main master; do
            if git show-ref --verify --quiet "refs/remotes/origin/$_c"; then BASE="origin/$_c"; break; fi
        done
    fi
fi

# Refresh from origin so the worktree starts at the latest commit. Handle both
# origin/-qualified refs and bare branch names (e.g. --base main): when the base
# names a branch origin has, fetch it and start from the fresh origin/<branch>,
# never a possibly-stale local branch of the same name. A local-only branch or a
# raw SHA (fetch fails) is left as-is.
case "$BASE" in
    origin/*)
        git fetch origin "${BASE#origin/}" -q \
            || echo "⚠️  Could not fetch ${BASE} — using the local ref." >&2
        ;;
    *)
        if git fetch origin "$BASE" -q 2>/dev/null; then
            BASE="origin/$BASE"
        fi
        ;;
esac

if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
    echo "Base ref '$BASE' does not exist. Pass an existing ref with --base." >&2
    exit 1
fi

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "Branch '$BRANCH' already exists. Pick a new name or remove it first." >&2
    exit 1
fi

WT="$MAIN_REPO/.claude/worktrees/$BRANCH"
if [ -e "$WT" ]; then
    echo "Worktree path already exists: $WT" >&2
    exit 1
fi

mkdir -p "$MAIN_REPO/.claude/worktrees"
git worktree add -b "$BRANCH" "$WT" "$BASE"

# Provide node_modules. Symlinking from the main checkout is fast and, because
# node_modules is gitignored, costs no disk. Fall back to npm ci when the
# dependency lock differs from main (a symlink would then give the wrong deps).
# Portable variant: only touch node deps when the repo is actually a Node project.
if [ ! -f "$MAIN_REPO/package.json" ]; then
    :  # not a Node repo — nothing to provide
elif [ "$INSTALL" -eq 1 ]; then
    echo "📦 npm ci (forced)…"
    ( cd "$WT" && npm ci )
elif [ ! -e "$MAIN_REPO/node_modules" ]; then
    echo "⚠️  Main checkout has no node_modules — running npm ci in the worktree."
    ( cd "$WT" && npm ci )
elif ! cmp -s "$MAIN_REPO/package-lock.json" "$WT/package-lock.json"; then
    echo "⚠️  package-lock.json differs from the main checkout — running npm ci so deps match this branch."
    ( cd "$WT" && npm ci )
else
    ln -s "$MAIN_REPO/node_modules" "$WT/node_modules"
    # A bare node_modules symlink shows as untracked (the .gitignore patterns are
    # directory-only), which would make this worktree look dirty and stop
    # cleanup-worktrees from ever removing it. Exclude it locally.
    EXCLUDE="$(git -C "$WT" rev-parse --git-path info/exclude 2>/dev/null)"
    if [ -n "$EXCLUDE" ] && [ -w "$EXCLUDE" ] && ! grep -qxF '/node_modules' "$EXCLUDE" 2>/dev/null; then
        printf '/node_modules\n' >> "$EXCLUDE"
    fi
    echo "🔗 Symlinked node_modules from the main checkout"
fi

if [ -f "$MAIN_REPO/.env" ]; then
    cp "$MAIN_REPO/.env" "$WT/.env"
    echo "📋 Copied .env"
fi

echo ""
echo "✅ Worktree ready: $WT"
echo "   Branch '$BRANCH' off $BASE"
echo ""
echo "Next: cd \"$WT\""
