/* board.js — the helm board's shell (helm-board-ux S3, docs/helm-board-ux-2026-10-26.md), built to the helm council's
   round-6 prototype (docs/helm-council-2026-11-01/fable/r6/board.js: strip, sea, placeBoats, head, sideHTML, viewLinks,
   render, refresh, savebar). helm_render.board_page() inlines this file, board.css and board.html with keel's
   foundation (tokens.css, art.js, fx.js: helm-ui S10) and the board's first snapshot, so one file serves the local
   server, a spacesheep deploy and an Artifact; the page reads state.json beside it every 30 s.
   The shell: the sky strip (the mark, every ship sailing toward the finish at the share of its steps done, the time,
   the host, the week, today's spend), its horizon, the views down the left with a count each (a tab bar below 1100 px),
   search, the theme, the keys sheet (?), the save strip, a nav slot for the Engine room; each view's head (an eyebrow,
   one sentence, the counts that matter). What each view holds until its own step (Decide S11, Fleet and Ships S12,
   Skippers and Reports S6) is the board's cards as they were, in the new look.
   The poll never redraws the page: every region is reconciled by key (`data-k`), and a node that holds the focus or
   a draft (a field whose value is not its default) is patched in place, never replaced, kept even when its card left.
   Prices are effective only, `$0.07e` (the header's `ratio`, the core's cost_ratio). Stdlib-free: no library. */
