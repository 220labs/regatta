#!/usr/bin/env node
/* engine_proof.js — the Engine room's adapter proof as a helm case (docs/engine-room-2026-11-02.md S3; carried from the
   design's tools/prove_adapter.js): feed bin/engine_adapter.js the real-shaped documents (engine_fixture.js, and the
   cases below built from the same shapes) and assert what comes out: no throw, no NaN, no path, the right counts and
   states; S4's fields absent and present; a source that did not read is unread, never zero. The design review's
   central finding (2026-11-02): the first fixture invented fields, so the adapter was proven on nothing real.
   Usage: node tests/engine_proof.js  →  PASS/FAIL lines, exit 1 on a FAIL (tests/test_engine.sh runs it). */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const ctx = {}; ctx.window = ctx;   // the files set window.X; a browser-less window
vm.createContext(ctx);
for (const f of [path.join(__dirname, 'engine_fixture.js'), path.join(__dirname, '..', 'bin', 'engine_adapter.js')]) vm.runInContext(fs.readFileSync(f, 'utf8'), ctx, { filename: path.basename(f) });
const SRC = ctx.ENGINE_SRC, OFF = ctx.ENGINE_SRC_OFF, ADAPT = ctx.ENGINE_ADAPT;
const NOW = SRC.hosts.at;
let pass = 0, fail = 0;
const ok = (name, cond, detail) => { if (cond) pass++; else fail++; console.log((cond ? 'PASS ' : 'FAIL ') + name + (cond || detail == null ? '' : ' — ' + detail)); };
const clone = (o) => JSON.parse(JSON.stringify(o));
const run = (name, src) => { try { return ADAPT(src, NOW); } catch (e) { ok(name + ': the adapter did not throw', false, e.message); return null; } };
const walk = (o, f, p = '') => { if (o && typeof o === 'object') Object.keys(o).forEach((k) => walk(o[k], f, p + '.' + k)); else f(o, p); };
const noNaN = (E) => { const bad = []; walk(E, (v, p) => { if (typeof v === 'number' && !isFinite(v)) bad.push(p); }); return bad; };
const noPath = (E) => { const bad = []; walk(E, (v, p) => { if (typeof v === 'string' && /\/Users\/|\/home\/|~\/|https?:\/\/|<home>/.test(v)) bad.push(p + '=' + v.slice(0, 60)); }); return bad; };
const texts = (E) => { const out = []; walk(E, (v) => { if (typeof v === 'string') out.push(v); }); return out.join('\n'); };

