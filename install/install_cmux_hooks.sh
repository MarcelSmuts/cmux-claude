#!/usr/bin/env bash
# Runs cmux's own `hooks setup`, which wires cmux's sidebar (git status, PR state, port
# detection, notifications) into Claude Code and any other supported CLI agent on PATH.
# This is cmux integrating with the agents, not something this repo ships — cmux must
# already be installed.
set -uo pipefail
# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

CMUX_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"
have cmux && CMUX_BIN="cmux"
[ -x "$CMUX_BIN" ] || CMUX_BIN="$(command -v cmux 2>/dev/null || true)"

if [ -z "$CMUX_BIN" ] || [ ! -x "$CMUX_BIN" ]; then
  err "cmux isn't installed yet — install it first (this installer's cmux step)."
  exit 1
fi

log "Running: cmux hooks setup"
"$CMUX_BIN" hooks setup --yes
ok "cmux hooks installed for every supported agent found on PATH"
