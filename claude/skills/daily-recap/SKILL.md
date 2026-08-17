---
name: daily-recap
description: Recap what the user did on their last working day across whichever sources are enabled (GitHub, Slack, Google Calendar, Wispr Flow recorded meetings, local Claude Code sessions, and any custom sources they've added), formatted as standup-ready bullets, and maintain the rolling todo list (shared with the todo skill) from the follow-ups it surfaces. Use when the user asks "what did I do yesterday", wants a daily recap or standup prep, needs to catch up on yesterday's work, or mentions "daily recap" or "standup".
---

# Daily Recap

Pulls the user's activity from the previous working day and renders standup-ready
bullets. An add-on to the [todo](../todo/SKILL.md) skill — install that first; this
skill writes to the same rolling list rather than keeping a second one.

**Read-only against every external service.** Never post, comment, react, merge, or
edit anything on GitHub, Slack, Calendar, or Wispr Flow. The only things this skill
writes are the shared rolling todo list (`todos.md`) and its companion `declined.md`
— and only after the user confirms the proposed changes (see §9). Everything else is
markdown in chat.

## Configuration

Identity and the enabled-sources list are stored once in a config file **outside**
either skill folder — the same file the todo skill would otherwise leave mostly empty
(`bash ../todo/scripts/config.sh path` → `~/.config/cmux-claude/config`), so nothing is
hardcoded and sharing the skill leaks no one's details. Fields: `github_login`,
`slack_user_id`, `timezone`, `calendar_id`, `sources`.

**Every run starts by loading it:**

```bash
bash ../todo/scripts/config.sh get   # KEY=VALUE: github_login, slack_user_id, timezone, calendar_id, sources
```

**First run only** — `get` exits non-zero when there's no config, or `sources` is
empty when the todo skill's config exists but daily-recap hasn't been set up yet.
Set it up once (don't make the user type what's auto-detectable):

1. `bash ../todo/scripts/config.sh detect` → auto-fills `github_login` (from `gh`) and
   `timezone` (from the system).
2. Ask which sources to enable (see **Sources** below) if not already installed with a
   choice. Read the **Slack user id**, if Slack is enabled, from any Slack MCP tool's
   own description (it states `Current logged in user's user_id is U…`).
3. Show the values, let the user confirm or correct, then persist:
   ```bash
   bash ../todo/scripts/config.sh init --github-login <login> --slack-id <U…> \
     --timezone <IANA> --sources <comma-list> --force
   ```
   `calendar_id` defaults to `primary`. To change anything later, re-run `init` with
   `--force` — unspecified flags keep their current value, so changing just one field
   (e.g. `--sources`) is safe.

**The user's meeting identity is not in the config** — it's resolved live, because
Wispr Flow attributes action items by display name and the names it uses are the ones
on the user's own calendar:

```
mcp__claude_ai_Wispr_Flow__get_account_info   → { name, aliases }
```

Call it once per run (before §6, if `wispr` is enabled) and keep `name` + every alias
— §6 and §9 match action-item attribution against that set.

The rolling todo list lives at `~/.config/cmux-claude/todos.md` (resolve with `bash
../todo/scripts/config.sh todos-path`) — the exact file the todo skill reads and
writes — alongside `declined.md` (`config.sh declined-path`), the Slack "Later"
permalinks the user has said no to. See §9 for how both are maintained.

## Sources

`sources` is a comma-separated subset of: `github`, `slack`, `calendar`, `wispr`,
`claude_sessions`. **Skip the corresponding numbered step below entirely — no line,
no "not enabled" note — for any source not in the list.** This is different from a
source being *unavailable* (e.g. a connector tool not loaded this session), which
should still be reported per that step's own fallback instructions.

**Custom sources.** If `~/.config/cmux-claude/custom-sources.md` exists, it holds
freeform instructions for additional sources the user has added themselves — each
`##`-level heading is one source's name, and the text under it is what to do to pull
that day's activity from it (a CLI command, an MCP tool call, a URL pattern — whatever
the user wrote). Run each one as its own numbered step alongside 2–7, folding its
output into the render (§8) under a bullet section titled after the heading. If the
file doesn't exist, there are no custom sources — say nothing about it.