// 1. the fixture whole: the night as the real tools would print it
let E = run('the fixture', SRC);
if (E) {
  ok('no NaN anywhere in the output', noNaN(E).length === 0, noNaN(E).join(', '));
  ok('no path, home folder or URL anywhere in the output (the desk\'s why and the cards\' url never pass)', noPath(E).length === 0, noPath(E).join(', '));
  ok('6 rows → 6 cards; host-e (no_sample) and host-c (3.2 h) read unread, four awake', E.hosts.length === 6 && E.hosts.filter((h) => h.state === 'unread').map((h) => h.id).join() === 'host-c,host-e' && E.hosts.filter((h) => h.state === 'awake').length === 4, E.hosts.map((h) => h.id + ':' + h.state).join());
  const A = Object.fromEntries(E.hosts.map((h) => [h.id, h]));
  ok('host-a is full by its cap while headroom says room (memory only): word "full", room true, 3 live runs', A['host-a'].word === 'full' && A['host-a'].room === true && A['host-a'].live === 3, A['host-a'].word + ' ' + A['host-a'].room);
  ok('host-b refuses by headroom\'s rate rule (the real reading): word "no room", its reason headroom\'s own line, and a Needs line with Limits', A['host-b'].word === 'no room' && /110\.3 MB\/s swapping, over 10 MB\/s/.test(A['host-b'].reason) && E.needs.some((n) => /host-b refuses runs: no room: 110\.3/.test(n.text) && n.act === 'limits'));
  ok('node-1: busy 3 counts the reservation, so 2 live runs and 1 reserved; word "room"', A['node-1'].live === 2 && A['node-1'].reserved === 1 && A['node-1'].word === 'room');
  ok('node-2: room null reads "room ?", runs null reads unread (never no runs), memory unread; both in Needs with no action', A['node-2'].word === 'room ?' && A['node-2'].runsUnread === true && A['node-2'].mem === null && E.needs.filter((n) => /^node-2:/.test(n.text) && !n.act).length === 2);
  ok('host-e: a row that does not parse is unread with a fixed note', A['host-e'].state === 'unread' && A['host-e'].note === 'no sample: its row does not parse');
  ok('checks: null on every row (S2 carries none) but the desk\'s own host, which takes the ops row\'s check {slots_busy, waiting}, its cap unknown', A['host-a'].checks && A['host-a'].checks.join('/') === '1/2/' && E.hosts.filter((h) => h.id !== 'host-a').every((h) => h.checks === null) && E.ops.checks.slice(0, 2).join('/') === '1/2' && E.ops.checks[2] === null);
  ok('capacity sums live runs over the awake hosts, reservations apart: 6 of 11, 1 reserved', E.ops.runs.join('/') === '6/11' && E.ops.reserved === 1, E.ops.runs.join('/') + ' r' + E.ops.reserved);
  ok('a run\'s login is the record\'s label; a record with none reads null, never a path', E.running.filter((r) => r.login).length === 5 && E.running.filter((r) => r.login === null).length === 1);
  ok('10 entries → 10 rows: 9 queued, 1 claimed (running on node-1, tone run, Watch and End)', E.queue.length === 10 && E.queued.length === 9 && E.claimed.length === 1 && E.claimed[0].tone === 'run' && E.claimed[0].acts.join() === 'watch,end', E.queued.length + '/' + E.claimed.length);
  const Q = Object.fromEntries(E.queue.map((q) => [q.qid, q]));
  ok('the 20-hour wait behind a held pin on an unread host: bad, says why, kind "held", no Unpin, Cancel first', Q['fleet:fleet-queue-s5-fix'].tone === 'bad' && /pinned to host-c/.test(Q['fleet:fleet-queue-s5-fix'].why) && /waiting 20 h/.test(Q['fleet:fleet-queue-s5-fix'].why) && Q['fleet:fleet-queue-s5-fix'].pinKind === 'held' && Q['fleet:fleet-queue-s5-fix'].acts.indexOf('unpin') < 0 && Q['fleet:fleet-queue-s5-fix'].acts[0] === 'cancel', JSON.stringify(Q['fleet:fleet-queue-s5-fix'].acts));
  ok('a typed --pin no login holds (pin_login false) to a full host: waits for room on host-a with the cap as its why; Unpin offered, by-session kept', Q['fleet:lease-renewal-s6'].pinKind === 'typed' && Q['fleet:lease-renewal-s6'].pinLogin === false && /waits for room on host-a/.test(Q['fleet:lease-renewal-s6'].state) && /3 of 3 runs/.test(Q['fleet:lease-renewal-s6'].why) && Q['fleet:lease-renewal-s6'].acts.indexOf('unpin') >= 0 && Q['fleet:lease-renewal-s6'].by === 'b1c2d3e4', Q['fleet:lease-renewal-s6'].state + ' | ' + Q['fleet:lease-renewal-s6'].why);
  ok('a pinned row as S2 prints it today (no pin_kind, no pinned_why): kind null, no Unpin', Q['fleet:lantern-s2'].pin === 'host-b' && Q['fleet:lantern-s2'].pinKind === null && Q['fleet:lantern-s2'].acts.indexOf('unpin') < 0);
  ok('the entry refused three times: bad, its last refusal with the refusing hosts, Kick first', Q['fleet:night-digest-s5'].tone === 'bad' && /last: the run cap \(2 of 2 busy at its start\) \(host-a, host-b\)/.test(Q['fleet:night-digest-s5'].why) && Q['fleet:night-digest-s5'].acts[0] === 'kick', Q['fleet:night-digest-s5'].why);
  ok('needs (a list) reads as a chip and a why, never a host match the rows cannot make', Q['fleet:night-digest-s5'].needs === 'macos' && /needs macos: the rows carry no features/.test(Q['fleet:night-digest-s5'].why));
  ok('a released preference (prefer_off): soft chip "released", said in the why', Q['fleet:mirror-retention-s2'].released === true && /preferred host-a, released/.test(Q['fleet:mirror-retention-s2'].why));
  ok('a finish pinned to host-a with pin_kind typed: held (every pinned finish is, S4), no Pin, no Unpin; Kick and Cancel', Q['fleet:harbor-lights-land'].finish === true && Q['fleet:harbor-lights-land'].pinKind === 'held' && Q['fleet:harbor-lights-land'].acts.join() === 'kick,cancel', JSON.stringify([Q['fleet:harbor-lights-land'].pinKind, Q['fleet:harbor-lights-land'].acts]));
  ok('an entry with after: waits for its step, Cancel only, no Pin', Q['fleet:slot-scheduler-s6'].state === 'waits for S5' && Q['fleet:slot-scheduler-s6'].acts.join() === 'cancel');
  ok('a plain entry is claimable where a host has room (node-1 and node-2, whose memory did not read, so dispatch goes ahead there; host-c is unread), Kick first', /claimable: node-1, node-2 have room/.test(Q['fleet:intake-lanes-s3'].state) && Q['fleet:intake-lanes-s3'].acts[0] === 'kick' && Q['fleet:intake-lanes-s3'].acts.indexOf('pin') >= 0, Q['fleet:intake-lanes-s3'].state);
  ok('the logins: pace is account\'s five-hour window share (acct-c 61 %), the words from the judge line', E.ops.logins.map((l) => l.word).join() === 'eligible,eligible,resting,week spent,parked' && E.ops.logins[2].pace === 61, E.ops.logins.map((l) => l.word + '@' + l.pace).join());
  ok('acct-e parked 30 h ago: its row shows its own age (1800 min); the logins chip ages by the walked logins only (4 min)', E.ops.logins[4].sampled === 1800 && E.sources.logins.age === 4, E.ops.logins[4].sampled + ' ' + E.sources.logins.age);
  const Bd = Object.fromEntries(E.ops.ci_budgets.map((b) => [b.name, b]));
  ok('3 budgets: hosted-vms into its reserve (24,600 × 1.1 ≥ 24,000) with issue #91, runner-minutes ok, org-minutes unread (absent) with no numbers', Bd['hosted-vms'].level === 'reserve' && Bd['hosted-vms'].issue === 91 && Bd['runner-minutes'].level === 'ok' && Bd['org-minutes'].unread === 'no token for it on the desk' && Bd['org-minutes'].used === null && Bd['org-minutes'].cap === null, JSON.stringify(Bd['org-minutes']));
  ok('the week share from ci-budgets.json: hosted-vms 5,740 of 9,000 = 64 %, runner-minutes 980 of 1,050 = 93 %; CI of the week is the max, 93', Bd['hosted-vms'].week === 64 && Bd['runner-minutes'].week === 93 && E.ops.ci === 93, Bd['hosted-vms'].week + ' ' + Bd['runner-minutes'].week + ' ' + E.ops.ci);
  ok('Intake: 7 cards, ages from created (a null one stays null), the repo its last part, mentions from the kind (5 mention, 2 do not)', E.intake.length === 7 && E.intake.filter((c) => c.age === null).length === 1 && E.intake.every((c) => c.repo.indexOf('/') < 0) && E.intake.filter((c) => c.mentions).length === 5 && E.alarms === 3, JSON.stringify(E.intake.map((c) => [c.repo, c.mentions, c.age == null ? null : +c.age.toFixed(1)])));
  ok('Needs a hand: 13 lines — the stale pile, host-b\'s rate, node-2 twice, host-c and host-e unread, 2 bad entries, acct-c and acct-d, a budget into its reserve and one unread, the alarms', E.needs.length === 13, E.needs.length + ': ' + E.needs.map((n) => n.text.slice(0, 28)).join(' | '));
  ok('the source chips: hosts 9 min (the oldest awake peer), queue 0, ci 6, intake 6, none off', E.sources.hosts.age === 9 && E.sources.queue.age === 0 && E.sources.ci.age === 6 && E.sources.intake.age === 6 && !E.sources.ci.off && !E.sources.intake.off, JSON.stringify([E.sources.hosts.age, E.sources.queue.age, E.sources.ci.age, E.sources.intake.age]));
  ok('no confined topic anywhere: the fence is a count (1 run on host-a, 2 entries dropped)', A['host-a'].confined === 1 && E.dropped === 2 && !/confined-|secret-/.test(texts(E)));
}

