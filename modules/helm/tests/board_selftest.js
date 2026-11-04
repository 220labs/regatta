/* board_selftest.js — test_board.sh's reads inside the helm board (helm-board-ux S3), injected after board.js; never shipped.
   ?selftest=<label> posts [{name, ok, got}] to the parent: the shell's facts at the frame's width and theme, or, with
   ?selftest=reconcile, the poll case — a typed answer and the find field survive three polls, a reorder and their card
   leaving the board (the doc's "The poll steals a draft" check). Every read is synchronous after load, so a frame that
   throws posts what it read so far and the error. */
(function () {
  var q = new URLSearchParams(location.search), label = q.get('selftest'), out = [], H = window.HELM;
  function read(name, ok, got) { out.push({ name: name, ok: !!ok, got: got === undefined ? '' : String(got) }); }
  function shown(el) { return !!el && getComputedStyle(el).display !== 'none' && el.getClientRects().length > 0; }
  function $(s) { return document.querySelector(s); }
  function $$(s) { return Array.prototype.slice.call(document.querySelectorAll(s)); }
  function post() { parent.postMessage({ board: label, out: out }, '*'); }
  function key(k) { document.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true })); }
  function clone(o) { return JSON.parse(JSON.stringify(o)); }

  function shell() {
    var w = innerWidth, wide = w >= 1100, S = H.S(), h = S.header || {};
    read('no script error', !(window.__errs || []).length, (window.__errs || []).join(' | '));
    read('the theme asked for', document.documentElement.dataset.theme === q.get('theme'), document.documentElement.dataset.theme);
    read('no sideways scroll', document.documentElement.scrollWidth <= w + 1, document.documentElement.scrollWidth + ' > ' + w);
    read(wide ? 'the side column, no tab bar' : 'the tab bar, no side column', wide ? shown($('#side')) && !shown($('#tabbar')) : shown($('#tabbar')) && !shown($('#side')));
    var views = wide ? $$('#side .vw') : $$('#tabbar .tab');
    read('the views: five' + (wide ? ' and the Engine room' : ''), views.length === (wide ? 6 : 5), views.map(function (a) { return a.dataset.view; }).join(','));
    read('the Engine room has its slot', !!document.querySelector('#csheet [data-view="engine"]') && (!wide || shown($('#side [data-view="engine"]'))));
    var dec = (wide ? $('#side .vw[data-view="decide"] .vb') : $('#tabbar .tab[data-view="decide"] .vb'));
    read('Decide counts what needs the owner', dec && dec.textContent === String(h.needs_owner), dec && dec.textContent);
    // a shipped boat hides on a narrow sea, as the prototype's does: only the boats shown are read
    var boats = $$('#strip .boat').filter(shown), sea = $('#strip .sea'), W = sea ? sea.getBoundingClientRect() : null;
    var sail = boats.filter(function (b) { return !b.classList.contains('shipped'); });
    read('the sea holds a boat per tenth when crowded: 4 for the 15 sailing', sail.length === 4 && sail.reduce(function (a, b) { var n = b.querySelector('.bn'); return a + (n ? +n.textContent : 1); }, 0) === 15,
      sail.map(function (b) { return (b.querySelector('.bn') || {}).textContent || 1; }).join(','));
    read('every boat shown inside the sea', W && boats.every(function (b) { var r = b.getBoundingClientRect(); return r.left >= W.left - 12 && r.right <= W.right + 26; }),
      boats.map(function (b) { return Math.round(b.getBoundingClientRect().left - W.left); }).join(','));
    var st = $('#strip .stat'), stt = st ? st.textContent : '';
    read('the strip names the time and the week', /\d\d:\d\d/.test(stt) && /week/.test(stt), stt);
    if (w >= 760) read('the strip names the host', stt.indexOf(S.host) >= 0, stt);
    var notes = $$('.hnotes .st').map(function (n) { return n.textContent; }).join(' | ');
    read('the header keeps the sheep and talk notes', notes.indexOf(h.sheep) >= 0 && notes.indexOf(h.talk) >= 0, notes);
    read('the h1 says you, never a name', /need you\.$/.test(($('.vh h1') || {}).textContent || ''), ($('.vh h1') || {}).textContent);
    // every price is effective, $0.07e: Fleet's cards carry costs
    H.go('fleet');
    var cost = $$('#main .card .mono').map(function (n) { return n.textContent; }).filter(function (t) { return /\$/.test(t); });
    read('prices are effective only, as the core\'s usd() prints them ($0.07e, spent/total, no exponent)',
      cost.slice().sort().join(' ') === ['$0.00000083e', '$0.00083e', '$0.012e/$0.015e', '$0.020e'].sort().join(' '), cost.join(' '));
    read('a card says what is parked and how much is open', /parked: S4, S5/.test($('#main').textContent) && /3 open/.test($('#main').textContent));
    H.go('ships');
    var svg = ($('#main .tl svg') || {}).innerHTML || '';
    read('Ships draws a milestone, an ask\'s flag, the parked hatch and the open asks', /S3 lands \(2\)/.test(svg) && /⚑D2/.test(svg) && /url\(#tl-hatch\)/.test(svg) && /1\?/.test(svg), svg.length);
    H.go('decide');
    key('?');
    read('? opens the keys sheet', $('#sheet').classList.contains('on') && /\$0\.07e/.test($('#sheet').textContent));
    key('Escape');
    read('esc closes it', !$('#sheet').classList.contains('on'));
    var th = document.documentElement.dataset.theme; key('t');
    read('T flips the theme', document.documentElement.dataset.theme !== th, document.documentElement.dataset.theme); key('t');
    key('g'); key('s');
    read('G then S goes to Ships', $('#main').dataset.view === 'ships', $('#main').dataset.view);
    H.go('decide');
    var docs = $$('#main article.doc');
    H.find('zzz-no-such-word');
    read('find hides what does not match', docs.length && docs.every(function (d) { return d.classList.contains('hid'); }), docs.filter(function (d) { return !d.classList.contains('hid'); }).length + ' shown');
    H.find('');
    read('an empty find shows every doc', docs.every(function (d) { return !d.classList.contains('hid'); }));
    read('no save strip while nothing is unsaved', !$('#savebar').classList.contains('on'));
    var d0 = (S.queue.docs[0] || {}).key;
    H.draft(d0, 'D1', 'B, with a note');
    read('an answer makes the save strip sticky', $('#savebar').classList.contains('dirty') && /1 answer/.test($('#savebar').textContent), $('#savebar').textContent);
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', metaKey: true, bubbles: true }));
    var kept = (H.drafts()[d0] || {}).D1;
    read('Save keeps the answer\'s text and marks its doc saved', kept && kept.text === 'B, with a note' && H.saved()[d0] && H.saved()[d0].at >= kept.at, JSON.stringify(H.drafts()) + ' ' + JSON.stringify(H.saved()));
    read('saved, the strip says so and is no longer sticky', $('#savebar').classList.contains('on') && !$('#savebar').classList.contains('dirty') && /1 answer saved in this browser/.test($('#savebar').textContent), $('#savebar').textContent);
    H.draft(d0, 'D1', '');   // a saved answer cleared is a change to save: the strip stays until a Save takes it
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', metaKey: true, bubbles: true }));
    read('cleared and saved, the strip goes', !$('#savebar').classList.contains('on') && !H.saved()[d0], $('#savebar').className + ' ' + JSON.stringify(H.saved()));
  }

  function round2() {   // round 2: the strip stays, a focused button keeps its focus, a select is typing, the stall count may be unknown
    var S0 = H.S(), waves = $('#strip .waves'), boat = $('#strip .boat'), q1 = clone(S0); q1.as_of += 1; H.apply(q1);
    read('a poll that moves nothing on the strip keeps its waves and boats (their motion goes on)', waves === $('#strip .waves') && boat === $('#strip .boat') && waves.isConnected);
    var tb = $('#strip [data-act="theme"]'), th = document.documentElement.dataset.theme; tb.focus(); tb.click();
    read('the theme button keeps its focus when pressed', document.documentElement.dataset.theme !== th && document.activeElement === tb && tb.isConnected, document.activeElement && document.activeElement.outerHTML.slice(0, 60));
    tb.click(); tb.blur();
    var sel = document.createElement('select'); sel.innerHTML = '<option>A</option><option>B</option>'; $('#main article.doc .card').appendChild(sel); sel.focus();
    th = document.documentElement.dataset.theme; sel.dispatchEvent(new KeyboardEvent('keydown', { key: 't', bubbles: true }));
    read('a key typed into a select fires no shortcut', document.documentElement.dataset.theme === th);
    sel.blur(); sel.remove();
    var q2 = clone(H.S()); q2.as_of += 30; q2.header.stalled = null; H.apply(q2); H.go('fleet');
    read('a stall count the judge could not read says unknown, never 0', /stalls unknown/.test($('#side').textContent) && !/\b0 stalls\b/.test($('#side').textContent), $('#side .watch') && $('#side .watch').textContent);
    H.go('decide');
    // the save strip: a clear or an edit after a Save is unsaved again
    var d0 = H.S().queue.docs[0].key, bar = $('#savebar');
    H.draft(d0, 'D1', 'A'); H.draft(d0, 'D2', 'B'); document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', metaKey: true, bubbles: true }));
    var clean = !bar.classList.contains('dirty');
    H.draft(d0, 'D2', '');
    read('a clear after a Save is unsaved again', clean && bar.classList.contains('dirty'), bar.textContent);
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', metaKey: true, bubbles: true }));
    var clean2 = !bar.classList.contains('dirty'); H.draft(d0, 'D1', 'A, changed');
    read('an edit after a Save is unsaved again, and a Save keeps what it saved', clean2 && bar.classList.contains('dirty') && H.saved()[d0].items.D1 === 'A', JSON.stringify(H.saved()[d0]));
    H.draft(d0, 'D1', '');
    // the theme set from outside (theme.js following the system): the strip's icon follows, read after the observer
    window.__th = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'; document.documentElement.dataset.theme = window.__th;
  }
  function after() {
    var icon = ($('#strip [data-act="theme"] svg') || {}).innerHTML || '';
    read('a theme set from outside redraws the strip\'s icon', (window.__th === 'dark') === /circle/.test(icon), window.__th + ' ' + icon.slice(0, 40));
  }
  function reconcile() {
    var S0 = H.S(), find = $('#side .findin');
    find.focus(); find.value = 'tide'; find.setSelectionRange(1, 3);
    var card = $('#main article.doc .card'), ck = card.getAttribute('data-k');
    var ta = document.createElement('textarea'); ta.setAttribute('data-k', 'answer'); card.appendChild(ta); ta.value = 'A, and keep the old pin';
    var before = $$('#main article.doc').map(function (a) { return a.getAttribute('data-k'); });
    // poll 1: the docs in the other order, a new clock, a count moved
    var S1 = clone(S0); S1.as_of += 30; S1.queue.docs.reverse(); S1.header.needs_owner += 1; H.apply(S1);
    var after = $$('#main article.doc').map(function (a) { return a.getAttribute('data-k'); });
    read('poll 1 reorders the docs', after.join() === before.slice().reverse().join() && after.join() !== before.join(), after.join());
    read('poll 1 keeps the find field focused, its text and selection', document.activeElement === find && find.value === 'tide' && find.selectionStart === 1 && find.selectionEnd === 3,
      (document.activeElement === find) + ' ' + find.value + ' ' + find.selectionStart + '-' + find.selectionEnd);
    read('poll 1 keeps the typed answer in its card', ta.isConnected && ta.value === 'A, and keep the old pin' && ta.parentNode && ta.parentNode.getAttribute('data-k') === ck);
    read('poll 1 draws the new count', ($('#side .vw[data-view="decide"] .vb') || {}).textContent === String(S1.header.needs_owner));
    // poll 2: the doc's items reordered and a card's title changed
    var S2 = clone(S1); S2.as_of += 30; var d = S2.queue.docs.filter(function (x) { return x.items.indexOf(ck) >= 0; })[0]; d.items.reverse();
    S2.columns[0].cards.forEach(function (c) { if (c.key !== ck) c.title += ' (moved)'; }); H.apply(S2);
    read('poll 2 keeps the answer through a reorder of its doc', ta.isConnected && ta.value === 'A, and keep the old pin');
    read('poll 2 draws the changed titles', /\(moved\)/.test($('#main').textContent));
    // poll 3: the card the answer sits in has left the board
    var S3 = clone(S2); S3.as_of += 30; S3.columns[0].cards = S3.columns[0].cards.filter(function (c) { return c.key !== ck; });
    S3.queue.docs.forEach(function (x) { x.items = x.items.filter(function (k) { return k !== ck; }); }); H.apply(S3);
    read('poll 3 keeps a draft whose card left', ta.isConnected && ta.value === 'A, and keep the old pin');
    read('poll 3 still keeps the find field', document.activeElement === find && find.value === 'tide');
    // no draft: a card that left is gone
    find.value = ''; find.blur(); ta.value = ''; var S4 = clone(S3); S4.as_of += 30; H.apply(S4);
    read('with no draft a card that left is removed', !ta.isConnected);
    // a focused link holds nothing: its card is drawn once when its key changes, and a view switch leaves one body
    var link = $('#main article.doc .card a'), lk = link.closest('.card').getAttribute('data-k'), lt = link.closest('.card').querySelector('.t1').textContent;
    link.focus();
    var S5 = clone(S4); S5.as_of += 30; S5.columns[0].cards.forEach(function (c) { if (c.key === lk) c.key = lk + '~2'; });
    S5.queue.docs.forEach(function (x) { x.items = x.items.map(function (k) { return k === lk ? lk + '~2' : k; }); }); H.apply(S5);
    read('a focused link\'s card is drawn once when its key changes', $$('#main .card .t1').filter(function (t) { return t.textContent === lt; }).length === 1,
      $$('#main .card .t1').filter(function (t) { return t.textContent === lt; }).length);
    $('#main article.doc .card a').focus(); key('g'); key('f');
    var bodies = $$('#main > .vbody').filter(function (b) { return !b.hidden; });
    read('a view switch with a focused link leaves one body shown, the new view\'s', bodies.length === 1 && bodies[0].getAttribute('data-k') === 'body-fleet' && !$$('#main article.doc').filter(shown).length,
      bodies.map(function (b) { return b.getAttribute('data-k'); }).join(','));
    H.go('decide');
    var ta2 = document.createElement('textarea'); ta2.setAttribute('data-k', 'answer2'); $('#main article.doc .card').appendChild(ta2); ta2.value = 'kept while away'; ta2.focus();
    H.go('ships');
    bodies = $$('#main > .vbody').filter(function (b) { return !b.hidden; });
    read('a switch away from a typed answer shows the new view alone, the answer kept hidden', bodies.length === 1 && bodies[0].getAttribute('data-k') === 'body-ships' && ta2.isConnected && !shown(ta2),
      bodies.map(function (b) { return b.getAttribute('data-k'); }).join(',') + ' ' + ta2.isConnected);
    H.go('decide');
    read('back on Decide the typed answer is there', ta2.isConnected && shown(ta2) && ta2.value === 'kept while away');
    // a select and a checkbox: a choice holds, an untouched box does not
    var c0 = $('#main article.doc .card'), sel = document.createElement('select'); sel.setAttribute('data-k', 'pick');
    sel.innerHTML = '<option>A</option><option>B</option>'; c0.appendChild(sel); sel.value = 'B';
    var c1 = $$('#main article.doc .card')[1], box = document.createElement('input'); box.type = 'checkbox'; box.setAttribute('data-k', 'box'); c1.appendChild(box);
    ta2.value = ''; ta2.blur(); var S6 = clone(H.S()); S6.as_of += 30; H.apply(S6);
    read('a changed select holds its choice; an untouched checkbox holds nothing', sel.isConnected && sel.value === 'B' && !box.isConnected, sel.isConnected + ' ' + box.isConnected);
    var cs = $$('#main article.doc .card'), us = document.createElement('select'), rg = document.createElement('input');
    us.innerHTML = '<option>A</option><option>B</option>'; cs[2].appendChild(us); rg.type = 'range'; cs[3].appendChild(rg);
    var gone = [cs[2].getAttribute('data-k'), cs[3].getAttribute('data-k')], S7 = clone(H.S()); S7.as_of += 30;
    S7.columns[0].cards = S7.columns[0].cards.filter(function (c) { return gone.indexOf(c.key) < 0; });
    S7.queue.docs.forEach(function (x) { x.items = x.items.filter(function (k) { return gone.indexOf(k) < 0; }); }); H.apply(S7);
    read('an untouched select or range holds nothing: their cards leave', !us.isConnected && !rg.isConnected, us.isConnected + ' ' + rg.isConnected);
    sel.value = 'A';
    round2();
    clicks();
  }
  function clicks() {   // the landing review: a bare [data-view] matched #main and <body>, so every click was a view change
    var seen = null; function spy(e) { seen = e.defaultPrevented; e.preventDefault(); }   // runs after the board's handler; never navigates
    addEventListener('click', spy);
    function click(el) { seen = null; el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })); return seen; }
    var card = $('#main article.doc .card'), ln = document.createElement('a'); ln.href = 'https://example.org/'; ln.target = '_blank'; ln.textContent = 'Course'; card.appendChild(ln);
    read('a card\'s link opens: its click is not taken as a view change', click(ln) === false, seen);
    ln.remove();
    H.go('decide'); key('?'); var h2 = $('#sheet h2') || $('#sheet');
    click(h2); read('a click inside the keys sheet leaves it open', $('#sheet').classList.contains('on'), $('#sheet').className);
    H.go('decide'); $('[data-act="contents"]') ? click($('[data-act="contents"]')) : null; $('#csheet').classList.add('on');
    click($('#csheet .findin')); read('a click on the contents sheet\'s find field leaves it open', $('#csheet').classList.contains('on'), $('#csheet').className);
    H.go('decide'); removeEventListener('click', spy);
    var t0 = Date.now; key('g'); Date.now = function () { return t0.call(Date) + 5000; }; key('f'); Date.now = t0;
    read('a g left waiting goes stale: an f 5 s later stays on Decide', document.body.dataset.view === 'decide', document.body.dataset.view);
  }

  try { if (label === 'reconcile') reconcile(); else shell(); } catch (e) { read('the case ran', false, e && (e.stack || e.message) || e); }
  // the theme's observer runs after this task: read it, then post
  setTimeout(function () {
    try { if (label === 'reconcile') after(); } catch (e) { read('the case ran (after)', false, e && (e.stack || e.message) || e); }
    post();
  }, 60);
})();
