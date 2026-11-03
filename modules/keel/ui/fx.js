/* fx.js — keel's copy of the helm council's round-6 fx layer (docs/helm-council-2026-11-01/fable/r6/fx.js; helm-ui
   S10), served by keel to the Course page and to helm's board (keel's foundation_js). What changed from the prototype:
   it stands without decision.js (S8's): the query is its own (`window.__q` for a srcdoc frame, as decision.js reads
   it), a page's events reach it through FX.on(why, m), which it hands to DC.on itself when decision.js loaded first;
   the device's memory is `helm-fx-shipped`, not a round's key; a settle restarts (a real style flush). The life on the board and the Course page.
   What it does: (1) a button that applies something answers with the rainbow press light (fx.css `.lit`), found
   again after the page re-renders it — a pick lights its option, a mode its button, a Save the strip, a card verb
   its card, a day or a tab itself; (2) a count that changed ticks (`.n[data-key]`); (3) a shipped ship opened for the
   first time on this device sets off the mark's fireworks (art.js), once per ship (localStorage), skipped by any key
   or click, never under reduced motion (a still burst stands beside the ship's name instead); (4) `?fx=<show>&t=<ms>`
   freezes a show at that instant for a screenshot: press, fireworks, settle, save, tick. Nothing here blocks input:
   every effect is a class on an element that is already in its new state. */
