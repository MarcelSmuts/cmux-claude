#!/usr/bin/env bash
# Shared config store for the todo skill and the optional daily-recap add-on, so
# identity is set ONCE, not re-derived each run.
#
# Location: $CMUXCLAUDE_CONFIG, else ${XDG_CONFIG_HOME:-$HOME/.config}/cmux-claude/config
# It lives OUTSIDE the skill folder on purpose — sharing the skill never leaks a user's
# identity, and each person who installs it gets their own config on first run.
#
# The rolling todo list (todos.md) lives next to the config, for the same reason.
# Resolve its path with `config.sh todos-path` — override with $CMUXCLAUDE_TODOS.
#
# Format: simple KEY=VALUE lines (sourceable):
#   github_login=...
#   slack_user_id=...
#   timezone=...            # IANA name, e.g. Europe/London ("" = use the machine's local tz)
#   calendar_id=primary
#   sources=...             # comma list enabled for daily-recap, e.g. github,claude_sessions
#                            # (empty/unset if daily-recap isn't installed — the todo skill
#                            # alone never reads this field)
#
# Commands:
#   config.sh get      # print config (KEY=VALUE); exit 1 if not configured yet
#   config.sh detect   # print auto-detectable values (github_login, timezone) for first-run prefill
#   config.sh path        # print the config file path
#   config.sh todos-path  # print the rolling todo-list file path (todos.md, next to the config)
#   config.sh sources     # print the enabled daily-recap sources, comma-separated (empty if none/not set)
#   config.sh init --github-login X --slack-id Y --timezone Z [--calendar-id C] [--sources S] [--force]
set -uo pipefail

CONFIG="${CMUXCLAUDE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cmux-claude/config}"
TODOS="${CMUXCLAUDE_TODOS:-$(dirname "$CONFIG")/todos.md}"
cmd="${1:-get}"; shift 2>/dev/null || true

case "$cmd" in
  path) echo "$CONFIG" ;;

  todos-path) echo "$TODOS" ;;

  sources)
    [ -f "$CONFIG" ] && (. "$CONFIG"; echo "${sources:-}") || echo "" ;;

  get)
    [ -f "$CONFIG" ] || { echo "not configured — no file at $CONFIG (run: config.sh init ...)" >&2; exit 1; }
    cat "$CONFIG" ;;

  detect)  # everything the shell can find on its own; Slack id must come from the MCP tool description
    echo "github_login=$(gh api user --jq .login 2>/dev/null || true)"
    tz=""
    command -v timedatectl >/dev/null 2>&1 && tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    [ -z "$tz" ] && [ -L /etc/localtime ] && tz="$(readlink /etc/localtime | sed 's#.*/zoneinfo/##')"
    [ -z "$tz" ] && tz="${TZ:-}"
    echo "timezone=$tz" ;;

  init)
    # Preload existing values so re-running init to change ONE field (e.g. daily-recap's
    # installer setting --sources) doesn't blank out the others.
    github_login=""; slack_user_id=""; timezone=""; calendar_id="primary"; sources=""
    [ -f "$CONFIG" ] && . "$CONFIG"
    login="$github_login" slack="$slack_user_id" tz="$timezone" cal="$calendar_id" src="$sources"
    force=0
    while [ $# -gt 0 ]; do case "$1" in
      --github-login) login="${2:-}"; shift 2 ;;
      --slack-id)     slack="${2:-}"; shift 2 ;;
      --timezone)     tz="${2:-}"; shift 2 ;;
      --calendar-id)  cal="${2:-}"; shift 2 ;;
      --sources)      src="${2:-}"; shift 2 ;;
      --force)        force=1; shift ;;
      *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac; done
    [ -f "$CONFIG" ] && [ "$force" -eq 0 ] && { echo "config already exists at $CONFIG (use --force to overwrite)" >&2; exit 1; }
    mkdir -p "$(dirname "$CONFIG")"
    { echo "github_login=$login"
      echo "slack_user_id=$slack"
      echo "timezone=$tz"
      echo "calendar_id=$cal"
      echo "sources=$src"
    } > "$CONFIG"
    echo "wrote $CONFIG" >&2
    cat "$CONFIG" ;;

  *) echo "usage: config.sh {get|detect|path|todos-path|sources|init [--github-login X --slack-id Y --timezone Z --calendar-id C --sources S --force]}" >&2; exit 2 ;;
esac
