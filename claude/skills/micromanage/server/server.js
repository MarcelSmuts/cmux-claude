#!/usr/bin/env node
// server.js — the micromanage UI: a localhost-only web front end over micromanage.sh and
// insight.js (read), plus att.sh to go to a tab and unspawn.sh to close one.
//
// Local by design: binds 127.0.0.1, and every /api call needs the token minted at
// startup and handed to the page through its URL. Nothing here is reachable from
// another machine, and a token means another *process* on this machine can't drive
// your sessions by guessing the port.
//
// Usage: node server.js [--port N] [--no-open]
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { execFile } = require('child_process');
const insight = require('./insight.js');

const HOME = os.homedir();
const HERE = __dirname;
const SKILL_SCRIPTS = path.join(HERE, '..', 'scripts');
const SESSION_SCRIPTS = path.join(HOME, '.claude', 'scripts');
const RUNTIME = path.join(HERE, '.runtime.json');

const argv = process.argv.slice(2);
const flag = (name) => argv.includes(name);
const opt = (name, fallback) => {
  const i = argv.indexOf(name);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
};

const PORT = Number(opt('--port', process.env.MICROMANAGE_PORT || 8899));

// Kept on disk so the URL survives a restart — this page is meant to stay open in a
// tab, and a fresh token every boot would break the bookmark.
const TOKEN_FILE = path.join(HERE, '.token');
const TOKEN = (() => {
  try {
    const saved = fs.readFileSync(TOKEN_FILE, 'utf8').trim();
    if (saved.length >= 32) return saved;
  } catch {}
  const fresh = crypto.randomBytes(16).toString('hex');
  fs.writeFileSync(TOKEN_FILE, fresh, { mode: 0o600 });
  return fresh;
})();
// Deliberately just under the page's 5s poll: every poll should find this stale and start
// a fresh scan behind the response it is already being served. Raise it above the poll
// interval and the real scan rate silently becomes this number instead.
const SCAN_TTL = 4000;

// ── shelling out ────────────────────────────────────────────────────────────────────
function run(cmd, args, { cwd, timeout = 30000 } = {}) {
  return new Promise((resolve) => {
    execFile(
      cmd,
      args,
      { cwd: cwd && fs.existsSync(cwd) ? cwd : HOME, timeout, maxBuffer: 16 << 20, env: { ...process.env, CMUX_QUIET: '1' } },
      (err, stdout, stderr) => {
        resolve({
          ok: !err,
          code: err ? (typeof err.code === 'number' ? err.code : 1) : 0,
          timedOut: !!(err && err.killed),
          stdout: stdout || '',
          stderr: stderr || '',
        });
      },
    );
  });
}

const script = (dir, name) => path.join(dir, name);

// ── the scan, cached ────────────────────────────────────────────────────────────────
let cache = { at: 0, data: { procs: 0, sessions: [] }, error: null };
let inFlight = null;

async function scan() {
  const res = await run('bash', [script(SKILL_SCRIPTS, 'micromanage.sh'), '--json'], { timeout: 60000 });
  if (!res.ok) throw new Error(res.stderr.trim() || `micromanage.sh exited ${res.code}`);
  return JSON.parse(res.stdout);
}

// ── pull request state, cached ──────────────────────────────────────────────────────
// Which PR a session owns comes free: it wrote a `pr-link` record when it opened one, so
// there is no branch-name guessing and no chance of matching some ancient PR that also
// happened to be raised from `master`. All gh is needed for is the live state, and that
// is slow enough (~1.2s per PR) to sit on its own TTL well behind the scan.
//
// Two sweeps, not a TTL per PR. A PR with checks still running will say something different
// shortly; one that has settled only moves when a human does something, and polling that
// hard just spends rate limit to be told the same thing. Neither sweep is a timer: both are
// a timestamp that the next arriving poll compares against, so an unopened page costs
// nothing at all.
const PR_TTL_LIVE = 2 * 60 * 1000;
const PR_TTL_SETTLED = 30 * 60 * 1000;
let sweptLive = 0;
let sweptSettled = 0;

