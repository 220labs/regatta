/* engine.js — the Engine room: its own view in helm's board (docs/engine-room-2026-11-02.md S3; the owner, 2026-11-02:
   "leave the ships board here, and move the CI/nodes/budgets stuff into the engine room page"; "[Intake] also goes to
   engine room"). Built from the prototype's engine.js (docs/engine-room-2026-11-02/prototype/) onto the landed shell
   (board.js, helm-board-ux S3): the shell calls ENGINE_VIEW(ctx) once and asks it for the view's head words and its
   body at every render; the body is reconciled by its `data-k` keys like every other region, so a poll never redraws it.
   What it draws, in order, each section earning its place: the capacity row (run slots, checks, CI, the week) with a
   source chip per feed; "Needs a hand" — one line per thing the owner might act on, its action beside it; the hosts,
   a card each with its runs and their logins; the fleet queue with why each entry waits and its actions; the logins'
   standing and the CI budgets; Intake by kind and number. Counted tabs show one section at a time (?sec=needs|hosts|
   queue|logins|intake), as Decide's do. A source that did not read says `unread` where its numbers would stand.
   Actions: every button is an envelope {kind, host, target} (docs/fleet-page-2026-11-01.md, the actions table; D2-A):
   `one` kinds run from any road, `confirm` kinds ask first, `verified` kinds need the token road — drawn disabled and
   dashed on the press road (?road=press, the default; ?road=token draws the local page). Raise is a verified kind: a
   press runs as an unattended caller, and dispatch-queue's raise_refusal refuses a priority above normal there. Pin
   and Unpin confirm and, until S5's executor says otherwise, work by the token road only (S4 as built: repin refuses
   an unattended caller, and a press is one). Unpin is offered for a typed pin no login holds (`pin_login` false); a
   held pin, a login's pin and a pin whose kind the row does not carry have none; a finish has no Pin. S3 has no
   executor: a press records the envelope on this page and says it was not sent (S5 builds `helm act`).
   Reads ctx.E() (engine_adapter.js on engine.json) at every call: the poll replaces it. */
