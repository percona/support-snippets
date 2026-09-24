#!/usr/bin/env node
// Browser test for the candidate flow of a deployed lab. tools/browser-test.sh
// runs it; see that file for usage and the environment it passes in.
//
// smoketest.sh proves every grader from the inside. Nothing proved the page a
// candidate actually uses: the Send handler once threw a ReferenceError inside
// its own try/catch, every candidate saw "Could not reach the server", and the
// suite kept passing 11/11. This drives headless Chromium through the real
// page over plain HTTP the way a candidate does — briefing, Start, terminals,
// the copy block, Send — and fails on any page error or console error.
//
// It mutates the lab (starts the exam, advances one level), so it refuses to
// run while an exam is in progress unless FORCE=1, and it always finishes with
// the interviewer's POST /reset (RUNBOOK.md, T-30), even after a failure. The
// Q1 fix it applies is the one in smoketest.sh; it travels over ssh on stdin
// and is never written to the server's disk.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { chromium } = require('playwright');

const HOST = need('LAB_HOST');
const BASE = 'http://' + HOST;
const CAND_PASS = need('CAND_PASS');
const INTV_PASS = need('INTV_PASS');
const SSH_TARGET = process.env.SSH_TARGET || '';
const SSH_KEY = process.env.SSH_KEY || '';
const SSH_PORT = process.env.SSH_PORT || '22';
const DRY = process.env.DRY === '1';
const FORCE = process.env.FORCE === '1';
// CURRENT_PREFIX-<node> in controller/app.py; nginx routes /term/node1/ to it.
const NODE1 = 'mysql-exercise-current-node1';
// One folder per lab, so two labs tested at once do not overwrite each other.
const OUT = path.join(__dirname, 'output', HOST.replace(/[^\w.-]/g, '_'));

// How long the lab may legitimately take. A cold spawn of a question is
// 30-60s before ttyd answers. A failing check is re-sampled for CHECK_SETTLE
// (30s) with each sample capped at CHECK_TIMEOUT (20s), and a passing one
// still needs two samples; then the prewarmed next level is promoted.
const BOOT_MS = 120000;
const CHECK_MS = 150000;

// ---- output, in smoketest.sh's style ----------------------------------------
const G = '\x1b[32m', R = '\x1b[31m', Y = '\x1b[33m', N = '\x1b[0m';
const ok = (m) => console.log(`${G}✓ ${m}${N}`);
const fail = (m) => console.log(`${R}✗ ${m}${N}`);
const info = (m) => console.log(`${Y}… ${m}${N}`);

const summary = [];
let failures = 0;
let mutated = false;   // set once the lab's state has been touched: a reset is then owed

class Abort extends Error {}

function need(name) {
  const v = process.env[name];
  if (!v) { console.error(`browser-test.js: ${name} is not set`); process.exit(1); }
  return v;
}

// An assertion prints its own ✓ line; the first failing one ends the case.
function expect(cond, msg) {
  if (!cond) throw new Error(msg);
  ok(msg);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rnd = (a, b) => a + Math.random() * (b - a);

// Typing the way a person does: one key at a time, uneven gaps. Playwright's
// own `delay` is constant, which the lab rightly rejects as machine-steady.
async function humanType(page, text) {
  for (const ch of text) {
    await page.keyboard.type(ch);
    await sleep(rnd(70, 230));
  }
}

// Poll for a value instead of sleeping a fixed time: a shell prompt or a
// websocket frame has no DOM state a locator could wait on.
async function until(fn, ms, what) {
  const t0 = Date.now();
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() - t0 > ms) throw new Error(`timed out after ${Math.round(ms / 1000)}s waiting for ${what}`);
    await sleep(500);
  }
}

const basic = (user, pass) => ({ Authorization: 'Basic ' + Buffer.from(`${user}:${pass}`).toString('base64') });
const asCandidate = () => basic('candidate', CAND_PASS);
const asInterviewer = () => basic('interviewer', INTV_PASS);

// Which page the controller is serving: the briefing means "not started".
function labState(html) {
  if (/<title>Before you begin/.test(html)) return 'briefing';
  if (/<title>Session locked/.test(html)) return 'locked';
  const m = /<title>Question (\d+)/.exec(html);
  if (m) return `question ${m[1]}`;
  if (/<title>Done/.test(html)) return 'done';
  return 'unknown page';
}