const prCache = new Map(); // "repo#number" → { at, detail }; `at` is a receipt, not a clock
const prInFlight = new Map(); // "repo#number" → promise, so two polls can't double-fetch

const prKey = (pr) => `${pr.repo}#${pr.number}`;

// Every check on a PR reports here, but a repo's branch ruleset may require just one of
// them by name. A red advisory check (e.g. a non-blocking lint bot) does not block a
// merge, so rolling them all into one verdict would send you chasing a check that
// doesn't count. Adjust this to match your own required-check name(s), or leave it as
// a harmless no-op regex — it just falls back to the whole rollup (see below).
const REQUIRED_CHECK = /\bCI Gate\b/i;
const BAD_CONCLUSION = new Set(['FAILURE', 'ERROR', 'TIMED_OUT', 'CANCELLED', 'STARTUP_FAILURE', 'ACTION_REQUIRED']);
const IGNORED_CONCLUSION = new Set(['SKIPPED', 'NEUTRAL']);

function checksOf(rollup) {
  const ci = { gate: null, failed: 0, running: 0, passed: 0, total: 0 };
  for (const c of rollup || []) {
    // CheckRun reports status + conclusion; the older StatusContext reports just state.
    const name = c.name || c.context || '';
    const verdict = String(c.conclusion || c.state || '').toUpperCase();
    const running = c.status ? String(c.status).toUpperCase() !== 'COMPLETED' : !verdict || verdict === 'PENDING';
    const failed = !running && BAD_CONCLUSION.has(verdict);
    ci.total++;
    if (running) ci.running++;
    else if (failed) ci.failed++;
    else if (!IGNORED_CONCLUSION.has(verdict)) ci.passed++;
    if (REQUIRED_CHECK.test(name)) ci.gate = running ? 'running' : failed ? 'fail' : 'pass';
  }
  // No required check matched on this repo, so the whole rollup is the verdict.
  if (ci.gate === null && ci.total > 0) ci.gate = ci.failed ? 'fail' : ci.running ? 'running' : 'pass';
  return ci;
}

async function prDetail(pr) {
  await ghTake();
  let r;
  try {
    r = await run(
      'gh',
      ['pr', 'view', String(pr.number), '--repo', pr.repo, '--json', 'state,isDraft,reviewDecision,mergeable,title,url,statusCheckRollup'],
      { timeout: 25000 },
    );
  } finally {
    ghGive();
  }
  if (!r.ok) return null;
  let d;
  try {
    d = JSON.parse(r.stdout);
  } catch {
    return null;
  }
  return {
    number: pr.number,
    repo: pr.repo,
    url: d.url || pr.url,
    title: d.title || '',
    state: String(d.state || '').toLowerCase(),
    draft: !!d.isDraft,
    review: String(d.reviewDecision || '').toLowerCase(), // approved | changes_requested | review_required
    conflicts: String(d.mergeable || '').toUpperCase() === 'CONFLICTING',
    ci: checksOf(d.statusCheckRollup),
  };
}

// Checks still moving, or a lookup that hasn't landed yet: both want the short sweep. A
// failed lookup left on the long one would hide a PR chip for half an hour over what is
// usually a momentary GitHub hiccup.
const isLive = (held) => {
  if (!held.detail) return true;
  const ci = held.detail.ci;
  return !!ci && (ci.gate === 'running' || ci.running > 0);
};

// gh pr view with the full check rollup is a heavy GraphQL query, and firing one per PR at
// once gets some of them refused. Three at a time is slower to warm up and actually lands.
let ghSlots = 3;
const ghWaiting = [];
const ghTake = () => (ghSlots > 0 ? (ghSlots--, Promise.resolve()) : new Promise((go) => ghWaiting.push(go)));
const ghGive = () => {
  const next = ghWaiting.shift();
  if (next) next();
  else ghSlots++;
};

// One lookup per PR at a time: two polls arriving together share the in-flight promise
// instead of spending two GraphQL queries to be told the same thing.
function lookup(link) {
  const key = prKey(link);
  const running = prInFlight.get(key);
  if (running) return running;
  const job = prDetail(link)
    .then((d) => {
      // A failed lookup keeps the old copy rather than blanking the card, but still takes
      // a fresh receipt so a broken PR isn't retried on every poll until the next sweep.
      prCache.set(key, { at: Date.now(), detail: d || (prCache.get(key) || {}).detail || null });
    })
    .catch(() => {})
    .finally(() => prInFlight.delete(key));
  prInFlight.set(key, job);
  return job;
}

