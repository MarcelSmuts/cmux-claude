#!/usr/bin/env bash
# Resolves the "last working day" in the machine's LOCAL timezone and emits filter
# windows for the daily-recap skill.
#   Mon -> previous Fri, Sun -> Fri, Sat -> Fri, otherwise the previous calendar day.
# User- and timezone-agnostic: honours the local tz (incl. DST) via the system clock —
# the UTC offset is derived from the target date, not hardcoded.
# Works with both macOS (BSD) and Linux (GNU) `date`.
# Usage: day-window.sh [YYYY-MM-DD]   (reference "today"; defaults to system today)
set -uo pipefail

# Use the configured timezone if set (config.sh stores `timezone=`), else the machine's local tz.
CONFIG="${CMUXCLAUDE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cmux-claude/config}"
[ -f "$CONFIG" ] && . "$CONFIG"
[ -n "${CMUXCLAUDE_TZ:-${timezone:-}}" ] && export TZ="${CMUXCLAUDE_TZ:-$timezone}"

# Detect date flavour: BSD `date -v` succeeds; GNU does not.
if date -v-1d +%Y-%m-%d >/dev/null 2>&1; then FLAVOUR=bsd; else FLAVOUR=gnu; fi

_dow()     { [ "$FLAVOUR" = bsd ] && date -j -f "%Y-%m-%d" "$1" +%u          || date -d "$1" +%u; }
_weekday() { [ "$FLAVOUR" = bsd ] && date -j -f "%Y-%m-%d" "$1" +%A          || date -d "$1" +%A; }
_shift()   { [ "$FLAVOUR" = bsd ] && date -j -v"$2"d -f "%Y-%m-%d" "$1" +%Y-%m-%d || date -d "$1 $2 days" +%Y-%m-%d; }
_offset()  { [ "$FLAVOUR" = bsd ] && date -j -f "%Y-%m-%d" "$1" +%z          || date -d "$1" +%z; }
_epoch()   { [ "$FLAVOUR" = bsd ] && date -j -f "%Y-%m-%d %H:%M:%S" "$1" +%s || date -d "$1" +%s; }
_utc()     { [ "$FLAVOUR" = bsd ] && date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ     || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

if [ $# -ge 1 ]; then today="$1"; else today="$(date +%Y-%m-%d)"; fi

dow="$(_dow "$today")" || { echo "invalid date: $today" >&2; exit 2; }   # 1=Mon .. 7=Sun
case "$dow" in
  1) back="-3" ;;   # Mon -> Fri
  7) back="-2" ;;   # Sun -> Fri
  *) back="-1" ;;   # Tue-Sat -> previous day (Sat -> Fri)
esac

target="$(_shift "$today" "$back")"
start_ts="$(_epoch "$target 00:00:00")"
end_ts="$(_epoch "$target 23:59:59")"

off="$(_offset "$target")"            # local UTC offset for that date, e.g. +0200 (DST-aware)
off="${off:0:3}:${off:3:2}"           # -> +02:00

echo "TARGET_DATE=$target"
echo "TARGET_WEEKDAY=$(_weekday "$target")"
echo "LOCAL_OFFSET=$off"                                          # for calendar / gh range params
echo "SLACK_DATE=$target"                                         # Slack on: uses workspace TZ; use START_TS/END_TS for precision
echo "START_TS=$start_ts"                                         # Slack after:/before: epoch (absolute, tz-proof)
echo "END_TS=$end_ts"
echo "WINDOW_START_UTC=$(_utc "$start_ts")"                       # GitHub events filter (jq on created_at)
echo "WINDOW_END_UTC=$(_utc "$end_ts")"
echo "GH_RANGE=${target}T00:00:00${off}..${target}T23:59:59${off}"   # gh search --created / --author-date / "merged:"
