# cmux-claude

[![CI](https://github.com/MarcelSmuts/cmux-claude/actions/workflows/ci.yml/badge.svg)](https://github.com/MarcelSmuts/cmux-claude/actions/workflows/ci.yml)
![Bash](https://img.shields.io/badge/bash-%E2%89%A54-4EAA25?logo=gnubash&logoColor=white)
![Zsh](https://img.shields.io/badge/zsh-supported-000000?logo=zsh&logoColor=white)
![Python](https://img.shields.io/badge/python-3-3776AB?logo=python&logoColor=white)
![macOS](https://img.shields.io/badge/platform-macOS-000000?logo=apple)
[![License: MIT](https://img.shields.io/github/license/MarcelSmuts/cmux-claude)](LICENSE)

A shareable setup for running [Claude Code](https://claude.com/claude-code) inside
[cmux](https://www.cmux.dev/), a Ghostty-based terminal with vertical tabs built for
running AI coding agents side by side. This repo packages:

- **cmux itself**, installed via Homebrew
- **cmux hooks** — cmux's own git/PR/port sidebar integration for Claude Code and
  other CLI agents
- **Three standing-tab skills**, each a permanent cmux tab with a fixed job:
  - **Micromanage** — a table (and local dashboard) of every Claude Code session
    running on your machine, what each is doing, and whether it needs you
  - **Planner** — a tab whose job is to plan and orchestrate (spawn worktree sessions
    for other tabs to implement), never to write code itself
  - **Todo** — a rolling personal follow-up list with its own local dashboard
- **Daily Recap** — an optional add-on to Todo: a full standup recap pulled from
  whichever sources you enable (GitHub, Slack, Google Calendar, Wispr Flow recorded
  meetings, local Claude Code sessions — or sources you define yourself)

Everything is **optional** — the installer is a checklist, and you only get what you
tick.

## Install

```bash
git clone https://github.com/MarcelSmuts/cmux-claude.git
cd cmux-claude
./install.sh
```

It walks you through a checklist, then symlinks the pieces you picked into
`~/.claude/` (so a later `git pull` here keeps them current) and merges the one shared
hook (`SessionStart`, for standing-tab role injection — see below) into
`~/.claude/settings.json`, backing up anything it would otherwise overwrite.

Not at a terminal, or want to skip the prompts? Pass flags instead:

```bash
./install.sh --micromanage --todo --daily-recap
```

## How the standing tabs work

Each standing-tab skill (Micromanage, Planner, Todo) ships a **role file** under
`~/.claude/roles/<name>.md`. A `SessionStart` hook
(`~/.claude/scripts/session-role.sh`) checks the cmux tab's title on every new Claude
Code session; if the title (lowercased, slugified) matches a role file, that file's
content is injected as context, so the session knows its standing job without you
re-explaining it every time.

To wire one up: in cmux, open a tab, rename it *exactly* to the role's name
(`MICROMANAGE`, `PLANNER`, or `TODO`), start Claude in it, and pin the tab so it stays
open. That's the whole mechanism — no cmux-side config beyond the tab title.

Each of the Micromanage/Planner/Todo installers offers to do this for you: if cmux is
running, it asks for a directory (Planner defaults to your current repo if you're in
one; Micromanage/Todo default to your home directory, since both are project-agnostic)
and, only on confirmation, creates the tab, starts Claude in it, and pins it — skipping
quietly (with the manual steps above printed instead) if cmux isn't running, a tab with
that title already exists, or you decline.

**Planner** also drives the session-orchestration scripts
(`~/.claude/scripts/spawn.sh`, `tell.sh`, `sessions.sh`, `att.sh`, `unspawn.sh`): spawn
a worktree session per plan slice, direct it, and tear it down when done. See the
comment header in each script for usage; add `~/.claude/scripts` to your `PATH` to run
them directly (`spawn feature-x "..."` instead of `bash
~/.claude/scripts/spawn.sh ...`).

## Components

| Component | What it installs | Depends on |
| --- | --- | --- |
| **cmux** | `brew install --cask cmux` | Homebrew |
| **cmux hooks** | `cmux hooks setup` | cmux installed |
| **Micromanage** | `skills/micromanage/`, `roles/micromanage.md` | `jq`, `node` (for the dashboard) |
| **Planner** | `roles/planner.md`, orchestration scripts | `jq` |
| **Todo** | `skills/todo/`, `roles/todo.md`, orchestration scripts | `jq`, `python3` (for the dashboard) |
| **Daily Recap** | `skills/daily-recap/` | Todo; `gh` CLI / Slack MCP / Calendar & Wispr Flow connectors, per source you enable |

Picking Micromanage, Planner, or Todo also installs the shared orchestration scripts
and the `SessionStart` role-injection hook — you don't need to select that separately.

## Daily Recap: sources

Daily Recap asks, at install time, which sources to pull from — each one needs its own
access already set up on your machine:

| Source | Needs |
| --- | --- |
| GitHub | `gh` CLI, logged in (`gh auth status`) |
| Slack | A Slack MCP server connected to this Claude Code session |
| Google Calendar | The Calendar connector (claude.ai-managed) |
| Wispr Flow | The Wispr Flow connector (claude.ai-managed) — recorded meetings + scratchpad notes |
| Local Claude Code sessions | Nothing — reads `~/.claude/projects` on this machine |

You can also add a **custom source**: a freeform instruction (a CLI command, an MCP
tool, a URL pattern) that the recap follows and folds into its own section. Add one
during install, or any time by editing `~/.config/cmux-claude/custom-sources.md`
directly — each `## Heading` is a new source.

Re-run `bash ~/.claude/skills/todo/scripts/config.sh init --sources <list> --force` any
time to change which sources are enabled without redoing the rest of your config.

## Uninstalling a piece

Every install step symlinks into `~/.claude/`, so removing one is: delete the symlink
(`rm ~/.claude/skills/<name>` / `rm ~/.claude/roles/<name>.md`). To remove the
`SessionStart` hook, edit `~/.claude/settings.json` (a pre-install backup is left at
`settings.json.pre-cmux-claude.bak` the first time this repo touches it).

## Requirements

- macOS (cmux itself is macOS-only)
- [Homebrew](https://brew.sh) — for installing cmux
- `jq` — used by the role-injection hook and settings.json merge
- `node` — only if you install Micromanage (its dashboard)
- `python3` — only if you install Todo (its dashboard's local server)