// 2. the desk off (this laptop's real `ops status --json` and `ops intake --json`, 2026-11-02): no row, no cards, fixed words
E = run('the desk off', Object.assign(clone(SRC), { ops: OFF.ops, intake: OFF.intake }));
if (E) {
  ok('desk off: no NaN, no path (the why names <home>/ops.jsonl and never passes)', noNaN(E).length === 0 && noPath(E).length === 0, noPath(E).join(', '));
  ok('desk off: CI null, no budgets, checks null everywhere, the chips say off in fixed words', E.ops.ci === null && E.ops.ci_budgets.length === 0 && E.ops.checks === null && E.hosts.every((h) => h.checks === null) && E.sources.ci.off && E.sources.ci.live === 'off: no desk sample on this host' && E.sources.intake.off && E.sources.intake.live === 'off: no intake on this host', E.sources.ci.live + ' | ' + E.sources.intake.live);
  ok('desk off: Intake empty, no alarms line in Needs', E.intake.length === 0 && E.alarms === 0 && !E.needs.some((n) => /alarms/.test(n.text)));
}

// 3. a budget in every state the desk prints (read_budget :701-710), and one with no cap in ci-budgets.json
{
  const s = clone(SRC);
  s.ops.row.budget = { a: { state: 'refused', why: 'GitHub\'s billing answered 403' }, b: { state: 'unread', why: 'the budget names no `user` or `org`' }, c: { state: 'absent', why: 'no CIRCLECI_TOKEN in <path>' }, d: { state: 'ok', used: 10, week_used: 5, unit: 'minutes', net_amount: 0 }, e: { state: 'ok', used: 100, week_used: 50, unit: 'minutes', net_amount: 12.5, cap: 3000, share: 0.033 } };
  s.budgets.accounts = { d: { provider: 'github', user: 'acct-x' }, e: { provider: 'github', org: 'acct-y', month_minutes: 3000, week_share: 0.35 } };
  s.alarms = {};
  E = run('every budget state', s);
  if (E) {
    const Bd = Object.fromEntries(E.ops.ci_budgets.map((b) => [b.name, b]));
    ok('refused, unread, absent: each unread with its fixed word and no numbers; nothing thrown', Bd.a.unread === 'the provider refused the read' && Bd.b.unread === 'the read did not answer' && Bd.c.unread === 'no token for it on the desk' && [Bd.a, Bd.b, Bd.c].every((b) => b.used === null && b.cap === null && b.week === null));
    ok('ok with no cap anywhere: numbers kept, level null with its why, no NaN', Bd.d.used === 10 && Bd.d.cap === null && Bd.d.level === null && Bd.d.share === null && noNaN(E).length === 0, JSON.stringify(Bd.d));
    ok('netAmount above zero reads reserve whatever the share (ops :738)', Bd.e.level === 'reserve' && /beyond its plan/.test(Bd.e.levelWhy));
    ok('CI of the week: the one budget with a week cap, 50 of 1,050 = 5 %', E.ops.ci === 5, E.ops.ci);
    ok('Needs: three unread lines (wait) and one reserve line (bad) with its numbers', E.needs.filter((n) => /^CI · [abc] unread/.test(n.text) && n.tone === 'wait').length === 3 && E.needs.some((n) => /^CI · e into its reserve: 100 of 3,000 minutes$/.test(n.text)), E.needs.filter((n) => /^CI/.test(n.text)).map((n) => n.text).join(' | '));
  }
}