(function () {
  'use strict';
  var snap = document.getElementById('snapshot');
  var S = JSON.parse(snap ? snap.textContent : '{}');
  var q = new URLSearchParams(location.search || window.__q || '');
  var B = window.HELM = { S: function () { return S; } };
  /* the Engine room (engine_adapter.js, engine.js; docs/engine-room-2026-11-02.md S3): its own document, engine.json beside
     state.json, adapted at each render (the ages move with the clock), so every count the shell shows of it agrees */
  var esnap = document.getElementById('engine-snapshot');
  var ES = (function () { try { return JSON.parse(esnap ? esnap.textContent : 'null'); } catch (e) { return null; } })();
  var EC = null;
  function E() {
    if (EC) return EC;
    var A = window.ENGINE_ADAPT;
    try { EC = A ? A(ES || { sources: { hosts: { state: 'unread' }, ops: { state: 'unread' }, intake: { state: 'unread' } } }, Date.now() / 1000) : null; } catch (e) { EC = null; }
    return EC;
  }
  B.E = E;
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  function get(k, d) { try { return localStorage.getItem('helm-' + k) || d; } catch (e) { return d; } }
  function put(k, v) { try { localStorage.setItem('helm-' + k, v); } catch (e) { /* private window */ } }
  var VIEWS = [['decide', 'keel', 'Decide'], ['fleet', 'wharf-runs', 'Fleet'], ['ships', 'regatta-small', 'Ships'],
               ['skippers', 'navigator', 'Skippers'], ['reports', 'plumb', 'Reports']];
  var ENGINE = ['engine', 'lighthouse', 'Engine room'];
  var NAMES = VIEWS.concat([ENGINE]).map(function (v) { return v[0]; });
  var V = { view: NAMES.indexOf(q.get('view')) >= 0 ? q.get('view') : NAMES.indexOf(get('view', '')) >= 0 ? get('view', '') : 'decide', find: '', g: 0, esec: q.get('sec') || 'all' };
  var ev = null;
  function EV() {   // the Engine room's view, built once; it reads E() at every call
    if (!E()) return null;   // a document the adapter refused: the fallback below, never a view over nothing
    if (ev || !window.ENGINE_VIEW) return ev;
    return (ev = window.ENGINE_VIEW({ E: E, V: V, esc: esc, plural: plural, N: N, hhmm: hhmm, road: q.get('road'), render: function () { render(); }, url: function () { url(); }, toast: function (m) { toast(m); },
      week: function () { var w = String((S.header || {}).week || ''), m = w.match(/(\d+(?:\.\d+)?)\s*%/); return { pct: m ? Math.round(+m[1]) : null, line: w }; } }));
  }
  if (q.get('sky') === '0') document.documentElement.classList.add('nosky');
  var ao = location.ancestorOrigins;
  if (q.get('sheep') === '1' || (ao && ao.length && /spacesheep\./.test(ao[ao.length - 1]))) document.documentElement.classList.add('sheep');

  /* ── the identity's module icons (the council's icons.js, the seven the shell draws) ── */
  var ICONS = {
    'helm': '<path d="M28.68 13.49 A11.5 11.5 0 1 1 25.2 12.56"/><path d="M24.16 19.5 L24.65 5.41"/><path d="M31.99 15.73 L36.09 11.48"/><path d="M28.5 23.92 L42.5 23.68"/><path d="M31.84 32.41 L36 36.87"/><path d="M24.08 28.5 L24.32 42.2"/><path d="M16.01 32.27 L11.64 36.8"/><path d="M19.5 23.84 L5.61 23.36"/><path d="M15.73 16.01 L11.56 11.98"/>',
    'keel': '<path d="M41 5.5 Q38.5 10 26 10 Q13 10 8 6.5"/><path d="M11.5 11.5 L10 17"/><path d="M27 11.5 L24.5 30.5"/><path d="M17 37 Q17 32 24.5 32 Q29.5 32 33 37 Q29.5 42 24.5 42 Q17 42 17 37 Z"/>',
    'wharf-runs': '<path d="M14.5 21 Q18 19.5 18 13.5 Q18 5.5 24 5.5 Q30 5.5 30 13.5 Q30 19.5 33.5 21 Z"/><path d="M24 26 h0.01"/><path d="M12.5 31 H35.5 L31.5 36 H16.5 Z"/><path d="M4.5 41.5 Q8.4 38.5 12.3 41.5 T20.1 41.5 T27.9 41.5 T35.7 41.5 T43.5 41.5"/>',
    'regatta-small': '<path d="M18.9 36.3 L18.9 15.3 Q12.3 23.1 8.1 30.3 L17.1 30.3"/><path d="M21.9 18.3 Q28.5 24.3 31.5 30.3 L22.5 30.3"/><path d="M4.5 36.3 L39.3 36.3 Q35.7 43.5 14.1 43.5 Q8.1 42.9 5.46 39.9"/><path d="M35.3 8.04 L34.7 4.64"/><path d="M39.2 8.69 L41.99 5.8"/><path d="M40.02 12.28 L43.46 12.52"/><path d="M38.74 16.39 L39.35 17.36"/><path d="M34.28 16.27 L33.2 18.93"/><path d="M31.03 10.57 L28.81 9.94"/>',
    'navigator': '<path d="M28.97 9.24 A17 17 0 1 1 19.03 9.24"/><path d="M24 8.5 L27.2 26 L24 39 L20.8 26 Z"/><path d="M8.5 25.5 H12"/><path d="M36 25.5 H39.5"/>',
    'plumb': '<path d="M24 4.5 V26"/><circle cx="24" cy="9" r="1.8"/><circle cx="24" cy="16.5" r="1.8"/><circle cx="24" cy="24" r="1.8"/><path d="M14.5 30.5 Q24 25 33.5 30.5 L24.7 43 Q24 43.8 23.3 43 Z"/>',
    'lighthouse': '<path d="M13.5 43.5 L16.5 19.5"/><path d="M26.5 43.5 L23.5 19.5"/><path d="M10 43.5 H30"/><path d="M15.5 19.5 H24.5"/><path d="M17 19.5 V13.5 H23 V19.5"/><path d="M15.5 13.5 L20 8.5 L24.5 13.5"/><path d="M27.95 12.27 L35.89 8.05"/><path d="M29.5 16.5 L40.5 16.5"/><path d="M27.95 20.73 L35.01 24.48"/>'
  };
  function icon(name, size) {
    var s = size || 20;
    return '<svg class="ic" viewBox="0 0 48 48" width="' + s + '" height="' + s + '" fill="none" stroke="currentColor" stroke-width="3" ' +
      'stroke-linecap="round" stroke-linejoin="round"><title>' + name + '</title>' + (ICONS[name] || '') + '</svg>';
  }
  function art(name) { var A = window.ART, a = [].slice.call(arguments, 1); return A && A[name] ? A[name].apply(A, a) : ''; }

  /* ── words and numbers ── */
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function plural(n, w, ws) { return n + ' ' + (n === 1 ? w : (ws || w + 's')); }
  function N(key, v) { return '<span class="n" data-key="' + key + '">' + v + '</span>'; }   // a count that ticks (fx.js)
  function ts(t) { if (t == null || t === '') return null; if (typeof t === 'number') return t * 1000; var d = Date.parse(t); return isNaN(d) ? null : d; }
  function hhmm(t) { var d = new Date(t); return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2); }
  function ago(t) { var m = ts(t); if (m == null) return ''; var s = Math.max(0, (Date.now() - m) / 1000); return s < 5400 ? Math.round(s / 60) + 'm' : s < 172800 ? Math.round(s / 3600) + 'h' : Math.round(s / 86400) + 'd'; }
  function when(t) { var m = ts(t); return m == null ? '—' : new Date(m).toLocaleString([], { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }); }
  function money(x) {   // effective only: the list price × the week's ratio; with no ratio, the list price said as such
    if (x == null || isNaN(+x)) return '';
    var r = (S.header || {}).ratio, v = Math.abs(r ? +x * r : +x), sign = (r ? +x * r : +x) < 0 ? '-' : '', f, d = 1;
    if (Math.round(v) >= 10) f = Math.round(v).toLocaleString('en-US');
    else if (+v.toFixed(2) >= 0.1 || v === 0) f = v.toFixed(2);
    else { while (Math.round(v * Math.pow(10, d) * 10) / 10 < 10 && d < 8) d++; f = v.toFixed(d); }   // the core's usd(): no exponent
    return sign + '$' + f + (r ? 'e' : ' list');
  }
  B.money = money;
  function spend(cost, togo) { return money(cost || 0) + (togo ? '/' + money((+cost || 0) + (+togo)) : ''); }   // spent/total, the owner's form

  /* ── the state, read the same way by every view ── */
  function cols() { return S.columns || []; }
  function col(name) { for (var i = 0; i < cols().length; i++) if (cols()[i].name === name) return cols()[i].cards || []; return []; }
  function owner() { return (cols()[0] || {}).cards || []; }
  function byKey() { var o = {}; owner().forEach(function (c) { if (c.key) o[c.key] = c; }); return o; }
  function queue() { return S.queue || { docs: [], groups: [] }; }
  function groupKeys(name) { var g = (queue().groups || []).filter(function (x) { return x[0] === name; })[0]; return g ? g[1] : []; }
  function ships() { return S.timeline || []; }
  function shipDone(r) { var b = r.bars || [], d = b.filter(function (x) { return /^(done|landed|launched)$/.test(x.status); }).length, run = b.filter(function (x) { return x.status === 'running'; }).length; return b.length ? (d + run * 0.5) / b.length : 0; }
  function tally() {
    var h = S.header || {}, unstick = groupKeys('unstick').length, land = groupKeys('land').length;
    var late = ships().filter(function (r) { return (r.bars || []).some(function (b) { return b.overrun; }); }).length;
    return { owed: h.needs_owner || 0, docs: (queue().docs || []).length, land: land, unstick: unstick, people: groupKeys('people').length,
             memo: groupKeys('memo').length, later: (S.later || []).length, blocked: col('Blocked').length, running: col('Running').length,
             parked: col('Parked / Relayed').length, done: col('Done today').length, intake: col('Intake').length, late: late, stalled: h.stalled == null ? null : h.stalled,
             needs: E() ? E().needs.length : null };
  }

  /* ── the sky strip: the mark, the fleet sailing toward the finish, the time and the week ── */
  var CROWD = 12;   // past this many sailing ships, a boat stands for every ship within a tenth of the course (a night of 40 was one blur)
  var seaW = 0;   // the sea's width at the last placing: sea() draws each boat where placeBoats() would put it
  function sea() {
    var all = ships().map(function (r) { return { r: r, p: shipDone(r) }; }), sail = all.filter(function (b) { return b.p < 1; }), home = all.filter(function (b) { return b.p >= 1; });
    var boats = sail.length > CROWD ? buckets(sail) : sail.map(function (b) { return { p: b.p, n: 1, names: [b.r.plan || b.r.id] }; });
    if (home.length) boats.push({ p: 1, n: home.length, names: home.map(function (b) { return b.r.plan || b.r.id; }) });
    boats.sort(function (a, b) { return a.p - b.p; });
    var at = layout(seaW, boats.filter(function (b) { return b.p < 1; }).map(function (b) { return b.p; })), j = 0;
    return art('waves').replace('<svg ', '<svg data-k="waves" ') + '<div class="finish" data-k="finish" style="left:92%"><i></i></div>' + boats.map(function (b, i) {
      var shipped = b.p >= 1, what = b.n > 1 ? plural(b.n, 'ship') + ': ' + b.names.slice(0, 6).join(', ') + (b.n > 6 ? ' and ' + (b.n - 6) + ' more' : '') : b.names[0];
      var pos = shipped ? { left: 'calc(92% + 16px)', top: 13, size: 22 } : at[j++];
      return '<a class="boat' + (shipped ? ' shipped' : '') + '" data-k="boat-' + (shipped ? 'home' : i) + '" href="?view=ships" data-view="ships" data-p="' + b.p.toFixed(3) + '" style="' + boatStyle(i, pos) + '" title="' + esc(what) + (shipped ? ' · every step done' : ' · ' + Math.round(b.p * 100) + ' % of the steps done') + '">' + art('sloop', pos.size) +
        (b.n > 1 ? '<b class="bn">' + b.n + '</b>' : '') + '</a>';
    }).join('');
  }
  function boatStyle(i, pos) { return '--bobt:' + (3.2 + (i * 7) % 5 * 0.35).toFixed(2) + 's;--bobd:-' + ((i * 1.3) % 3).toFixed(2) + 's;left:' + pos.left + ';top:' + pos.top + 'px'; }
  function layout(W, ps) {   // each sailing boat at its share, spaced so none hides another, never past the finish
    var size = !W || W >= 260 ? 22 : W < 200 ? 13 : 16, top = size < 20 ? 15 : 13;
    if (!W) return ps.map(function (p) { return { left: (3 + p * 80).toFixed(2) + '%', top: top, size: size }; });
    var gap = Math.min(size + 12, W * 0.86 / Math.max(1, ps.length)), last = -999, xs = [], x0 = size / 2 + 2;
    ps.forEach(function (p) { var px = Math.max(x0, W * (0.03 + p * 0.8)); if (px - last < gap) px = last + gap; last = px; xs.push(px); });
    var lim = W * 0.88, mx = Math.max.apply(null, xs.concat([0]));
    if (mx > lim) xs = xs.map(function (x) { return x0 + (x - x0) * (lim - x0) / (mx - x0); });
    return xs.map(function (x) { return { left: (x / W * 100).toFixed(2) + '%', top: top, size: size }; });
  }
  function buckets(list) {   // one boat per tenth of the course, at its ships' mean share
    var o = {};
    list.forEach(function (b) { var k = Math.min(9, Math.floor(b.p * 10)); (o[k] = o[k] || []).push(b); });
    return Object.keys(o).map(function (k) { var g = o[k]; return { p: g.reduce(function (a, b) { return a + b.p; }, 0) / g.length, n: g.length, names: g.map(function (b) { return b.r.plan || b.r.id; }) }; });
  }
  function placeBoats() {   // the sea's width read: when it moved, the strip is drawn again at it (the first draw, a resize)
    var el = $('#strip .sea'); if (!el) return;
    var W = el.clientWidth; if (!W || W === seaW) return;
    seaW = W; reconcile($('#strip'), strip());
  }
  function weekPct() { var m = String((S.header || {}).week || '').match(/(\d+(?:\.\d+)?)\s*%/); return m ? m[1] + ' %' : ''; }
  function strip() {
    var h = S.header || {}, at = ts(S.as_of), wk = weekPct(), today = h.today_cost ? money(h.today_cost) : '';
    var long = 'as of <b>' + (at ? hhmm(at) : '—') + '</b>' + (S.host ? ' · ' + esc(S.host) : '') + (wk ? ' · week <b>' + wk + '</b>' : '') + (today ? ' · today <b>' + today + '</b>' : '');
    return '<div class="strip-in" data-k="strip-in"><button type="button" class="sbtn contents-btn" data-act="contents" title="Views and what each needs">' + listIcon() + '</button>' +
      '<a class="mark" href="?view=decide" data-view="decide">' + icon('helm', 22) + 'helm</a><div class="sea' + (seaW && seaW < 260 ? ' narrow' : '') + '" data-k="sea">' + sea() + '</div>' +
      '<span class="stat" data-k="stat" title="' + esc(h.week || '') + '"><span class="long">' + long + '</span><span class="short"><b>' + (at ? hhmm(at) : '—') + '</b>' + (wk ? ' · week <b>' + wk + '</b>' : '') + '</span></span>' +
      '<button type="button" class="sbtn" data-act="theme" title="Light or dark  T">' + themeIcon() + '</button><button type="button" class="sbtn" data-act="help" title="Keys  ?"><span class="kc">?</span></button></div>';
  }
  function listIcon() { return '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><path d="M3 4.5h12M3 9h12M3 13.5h8"/></svg>'; }
  function searchIcon() { return '<svg width="15" height="15" viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><circle cx="6" cy="6" r="4.2"/><path d="M9.2 9.2L12.5 12.5"/></svg>'; }
  function themeIcon() {
    return document.documentElement.dataset.theme === 'dark' ? '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><circle cx="9" cy="9" r="3.4"/><path d="M9 1.8v1.6M9 14.6v1.6M1.8 9h1.6M14.6 9h1.6M3.9 3.9l1.1 1.1M13 13l1.1 1.1M3.9 14.1L5 13M13 5l1.1-1.1"/></svg>' :
      '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"><path d="M14.5 11.2A6 6 0 0 1 6.8 3.5a6 6 0 1 0 7.7 7.7z"/></svg>';
  }

  /* ── the views, with what each needs: the side column at ≥ 1100 px, the tab bar below ── */
  function badge(v, c) {   // a count is graphite unless it is an alarm or a late ship; Decide's keeps the flag
    return v === 'decide' ? ['flag', c.owed, c.owed + ' need you'] : v === 'fleet' ? ['bad', c.blocked, c.blocked + ' blocked'] :
      v === 'ships' ? ['bad', c.late, c.late + ' past an ETA'] : v === 'reports' ? ['', c.done, c.done + ' done today'] :
      v === 'engine' ? (c.needs == null ? ['bad', c.intake, c.intake + ' in Intake'] : ['bad', c.needs, c.needs + ' need a hand in the Engine room']) : ['', 0, ''];
  }
  function viewLink(v, cls, c) {
    var b = badge(v[0], c);
    return '<a class="' + cls + (V.view === v[0] ? ' on' : '') + '" data-view="' + v[0] + '" href="?view=' + v[0] + '" title="' + esc(v[2] + (b[2] ? ' · ' + b[2] : '')) + '">' + icon(v[1], 20) +
      '<span class="vl">' + v[2] + '</span>' + (b[1] ? '<b class="vb ' + b[0] + '">' + N('vb-' + cls + '-' + v[0], b[1]) + '</b>' : '') + '</a>';
  }
  function viewLinks(cls) { var c = tally(); return VIEWS.map(function (v) { return viewLink(v, cls, c); }).join(''); }
  function tabbar() { return '<div class="in">' + viewLinks('tab') + '</div>'; }
  function sideHTML() {
    return '<div class="side-in"><label class="find">' + searchIcon() + '<input class="findin" data-k="find" placeholder="Find a doc, ship or run" autocomplete="off"><span class="kc">/</span></label>' +
      '<nav class="views" data-k="views">' + viewLinks('vw') + '<span class="vsep"></span>' + viewLink(ENGINE, 'vw engine', tally()) + '</nav><div class="ctx" data-k="ctx">' + ctxHTML() + '</div></div>';
  }
  function ctxHTML() { return V.view === 'decide' ? docsList() : watchList(); }
  function docsList() {
    var c = tally(), h = '<div class="ctx-h"><span class="lbl">Tonight</span><span class="ctx-s"><b>' + N('side-owed', c.owed) + '</b> for you in ' + plural(c.docs, 'doc') + '</span></div><ul class="docs">';
    (queue().docs || []).forEach(function (d, i) {
      h += '<li data-k="sd-' + esc(d.key) + '"><a href="#doc-' + i + '" data-jump="doc-' + i + '" data-find><span class="no">' + ('0' + (i + 1)).slice(-2) + '</span><span class="nm">' + art('pennant', 11) + esc(d.title) +
        '</span><span class="dm"><b>' + (d.open || 0) + '</b> for you' + (d.rank === 0 ? ' · <span class="t-wait">a step waits</span>' : d.rank === 1 ? ' · <span class="t-irr">irreversible</span>' : '') + '</span></a></li>';
    });
    h += '</ul><div class="ctx-g">Also for you</div><ul class="also">' + [['land', 'ok', 'To land', c.land], ['unstick', 'bad', 'Stuck and waiting', c.unstick], ['people', 'park', 'People', c.people], ['later', 'park', 'Later', c.later]].map(function (x) {
      return x[3] ? '<li data-k="also-' + x[0] + '"><a href="#g-' + x[0] + '" data-jump="g-' + x[0] + '"><i class="sd ' + x[1] + '"></i><span class="nm">' + x[2] + '</span><b class="cnt">' + x[3] + '</b></a></li>' : '';
    }).join('') + '</ul>';
    return h;
  }
  function watchList() {
    var c = tally(), at = ts(S.as_of);
    var rows = [['flag', plural(c.owed, 'card') + ' need you', 'decide'], ['run', c.running + ' running', 'fleet'], ['bad', c.blocked + ' blocked', 'fleet'],
      ['bad', c.stalled == null ? 'stalls unknown: the judge did not read' : plural(c.stalled, 'stall'), 'decide'], ['bad', c.late + ' ships past an ETA', 'ships'], ['ok', c.done + ' done today', 'reports']].concat(engineWatch(c));
    return '<div class="ctx-h"><span class="lbl">On watch</span><span class="ctx-s">as of ' + (at ? hhmm(at) : '—') + (S.host ? ' on ' + esc(S.host) : '') + '</span></div><ul class="watch">' + rows.map(function (r) {
      return '<li data-k="w-' + r[2] + '-' + (r[3] || r[0]) + '"><a href="?view=' + r[2] + '" data-view="' + r[2] + '"><i class="sd ' + r[0] + '"></i><span>' + r[1] + '</span></a></li>';
    }).join('') + '</ul>';
  }

  function engineWatch(c) {
    var e = E();
    if (!e) return [['wait', c.intake + ' in Intake', 'engine']];
    var intake = [e.alarms ? 'bad' : 'wait', e.unread.intake ? 'Intake unread' : (e.intake.length + (e.intakeGuarded || 0)) + ' in Intake' + (e.alarms ? ', ' + plural(e.alarms, 'alarm') : ''), 'engine', 'intake'];
    if (e.unread.hosts) return [['wait', 'the hosts unread', 'engine', 'queue'], intake];
    var cant = e.queued.filter(function (x) { return x.tone === 'bad'; }).length;
    return [['wait', e.queueUnknown ? 'the queue unread' : e.queued.length + ' queued · ' + cant + ' cannot start', 'engine', 'queue'], intake];
  }

  /* ── each view's head: an eyebrow, one sentence, the counts that matter in their colours; the page's notes ── */
  function notes() {
    var h = S.header || {}, n = [];
    if (h.sheep) n.push(['wait', h.sheep]);
    if (h.talk) n.push(['wait', h.talk]);
    if (h.stalls_note) n.push(['wait', h.stalls_note]);
    if (h.stalls_old) n.push(['park', h.stalls_old + ' stalls over ' + (h.stall_days || 7) + 'd (oldest ' + ago(h.stalls_oldest) + ')']);
    if (h.wip_idle) n.push(['park', plural(h.wip_idle, 'WIP PR') + ' idle']);
    return n.length ? '<ul class="hnotes" data-k="notes">' + n.map(function (x, i) { return '<li data-k="note-' + i + '"><span class="st ' + x[0] + '">' + esc(x[1]) + '</span></li>'; }).join('') + '</ul>' : '';
  }
  function head() {
    var c = tally(), h = S.header || {}, at = ts(S.as_of), e = '', h1 = '', sub = '', d = at ? new Date(at) : new Date();
    var day = d.toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' });
    if (V.view === 'decide') {
      e = 'Decide · ' + day;
      h1 = c.owed ? N('h1-owed', c.owed) + (c.owed === 1 ? ' card needs you.' : ' cards need you.') : 'Nothing needs you.';
      sub = plural(c.docs, 'doc') + ' with decisions; <b>' + c.land + ' to land</b>, <span class="t-bad">' + c.unstick + ' stuck or waiting</span>, ' + c.people + ' for people' + (c.later ? ', ' + c.later + ' put off' : '') + '.';
    } else if (V.view === 'fleet') {
      e = 'Fleet · as of ' + (at ? hhmm(at) : '—');
      h1 = plural(c.running, 'run') + ' at work across ' + plural(ships().length, 'ship') + '; ' + c.done + ' done today.';
      sub = '<b>' + c.owed + ' need you</b>, <span class="t-bad">' + c.blocked + ' blocked</span>, ' + c.parked + ' parked or relayed. Hosts, the queue, logins, CI and Intake live in the Engine room.';
    } else if (V.view === 'ships') {
      var spent = 0, togo = 0; ships().forEach(function (r) { spent += (r.totals || {}).cost || 0; togo += (r.totals || {}).est_to_go || 0; });
      e = 'Ships · the ladder of ETAs';
      h1 = plural(ships().length, 'ship') + (c.late ? ' · ' + c.late + ' past an ETA.' : ' · all on their ETAs.');
      sub = spend(spent, togo) + ' spent of the estimates\' total. ETAs are guesses; a bar past its ETA turns amber.';
    } else if (V.view === 'skippers') {
      e = 'Skippers · read, hail, answer'; h1 = 'Every skipper on watch.'; sub = 'Each skipper\'s watch card, its open asks and its hail come in a later build.';
    } else if (V.view === 'reports') {
      e = 'Reports · Completed'; h1 = plural(c.done, 'card') + ' done today.'; sub = 'Today\'s spend ' + (money(h.today_cost || 0)) + '. The day-by-day reports come in a later build.';
    } else if (EV()) {
      var eh = EV().head(); e = eh.e; h1 = eh.h1; sub = eh.sub;
    } else {
      e = 'Engine room'; h1 = 'Hosts, the queue, logins, CI, budgets and Intake.';
      sub = 'Its document did not load on this page. <a href="?view=fleet" data-view="fleet">← Fleet</a>';
    }
    return '<header class="vh" data-k="vh">' + notes() + '<div class="eyebrow"><span class="lbl">' + e + '</span></div><h1>' + h1 + '</h1><p class="vsub">' + sub + '</p></header>';
  }

  /* ── cards: one row each, the title on its own line and its facts under it ── */
  var KIND = { ask: ['flag', 'ask'], memo: ['run', 'memo'], lookout: ['run', 'comment'], pr: ['ok', 'PR'], held: ['held', 'held'], stall: ['bad', 'stall'], road: ['bad', 'refused'],
    waiting: ['wait', 'waiting'], permission: ['wait', 'permission'], task: ['run', 'task'], human: ['park', 'a person'], done: ['ok', 'done'], intake: ['bad', 'intake'],
    'main-red': ['bad', 'main red'] };
  function card(c) {
    var k = KIND[c.kind] || ['park', c.label || c.kind || 'card'], t2 = [];
    if (c.plan) t2.push('<span>' + esc(c.plan) + '</span>');
    if (c.repo) t2.push('<span class="mono">' + esc(c.repo) + '</span>');
    if (c.by || c.owner) t2.push('<span>' + esc(c.by || c.owner) + '</span>');
    if (c.reversible) t2.push('<span class="' + (c.reversible === 'no' ? 't-irr' : '') + '">Reversible: ' + esc(c.reversible) + '</span>');
    if (c.recommended) t2.push('<span>Recommended: ' + esc(c.recommended) + '</span>');
    if (c.eta) t2.push('<span class="' + (c.overrun ? 't-wait' : '') + '">ETA ' + when(c.eta) + '</span>');
    if (c.cost != null) t2.push('<span class="mono">' + spend(c.cost, c.est) + '</span>');
    if (c.blockers && c.blockers.length) t2.push('<span class="t-bad">blocked: ' + esc(c.blockers.join('; ')) + '</span>');
    if (c.parked && c.parked.length) t2.push('<span>parked: ' + esc(c.parked.join(', ')) + '</span>');
    if (c.open) t2.push('<span>' + esc(c.open) + ' open</span>');
    ['ref', 'keel', 'review', 'evidence', 'held', 'rule'].forEach(function (f) { if (c[f]) t2.push('<span class="dim">' + esc(c[f]) + (f === 'rule' && c.action ? ' → ' + esc(c.action) : '') + '</span>'); });
    if (c.updated) t2.push('<span>' + ago(c.updated) + ' ago</span>');
    var links = [['course', 'Course ↗'], ['github', 'GitHub ↗'], ['url', 'Open ↗']].filter(function (x) { return c[x[0]]; }).map(function (x) {
      return '<a class="btn sm ghost" href="' + esc(c[x[0]]) + '" target="_blank" rel="noopener">' + x[1] + '</a>';
    }).join('');
    return '<div class="card" data-k="' + esc(c.key || card_id(c)) + '" data-find><span class="st ' + k[0] + '">' + esc(k[1]) + '</span><div class="tt"><div class="t1">' + esc(c.title) + '</div><div class="t2">' + t2.join('') + '</div></div><div class="verbs">' + links + '</div></div>';
  }
  function card_id(c) { return [c.kind, c.repo, c.ref || c.url || c.session || c.title].join('|'); }
  function cards(list, empty) { return '<div class="cards">' + (list.length ? list.map(card).join('') : '<div class="card empty">' + art('quietNight', 34) + '<span>' + (empty || 'Nothing here.') + '</span></div>') + '</div>'; }
  function grp(id, title, why, list, tone, empty) {
    return '<section class="grp" id="g-' + id + '" data-k="g-' + id + '"><div class="gh"><h2 class="lbl' + (tone ? ' ' + tone : '') + '">' + title + ' <b>' + N('g-' + id, list.length) + '</b></h2>' + (why ? '<span class="why">' + why + '</span>' : '') + '</div>' + cards(list, empty) + '</section>';
  }

  /* ── what each view holds until its own step builds it ── */
  function decideHTML() {
    var K = byKey(), h = '<div class="feed" data-k="feed">', docs = queue().docs || [];
    var names = { memo: ['Memos', 'read first'], land: ['To land', 'ready pull requests and held ones'], unstick: ['Stuck and waiting', 'runs that stopped, sessions that wait on you'],
      people: ['People', 'a person\'s line in a TODO'], tasks: ['Ship tasks', 'a plan\'s step that waits on you'], other: ['Other', ''] };
    if (docs.length) {
      h += '<section class="grp" id="g-docs" data-k="g-docs"><div class="gh"><h2 class="lbl">Decisions <b>' + N('g-docs', docs.length) + '</b></h2><span class="why">docs a step waits on, then irreversible ones, then oldest first</span></div>';
      docs.forEach(function (d, i) {
        var links = (d.course ? '<a class="btn sm ghost" href="' + esc(d.course) + '" target="_blank" rel="noopener">Course ↗</a>' : '') + (d.github ? '<a class="btn sm ghost" href="' + esc(d.github) + '" target="_blank" rel="noopener">GitHub ↗</a>' : '');
        h += '<article class="doc" id="doc-' + i + '" data-k="doc-' + esc(d.key) + '"><div class="doc-h"><span class="doc-no">' + ('0' + (i + 1)).slice(-2) + '</span><div><h3 class="doc-t" data-find>' + esc(d.title) + '</h3><div class="doc-meta"><span class="mono">' + esc(d.repo || '') + '</span><span><b>' + (d.open || 0) + '</b> for you</span><span class="' + (d.rank === 0 ? 't-wait' : d.rank === 1 ? 't-irr' : '') + '">' + esc(d.why || '') + '</span>' + (d.oldest ? '<span>' + ago(d.oldest) + ' old</span>' : '') + '</div></div><div class="doc-r">' + links + '</div></div>' +
          '<div class="qs">' + cards((d.items || []).map(function (k) { return K[k]; }).filter(Boolean)) + '</div></article>';
      });
      h += '</section>';
    }
    (queue().groups || []).forEach(function (g) { var n = names[g[0]] || [esc(g[0]), '']; h += grp(esc(g[0]), n[0], n[1], g[1].map(function (k) { return K[k]; }).filter(Boolean), g[0] === 'unstick' ? 'bad' : ''); });
    var later = (S.later || []).map(function (r) { return { key: 'later-' + r.key, kind: 'later', label: r.kind === 'done' ? 'done' : 'later', title: r.title, updated: r.at }; });
    if (later.length) h += grp('later', 'Later', 'snoozed or marked done; back when the card changes', later, '');
    if (!docs.length && !(queue().groups || []).length) h += '<div class="empty-big">' + art('finishLine', 120) + '<p>Nothing is owed. Every decision is taken.</p></div>';
    return h + '</div>';
  }
  function fleetHTML() {
    var h = engineLine(), people = cols()[1];
    if (people && people.cards.length) h += grp('people-col', esc(people.name), 'the people the owner works with', people.cards, '');
    [['Blocked', 'bad', 'a step that cannot go on'], ['Running', '', 'runs at work now'], ['Parked / Relayed', '', 'parked by a skipper, or relayed to one'], ['Done today', '', 'what ended since the morning']].forEach(function (x, i) {
      h += grp('c' + i, x[0], x[2], col(x[0]), x[1]);
    });
    return h;
  }
  var FILL = { running: 'var(--run)', relayed: 'var(--park)', parked: 'var(--park)', waiting: 'var(--wait)', blocked: 'var(--bad)', failed: 'var(--bad)', done: 'var(--ok)', landed: 'var(--ok)', launched: 'var(--ok)', planned: 'var(--rule-strong)' };
  function engineLine() {   // Fleet's one line pointing at the Engine room, with its counts and its freshness (the owner, 2026-11-02)
    var e = E();
    if (!e) return '<p class="engine-line" data-k="eline">Hosts, the queue, logins, CI, budgets and Intake → <a href="?view=engine" data-view="engine">Engine room</a></p>';
    var span = function (k, t) { return '<span data-k="el-' + k + '">' + t + '</span>'; }, x = [];
    if (e.unread.hosts) x.push(span('runs', '<span class="t-wait">hosts ' + (e.sources.hosts.off ? 'off here' : 'unread') + '</span>'));
    else {
      var cant = e.queued.filter(function (q) { return q.tone === 'bad'; }).length, awake = e.hosts.filter(function (h) { return h.state === 'awake'; }).length;
      x.push(span('runs', (e.ops.runsUnknown ? '<span class="t-wait">runs unread</span>' : (e.ops.runsPartial ? 'at least ' : '') + e.ops.runs[0] + ' runs') + ' on ' + plural(awake, 'host')), span('q', e.queueUnknown ? '<span class="t-wait">the queue unread</span>' : e.queued.length + ' queued' + (cant ? ', <span class="t-bad">' + cant + ' cannot start</span>' : '')));
    }
    x.push(span('al', e.unread.intake ? '<span class="t-wait">Intake unread</span>' : e.alarms ? '<span class="t-bad">' + plural(e.alarms, 'alarm') + '</span> in Intake' : 'no alarms'));
    x.push(span('ci', 'CI ' + (e.ops.ci == null ? (e.ciRead ? 'no week share' : '<span class="t-wait">' + (e.sources.ci.off ? 'off here' : 'unread') + '</span>') : '<span class="' + (e.ops.ci >= 80 ? 't-bad' : '') + '">' + e.ops.ci + ' %</span>')));
    x.push(span('at', '<span class="dim">as of ' + (e.at ? hhmm(e.at * 1000) : '—') + '</span>'));
    return '<p class="engine-line pointer" data-k="eline"><span class="lbl2" data-k="el-l">Engine room</span>' + x.join('') + '<a class="go" data-k="el-go" href="?view=engine" data-view="engine">Open the Engine room →</a></p>';
  }
  function shipsHTML() {   // the timeline as it was (milestones, ask flags, the parked hatch), in the tokens' colours, until S12's ladder
    var rows = ships(); if (!rows.length) return '<div class="empty-big" data-k="noships">' + art('quietNight', 120) + '<p>No ships with tasks.</p></div>';
    var now = (ts(S.as_of) || Date.now()) / 1000, lo = now, hi = now;
    rows.forEach(function (r) { (r.bars || []).forEach(function (b) { lo = Math.min(lo, b.start || now); hi = Math.max(hi, b.end || now); }); (r.milestones || []).forEach(function (m) { hi = Math.max(hi, m.on); }); });
    hi = Math.max(hi, lo + 3600);
    var W = Math.max(640, Math.min(1400, ($('#main') || document.body).clientWidth || 900)), L = 170, R = 110, rowH = 24, y = 24, x = function (t) { return L + (W - L - R) * (t - lo) / (hi - lo); }, p = [], pos = {};
    rows.forEach(function (r) {
      p.push('<text x="4" y="' + (y + 14) + '" class="tl-ship">' + esc(r.plan) + '</text><text x="' + (W - R + 8) + '" y="' + (y + 14) + '" class="tl-m">' + spend((r.totals || {}).cost, (r.totals || {}).est_to_go) + ((r.totals || {}).open_asks ? ' · ' + r.totals.open_asks + '?' : '') + '</text>'); y += rowH;
      (r.milestones || []).forEach(function (m) { var mx = x(m.on).toFixed(1);
        p.push('<path d="M' + mx + ' ' + (y - 16) + ' l6 6 l-6 6 l-6 -6z" fill="var(--ink-2)"><title>' + esc(m.name) + '</title></path><text x="' + (+mx + 8) + '" y="' + (y - 6) + '" class="tl-m">' + esc(m.name) + ' (' + esc(m.open) + ')</text>'); });
      (r.bars || []).forEach(function (b) {
        var x0 = b.status === 'blocked' || (b.blockers && b.blockers.length && b.status === 'planned') ? x(now) : x(b.start || now), x1 = Math.max(x0 + 4, x(b.end || now)), f = FILL[b.status] || 'var(--rule-strong)', hollow = b.kind === 'human' || b.status === 'blocked';
        pos[r.id + '/' + b.id] = { x0: x0, x1: x1, y: y + 8 };
        p.push('<text x="14" y="' + (y + 13) + '" class="tl-t">' + esc(String(b.title || '').slice(0, 24)) + '</text><rect x="' + x0.toFixed(1) + '" y="' + (y + 2) + '" width="' + (x1 - x0).toFixed(1) + '" height="14" rx="4" fill="' + (hollow ? 'none' : f) + '" stroke="' + (b.overrun ? 'var(--wait)' : f) + '" stroke-width="' + (b.overrun ? 2 : 1) + '"><title>' + esc(b.title + ' — ' + b.status + (b.blockers && b.blockers.length ? ' — ' + b.blockers.join('; ') : '')) + '</title></rect>');
        if (b.parked_at) { var px = Math.max(x0, x(b.parked_at)); p.push('<rect x="' + px.toFixed(1) + '" y="' + (y + 2) + '" width="' + Math.max(2, x1 - px).toFixed(1) + '" height="14" fill="url(#tl-hatch)"/>'); }
        if (b.cost != null) p.push('<text x="' + (x1 + 5).toFixed(1) + '" y="' + (y + 13) + '" class="tl-m">' + spend(b.cost, b.est) + '</text>');
        (b.flags || []).forEach(function (fl, k) { p.push('<text x="' + (x0 + 4 + k * 24).toFixed(1) + '" y="' + y + '" class="tl-now">⚑' + esc(fl) + '</text>'); });
        y += rowH;
      });
      (r.bars || []).forEach(function (b) { (b.deps || []).forEach(function (d) { var a = pos[r.id + '/' + d], c = pos[r.id + '/' + b.id]; if (!a || !c) return;
        p.push('<path d="M' + a.x1.toFixed(1) + ' ' + a.y + ' C' + (a.x1 + 20).toFixed(1) + ' ' + a.y + ' ' + (c.x0 - 20).toFixed(1) + ' ' + c.y + ' ' + c.x0.toFixed(1) + ' ' + c.y + '" fill="none" stroke="' + (c.x0 < a.x1 - 1 ? 'var(--bad)' : 'var(--rule-strong)') + '"/>'); }); });
      y += 10;
    });
    var nx = x(now); p.push('<line x1="' + nx.toFixed(1) + '" y1="8" x2="' + nx.toFixed(1) + '" y2="' + y + '" stroke="var(--flag)" stroke-dasharray="3 3"/><text x="' + (nx + 4).toFixed(1) + '" y="12" class="tl-now">now</text>');
    return '<div class="tl" data-k="tl-' + rows.length + '-' + W + '"><svg width="' + W + '" height="' + (y + 10) + '" viewBox="0 0 ' + W + ' ' + (y + 10) + '" role="img"><title>the ships\' steps on one time axis</title><defs><pattern id="tl-hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="6" stroke="var(--park)" stroke-width="2"/></pattern></defs>' + p.join('') + '</svg></div>';
  }
  function skippersHTML() { return '<div class="empty-big" data-k="nosk">' + art('noSkippers', 120) + '<p>Not built yet: each skipper\'s watch card.</p></div>'; }
  function reportsHTML() { return grp('done', 'Done today', 'every card that ended since the morning', col('Done today'), '', 'Nothing ended yet today.'); }
  function engineHTML() {   // the Engine room's body (engine.js); without its files, the board's ops line and Intake cards as before
    if (EV()) return EV().html();
    var h = S.header || {};
    return (h.ops ? '<p class="ops' + (h.ops_stale ? ' t-wait' : '') + '" data-k="ops">' + esc(h.ops) + '</p>' : '') + grp('intake', 'Intake', 'the desk\'s open issues, by kind', col('Intake'), 'bad', 'Intake is empty.');
  }
  function mainHTML() {   // one body per view, the others drawn empty and hidden: a draft left in another view stays there,
    var v = V.view;       // hidden, and never under this one (a switch once kept the Decide feed under Fleet: S3's round-1 review)
    return head() + NAMES.map(function (n) {
      return n !== v ? '<div class="vbody" data-k="body-' + n + '" hidden></div>' : '<div class="vbody" data-k="body-' + n + '">' +
        (v === 'decide' ? decideHTML() : v === 'fleet' ? fleetHTML() : v === 'ships' ? shipsHTML() : v === 'skippers' ? skippersHTML() : v === 'reports' ? reportsHTML() : engineHTML()) + '</div>';
    }).join('');
  }

  /* ── the reconcile: a region's new HTML patched into the old by key, never over a focus or a draft. A keyed node, or one
     holding the focus, is patched in place (its animations, its focus and its scroll go on); a node that left stays only
     while it holds a draft (round 2: the strip's waves restarted every poll, and a focused button lost its focus) ── */
  function frag(html) { var t = document.createElement('template'); t.innerHTML = html; return t.content; }
  function keyOf(n) { return n.nodeType === 1 ? n.getAttribute('data-k') : null; }
  // a field the owner types into or picks in; a focused link or button holds nothing (round 1: a focused "GitHub ↗"
  // kept a whole view, and a card twice when its key changed)
  var FIELDS = 'textarea, input, select, [contenteditable]';
  function isField(x) { return !!x && x.nodeType === 1 && x.matches(FIELDS) && !/^(button|submit|reset|image|hidden)$/.test(x.type || ''); }
  function changed(x) {   // a draft by the field's kind: the value, the tick, the choice, or what the page marked
    if (x.hasAttribute('data-draft')) return true;
    if (x.isContentEditable) return x.hasAttribute('data-orig') && x.textContent !== x.getAttribute('data-orig');
    if (x.tagName === 'SELECT') {   // an untouched select shows its first option, which no `selected` marks
      if (x.multiple) return [].some.call(x.options, function (o) { return o.selected !== o.defaultSelected; });
      var dflt = 0; [].some.call(x.options, function (o, i) { if (o.defaultSelected) { dflt = i; return true; } return false; });
      return x.options.length > 0 && x.selectedIndex !== dflt;
    }
    if (x.type === 'checkbox' || x.type === 'radio') return x.checked !== x.defaultChecked;
    if (x.type === 'range' || x.type === 'color') {   // their default value is a computed one: a fresh field of the same attributes says it
      var f = document.createElement('input'); ['type', 'min', 'max', 'step', 'value'].forEach(function (a) { if (x.hasAttribute(a)) f.setAttribute(a, x.getAttribute(a)); });
      return x.value !== f.value;
    }
    return x.value != null && x.defaultValue != null && x.value !== x.defaultValue;
  }
  function holds(n) {
    if (n.nodeType !== 1) return false;
    var a = document.activeElement;
    if (isField(a) && n.contains(a)) return true;
    var f = [].slice.call(n.querySelectorAll(FIELDS));
    if (n.matches(FIELDS)) f.push(n);
    return f.some(function (x) { return isField(x) && changed(x); });
  }
  function attrs(m, n) {
    [].slice.call(m.attributes).forEach(function (a) { if (!n.hasAttribute(a.name) && a.name !== 'value') m.removeAttribute(a.name); });
    [].slice.call(n.attributes).forEach(function (a) { if (a.name !== 'value' && m.getAttribute(a.name) !== a.value) m.setAttribute(a.name, a.value); });
  }
  function sync(cur, nxt) {
    var old = [].slice.call(cur.childNodes), keyed = {}, free = [], out = [];
    old.forEach(function (n) { var k = keyOf(n); if (k && !keyed[k]) keyed[k] = n; else free.push(n); });
    [].slice.call(nxt.childNodes).forEach(function (n) {
      var k = keyOf(n), m = null;
      if (k) { m = keyed[k] || null; delete keyed[k]; }
      else for (var i = 0; i < free.length; i++) if (free[i] && free[i].nodeName === n.nodeName && !keyOf(free[i])) { m = free[i]; free[i] = null; break; }
      if (m && m.isEqualNode(n)) out.push(m);
      else if (m && m.nodeType === 1 && m.nodeName === n.nodeName && (k || m.contains(document.activeElement) || holds(m))) { attrs(m, n); sync(m, n); out.push(m); }
      else { if (m && k && holds(m)) out.push(m); out.push(n); }   // a keyed node that changed its tag keeps its draft beside the new one
    });
    // a node that holds the focus or a draft stays even when its card left the board
    Object.keys(keyed).forEach(function (k) { if (holds(keyed[k])) out.push(keyed[k]); });
    free.forEach(function (n) { if (n && holds(n)) out.push(n); });
    old.forEach(function (n) { if (out.indexOf(n) < 0) cur.removeChild(n); });
    out.forEach(function (n, i) { var at = cur.childNodes[i]; if (at !== n) cur.insertBefore(n, at || null); });
  }
  function reconcile(el, html) {
    if (!el) return;
    var a = document.activeElement, sel = null;
    try { sel = a && a.setSelectionRange ? [a.selectionStart, a.selectionEnd] : null; } catch (e) { sel = null; }
    sync(el, frag(html));
    if (a && a !== document.body && a !== document.activeElement && a.isConnected) {   // a move blurs: give it back
      a.focus({ preventScroll: true });
      if (sel) try { a.setSelectionRange(sel[0], sel[1]); } catch (e) { /* not a text field */ }
    }
  }
  B.reconcile = reconcile;

  /* ── the save strip: in the flow at the end of the column; sticky at the bottom only while something is unsaved.
     The draft store is this browser's (`helm-drafts`); Decide's picks fill it (S11), the board's writer drains it (S4). ── */
  // A Save keeps every answer's text: it records each doc's answers as saved ({at, sig, items}), as the prototype's
  // DC.save keeps what it saved and its sig, and the answers stay in `helm-drafts` until S4's writer confirms them in
  // their docs. A doc is unsaved while its answers' sig differs from the saved one: an edit, an added answer or a cleared
  // one after a Save (round 1: Save kept a time alone; round 2: a clear after a Save read as saved)
  function drafts() { try { return JSON.parse(get('drafts', '{}')) || {}; } catch (e) { return {}; } }
  function saved() { try { return JSON.parse(get('saved', '{}')) || {}; } catch (e) { return {}; } }
  function savedAt(sv, k) { var x = sv[k]; return x == null ? 0 : typeof x === 'number' ? x : +x.at || 0; }
  function sig(items) { return JSON.stringify(Object.keys(items || {}).sort().map(function (it) { return [it, items[it].text]; })); }
  function unsaved(d, sv) {   // {doc: [items]}: a doc whose answers are not the ones saved; an older mark without a sig judged by time
    var o = {};
    Object.keys(d).concat(Object.keys(sv).filter(function (k) { return !d[k] && sv[k] && sv[k].sig; })).forEach(function (k) {
      var x = sv[k], its = Object.keys(d[k] || {});
      if (x && x.sig != null) { if (x.sig !== sig(d[k])) o[k] = its.length ? its : Object.keys(x.items || {}); }
      else { var at = savedAt(sv, k); its = its.filter(function (it) { return (+d[k][it].at || 0) > at; }); if (its.length) o[k] = its; }
    });
    return o;
  }
  B.draft = function (doc, item, text) {
    var d = drafts(), sv = saved(); d[doc] = d[doc] || {};
    if (text == null || text === '') delete d[doc][item]; else d[doc][item] = { text: String(text), at: Date.now() };
    if (!Object.keys(d[doc]).length) { delete d[doc]; if (sv[doc] != null && !(sv[doc].sig && sv[doc].sig !== sig({}))) { delete sv[doc]; put('saved', JSON.stringify(sv)); } }
    put('drafts', JSON.stringify(d)); savebar();
  };
  B.drafts = drafts;
  B.saved = saved;
  function stamp(t) { var d = new Date(t), now = new Date(); return (d.toDateString() === now.toDateString() ? '' : d.toLocaleDateString([], { day: 'numeric', month: 'short' }) + ' ') + hhmm(t); }
  function savebar() {
    var el = $('#savebar'), d = drafts(), sv = saved(), u = unsaved(d, sv), ids = Object.keys(u), n = ids.reduce(function (a, k) { return a + u[k].length; }, 0);
    var kept = Object.keys(d).filter(function (k) { return savedAt(sv, k); }), last = Math.max.apply(null, [0].concat(kept.map(function (k) { return savedAt(sv, k); })));
    if (!el) return;
    if (V.view !== 'decide' || (!n && !kept.length)) { el.className = 'savebar'; el.innerHTML = ''; return; }
    var title = function (k) { var g = (queue().docs || []).filter(function (x) { return x.key === k; })[0]; return g ? g.title : k.split(':').pop(); };
    var held = kept.reduce(function (a, k) { return a + Object.keys(d[k]).length; }, 0);
    el.className = 'savebar on' + (n ? ' dirty' : '');
    reconcile(el, n ? '<span class="sb-n">' + plural(n, 'answer') + '<span class="lg"> in ' + plural(ids.length, 'doc') + '</span> · not saved</span><span class="sb-r">' + esc(ids.slice(0, 2).map(title).join(' · ')) + (ids.length > 2 ? ' and ' + (ids.length - 2) + ' more' : '') + '</span>' +
      '<span class="sp"></span><span class="sb-acts"><button type="button" class="btn" data-act="copy">Copy answers</button><button type="button" class="btn primary" data-act="save">Save <span class="k">⌘↩</span></button></span>' :
      '<span class="sb-n">Nothing unsaved</span><span class="sb-r">' + plural(held, 'answer') + ' saved in this browser at ' + stamp(last) + '; the board\'s writer takes them to their docs once it is built</span>' +
      '<span class="sp"></span><span class="sb-acts"><button type="button" class="btn" data-act="copy">Copy answers</button></span>');
  }
  function doSave() {
    var d = drafts(), sv = saved(), ids = Object.keys(unsaved(d, sv)), at = Date.now();
    if (!ids.length) { toast('Nothing unsaved'); return; }
    ids.forEach(function (k) {   // a doc whose every answer was cleared after its Save: saved as none
      var items = {}; Object.keys(d[k] || {}).forEach(function (it) { items[it] = d[k][it].text; });
      if (Object.keys(items).length) sv[k] = { at: at, sig: sig(d[k]), items: items }; else delete sv[k];
    });
    put('saved', JSON.stringify(sv));
    toast('Saved in this browser: ' + plural(ids.length, 'doc')); savebar();
    if (window.FX && FX.on) FX.on('save');
  }
  function doCopy() {
    var d = drafts(), lines = [];
    Object.keys(d).forEach(function (k) { Object.keys(d[k]).forEach(function (it) { lines.push(k + ' ' + it + ': ' + d[k][it].text); }); });
    var text = lines.join('\n'), ok = function () { toast('Copied ' + plural(lines.length, 'answer')); }, bad = function () { toast('Copy failed: the browser refused the clipboard'); };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(ok, bad); else bad();
  }
  var tt = null;
  function toast(m) { var t = $('#toast'); if (!t) return; t.textContent = m; t.classList.add('on'); clearTimeout(tt); tt = setTimeout(function () { t.classList.remove('on'); }, 2600); }

  /* ── the keys sheet ── */
  function help() {
    var kk = function (a, b) { return '<div><span>' + a + '</span><span>' + b + '</span></div>'; };
    $('#sheet').innerHTML = '<button type="button" class="iconbtn x" data-act="close" title="Close  esc">✕</button><h2>Keys</h2><p class="dim">None fire while you type.</p><div class="keys">' +
      kk('Find', '<span class="kc">/</span>') + kk('Go to a view', '<span class="kc">G</span> then <span class="kc">D</span> <span class="kc">F</span> <span class="kc">S</span> <span class="kc">K</span> <span class="kc">R</span> <span class="kc">E</span>') +
      kk('Light or dark', '<span class="kc">T</span>') + kk('Save every answered doc', '<span class="kc">⌘</span><span class="kc">⏎</span>') + kk('This sheet', '<span class="kc">?</span>') + kk('Close', '<span class="kc">esc</span>') + '</div>' +
      '<h3 class="sh3">What the colours say</h3><div class="legend2"><span class="st ok">landed</span><span>done, passing, live</span><span class="st run">running</span><span>running, claimed, in review</span>' +
      '<span class="st wait">waiting</span><span>queued, quiet, answered and not saved</span><span class="st bad">stuck</span><span>failed, blocked, late, an alarm</span><span class="st park">parked</span><span>parked, relayed, planned</span>' +
      '<span class="mono b">$0.07e</span><span>7 cents effective: the list price × the week\'s ratio' + ((S.header || {}).ratio ? ' (' + S.header.ratio + ')' : '') + '.</span></div>';
    openSheet();
  }
  function openSheet() { $('#sheet').classList.add('on'); $('#scrim').classList.add('on'); $('#sheet').scrollTop = 0; }
  function closeSheets() { $('#sheet').classList.remove('on'); $('#csheet').classList.remove('on'); $('#scrim').classList.remove('on'); }

  /* ── render: the first draw and every poll, region by region ── */
  function filter() {
    var w = V.find.trim().toLowerCase();
    $$('[data-find]').forEach(function (el) {
      var host = el.closest('.card, .doc, li') || el;
      host.classList.toggle('hid', !!w && host.textContent.toLowerCase().indexOf(w) < 0);
    });
  }
  function render() {
    EC = null;   // the adapter again: the ages move with the clock
    var snapN = window.FX && FX.snap ? FX.snap() : null;
    reconcile($('#strip'), strip()); placeBoats();
    reconcile($('#side'), sideHTML());
    reconcile($('#tabbar'), tabbar());
    reconcile($('#main'), mainHTML());
    reconcile($('#csheet'), sideHTML());
    $('#main').dataset.view = V.view; document.body.dataset.view = V.view;
    savebar(); filter();
    if (snapN && FX.tick) FX.tick(snapN);
  }
  function apply(next) { if (!next || typeof next !== 'object') return; S = next; render(); }
  B.apply = apply;
  function go(v) {
    if (NAMES.indexOf(v) < 0) return;
    V.view = v; put('view', v); closeSheets(); render(); url(); scrollTo(0, 0);
  }
  B.go = go;
  function url() {
    try {
      var p = new URLSearchParams(location.search); p.set('view', V.view);
      if (V.view === 'engine' && V.esec && V.esec !== 'all') p.set('sec', V.esec); else p.delete('sec');
      history.replaceState(null, '', '?' + p.toString());
    } catch (e) { /* a file: or srcdoc page */ }
  }
  function theme() {
    var r = document.documentElement, t = r.dataset.theme === 'dark' ? 'light' : 'dark';
    r.dataset.theme = t; try { localStorage.setItem('helm-theme', t); } catch (e) { /* private window */ }
    render();
  }
  if (window.MutationObserver) new MutationObserver(function () { reconcile($('#strip'), strip()); })
    .observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });   // theme.js follows the system with no render
  B.theme = theme;
  B.find = function (w) { V.find = String(w || ''); $$('.findin').forEach(function (x) { x.value = V.find; }); filter(); };

  document.addEventListener('click', function (e) {
    // only the triggers: #main and <body> carry data-view as state, so a bare [data-view] matched every click
    // (a card's links never opened, a click in a sheet closed it); a modified click opens its new tab as a link does
    var a = e.target.closest('a[data-view], [data-act], [data-jump], [data-esec], [data-verb]'); if (!a) return;
    if (a.dataset.esec) { V.esec = a.dataset.esec; V.econfirm = null; render(); url(); return; }
    if (a.dataset.verb && a.dataset.verb.slice(0, 2) === 'e:' && EV()) { var ep = a.dataset.verb.split(':'); EV().verb(ep[1], ep[2], ep.slice(3).join(':')); return; }
    if (a.dataset.view) { if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button) return; e.preventDefault(); go(a.dataset.view); return; }
    if (a.dataset.jump) { var t = document.getElementById(a.dataset.jump); if (t) { e.preventDefault(); closeSheets(); scrollTo(0, t.getBoundingClientRect().top + scrollY - 90); } return; }
    var act = a.dataset.act;
    if (act === 'theme') theme(); else if (act === 'help') help(); else if (act === 'close') closeSheets();
    else if (act === 'contents') { $('#csheet').classList.add('on'); $('#scrim').classList.add('on'); }
    else if (act === 'save') doSave(); else if (act === 'copy') doCopy();
  });
  $('#scrim').addEventListener('click', closeSheets);
  document.addEventListener('input', function (e) {
    if (!e.target.classList || !e.target.classList.contains('findin')) return;
    V.find = e.target.value; $$('.findin').forEach(function (x) { if (x !== e.target) x.value = V.find; }); filter();
  });
  document.addEventListener('keydown', function (e) {
    var typing = e.target.closest && e.target.closest('input, textarea, select, [contenteditable]');
    if (e.key === 'Escape') { if ($('#sheet.on, #csheet.on')) { e.preventDefault(); closeSheets(); } else if (V.view === 'engine' && EV() && EV().escape()) e.preventDefault(); else if (typing) e.target.blur(); return; }
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') { if (V.view === 'decide') { e.preventDefault(); doSave(); } return; }   // the save strip is Decide's
    if (typing || e.metaKey || e.ctrlKey || e.altKey) { V.g = 0; return; }
    var gAt = V.g; V.g = 0;
    if (gAt && Date.now() - gAt < 1500) { var to = { d: 'decide', f: 'fleet', s: 'ships', k: 'skippers', r: 'reports', e: 'engine' }[e.key.toLowerCase()]; if (to) { e.preventDefault(); go(to); } return; }
    if (e.key === '/') { var f = $$('.findin').filter(function (x) { return x.offsetParent; })[0]; if (!f) { $('#csheet').classList.add('on'); $('#scrim').classList.add('on'); f = $('#csheet .findin'); } if (f) { e.preventDefault(); f.focus(); } }
    else if (e.key === '?') { e.preventDefault(); help(); }
    else if (e.key === 't' || e.key === 'T') theme();
    else if (e.key === 'g' || e.key === 'G') V.g = Date.now();   // a g waits 1.5 s for its view key
  });
  var lastW = innerWidth;
  addEventListener('resize', function () { if (Math.abs(innerWidth - lastW) > 40) { lastW = innerWidth; render(); } placeBoats(); });

  /* ── the poll: one fetch of state.json beside the page, every 30 s; a new snapshot is reconciled, never redrawn ── */
  function poll() {
    fetch('state.json', { cache: 'no-store' }).then(function (r) { return r.ok ? r.json() : null; }).then(function (j) { if (j && j.as_of !== S.as_of) apply(j); }).catch(function () { /* offline, file: */ });
    // the Engine room's document beside it: a new `at` is reconciled like the board (a page with none keeps its snapshot)
    fetch('engine.json', { cache: 'no-store' }).then(function (r) { return r.ok ? r.json() : null; }).then(function (j) { if (j && typeof j === 'object' && (!ES || j.at !== ES.at)) applyEngine(j); }).catch(function () { /* offline, file: */ });
  }
  function applyEngine(next) { if (!next || typeof next !== 'object') return; ES = next; EC = null; render(); }
  B.applyEngine = applyEngine;
  B.poll = poll;
  render();
  if (q.get('help')) help();
  if (window.FX && FX.runFrozen) FX.runFrozen({});
  if (!/^(file|about):/.test(location.protocol)) setInterval(poll, 30000);
})();