## Depth: full vs quick

**Default is full**: §6 reads the complete transcript of every recorded meeting on the
day (only when `wispr` is enabled). That's the accurate mode — attribution in the
auto-generated notes is frequently wrong or anonymised, and only the transcript
settles it.

It is also the expensive part of the recap: a day with 5 recorded meetings is a few
hundred thousand characters of transcript. When the user asks for a **"quick recap"**
(or says they're in a hurry), run §6 in **summary-only** mode — skip
`view_transcript`, take the Flow Summary at face value, and label every `(Speaker N)`
action item `UNCLEAR?` instead of resolving it. Say which mode you ran in one clause,
e.g. "quick mode — summaries only, speaker attribution unresolved".

## Workflow

### 1. Resolve the day

Run the helper and `eval` its output. It resolves the "last working day" (Mon→Fri,
Sun→Fri, Sat→Fri, otherwise the previous calendar day) and emits all the windows the
queries need:

```bash
eval "$(bash scripts/day-window.sh)"   # sets TARGET_DATE, TARGET_WEEKDAY, LOCAL_OFFSET, GH_RANGE, SLACK_DATE, START_TS, END_TS, WINDOW_*_UTC
```

State which day you're recapping up front, e.g. "Recapping **Tuesday 2026-06-23**".

> **Shell state doesn't persist between separate command runs here.** So in each later
> step either (a) substitute the literal values printed above into the command, or (b)
> prefix the command with `eval "$(bash scripts/day-window.sh)"; ` so the vars exist in
> that same invocation. The `$VAR` names below refer to these values.

### 2. GitHub — PRs, commits, reviews *(skip if `github` not in sources)*

Run the four queries in [REFERENCE.md](REFERENCE.md) §GitHub:
- PRs **opened** that day, PRs **merged** that day, **reviews** given (events API →
  enrich title), **commits** authored (drop merge commits).
- Rewrite PR titles in plain language. When several repos carry the same feature (e.g.
  a backend + frontend pair), group those PRs into one bullet.

### 3. Slack — sent + replies + mentions *(skip if `slack` not in sources)*

Run the two searches in [REFERENCE.md](REFERENCE.md) §Slack:
- **Authored** (top-level + thread replies): `from:<@$slack_user_id> on:$SLACK_DATE`
- **Mentioned by others**: `<@$slack_user_id> on:$SLACK_DATE -from:<@$slack_user_id>`

Summarize by theme — don't transcribe every "thanks 🙌". Drop static footer mentions
(e.g. an incident bot's "default commanders" blurb that names the user without tagging
them to act). Flag any mention that still looks like it's awaiting the user's reply.

Both searches are day-scoped (`on:$SLACK_DATE`). The user's saved **"Later"** list
(`is:saved`) is *not* day-scoped — it's pulled separately in §9 as a todo source, not a
recap bullet.

### 4. Claude Code sessions *(skip if `claude_sessions` not in sources)*

Run the helper with the target day to list what was worked on in Claude Code that day
— cheap, reads only the session titles, never the transcripts:

```bash
bash scripts/claude-sessions.sh "$TARGET_DATE"   # one bullet per session: [project @branch] <ai-title>
```

Scope: local **Claude Code CLI** sessions only (not claude.ai web/desktop chats).
These often *produced* the GitHub PRs — **cross-reference and dedupe** (if `github` is
also enabled): fold sessions that map to a PR into the same work item, and surface as
separate bullets only the sessions with no PR/commit (e.g. investigations like "Review
policy lapse logic").

### 5. Meetings — the calendar list *(skip if `calendar` not in sources)*

Call `mcp__claude_ai_Google_Calendar__list_events` for the target day:
- `startTime: ${TARGET_DATE}T00:00:00${LOCAL_OFFSET}`, `endTime:
  ${TARGET_DATE}T23:59:59${LOCAL_OFFSET}`, `calendarId: $calendar_id`, `orderBy:
  startTime`. (Optionally set `timeZone: $timezone` to render times in the user's
  zone.)
- **Skip** events the user declined (own attendee `responseStatus: declined`) and
  `WORKING_LOCATION` / `OUT_OF_OFFICE` entries. `FOCUS_TIME` is a self-block, not a
  meeting — omit it (or note focus time separately).
- For each remaining event: `start–end` time + title (+ organizer if not the user).

This step answers *what was on the diary*. §6 answers *what actually came out of the
ones that were recorded*.

Calendar tools load at session start. **If the tool isn't available**, the connector
wasn't loaded into this session — fall back to
`mcp__claude_ai_Wispr_Flow__search_calendar_events` (same underlying Google Calendar,
requires `wispr` in sources; see [REFERENCE.md](REFERENCE.md) §Wispr Flow → Calendar
fallback) and note the reduced filtering in one line, rather than dropping meetings
from the recap. If `wispr` isn't enabled either, say the calendar step couldn't run
this time.

### 6. Recorded meetings — Wispr Flow *(skip if `wispr` not in sources)*

Wispr Flow's Meeting Recorder captures only *some* of the day's meetings. Those it
captured carry the substance the calendar can't: decisions, and attributed action
items. This is where most follow-ups come from.

1. **Find the day's recordings.** `mcp__claude_ai_Wispr_Flow__search_meetings` with
   `since: $WINDOW_START_UTC` and no query. Its `since`/`until` filter
   **`modified_at`, not start time** — so filter client-side: keep meetings whose
   `start` falls within `[$WINDOW_START_UTC, $WINDOW_END_UTC]`. Page while `has_more`.
2. **Read each one.** `mcp__claude_ai_Wispr_Flow__get_meeting` with `view_transcript:
   {char_limit: 40000}`, paging on the continuation offset until the transcript is
   exhausted (see [REFERENCE.md](REFERENCE.md) §Wispr Flow). In **quick** mode (see
   *Depth* above) omit `view_transcript` and work from `summary` alone.
3. **Extract three things** per meeting, synthesizing from the transcript and using
   `summary`'s `### Next Steps` / `### Decisions Made` only as an index of what to look
   for:
   - **Outcome** — one line: what the meeting resolved or moved.
   - **Decisions** — anything settled that others would need to know.
   - **Action items**, each assigned an owner (see attribution below).
4. **Attribute every action item** against the identity from `get_account_info`:
   - Attributed to the user's `name` or any alias → **theirs**. Feeds 📌 *Needs my
     follow-up* and §9.
   - Attributed to a named other person → **delegated**, if the user is the one who'll
     chase it. Feeds 🤝 *Delegated / waiting on* and goes on the todo list tagged `·
     delegated to <name>`.
   - Attributed to `(Speaker N)` or unattributed → **try to resolve it from the
     transcript** — who accepted the task, and whether anyone addresses them by name.
     If it settles, use that; if it doesn't, carry the item with `UNCLEAR?` and let the
     user claim or drop it in §9.
   > The notes' own attribution is a guess and is often wrong — a transcript reading
   > always wins over the `(Name)` prefix in `### Next Steps`. Never silently trust the
   > prefix in full mode.
   >
   > But don't over-promise: the transcript's speaker labels are the *same* unresolved
   > `Speaker N` diarization. It settles **what was committed to**; it maps a speaker
   > to a person only when someone is addressed by name aloud. On big external calls
   > some items will stay `UNCLEAR?` — surface them as such rather than guessing an
   > owner.
5. **Ignore the `todos` field.** `get_meeting` returns a structured `todos` array that
   is empty in practice; the real action items are the prose under `### Next Steps`.
   Don't report "no action items" on the strength of `todos: []`.
6. **Meetings still processing** — a result with `finalized: false` may have partial
   notes. Use it, and mark the bullet `(notes still processing)`.

Cross-reference against §5 (if `calendar` is also enabled): a calendar entry with a
matching recording gets the recording's substance folded into its bullet, not a second
bullet of its own.

**If the Wispr tools aren't available** in this session, emit one line and continue —
don't fail the recap: `🎙 Recordings: Wispr Flow tools not loaded this session —
restart Claude Code. Meetings shown from calendar only.`

### 7. Scratchpad notes — Wispr Flow *(skip if `wispr` not in sources)*

`mcp__claude_ai_Wispr_Flow__search_scratchpad_notes` with `since: $WINDOW_START_UTC`,
`until: $WINDOW_END_UTC`, no query — the notes the user jotted that day.
`get_scratchpad_note` for the body of any that look substantive.

These are things the user typed to themselves, so they're a high-signal todo source
(§9). **When there are no notes, say nothing** — no empty section, no "scratchpad was
empty" line. This source is silent until it has something.

### 8. Render standup bullets

Group by **theme/project**, not by source. Keep each bullet to one line. Use this
shape (omit empty sections — including any whose source isn't enabled, and any custom
source with nothing to report).

For the **📌 Needs my follow-up** section, first load the todo list (§9) and merge
three things so nothing persistent is dropped: (a) mentions/asks discovered today that
still await the user's reply, (b) action items §6 attributed to the user, and (c)
still-open `- [ ]` items carried over from `todos.md`.

```
*Recap — <TARGET_WEEKDAY> <TARGET_DATE>*

🔧 Shipped / coded
- <plain-language summary> (repo #num)

🔍 Explored / investigated
- <Claude Code session with no PR/commit> (project)

👀 Reviewed
- <PR title> for <author> (repo #num)

💬 Discussions / decisions
- <theme> (#channel)

🎙 Meeting outcomes
- <meeting title> — <what it resolved>; decided: <decision>

📌 Needs my follow-up
- <mention awaiting reply> (#channel)
- <action item I own> (meeting: <title>)

🤝 Delegated / waiting on
- <action item> — <person> (meeting: <title>)

📅 Meetings
- <HH:MM> <title> 🎙        ← 🎙 marks the ones Wispr recorded

<Custom source heading>
- <whatever that source's instructions produce>
```

### 9. Maintain the rolling todo list

The recap's follow-ups feed the shared list at `todos.md` (resolve with `bash
../todo/scripts/config.sh todos-path`; create it if absent — see the
[todo skill](../todo/SKILL.md) for the file format). It and `declined.md` are the only
things this skill *writes*, and both are written **only after the user confirms**:
propose the changes, then wait for an explicit go-ahead (`write them`) before touching
either file.

1. **Load** the current list (Read the file; if it doesn't exist, start from empty).
2. **Pull the Slack "Later" list** *(only if `slack` is enabled)* — run the `is:saved`
   search (see [REFERENCE.md](REFERENCE.md) §Slack). These are messages the user
   parked to come back to, so treat each as a **candidate todo**. It is *not*
   day-scoped (`is:saved` ignores `on:`/`after:`), so it returns the whole saved list
   every run — that's intended; dedupe (step 3) keeps it from piling up. Also read
   `declined.md` (`bash ../todo/scripts/config.sh declined-path`; may not exist) and
   drop, silently, any saved message whose permalink is listed there — the user has
   already said no to it.
3. **Reconcile** the list against today's day-scoped findings, the meeting action
   items, the scratchpad notes, and the Later list (whichever of these are enabled),
   into a proposed set of changes:
   - **Carry over** every open `- [ ]` item unchanged.
   - **Suggest done** — for each open item, check whether the recapped day's activity
     (from whatever sources are enabled) shows it's complete. Propose flipping it to
     `- [x]` and appending `· done YYYY-MM-DD` (the day it was completed — the recapped
     `TARGET_DATE`), *with the evidence*, but never assume — label it `DONE?` for the
     user to confirm or reject.
   - **Add** newly-discovered follow-ups that aren't already on the list, each stamped
     `· added YYYY-MM-DD` (today, `date +%F`) and `· effort S/M/L` — your best guess at
     relative size from what the item actually asks for. It's a guess, not a
     commitment — the user can override it when confirming the diff, or later from the
     effort dropdown on the todos page. Sources, each only if enabled:
     - the day's Slack mentions/asks that still await the user's reply (`slack`);
     - **meeting action items owned by the user** (`wispr`), sourced as `(meeting:
       <title> · YYYY-MM-DD)`;
     - **delegated action items** (`wispr`), same source hint plus `· delegated to
       <name>` — chase-ups, not work the user does;
     - **actionable items from the Later list** (`slack`) — a parked request or task;
     - **actionable scratchpad notes** (`wispr`), sourced as `(note: <title>)`;
     - anything actionable a **custom source** surfaced, sourced as `(<source name>)`.
     When the source states a deadline ("by Friday", "end of next week", "check
     tomorrow"), resolve it to a date and stamp `· due YYYY-MM-DD` too. Only when it's
     stated — never infer a due date from urgency of tone.
     Skip items that are purely informational (a reference doc, an FYI, a link to
     keep) rather than an action for the user; tag the ones you do propose so their
     origin is clear, and keep any permalink as the source hint.
   - **Carry `UNCLEAR?` items** from §6 into the proposal as questions rather than
     adds — one line each, asking the user whether it's theirs, someone else's, or
     noise. Only what they claim gets written.
   - Dedupe by meaning, not exact string, against every item already on the list
     **open or done** — don't re-add something already there in different words, and
     don't resurrect a Later item that's already been completed. A meeting action item
     and a Slack ask about the same thing are **one** todo; keep whichever source hint
     is more useful and mention the other in the proposal.
4. **Propose** the changes as a compact diff — `+ ADD … · effort S/M/L` (noting which
   are `· saved` from the Later list, from a meeting, or from a note — and inviting the
   user to override the effort guess), `~ DONE? … (evidence)`, `? UNCLEAR …`, and a
   count of untouched items — then **wait** for the user's go-ahead (`write them`, or
   edits, including effort corrections). Don't write on your own initiative.
5. On confirmation, **write** the file — and append the permalink of every Later add
   the user declined to `declined.md`, saying which ones you're recording so declining
   isn't a silent side-effect.

> **The Later list is read-only.** This skill can't un-save a Slack item, so a saved
> message stays in the user's Later list (and thus keeps re-appearing in the
> `is:saved` results) until they clear it in Slack. Two things keep it out of the
> proposal: dedupe (step 3) once it's on `todos.md`, and `declined.md` once the user
> has said no to it. Wispr Flow is read-only the same way — there's no tool to tick off
> a meeting action item at the source.

**`declined.md`** — one declined Slack permalink per line, optionally followed by the
item text so a human can read the list. Lines starting with `#` are comments:

```
https://yourteam.slack.com/archives/C0123ABCDEF/p1700000000000000  API migration thread
```

**Displaying the list** and the file format itself are owned by the
[todo skill](../todo/SKILL.md) — see it for the exact markdown shape (including the
`due` tag this skill writes), the sort/grouping rules, and the dashboard
(`scripts/todos-server.sh`, which lives there, not here).

## Notes

- All windows are computed in the configured (or local) timezone then converted to UTC
  by the helper — don't hand-roll date math.
- **Every Wispr Flow timestamp is UTC** (ISO 8601, `…Z`). Convert to the user's
  `timezone` before showing any time. Google Calendar times carry their own offset and
  don't need this.
- The GitHub events API includes private repos but strips titles/commit messages;
  that's why reviews are enriched via `gh pr view`. See [REFERENCE.md](REFERENCE.md)
  for why.
- If an *enabled* source returns nothing, say so briefly rather than omitting it
  silently — **except** the scratchpad (§7), which is silent when empty. A *disabled*
  source gets no mention at all (see Sources above).