// 4. a host row with every optional field missing, a row with torn fence, headroom's refusals in its own words
{
  const s = clone(SRC);
  s.hosts.hosts['node-3'] = { host: 'node-3', at: NOW - 60, load: {}, mem: {}, limits: {}, headroom: { room: false, reason: 'no room: 8 % free, under 10 %; 9.2 GB swap, over 8 GB', near: ['avail', 'swap'] }, slots: {}, fence: { confined: 0, unreadable: true }, runs: null };
  s.hosts.hosts['host-a'].fence = { confined: 3, unreadable: true }; s.hosts.hosts['host-a'].runs = null;
  s.hosts.queue.fence_unreadable = true; s.hosts.queue.entries = [];
  E = run('bare rows and a torn registry', s);
  if (E) {
    const A = Object.fromEntries(E.hosts.map((h) => [h.id, h]));
    ok('a bare row: cap 0, load null, memory null, swap "", no NaN; headroom\'s "no room" in its words', A['node-3'].runs.join('/') === '0/0' && A['node-3'].load === null && A['node-3'].mem === null && A['node-3'].swap === '' && A['node-3'].word === 'no room' && noNaN(E).length === 0, JSON.stringify(A['node-3']).slice(0, 200));
    ok('a torn registry on host-a: runs null, unreadable true, confined 3 counted; the queue says fence_unreadable', A['host-a'].unreadable === true && A['host-a'].runsUnread === true && A['host-a'].confined === 3 && E.fenceUnreadable === true && E.queue.length === 0);
    ok('host-a full by cap still (busy 3 of 3 from slots) with its runs unknown', A['host-a'].full === true && A['host-a'].word === 'full');
  }
}

// 5. the hosts document itself unreadable: the ref did not read, one host, an entry pinned to a host with no row
{
  const s = clone(SRC);
  s.hosts.hosts = { 'host-a': s.hosts.hosts['host-a'] }; s.hosts.ref = { unreadable: 'the hosts ref does not read', offline: 'the queue home did not answer; its last fetch shown' };
  E = run('the ref unreadable', s);
  if (E) {
    const Q = Object.fromEntries(E.queue.map((q) => [q.qid, q]));
    ok('an entry pinned to a host with no row: cannot start, said; Cancel only', /cannot start: host-c has no row/.test(Q['fleet:fleet-queue-s5-fix'].state) && Q['fleet:fleet-queue-s5-fix'].acts.join() === 'cancel', Q['fleet:fleet-queue-s5-fix'].state);
    ok('the ref\'s two words pass as hosts printed them (fixed words, no address)', E.ref.unreadable === 'the hosts ref does not read' && /did not answer/.test(E.ref.offline));
    ok('no host has room: every plain entry waits for room', E.queued.filter((q) => !q.pin && !q.after && q.attempts < 3).every((q) => q.state === 'waits for room'));
  }
}

// 6. nothing at all: empty documents, as a poll on a host with no queue home might hand over
E = run('empty documents', { hosts: { at: NOW, here: 'host-z', hosts: {}, queue: { entries: [], dropped: 0, fence_unreadable: false, unreadable: true }, logins: [], records: { stale: 0, oldest_days: 0 }, ref: { unreadable: 'no queue home here (wharf-runs/queue-repo)', offline: null } }, ops: { row: null, why: 'x' }, budgets: {}, alarms: {}, intake: { open: [], why: 'y', sig: '' } });
if (E) ok('empty: 0 hosts, 0 rows, 0 logins, CI null, no NaN, the queue marked unreadable', E.hosts.length === 0 && E.queue.length === 0 && E.ops.logins.length === 0 && E.ops.ci === null && E.queueUnreadable === true && noNaN(E).length === 0);
E = run('no documents', {});
if (E) ok('no documents at all: the adapter still answers, and says each source unread, never zero', E.hosts.length === 0 && E.unread.hosts && E.unread.ops && E.unread.intake && E.ops.runs === null && E.records.stale === null && E.needs.length === 3, JSON.stringify(E.needs.map((n) => n.text)));

