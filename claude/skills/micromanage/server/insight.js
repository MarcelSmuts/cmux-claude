'use strict';
// insight.js — what a session is actually doing and how well, read off its transcript.
//
// micromanage.sh answers "is this session busy or blocked". That is the cheap half. The
// expensive half is in the records it doesn't read: the pending tool call IS the pending
// permission, an unanswered AskUserQuestion IS the question, and every test run the
// session ever did is sitting there with its output. Two passes:
//
//   now()  — the tail only, to see the live turn: what it is running, or waiting on.
//   work() — the whole transcript, folded incrementally, for the evidence trail.
//
// work() is append-only and monotonic, so a poll re-reads only the bytes that arrived
// since the last one. Nothing here writes, and nothing here shells out.

const fs = require('fs');

const COLD_BYTES = 4 * 1024 * 1024; // a long transcript's first read starts this far back
const TAIL_BYTES = 384 * 1024; // enough of the tail to contain the live turn

const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit']);
const LOOK_TOOLS = new Set(['Read', 'Grep', 'Glob', 'WebFetch', 'WebSearch', 'ToolSearch']);

// What a shell command is for. Order matters: a `npm test` that pipes through tsc is a
// test run first.
const COMMAND_KINDS = [
  ['test', /\b(mocha|jest|vitest|npm (run )?test|yarn (run )?test|pnpm test|run-tests)\b/],
  ['types', /\b(tsc|typecheck|type-check)\b/],
  ['lint', /\b(eslint|prettier|npm run lint)\b/],
  ['commit', /\bgit\s+(-C\s+\S+\s+)?commit\b/],
  ['push', /\bgit\s+(-C\s+\S+\s+)?push\b/],
  ['pr', /\bgh\s+pr\s+create\b/],
];

const blocks = (rec) => {
  const c = rec && rec.message && rec.message.content;
  return Array.isArray(c) ? c : [];
};

const commandKind = (cmd) => {
  for (const [kind, re] of COMMAND_KINDS) if (re.test(cmd)) return kind;
  return null;
};

// ── the evidence trail, folded record by record ─────────────────────────────────────
const cache = new Map(); // transcript path → { size, work }

function freshWork() {
  return {
    tools: 0,
    edits: 0,
    files: new Set(),
    errors: 0,
    commits: 0,
    pushes: 0,
    pushedAt: null, // when it last pushed, which is when CI took over as the better witness
    prCreated: false,
    out: 0, // output tokens, the only usage figure that tracks effort rather than context
    tests: null, // { ok, passing, failing, at }
    types: null,
    lint: null,
    open: new Map(), // tool_use_id → kind, for commands whose result hasn't arrived yet
    // Claude Code writes these itself, so they beat anything we could infer.
    summary: null, // the away_summary: goal, state, and what it wants from you
    summaryAt: null,
    // A session can own more than one PR: a frontend slice that needed a backend change
    // links one in each repo, and dropping either hides half of what it shipped.
    prs: new Map(), // "repo#number" → { number, url, repo }
    permissionMode: null,
    lastPrompt: null, // the instruction you actually gave it
  };
}

function resultText(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) return content.map((c) => c.text || '').join('\n');
  return '';
}

// Read the numbers out of a runner's own output where it has them, and fall back to the
// tool_result error flag where it doesn't. A run whose output we can't parse still tells
// us pass or fail.
// A backgrounded or truncated run reports no counts at all. Saying "0 passing" there
// would read as an empty suite, so an unparseable run keeps its pass/fail verdict and
// drops the numbers.
function settle(work, kind, block, at) {
  const text = resultText(block.content);
  const failed = !!block.is_error;
  if (kind === 'test') {
    const passing = Number((text.match(/(\d+)\s+passing/) || [])[1] || 0);
    const failing = Number((text.match(/(\d+)\s+failing/) || [])[1] || 0);
    const counted = passing > 0 || failing > 0;
    work.tests = { ok: failing === 0 && !failed, passing, failing, counted, at };
  } else if (kind === 'types') {
    const errors = (text.match(/error TS\d+/g) || []).length;
    work.types = { ok: errors === 0 && !failed, errors, at };
  } else if (kind === 'lint') {
    const problems = Number((text.match(/(\d+)\s+problems?/) || [])[1] || 0);
    work.lint = { ok: problems === 0 && !failed, problems, at };
  }
}

function fold(work, rec) {
  // Records Claude Code maintains for its own resume and status machinery. Last one wins:
  // the mode can change, and a session gets a fresh away_summary every time it stops.
  switch (rec.type) {
    case 'system':
      if (rec.subtype === 'away_summary' && rec.content) {
        work.summary = oneLine(rec.content, 400);
        work.summaryAt = rec.timestamp || null;
      }
      return;
    case 'pr-link':
      if (rec.prNumber && rec.prRepository) {
        work.prs.set(`${rec.prRepository}#${rec.prNumber}`, {
          number: rec.prNumber,
          url: rec.prUrl,
          repo: rec.prRepository,
        });
      }
      return;
    case 'permission-mode':
      work.permissionMode = rec.permissionMode || null;
      return;
    case 'last-prompt':
      work.lastPrompt = oneLine(rec.lastPrompt, 200);
      return;
    default:
      break;
  }

  if (rec.type === 'assistant') {
    const usage = rec.message && rec.message.usage;
    if (usage) work.out += usage.output_tokens || 0;
    for (const b of blocks(rec)) {
      if (b.type !== 'tool_use') continue;
      work.tools++;
      if (EDIT_TOOLS.has(b.name)) {
        work.edits++;
        const f = b.input && b.input.file_path;
        if (f) work.files.add(f);
      }
      if (b.name !== 'Bash') continue;
      const kind = commandKind(String((b.input && b.input.command) || ''));
      if (kind === 'commit') work.commits++;
      else if (kind === 'push') {
        work.pushes++;
        work.pushedAt = rec.timestamp || work.pushedAt;
      } else if (kind === 'pr') work.prCreated = true;
      else if (kind) work.open.set(b.id, kind);
    }
    return;
  }
  if (rec.type !== 'user') return;
  for (const b of blocks(rec)) {
    if (b.type !== 'tool_result') continue;
    if (b.is_error) work.errors++;
    const kind = work.open.get(b.tool_use_id);
    if (!kind) continue;
    work.open.delete(b.tool_use_id);
    settle(work, kind, b, rec.timestamp || null);
  }
}