function refreshPrs(links) {
  const now = Date.now();
  const sweepLive = now - sweptLive >= PR_TTL_LIVE;
  const sweepSettled = now - sweptSettled >= PR_TTL_SETTLED;
  const jobs = [];
  const seen = new Set();
  for (const link of links) {
    if (!link || !link.number || !link.repo) continue;
    const key = prKey(link);
    if (seen.has(key)) continue;
    seen.add(key);
    if (!prInFlight.has(key)) {
      const held = prCache.get(key);
      // The owning session pushed since we last looked, so CI is starting over whatever the
      // cached copy says. Without this a settled-green PR could sit half an hour out of date
      // while its checks were actually re-running.
      const pushedSince = held && link.pushedAt && new Date(link.pushedAt).getTime() > held.at;
      if (held && !pushedSince && !(isLive(held) ? sweepLive : sweepSettled)) continue;
    }
    jobs.push(lookup(link));
  }
  // Stamped even when a sweep matched nothing: it ran, and found nothing to do.
  if (sweepLive) sweptLive = now;
  if (sweepSettled) sweptSettled = now;
  return Promise.all(jobs);
}

// The card's ↻. Both sweeps are deliberately slow, so this is how you say "ask GitHub now"
// for one card: no receipt is consulted, and the answer lands before the reply so the poll
// that follows already has it.
function refreshPrsNow(links) {
  const seen = new Set();
  const jobs = [];
  for (const link of links) {
    if (!link || !link.number || !link.repo) continue;
    const key = prKey(link);
    if (seen.has(key)) continue;
    seen.add(key);
    jobs.push(lookup(link));
  }
  return Promise.all(jobs).then(() => seen.size);
}

function prFor(link) {
  if (!link || !link.number || !link.repo) return null;
  const held = prCache.get(prKey(link));
  if (!held || !held.detail) return link; // number and url only, until the first lookup lands
  return { ...held.detail, checkedAt: held.at };
}

// ── which pile a session belongs in ─────────────────────────────────────────────────
// Not by pipeline position but by what it wants from you, because that is what decides
// the order you work through them. A session parked for most of a day is its own pile
// however it got there: at that age the question is whether to reclaim the tab, not what
// it asked you four days ago.
const STALE_SECS = 12 * 3600;

function bucketOf(s, prs) {
  const now = s.now || {};
  // Everything it opened has landed, so the tab and its worktree are reclaimable.
  if (prs.length && prs.every((p) => p.state === 'merged' || p.state === 'closed')) return 'done';
  if (s.state === 'working') return 'working';
  if (s.state === 'error') return 'decide';
  if (now.kind === 'question') return 'decide'; // it is holding an AskUserQuestion open
  if (now.kind === 'tool') return 'approve'; // a tool call it can't make on its own
  if (s.idle >= STALE_SECS) return 'stale';
  if (now.kind === 'asking') return 'decide';
  return 'review';
}

function sessions({ force = false } = {}) {
  const fresh = Date.now() - cache.at < SCAN_TTL;
  if (!inFlight && (force || !fresh)) {
    inFlight = scan()
      .then((data) => {
        cache = { at: Date.now(), data, error: null };
      })
      .catch((err) => {
        cache = { ...cache, at: Date.now(), error: String(err.message || err) };
      })
      .finally(() => {
        inFlight = null;
      });
  }
  // First call has nothing to serve yet, so wait for it; after that the page always
  // gets an instant answer plus the age of what it's looking at.
  const wait = cache.at === 0 ? inFlight : Promise.resolve();
  return wait.then(async () => {
    const read = (cache.data.sessions || []).map((s) => ({ ...s, ...insight.read(s) }));
    // Only the very first page load waits on gh; after that a stale index is served and
    // the refresh lands on a later poll.
    const pending = refreshPrs(
      read.flatMap((s) => ((s.work && s.work.prs) || []).map((p) => ({ ...p, pushedAt: s.work.pushedAt }))),
    );
    if (!prCache.size) await pending; // only the very first load waits on gh
    const list = read.map((s) => {
      const prs = (((s.work && s.work.prs) || []).map(prFor)).filter(Boolean);
      return { ...s, prs, bucket: bucketOf(s, prs) };
    });
    return {
      ...cache.data,
      sessions: list,
      error: cache.error,
      scannedAt: cache.at,
      scanning: !!inFlight,
    };
  });
}