async function liveJson() {
  const r = await fetch(`${BASE}/interviewer/live`, { headers: asInterviewer() });
  if (r.status !== 200) throw new Error(`GET /interviewer/live → ${r.status} (INTV_PASS wrong?)`);
  return r.json();
}

// The first line of the question's README is its title; compare when the
// repo is beside us (tools/browser-test/ → project root is ../..).
function localTitle(level) {
  try {
    const ex = path.join(__dirname, '..', '..', 'exercises');
    const dir = fs.readdirSync(ex).find((d) => d.startsWith(String(level).padStart(2, '0') + '-'));
    if (!dir) return null;
    const first = fs.readFileSync(path.join(ex, dir, 'README.md'), 'utf8').split('\n')[0];
    return first.replace(/^#\s*/, '').trim() || null;
  } catch (e) {
    return null;
  }
}

// ---- lab mutations ------------------------------------------------------------
// RUNBOOK.md, T-30: the interviewer's POST /reset archives the run, sets the
// level back to 1 and stops the exercise containers. A GET is 405 and does
// nothing, which is why this is a POST with the interviewer credential.
async function resetLab() {
  const r = await fetch(`${BASE}/reset`, { method: 'POST', headers: asInterviewer(), redirect: 'manual' });
  expect(r.status === 302 || r.status === 303, `POST /reset → ${r.status} (redirect to /)`);
  const live = await liveJson();
  expect(live.current === 1, `interviewer view: current level is ${live.current}`);
  const home = await fetch(`${BASE}/`, { headers: asCandidate() });
  const state = labState(await home.text());
  expect(state === 'briefing', `candidate view: ${state} (exam not started)`);
}

async function unlockLab() {
  const r = await fetch(`${BASE}/unlock`, { method: 'POST', headers: asInterviewer() });
  expect(r.status === 200, `interviewer POST /unlock → ${r.status}`);
  expect(!(await liveJson()).input_lock.at, 'interviewer view: session unlocked');
}

// The same commands as smoketest.sh's level 1 fix, run inside the live node1
// container. The script goes to the remote bash on stdin (`bash -s`), like
// tools/remote-smoketest.sh does, so it never lands on the server's disk.
// String.raw keeps the backslashes exactly as smoketest.sh has them.
function applyQ1Fix() {
  const script = String.raw`
set -e
C=${NODE1}
docker exec "$C" bash -c '
    sed -i "s/^bind-address.*/bind-address             = 0.0.0.0/" /etc/my.cnf
    systemctl restart mysqld'
for _ in $(seq 1 240); do
    docker exec "$C" mysqladmin --protocol=socket ping >/dev/null 2>&1 && break
    sleep 1
done
sleep 15  # let the application pool reconnect after the restart
docker exec "$C" bash -c '
    c=$(mysql -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.PROCESSLIST WHERE USER=\"appuser\";" | tr -cd "0-9")
    echo "$c" > /home/candidate/answer.txt'
`;
  const args = ['-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new',
    '-o', 'IgnoreUnknown=WarnWeakCrypto', '-o', 'WarnWeakCrypto=no-pq-kex', '-p', SSH_PORT];
  if (SSH_KEY) args.push('-i', SSH_KEY);
  args.push(SSH_TARGET, 'bash -s');
  const r = spawnSync('ssh', args, { input: script, encoding: 'utf8', timeout: 300000 });
  if (r.status !== 0) {
    throw new Error(`Q1 fix over ssh failed (exit ${r.status}): ${(r.stderr || r.stdout || r.error || '').toString().trim()}`);
  }
}

// ---- browser bookkeeping ------------------------------------------------------
const pageErrors = [];     // uncaught exceptions, from any frame: these fail the run
const consoleErrors = [];  // console.error from the candidate page itself: these fail the run
const termConsole = [];    // console.error from inside ttyd's frame: reported, not fatal
const dialogs = [];        // every confirm/alert/beforeunload, accepted and recorded
const sockets = [];        // every websocket, with what the server sent over it
// A /check status a case provokes on purpose. Chromium logs every 4xx/5xx
// response as a console error; these are the answer under test, not a fault.
const expectedCheckStatus = new Set();

function watch(page, label) {
  page.on('pageerror', (e) => pageErrors.push(`[${label}] ${e.message}`));
  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const url = (m.location() || {}).url || '';
    const st = /^Failed to load resource: the server responded with a status of (\d+)/.exec(m.text());
    if (st && url === `${BASE}/check` && expectedCheckStatus.has(+st[1])) return;
    const line = `[${label}] ${m.text()} (${url})`;
    // ttyd's own client is not ours to judge; a broken guard or frame shows up
    // in case 4 anyway.
    (url.includes('/term/') ? termConsole : consoleErrors).push(line);
  });
  // Playwright dismisses dialogs by default, which would cancel every Send at
  // its confirm() and keep the page on a beforeunload prompt. Accept them all
  // and keep the text for the assertions.
  page.on('dialog', (d) => { dialogs.push({ type: d.type(), message: d.message() }); d.accept().catch(() => {}); });
  // ttyd draws with WebGL/canvas, so the prompt never appears as DOM text.
  // What the shell wrote is visible on the wire: ttyd output frames are the
  // raw bytes behind a one-character opcode.
  page.on('websocket', (ws) => {
    const rec = { url: ws.url(), text: '', error: '' };
    sockets.push(rec);
    ws.on('framereceived', (f) => {
      rec.text += String(f.payload);
      if (rec.text.length > 65536) rec.text = rec.text.slice(-32768);
    });
    ws.on('socketerror', (e) => { rec.error = String(e); });
  });
}

