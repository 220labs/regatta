/* engine_adapter.js — the Engine room's adapter (docs/engine-room-2026-11-02.md S3, "The binding"): helm's poll hands
   the page engine.json (helm_render.engine_state(): lighthouse's `hosts --json`, `ops status --json` and
   `ops intake --json`, the config dir's ci-budgets.json and the log dir's ci-budget-alarms.json, each through the
   page's field allowlist, each with its own `at` and read state under `sources`), and this pure function maps those
   five documents onto what the Engine room draws, and the counts the shell shows beside it (the view's badge, the
   watch list, Fleet's pointer line). Pure: (src, now) → engine; no DOM; never throws on a document the real tool can
   print (an unread budget, a null row, a null runs list, a row that does not parse, a source that did not read:
   tests/engine_proof.js). Built from the prototype's adapter.js (docs/engine-room-2026-11-02/prototype/), which was
   proven on the same shapes.
   Every text that reaches the page is a name or a number from the sources, or a fixed word of this file's: a topic, a
   registry key, a login's label, headroom's reason and account's judge line as `hosts` scrubbed them. A `why` the desk
   prints never reaches here: the allowlist drops it and the chip says a fixed word.
   A source that did not read is unread, never zero (reviews.md finding 10): `E.unread.<source>` is true, its counts are
   null, and the view says `unread` where a number would stand. A source with no desk on this host is `off`.
   In the real shapes:
     a row's slots.busy counts the queue's reservations (dispatch --slots), so the live runs are busy − reserved;
     headroom judges memory only (its three rules), so a host at its cap reads `room: true`; `room: null` is a memory
     that did not read; `runs: null` with fence.runs_unread is unknown, never none; `checks` {busy, cap, waiting} and
     `features` are S4's (absent: unknown; the desk's host takes the ops row's check); an entry's needs is a list,
     refused_by {host: at}; pin_kind, pinned_why, by and pin_login are S4's too (absent: a pin whose kind and login the
     page cannot tell, so no Unpin); `records.stale` null is unknown, never 0; a budget whose state is not ok has no
     numbers; the week share, reserve and margin live in ci-budgets.json and the alarm level is budget_level()'s
     arithmetic (ops), its issue in ci-budget-alarms.json.
   The pins, as S4 built the verbs (docs/engine-room-2026-11-02.md, "S4 as built"): Unpin only for a typed pin whose
   `pin_login` is false (repin never moves a pin whose run names a login); a held pin (pinned_why) lifts when its run
   ends; a Pin is a typed pin, and the run's own --next inherits it. A finish (kind `finish`, a fleet entry since
   finish-as-task) is never pinned from here and every pinned finish is held, so a finish gets no Pin and Unpin only
   where it has no host and a preference (Unpin then drops the preference). */
