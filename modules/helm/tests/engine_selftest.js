/* engine_selftest.js — test_engine.sh's reads inside the helm board on ?view=engine (docs/engine-room-2026-11-02.md S3),
   injected after board.js; never shipped. Carried from the design's prototype/selftest-engine.js onto the landed shell:
   ?selftest=<label> posts [{name, ok, got}] to the parent, the Engine room's facts at the frame's width and theme on the
   fixture (tests/engine_fixture.js at today's clock, in the poll's envelope); ?road=token runs the token road's cases.
   The adapter's own cases on the real shapes are tests/engine_proof.js (node, no DOM); here the page is what is read.
   No private word in a case (the design review's finding 16): the fixture's names are host-N, node-N and acct-N. */
(function () {
  var q = new URLSearchParams(location.search), label = q.get('selftest'), out = [], H = window.HELM, road = q.get('road') === 'token' ? 'token' : 'press';
  function read(name, ok, got) { out.push({ name: name, ok: !!ok, got: got === undefined ? '' : String(got) }); }
  function shown(el) { return !!el && getComputedStyle(el).display !== 'none' && el.getClientRects().length > 0; }
  function $(s) { return document.querySelector(s); }
  function $$(s) { return Array.prototype.slice.call(document.querySelectorAll(s)); }
  function txt(s) { var e = $(s); return e ? e.textContent.replace(/\s+/g, ' ') : ''; }
  function post() { parent.postMessage({ board: label, out: out }, '*'); }
  function key(k) { document.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })); }
  function click(el) { if (el) el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })); }
  function clone(o) { return JSON.parse(JSON.stringify(o)); }
  function lum(c) { var m = c.match(/\d+(\.\d+)?/g).map(Number); var a = m.slice(0, 3).map(function (v) { v /= 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }); return 0.2126 * a[0] + 0.7152 * a[1] + 0.0722 * a[2]; }
  function cr(a, b) { var x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }
  function bgOf(el) { while (el && el !== document.documentElement) { var b = getComputedStyle(el).backgroundColor; if (b && !/rgba\(0, 0, 0, 0\)|transparent/.test(b)) return b; el = el.parentElement; } return getComputedStyle(document.body).backgroundColor; }

  function engine() {
    var w = innerWidth, wide = w >= 1100, phone = w < 520, E = H.E(), main = $('#main');
    read('no script error', !(window.__errs || []).length, (window.__errs || []).join(' | '));
    read('the theme asked for', document.documentElement.dataset.theme === q.get('theme'), document.documentElement.dataset.theme);
    read('the Engine room is the view, its adapter read the fixture', main.dataset.view === 'engine' && !!E && E.hosts.length === 6 && E.queue.length === 10, main.dataset.view + ' ' + (E && [E.hosts.length, E.queue.length].join('/')));
    read('no sideways scroll', document.documentElement.scrollWidth <= w + 1, document.documentElement.scrollWidth + ' > ' + w);
    var badge = $$('#side .vw.engine .vb, #csheet .vw.engine .vb')[0];
    read('the Engine room\'s slot counts what needs a hand (13)', badge && badge.textContent === String(E.needs.length) && E.needs.length === 13, badge && badge.textContent);
    var h1 = txt('.vh h1'), sub = txt('.vh .vsub');
    read('the head counts live runs and queued entries: 6 runs on 4 hosts, 9 wait, 2 cannot start, 1 claimed', /6 runs at work on 4 hosts/.test(h1) && /9 wait in the queue, 2 cannot start; 1 claimed/.test(h1), h1);
    read('the sub names the alarms, the stale records, CI, the reservation, the unread runs and the fence', /3 alarms/.test(sub) && /28 stale records/.test(sub) && /CI at 93 %/.test(sub) && /1 slot reserved/.test(sub) && /runs unread/.test(sub) && /counted only/.test(sub), sub);
    read('the eyebrow says as of when and on which host', /Engine room · as of \d\d:\d\d on host-a/.test(txt('.vh .eyebrow')), txt('.vh .eyebrow'));
    read('the section tabs: six, counted, All on', $$('.ecats .cat').length === 6 && !!$('.ecats .cat.on[data-esec="all"]') && /Needs a hand ?13/.test(txt('.ecats')), txt('.ecats'));
    read('All: the capacity row, needs (13), 6 hosts, the queue (10), the logins (5), 3 CI budgets and Intake (7), in that order',
      $$('.ekpis .kpi').length === 4 && $$('#e-needs li').length === 13 && $$('#e-hosts .host').length === 6 && $$('table.equeue tbody tr').length === 10 && $$('table.elogins tbody tr').length === 5 && $$('.cib .kpi').length === 3 && $$('table.eintake tbody tr').length === 7 &&
      $$('#main .eroom .sec').map(function (s) { return s.id; }).join() === 'e-needs,e-hosts,e-queue,e-logins,e-intake',
      [$$('.ekpis .kpi').length, $$('#e-needs li').length, $$('#e-hosts .host').length, $$('table.equeue tbody tr').length, $$('table.elogins tbody tr').length, $$('.cib .kpi').length, $$('table.eintake tbody tr').length].join('/'));
    read('every feed has its chip, its age and its own time; none red on a fresh night', $$('.srcs .src').length === 5 && $$('.srcs .src.bad').length === 0 && $$('.srcs .src').every(function (s) { return /min ago|just now|off/.test(s.textContent); }), $$('.srcs .src').map(function (s) { return s.textContent; }).join(' | '));
    read('host-c\'s 3.2 h sample reads unread, its age red; host-e (a row that does not parse) says so', /3\.2 h ago/.test(txt('#e-host-host-c .gl')) && !!$('#e-host-host-c .gl dd.t-bad') && /does not parse/.test(txt('#e-host-host-e')), txt('#e-host-host-c .gl'));
    read('node-2: runs unread (never "no runs"), memory unread; checks unread on every card but the desk\'s', /runs unread here/.test(txt('#e-host-node-2')) && !/no runs/.test(txt('#e-host-node-2')) && /memory unreadable/.test(txt('#e-host-node-2')) && /1 busy/.test(txt('#e-host-host-a .gl')) && /unread/.test(txt('#e-host-node-1 .gl')), txt('#e-host-node-2').slice(0, 160));
    read('each host card shows its host\'s name (the shell\'s find hides .hid: the name is .hnm)', $$('.eroom .host .hnm').filter(shown).map(function (n) { return n.textContent; }).join() === 'host-a,host-b,host-c,host-e,node-1,node-2', $$('.eroom .host .hnm').filter(shown).length);
    read('node-1\'s pips: 2 runs lit, 1 reserved hatched, 1 free', $$('#e-host-node-1 .pips i.on').length === 2 && $$('#e-host-node-1 .pips i.res').length === 1 && $$('#e-host-node-1 .pips i').length === 4);
    read('a run with no login reads "login ?"; the fence a count, no confined topic', /login \?/.test(txt('#e-hosts')) && /in a confidential scope or a guarded repo · a count/.test(txt('#e-host-host-a')) && !/confined-|secret-/.test(main.textContent));
    read('a stale pile on host-a with Settle; no other host has one', $$('.eroom .stale').length === 1 && !!$('#e-host-host-a .stale [data-verb^="e:settle"]'));
    var rows = $$('table.equeue tbody tr'), row = function (re) { return rows.filter(function (r) { return re.test(r.textContent); })[0]; };
    read('the queue tells pins apart: a typed --pin, a held pin, a pin of unread kind, the finish held; two --on, one released', $$('table.equeue .rts:not(.inrow) .rt.hard').length === 4 && $$('table.equeue .rts:not(.inrow) .rt.held').length === 2 && $$('table.equeue .rts:not(.inrow) .rt.soft').length === 2 && /released/.test(txt('table.equeue')) && /kind unread/.test(txt('table.equeue')),
      [$$('table.equeue .rts:not(.inrow) .rt.hard').length, $$('table.equeue .rts:not(.inrow) .rt.held').length, $$('table.equeue .rts:not(.inrow) .rt.soft').length].join('/'));
    read('the 20-hour age red; two state pills say cannot start or refused', $$('table.equeue td.t-bad').length === 1 && $$('table.equeue td:nth-child(6) .st.bad').length === 2, $$('table.equeue td.t-bad').length + ' ' + $$('table.equeue td:nth-child(6) .st.bad').length);
    var run = row(/running on node-1/), fin = row(/harbor-lights/);
    read('the claimed entry: Watch and End, no Kick or Pin', run && run.querySelector('[data-verb^="e:watch"]') && run.querySelector('[data-verb^="e:end"]') && !run.querySelector('[data-verb^="e:kick"], [data-verb^="e:pin"]'));
    read('the finish: held, a finish chip, no Pin and no Unpin', fin && /finish/.test(fin.textContent) && /held on host-a/.test(fin.textContent) && !fin.querySelector('[data-verb^="e:pin"], [data-verb^="e:unpin"]'));
    read('Unpin only on the typed pin no login holds', $$('table.equeue [data-verb^="e:unpin"]').length === 1 && /lease-renewal/.test(($$('table.equeue [data-verb^="e:unpin"]')[0] || { closest: function () { return { textContent: '' }; } }).closest('tr').textContent));
    var verified = $$('#main .eroom [data-verb^="e:raise"], #main .eroom [data-verb^="e:cancel:"], #main .eroom [data-verb^="e:end"], #main .eroom [data-verb^="e:limits"], #main .eroom [data-verb^="e:park"], #main .eroom [data-verb^="e:ceiling"], #main .eroom [data-verb^="e:pin"], #main .eroom [data-verb^="e:unpin"]');
    if (road === 'press') read('the press road: every verified kind and Pin/Unpin disabled and dashed; Kick and Settle live', verified.length > 10 && verified.every(function (b) { return b.disabled && getComputedStyle(b).borderStyle === 'dashed'; }) && $$('#main .eroom [data-verb^="e:kick"]').some(function (b) { return !b.disabled; }), verified.filter(function (b) { return !b.disabled; }).map(function (b) { return b.dataset.verb; }).join());
    else read('the token road: every kind live', verified.length > 10 && verified.every(function (b) { return !b.disabled; }));
    var contact = $$('table.eintake tbody tr').filter(function (r) { return /contact/.test(r.textContent); });
    read('a contact is a kind and a number: the repo its last part, "stranger", no owner, nothing more', contact.length === 2 && contact.every(function (r) { return /inbox #9[35]/.test(r.textContent) && /stranger/.test(r.textContent) && !/acct-owner/.test(r.textContent) && r.textContent.length < 80; }));
    read('no NaN, undefined or null on the page; no path, address or home folder', !/\bNaN\b|\bundefined\b|\bnull\b/.test(main.textContent) && !/\/Users|\/home\/|~\/|<home>|https?:/.test(main.textContent));
    // contrast: the Engine room's own text pairs, ≥ 4.5:1 in this theme
    var pairs = $$('.eroom .src, .eroom .rt.soft, .eroom .rt.need, .eroom .rt.held, .eroom .qwhy, .eroom .hrole, .eroom .host .note, .eroom .stale span, .eroom .kpi .ks').filter(shown);
    var low = pairs.filter(function (el) { return cr(getComputedStyle(el).color, bgOf(el)) < 4.5; });
    read('every Engine room text pair at 4.5:1 or more', pairs.length > 20 && !low.length, low.slice(0, 3).map(function (el) { return el.className + ' ' + cr(getComputedStyle(el).color, bgOf(el)).toFixed(2); }).join(' | '));
    if (phone) {
      read('the phone: two KPIs across, one host a row, the queue\'s header folded', getComputedStyle($('.ekpis')).gridTemplateColumns.split(' ').length === 2 && getComputedStyle($('.ehosts')).gridTemplateColumns.split(' ').length === 1 && !shown($('table.equeue thead')), getComputedStyle($('.ekpis')).gridTemplateColumns);
    } else {
      var across = w >= 760 ? 2 : 1;
      read(across === 2 ? 'two host cards across' : 'one host card a row under 760 px', getComputedStyle($('.ehosts')).gridTemplateColumns.split(' ').length === across, getComputedStyle($('.ehosts')).gridTemplateColumns);
    }
    // the page's reads, then its moves
    if (road === 'token') {
      click($('table.equeue [data-verb^="e:unpin"]'));
      read('token road: Unpin asks first, naming a typed --pin no login holds', /typed --pin/.test(txt('.econfirm')) && /no login holds it/.test(txt('.econfirm')), txt('.econfirm'));
      key('Escape');
      read('esc closes the confirm', !$('.econfirm'));
      click($('table.equeue [data-verb^="e:pin"]'));
      read('token road: Pin asks first, saying a typed pin its --next inherits', /typed --pin/.test(txt('.econfirm')) && /--next inherits the pin/.test(txt('.econfirm')), txt('.econfirm'));
      click($('.econfirm [data-verb^="e:ok"]'));
      read('confirmed, the envelope is recorded on the page and said not sent', /recorded on this page, not sent/.test(txt('table.equeue')) && /not sent/.test(txt('#toast')), txt('#toast'));
    } else {
      var k = $$('#main .eroom [data-verb^="e:kick"]').filter(function (b) { return !b.disabled; })[0];
      click(k);
      read('a press records its envelope here and says not sent (S3 has no executor)', /recorded on this page, not sent/.test(main.textContent) && /not sent/.test(txt('#toast')), txt('#toast'));
    }
    click($('.ecats [data-esec="queue"]'));
    read('the Queue tab shows the queue alone: no capacity row, no hosts', !!$('#e-queue') && !$('#e-hosts') && !$('.ekpis') && $('.ecats .cat.on').dataset.esec === 'queue');
    click($('.ecats [data-esec="all"]'));
    // the poll: a document whose hosts did not read is unread on the page, never zero
    var keep = clone(window.__engine);
    H.applyEngine({ at: keep.at + 60, sources: { hosts: { state: 'unread', at: null }, ops: keep.sources.ops, budgets: keep.sources.budgets, alarms: keep.sources.alarms, intake: keep.sources.intake }, hosts: null, ops: keep.ops, budgets: keep.budgets, alarms: keep.alarms, intake: keep.intake });
    read('a poll whose hosts did not read: the head says so, the counts read ?, no "0 runs"', /did not read/.test(txt('.vh h1')) && /Hosts \?/.test(txt('#e-hosts .gh')) && !/\b0 runs\b/.test(main.textContent) && /unread/.test(txt('.ekpis')), txt('.vh h1'));
    read('…and the watch list still counts Intake and its alarms then', /7 in Intake, 3 alarms/.test(txt('#side .watch, #csheet .watch')), txt('#side .watch, #csheet .watch'));
    H.applyEngine(keep);
    read('the next poll restores it', /6 runs at work on 4 hosts/.test(txt('.vh h1')));
    // Fleet's one line points here with the same counts
    H.go('fleet');
    var p = txt('#main .engine-line.pointer');
    read('Fleet\'s pointer: 6 runs on 4 hosts, 9 queued, 2 cannot start, 3 alarms, CI 93 %, as of a time', /6 runs on 4 hosts/.test(p) && /9 queued, 2 cannot start/.test(p) && /3 alarms in Intake/.test(p) && /CI 93 %/.test(p) && /as of \d\d:\d\d/.test(p) && !!$('#main .engine-line.pointer a[data-view="engine"]'), p);
    read('the watch list counts the queue and Intake from the same document', /9 queued · 2 cannot start/.test(txt('#side .watch, #csheet .watch')) && /7 in Intake, 3 alarms/.test(txt('#side .watch, #csheet .watch')), txt('#csheet .watch'));
    key('g'); key('e');
    read('G then E goes back to the Engine room', main.dataset.view === 'engine', main.dataset.view);
  }

  addEventListener('load', function () {
    try { engine(); } catch (e) { read('no exception', false, e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e); }
    post();
  });
})();
