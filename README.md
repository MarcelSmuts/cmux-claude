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
- **Shell integration** — a zsh layer giving you `ccw` (open/focus one cmux tab per
  git worktree, with tab completion) and `spawn`/`tell`/`sessions`/`att`/`unspawn` as
  plain commands, sourced from your `~/.zshrc`
- **Statusline** — a one-line Claude Code status line showing the model plus
  cumulative session tokens, cost, and context-window usage; the context figure
  turns yellow with a 😫 once usage passes 20%

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

> **Installing or driving this from an AI agent?** See [`llms.txt`](llms.txt) — an
> execute-top-to-bottom runbook that front-loads the non-obvious traps (the bash-4+
> requirement, and the cmux socket-control password setup an agent needs before it can
> spawn or pin tabs non-interactively).

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
comment header in each script for usage. To call them by name (`spawn feature-x "..."`
instead of `bash ~/.claude/scripts/spawn.sh ...`), install the **Shell integration**
component below, or add `~/.claude/scripts` to your `PATH`.

## Shell integration (zsh)

The **Shell integration** component symlinks two files into `~/.claude/shell/` and
adds a fenced block to your `~/.zshrc` that sources them (backing the rc up once):

- `ccw <branch>` — the interactive front door: create the worktree if needed
  (`~/.claude/scripts/new-worktree.sh`), open **one cmux tab per worktree** running
  Claude, and focus it; `ccw <branch>` again refocuses. `ccw` with no args lists open
  tabs, `ccw --list` lists this repo's worktrees (● = open tab), and `ccw --prune`
  removes finished ones (`~/.claude/scripts/cleanup-worktrees.sh`). `ccw <TAB>`
  completes existing worktree names.
- `spawn` / `tell` / `sessions` / `att` / `unspawn` — thin function wrappers over the
  orchestration scripts, so you don't type `bash ~/.claude/scripts/…`. These are plain
  POSIX functions, so they also work if you source the file from bash; `ccw` and its
  completion are zsh-only.

The component pulls in the orchestration scripts automatically (you don't need to pick
Planner too). Open a new terminal, or `source ~/.zshrc`, to pick the commands up.

## Components

| Component | What it installs | Depends on |
| --- | --- | --- |
| **cmux** | `brew install --cask cmux` | Homebrew |
| **cmux hooks** | `cmux hooks setup` | cmux installed |
| **Micromanage** | `skills/micromanage/`, `roles/micromanage.md` | `jq`, `node` (for the dashboard) |
| **Planner** | `roles/planner.md`, orchestration scripts | `jq` |
| **Shell integration** | `shell/*.zsh`, a sourced block in `~/.zshrc`, orchestration scripts | `jq`, zsh |
| **Statusline** | `statusline.sh`, a `statusLine` entry in `settings.json` | `jq` |
| **Todo** | `skills/todo/`, `roles/todo.md`, orchestration scripts | `jq`, `python3` (for the dashboard) |
| **Daily Recap** | `skills/daily-recap/` | Todo; `gh` CLI / Slack MCP / Calendar & Wispr Flow connectors, per source you enable |

Picking Micromanage, Planner, Todo, or Shell integration also installs the shared
orchestration scripts (`spawn`/`tell`/`sessions`/`att`/`unspawn`, plus
`new-worktree.sh` / `cleanup-worktrees.sh`) and the `SessionStart` role-injection hook
— you don't need to select those separately.

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
`settings.json.pre-cmux-claude.bak` the first time this repo touches it). To remove the
shell integration, delete the fenced `# >>> cmux-claude shell integration >>>` block
from `~/.zshrc` (a backup is left at `~/.zshrc.pre-cmux-claude.bak`). To remove the
statusline, delete `~/.claude/statusline.sh` and the `statusLine` block from
`~/.claude/settings.json`.

## Requirements

- macOS (cmux itself is macOS-only)
- **bash 4+ to run `install.sh`** — it uses associative arrays, which stock macOS bash
  3.2 lacks; `brew install bash` and run it under that if `./install.sh` fails to parse
- [Homebrew](https://brew.sh) — for installing cmux
- `jq` — used by the role-injection hook, the statusline, and settings.json merges
- `node` — only if you install Micromanage (its dashboard)
- `python3` — only if you install Todo (its dashboard's local server)
