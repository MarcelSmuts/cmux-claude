#!/usr/bin/env bash
# Low-cost recap of Claude Code sessions active on a given local day.
# Reads only the small `ai-title` / `last-prompt` / `cwd` / `gitBranch` lines from each
# transcript — never the full conversation — so it's cheap regardless of session size.
# Scope: Claude *Code* CLI sessions stored under ~/.claude/projects on THIS machine.
#        It does NOT cover claude.ai web/desktop chats.
# Usage: claude-sessions.sh <YYYY-MM-DD>   (the target local day)
#
# NOTE: intentionally NOT `set -e`. A title-less session makes the ai-title grep exit 1,
# and under `set -e` that failing command-substitution would abort the whole read loop —
# silently dropping every session after the first one without an ai-title.
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: claude-sessions.sh <YYYY-MM-DD>" >&2; exit 2; }
D="$1"
# Exclusive upper bound (next local day). Support macOS (BSD) and Linux (GNU) date.
if date -v+1d +%Y-%m-%d >/dev/null 2>&1; then
  NEXT="$(date -j -v+1d -f "%Y-%m-%d" "$D" +%Y-%m-%d)" || { echo "invalid date: $D" >&2; exit 2; }
else
  NEXT="$(date -d "$D +1 day" +%Y-%m-%d)" || { echo "invalid date: $D" >&2; exit 2; }
fi
ROOT="$HOME/.claude/projects"

[ -d "$ROOT" ] || { echo "(no Claude sessions dir at $ROOT)"; exit 0; }

# Top-level session files only — exclude subagent transcripts (they're noise here).
find "$ROOT" -name '*.jsonl' -not -path '*/subagents/*' \
  -newermt "$D 00:00:00" ! -newermt "$NEXT 00:00:00" 2>/dev/null \
| while IFS= read -r F; do
    title=$(grep -m1 '"type":"ai-title"' "$F" | jq -r '.aiTitle // empty' 2>/dev/null)
    [ -z "$title" ] && title=$(grep -m1 '"type":"last-prompt"' "$F" | jq -r '(.lastPrompt[0:80]) // empty' 2>/dev/null)
    cwd=$(grep -m1 '"cwd":"' "$F" | jq -r '.cwd // empty' 2>/dev/null)
    branch=$(grep -m1 '"gitBranch":"[^"]' "$F" | jq -r '.gitBranch // empty' 2>/dev/null)
    proj=$(basename "${cwd:-unknown}")
    echo "- [$proj${branch:+ @$branch}] ${title:-(no title)}"
  done | sort -u