// ── HTTP ────────────────────────────────────────────────────────────────────────────
const json = (res, code, body) => {
  const payload = JSON.stringify(body);
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(payload);
};

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => {
      data += c;
      if (data.length > 1 << 20) reject(new Error('body too large'));
    });
    req.on('end', () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch (e) {
        reject(e);
      }
    });
  });
}

const LOCAL_HOSTS = new Set(['127.0.0.1', 'localhost', '[::1]', '::1']);

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const host = (req.headers.host || '').replace(/:\d+$/, '');
  if (!LOCAL_HOSTS.has(host)) return json(res, 403, { error: 'localhost only' });

  if (url.pathname === '/' || url.pathname === '/index.html') {
    let html;
    try {
      html = fs.readFileSync(path.join(HERE, 'index.html'), 'utf8');
    } catch {
      return json(res, 500, { error: 'index.html missing' });
    }
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
    return res.end(html);
  }

  if (!url.pathname.startsWith('/api/')) return json(res, 404, { error: 'not found' });

  const token = req.headers['x-micromanage-token'] || url.searchParams.get('t');
  if (token !== TOKEN) return json(res, 401, { error: 'bad token' });

  try {
    if (req.method === 'GET' && url.pathname === '/api/sessions') {
      return json(res, 200, await sessions({ force: url.searchParams.get('force') === '1' }));
    }

    if (req.method === 'POST') {
      const body = await readBody(req);

      // Which PRs to look up is read back out of the scan rather than taken from the page,
      // so a request can only ever refresh a PR some session actually opened.
      if (url.pathname === '/api/pr-refresh') {
        const s = (cache.data.sessions || []).find((x) => x.file === String(body.file || ''));
        if (!s) return json(res, 404, { error: 'unknown session' });
        const links = (insight.read(s).work || {}).prs || [];
        if (!links.length) return json(res, 200, { ok: true, refreshed: 0 });
        return json(res, 200, { ok: true, refreshed: await refreshPrsNow(links) });
      }

      const ws = String(body.ws || '').trim();
      if (!ws) return json(res, 400, { error: 'no tab' });

      if (url.pathname === '/api/focus') {
        return json(res, 200, await run('bash', [script(SESSION_SCRIPTS, 'att.sh'), ws], { timeout: 15000 }));
      }

      if (url.pathname === '/api/close') {
        const args = [script(SESSION_SCRIPTS, 'unspawn.sh'), ws];
        if (body.keepWorktree) args.push('--keep-worktree');
        if (body.force) args.push('--force');
        const out = await run('bash', args, { cwd: body.cwd, timeout: 60000 });
        cache.at = 0; // that tab just went away — next poll should re-scan
        return json(res, 200, out);
      }
    }

    return json(res, 404, { error: 'not found' });
  } catch (err) {
    return json(res, 500, { error: String(err.message || err) });
  }
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`micromanage: port ${PORT} is already in use — another UI is probably running.`);
    process.exit(4);
  }
  console.error('micromanage:', err.message);
  process.exit(1);
});

server.listen(PORT, '127.0.0.1', () => {
  const url = `http://127.0.0.1:${PORT}/?t=${TOKEN}`;
  fs.writeFileSync(RUNTIME, JSON.stringify({ pid: process.pid, port: PORT, token: TOKEN, url }, null, 2), { mode: 0o600 });
  console.log(url);
  if (!flag('--no-open')) run('open', [url]);
  sessions(); // warm the cache so the first page load lands on data
});

const shutdown = () => {
  try {
    fs.unlinkSync(RUNTIME);
  } catch {}
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
