#!/usr/bin/env bash
# ui.sh — open the micromanage UI: every live Claude session as a card, grouped by what it
# wants from you, carrying its pending ask, the evidence of its work and its PRs.
# Double-click a card to go to that tab; unspawn is the only action the page takes itself.
# Starts the local server on first use and re-opens the same one after that.
#
# Usage:
#   ui.sh [--port N] [--no-open] [--foreground] [--stop] [--url]
set -uo pipefail

DIR="$(cd "$(dirname "$0")/../server" && pwd)"
RUNTIME="$DIR/.runtime.json"
LOG="$DIR/.server.log"

PORT=""; OPEN=1; FG=0; STOP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --port)       PORT="${2:-}"; shift ;;
    --no-open)    OPEN=0 ;;
    --foreground) FG=1 ;;
    --stop)       STOP=1 ;;
    --url)        OPEN=0 ;;
    --help|-h)    sed -n '2,10p' "$0"; exit 0 ;;
    *)            echo "ui: unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v node >/dev/null 2>&1 || { echo "ui: node is required" >&2; exit 3; }

running_pid() { [ -f "$RUNTIME" ] && jq -r '.pid // empty' "$RUNTIME" 2>/dev/null; }
running_url() { [ -f "$RUNTIME" ] && jq -r '.url // empty' "$RUNTIME" 2>/dev/null; }
alive() { local p; p="$(running_pid)"; [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }

if [ "$STOP" -eq 1 ]; then
  if alive; then kill "$(running_pid)" && echo "ui: stopped"; else echo "ui: not running"; fi
  rm -f "$RUNTIME"; exit 0
fi

if ! alive; then
  rm -f "$RUNTIME"
  args=(--no-open); [ -n "$PORT" ] && args+=(--port "$PORT")
  if [ "$FG" -eq 1 ]; then
    exec node "$DIR/server.js" "${args[@]}"
  fi
  nohup node "$DIR/server.js" "${args[@]}" >"$LOG" 2>&1 &
  for _ in $(seq 1 40); do alive && [ -n "$(running_url)" ] && break; sleep 0.25; done
  alive || { echo "ui: server failed to start — see $LOG" >&2; tail -n 5 "$LOG" >&2; exit 1; }
fi

URL="$(running_url)"
[ -n "$URL" ] || { echo "ui: server is up but wrote no url — see $LOG" >&2; exit 1; }
echo "$URL"
[ "$OPEN" -eq 1 ] && open "$URL" >/dev/null 2>&1
exit 0