(function () {
  'use strict';
  var FX = window.FX = {};
  var DC = window.DC || {};
  var qs = DC.qs || new URLSearchParams(location.search || window.__q || ''), reduced = function () { return matchMedia('(prefers-reduced-motion: reduce)').matches; };
  FX.reduced = reduced;
  var frozen = qs.get('fx') ? { show: qs.get('fx'), t: +(qs.get('t') || 400) } : null;
  FX.frozen = frozen;

  /* ── the press light ── */
  function light(el) {
    if (!el || reduced()) return;
    el.classList.remove('lit'); void el.offsetWidth;   // restart the light on a second press
    el.classList.add('lit');
    if (!frozen) setTimeout(function () { document.querySelectorAll('.lit').forEach(function (x) { x.classList.remove('lit'); }); }, 950);   // by selector: the element may have been redrawn meanwhile (DC.carryFx)
  }
  FX.light = light;
  function soon(f) { setTimeout(f, 20); }   // a timer, not a frame: a hidden page gets no frames, and the light must still be there when it is looked at
  // a pick lights the picked option, once the page has drawn it as picked; a page without decision.js calls FX.on itself
  FX.on = function (why, m) {
    if (why === 'pick' && m) soon(function () { var q = document.getElementById('q-' + m.doc + '-' + m.n); if (q) light(q.querySelector('.opt.pick')); FX.settle(m); });
    if (why === 'mode' && m) soon(function () { var b = document.querySelector('[data-modes="' + m.doc + '"] button.on') || document.querySelector('.modes button.on[data-mode="' + m.mode + '"]'); light(b); });
    if (why === 'save') soon(function () { light(document.getElementById('savebar')); });
  };
  if (DC.on) DC.on(FX.on);
  // a click on a day, a tab over the feed, a card's verb or a sheet's confirming button lights what it pressed
  document.addEventListener('click', function (e) {
    var t = e.target.closest && e.target.closest('.day, .cat, [data-verb], [data-act="memo-read"], [data-act="hail-send"], [data-act="bringback"], [data-act="yolo-ok"], [data-takeall], [data-take], [data-act="confirm"]');
    if (!t) return;
    var card = t.closest('.card'), key = t.dataset.day ? '.day[data-day="' + t.dataset.day + '"]' : t.dataset.cat ? '.cat[data-cat="' + t.dataset.cat + '"]' : null;
    soon(function () {
      if (card && card.id) { var c = document.getElementById(card.id); light(c || card); return; }
      if (key) { light(document.querySelector(key)); return; }
      if (t.isConnected) light(t);
    });
  }, true);

  /* ── the buoys settle: the Course strip's and contents' buoy of an answered decision rocks once ── */
  FX.settle = function (m) {
    document.querySelectorAll('[data-goq="' + m.n + '"] .buoy, #q-' + m.doc + '-' + m.n + ' .buoy').forEach(function (b) { b.classList.remove('settle'); void b.getBoundingClientRect(); b.classList.add('settle'); });
    if (!frozen) setTimeout(function () { document.querySelectorAll('.buoy.settle').forEach(function (b) { b.classList.remove('settle'); }); }, 1100);
  };

  /* ── counts tick: snapshot the keyed numbers before a refresh, mark the ones that changed after it ── */
  FX.snap = function () { var o = {}; document.querySelectorAll('.n[data-key]').forEach(function (n) { o[n.dataset.key] = n.textContent; }); return o; };
  FX.tick = function (prev) {
    if (!prev) return;
    document.querySelectorAll('.n[data-key]').forEach(function (n) { if (prev[n.dataset.key] != null && prev[n.dataset.key] !== n.textContent) { n.classList.add('tick'); if (!frozen) setTimeout(function () { n.classList.remove('tick'); }, 500); } });
  };

  /* ── the fireworks for a shipped ship, the first time on this device ── */
  var FKEY = 'helm-fx-shipped', mem = {}, fresh = qs.has('selftest') || qs.has('fresh');   // mem: this page's own memory; a fresh page (a self-test) never reads or writes the device's
  function seen() { var o = {}; if (!fresh) { try { o = JSON.parse(localStorage.getItem(FKEY) || '{}'); } catch (e) { o = {}; } } for (var k in mem) o[k] = mem[k]; return o; }
  FX.seenShipped = function (id) { return !!seen()[id]; };
  FX.fireworks = function (ship, o) {
    o = o || {};
    var s = seen();
    if (!o.force && s[ship.id]) return 'seen';
    if (!o.force) { s[ship.id] = mem[ship.id] = Date.now(); try { if (!fresh) localStorage.setItem(FKEY, JSON.stringify(s)); } catch (e) { /* off */ } }
    if (reduced() || o.reduced) return 'still';   // the ship's head carries the still burst already
    FX.stop();
    var layer = document.createElement('div'); layer.className = 'fxlayer'; layer.id = 'fxlayer';
    layer.innerHTML = ART.fireworks(ship.hue && ship.hue !== 'slate' ? 'var(--hue-' + ship.hue + ')' : 'var(--flag)', 760, 270);
    document.body.appendChild(layer);
    var end = function () { FX.stop(); };
    FX._end = end;
    document.addEventListener('keydown', end, { once: true, capture: true });
    document.addEventListener('pointerdown', end, { once: true, capture: true });
    if (!frozen) FX._t = setTimeout(end, 3200);
    return 'shown';
  };
  FX.stop = function () { var l = document.getElementById('fxlayer'); if (l) l.remove(); clearTimeout(FX._t); if (FX._end) { document.removeEventListener('keydown', FX._end, true); document.removeEventListener('pointerdown', FX._end, true); FX._end = null; } };

  /* ── freezing a show for a screenshot: ?fx=press|fireworks|settle|save|tick&t=<ms> ── */
  FX.freezeNow = function () {
    if (!frozen) return;
    document.documentElement.style.setProperty('--fxt', frozen.t + 'ms');
    document.documentElement.classList.add('fxfreeze');
  };
  FX.runFrozen = function (ctx) {
    if (!frozen) return;
    var show = frozen.show;
    setTimeout(function () {
      if (show === 'press') { var q = document.querySelector('.dq:not(.folded) .opt.pick') || document.querySelector('.dq:not(.folded) .opt.rec') || document.querySelector('.btn.primary'); if (q) q.classList.add('lit'); }
      else if (show === 'fireworks') { var sh = (ctx && ctx.ship) || { id: 'frozen', hue: 'teal' }; FX.fireworks(sh, { force: true }); }
      else if (show === 'settle') { document.querySelectorAll('.sbuoy .buoy, .toc-l .buoy, .tier .buoy').forEach(function (b, i) { if (i % 2 === 0) b.classList.add('settle'); }); }
      else if (show === 'save') { var sb = document.getElementById('savebar'); if (sb) { sb.classList.remove('on'); void sb.offsetWidth; sb.classList.add('on'); sb.classList.add('lit'); } }
      else if (show === 'tick') { document.querySelectorAll('.n[data-key]').forEach(function (n) { n.classList.add('tick'); }); }
      FX.freezeNow();
    }, 60);
  };
})();
