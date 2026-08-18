#!/usr/bin/env bash
# micromanage.sh — list the Claude Code CLI sessions running RIGHT NOW, each with
# its cmux tab name, working state and whether it needs your attention.
#
# How each session is identified:
#   cmux launches Claude with `--session-id <uuid>`, and that uuid IS the transcript
#   filename. So `ps` gives an exact pid → transcript mapping, and `cmux top
#   --processes` walks pid → surface → pane → workspace for the tab name. Sessions
#   started by hand (no --session-id in argv) fall back to a per-project
#   most-recently-touched-transcript heuristic — honest best effort, see the caveats
#   in SKILL.md.
#
# Output (TSV, for the skill to render):
#   PROCS<TAB><n>                  # count of live claude processes
#   <state> <idle_secs> <project> <branch> <tab> <last_assistant_text>
# states: working | waiting-for-you | needs-permission | stalled | error | unknown
#
# With --json: one object { procs, sessions: [...] } instead, each session carrying
# the same fields plus `ws` (the cmux workspace title att/tell/unspawn address it by,
# empty when the session isn't in an addressable tab), `pid` and `file` (its
# transcript). That's what the interactive UI in ../server/ consumes.
#
# Scope: local Claude *Code* CLI sessions on THIS machine. Not claude.ai web/desktop
#        chats, not subagent transcripts.
#
# NOT `set -e`: a title-less/edge transcript makes a grep or jq exit non-zero, and under
# `set -e` that failing command-substitution would abort the whole scan.
set -uo pipefail

JSON=0
for a in "$@"; do
  case "$a" in
    --json) JSON=1 ;;
    --help|-h) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "micromanage: unknown flag: $a" >&2; exit 2 ;;
  esac
done

ROOT="$HOME/.claude/projects"
NOW=$(date +%s)
WINDOW_MIN=20160    # candidate transcripts touched in the last 14 days, for the fallback
                    # path only. A find() perf guard, NOT a liveness test: PROCS is the
                    # truth for what's live. A tab left open idle for days still has a live
                    # process, so its transcript must survive to be classified.
PENDING_IDLE=90     # a pending tool_use idle beyond this ⇒ likely a permission prompt
STALL_IDLE=300      # a tool_result tail idle beyond this ⇒ assistant never continued
SNIPPET=400         # chars of the last assistant message handed to the skill to summarise

command -v jq >/dev/null 2>&1 || { echo "micromanage: jq is required" >&2; exit 3; }

