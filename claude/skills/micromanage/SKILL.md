---
name: micromanage
description: Show every Claude Code CLI session running right now — one line each — with what it's working on and whether it needs your attention (waiting for a reply, a permission prompt, stalled, or errored). Use when the user asks to check/list their running or open Claude sessions, wants a session status breakdown, asks which sessions need action or are stuck, or mentions "micromanage", "my sessions", "open sessions", or "running claude sessions".
---

# Micromanage

Surveys the Claude Code CLI sessions live on this machine and reports, per session, **what it's doing** and **whether it needs you**. Read-only — it never touches any session.

## Run it

```bash
bash scripts/micromanage.sh
```

One `PROCS<TAB>n` header (count of live `claude` processes), then one TSV row per session:
`state · idle_seconds · project · branch · tab · last_message`.

## Or open the interactive UI

```bash
bash scripts/ui.sh          # --stop to shut it down, --url to print without opening
```

A localhost page: a board of cards grouped by what each session wants from you (a click,
an answer, a look, nothing, or reclaiming), carrying its pending ask, its `away_summary`,
the evidence of its work (tests, typecheck, edits, pushes) and its PRs with CI and review
state. Filters narrow to what wants you, what is ready to merge, what has red CI, and what
is ready to close (every PR it opened has landed, so the tab and worktree are reclaimable).
It re-scans every few seconds on its own.

Reading and replying happen in the tab, so the page is deliberately read-only bar one
action: double-click a card to go to its tab, and **×** to unspawn a finished one. Each card
also carries **↻** and **↓**: PR state rides slow sweeps (a couple of minutes while checks
move, half an hour once they settle), so ↻ asks GitHub about that card's PRs right now, and
↓ parks the card until its session does something new (↑ to bring it back).

Run this instead of the table when the user asks to *open* micromanage or wants a UI. It starts the server on first use
and re-opens the same one after that, so it's safe to run repeatedly. The page is
localhost-only and token-gated; the URL it prints carries the token.

`tab` is the cmux tab (workspace) name — what the user sees in the tab bar. `last_message` is a raw ~400-char excerpt of the session's last assistant turn; it is **input, not output** — see below.

## States → what to tell the user

Map each row's state to a plain-language action. Emoji + phrasing:

| state | means | action |
| --- | --- | --- |
| `working` | actively generating or running a tool (recent write) | ✅ none — let it run |
| `waiting-for-you` | finished its turn, sitting at the prompt | ⏳ respond / continue / close |
| `needs-permission` | a tool has been pending a while — **either** a permission prompt **or** a genuinely long-running tool (indistinguishable from the transcript) | 🔐 switch to it and check |
| `stalled` | last activity was a user message / tool result with nothing since (>5m) | 💤 likely interrupted or stuck — check |
| `error` | last tool result errored and wasn't handled | ⚠️ investigate |
| `unknown` | couldn't classify the tail | 👀 glance at it |

For `waiting-for-you`, let the **idle** time sharpen the advice: a couple of minutes = it's genuinely waiting on you; hours = probably done, suggest closing it.

## Rendering

Table columns, in order: **State · Idle · Project/Branch · Tab · To do**.

- **State** is the emoji only (✅/⏳/🔐/💤/⚠️/👀) — no word. Keep the word in prose (summary line, judgment notes) so it's still unambiguous, just not in the table cell.
- Print a one-line legend directly above the table, only for states actually present in this run: `✅ Working | ⏳ Waiting | 🔐 Needs permission | 💤 Stalled | ⚠️ Error | 👀 Unknown`.
- **Project/Branch** merges the two into one cell, e.g. `my-api / fix-invoice-total-sign`. If project and branch are identical or branch is uninformative (e.g. `HEAD`), just show the project.
- Convert `idle_seconds` to a compact age (`45s`, `12m`, `2h`).
- **Tab** is the tab name verbatim. A `Workspace › Surface` value means that tab holds two Claude sessions.
- **To do** is yours to write: read `last_message` and compress it to **the single next action the user owes that tab**, ≤ 6 words, no trailing period ("approve worktree switch", "answer: rebase or merge?", "nothing — let it run"). Never paste the excerpt through. If it's genuinely unclear what's wanted, write "unclear — open it".
- Present the table sorted by urgency (needs-permission / error / stalled first, then waiting-for-you by idle, then working last).
- **Reconcile the count:** if `PROCS n` exceeds the number of rows, say so — the extras are sessions with no activity in the last 12h (a fresh session sitting at its first prompt, or one idle beyond the window). If rows ≥ `n`, don't claim more are running than there are processes.
- End with a one-line **needs-you** summary (e.g. "2 waiting on you, 1 stalled; the rest are working or idle").

## Judgment to add on top

The script reports mechanical state; you add the insight it can't:
- **Duplicate / overlapping work** — two sessions on the same slice or file. Flag it.
- **Backend/frontend pairs** — a backend + frontend session on the same feature; note they belong together.
- Only surface these when the tab names actually warrant it. Don't invent connections.

## Caveats (state them if they matter)

- Scope is local **Claude Code CLI** sessions only — not claude.ai web/desktop chats, not subagents.
- Sessions cmux launched are pinned to their transcript exactly (via the `--session-id` in their argv) and to their tab (via `cmux top`). A session started by hand has neither, so it falls back to per-project most-recently-active transcripts and shows the project name in place of a tab — there, a just-closed transcript can occasionally stand in for a quieter live one.
- `needs-permission` vs a slow tool is genuinely ambiguous from the transcript — present it as "check it", not a certainty.
