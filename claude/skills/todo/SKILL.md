---
name: todo
description: Maintain a rolling personal follow-up list stored at ~/.config/cmux-claude/todos.md, and open a local dashboard to view/check off/edit it. Use when the user wants to add a todo, see their outstanding follow-ups, mark something done, or open their todo list/dashboard.
---

# Todo

A rolling follow-up list, stored as plain markdown **outside** this skill folder so
sharing the skill never leaks anyone's personal list, and so the optional
[daily-recap](../daily-recap/SKILL.md) add-on can feed it without a second copy.

## Storage

```bash
bash scripts/config.sh todos-path   # -> ~/.config/cmux-claude/todos.md (override: $CMUXCLAUDE_TODOS)
```

The file doesn't need to exist yet — treat a missing file as an empty list. Format is a
flat markdown checklist, one item per line, open items on top:

```
# Todos

- [ ] Confirm the migration plan with Alex · added 2026-08-10 · effort M
- [ ] Rotate the staging API key · added 2026-08-14 · effort S
- [x] Ship the invoice PDF fix · added 2026-08-05 · effort S · done 2026-08-06
```

- Every item gets `· added YYYY-MM-DD` when it's created, and `· done YYYY-MM-DD`
  appended right after when it's checked off. Tag order: `added`, `effort`, `done`,
  then any free-text notes.
- `· effort S/M/L` is your best guess (S = quick, M = a real chunk of work, L = a
  project) — a reasonable guess is enough, the user can correct it later (in chat, or
  by clicking the effort badge in the dashboard).
- Completed items stay in the file (flipped to `- [x]`, never deleted) — the dashboard
  and any "what's outstanding" answer just filter what's shown (see below).

## Adding / completing items

- **New follow-up** (from chat, a meeting, an idea): append a `- [ ] text · added
  YYYY-MM-DD · effort S/M/L` line, matching the existing lines' format. Guess the
  effort yourself.
- **Marking something done** via chat: flip `- [ ]` to `- [x]` and append `· done
  YYYY-MM-DD` right after the `effort` tag (or right after `added` if there's no
  effort tag yet) — don't just tell the user to go click it.

## Showing the list

**In chat** ("what's outstanding", "what's on my list"): read the file back grouped
by effort (S → M → L, unestimated last), not dumped verbatim. Flag any open item
whose `added` date is more than 7 days old.

**As a page** (the user asks to *see*/*open* the list): start the local dashboard and
open it — it's idempotent, safe to call every time:

```bash
bash scripts/todos-server.sh   # prints http://127.0.0.1:8943/todos.html, starts the
                                # server if it isn't already running
```

Then `open <the URL it printed>`. It's a small static page (`scripts/todos.html`)
backed by a local Python server (`scripts/todos-server.py`, same folder) that
reads/writes `todos.md` directly on disk — the page just `fetch()`s it, so it loads
and saves with zero manual steps and no browser file permission involved. It already
sorts by effort and flags anything older than 7 days; checking a box or clicking the
effort badge saves straight back to the file.

**Must be served over `http://localhost`, not opened as a bare `file://` path** —
that's what `todos-server.sh` is for. Don't publish this as a hosted Artifact either:
artifacts have no local-filesystem access, so a hosted page can't save a checkbox
click back to `todos.md`.

## Notes

- This skill only writes `todos.md` — it never touches anything else on disk, and
  makes no network calls of its own.
- If [daily-recap](../daily-recap/SKILL.md) is also installed, its recap step proposes
  additions/completions here but always asks before writing — this skill's own
  add/complete flow above is always synchronous with the user's request, no
  confirmation step needed.