// Whole lines only: the last record may still be half-written, and re-reading it next
// poll is the point of returning the offset we actually consumed.
function foldRange(work, path, start, end) {
  if (end <= start) return start;
  const fd = fs.openSync(path, 'r');
  const buf = Buffer.alloc(end - start);
  try {
    fs.readSync(fd, buf, 0, buf.length, start);
  } finally {
    fs.closeSync(fd);
  }
  const cut = buf.lastIndexOf(0x0a);
  if (cut < 0) return start;
  const text = buf.subarray(0, cut).toString('utf8');
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    try {
      fold(work, JSON.parse(line));
    } catch {}
  }
  return start + cut + 1;
}

function workOf(path, size) {
  let held = cache.get(path);
  // A transcript only grows. Anything else (a resume rewrite, a rotation) means the
  // offset we held is meaningless, so start over.
  if (!held || size < held.size) {
    held = { size: Math.max(0, size - COLD_BYTES), work: freshWork(), cold: size > COLD_BYTES };
    cache.set(path, held);
  }
  held.size = foldRange(held.work, path, held.size, size);
  const w = held.work;
  return {
    tools: w.tools,
    edits: w.edits,
    files: w.files.size,
    errors: w.errors,
    commits: w.commits,
    pushes: w.pushes,
    pushedAt: w.pushedAt,
    prCreated: w.prCreated,
    out: w.out,
    tests: w.tests,
    types: w.types,
    lint: w.lint,
    summary: w.summary,
    summaryAt: w.summaryAt,
    prs: [...w.prs.values()],
    permissionMode: w.permissionMode,
    lastPrompt: w.lastPrompt,
    partial: !!held.cold, // stats start mid-transcript, so counts are a floor
  };
}

// ── the live turn ───────────────────────────────────────────────────────────────────
function tailRecords(path, size) {
  const start = Math.max(0, size - TAIL_BYTES);
  const fd = fs.openSync(path, 'r');
  const buf = Buffer.alloc(size - start);
  try {
    fs.readSync(fd, buf, 0, buf.length, start);
  } finally {
    fs.closeSync(fd);
  }
  const lines = buf.toString('utf8').split('\n');
  if (start > 0) lines.shift();
  const out = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line));
    } catch {}
  }
  return out;
}

const oneLine = (s, n = 240) =>
  String(s || '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, n);

// The one input worth showing per tool, in the order a human would look for it.
function toolDetail(block) {
  const i = block.input || {};
  if (block.name === 'Bash') return oneLine(i.command);
  const one = i.file_path || i.pattern || i.path || i.url || i.description || i.prompt;
  return oneLine(typeof one === 'string' ? one : JSON.stringify(i));
}

// A prose ask reads as a question. Cheap and only used to sort a card into "decide"
// rather than "review", where guessing wrong costs a glance at the wrong column.
const ASKING = /\?\s*$|\b(should i|which (one|of|approach|would)|do you want|prefer|shall i|confirm|let me know|your call|option [ab1-3])\b/i;

function nowOf(path, size, lastText) {
  const records = tailRecords(path, size);
  const resolved = new Set();
  const issued = [];
  for (const rec of records) {
    for (const b of blocks(rec)) {
      if (b.type === 'tool_use') issued.push(b);
      else if (b.type === 'tool_result' && b.tool_use_id) resolved.add(b.tool_use_id);
    }
  }
  const pending = issued.filter((b) => !resolved.has(b.id));

  const question = pending.find((b) => b.name === 'AskUserQuestion');
  if (question) {
    const qs = ((question.input && question.input.questions) || []).map((q) => ({
      header: oneLine(q.header, 40),
      question: oneLine(q.question, 300),
      options: (q.options || []).map((o) => oneLine(o.label, 60)),
    }));
    return { kind: 'question', questions: qs };
  }

  const live = pending[pending.length - 1];
  if (live) return { kind: 'tool', tool: live.name, detail: toolDetail(live) };

  // Nothing outstanding: the session has handed the turn back, so its closing message is
  // the ask. Whether that is a question or a report decides which column it lands in.
  const text = oneLine(lastText, 600);
  return { kind: ASKING.test(text) ? 'asking' : 'report', text };
}

function read(session) {
  const path = session.file;
  if (!path) return {};
  let size;
  try {
    size = fs.statSync(path).size;
  } catch {
    return {};
  }
  try {
    return { now: nowOf(path, size, session.last), work: workOf(path, size) };
  } catch {
    return {};
  }
}

module.exports = { read };