// 7. S4's fields absent (as main's `hosts` prints today) and present (#426)
{
  const s = clone(SRC);
  delete s.hosts.queue.entries[0].pin_login;   // a typed pin whose login the row does not say
  E = run('S4 absent', s);
  if (E) {
    const Q = Object.fromEntries(E.queue.map((q) => [q.qid, q]));
    ok('S4 absent: a typed pin with no pin_login reads unknown (null), so no Unpin; checks null on every row but the desk\'s; features null', Q['fleet:lease-renewal-s6'].pinLogin === null && Q['fleet:lease-renewal-s6'].acts.indexOf('unpin') < 0 && E.hosts.every((h) => h.features === null), JSON.stringify(Q['fleet:lease-renewal-s6'].acts));
  }
  const t = clone(SRC);
  t.hosts.hosts['host-a'].checks = { busy: 2, cap: 3, waiting: 1 }; t.hosts.hosts['node-1'].checks = { busy: 0, cap: 2, waiting: 0 };
  t.hosts.hosts['host-a'].features = ['macos', 'finish-queue']; t.hosts.hosts['node-1'].features = ['linux']; t.hosts.hosts['host-b'].features = ['macos']; t.hosts.hosts['node-2'].features = [];
  t.hosts.hosts['host-b'].records = { stale: null, oldest_days: 0, note: 'the records did not read' };
  t.hosts.queue.entries[0].pin_login = true;
  E = run('S4 present', t);
  if (E) {
    const A = Object.fromEntries(E.hosts.map((h) => [h.id, h])), Q = Object.fromEntries(E.queue.map((q) => [q.qid, q]));
    ok('S4 checks: each row\'s own {busy, cap, waiting}, summed with their caps (2+0 of 3+2, 1 waiting)', A['host-a'].checks.join('/') === '2/1/3' && E.ops.checks.join('/') === '2/1/5', JSON.stringify(E.ops.checks));
    ok('S4 features: the needs why names the awake hosts that meet it (host-a and host-b list macos)', /needs macos: host-a, host-b meet it/.test(Q['fleet:night-digest-s5'].why), Q['fleet:night-digest-s5'].why);
    ok('records.stale null: unknown, never 0 — a Needs line with no Settle', A['host-b'].stale === null && E.needs.some((n) => /host-b: its peer records did not read/.test(n.text) && !n.act));
    ok('pin_login true: a login holds the pin, so no Unpin (repin never moves it)', Q['fleet:lease-renewal-s6'].pinLogin === true && Q['fleet:lease-renewal-s6'].acts.indexOf('unpin') < 0);
  }
  const u = clone(SRC);
  u.hosts.queue.entries.push({ qid: 'fleet:dock-finish', topic: 'dock-finish-s2', repo: 'dock', state: 'queued', priority: 'normal', kind: 'finish', host: '', prefer: 'host-b', prefer_off: null, queued_at: NOW - 600, attempts: 0, needs: [], after: [], refused_by: {} });
  E = run('an unpinned finish', u);
  if (E) {
    const Q = Object.fromEntries(E.queue.map((q) => [q.qid, q]));
    ok('a finish with no host and a preference: Unpin (it drops the preference), never Pin', Q['fleet:dock-finish'].acts.indexOf('unpin') >= 0 && Q['fleet:dock-finish'].acts.indexOf('pin') < 0, JSON.stringify(Q['fleet:dock-finish'].acts));
  }
}

// 8. the poll's envelope: each source's state and at (helm_render.engine_state); one that did not read is unread
{
  const s = clone(SRC);
  s.at = NOW;
  s.sources = { hosts: { state: 'ok', at: NOW }, ops: { state: 'unread', at: null }, budgets: { state: 'ok', at: NOW - 3600 }, alarms: { state: 'off', at: null }, intake: { state: 'unread', at: null } };
  s.ops = null; s.intake = null;
  E = run('the envelope, two unread', s);
  if (E) {
    ok('ops unread: CI null, the chip unread (not off), a Needs line; never 0 %', E.ops.ci === null && E.sources.ci.unread === true && !E.sources.ci.off && E.needs.some((n) => /^CI unread/.test(n.text)));
    ok('intake unread: the chip unread, a Needs line, no cards, no alarms counted', E.sources.intake.unread === true && E.intake.length === 0 && E.needs.some((n) => /^Intake unread/.test(n.text)));
    ok('the hosts chip carries the source\'s own at', E.sources.hosts.at === NOW);
  }
  const t = clone(SRC);
  t.sources = { hosts: { state: 'unread', at: null } };
  E = run('the hosts unread', t);
  if (E) ok('hosts unread: no host, no entry, no login shown, runs null (never 0 of 0), its Needs line first', E.hosts.length === 0 && E.queue.length === 0 && E.ops.logins.length === 0 && E.ops.runs === null && /^the hosts did not read/.test(E.needs[0].text) && E.sources.hosts.unread && E.sources.queue.unread);
}