function noErrors(when) {
  const errs = pageErrors.concat(consoleErrors);
  expect(errs.length === 0, `no page errors or console errors ${when}` + (errs.length ? ':\n    ' + errs.join('\n    ') : ''));
}

async function snapshot(context, name) {
  try {
    fs.mkdirSync(OUT, { recursive: true });
    let i = 0;
    for (const p of context.pages()) {
      const file = path.join(OUT, `${name}${i++ ? '-' + i : ''}.png`);
      await p.screenshot({ path: file }).catch(() => {});
      info(`screenshot: ${file}`);
    }
  } catch (e) { /* a screenshot is a courtesy */ }
}

async function runCase(context, id, desc, fn, opts = {}) {
  info(`C${id}: ${desc}`);
  try {
    await fn();
    summary.push(`C${id} ${desc}: ${G}OK${N}`);
    return true;
  } catch (e) {
    fail(`C${id}: ${e.message}`);
    summary.push(`C${id} ${desc}: ${R}FAIL${N} — ${e.message.split('\n')[0]}`);
    failures += 1;
    if (context) await snapshot(context, `c${id}`);
    // Later cases build on this one (no page to click Send on, say).
    if (opts.gate) throw new Abort(`C${id} failed`);
    return false;
  }
}

const header = (page, n) => page.locator('header .title').filter({ hasText: `Question ${n} /` });

