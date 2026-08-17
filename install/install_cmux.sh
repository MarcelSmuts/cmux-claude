#!/usr/bin/env bash
# Installs the cmux app itself (a Ghostty-based terminal with vertical tabs built for
# running AI coding agents side by side — https://www.cmux.dev/), via Homebrew cask.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

if [ -d "/Applications/cmux.app" ] || have cmux; then
  ok "cmux is already installed"
  exit 0
fi

have brew || { err "Homebrew is required to install cmux. Install it from https://brew.sh, then re-run."; exit 1; }

log "cmux isn't installed. Installing via: brew install --cask cmux"
brew install --cask cmux
ok "cmux installed — launch it from /Applications once to finish setup (login, permissions)."
