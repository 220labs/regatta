/* decision.js — keel's decision component (helm-ui S8): the helm council's round-6 decision.js
   (docs/helm-council-2026-11-01/fable/r6/decision.js) on keel's own markup, served by decision_js() as window.KDC.
   The Course page's form owns the answers: each decision's hidden `#ans-D<n>` box is what Save, Copy and the
   draft read, as before S8. This file owns what the owner sees and presses:
   - one answer per question: a letter, or the owner's own words in the last row, never both — picking a letter
     empties the words, typing words unpicks the letter at once (the council's round 6b);
   - the guard: a one-way pick (tier irreversible or held) waits for its confirm, inline, Return again or the
     button; R takes only a plain pick (never a conditional, reopened, unmarked or absent one); Accept all takes
     every one-letter, unconditional `Reversible: yes` pick, then offers the irreversible ones behind one confirm
     (actions D1, answered C); a held or the owner's own is never taken in bulk;
   - the keys: ↓ ↑ walk the visual rows of a question's buttons to the nearest by x, and only from the last row
     (or the first) on to the next question; ← → across a row and on in reading order, the words last; J K
     question to question; Return chooses the ringed option and Return again confirms; R the recommended; A–F
     direct; Esc cancels a confirm, else lets go; ⌘↩ (Ctrl+↩) saves;
   - the mode switch: what each skipper mode would take, a decision it takes folded to two lines on this page.
     The run keeps the mode helm gave it: the switch is this browser's, kept per doc. */