(function (root) {
  'use strict';
  function ADAPT(src, now) {
    src = src && typeof src === 'object' ? src : {};
    var SRCS = src.sources && typeof src.sources === 'object' ? src.sources : null;
    // a source's read state: the envelope's word where the poll wrote one, else present or not (the prototype's fixtures)
    var state = function (k) { var s = SRCS && SRCS[k]; if (s && typeof s === 'object' && typeof s.state === 'string') return s.state; return src[k] && typeof src[k] === 'object' ? 'ok' : 'unread'; };
    var srcAt = function (k) { var s = SRCS && SRCS[k]; return s && typeof s.at === 'number' && isFinite(s.at) ? s.at : null; };
    var unread = { hosts: state('hosts') !== 'ok', ops: state('ops') === 'unread', budgets: state('budgets') === 'unread', alarms: state('alarms') === 'unread', intake: state('intake') === 'unread' };
    var off = { hosts: state('hosts') === 'off', ops: state('ops') === 'off', intake: state('intake') === 'off' };
    var H = !unread.hosts && src.hosts && typeof src.hosts === 'object' ? src.hosts : { at: null, here: '', hosts: {}, queue: {}, logins: [] };
    var O = src.ops && typeof src.ops === 'object' ? src.ops : { row: null }, B = src.budgets && typeof src.budgets === 'object' ? src.budgets : {};
    var AL = src.alarms && typeof src.alarms === 'object' ? src.alarms : {}, I = src.intake && typeof src.intake === 'object' ? src.intake : { open: [] };
    var num = function (v) { return typeof v === 'number' && isFinite(v) ? v : null; };
    var mins = function (t) { return num(t) == null ? null : Math.max(0, Math.round((now - t) / 60)); };
    var last = function (s) { return String(s || '').split('/').pop(); };   // a repo as owner/repo: its last part only
    var topicStep = function (topic) {   // 'lease-renewal-s6' → ship 'lease-renewal', step 'S6'; 'fleet-queue-s5-fix' → 'S5 fix'
      var m = String(topic).match(/^(.*?)-s(\d+)(?:-(.*))?$/), l = String(topic).match(/^(.*?)-land$/);
      return m ? { ship: m[1], step: 'S' + m[2] + (m[3] ? ' ' + m[3] : '') } : l ? { ship: l[1], step: 'landing' } : { ship: null, step: String(topic) };
    };
    var STALE = 30;   // min: a row older than this, when the poll read it, reads unread
    // a row's staleness is judged at the document's own time, never the viewer's: the deployed page keeps one document
    // up to an hour while the fleet is unchanged (board_sig), and every row would turn unread at 30 min (round-1 review)
    var docAt = srcAt('hosts') != null ? srcAt('hosts') : num(H.at) != null ? H.at : num(src.at) != null ? src.at : now;

    /* the ops row (the desk's), null where no desk has run on this host or its row did not read */
    var row = O && O.row && typeof O.row === 'object' ? O.row : null;
    var opsAge = row ? (num(row.as_of) != null ? mins(row.as_of) : num(O.age_s) != null ? Math.round(O.age_s / 60) : null) : null;   // the viewer's clock: a deployed document stands up to an hour
    var opsHost = row ? row.host : null;

    /* hosts: a card each. Three different things kept apart: unread (no sample for 30 min, or a row that does not
       parse), full (every slot taken, reservations counted), no room (headroom's memory rules), room ? (memory unread) */
    var hosts = Object.keys(H.hosts && typeof H.hosts === 'object' ? H.hosts : {}).sort().map(function (name) {
      var r = H.hosts[name];
      if (!r || typeof r !== 'object' || r.no_sample || num(r.at) == null) {
        return { id: name, os: '', role: '', here: false, source: 'ref', state: 'unread', word: 'unread', runs: [0, 0], live: 0, reserved: 0, checks: null, features: null, load: null, mem: null, swap: '', rate: 0, age: null,
          note: 'no sample: ' + (r && typeof r.no_sample === 'string' ? r.no_sample : 'its row does not read'), room: null, reason: '', near: [], limits: {}, runsList: [], runsUnread: true, unreadable: false, confined: 0, stale: 0, oldest: 0, history: [] };
      }
      var age = mins(r.at), stale = docAt - r.at > STALE * 60;   // engine_sig's rule exactly: seconds, no rounding
      var obj = function (v) { return v && typeof v === 'object' ? v : {}; };
      var lim = obj(r.limits), hr = obj(r.headroom), mem = obj(r.mem), sl = obj(r.slots), fn = obj(r.fence), ck = r.checks && typeof r.checks === 'object' ? r.checks : null;
      // a slot count that did not read (hosts writes null when dispatch --slots or the reservations fail) is unknown,
      // never 0: the host's word says so and the capacity row leaves it out, said
      var slotsUnread = num(sl.cap) == null || num(sl.busy) == null || num(sl.reserved) == null;
      var cap = num(sl.cap) || 0, busy = num(sl.busy) || 0, reserved = num(sl.reserved) || 0, live = slotsUnread ? 0 : Math.max(0, busy - reserved);
      var full = !slotsUnread && cap > 0 && busy >= cap, room = hr.room === true ? true : hr.room === false ? false : null;
      var swapGb = num(mem.swap_gb), swapT = num(mem.swap_total_gb);
      var swap = swapGb == null ? '' : swapT ? swapGb + ' of ' + swapT + ' GB' : swapGb + ' GB';
      var runs = Array.isArray(r.runs) ? r.runs : null;
      var rec = r.records && typeof r.records === 'object' ? r.records : null;
      return {
        id: name, os: typeof r.os === 'string' ? r.os : '', role: typeof r.role === 'string' ? r.role : '', here: r.source === 'here', source: r.source || 'ref',
        state: stale ? 'unread' : 'awake',
        word: stale ? 'unread' : room === false ? 'no room' : full ? 'full' : room == null || slotsUnread ? 'room ?' : 'room',
        runs: [busy, cap], live: live, reserved: slotsUnread ? 0 : reserved, slotsUnread: slotsUnread,
        // S4's checks {busy, cap, waiting}; before it, the desk's host takes the ops row's {slots_busy, waiting}; else unknown
        checks: ck && num(ck.busy) != null ? [ck.busy, num(ck.waiting) || 0, num(ck.cap)] : (opsHost === name && row.check && num(row.check.slots_busy) != null ? [row.check.slots_busy, num(row.check.waiting) || 0, null] : null),
        features: Array.isArray(r.features) ? r.features.filter(function (f) { return typeof f === 'string'; }) : null,
        load: r.load ? num(r.load.per_core_5m) : null, mem: num(mem.avail), swap: swap, rate: num(mem.rate) || 0,
        age: age, note: stale ? 'no sample for ' + (age < 120 ? age + ' min' : Math.round(age / 60) + ' h') + (r.role ? ' · the ' + r.role : '') : '',
        room: room, full: full, reason: typeof hr.reason === 'string' ? hr.reason : '', near: Array.isArray(hr.near) ? hr.near : [], limits: lim,
        runsList: (runs || []).filter(function (x) { return x && typeof x === 'object'; }).map(function (x) { var ts = topicStep(x.topic); return { topic: String(x.topic || '?'), ship: ts.ship, step: ts.step, repo: last(x.repo), login: typeof x.login === 'string' ? x.login : null, state: x.state || 'busy', prio: x.prio || null, since: num(x.started) > 0 ? mins(x.started) : null }; }),
        runsUnread: runs === null, unreadable: !!fn.unreadable, confined: num(fn.confined) || 0,
        // a record count that did not read is unknown (null), never 0 (S4: `records.stale` null with a note)
        stale: rec ? num(rec.stale) : null, oldest: rec ? num(rec.oldest_days) || 0 : 0,
        history: Array.isArray(r.history) ? r.history : []
      };
    });
    var byHost = {}; hosts.forEach(function (x) { byHost[x.id] = x; });
    var awake = hosts.filter(function (x) { return x.state === 'awake'; });
    var withRoom = awake.filter(function (x) { return x.room !== false && !x.full && !x.slotsUnread; });
    var counted = awake.filter(function (x) { return !x.slotsUnread; });
    var featured = awake.filter(function (x) { return x.features; });

    /* the queue: the fleet store, each entry with why it waits and a tone the eye reads first */
    var Q = H.queue && typeof H.queue === 'object' ? H.queue : {};
    var queue = (Array.isArray(Q.entries) ? Q.entries : []).filter(function (e) { return e && typeof e === 'object'; }).map(function (e) {
      var ts = topicStep(e.topic), store = String(e.qid || '').split(':')[0], pin = e.host || null, finish = e.kind === 'finish';
            // a finish with a host is held whatever its pin_kind (S4's rule: the ladder or held_here pinned it, never a person)
      var held = (!!e.pinned_why && !e.pin_kind) || (finish && !!pin);
      var q = { qid: String(e.qid || ''), store: store, finish: finish, prio: e.priority || 'normal', kind: e.kind || 'step',
        step: (ts.ship || last(e.repo)) + ' ' + ts.step, ship: ts.ship, repo: last(e.repo),
        on: e.prefer || null, released: num(e.prefer_off) != null, pin: pin, held: held ? String(e.pinned_why || 'a finish is held where its landing must run') : null,
        pinKind: pin ? (held ? 'held' : e.pin_kind === 'typed' || e.pin_kind === 'login' ? e.pin_kind : null) : null, by: typeof e.by === 'string' && e.by ? e.by.slice(0, 8) : null,
        pinLogin: typeof e.pin_login === 'boolean' ? e.pin_login : null,
        needs: Array.isArray(e.needs) && e.needs.length ? e.needs.join(', ') : null, needList: Array.isArray(e.needs) ? e.needs : [],
        after: Array.isArray(e.after) && e.after.length ? e.after.map(function (t) { return topicStep(t).step; }).join(', ') : null,
        age: mins(e.queued_at) || 0, attempts: num(e.attempts) || 0, refusal: typeof e.last_refusal === 'string' && e.last_refusal ? e.last_refusal : null,
        refusedBy: e.refused_by && typeof e.refused_by === 'object' ? Object.keys(e.refused_by).sort() : [], runningOn: e.running_on || null, claimedAt: mins(e.claimed_at),
        queued: e.state === 'queued', why: '', state: '', tone: 'wait', acts: [] };
      var pinned = q.pin && byHost[q.pin];
      if (e.state === 'running' || e.state === 'claimed') { q.state = (e.state === 'claimed' ? 'claimed by ' : 'running on ') + (q.runningOn || e.claimed_by || '?') + (q.claimedAt != null ? ' · ' + q.claimedAt + ' min ago' : ''); q.tone = 'run'; q.acts = ['watch', 'end']; }
      else if (e.state === 'waiting') { q.state = 'waiting on ' + (q.runningOn || e.claimed_by || '?'); q.tone = 'wait'; q.acts = ['watch', 'end']; }
      else if (q.after) { q.state = 'waits for ' + q.after; q.tone = 'wait'; q.why = 'after: its step must land first'; q.acts = ['cancel']; }
      else if (q.pin && !pinned) { q.state = 'cannot start: ' + q.pin + ' has no row'; q.tone = 'bad'; q.why = 'pinned to a host the hosts ref does not list'; q.acts = ['cancel']; }
      else if (q.pin && pinned.state !== 'awake') { q.state = 'cannot start: ' + q.pin + ' ' + pinned.state; q.tone = 'bad'; q.why = 'pinned to ' + q.pin + ' · ' + pinned.note; q.acts = ['cancel']; }
      else if (q.pin && pinned.slotsUnread) { q.state = 'waits: room on ' + q.pin + ' unknown'; q.tone = 'wait'; q.why = q.pin + '\'s run slots did not read'; q.acts = ['kick', 'cancel']; }
      else if (q.pin && (pinned.room === false || pinned.full)) { q.state = 'waits for room on ' + q.pin; q.tone = 'wait'; q.why = pinned.room === false ? pinned.reason : pinned.live + ' of ' + pinned.runs[1] + ' runs' + (pinned.reserved ? ', ' + pinned.reserved + ' reserved' : ''); q.acts = ['kick', 'cancel']; }
      else if (q.pin) { q.state = 'claimable: ' + q.pin + ' has room'; q.tone = 'ok'; q.acts = ['kick', 'cancel']; }
      else if (q.attempts >= 3 && q.refusal) { q.state = 'refused ' + q.attempts + ' times'; q.tone = 'bad'; q.why = 'last: ' + q.refusal + (q.refusedBy.length ? ' (' + q.refusedBy.join(', ') + ')' : ''); q.acts = ['kick', 'raise', 'cancel']; }
      else if (withRoom.length) { q.state = 'claimable: ' + withRoom.map(function (x) { return x.id; }).join(', ') + (withRoom.length === 1 ? ' has' : ' have') + ' room'; q.tone = 'ok'; q.why = q.refusal ? 'last: ' + q.refusal : ''; q.acts = ['kick', 'raise', 'cancel']; }
      else { q.state = 'waits for room'; q.tone = 'wait'; q.why = q.refusal ? 'last: ' + q.refusal : ''; q.acts = ['kick', 'raise', 'cancel']; }
      if (q.needs && q.tone !== 'run') {
        // S4's `features`: which awake host meets every need; before it, the rows carry none and the page says so
        var meets = featured.filter(function (x) { return q.needList.every(function (n) { return x.features.indexOf(n) >= 0; }); }).map(function (x) { return x.id; });
        q.why = (q.why ? q.why + ' · ' : '') + 'needs ' + q.needs + (featured.length ? (meets.length ? ': ' + meets.join(', ') + (meets.length === 1 ? ' meets it' : ' meet it') : ': no awake host lists it') + (featured.length < awake.length ? ' (' + (awake.length - featured.length) + ' unread)' : '') : ': the rows carry no features, so which host meets it is not shown');
      }
      if (q.released && q.on) q.why = (q.why ? q.why + ' · ' : '') + 'preferred ' + q.on + ', released: any host with room claims it';
      if (q.age >= 12 * 60 && q.tone !== 'run') { q.tone = 'bad'; q.why = (q.why ? q.why + ' · ' : '') + 'waiting ' + Math.round(q.age / 60) + ' h'; }
      // S4's repin moves a queued entry only, never one a run already holds (running_on), never a login's pin
      var movable = e.state === 'queued' && !q.runningOn && q.pinLogin !== true;
      if (movable && !q.after) {
        if (q.finish) { if (!q.pin && q.on) q.acts.push('unpin'); }   // a finish: no Pin; Unpin drops its preference only
        else if (q.pin && q.pinKind === 'typed' && q.pinLogin === false) q.acts.push('unpin');   // a typed pin no login holds
        else if (!q.pin) q.acts.push('pin');
      }
      return q;
    });
    var prioN = { force: 0, high: 1, normal: 2, low: 3 };
    queue.sort(function (a, b) { return (prioN[a.prio] == null ? 4 : prioN[a.prio]) - (prioN[b.prio] == null ? 4 : prioN[b.prio]) || b.age - a.age || (a.qid < b.qid ? -1 : a.qid > b.qid ? 1 : 0); });
    var queued = queue.filter(function (q) { return q.queued; }), claimed = queue.filter(function (q) { return !q.queued; });

    /* the logins: the five-hour window against account's pace (its rule: the window's elapsed share), the week against
       its ceiling, a standing in one word from the judge's own line */
    var FIVE_H = 5 * 3600;
    var logins = (Array.isArray(H.logins) ? H.logins : []).filter(function (l) { return l && typeof l === 'object'; }).map(function (l) {
      var lim = l.limits && typeof l.limits === 'object' ? l.limits : {}, at = num(l.sampled), end = num(lim.five_hour_resets);
      var pace = at != null && end != null && end - at > 0 && end - at <= FIVE_H ? Math.round(100 * (1 - (end - at) / FIVE_H)) : null;
      var why = typeof l.why === 'string' ? l.why : '';
      var word = l.parked ? 'parked' : l.eligible ? 'eligible' : /^locked/.test(why) ? 'locked' : /^week/.test(why) ? 'week spent' : /^5h/.test(why) ? 'resting' : 'held back';
      var tone = { parked: 'park', eligible: 'ok', locked: 'bad', 'week spent': 'bad', resting: 'wait', 'held back': 'wait' }[word];
      return { id: String(l.label || '?'), primary: !!l.primary, plan: typeof lim.plan === 'string' ? lim.plan : '', week: num(lim.seven_day), five: num(lim.five_hour), fable: num(lim.fable_week), pace: pace, word: word, tone: tone, why: why, parked: !!l.parked, eligible: !!l.eligible, sampled: mins(l.sampled), resets: end != null && end > now ? end : null };
    });

    /* CI: the desk's budget per account joined with ci-budgets.json (the reserve, the week share, the margin) and the
       alarm level (budget_level's terms), its issue from ci-budget-alarms.json; an unread budget has no numbers and
       says why in a fixed word */
    var accounts = B.accounts && typeof B.accounts === 'object' ? B.accounts : {};
    var UNREAD = { absent: 'no token for it on the desk', refused: 'the provider refused the read', unread: 'the read did not answer' };
    var budgets = Object.keys(row && row.budget && typeof row.budget === 'object' ? row.budget : {}).sort().map(function (k) {
      var e = row.budget[k] && typeof row.budget[k] === 'object' ? row.budget[k] : {}, b = accounts[k] && typeof accounts[k] === 'object' ? accounts[k] : {}, al = AL[k] && typeof AL[k] === 'object' ? AL[k] : null;
      var reserve = num(b.reserve) != null ? b.reserve : num(B.reserve) != null ? B.reserve : 0.2;
      var out = { name: k, provider: typeof b.provider === 'string' ? b.provider : null, unit: e.unit || (b.month_credits ? 'credits' : 'minutes'), state: e.state || 'unread', reserve: Math.round(reserve * 100), used: null, cap: null, share: null, week: null, weekUsed: null, weekCap: null, level: null, levelWhy: '', issue: al && num(al.issue) != null ? al.issue : null, since: al ? mins(al.since) : null };
      if (e.state !== 'ok') { out.unread = UNREAD[e.state] || UNREAD.unread; return out; }
      var cap = num(e.cap) != null ? e.cap : out.unit === 'minutes' ? num(b.month_minutes) : num(b.month_credits);   // the unit's own, as ops' read_budget
      if (!(cap > 0)) cap = null;   // read_budget keeps a cap only above 0; budget_level judges none without one
      var margin = num(b.margin) != null ? b.margin : out.unit === 'credits' ? 0.1 : 0, ws = num(b.week_share);
      out.used = num(e.used) || 0; out.weekUsed = num(e.week_used); out.cap = cap; out.share = cap ? Math.round(out.used / cap * 100) : null;
      out.weekCap = cap && ws ? Math.round(cap * ws) : null; out.week = out.weekCap && out.weekUsed != null ? Math.round(out.weekUsed / out.weekCap * 100) : null;
      var usedM = out.used * (1 + margin), weekM = (out.weekUsed || 0) * (1 + margin), net = num(e.net_amount) || 0;
      if (cap == null) { out.level = null; out.levelWhy = 'no cap in ci-budgets.json'; }
      else if (net > 0) { out.level = 'reserve'; out.levelWhy = 'pays beyond its plan this month'; }
      else if (usedM >= cap * (1 - reserve)) { out.level = 'reserve'; out.levelWhy = 'the ' + out.reserve + ' % reserve reached, the margin counted'; }
      else if (ws && weekM >= cap * ws) { out.level = 'week'; out.levelWhy = 'past its week share of ' + out.weekCap; }
      else { out.level = 'ok'; out.levelWhy = 'under its reserve'; }
      return out;
    });
    var ciWeek = budgets.filter(function (b) { return b.week != null; }).reduce(function (a, b) { return Math.max(a == null ? 0 : a, b.week); }, null);

    /* Intake: the desk's cards, a kind and a number each; the mention from the kind (alarms and contacts mention the
       owner, bugs nobody: AGENTS.md "Where an issue goes"); never the card's url, its scope or the desk's why */
    var ALARM = /^(deadman|stall|budget)$/;
    var intake = (Array.isArray(I.open) ? I.open : []).filter(function (c) { return c && typeof c === 'object'; }).map(function (c) {
      var kind = String(c.kind || 'other');
      return { kind: kind, n: num(c.number), repo: last(c.repo), author: String(c.author || '?'), age: num(c.created) != null ? Math.max(0, (now - c.created) / 3600) : null, mentions: ALARM.test(kind) || kind === 'contact', alarm: ALARM.test(kind) };
    });
    var G = I.guarded && typeof I.guarded === 'object' ? I.guarded : {};
    var guarded = Object.keys(G).reduce(function (a, k) { return a + (num(G[k]) || 0); }, 0);
    var alarms = intake.filter(function (x) { return x.alarm; }).length + Object.keys(G).filter(function (k) { return ALARM.test(k); }).reduce(function (a, k) { return a + (num(G[k]) || 0); }, 0);

    /* capacity, summed over the awake hosts; checks from the rows that carry them, else the desk's for its own host */
    var runsUnknown = !unread.hosts && awake.length > 0 && !counted.length;   // every awake host's slots unread: unknown, never 0
    var runs = unread.hosts ? null : counted.reduce(function (a, x) { return [a[0] + x.live, a[1] + x.runs[1]]; }, [0, 0]);
    var reserved = counted.reduce(function (a, x) { return a + x.reserved; }, 0);
    var queueUnknown = unread.hosts || !!Q.unreadable || !!Q.fence_unreadable || !!Q.guard_unread;
    var withChecks = hosts.filter(function (x) { return x.checks; });
    var checks = withChecks.length ? withChecks.reduce(function (a, x) { return [a[0] + x.checks[0], a[1] + x.checks[1], x.checks[2] == null || a[2] == null ? null : a[2] + x.checks[2]]; }, [0, 0, 0]) : null;

    /* what needs a hand: one line each, the action beside it — the page's first list, and its badge */
    var needs = [];
    if (unread.hosts && !off.hosts) needs.push({ tone: 'bad', text: 'the hosts did not read at the poll: hosts, the queue and the logins are unknown here', act: null });
    hosts.forEach(function (x) {
      if (x.stale == null && x.state === 'awake') needs.push({ tone: 'wait', text: x.id + ': its peer records did not read, so the stale ones are unknown', act: null, host: x.id });
      else if (x.stale) needs.push({ tone: 'wait', text: x.stale + ' stale peer records on ' + x.id + ', the oldest ' + x.oldest + ' d', act: 'settle', host: x.id, target: x.id });
      if (x.state === 'unread') needs.push({ tone: 'bad', text: x.id + ': ' + x.note, act: null, host: x.id });
      if (x.state === 'awake' && x.room === false) needs.push({ tone: 'bad', text: x.id + ' refuses runs: ' + x.reason, act: 'limits', host: x.id, target: x.id });
      if (x.state === 'awake' && x.room == null) needs.push({ tone: 'wait', text: x.id + ': ' + (x.reason || 'memory unreadable there') + ' — dispatch goes ahead there without the rule', act: null, host: x.id });
      if (x.state === 'awake' && x.slotsUnread) needs.push({ tone: 'wait', text: x.id + ': its run slots did not read, so its room is unknown and the capacity row leaves it out', act: null, host: x.id });
      if (x.state === 'awake' && x.runsUnread) needs.push({ tone: 'wait', text: x.id + ': its runs are unread (no dispatch-rc there)' + (x.slotsUnread ? '' : '; ' + x.live + ' of ' + x.runs[1] + ' slots busy'), act: null, host: x.id });
    });
    // the line's action on the host its row's button names (engine.js: the run's host first; a Pin on this host)
    queue.forEach(function (q) { if (q.tone === 'bad') { var a = q.acts[0] || null; needs.push({ tone: 'bad', text: q.step + ' ' + q.state + (q.why ? ' · ' + q.why : ''), act: a, host: a === 'pin' ? H.here : q.runningOn || q.pin || q.on || H.here, target: q.qid }); } });
    if (!unread.hosts && (Q.unreadable || Q.fence_unreadable || Q.guard_unread)) needs.push({ tone: 'bad', text: Q.unreadable ? 'the queue ref did not read: the queue is unknown here, not empty' : Q.fence_unreadable ? 'the registry did not read, so every entry was dropped: the queue is unknown here, not empty' : 'the guarded list did not read, so every run and entry was hidden: the queue is unknown here, not empty', act: null });
    logins.forEach(function (l) { if (!l.parked && !l.eligible) needs.push({ tone: l.tone, text: l.id + ' ' + l.word + ': ' + l.why, act: null }); });
    if (unread.ops) needs.push({ tone: 'wait', text: 'CI unread: the desk\'s row did not read at the poll', act: null });
    else if (row && !(row.budget && typeof row.budget === 'object')) needs.push({ tone: 'wait', text: 'CI unread: the desk\'s budget read did not answer this sample', act: null });
    if (unread.budgets && row) needs.push({ tone: 'wait', text: 'CI: ci-budgets.json did not read, so the reserves and week shares are the defaults', act: null });
    budgets.forEach(function (b) {
      if (b.unread) needs.push({ tone: 'wait', text: 'CI · ' + b.name + ' unread: ' + b.unread, act: null });
      else if (b.level && b.level !== 'ok') needs.push({ tone: 'bad', text: 'CI · ' + b.name + ' ' + (b.level === 'reserve' ? 'into its reserve' : 'past its week share') + ': ' + b.used.toLocaleString('en-US') + ' of ' + b.cap.toLocaleString('en-US') + ' ' + b.unit + (b.issue ? ' · issue #' + b.issue : ''), act: null });
    });
    if (unread.intake) needs.push({ tone: 'wait', text: 'Intake unread: the desk\'s intake did not read at the poll', act: null });
    if (alarms) needs.push({ tone: 'bad', text: alarms + (alarms === 1 ? ' alarm' : ' alarms') + ' in Intake', act: 'intake' });

    /* a chip per feed: its own `at` where the poll recorded one, its age, and whether it read */
    var OFF = { ci: 'off: no desk sample on this host', intake: 'off: no intake on this host' };
    var peerAge = Math.max.apply(null, hosts.filter(function (x) { return x.state === 'awake' && !x.here; }).map(function (x) { return x.age; }).concat([0]));
    var sources = {
      hosts: { label: 'hosts ref', at: srcAt('hosts') != null ? srcAt('hosts') : num(H.at), age: unread.hosts ? null : peerAge, unread: unread.hosts && !off.hosts, off: off.hosts, live: off.hosts ? 'off: no hosts tool on this host' : unread.hosts ? 'unread: hosts --json did not answer at the poll' : 'this host sampled at the poll; the others every 10 min and at each claim' },
      queue: { label: 'the queue ref', at: num(H.at), age: unread.hosts ? null : mins(H.at), unread: unread.hosts || !!Q.unreadable, live: unread.hosts ? 'unread: hosts --json did not answer at the poll' : Q.unreadable ? 'unread: the queue ref did not read' : 'read at the poll' },
      logins: { label: 'account limits', at: num(H.at), age: unread.hosts || !logins.length || logins.some(function (l) { return !l.parked && l.sampled == null; }) ? null : Math.max.apply(null, logins.filter(function (l) { return !l.parked; }).map(function (l) { return l.sampled; }).concat([0])), unread: (unread.hosts && !off.hosts) || !logins.length, live: unread.hosts ? 'unread: hosts --json did not answer at the poll' : !logins.length ? 'unread: no login in the answer (account limits may have failed)' : 'the cached read; a parked login is not walked, so its reading does not age the chip' },
      ci: { label: 'the desk', at: row ? num(row.as_of) : srcAt('ops'), age: opsAge, unread: unread.ops, off: !row && !unread.ops, live: unread.ops ? 'unread: ops status --json did not answer at the poll' : row ? 'the desk\'s 15-minute job' + (O.stale ? ' · stale' : '') + (row.partial ? ' · partial' : '') + (unread.budgets ? ' · ci-budgets.json unread' : '') + (unread.alarms ? ' · the alarms file unread' : '') : OFF.ci },
      intake: { label: 'the desk', at: srcAt('intake'), age: unread.intake || off.intake || I.why ? null : srcAt('intake') != null ? mins(srcAt('intake')) : opsAge, unread: unread.intake, off: !unread.intake && (off.intake || !!I.why), live: unread.intake ? 'unread: ops intake --json did not answer at the poll' : off.intake || I.why ? OFF.intake : 'the desk\'s 10-minute job' }
    };
    return {
      here: H.here || '', at: num(H.at) != null ? H.at : num(src.at), unread: unread, queueUnknown: queueUnknown, hosts: hosts, queue: queue, queued: queued, claimed: claimed, dropped: num(Q.dropped) || 0, fenceUnreadable: !!Q.fence_unreadable, queueUnreadable: !!Q.unreadable, ref: H.ref && typeof H.ref === 'object' ? H.ref : {},
      ops: { runs: runs, runsUnknown: runsUnknown, runsPartial: counted.length < awake.length, reserved: reserved, checks: checks, ci: ciWeek, logins: logins, ci_budgets: budgets, partial: !!(row && row.partial), host: opsHost, stale: !!(row && O.stale) },
      records: H.records && typeof H.records === 'object' ? { stale: num(H.records.stale), oldest_days: num(H.records.oldest_days) || 0 } : { stale: unread.hosts ? null : 0, oldest_days: 0 },
      intake: intake, intakeGuarded: guarded, alarms: alarms, needs: needs, sources: sources, guardUnread: !!Q.guard_unread,
      // a null CI week is "no week share set" only when the row's budget read and every budget in it read ok; a budget
      // that did not read (null: the desk's read timed out or crashed; or any unread account) is unread
      ciRead: !!row && !unread.ops && !!row.budget && typeof row.budget === 'object' && budgets.every(function (b) { return !b.unread; }),
      running: hosts.reduce(function (a, x) { return a.concat(x.runsList.map(function (r) { return { ship: r.ship, step: r.step, host: x.id, login: r.login, since: r.since }; })); }, [])
    };
  }
  root.ENGINE_ADAPT = ADAPT;
  if (typeof module === 'object' && module.exports) module.exports = ADAPT;
})(typeof window !== 'undefined' ? window : this);