// 8b. the round-1 review's cases: a document judged late, slots that did not read, a queue that did not read, the pins
//     S4's repin refuses, a Needs line's host, a row with no records
{
  const late = ADAPT(SRC, NOW + 35 * 60);
  ok('a document judged 35 min after its poll: its rows are judged at the document\'s own time (still 4 awake), its ages at the viewer\'s', late.hosts.filter((h) => h.state === 'awake').length === 4 && late.hosts.find((h) => h.id === 'node-1').age === 36, late.hosts.map((h) => h.id + ':' + h.state).join());
  const s = clone(SRC); s.hosts.hosts['node-1'].slots = { busy: null, cap: 4, reserved: 1 };
  const E1 = ADAPT(s, NOW), n1 = E1.hosts.find((h) => h.id === 'node-1');
  ok('slots that did not read: unknown, never free — word "room ?", left out of the capacity sum (said partial), a Needs line', n1.slotsUnread && n1.word === 'room ?' && n1.live === 0 && E1.ops.runsPartial && E1.ops.runs.join('/') === '4/7' && E1.needs.some((n) => /node-1: its run slots did not read/.test(n.text)), n1.word + ' ' + E1.ops.runs.join('/'));
  const t = clone(SRC); t.hosts.queue.unreadable = true; t.hosts.queue.entries = [];
  const E2 = ADAPT(t, NOW);
  ok('a queue ref that did not read: the queue unknown, not empty, and a Needs line', E2.queueUnknown === true && E2.needs.some((n) => /queue ref did not read/.test(n.text)));
  const u = clone(SRC);
  u.hosts.queue.entries.push({ qid: 'fleet:w-s1', topic: 'w-s1', repo: 'w', state: 'waiting', kind: 'step', host: '', running_on: 'node-1', queued_at: NOW - 13 * 3600, needs: [], after: [], refused_by: {} });
  u.hosts.queue.entries.push({ qid: 'fleet:r-s1', topic: 'r-s1', repo: 'r', state: 'queued', kind: 'step', host: '', running_on: 'node-1', queued_at: NOW - 60, needs: [], after: [], refused_by: {} });
  u.hosts.queue.entries.push({ qid: 'fleet:l-s1', topic: 'l-s1', repo: 'l', state: 'queued', kind: 'step', host: '', pin_login: true, queued_at: NOW - 60, needs: [], after: [], refused_by: {} });
  const E3 = ADAPT(u, NOW), Q3 = Object.fromEntries(E3.queue.map((q) => [q.qid, q]));
  ok('no Pin where S4\'s repin refuses it: a waiting entry, a queued one a run holds (running_on), a login\'s', ['fleet:w-s1', 'fleet:r-s1', 'fleet:l-s1'].every((k) => Q3[k].acts.indexOf('pin') < 0) && Q3['fleet:intake-lanes-s3'].acts.indexOf('pin') >= 0, JSON.stringify(['fleet:w-s1', 'fleet:r-s1', 'fleet:l-s1'].map((k) => Q3[k].acts)));
  const nw = E3.needs.find((n) => /^w S1 waiting on node-1/.test(n.text));
  ok('a Needs line acts on the host its row names: the waiting entry\'s Watch on node-1, never this host', nw && nw.act === 'watch' && nw.host === 'node-1', JSON.stringify(nw));
  const v = clone(SRC); delete v.hosts.hosts['node-1'].records;
  ok('a row with no records object: its stale count unknown (null), never 0', ADAPT(v, NOW).hosts.find((h) => h.id === 'node-1').stale === null);
}