(function () {
  'use strict';
  var KDC = window.KDC = {};
  var REC_TAKEN = /^=\s*recommended(?:\s*\(accept all\))?$/i;
  KDC.ACCEPT_ALL = '= recommended (accept all)';
  KDC.MODES = ['ask', 'auto', 'dnd', 'yolo'];
  KDC.TAKES = { ask: [], auto: ['safe'], dnd: ['safe', 'irreversible'], yolo: ['safe', 'irreversible', 'held'] };
  /* plain yolo as keel's yolo() runs it: an unmarked pick taken too, and nothing at all while an open decision is
     reopened, conditional or has no pick (all or nothing: the run stops, writing none) */
  KDC.YOLO_STOPS = ['reopened', 'conditional', 'no pick'];
  KDC.MODE_SAYS = { ask: 'nothing answers but you', auto: 'takes the safe picks (helm\'s default mode)', dnd: 'takes safe and irreversible picks; holds money, deletion, publish, a third party',
                    yolo: 'takes every plain pick, unmarked ones too; while one is reopened, conditional or has no pick, takes nothing' };
  var cfg = { changed: function () {}, save: function () {}, flash: function () {}, slug: '', mode: 'ask' };
  var $ = function (id) { return document.getElementById(id); };
  var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); };
  var vis = function (el) { return el.offsetParent !== null || el.getClientRects().length > 0; };
  KDC.pending = null;   // {id, letter}: a one-way pick waiting for its confirm
  var unfolded = {}, mode = 'ask';

  KDC.items = function () { return Array.prototype.slice.call(document.querySelectorAll('.dq[data-item]')); };
  function sec(id) { return $('card-' + id); }
  function box(s) { return $('ans-' + s.dataset.id); }
  function words(s) { return $('free-' + s.dataset.id); }
  function letters(s) { return Array.prototype.map.call(s.querySelectorAll('button.opt[data-letter]'), function (b) { return b.dataset.letter; }); }
  function optText(s, l) { var b = s.querySelector('button.opt[data-letter="' + l + '"] .ot'); return b ? b.textContent : ''; }
  /* the letter an answer box holds: a lone letter of the options, or the recommendation's taken marker */
  KDC.chosen = function (s, v) {
    v = (v || '').trim();
    if (REC_TAKEN.test(v)) return s.dataset.rec || null;
    return /^[A-Z]$/.test(v) && letters(s).indexOf(v) >= 0 ? v : null;
  };
  KDC.oneWay = function (s) { return s.dataset.tier === 'irreversible' || s.dataset.tier === 'held'; };

  /* the page as the box says: the picked row, the words row, answered */
  KDC.sync = function (s) {
    var v = box(s).value, c = KDC.chosen(s, v), w = words(s), mine = !c && !REC_TAKEN.test(v.trim()) ? v : '';
    Array.prototype.forEach.call(s.querySelectorAll('button.opt[data-letter]'), function (b) { b.classList.toggle('pick', b.dataset.letter === c); });
    if (w && document.activeElement !== w && w.value !== mine) w.value = mine;
    if (w) w.closest('.opt').classList.toggle('pick', !!mine.trim());
    s.classList.toggle('answered', !!v.trim());
    var p = KDC.pending;
    s.classList.toggle('confirming', !!(p && p.id === s.dataset.id));
  };
  KDC.syncAll = function () { KDC.items().forEach(KDC.sync); applyMode(); };

  function confirmHTML(s, l) {
    var tier = s.dataset.tier, cls = s.dataset.cls, word = tier + (cls ? ' · ' + cls : ''), t = l ? optText(s, l) : '';
    var what = l ? 'You chose ' + l + ' — “' + esc(t.slice(0, 90)) + (t.length > 90 ? '…' : '') + '”.' : 'You chose the recommendation.';
    return '<div class="cw"><b>' + esc(word.charAt(0).toUpperCase() + word.slice(1)) + '.</b> ' +
      (tier === 'held' ? 'A mode short of yolo holds this pick (' + esc(cls) + '). ' : 'The doc marks this decision one-way: a revert does not undo it. ') + what +
      '</div><div class="btns"><button type="button" class="btn sm" data-act="cancel">Cancel <span class="k">esc</span></button>' +
      '<button type="button" class="btn sm go" data-act="confirm">Confirm ' + (l || 'it') + ' <span class="k">⏎</span></button></div>';
  }
  /* a letter (or null for the recommendation's marker) into the box; a one-way pick asks first */
  KDC.pick = function (s, l, how) {
    how = how || {};
    if (KDC.oneWay(s) && !how.confirmed) {
      var was = KDC.pending && KDC.pending.id !== s.dataset.id ? sec(KDC.pending.id) : null;
      KDC.pending = { id: s.dataset.id, letter: l, rec: !!how.rec };
      if (was) KDC.sync(was);   // one confirm on the page: the decision asked before lets its box go
      if (s.classList.contains('folded')) { unfolded[s.dataset.id] = 1; applyMode(); }   // a confirm is never asked out of sight
      s.querySelector('.confirm').innerHTML = confirmHTML(s, l);
      KDC.sync(s); return 'confirm';
    }
    KDC.pending = null;
    box(s).value = how.rec ? '= recommended' : l;
    if (words(s)) words(s).value = '';
    KDC.sync(s); cfg.changed();
    if (window.FX && window.FX.light) setTimeout(function () { window.FX.light(s.querySelector('.opt.pick')); }, 20);
    return 'picked';
  };
  KDC.confirm = function () {
    var p = KDC.pending; if (!p) return null;
    var s = sec(p.id); KDC.pending = null;
    return KDC.pick(s, p.letter, { confirmed: true, rec: p.rec });
  };
  KDC.cancel = function () { var p = KDC.pending; KDC.pending = null; if (p) KDC.sync(sec(p.id)); };
  /* R and the card's Take: only a plain pick — the refusals say why */
  KDC.takeRec = function (s) {
    var cls = s.dataset.cls;
    if (s.dataset.tier === 'yours') {
      cfg.flash(cls === 'pre-filled' ? s.dataset.id + '\'s answer is pre-filled with its recommendation: leave it, or write your own; Back to the recommendation restores it.' :
        cls === 'conditional' ? 'R takes only a plain pick: ' + s.dataset.id + '\'s is conditional. Choose it yourself.' :
        cls === 'reopened' ? 'R refuses a reopened decision: its recommendation was challenged.' :
        cls === 'unmarked' ? 'R refuses ' + s.dataset.id + ': its Reversible line is missing.' : 'R has nothing to take: ' + s.dataset.id + ' has no recommended pick.', 'Yours');
      return 'refused';
    }
    return KDC.pick(s, s.dataset.rec || null, { rec: true });
  };
  KDC.free = function (s) {   // the words row: typed words are the answer at once, and the letter goes
    var w = words(s); if (!w) return;
    unfolded[s.dataset.id] = 1; KDC.pending = null; box(s).value = w.value; KDC.sync(s); cfg.changed();
  };

  /* Accept all: the safe one-letter picks at once; the irreversible ones behind one confirm; done() saves */
  KDC.acceptAll = function (done) {
    var safe = [], irr = [], left = 0;
    KDC.items().forEach(function (s) {
      if (s.dataset.shape !== 'new' || box(s).value.trim()) return;
      if (s.dataset.rec && s.dataset.tier === 'safe') safe.push(s);
      else if (s.dataset.rec && s.dataset.tier === 'irreversible') irr.push(s);
      else left++;
    });
    safe.forEach(function (s) { box(s).value = KDC.ACCEPT_ALL; KDC.sync(s); });
    if (safe.length) cfg.changed();
    var ta = $('takeall'), took = 'Took ' + safe.length + ' safe pick' + (safe.length === 1 ? '' : 's') + '.';
    var note = left ? took + ' ' + left + ' left for you: held, the owner\'s own (conditional, unmarked, reopened), or a pick that is not one letter.' : '';
    if (!irr.length || !ta) { done(safe.length, note); return safe.length; }
    ta.innerHTML = '<span class="tw">' + took + ' <b>Also the ' + irr.length + ' irreversible?</b> ' + irr.map(function (s) {
      var t = optText(s, s.dataset.rec); return esc(s.dataset.id) + ' → ' + esc(s.dataset.rec) + (t ? ': ' + esc(t.slice(0, 60)) + (t.length > 60 ? '…' : '') : ''); }).join(' · ') +
      '</span><button type="button" class="btn sm" data-act="notnow">Not now</button><button type="button" class="btn sm go" data-act="takeirr">Take ' + irr.length + ' irreversible</button>';
    ta.hidden = false;
    KDC._irr = { list: irr.map(function (s) { return s.dataset.id; }), done: done, n: safe.length, note: note };
    return 'asked';
  };
  KDC.takeIrr = function (yes) {
    var q = KDC._irr; if (!q) return; KDC._irr = null; $('takeall').hidden = true;
    if (yes) { q.list.forEach(function (id) { var s = sec(id); if (!box(s).value.trim()) { box(s).value = KDC.ACCEPT_ALL; KDC.sync(s); } }); cfg.changed(); }
    q.done(q.n + (yes ? q.list.length : 0), yes ? q.note : (q.note ? q.note + ' ' : '') + 'Not now: ' + q.list.length + ' irreversible left.');
  };

  /* the mode switch: this browser's per doc; a decision the mode takes folds, until opened */
  function open_(s) { return s.dataset.shape === 'new' && !box(s).value.trim(); }
  KDC.yoloStopped = function () { return KDC.items().some(function (s) { return open_(s) && KDC.YOLO_STOPS.indexOf(s.dataset.cls) >= 0; }); };
  KDC.takes = function (s, m) {
    m = m || mode;
    if (m === 'yolo') return !KDC.yoloStopped() && (KDC.TAKES.yolo.indexOf(s.dataset.tier) >= 0 || s.dataset.cls === 'unmarked');
    return KDC.TAKES[m].indexOf(s.dataset.tier) >= 0;
  };
  function applyMode() {
    KDC.items().forEach(function (s) {
      var taken = open_(s) && KDC.takes(s) && !unfolded[s.dataset.id];
      s.classList.toggle('folded', taken);
      var who = s.querySelector('.fold .who');
      if (who) { who.className = 'who ' + mode; who.textContent = mode + ' takes ' + (s.dataset.rec || 'the pick'); }
    });
    Array.prototype.forEach.call(document.querySelectorAll('.cmode .modes button[data-mode]'), function (b) { b.classList.toggle('on', b.dataset.mode === mode); });
    if ($('mode-says')) $('mode-says').textContent = (mode === 'yolo' && KDC.yoloStopped() ? 'yolo stops at this doc, taking nothing: a decision is reopened, conditional or has no pick' : KDC.MODE_SAYS[mode]) +
      ' — on this page only; the run keeps the mode helm gave it.';
  }
  KDC.setMode = function (m) {
    if (KDC.MODES.indexOf(m) < 0) return;
    mode = m; unfolded = {};
    try { localStorage.setItem('keel-mode:' + cfg.slug, m); } catch (e) { /* storage off */ }
    applyMode();
  };
  KDC.mode = function () { return mode; };

  /* ── keys: the board's controller, on this page's decisions ── */
  var K = KDC.K = { i: -1, kopt: null };
  K.cur = function () { return KDC.items().filter(vis)[K.i] || null; };
  K.buttons = function (s) { return Array.prototype.slice.call(s.querySelectorAll('button.opt[data-letter], .opt.free')).filter(vis); };
  K.keyOf = function (b) { return b.classList.contains('free') ? 'free' : b.dataset.letter; };
  K.btn = function (s, k) { return k === 'free' ? s.querySelector('.opt.free') : k == null ? null : s.querySelector('button.opt[data-letter="' + k + '"]'); };
  /* the buttons grouped into the rows the eye sees: a new row wherever a button starts lower */
  K.rows = function (s) {
    var rows = [];
    K.buttons(s).forEach(function (b) {
      var r = b.getBoundingClientRect(), row = null;
      for (var i = 0; i < rows.length; i++) if (Math.abs(rows[i].top - r.top) < 8) { row = rows[i]; break; }
      if (!row) { row = { top: r.top, items: [] }; rows.push(row); }
      row.items.push({ k: K.keyOf(b), x: r.left + r.width / 2 });
    });
    rows.sort(function (a, b) { return a.top - b.top; });
    rows.forEach(function (r) { r.items.sort(function (a, b) { return a.x - b.x; }); });
    return rows;
  };
  K.order = function (s) { var o = []; K.rows(s).forEach(function (r) { r.items.forEach(function (it) { o.push(it.k); }); }); return o; };
  /* the ring: the focused decision, the ringed button, the browser's focus kept on it so Return and the ring agree */
  K.focus = function (s, k, scroll) {
    var all = KDC.items().filter(vis);
    var p = KDC.pending;
    if (p && (!s || p.id !== s.dataset.id || (k != null && k !== p.letter))) KDC.cancel();
    KDC.items().forEach(function (x) { if (x !== s) x.classList.remove('focus'); });
    Array.prototype.forEach.call(document.querySelectorAll('.dq .kfocus'), function (x) { x.classList.remove('kfocus'); });
    K.i = all.indexOf(s); K.kopt = k == null ? null : k;
    if (!s) return;
    s.classList.add('focus');
    var b = K.btn(s, K.kopt), a = document.activeElement;
    if (b) b.classList.add('kfocus');
    if (!(a && /^(TEXTAREA|INPUT|SELECT)$/.test(a.tagName))) {
      var t = b && b.classList.contains('free') ? null : b;
      // a control focused elsewhere (a mode, Save, Accept all) lets go too, or Return would press it again
      try { if (t) t.focus({ preventScroll: true }); else if (a && a !== b && a !== document.body && a.blur && (!s.contains(a) || (a.closest && a.closest('.dq .opt')))) a.blur(); } catch (e) { /* gone */ }
    }
    if (scroll === false) return;
    var r = (b || s).getBoundingClientRect(), top = 16, bar = document.querySelector('.bar'), bottom = innerHeight - (bar ? bar.offsetHeight : 0) - 16;
    if (!b) r = { top: r.top, bottom: Math.min(r.bottom, r.top + innerHeight * 0.6) };
    if (r.top < top) scrollBy(0, r.top - top - 8); else if (r.bottom > bottom) scrollBy(0, r.bottom - bottom + 8);
  };
  K.release = function () { KDC.pending = null; KDC.items().forEach(function (x) { x.classList.remove('focus'); KDC.sync(x); }); K.focus(null); K.i = -1; };
  /* J K: question to question, nothing ringed */
  K.move = function (d) {
    var it = KDC.items().filter(vis); if (!it.length) return;
    var j = K.cur() ? Math.max(0, Math.min(it.length - 1, K.i + d)) : (d > 0 ? 0 : it.length - 1);
    KDC.cancel(); K.focus(it[j], null);
  };
  /* ↓ ↑ from the last row (or the first) on to the next decision: its first row going down, its last going up */
  K.step = function (d) {
    var it = KDC.items().filter(vis); if (!it.length) return false;
    var j;
    if (K.cur()) j = K.i + d;
    else {   // nothing ringed: the first decision in view going down, the last going up; none in view, the page scrolls
      var seen = it.filter(function (x) { var r = x.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight; });
      if (!seen.length) return false;
      j = it.indexOf(d > 0 ? seen[0] : seen[seen.length - 1]);
    }
    if (j < 0 || j >= it.length) return false;
    KDC.cancel();
    K.focus(it[j], null, false);   // focused first: the words row shows only on the focused question, and is a row then
    var rows = K.rows(it[j]), r = rows.length ? (d > 0 ? rows[0] : rows[rows.length - 1]) : null;
    K.focus(it[j], r ? r.items[0].k : null);
    return true;
  };
  K.vert = function (d) {   // false: nothing to move to, so the key is the page's (it scrolls)
    var s = K.cur(); if (!s) return K.step(d);
    var rows = K.rows(s);
    if (K.kopt == null) { if (d > 0 && rows.length) { K.focus(s, rows[0].items[0].k); return true; } return K.step(d); }
    var at = null;
    rows.forEach(function (r, i) { r.items.forEach(function (it, j) { if (it.k === K.kopt) at = [i, j]; }); });
    if (!at) return K.step(d);
    var ri = at[0] + d;
    if (ri >= 0 && ri < rows.length) {
      var x = rows[at[0]].items[at[1]].x, best = rows[ri].items[0];
      rows[ri].items.forEach(function (c) { if (Math.abs(c.x - x) < Math.abs(best.x - x)) best = c; });
      K.focus(s, best.k); return true;
    }
    return K.step(d);
  };
  /* ← → across a row and on in reading order, the words last */
  K.across = function (d) {
    var s = K.cur(); if (!s) return;
    var a = K.order(s); if (!a.length) return;
    var j = a.indexOf(K.kopt);
    j = j < 0 ? (d > 0 ? 0 : a.length - 1) : Math.max(0, Math.min(a.length - 1, j + d));
    K.focus(s, a[j]);
  };
  /* on to the next decision still owed, after a pick the keys made */
  K.advance = function (s) {
    setTimeout(function () {
      var it = KDC.items().filter(vis), i = it.indexOf(s);
      for (var j = i + 1; j < it.length; j++) if (!box(it[j]).value.trim() && !it[j].classList.contains('folded')) { K.focus(it[j], null); return; }
    }, 160);
  };
  K.choose = function (s, k) {
    if (k === 'free') { var w = words(s); if (w) { w.closest('.opt').classList.add('open'); w.focus(); } return; }
    K.focus(s, k, false);
    if (KDC.pick(s, k) === 'picked') K.advance(s);
  };
  K.handle = function (e) {
    var t = e.target, t0 = (e.composedPath && e.composedPath()[0]) || t, mod = e.metaKey || e.ctrlKey, k = e.key;
    var typing = !!t0 && (/^(TEXTAREA|INPUT|SELECT)$/.test(t0.tagName || '') || !!t0.isContentEditable);
    if (mod && k === 'Enter') { e.preventDefault(); cfg.save(); return; }
    if (typing) {
      if (k === 'Escape') { e.preventDefault(); t.blur(); }
      if (k === 'Enter' && !e.shiftKey && t.id && t.id.indexOf('free-') === 0) { e.preventDefault(); t.blur(); }
      return;
    }
    if (mod || e.altKey) return;
    var s = K.cur();
    var nb = t && t.closest && t !== document.body ? t.closest('button, a, [role="button"]') : null;
    if (nb && (k === 'Enter' || k === ' ')) {
      var host = nb.closest('.dq[data-item]');
      if (!(host && nb.matches('button.opt[data-letter], .opt.free') && k === 'Enter')) return;   // any other control keeps its own keys
      e.preventDefault(); K.i = KDC.items().filter(vis).indexOf(host);
      if (KDC.pending && KDC.pending.id === host.dataset.id) { if (KDC.confirm() === 'picked') K.advance(host); return; }
      K.choose(host, K.keyOf(nb)); return;
    }
    if (k === 'ArrowDown' || k === 'ArrowUp') { if (K.vert(k === 'ArrowDown' ? 1 : -1)) e.preventDefault(); return; }
    if (k === 'j' || k === 'J') { e.preventDefault(); K.move(1); return; }
    if (k === 'k' || k === 'K') { e.preventDefault(); K.move(-1); return; }
    if ((k === 'ArrowRight' || k === 'ArrowLeft') && s) { e.preventDefault(); K.across(k === 'ArrowRight' ? 1 : -1); return; }
    if (k === 'Escape') { if (!s) return; e.preventDefault(); if (KDC.pending) { KDC.cancel(); return; } K.release(); return; }
    if (!s) return;
    // a folded decision opens first: Return, R or a letter on it only unfolds it, so nothing is picked unseen
    if (s.classList.contains('folded') && (k === 'Enter' || k === 'r' || k === 'R' || /^[a-fA-F]$/.test(k))) {
      e.preventDefault(); unfolded[s.dataset.id] = 1; applyMode(); K.focus(s, null); return;
    }
    if (k === 'Enter') {
      e.preventDefault();
      if (KDC.pending && KDC.pending.id === s.dataset.id) { if (KDC.confirm() === 'picked') K.advance(s); return; }
      if (K.kopt == null) { K.focus(s, s.dataset.rec && K.btn(s, s.dataset.rec) ? s.dataset.rec : K.order(s)[0]); return; }
      K.choose(s, K.kopt); return;
    }
    if ((k === 'r' || k === 'R') && !e.shiftKey) { e.preventDefault(); K.focus(s, s.dataset.rec || null, false); if (KDC.takeRec(s) === 'picked') K.advance(s); return; }
    if (/^[a-fA-F]$/.test(k) && !e.shiftKey) {
      var l = k.toUpperCase();
      if (letters(s).indexOf(l) >= 0) { e.preventDefault(); K.choose(s, l); }
    }
  };

  /* clicks: an option picks (a one-way one asks), the words row opens, the confirm's and Accept all's buttons answer */
  KDC.click = function (b) {
    var s = b.closest('.dq[data-item]'); if (!s) return;
    if (KDC.pending && KDC.pending.id === s.dataset.id && KDC.pending.letter === b.dataset.letter) { KDC.confirm(); return; }
    K.focus(s, b.dataset.letter, false); KDC.pick(s, b.dataset.letter);
  };
  function onClick(e) {
    var a = e.target.closest && e.target.closest('[data-act], [data-mode]');
    if (a && a.dataset.mode && a.closest('.cmode')) { KDC.setMode(a.dataset.mode); return; }
    var s = e.target.closest && e.target.closest('.dq[data-item]');
    if (a) {
      var act = a.dataset.act;
      // a confirm answers its own decision only: a box another pick left behind confirms nothing
      if (act === 'confirm') { if (!s || !KDC.pending || KDC.pending.id !== s.dataset.id) { if (s) KDC.sync(s); return; }
        if (KDC.confirm() === 'picked') K.advance(s); return; }
      if (act === 'cancel') { KDC.cancel(); return; }
      if (act === 'unfold' && s) { unfolded[s.dataset.id] = 1; applyMode(); K.focus(s, null, false); return; }
      if (act === 'takeirr' || act === 'notnow') { KDC.takeIrr(act === 'takeirr'); return; }
    }
    if (!s) return;
    var f = e.target.closest('.opt.free');
    if (f && !e.target.closest('textarea')) { f.classList.add('open'); words(s).focus(); }
    if (!e.target.closest('button.opt')) K.focus(s, f ? 'free' : K.cur() === s ? K.kopt : null, false);
  }

  KDC.init = function (c) {
    for (var k in c) cfg[k] = c[k];
    var m = null; try { m = localStorage.getItem('keel-mode:' + cfg.slug); } catch (e) { /* storage off */ }
    mode = KDC.MODES.indexOf(m) >= 0 ? m : (KDC.MODES.indexOf(cfg.mode) >= 0 ? cfg.mode : 'ask');
    if (window.ART) {   // the hand-drawn marks: the tier's buoy, the recommended flag (keel's foundation, art.js)
      Array.prototype.forEach.call(document.querySelectorAll('.dq [data-buoy]'), function (x) { x.innerHTML = window.ART.buoy(x.dataset.buoy, x.dataset.buoy, 18); });
      Array.prototype.forEach.call(document.querySelectorAll('.dq [data-art="flag"]'), function (x) { x.innerHTML = window.ART.flag(13); });
    }
    KDC.items().forEach(function (s) {
      var w = words(s);
      if (w) w.addEventListener('input', function () { KDC.free(s); });
    });
    document.addEventListener('keydown', K.handle);
    document.addEventListener('click', onClick);
    /* Tab onto an option or the words row moves the ring there too (a pointer's focus is left to its click), as the
       prototype's focusin does: the keys then walk on from where the browser's focus is */
    var lastPointer = 0;
    document.addEventListener('pointerdown', function () { lastPointer = Date.now(); }, true);
    document.addEventListener('focusin', function (e) {
      if (Date.now() - lastPointer < 400 || !e.target.closest) return;
      var b = e.target.closest('.dq button.opt[data-letter], .dq .opt.free'), s = b && b.closest('.dq[data-item]');
      if (!s || (K.cur() === s && K.kopt === K.keyOf(b))) return;
      K.focus(s, K.keyOf(b), false);
    });
    KDC.syncAll();
  };
})();