# Both output shapes are written from the same internal rows; the TSV form drops the
# columns only the UI has a use for.
emit() {
  local n="$1" rows="${2:-/dev/null}"
  if [ "$JSON" -eq 1 ]; then
    jq -Rn --argjson procs "${n:-0}" '
      { procs: $procs,
        sessions: [ inputs | split("\t")
                    | { state: .[0], idle: (.[1] | tonumber), project: .[2], branch: .[3],
                        tab: .[4], ws: .[5], pid: .[6], file: .[7], cwd: .[8],
                        last: (.[9] // ""),
                        active: ((.[10] // "0") | tonumber) } ] }' < "$rows"
  else
    printf 'PROCS\t%s\n' "${n:-0}"
    [ -s "$rows" ] && cut -f1-5,10 "$rows"
  fi
  return 0
}

[ -d "$ROOT" ] || { emit 0; exit 0; }

CMUX="${CMUX_BUNDLED_CLI_PATH:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
command -v "$CMUX" >/dev/null 2>&1 || CMUX="$(command -v cmux 2>/dev/null)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pidsf="$tmp/pids"        # pid \t session-id-or-"-"
cwdf="$tmp/cwds"         # one line per unresolved process, its cwd
tabf="$tmp/tabs"         # pid \t tab title
usedf="$tmp/used"        # transcripts already claimed
rowsf="$tmp/rows"

# ── 1. live claude CLI processes, with the session id cmux launched them with ────────
#    argv0's BASENAME is "claude": catches a bare `claude` and a full-path launch alike,
#    while excluding the desktop app (capitalised "Claude") and node/python MCP subprocs.
#    cmux launches with --session-id on a fresh tab and --resume once the tab has been
#    reopened; both carry the uuid that names the transcript.
ps -Awwo pid=,args= \
  | awk '{ n=split($2,a,"/"); if (a[n] != "claude") next
           sid="-"
           for (i=3;i<=NF;i++)
             if (($i=="--session-id" || $i=="--resume") && (i+1)<=NF) sid=$(i+1)
           print $1 "\t" sid }' > "$pidsf"
nprocs=$(grep -c . "$pidsf" || true)
[ "${nprocs:-0}" -gt 0 ] || { emit "$nprocs"; exit 0; }

# ── 2. pid → cmux tab (workspace) name ───────────────────────────────────────────────
#    `cmux top` emits a flat parent-linked tree (kind, ref, parent, label). A Claude pid
#    surfaces on several rows and only one of them is truthful: its `:tag:claude_code`
#    row hangs straight off the owning workspace, while its surface rows include stale
#    entries pointing at tabs it never ran in. So take the workspace from the tag row,
#    and accept a surface row only if it walks up to that same workspace.
#    A workspace can hold more than one Claude surface, so when two sessions land on the
#    same tab the surface's own name is appended to keep the rows distinguishable.
if [ -n "$CMUX" ]; then
  "$CMUX" top --all --processes --format tsv 2>/dev/null | awk -F'\t' '
    function wsof(r,   n) {
      while (r != "" && kind[r] != "workspace" && n++ < 12) r = parent[r]
      return (kind[r] == "workspace") ? r : ""
    }
    { if ($4 != "process") { parent[$5]=$6; label[$5]=$7; kind[$5]=$4 }
      if ($4=="process" && $7=="claude.exe") {
        pids[$5]=1
        if ($6 ~ /:tag:claude_code$/) tagof[$5]=$6
        else if ($6 ~ /^surface:/) surfs[$5]=surfs[$5] " " $6
      } }
    END {
      for (p in pids) {
        w = (p in tagof) ? wsof(tagof[p]) : ""
        n = split(surfs[p], cand, " ")
        surf=""
        for (i=1; i<=n; i++) {
          sw = wsof(cand[i])
          if (sw == "") continue
          if (w == "") w = sw            # no tag row — trust the first surface that resolves
          if (sw == w && surf == "") surf = label[cand[i]]
        }
        if (w != "" && label[w] != "") { tab[p]=label[w]; sfx[p]=surf; count[label[w]]++ }
      }
      for (p in tab) {
        gsub(/^[^[:alnum:]]+/, "", sfx[p])
        print p "\t" tab[p] ((count[tab[p]] > 1 && sfx[p] != "") ? " \xe2\x80\xba " sfx[p] : "")
      }
    }' > "$tabf"
fi
tab_of() { awk -F'\t' -v p="$1" '$1==p{print $2; exit}' "$tabf" 2>/dev/null; }

: > "$usedf"; : > "$cwdf"; : > "$rowsf"

# ── 3. classify one transcript ───────────────────────────────────────────────────────
#    args: transcript, mtime, cwd, tab-title, pid → appends one row to $rowsf
classify() {
  local F="$1" mt="$2" cwd="$3" tab="$4" pid="${5:-}"
  local idle=$(( NOW - mt )) active role stop kinds is_err state branch proj last ws jqcwd

  # One jq per transcript for everything the row needs: on macOS a process spawn costs
  # ~30ms, so with a tab per branch open the spawn count IS the runtime.
  IFS=$'\t' read -r active role stop kinds is_err branch jqcwd last < <(
    tail -n 400 "$F" | jq -sr --argjson n "$SNIPPET" '
      # A slash command, the echo of one, and the summary a compaction leaves behind are
      # all written as user records, and none of them is a turn anyone is waiting on.
      # Counting them makes a finished session look like it owes a reply.
      def synthetic:
        (.isMeta // false)
        or ( ( [ (.message.content // [])
                 | if type=="string" then .
                   elif type=="array" then (.[] | select(.type=="text") | .text)
                   else empty end ] | join(" ") )
             | test("^\\s*(<(local-command-|command-name|command-message|command-args)|This session is being continued from a previous conversation|/[a-z][a-z0-9-]*\\s*$)") );

      [ .[] | select(.type=="assistant" or .type=="user")
            | select(.type=="assistant" or (synthetic | not)) ] as $t
      | ($t[-1] // {}) as $l
      | [ $t[] | select(.type=="assistant")
              | (.message.content // []) | if type=="array" then .[] else empty end
              | select(.type=="text") | .text ] as $a
      | [ $t[] | select(.type=="user") | .message.content
              | if type=="string" then . else (if type=="array" then (.[] | select(.type=="text") | .text) else empty end) end ] as $u
      | [ (([ $t[] | .timestamp // empty ] | last // "")
            | if . == "" then 0 else ((.[0:19]+"Z") | fromdateiso8601) end),
          ($l.type // "-"),
          ($l.message.stop_reason // "-"),
          ([ ($l.message.content // []) | if type=="array" then .[].type else "text" end ] | join(",")),
          ([ ($l.message.content // []) | if type=="array" then .[] else empty end
             | select(.type=="tool_result") | .is_error ] | any),
          ([ .[] | .gitBranch // empty ] | last // ""),
          ([ .[] | .cwd // empty ] | last // ""),
          ((($a[-1] // $u[-1]) // "") | gsub("\\s+"; " ") | .[0:$n])
        ] | @tsv' 2>/dev/null)
  role="${role:-unknown}"
  [ -n "$cwd" ] && [ "$cwd" != "?" ] || cwd="${jqcwd:-?}"

  # Age off the last real turn, not the file's mtime: something appends pr-link and mode
  # records to an idle transcript for days afterwards, which resets mtime and hides a
  # session that has been sitting untouched since Tuesday.
  case "$active" in
    ''|*[!0-9]*) ;;
    *) [ "$active" -gt 0 ] && idle=$(( NOW - active )) ;;
  esac
  [ "$idle" -lt 0 ] && idle=0

  case "$role" in
    assistant)
      if [ "$stop" = "end_turn" ] || ! printf '%s' "$kinds" | grep -q tool_use; then
        state="waiting-for-you"
      elif [ "$idle" -ge "$PENDING_IDLE" ]; then
        state="needs-permission"
      else
        state="working"
      fi ;;
    user)
      # last turn is a tool_result or a user prompt the assistant hasn't answered yet.
      if [ "$is_err" = "true" ] && [ "$idle" -ge 60 ]; then state="error"
      elif [ "$idle" -ge "$STALL_IDLE" ]; then state="stalled"
      else state="working"; fi ;;
    *) state="unknown" ;;
  esac

  # only a real cmux tab is addressable by att/tell/unspawn, and only under its
  # workspace title — strip the " › surface" disambiguator two sessions in one tab get.
  ws="${tab%% › *}"

  # tab name is the header; fall back to what Claude called the session, then the cwd.
  if [ -z "$tab" ]; then
    tab=$(grep -m1 '"type":"ai-title"' "$F" | jq -r '.aiTitle // empty' 2>/dev/null)
  fi

  # a worktree under <repo>/.claude/worktrees/<x> still belongs to <repo>
  proj=$(basename "${cwd%%/.claude/worktrees/*}")

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$state" "$idle" "$proj" "${branch:-?}" "${tab:-$proj}" "$ws" "$pid" "$F" "$cwd" "${last:-}" "${active:-0}" >> "$rowsf"
}

transcript_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# cwd rides on every conversational record, so read the tail rather than scanning the
# file — the fallback pass probes candidates one by one and only cares about the last.
transcript_cwd() {
  local line
  line=$(tail -n 40 "$1" 2>/dev/null | grep '"cwd":"[^"]' | tail -n1)
  printf '%s' "$line" | jq -r '.cwd // empty' 2>/dev/null
}

# ── 4. exact path: pid's --session-id names its transcript ───────────────────────────
#    One index for every pid: ~/.claude/projects is big enough that a find per process
#    dominated the runtime.
idxf="$tmp/index"
find "$ROOT" -maxdepth 2 -name '*.jsonl' -not -path '*/subagents/*' 2>/dev/null > "$idxf"

while IFS=$'\t' read -r pid sid; do
  F=""
  if [ "$sid" != "-" ]; then
    F=$(grep -m1 -F "/$sid.jsonl" "$idxf")
  fi
  if [ -z "$F" ]; then
    # unresolved (hand-launched, or the session was resumed under a different id) —
    # remember its cwd so the fallback pass can account for it.
    lsof -a -d cwd -p "$pid" 2>/dev/null \
      | awk 'NR>1{p=$9; for(i=10;i<=NF;i++)p=p" "$i; print p}' >> "$cwdf"
    continue
  fi
  printf '%s\n' "$F" >> "$usedf"
  mt=$(transcript_mtime "$F"); [ -n "$mt" ] || continue
  classify "$F" "$mt" "" "$(tab_of "$pid")" "$pid"
done < "$pidsf"

# ── 5. fallback: per unresolved project, take its N most-recently-touched transcripts ─
if [ -s "$cwdf" ]; then
  candf="$tmp/cands"; takenf="$tmp/taken"; : > "$takenf"
  if stat -f %m "$ROOT" >/dev/null 2>&1; then STATFMT=(-f '%m %N'); else STATFMT=(-c '%Y %n'); fi

  # Newest first, from ONE stat call. Reading each candidate's cwd is the expensive
  # part, so the loop below probes in recency order and stops the moment every
  # unresolved process has a transcript — normally after a handful of files.
  find "$ROOT" -name '*.jsonl' -not -path '*/subagents/*' -mmin "-$WINDOW_MIN" -print0 2>/dev/null \
    | xargs -0 stat "${STATFMT[@]}" 2>/dev/null | sort -rn > "$candf"

  need=$(grep -c . "$cwdf")
  while read -r mt F; do
    [ -n "$F" ] || continue
    grep -qxF "$F" "$usedf" && continue
    # LAST (not first) cwd: a session resumed in a new dir — e.g. relocated into a
    # worktree — keeps its original cwd on early lines; the tail reflects where it
    # runs now, which is what lsof reports for the live process, so it buckets right.
    cwd=$(transcript_cwd "$F"); [ -n "$cwd" ] || continue
    want=$(grep -cxF "$cwd" "$cwdf"); [ "$want" -gt 0 ] || continue
    [ "$(grep -cxF "$cwd" "$takenf")" -lt "$want" ] || continue
    printf '%s\n' "$cwd" >> "$takenf"
    classify "$F" "$mt" "$cwd" "" ""
    [ "$(grep -c . "$takenf")" -lt "$need" ] || break
  done < "$candf"
fi

emit "$nprocs" "$rowsf"