(function (root) {
  'use strict';
  root.ENGINE_VIEW = function (ctx) {
    var esc = ctx.esc, plural = ctx.plural, N = ctx.N, V = ctx.V;
    var road = ctx.road === 'token' ? 'token' : 'press';
    var KIND = { kick: 'one', settle: 'one', watch: 'one', intake: 'one', pin: 'confirm', unpin: 'confirm', raise: 'verified', cancel: 'verified', end: 'verified', limits: 'verified', park: 'verified', unpark: 'verified', ceiling: 'verified' };
    var TOKEN_ONLY = { pin: 1, unpin: 1 };   // confirm kinds S4's verbs refuse to an unattended caller: the token road until S5
    var VERB = { kick: 'dispatch --kick <qid>', settle: 'dispatch-rc settle --stale', pin: 'dispatch-queue repin <qid> <the deploying host>', unpin: 'dispatch-queue repin <qid> any', raise: 'dispatch-queue raise <qid> --priority high (refused to an unattended caller: raise_refusal)', cancel: 'dispatch-queue cancel <qid>', end: 'dispatch --end <topic>', limits: 'regatta limit set <key> <host>:<value>', park: 'account park <label>', unpark: 'account unpark <label>', ceiling: 'regatta limit set week-max <label>:<pct> --on <host>|--all' };
    V.everbs = V.everbs || {}; V.econfirm = V.econfirm || null;
    var SECS = ['all', 'needs', 'hosts', 'queue', 'logins', 'intake'];
    if (SECS.indexOf(V.esec) < 0) V.esec = 'all';
    function E() { return ctx.E(); }
    function word(kind) { return kind === 'pin' ? 'Pin to ' + (E().here || 'this host') : { kick: 'Kick', settle: 'Settle', watch: 'Watch', unpin: 'Unpin', raise: 'Raise', cancel: 'Cancel', end: 'End', limits: 'Limits', park: 'Park', unpark: 'Unpark', ceiling: 'Ceiling', intake: 'Intake →' }[kind] || kind; }
    function on(s) { return V.esec === 'all' || V.esec === s; }
    function ageWord(m) { return m == null ? 'no sample' : m < 1 ? 'just now' : m < 60 ? m + ' min ago' : (m / 60).toFixed(m < 600 ? 1 : 0).replace(/\.0$/, '') + ' h ago'; }
    function ageH(h) { return h == null ? '—' : h < 1 ? Math.max(0, Math.round(h * 60)) + 'm' : h < 48 ? Math.round(h) + 'h' : Math.round(h / 24) + 'd'; }
    function hhmm(t) { return t == null ? '—' : ctx.hhmm(t * 1000); }
    function key(s) { return String(s).replace(/[^A-Za-z0-9_.:=-]/g, '_'); }
    function rowOf(qid) { return E().queue.filter(function (q) { return q.qid === qid; })[0]; }
    function locked(kind) { return (KIND[kind] === 'verified' || TOKEN_ONLY[kind]) && road !== 'token'; }
    function ship(name, repo) { return '<span class="mono b">' + esc(name || repo || '?') + '</span>'; }
    var UNREAD = '<span class="t-wait">unread</span>';

    /* a button is its envelope: kind · host · target; a verified or token-only kind on the press road is drawn locked */
    function act(kind, host, target, extra) {
      var lk = locked(kind), k = kind + '|' + host + '|' + target, r = V.everbs[k];
      if (r) return '<span class="st park rcpt" data-k="rc-' + key(k) + '">' + esc(r) + '</span>';
      var title = (VERB[kind] || kind) + ' · on ' + host + (lk ? ' · needs the token road: a press is an unattended caller, and this verb refuses one before it runs (D2-A)' : KIND[kind] === 'confirm' ? ' · asks first' : ' · runs as an unattended caller from a press');
      return '<button type="button" class="btn sm' + (kind === 'intake' ? '' : ' ghost') + (lk ? ' off' : '') + '"' + (lk ? ' disabled' : '') + ' data-k="b-' + key(k) + '" data-verb="e:' + kind + ':' + esc(host) + ':' + esc(target) + '" title="' + esc(title) + '">' + esc(word(kind)) + (extra || '') + '</button>';
    }
    function src(k) {
      var s = E().sources[k], tone = s.unread ? 'bad' : s.off ? 'park' : s.age == null ? 'bad' : s.age > 30 ? 'bad' : s.age > 15 ? 'wait' : 'park';
      var said = s.unread ? 'unread' : s.off ? s.live : ageWord(s.age) + (s.at != null ? ' · ' + hhmm(s.at) : '');
      return '<span class="src ' + tone + '" data-k="src-' + k + '" title="' + esc(s.live) + '"><i class="sd ' + tone + '"></i>' + esc(s.label) + ' · ' + esc(said) + '</span>';
    }
    function confirmStrip(k) {
      var c = V.econfirm; if (!c || c.key !== k) return '';
      var q = rowOf(c.target) || {}, who = q.by ? ' by session ' + q.by : '';
      var what = c.kind === 'unpin' ? (q.finish ? 'Unpin ' + c.target + '? It is a finish with a preference for ' + (q.on || '?') + '; Unpin drops the preference, and any host that may land it claims it.' :
        'Unpin ' + c.target + '? Its pin is a typed --pin' + who + ', no login holds it; unpinned, any host with room claims it at the next sweep.') :
        'Pin ' + c.target + ' to ' + c.host + '? It becomes a typed --pin: only ' + c.host + ' may claim it, room or not, and its run\'s own --next inherits the pin.';
      return '<div class="econfirm" role="group" data-k="cf-' + key(k) + '"><span>' + esc(what) + '</span><button type="button" class="btn sm" data-verb="e:cancelconfirm:' + esc(c.host) + ':' + esc(c.target) + '">Not now <span class="k">esc</span></button><button type="button" class="btn sm primary" data-verb="e:ok:' + esc(c.host) + ':' + esc(c.target) + '">' + esc(word(c.kind)) + '</button></div>';
    }
    var sbar = function (pct, tone, mark, markTitle) { return '<span class="kbar sm"><i class="' + tone + '" style="width:' + Math.max(0, Math.min(100, pct)) + '%"></i>' + (mark != null ? '<em style="left:' + Math.min(100, mark) + '%" title="' + esc(markTitle || ('pace ' + mark + ' %')) + '"></em>' : '') + '</span>'; };
    var bar = function (pct, tone, mark) { return '<span class="kbar"><i class="' + tone + '" style="width:' + Math.max(0, Math.min(100, pct)) + '%"></i>' + (mark != null ? '<em style="left:' + Math.min(100, mark) + '%"></em>' : '') + '</span>'; };
    var ciWord = function () { var e = E(); return e.unread.ops ? '<span class="t-wait">CI unread</span>' : e.ops.ci == null ? (e.ciRead ? 'CI: no week share set' : '<span class="t-wait">CI ' + (e.sources.ci.off ? 'off here' : 'unread') + '</span>') : 'CI at <span class="' + (e.ops.ci >= 80 ? 't-bad' : 't-wait') + '">' + e.ops.ci + ' % of the week</span>'; };

    /* ── the head's words: the shell's head() wraps them with the page's notes ── */
    function head() {
      var e = E(), eyebrow = 'Engine room · as of ' + hhmm(e.at) + (e.here ? ' on ' + esc(e.here) : '');
      if (e.unread.hosts) return { e: eyebrow, h1: e.sources.hosts.off ? 'No hosts tool on this host.' : 'The hosts did not read at the poll.', sub: 'Runs, the queue and the logins are unknown here, not none; ' + ciWord() + (e.alarms ? ', <span class="t-bad">' + plural(e.alarms, 'alarm') + '</span> in Intake' : '') + '. <a href="?view=fleet" data-view="fleet">← Fleet</a>' };
      var cant = e.queued.filter(function (q) { return q.tone === 'bad'; }).length, awake = e.hosts.filter(function (x) { return x.state === 'awake'; }).length;
      var conf = e.hosts.reduce(function (a, x) { return a + x.confined; }, 0), unread = e.hosts.filter(function (x) { return x.state === 'awake' && x.runsUnread; }).length;
      var h1 = (e.ops.runsUnknown ? '<span class="t-wait">runs unread</span>' : (e.ops.runsPartial ? 'at least ' : '') + N('e-runs', e.ops.runs[0]) + ' runs at work') + ' on ' + plural(awake, 'host') + (conf ? ' (' + conf + ' confidential, counted)' : '') + '; ' + (e.queueUnknown ? '<span class="t-wait">the queue unread</span>' : N('e-q', e.queued.length) + ' wait in the queue' + (cant ? ', <span class="t-bad">' + cant + ' cannot start</span>' : '') + (e.claimed.length ? '; ' + e.claimed.length + ' claimed' : '')) + '.';
      var stale = e.records.stale == null ? '<span class="t-wait">stale records unread</span>, ' : e.records.stale ? '<span class="t-wait">' + e.records.stale + ' stale records</span>, ' : '';
      var sub = (e.alarms ? '<span class="t-bad">' + plural(e.alarms, 'alarm') + '</span> in Intake, ' : '') + stale + ciWord() + (e.ops.reserved ? ', ' + plural(e.ops.reserved, 'slot') + ' reserved' : '') + (unread ? ', <span class="t-wait">' + plural(unread, 'host') + ' with runs unread</span>' : '') + (e.guardUnread ? '; <span class="t-wait">the guarded list did not read: every run and entry hidden</span>' : conf ? '; ' + plural(conf, 'run') + ' in confidential scopes or guarded repos, counted only' : '') + '.';
      return { e: eyebrow, h1: h1, sub: sub };
    }

    /* ── the tabs: one section at a time, as Decide's ── */
    function tabs() {
      var e = E(), n = function (v) { return e.unread.hosts ? null : v; };
      var t = [['all', 'All', null], ['needs', 'Needs a hand', e.needs.length], ['hosts', 'Hosts', n(e.hosts.length)], ['queue', 'Queue', e.queueUnknown ? null : e.queue.length], ['logins', 'Logins and CI', n(e.ops.logins.length)], ['intake', 'Intake', e.unread.intake ? null : e.intake.length + e.intakeGuarded]];
      return '<div class="cats ecats" data-k="ecats">' + t.map(function (x) { return '<button type="button" class="cat' + (V.esec === x[0] ? ' on' : '') + '" data-k="ec-' + x[0] + '" data-esec="' + x[0] + '">' + x[1] + (x[2] != null ? '<b>' + x[2] + '</b>' : '') + '</button>'; }).join('') + '</div>';
    }

    /* ── the capacity row, each number with where it came from ── */
    function capacity() {
      var e = E(), o = e.ops, wk = ctx.week();
      var slots;
      if (!o.runs || o.runsUnknown) slots = '<div class="kv"><small>unread</small></div>' + bar(0, 'run') + '<div class="ks"><span class="t-wait">' + (o.runs ? 'no awake host\'s run slots read' : 'the hosts did not read at the poll') + '</span></div>';
      else {
        var free = Math.max(0, o.runs[1] - o.runs[0] - o.reserved), roomHosts = e.hosts.filter(function (x) { return x.state === 'awake' && x.room !== false && !x.full && !x.slotsUnread; }).map(function (x) { return x.id; });
        slots = '<div class="kv">' + o.runs[0] + ' <small>/ ' + o.runs[1] + (o.reserved ? ' · ' + o.reserved + ' reserved' : '') + '</small></div>' + bar((o.runs[0] + o.reserved) / Math.max(1, o.runs[1]) * 100, 'run') + '<div class="ks">' + (free ? free + ' free' + (roomHosts.length ? ' · room on ' + esc(roomHosts.join(', ')) : ' · <span class="t-wait">no host has room</span>') : '<span class="t-wait">none free across the awake hosts</span>') + (o.runsPartial ? ' · <span class="t-wait">a host\'s slots unread, left out</span>' : '') + '</div>';
      }
      var ciB = o.ci_budgets.filter(function (b) { return b.week != null; }).sort(function (a, b) { return b.week - a.week; })[0], unreadB = o.ci_budgets.filter(function (b) { return b.unread; }).length;
      var checks = o.checks ? '<div class="kv">' + o.checks[0] + ' <small>busy' + (o.checks[2] != null ? ' / ' + o.checks[2] : '') + '</small></div>' + bar(o.checks[2] ? o.checks[0] / o.checks[2] * 100 : 0, 'run') + '<div class="ks">' + (o.checks[1] ? '<span class="t-wait">' + o.checks[1] + ' waiting for a slot</span>' : 'none waiting') + (e.hosts.some(function (x) { return x.checks && x.checks[2] != null; }) ? '' : o.host ? ' · the desk\'s host only' : '') + '</div>' :
        '<div class="kv"><small>unread</small></div>' + bar(0, 'run') + '<div class="ks"><span class="t-wait">no row carries check slots yet</span></div>';
      var ci = o.ci == null && e.ciRead ? '<div class="kv"><small>no share</small></div>' + bar(0, 'wait') + '<div class="ks">no budget has a week share in ci-budgets.json; each budget\'s month is below</div>' :
        o.ci == null ? '<div class="kv"><small>' + (e.sources.ci.off ? 'off' : 'unread') + '</small></div>' + bar(0, 'wait') + '<div class="ks"><span class="t-wait">' + esc(e.sources.ci.live) + '</span></div>' :
        '<div class="kv">' + o.ci + ' <small>%</small></div>' + bar(o.ci, o.ci >= 80 ? 'bad' : 'wait', 80) + '<div class="ks">' + (ciB ? (ciB.level !== 'ok' ? '<span class="t-bad">' + esc(ciB.name) + ' ' + (ciB.level === 'reserve' ? 'into its reserve' : 'past its week share') + '</span>' : esc(ciB.name) + ' the nearest') : 'no budgeted account') + (unreadB ? ' · <span class="t-wait">' + unreadB + ' unread</span>' : '') + '</div>';
      var week = wk.pct == null ? '<div class="kv"><small>unread</small></div>' + bar(0, 'ok') + '<div class="ks"><span class="t-wait">the week line did not read</span></div>' : '<div class="kv">' + wk.pct + ' <small>%</small></div>' + bar(wk.pct, 'ok') + '<div class="ks">' + esc(wk.line) + '</div>';
      return '<div class="kpis ekpis" data-k="ekpis">' +
        '<div class="kpi" data-k="kp-slots"><div class="kl">Run slots</div>' + slots + '</div>' +
        '<div class="kpi" data-k="kp-checks"><div class="kl">Checks</div>' + checks + '</div>' +
        '<div class="kpi" data-k="kp-ci"><div class="kl">CI budget · the week</div>' + ci + '</div>' +
        '<div class="kpi" data-k="kp-week"><div class="kl">Week · tokens</div>' + week + '</div></div>' +
        '<div class="srcs" data-k="esrcs">' + src('hosts') + src('queue') + src('logins') + src('ci') + src('intake') + (e.ref.offline ? '<span class="src bad" data-k="src-off"><i class="sd bad"></i>' + esc(e.ref.offline) + '</span>' : '') + (e.ref.unreadable ? '<span class="src bad" data-k="src-unr"><i class="sd bad"></i>' + esc(e.ref.unreadable) + '</span>' : '') + '</div>';
    }

    /* ── needs a hand: one line each, its action beside it ── */
    function needs() {
      var e = E();
      if (!e.needs.length) return '<section class="sec" id="e-needs" data-k="e-needs"><div class="gh"><h2 class="lbl">Needs a hand <b>0</b></h2></div><p class="dim">Nothing: every host samples, every entry can start, every login is eligible.</p></section>';
      return '<section class="sec" id="e-needs" data-k="e-needs"><div class="gh"><h2 class="lbl">Needs a hand <b>' + e.needs.length + '</b></h2><span class="why">what the page would ask you to do; each line\'s action is the same one on its row below</span></div><ul class="needs">' + e.needs.map(function (n, i) {
        var k = n.act && n.act !== 'intake' ? n.act + '|' + n.host + '|' + n.target : null;
        return '<li class="erow" data-k="en-' + key(k || (n.host ? n.host + '|' : '') + n.text.replace(/\d+(?:[.,]\d+)?/g, '#')) + '"><i class="sd ' + n.tone + '"></i><span class="nt">' + esc(n.text) + '</span><span class="na">' + (n.act === 'intake' ? '<button type="button" class="btn sm ghost" data-verb="e:sec:-:intake">Intake →</button>' : n.act ? act(n.act, n.host, n.target) : '') + '</span>' + (k ? confirmStrip(k) : '') + '</li>';
      }).join('') + '</ul></section>';
    }

    /* ── the hosts: a card each; its runs with their logins; the fence's count; the stale pile with its one action ── */
    function hostCard(x) {
      var pips = ''; if (!x.slotsUnread) for (var i = 0; i < x.runs[1]; i++) pips += '<i class="' + (i < x.live ? 'on' : i < x.live + x.reserved ? 'res' : '') + '"></i>';
      var st = x.state !== 'awake' ? 'bad' : x.room === false ? 'wait' : x.full ? 'wait' : x.room == null ? 'park' : 'ok';
      var L = x.limits || {}, near = function (k) { return x.near.indexOf(k) >= 0 ? ' t-wait' : ''; };
      var runs = x.runsList.map(function (r) {
        return '<li data-k="r-' + key(r.topic) + '"><span class="rs ' + (r.state === 'busy' ? 'run' : 'wait') + '"></span>' + ship(r.ship, r.repo) + '<span class="mono">' + esc(r.step) + '</span><span class="rl">' + (r.login ? esc(r.login) : '<span class="t-wait" title="the record carries neither a login nor a config_dir a login row names">login ?</span>') + ' · ' + (r.since == null ? '<span class="t-wait">started ?</span>' : r.since < 60 ? r.since + ' min' : (r.since / 60).toFixed(1) + ' h') + (r.state === 'waiting' ? ' · <span class="t-wait">waiting for room</span>' : r.state === 'warm' ? ' · warm' : '') + '</span><span class="ra">' + act('end', x.id, r.topic) + '</span></li>';
      }).join('') + (x.confined ? '<li class="conf" data-k="r-conf"><span class="rs park"></span><span class="rl">' + plural(x.confined, 'run') + (E().guardUnread ? ' hidden: the guarded list did not read' : ' in a confidential scope or a guarded repo') + ' · a count, never a row</span></li>' : '') + (x.unreadable ? '<li class="conf" data-k="r-torn"><span class="rs bad"></span><span class="rl t-bad">the registry did not read: every run dropped</span></li>' : '');
      var runsBlock = runs ? '<ul class="hruns">' + runs + '</ul>' : x.state !== 'awake' ? '' : x.runsUnread ? '<div class="note t-wait">runs unread here: no dispatch-rc on this host, so its runs are unknown, never none' + (x.slotsUnread ? '' : ' (' + x.live + ' of ' + x.runs[1] + ' slots busy)') + '</div>' : '<div class="note">no runs</div>';
      var checks = x.checks ? x.checks[0] + ' busy' + (x.checks[2] != null ? ' / ' + x.checks[2] : '') + (x.checks[1] ? ', <span class="t-wait">' + x.checks[1] + ' waiting</span>' : '') : '<span class="dim" title="this row carries no check slots (S4 adds them); the desk\'s host shows its own">unread</span>';
      var stale = x.stale == null ? (x.state === 'awake' ? '<div class="stale"><i class="sd wait"></i><span>peer records unread: the stale ones are unknown</span></div>' : '') : x.stale ? '<div class="stale"><i class="sd wait"></i><span>' + x.stale + ' stale peer records, the oldest ' + x.oldest + ' d</span>' + act('settle', x.id, x.id) + '</div>' : '';
      return '<div class="host erow ' + x.state + (x.room === false || x.full ? ' full' : '') + '" id="e-host-' + esc(x.id) + '" data-k="h-' + key(x.id) + '"><div class="hn"><span class="hnm">' + esc(x.id) + '</span><span class="os">' + esc(x.os) + '</span><span class="st ' + st + '">' + esc(x.word) + '</span></div>' + (x.role || x.here ? '<div class="hrole">' + esc(x.role) + (x.here ? (x.role ? ' · ' : '') + 'this host, sampled at the poll' : '') + '</div>' : '') +
        (x.slotsUnread && x.state === 'awake' ? '<div class="note t-wait">run slots unread: its room is unknown, never free</div>' : '<div class="pips" title="' + x.live + ' of ' + x.runs[1] + ' runs' + (x.reserved ? ', ' + x.reserved + ' reserved for a claim' : '') + '">' + pips + '</div>') +
        '<dl class="gl">' + (x.state === 'awake' ? '<dt>load</dt><dd class="' + (L.load_max && x.load != null && x.load > L.load_max * 0.7 ? 't-wait' : '') + near('load') + '">' + (x.load == null ? '—' : x.load.toFixed(2)) + ' <small>/ ' + esc(L.load_max || '—') + '</small></dd>' +
          '<dt>memory free</dt><dd class="' + (L.avail && x.mem != null && x.mem < L.avail * 1.3 ? 't-wait' : '') + near('avail') + '">' + (x.mem == null ? UNREAD : x.mem + ' %') + ' <small>floor ' + esc(L.avail || '—') + '</small></dd>' +
          (x.swap ? '<dt>swap</dt><dd class="' + (L.rate && x.rate > L.rate ? 't-bad' : near('swap') + near('rate')) + '">' + esc(x.swap) + (x.rate ? ' · ' + x.rate + ' <small>MB/s / ' + esc(L.rate || 'no rule') + '</small>' : '') + '</dd>' : '') +
          '<dt>checks</dt><dd>' + checks + '</dd>' : '') +
          '<dt>sampled</dt><dd class="' + (x.age == null || x.age > 30 ? 't-bad' : x.age > 15 ? 't-wait' : '') + '">' + ageWord(x.age) + '</dd></dl>' +
        (x.state === 'awake' && x.room === false ? '<div class="note t-wait">' + esc(x.reason) + '</div>' : x.state === 'awake' && x.room == null ? '<div class="note t-wait">' + esc(x.reason || 'memory unreadable') + ' · dispatch goes ahead here without the rule</div>' : x.state === 'awake' && x.full ? '<div class="note">full: ' + x.live + ' of ' + x.runs[1] + ' runs' + (x.reserved ? ' and ' + x.reserved + ' reserved' : '') + ' · ' + esc(x.reason) + '</div>' : x.note ? '<div class="note">' + esc(x.note) + '</div>' : '') +
        runsBlock + stale +
        '<div class="hf">' + (x.state === 'awake' ? act('limits', x.id, x.id, ' <small>cap ' + esc(L.cap || '—') + ' · floor ' + esc(L.avail || '—') + ' % · load ' + esc(L.load_max || '—') + '</small>') : '') + '</div></div>';
    }
    function hosts() {
      var e = E(), body = e.unread.hosts ? '<p class="dim">' + UNREAD + ': <code>hosts --json</code> did not answer at the poll, so no host is shown; none is not the same as unknown.</p>' : '<div class="hosts ehosts">' + e.hosts.map(hostCard).join('') + '</div>';
      return '<section class="sec" id="e-hosts" data-k="e-hosts"><div class="gh"><h2 class="lbl">Hosts <b>' + (e.unread.hosts ? '?' : e.hosts.length) + '</b></h2><span class="why">each host\'s room against the rule that refuses it (full is its cap, no room is headroom\'s memory rule); a run with the login it got; End and Limits (dashed) only by the token road</span><span class="sp"></span>' + src('hosts') + '</div>' + body + '</section>';
    }

    /* ── the queue: why each entry waits, and what the owner can do about it ── */
    function queue() {
      var e = E(), prio = { force: 'bad', high: 'wait', normal: 'park', low: 'park' };
      var rows = e.queue.map(function (q) {
        var rt = [];
        if (q.finish) rt.push('<span class="rt need" title="a finish: a landing\'s fleet entry; never pinned from here">finish</span>');
        if (q.pin && q.pinKind === 'held') rt.push('<span class="rt hard held" title="held here: ' + esc(q.held || 'the host holds what the step needs') + ' — no Unpin: the pin lifts when the step\'s run ends">held on ' + esc(q.pin) + '</span>');
        else if (q.pin && q.pinKind === 'typed') rt.push('<span class="rt hard" title="--pin: a typed pin' + (q.by ? ', by session ' + esc(q.by) : '') + (q.pinLogin ? '; its run names a login, which repin never moves' : q.pinLogin == null ? '; whether a login holds it is unread, so no Unpin' : '') + '; only this host may claim it">--pin ' + esc(q.pin) + (q.pinLogin ? ' · its login' : '') + '</span>');
        else if (q.pin && q.pinKind === 'login') rt.push('<span class="rt hard" title="a named login\'s pin: that login is set up on this host alone">pinned ' + esc(q.pin) + ' · its login</span>');
        else if (q.pin) rt.push('<span class="rt hard" title="pinned; the row carries no pin_kind (S4 adds it), so typed and held cannot be told apart and no Unpin is offered">pinned ' + esc(q.pin) + ' · kind unread</span>');
        if (q.on) rt.push('<span class="rt soft" title="--on: a preference; any eligible host claims it after one sweep' + (q.released ? ' — released: its host found no room' : '') + '">--on ' + esc(q.on) + (q.released ? ' · released' : ' · soft') + '</span>');
        if (q.needs) rt.push('<span class="rt need" title="--needs: eligibility, not a pin">needs ' + esc(q.needs) + '</span>');
        if (!rt.length) rt.push('<span class="rt any">any host</span>');
        var host = q.runningOn || q.pin || q.on || e.here, ck = function (k) { return k + '|' + (k === 'pin' ? e.here : host) + '|' + q.qid; };
        var acts = q.acts.map(function (k) { return k === 'watch' ? '<button type="button" class="btn sm ghost" data-k="b-watch-' + key(q.qid) + '" data-verb="e:watch:' + esc(host) + ':' + esc(q.qid) + '" title="the run\'s record on its host">Watch</button>' : act(k, k === 'pin' ? e.here : host, q.qid); }).join('');
        var conf = q.acts.map(function (k) { return confirmStrip(ck(k)); }).join('');
        var stepTxt = q.step.indexOf((q.ship || q.repo) + ' ') === 0 ? q.step.slice((q.ship || q.repo).length + 1) : q.step;
        return '<tr class="erow" data-k="q-' + key(q.qid) + '"><td><div class="qstep">' + ship(q.ship, q.repo) + '<span class="mono">' + esc(stepTxt) + '</span></div>' + (q.why ? '<div class="qwhy">' + esc(q.why) + '</div>' : '') + '<div class="rts inrow">' + rt.join('') + '</div></td>' +
          '<td><span class="st ' + (prio[q.prio] || 'park') + ' nodot">' + esc(q.prio) + '</span></td><td><div class="rts">' + rt.join('') + '</div></td><td class="m">' + (q.after ? esc(q.after) : '—') + '</td><td class="m r ' + (q.age >= 12 * 60 ? 't-bad' : '') + '">' + ageH(q.age / 60) + '</td>' +
          '<td><span class="st ' + q.tone + '">' + esc(q.state) + '</span></td><td class="acts-td"><div class="eacts">' + acts + '</div>' + conf + '</td></tr>';
      }).join('');
      var body = e.queueUnknown ? '<p class="dim">' + UNREAD + ': ' + (e.unread.hosts ? 'the hosts did not read at the poll' : e.queueUnreadable ? 'the queue ref did not read' : e.fenceUnreadable ? 'the registry did not read, so every entry was dropped' : 'the guarded list did not read, so every entry was hidden') + '; the queue is unknown here, not empty.</p>' :
        e.queue.length ? '<div class="tblw"><table class="tbl queue equeue"><thead><tr><th>Step</th><th>Priority</th><th>May run on</th><th>After</th><th>Age</th><th>State</th><th>Actions</th></tr></thead><tbody>' + rows + '</tbody></table></div>' : '<p class="dim">The fleet queue is empty.</p>';
      return '<section class="sec" id="e-queue" data-k="e-queue"><div class="gh"><h2 class="lbl">The fleet queue <b>' + (e.queueUnknown ? '?' : e.queue.length) + '</b></h2><span class="why">' + (e.queueUnknown ? '' : e.queued.length + ' wait, ' + e.claimed.length + ' claimed; ') + 'who can claim now, and why not; Kick and Settle from any road; Pin, Unpin, Raise, Cancel and End (dashed) only by the token road</span><span class="sp"></span>' + src('queue') + '</div>' + body +
        '<p class="opsline">' + (e.dropped && !e.fenceUnreadable && !e.guardUnread ? '<b>' + e.dropped + '</b> not shown (ended finishes, a scope\'s own store, confidential scopes or guarded repos), counted only · ' : '') + 'the fleet store; a scope\'s local queue never leaves its host' + (e.fenceUnreadable ? ' · <span class="t-bad">the registry did not read: every entry dropped</span>' : '') + '</p></section>';
    }

    /* ── the logins' standing and the CI budgets ── */
    function logins() {
      var e = E();
      var rows = e.ops.logins.map(function (l) {
        var host = e.here, acts = (l.parked ? act('unpark', host, l.id) : act('park', host, l.id)) + act('ceiling', host, l.id);
        return '<tr class="erow" data-k="l-' + key(l.id) + '"><td class="m"><b>' + esc(l.id) + '</b>' + (l.primary ? ' <span class="dim">primary</span>' : '') + (l.plan ? '<div class="dim">' + esc(l.plan) + '</div>' : '') + '</td>' +
          '<td>' + (l.week == null ? '<span class="dim">—</span>' : '<div class="mm">' + sbar(l.week, l.word === 'week spent' ? 'bad' : l.tone === 'ok' || l.tone === 'park' ? 'ok' : 'wait', 90, 'the week ceiling, 90 %') + '<span class="mono">' + l.week + ' %</span></div>') + '</td>' +
          '<td>' + (l.five == null ? '<span class="dim">—</span>' : '<div class="mm">' + sbar(l.five, l.five >= 80 ? 'bad' : 'run', l.pace) + '<span class="mono">' + l.five + ' %</span></div>' + (l.pace != null ? '<div class="qwhy nowrap">pace ' + l.pace + ' %' + (l.resets ? ' · resets ' + hhmm(l.resets) : '') + '</div>' : l.resets ? '<div class="qwhy">resets ' + hhmm(l.resets) + '</div>' : '')) + '</td>' +
          '<td><span class="st ' + l.tone + '">' + esc(l.word) + '</span>' + (l.why ? '<div class="qwhy">' + esc(l.why) + '</div>' : '') + '</td><td class="acts-td"><div class="eacts">' + acts + '</div></td></tr>';
      }).join('');
      var cib = e.ops.ci_budgets.map(function (b) {
        if (b.unread) return '<div class="kpi" data-k="ci-' + key(b.name) + '"><div class="kl">CI · ' + esc(b.name) + (b.provider ? ' <small>' + esc(b.provider) + '</small>' : '') + '</div><div class="kv"><small>unread</small></div>' + bar(0, 'wait') + '<div class="ks"><span class="t-wait">' + esc(b.state) + ': ' + esc(b.unread) + '</span></div></div>';
        var al = b.level && b.level !== 'ok';
        return '<div class="kpi" data-k="ci-' + key(b.name) + '"><div class="kl">CI · ' + esc(b.name) + (b.provider ? ' <small>' + esc(b.provider) + '</small>' : '') + '</div><div class="kv">' + (b.share == null ? '<small>no cap</small>' : b.share + ' <small>% of the month</small>') + '</div>' + bar(b.share || 0, al ? 'bad' : 'ok', 100 - b.reserve) + '<div class="ks">' + b.used.toLocaleString('en-US') + (b.cap != null ? ' of ' + b.cap.toLocaleString('en-US') : '') + ' ' + esc(b.unit) + ' · ' + (al ? '<span class="t-bad">' + esc(b.levelWhy) + (b.issue ? ' · issue #' + b.issue : '') + '</span>' : '<span class="t-ok">' + esc(b.levelWhy) + '</span>') + (b.week != null ? ' · week ' + b.week + ' % of its ' + b.weekCap.toLocaleString('en-US') : '') + '</div></div>';
      }).join('');
      var table = e.unread.hosts ? '<p class="dim">' + UNREAD + ': the logins came with the hosts, which did not read at the poll.</p>' : '<div class="tblw"><table class="tbl logins elogins"><thead><tr><th>Login</th><th>Week</th><th>Five hours</th><th>Standing</th><th>Actions</th></tr></thead><tbody>' + rows + '</tbody></table></div>';
      return '<section class="sec" id="e-logins" data-k="e-logins"><div class="gh"><h2 class="lbl">Logins and CI <b>' + (e.unread.hosts ? '?' : e.ops.logins.length) + '</b></h2><span class="why">each login\'s five hours against its pace mark and its week against the ceiling, in account\'s own words; each CI budget against its reserve and week share; Park and Ceiling by the token road</span><span class="sp"></span>' + src('logins') + src('ci') + '</div><div class="standing">' +
        table + '<div class="cib">' + (cib || '<p class="dim">' + esc(e.sources.ci.off || e.sources.ci.unread ? e.sources.ci.live : 'no budget in this sample') + '</p>') + '</div></div></section>';
    }

    /* ── Intake: kind and number; a contact is a stranger's text and never shows ── */
    function intake() {
      var e = E();
      var rows = e.intake.map(function (x, i) {
        var tone = x.alarm ? 'bad' : x.kind === 'contact' ? 'flag' : 'park';
        return '<tr data-k="i-' + key(x.repo + '#' + (x.n == null ? 'i' + i : x.n)) + '"><td><span class="st ' + tone + '">' + (x.alarm ? 'alarm · ' : '') + esc(x.kind) + '</span></td><td>' + (x.n == null ? '<span class="dim">' + esc(x.repo) + '</span>' : '<span class="mono">' + esc(x.repo) + ' #' + x.n + '</span>') + '</td><td class="m">' + esc(x.author) + '</td><td class="m">' + (x.mentions ? '<span class="t-bad">you</span>' : 'nobody') + '</td><td class="m r">' + ageH(x.age) + '</td></tr>';
      }).join('');
      var hidden = e.intakeGuarded ? '<p class="opsline"><b>' + e.intakeGuarded + '</b> in confidential scopes or guarded repos, counted only (their alarms among the alarms)</p>' : '';
      var body = e.unread.intake ? '<p class="dim">' + UNREAD + ': ' + esc(e.sources.intake.live) + '.</p>' : e.intake.length ? '<div class="tblw"><table class="tbl intake eintake"><thead><tr><th>Kind</th><th>Issue</th><th>From</th><th>Mentions</th><th>Age</th></tr></thead><tbody>' + rows + '</tbody></table></div>' : '<p class="dim">' + esc(e.sources.intake.off ? e.sources.intake.live : 'no open issue in the fleet\'s intake') + '</p>';
      return '<section class="sec" id="e-intake" data-k="e-intake"><div class="gh"><h2 class="lbl">Intake <b>' + (e.unread.intake ? '?' : e.intake.length + e.intakeGuarded) + '</b></h2><span class="why">kind and number only: a contact is a stranger\'s text, and never shows here; alarms and contacts mention you, bugs nobody</span><span class="sp"></span>' + src('intake') + '</div>' + body + hidden + '</section>';
    }

    /* ── a click on an envelope: one records, confirm asks, verified (and token-only) is refused off the token road.
       S3 has no executor: every press is recorded on this page and said to be not sent (S5 builds `helm act`) ── */
    function verb(kind, host, target) {
      var k = kind + '|' + host + '|' + target;
      if (kind === 'sec') { V.esec = target; ctx.render(); ctx.url(); return; }
      if (kind === 'cancelconfirm') { V.econfirm = null; ctx.render(); return; }
      if (kind === 'ok') { var c = V.econfirm; V.econfirm = null; if (c) record(c.kind, c.host, c.target); return; }
      if (kind === 'watch') { ctx.toast('The run\'s record is on ' + host + ': the page links it once S5\'s executor reads it'); return; }
      if (!KIND[kind]) return;
      if (locked(kind)) { ctx.toast(word(kind) + ' needs the token road: a press is an unattended caller, which the verb refuses before it runs'); return; }
      if (KIND[kind] === 'confirm') { V.econfirm = { key: k, kind: kind, host: host, target: target }; ctx.render(); return; }
      record(kind, host, target);
    }
    function record(kind, host, target) {
      V.everbs[kind + '|' + host + '|' + target] = kind + ' · ' + host + ' · ' + target + ' — recorded on this page, not sent: the executor comes with S5';
      ctx.render();
      ctx.toast('{kind: ' + kind + ', host: ' + host + ', target: ' + target + '} recorded here, not sent');
    }
    function escape() { if (!V.econfirm) return false; V.econfirm = null; ctx.render(); return true; }

    function html() {
      return '<div class="eroom" data-k="eroom">' + tabs() + (V.esec === 'all' ? capacity() : '') + (on('needs') ? needs() : '') + (on('hosts') ? hosts() : '') + (on('queue') ? queue() : '') + (on('logins') ? logins() : '') + (on('intake') ? intake() : '') + '</div>';
    }
    return { html: html, head: head, verb: verb, escape: escape, road: road };
  };
})(typeof window !== 'undefined' ? window : this);
