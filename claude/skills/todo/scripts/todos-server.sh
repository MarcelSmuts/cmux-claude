#!/usr/bin/env bash
# Ensures the local todos server (todos-server.py, same folder) is running, then prints
# its URL. That server reads/writes todos.md directly on the machine, so the browser
# needs no filesystem permission of its own — just localhost, which is why the page
# must be served, not opened as a bare file:// path.
#
# Usage: bash scripts/todos-server.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8943
LOG="/tmp/todos-server.log"
URL="http://127.0.0.1:$PORT/todos.html"

if ! curl -s --max-time 2 -o /dev/null "$URL"; then
  ( nohup python3 "$SCRIPT_DIR/todos-server.py" </dev/null >"$LOG" 2>&1 & disown )
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl -s --max-time 2 -o /dev/null "$URL" && break
    sleep 0.3
  done
fi

echo "$URL"