// ---- the run ------------------------------------------------------------------
async function main() {
  // Pre-flight, before a browser is opened: whose lab is this? A candidate
  // may be live. Anything past the briefing is refused unless FORCE=1, in
  // which case the lab is reset first so the run starts from the briefing.
  const home = await fetch(`${BASE}/`, { headers: asCandidate() });
  if (home.status === 401) { fail('the candidate credentials were rejected (401) — CAND_PASS is wrong'); process.exit(2); }
  const state = labState(await home.text());
  if (!DRY && state !== 'briefing') {
    if (!FORCE) {
      fail(`the lab is at "${state}", not at the briefing — an exam may be in progress. Refusing to touch it.`);
      info('FORCE=1 runs anyway (it resets the lab first). Never do that during an interview.');
      process.exit(2);
    }
    info(`FORCE=1: the lab is at "${state}"; resetting it before the run`);
    mutated = true;
    await resetLab();
  }

  let browser;
  try {
    browser = await chromium.launch();
  } catch (e) {
    fail('could not launch Chromium: ' + e.message.split('\n')[0]);
    info('The pinned Playwright expects the Chromium build already cached under ~/Library/Caches/ms-playwright.');
    info('If it is missing: (cd tools/browser-test && npx playwright install chromium)');
    process.exit(3);
  }
  // httpCredentials answers the 401 challenge, and Chromium then caches the
  // credential for the origin, which is what the terminal's websocket
  // handshake relies on — exactly the path a real browser takes.
  const context = await browser.newContext({
    httpCredentials: { username: 'candidate', password: CAND_PASS },
    viewport: { width: 1400, height: 900 },
  });
  context.setDefaultTimeout(30000);
  // The page reports navigator.webdriver to the controller on load. In a full
  // run that flag is expected and the reset archives it; dry mode may be
  // looking at someone else's live run, so it never reaches the server.
  if (DRY) await context.route('**/input-event', (r) => r.fulfill({ status: 204, body: '' }));
  const page = await context.newPage();
  watch(page, 'A');
  let pageB = null;

  try {
    await runCase(context, 1, 'no credentials → 401; candidate credentials → briefing', async () => {
      const anon = await fetch(`${BASE}/`);
      expect(anon.status === 401 && /basic/i.test(anon.headers.get('www-authenticate') || ''),
        'GET / without credentials → 401 with a Basic challenge');
      expect(home.status === 200, 'GET / with the candidate credentials → 200');
      if (DRY) info(`lab state: ${state} (dry mode does not require the briefing)`);
      else expect(state === 'briefing', 'the lab is at the briefing: exam not started');
      await page.goto(`${BASE}/`);
      const title = await page.title();
      if (state === 'briefing') {
        expect(/Before you begin/.test(title), `the briefing renders in Chromium ("${title}")`);
        expect(await page.locator('#startbtn').isDisabled(), 'Start is disabled until the rules are ticked');
      } else {
        expect(title.length > 0, `the page renders in Chromium ("${title}")`);
      }
    }, { gate: true });
    if (DRY) return;

    await runCase(context, 2, 'Start the test → question 1', async () => {
      mutated = true;
      await page.check('#ack');
      expect(await page.locator('#startbtn').isEnabled(), 'ticking the acknowledgement enables Start');
      await page.click('#startbtn');
      try {
        await header(page, 1).waitFor({ timeout: BOOT_MS });
      } catch (e) {
        const err = await page.locator('#starterr').textContent().catch(() => '');
        throw new Error('question 1 did not render after Start' + (err && err.trim() ? ': ' + err.trim() : ''));
      }
      ok('Start → the question 1 page');
      const h1 = ((await page.locator('#exercise h1').textContent()) || '').trim();
      const want = localTitle(1);
      expect(h1.length > 0 && (!want || h1 === want), `question title rendered: "${h1}"`);
      expect(/^Question 1 \//.test(await page.title()), 'window title names question 1');
    }, { gate: true });

    await runCase(context, 3, 'watermark, copy/selection block, Files editor exempt', async () => {
      // The header is in the DOM before the stylesheet has loaded: Start lands
      // on / by navigation, and a locator does not wait for CSS.
      await page.waitForFunction(() => [...document.styleSheets].some((x) => /\/static\/style\.css/.test(x.href || '')));
      const bg = await page.locator('#exercise').evaluate((el) => getComputedStyle(el).backgroundImage);
      let decoded = bg;
      try { decoded = decodeURIComponent(bg); } catch (e) { /* keep raw */ }
      expect(/data:image\/svg\+xml/.test(bg) && /PROCTORED HIRING ASSESSMENT/.test(decoded),
        'the #exercise watermark is a tiled SVG saying PROCTORED HIRING ASSESSMENT');

      // Real gestures, so both layers (user-select: none and the selectstart
      // block) are what stops them, not a synthetic event.
      await page.locator('#exercise h1').click({ clickCount: 3 });
      const readme = page.locator('#exercise .readme');
      const box = await readme.boundingBox();
      await page.mouse.move(box.x + 8, box.y + 8);
      await page.mouse.down();
      await page.mouse.move(box.x + box.width - 8, box.y + Math.min(box.height - 8, 200), { steps: 8 });
      await page.mouse.up();
      const selected = await page.evaluate(() => String(window.getSelection()));
      expect(selected === '', 'selecting question text yields an empty selection');
      const copyBlocked = await readme.evaluate((el) => !el.dispatchEvent(new ClipboardEvent('copy', { bubbles: true, cancelable: true })));
      expect(copyBlocked, 'a copy event on the question is prevented');

      await page.click('#filesbtn');
      await page.locator('#filepanel').waitFor({ state: 'visible' });
      const name = 'browser-test.txt';
      await page.fill('#fp-new', name);
      await page.keyboard.press('ControlOrMeta+a');
      const nameSel = await page.locator('#fp-new').evaluate((i) => i.selectionEnd - i.selectionStart);
      expect(nameSel === name.length, 'selection works in the filename box');
      await page.click('#fp-create');
      const editor = page.locator('#editor-text');
      expect(await editor.isEnabled(), 'Create opens the editor');
      await editor.click();
      await page.keyboard.type('SELECT 1;');
      expect((await editor.inputValue()) === 'SELECT 1;', 'typing into the Files editor works');
      await page.keyboard.press('ControlOrMeta+a');
      const [s, e] = await editor.evaluate((t) => [t.selectionStart, t.selectionEnd]);
      expect(s === 0 && e === 'SELECT 1;'.length, 'selecting in the Files editor works');
      const copyAllowed = await editor.evaluate((el) => el.dispatchEvent(new ClipboardEvent('copy', { bubbles: true, cancelable: true })));
      expect(copyAllowed, 'a copy event in the Files editor is not prevented');

      // How a browser agent writes: the whole string in one CDP insertText.
      await page.keyboard.press('End');
      await page.keyboard.insertText(' -- written by an agent');
      await page.waitForURL(`${BASE}/`);
      await page.getByRole('heading', { name: 'Session locked' }).waitFor();
      const editorLock = (await liveJson()).input_lock;
      expect(editorLock && editorLock.reason.startsWith('Files editor:'),
        'the dashboard records why the session locked');
      const check = await fetch(`${BASE}/check`, { method: 'POST', headers: { ...asCandidate(), 'Content-Type': 'application/json' }, body: JSON.stringify({ level: 1 }) });
      expect(check.status === 423, 'Send is refused while locked');
      const file = await fetch(`${BASE}/file`, { method: 'POST', headers: { ...asCandidate(), 'Content-Type': 'application/json' }, body: JSON.stringify({ node: 'node1', name, content: 'bypass' }) });
      expect(file.status === 423, 'Files save is refused while locked');
      const term = await fetch(`${BASE}/term/node1/`, { headers: asCandidate() });
      expect(term.status === 403, 'a new terminal connection is refused while locked');
      await unlockLab();
      await header(page, 1).waitFor({ timeout: 10000 });
    });

    await runCase(context, 4, 'terminal frame: guard injected, websocket connected, shell prompt', async () => {
      const frameEl = page.locator('#frames iframe[data-node="node1"]').first();
      expect((await frameEl.count()) === 1 && (await frameEl.getAttribute('src')) === '/term/node1/',
        'a terminal iframe for node1 points at /term/node1/');
      const frame = await until(() => page.frames().find((f) => /\/term\/node1\//.test(f.url())), 15000, 'the terminal frame');
      // Until ttyd answers, nginx serves a self-refreshing "Starting exercise"
      // page in the same frame; the locator waits across those reloads. The
      // guard plants this element, so its presence means the injected script
      // actually ran, not just that the tag is there.
      await frame.locator('#interview-agent-notice').waitFor({ state: 'attached', timeout: BOOT_MS });
      ok('terminal-guard.js ran inside the frame (agent notice planted)');
      expect((await frame.locator('script[src="/static/terminal-guard.js"]').count()) === 1,
        'nginx injected <script src="/static/terminal-guard.js"> into ttyd\'s page');
      await frame.locator('.xterm').waitFor({ state: 'attached', timeout: 30000 });
      ok('xterm mounted in the frame');
      const sock = await until(
        () => sockets.find((s) => /\/term\/node1\/ws/.test(s.url) && /candidate@node1/.test(s.text)),
        BOOT_MS,
        'a shell prompt over the terminal websocket' +
          (sockets.length ? ` (seen: ${sockets.map((s) => s.url + (s.error ? ' error=' + s.error : '')).join(', ')})` : ' (no websocket opened)'),
      );
      ok(`websocket ${sock.url} connected and the shell prompted as candidate@node1`);
    });

    // What the ChatGPT agent did unhindered: type into the terminal. A browser
    // agent never presses a key; it inserts the command in one piece. Some
    // drive real key events instead, at machine speed. Both must be dropped
    // before the shell runs anything, and typing at a person's pace must not.
    await runCase(context, 5, 'terminal: human typing works; rejected input locks the session', async () => {
      const frame = page.frames().find((f) => /\/term\/node1\//.test(f.url()));
      const tag = Date.now().toString(36).toUpperCase();
      const wire = () => sockets.filter((x) => /\/term\/node1\/ws/.test(x.url)).map((x) => x.text).join('');
      await frame.locator('.xterm-helper-textarea').focus();
      const before = await page.evaluate(() => window.InterviewCadence.count());
      await humanType(page, `echo HUMAN_${tag}`);
      await page.keyboard.press('Enter');
      // Each echoed keystroke is its own frame behind an opcode byte, so the
      // marker only appears in one piece as the command's output.
      await until(() => wire().includes(`HUMAN_${tag}`), 10000, 'the shell to run the typed command');
      ok('typed at a person\'s pace: the shell ran it');
      // C3's notice may still be fading out; what matters is no new rejection.
      expect((await page.evaluate(() => window.InterviewCadence.count())) === before, 'typing added no rejection');

      await page.keyboard.insertText(`echo AGENT_${tag}`);
      await page.getByRole('heading', { name: 'Session locked' }).waitFor();
      expect(!wire().includes(`AGENT_${tag}`), 'the inserted command never reached the shell');
      const lock = (await liveJson()).input_lock;
      expect(lock && /inserted/.test(lock.reason), 'the dashboard shows the terminal rejection and lock');
      await unlockLab();
      await header(page, 1).waitFor({ timeout: 10000 });
      noErrors('while rejecting input');
    });

    // The controller advances on a failed grade by design (README, "How
    // submission works"), so an unsolved Send against the real server would
    // burn question 1. A 503 is the one Send outcome that keeps the level,
    // and a healthy lab never produces one: it is answered here, once, in
    // the browser. The server is not involved; the request the handler builds
    // is, and that is where the ReferenceError lived.
    await runCase(context, 6, 'Send while unsolved: request carries the level; a refused check keeps question 1', async () => {
      const msg = 'The check could not run (browser-test). Nothing was recorded; reload the page and send again.';
      expectedCheckStatus.add(503);
      await page.route('**/check', (route) => route.fulfill({
        status: 503, contentType: 'application/json',
        body: JSON.stringify({ submitted: false, error: msg }),
      }));
      const n = dialogs.length;
      const reqP = page.waitForRequest((r) => r.url() === `${BASE}/check` && r.method() === 'POST', { timeout: 15000 });
      await page.click('#check');
      const req = await reqP;
      expect(dialogs.slice(n).some((d) => d.type === 'confirm' && /Send your work/.test(d.message)),
        'Send asks "Send your work and move on…" first');
      expect(req.postDataJSON().level === 1, 'the handler POSTs {level: 1} to /check');
      await page.locator('#submit-close').waitFor({ state: 'visible', timeout: 10000 });
      expect(((await page.locator('#submit-msg').textContent()) || '').trim() === msg, 'the 503 message is shown in the modal');
      expect(await page.locator('#submit-modal .spinner').isHidden(), 'the spinner is gone');
      expect(await page.locator('#check').isEnabled(), 'Send is enabled again');
      await page.unroute('**/check');
      expectedCheckStatus.delete(503);
      await page.click('#submit-close');
      expect(await page.locator('#submit-modal').isHidden(), 'Close hides the modal');
      await page.reload();
      await header(page, 1).waitFor();
      ok('the lab is still on question 1');
      noErrors('during the refused Send');
    });

    await runCase(context, 7, 'Q1 fix over ssh → Send → wait modal → question 2', async () => {
      if (!SSH_TARGET) throw new Error('SSH_TARGET is not set; the Q1 fix needs ssh');
      info(`applying the Q1 fix inside ${NODE1} over ssh (30-60s)`);
      applyQ1Fix();
      ok('Q1 fix applied');

      // A second tab stays on question 1: it becomes the stale page for C8.
      pageB = await context.newPage();
      watch(pageB, 'B');
      await pageB.goto(`${BASE}/`);
      await header(pageB, 1).waitFor();
      ok('a second tab is open on question 1 (for the stale Send)');

      const n = dialogs.length;
      const reqP = page.waitForRequest((r) => r.url() === `${BASE}/check` && r.method() === 'POST', { timeout: 15000 });
      const respP = page.waitForResponse((r) => r.url() === `${BASE}/check`, { timeout: CHECK_MS });
      // The page reloads the moment the response lands and Chromium drops the
      // body with the old document, so read it on the way through instead.
      let body = null;
      await page.route('**/check', async (route) => {
        const r = await route.fetch({ timeout: CHECK_MS });
        try { body = await r.json(); } catch (e) { body = null; }
        await route.fulfill({ response: r });
      });
      await page.click('#check');
      const req = await reqP;
      expect(dialogs.slice(n).some((d) => d.type === 'confirm' && /Send your work/.test(d.message)), 'Send asks for confirmation');
      expect(req.postDataJSON().level === 1, 'the handler POSTs {level: 1} to /check');
      await page.locator('#submit-modal').waitFor({ state: 'visible', timeout: 5000 });
      expect(/Checking your work on the server/.test((await page.locator('#submit-msg').textContent()) || ''),
        'wait modal: "Checking your work on the server…"');
      expect(await page.locator('#submit-detail').isVisible(), 'wait modal explains the wait and shows the counter');
      const ticked = await Promise.race([
        page.waitForFunction(() => /^[1-9]\d* s$/.test(document.getElementById('submit-elapsed').textContent), null, { timeout: 20000 })
          .then(() => true, () => false),
        respP.then(() => false, () => false),
      ]);
      if (ticked) ok('the elapsed counter ticks'); else info('the check returned before the counter ticked');
      const resp = await respP;
      await page.unroute('**/check');
      expect(resp.status() === 200, `POST /check → ${resp.status()}${body ? ' ' + JSON.stringify(body) : ''}`);
      expect(!!body && body.submitted === true, 'the check reports submitted: true');
      await header(page, 2).waitFor({ timeout: BOOT_MS });
      ok('the page landed on question 2');
      const live = await liveJson();
      const l1 = (live.levels || []).find((l) => l.level === 1) || {};
      expect(live.current === 2 && l1.outcome === 'passed',
        `interviewer view: current=${live.current}, question 1 ${l1.outcome || '?'} ${(l1.check_output || '').trim()}`);
      noErrors('during Send');
    }, { gate: true });

    await runCase(context, 8, 'stale tab Send → 409 → reloads onto question 2', async () => {
      expectedCheckStatus.add(409);
      const respP = pageB.waitForResponse((r) => r.url() === `${BASE}/check`, { timeout: CHECK_MS });
      await pageB.click('#check');
      const resp = await respP;
      expect(resp.status() === 409, `Send from the tab still showing question 1 → ${resp.status()}`);
      await header(pageB, 2).waitFor({ timeout: BOOT_MS });
      ok('the stale tab reloaded itself onto question 2');
      noErrors('after the stale Send');
    });
  } finally {
    if (termConsole.length) {
      info(`console errors inside the terminal frame (not fatal):\n    ${termConsole.join('\n    ')}`);
    }
    await browser.close().catch(() => {});
    if (mutated) await runCase(null, 9, 'reset → level 1, not started', resetLab);
  }
}

// Ctrl-C mid-run must not leave the exam started for the next candidate.
process.on('SIGINT', async () => {
  info('interrupted');
  if (mutated) { try { await resetLab(); } catch (e) { fail('reset after interrupt failed: ' + e.message); } }
  process.exit(130);
});

main()
  .catch((e) => {
    if (!(e instanceof Abort)) { fail('unexpected error: ' + (e.stack || e.message)); failures += 1; }
  })
  .finally(() => {
    console.log('\n==== Summary ====');
    for (const line of summary) console.log(`  ${line}`);
    if (DRY) info('dry mode: only C1 ran; nothing was changed and no reset was needed');
    if (failures > 0) { console.log(`\n${R}${failures} failure(s)${N}`); process.exit(1); }
    process.exit(0);
  });