// 9. the view (bin/engine.js) on the same documents, in node: its html in each state, no DOM. The page's own render cases
//    (tests/engine_selftest.js) run it in headless Chrome at three widths and both themes.
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'bin', 'engine.js'), 'utf8'), ctx, { filename: 'engine.js' });
const esc = (x) => String(x == null ? '' : x).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const view = (src, road, sec) => {
  const Ex = ADAPT(src, NOW), V = { esec: sec || 'all' }, said = [];
  const v = ctx.ENGINE_VIEW({ E: () => Ex, V: V, esc: esc, plural: (n, w, ws) => n + ' ' + (n === 1 ? w : (ws || w + 's')), N: (k, x) => '<span class="n">' + x + '</span>',
    hhmm: (t) => new Date(t).toISOString().slice(11, 16), road: road, render: () => {}, url: () => {}, toast: (m) => said.push(m), week: () => ({ pct: 37, line: 'week 37% used' }) });
  return { v: v, V: V, E: Ex, said: said, html: v.html(), head: v.head() };
};
const text = (h) => h.replace(/<[^>]+>/g, ' ').replace(/&#39;/g, "'").replace(/\s+/g, ' ');
const buttons = (h) => [...h.matchAll(/<button[^>]*data-verb="e:([a-z]+):([^:"]*):([^"]*)"[^>]*>/g)].map((m) => ({ kind: m[1], host: m[2], target: m[3], off: / disabled/.test(m[0]) }));
{
  const r = view(SRC, 'press');
  const T = text(r.html + r.head.h1 + r.head.sub);
  ok('view: the fixture renders every section, the tabs counted, no NaN, undefined or null in its text', ['e-needs', 'e-hosts', 'e-queue', 'e-logins', 'e-intake'].every((id) => r.html.indexOf('id="' + id + '"') >= 0) && (r.html.match(/data-esec=/g) || []).length === 6 && !/\bNaN\b|\bundefined\b|\bnull\b/.test(T), (T.match(/.{30}\b(NaN|undefined|null)\b.{30}/) || [''])[0]);
  ok('view: the head counts live runs and queued entries only (6 runs on 4 hosts; 9 wait; 1 claimed)', /6 runs at work on 4 hosts/.test(text(r.head.h1)) && /9 .*wait in the queue/.test(text(r.head.h1)) && /1 claimed/.test(r.head.h1), text(r.head.h1));
  const B = buttons(r.html);
  ok('view, the press road: every verified kind and Pin/Unpin drawn disabled; Kick and Settle live', B.filter((b) => /^(raise|cancel|end|limits|park|unpark|ceiling|pin|unpin)$/.test(b.kind)).every((b) => b.off) && B.some((b) => b.kind === 'kick' && !b.off) && B.some((b) => b.kind === 'settle' && !b.off), JSON.stringify(B.filter((b) => !b.off).map((b) => b.kind)));
  ok('view: Unpin only on the typed pin no login holds; none on the held pin, the kind-unread pin or the pinned finish', B.filter((b) => b.kind === 'unpin').map((b) => b.target).join() === 'fleet:lease-renewal-s6' && /kind unread/.test(r.html) && /held on host-c/.test(r.html), B.filter((b) => b.kind === 'unpin').map((b) => b.target).join());
  ok('view: no Pin on a finish; the finish chip shown', !B.some((b) => b.kind === 'pin' && b.target === 'fleet:harbor-lights-land') && /class="rt need"[^>]*>finish</.test(r.html));
  ok('view: every source chip shows its age, the CI chip its desk; no path, no URL in the html', (r.html.match(/class="src /g) || []).length >= 5 && !/\/Users\/|\/home\/|https?:\/\//.test(r.html));
  r.v.verb('kick', 'host-a', 'fleet:lease-renewal-s6');
  ok('view: a press records its envelope on the page and says it was not sent (S3 has no executor)', /not sent/.test(r.said[0] || '') && /recorded on this page, not sent/.test(r.v.html()), r.said.join(' | '));
  r.v.verb('cancel', 'host-a', 'fleet:lease-renewal-s6');
  ok('view: a verified kind pressed off the token road is refused before anything is recorded', /needs the token road/.test(r.said[1] || '') && !r.V.everbs['cancel|host-a|fleet:lease-renewal-s6']);
}
{
  const r = view(SRC, 'token');
  const B = buttons(r.html);
  ok('view, the token road: Pin and Unpin enabled and confirm first; the Pin confirm says a typed pin its --next inherits', B.some((b) => b.kind === 'unpin' && !b.off) && B.some((b) => b.kind === 'pin' && !b.off) && (r.v.verb('pin', 'host-a', 'fleet:intake-lanes-s3'), /typed --pin/.test(r.v.html()) && /--next inherits the pin/.test(r.v.html())) && (r.v.escape(), !/class="econfirm"/.test(r.v.html())));
}
{
  const s = clone(SRC); s.sources = { hosts: { state: 'unread', at: null }, ops: { state: 'unread' }, intake: { state: 'unread' } }; s.ops = null; s.intake = null;
  const r = view(s, 'press'), T = text(r.html + r.head.h1 + r.head.sub);
  ok('view, every source unread: the head says the hosts did not read, the sections say unread, no "0 runs" and no count of 0 hosts', /did not read/.test(r.head.h1) && !/\b0 runs\b/.test(T) && /Hosts <b>\?<\/b>/.test(r.html) && /The fleet queue <b>\?<\/b>/.test(r.html) && /Intake <b>\?<\/b>/.test(r.html) && (T.match(/unread/g) || []).length >= 6, T.slice(0, 200));
}
{
  const r = view(Object.assign(clone(SRC), { ops: OFF.ops, intake: OFF.intake }), 'press'), T = text(r.html);
  ok('view, the desk off: CI and Intake say off in fixed words, never a path or 0 %', /off: no desk sample on this host/.test(T) && /off: no intake on this host/.test(T) && !/<home>|ops\.jsonl/.test(r.html) && !/CI at 0 %|>0 <small>%/.test(r.html), (T.match(/.{40}(0 %|ops\.jsonl).{20}/) || [T.slice(0, 120)])[0]);
}
{
  const r = view(SRC, 'press', 'queue');
  ok('view: ?sec=queue shows the queue alone, no capacity row', /id="e-queue"/.test(r.html) && !/id="e-hosts"/.test(r.html) && !/class="kpis/.test(r.html));
}

// 10. the round-2 review's cases
{
  const s = clone(SRC); s.hosts.hosts['node-1'].at = NOW - 1815;
  ok('staleness by engine_sig\'s rule exactly: a row 1815 s old at the document\'s time reads unread (seconds, no rounding)', ADAPT(s, NOW).hosts.find((h) => h.id === 'node-1').state === 'unread');
  const t = clone(SRC); t.hosts.queue.fence_unreadable = true; t.hosts.queue.entries = []; t.hosts.queue.dropped = 10;
  const r = view(t, 'press', 'queue'), T = text(r.html);
  ok('a torn registry: the queue section says unknown, not empty, with no counts and no "in confidential scopes"', /the registry did not read, so every entry was dropped/.test(T) && !/is empty/.test(T) && !/\b0 wait\b/.test(T) && !/confidential scopes/.test(T), T.slice(0, 220));
  const u = clone(SRC); ['host-a', 'host-b', 'node-2'].forEach((k) => { u.hosts.hosts[k].headroom.room = false; }); u.hosts.hosts['node-1'].slots = { busy: null, cap: 4, reserved: 0 }; u.hosts.hosts['node-1'].runs = null;
  const E1 = ADAPT(u, NOW), Q1 = Object.fromEntries(E1.queue.map((q) => [q.qid, q]));
  ok('slots unread: the host never has room (no "claimable" on it), and its runs line says no slot count', !/claimable: node-1/.test(Q1['fleet:intake-lanes-s3'].state) && E1.needs.some((n) => /node-1: its runs are unread \(no dispatch-rc there\)$/.test(n.text)), Q1['fleet:intake-lanes-s3'].state);
  const v = clone(SRC); Object.values(v.budgets.accounts).forEach((a) => { delete a.week_share; }); delete v.ops.row.budget['org-minutes'];
  const r2 = view(v, 'press');
  ok('no budget with a week share, the desk read fine: "no week share set", never "CI unread"', r2.E.ops.ci === null && r2.E.ciRead && /no week share set/.test(text(r2.head.sub)) && !/CI unread/.test(text(r2.head.sub + r2.html)), text(r2.head.sub));
  const w = clone(SRC); w.hosts.hosts['node-1'].runs[0].started = 0;
  const r3 = view(w, 'press');
  ok('a run whose record has no start (hosts writes 0): since unknown, "started ?", never decades', r3.E.hosts.find((h) => h.id === 'node-1').runsList[0].since === null && /started \?/.test(r3.html) && !/\d{5,}(\.\d)? h/.test(text(r3.html)));
  const x = clone(SRC); x.ops.row.budget['runner-minutes'] = { state: 'ok', used: 2900, week_used: 100, unit: 'minutes', net_amount: 0 }; delete x.budgets.accounts['runner-minutes'].month_minutes; x.budgets.accounts['runner-minutes'].month_credits = 3000;
  const bx = ADAPT(x, NOW).ops.ci_budgets.find((b) => b.name === 'runner-minutes');
  ok('a minutes budget takes the minutes cap alone, as ops does: no month_minutes, no cap, no level', bx.cap === null && bx.level === null, JSON.stringify([bx.cap, bx.level]));
  const y = clone(SRC); y.intake.guarded = { deadman: 1, bug: 2 };
  const Ey = ADAPT(y, NOW);
  ok('guarded Intake cards: counted (3), a guarded deadman among the alarms (4), never listed', Ey.intakeGuarded === 3 && Ey.alarms === 4 && Ey.intake.length === 7, Ey.intakeGuarded + ' ' + Ey.alarms);
  const z = clone(SRC); z.hosts.queue.entries[8].pin_kind = ''; const z2 = clone(SRC); z2.hosts.queue.entries[8].pin_kind = null;
  ok('a pin of no known kind (pin_kind "" or null, no pinned_why) reads unknown, never held', ADAPT(z, NOW).queue.find((q) => q.qid === 'fleet:lantern-s2').pinKind === null && ADAPT(z2, NOW).queue.find((q) => q.qid === 'fleet:lantern-s2').pinKind === null);
}

// 11. the round-3 review's cases
{
  const a = clone(SRC); a.ops.row.budget = null;
  const r = view(a, 'press');
  ok('a budget read that did not answer (row.budget null): CI unread with a Needs line, never "no week share"', !r.E.ciRead && /CI unread/.test(text(r.head.sub)) && !/no week share/.test(text(r.html + r.head.sub)) && r.E.needs.some((n) => /budget read did not answer/.test(n.text)));
  const b = clone(SRC); b.hosts.queue.guard_unread = true; b.hosts.queue.entries = []; b.hosts.queue.dropped = 9;
  const r2 = view(b, 'press', 'queue'), T2 = text(r2.html);
  ok('a guarded list that did not read: the queue unknown, not empty, in its own words; never "in confidential scopes"', r2.E.queueUnknown && /the guarded list did not read/.test(T2) && !/is empty/.test(T2) && !/confidential/.test(T2), T2.slice(0, 200));
  const c = clone(SRC); c.ops.age_s = 300; c.ops.row.as_of = NOW - 300;
  const late = ADAPT(c, NOW + 3600);
  ok('the CI chip ages on the viewer\'s clock from the row\'s as_of: 65 min an hour after the poll, never a frozen 5', late.sources.ci.age === 65, late.sources.ci.age);
}

// 8e. the finish review's cases: every awake host's slots unread, a cap of 0, no login in the answer, no hosts tool
{
  const s = clone(SRC); Object.values(s.hosts.hosts).forEach((r) => { if (r && typeof r === 'object') r.slots = { busy: null, cap: null, reserved: null }; });
  const r1 = view(s, 'press');
  ok('every awake host\'s slots unread: runs unknown, never "0 runs at work"; the capacity tile unread', r1.E.ops.runsUnknown && /runs unread/.test(text(r1.head.h1)) && !/\b0 runs at work/.test(text(r1.head.h1)), text(r1.head.h1));
  const p = clone(SRC); p.hosts.hosts['node-1'].slots = { busy: null, cap: 4, reserved: 1 };
  ok('some hosts\' slots unread: the head says at least', /at least \d+ runs at work/.test(text(view(p, 'press').head.h1)), text(view(p, 'press').head.h1));
  const x = clone(SRC); x.ops.row.budget['runner-minutes'] = { state: 'ok', used: 10, week_used: 1, unit: 'minutes', net_amount: 0 }; x.budgets.accounts['runner-minutes'].month_minutes = 0;
  const bx = ADAPT(x, NOW).ops.ci_budgets.find((b) => b.name === 'runner-minutes');
  ok('a cap of 0 is no cap, as ops\' read_budget: no level, never "into its reserve"', bx.cap === null && bx.level === null, JSON.stringify([bx.cap, bx.level]));
  const l = clone(SRC); l.hosts.logins = [];
  const El = ADAPT(l, NOW);
  ok('no login in the answer (account limits may have failed): the chip unread, never "just now"', El.sources.logins.unread && El.sources.logins.age === null);
  const o = clone(SRC); o.sources = Object.assign({}, o.sources || {}, { hosts: { state: 'off', at: null } }); o.hosts = null;
  const Eo = ADAPT(o, NOW);
  ok('no hosts tool on this host: the hosts source off, no red Needs line', Eo.sources.hosts.off && !Eo.sources.hosts.unread && !Eo.needs.some((n) => /hosts did not read/.test(n.text)));
}

console.log('PROVE the Engine room\'s adapter and view: ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
