/* art.js — keel's copy of the helm council's round-6 drawings (docs/helm-council-2026-11-01/fable/r6/art.js; helm-ui
   S10), served by keel to the Course page and to helm's board (keel's foundation_js). One change from the prototype:
   a drawing with no title is role="presentation" and one with a title role="img" — no attribute by the accessibility
   prefix, which the publish gate's word list refuses (AGENTS.md's trap). The drawings round 6 added, all in the identity's pen (STYLE.md: a 48 grid, stroke 3, round caps and joins,
   a confident freehand line that is not symmetrical to the decimal, fewer strokes). Every mark here is a function
   that returns an SVG string; make_art.js writes each one to art/ as a file, and `keel ui sheet` shows the whole set on
   one page — never edited there by hand.

   The set:
     buoy(tier, state)   a decision as a buoy: the shape is the tier (safe a round can, irreversible a pointed nun,
                         held a square box, yours a spar with a ball), the colour its tier; taken is a quiet grey
                         outline, picked is the flag's blue with a white flag at the masthead
     pennant(), flag()   a ship's pennant (a swallow-tail that waves) and the recommended flag (a rectangle that waves)
     dueFlag()           the due-date flag on the ladder: a pole with a waving rectangle
     waves(w)            the strip's sea: two hand-drawn swell lines
     sloop()             the regatta-small sloop with a pennant in the ship's hue
     fireworks(hue)      the mark's three bursts as strokes — the woven knot, twelve uneven rays, the four-point
                         star — each with a rocket, drawn to be animated (fx.css) or frozen
     quietNight()        an empty Decide / Reports: a sloop at anchor under a moon and one star
     finishLine()        the finish for a shipped ship: the sloop across the line under the blue flag
     nothingLater()      an empty Later: a buoy with no flag
     noSkippers()        an empty Skippers: a wheel with nobody at it */
(function () {
  'use strict';
  var A = window.ART = {};
  var PEN = 'fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"';
  function svg(vb, w, h, body, cls, title) {
    return '<svg class="art ' + (cls || '') + '" viewBox="' + vb + '" width="' + w + '" height="' + h + '" ' + PEN + ' role="' + (title ? 'img' : 'presentation') + '">' + (title ? '<title>' + String(title).replace(/[&<>]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]; }) + '</title>' : '') + body + '</svg>';
  }

  /* ── the buoys: one shape per tier, so a decision reads without its colour too ── */
  var BODY = {
    // a can buoy: a stout cylinder with rounded shoulders, the mast short, the topmark a ball
    safe: '<path d="M16.4 33 L17.6 15.2 Q24 12.4 30.6 15.6 L31.6 33"/><path d="M24.2 14.6 V7.2"/><circle cx="24.4" cy="5.4" r="2.2"/>',
    // a nun buoy: a cone that narrows to the mast, the topmark a small diamond
    irreversible: '<path d="M14.8 33 L21.2 12.4 L27.4 12.2 L33.4 33"/><path d="M24.3 12 V7.6"/><path d="M24.2 2.4 L27.1 5.3 L24.3 8.2 L21.4 5.4 Z"/>',
    // a box buoy: a square body under a short mast, a square topmark
    held: '<path d="M15.6 33 L16 16.2 L32.2 15.8 L32.6 33"/><path d="M24.1 15.6 V8.4"/><path d="M21.2 3.2 L27.2 3 L27.4 8.2 L21.4 8.4 Z"/>',
    // a spar buoy: a tall pole with a ball on top, a short float at the waterline — the owner's own mark, hollow
    yours: '<path d="M22.6 33 L23.4 12"/><path d="M25.6 33 L24.8 12"/><circle cx="24.2" cy="7.2" r="3.4"/><path d="M19 33 Q24 30.4 29.4 33"/>'
  };
  // the water under every buoy: two short swells, left and right, drawn a little differently each side
  var WATER = '<path d="M5.2 35.4 Q9.4 32 13.8 35.2"/><path d="M34.4 35 Q38.6 38.2 43 35.2"/>';
  var FILLS = { safe: 'safe', irreversible: 'irr', held: 'held', yours: 'yours' };
  A.buoy = function (tier, state, size, title) {
    state = state || tier;
    var cls = 'buoy b-' + tier + ' s-' + state, body = BODY[tier] || BODY.yours;
    if (state === 'picked') body = (BODY[tier] || BODY.safe) + '<path class="bflag" d="M24.4 2.6 C28 1.2 31.6 3.6 35.4 2.2 L35.2 8.4 C31.4 9.8 27.8 7.4 24.4 8.8 Z"/>';
    return svg('0 0 48 48', size || 20, size || 20, body + WATER, cls, title);
  };
  A.TIERS = ['safe', 'irreversible', 'held', 'yours'];

  /* ── flags, drawn by hand: a pennant that waves and a rectangle flag on a pole ── */
  // a ship's pennant: the swallow-tail off a short pole, its edges wavy as cloth is
  A.pennant = function (size) {
    return svg('0 0 24 24', size || 12, size || 12, '<path d="M4.2 2.6 V21.6"/><path d="M5 4.2 C9.4 2.4 14.2 5.8 20.8 3.6 L17.2 9.6 L21 15.2 C14.4 13.4 9.6 16.8 5 15 Z" fill="currentColor" stroke-width="2.4"/>', 'pennant');
  };
  // the recommended flag: a rectangle on a pole, the fly end waving — filled, as the race committee's blue flag is
  A.flag = function (size) {
    return svg('0 0 24 24', size || 12, size || 12, '<path d="M4.6 2.4 V21.8"/><path d="M5.4 4 C10 2.2 14.6 6 20.6 3.8 L20.2 13.4 C14.4 15.6 9.8 11.8 5.4 13.6 Z" fill="currentColor" stroke-width="2.4"/>', 'flag');
  };
  // the due flag on the ladder: a pole with a small waving rectangle at its head
  A.dueFlag = function (size) {
    return svg('0 0 24 36', size || 12, (size || 12) * 1.5, '<path d="M4.4 2.6 V34"/><path d="M5.2 4.2 C9.8 2.4 14.4 6.2 20.4 4 L20 13.2 C14.2 15.4 9.6 11.6 5.2 13.4 Z" fill="currentColor" stroke-width="2.4"/>', 'dueflag');
  };

  /* ── the sea in the strip: two hand-drawn swell lines, each a repeat of 240 units so it can drift ── */
  function swell(y, amp, seed) {
    var d = 'M0 ' + y, x = 0, r = seed;
    function rnd() { r = (r * 1103515245 + 12345) & 0x7fffffff; return r / 0x7fffffff; }
    while (x < 480) {
      var w = 22 + rnd() * 16, a = amp * (0.6 + rnd() * 0.8);
      d += ' q' + (w / 2).toFixed(1) + ' ' + (-a).toFixed(1) + ' ' + w.toFixed(1) + ' 0';
      x += w;
    }
    return d;
  }
  A.waves = function () {
    // the far swell sits higher and fainter; the near one lower and bolder; both drawn twice, end to end, so a drift
    // of half their width loops without a seam
    var far = swell(6, 2.2, 7), near = swell(13, 3.4, 23);
    return '<svg class="waves" viewBox="0 0 480 20" preserveAspectRatio="none" fill="none" stroke-linecap="round" role="presentation">' +
      '<g class="w far" stroke-width="1.4"><path d="' + far + '"/><path transform="translate(480 0)" d="' + far + '"/></g>' +
      '<g class="w near" stroke-width="1.8"><path d="' + near + '"/><path transform="translate(480 0)" d="' + near + '"/></g></svg>';
  };

  /* ── the sloop (regatta-small, the identity's own) with a pennant in the ship's hue at the masthead ── */
  A.sloop = function (size) {
    return svg('0 0 48 48', size || 22, size || 22,
      '<path class="pen" d="M19 13.4 C22.4 11.6 25.6 14.4 29.6 12.6 L29.2 17.4 C25.4 19 22.2 16.4 19 18 Z" fill="var(--hue, currentColor)" stroke="var(--hue, currentColor)" stroke-width="2.2"/>' +
      '<path d="M18.9 36.3 L18.9 15.3 Q12.3 23.1 8.1 30.3 L17.1 30.3"/><path d="M21.9 18.3 Q28.5 24.3 31.5 30.3 L22.5 30.3"/><path d="M4.5 36.3 L39.3 36.3 Q35.7 43.5 14.1 43.5 Q8.1 42.9 5.46 39.9"/>', 'sloop');
  };

  /* ── the fireworks: the mark's three bursts, as strokes, each on its own rocket ── */
  // the woven knot: six sticks round a six-sided hole, each run on past its corner (STYLE.md), with uneven lengths
  function knot(R) {
    var d = '', D = Math.PI / 180;
    for (var k = 0; k < 6; k++) {
      var th = (60 * k - 90) * D, x0 = R * 0.42 * Math.cos(th), y0 = R * 0.42 * Math.sin(th), dir = th + 120 * D;
      var len = R * (0.92 + ((k * 7) % 3) * 0.06), x1 = x0 + len * Math.cos(dir), y1 = y0 + len * Math.sin(dir);
      var x2 = x0 - R * 0.1 * Math.cos(dir), y2 = y0 - R * 0.1 * Math.sin(dir);
      d += '<path d="M' + x2.toFixed(1) + ' ' + y2.toFixed(1) + ' L' + x1.toFixed(1) + ' ' + y1.toFixed(1) + '"/>';
    }
    return d;
  }
  // twelve rays of uneven length round a small core, as the mark's burst has them
  var RAYS = [[-90, 1], [-62, .74], [-34, .92], [-6, .66], [22, .9], [50, .7], [78, .96], [106, .72], [134, .88], [162, .68], [190, .94], [218, .7], [246, .86], [274, .76]];
  function rays(R) {
    var d = '<circle cx="0" cy="0" r="' + (R * 0.14).toFixed(1) + '" fill="currentColor" stroke="none"/>';
    RAYS.forEach(function (r) { var a = r[0] * Math.PI / 180, i = R * 0.3, o = R * r[1]; d += '<path d="M' + (i * Math.cos(a)).toFixed(1) + ' ' + (i * Math.sin(a)).toFixed(1) + ' L' + (o * Math.cos(a)).toFixed(1) + ' ' + (o * Math.sin(a)).toFixed(1) + '"/>'; });
    return d;
  }
  // the four-point star, its sides curved in; the top point a touch longer, as a hand draws it
  function star(R) {
    var a = R, b = R * 0.3;
    return '<path d="M0 ' + (-a * 1.06).toFixed(1) + ' Q' + b.toFixed(1) + ' ' + (-b).toFixed(1) + ' ' + a.toFixed(1) + ' 0 Q' + b.toFixed(1) + ' ' + b.toFixed(1) + ' 0 ' + a.toFixed(1) + ' Q' + (-b).toFixed(1) + ' ' + b.toFixed(1) + ' ' + (-a * 0.98).toFixed(1) + ' 0 Q' + (-b).toFixed(1) + ' ' + (-b).toFixed(1) + ' 0 ' + (-a * 1.06).toFixed(1) + ' Z"/>';
  }
  // sparks that fall from a burst: eight short strokes at the rim, each with its own fall
  function sparks(R, n) {
    var d = '';
    for (var i = 0; i < n; i++) { var a = (i / n) * 6.283 + 0.3, x = R * Math.cos(a), y = R * Math.sin(a); d += '<path class="spark" style="--i:' + i + '" d="M' + x.toFixed(1) + ' ' + y.toFixed(1) + ' l' + (Math.cos(a) * 4).toFixed(1) + ' ' + (Math.sin(a) * 4 + 2).toFixed(1) + '"/>'; }
    return d;
  }
  /* one burst: a rocket that rises from (x, y0) to (x, y), then the shape opening at (x, y); every animated part
     carries --d, its own delay from the show's start, so fx.css can play it or freeze it at any instant */
  function burst(kind, x, y, y0, R, delay, color) {
    var shape = (kind === 'knot' ? knot(R) : kind === 'rays' ? rays(R) : star(R)).replace(/<path /g, '<path pathLength="1" ');
    return '<g class="burst k-' + kind + '" style="--d:' + delay + 'ms;color:' + color + '">' +
      '<path class="rocket" pathLength="1" d="M' + x + ' ' + y0 + ' Q' + (x + (kind === 'rays' ? -6 : 7)) + ' ' + ((y0 + y) / 2) + ' ' + x + ' ' + (y + 4) + '" stroke-width="2.2"/>' +
      '<g class="at" transform="translate(' + x + ' ' + y + ')"><g class="shape"><g class="open">' + shape + '</g>' + sparks(R * 1.02, 8) + '</g></g></g>';
  }
  A.fireworks = function (hue, w, h) {
    // three bursts across the sky over the title: the knot left, the rays in the middle and highest, the star right
    w = w || 720; h = h || 260;
    var c = [hue || 'var(--hue-violet)', 'var(--fire)', 'var(--hue-violet)'];
    return '<svg class="fw" viewBox="0 0 ' + w + ' ' + h + '" width="' + w + '" height="' + h + '" ' + PEN + ' role="presentation">' +
      burst('knot', Math.round(w * 0.28), 112, h, 54, 0, c[0]) + burst('rays', Math.round(w * 0.52), 78, h, 66, 260, c[1]) + burst('star', Math.round(w * 0.74), 124, h, 46, 520, c[2]) + '</svg>';
  };
  // the same three bursts still, small, for a shipped ship's badge and the reduced-motion case
  A.burstMark = function (size) {
    return svg('-30 -30 60 60', size || 22, size || 22, '<g transform="scale(.42)">' + rays(40) + '</g>', 'burstmark');
  };

  /* ── empty states ── */
  // a quiet night: the sloop at anchor, sails down, under a moon and one star; the water flat
  A.quietNight = function (size) {
    return svg('0 0 96 48', (size || 48) * 2, size || 48,
      '<path d="M30 36.4 L64.6 36.4 Q61 43.4 40 43.4 Q33.8 42.8 31 39.8"/><path d="M46.2 36.4 V14.6"/><path d="M46.2 14.6 L52 22.4 L46.6 22.6"/>' +
      '<path d="M46.2 36.4 Q42 39.6 38.4 43.2" stroke-dasharray="1 5"/>' +
      '<path d="M80.4 8.2 A8.2 8.2 0 1 0 88.2 19 A6.4 6.4 0 1 1 80.4 8.2 Z"/>' +
      '<path d="M14 11 L14.6 14.2 L17.8 14.8 L14.6 15.4 L14 18.6 L13.4 15.4 L10.2 14.8 L13.4 14.2 Z" fill="currentColor" stroke="none"/>' +
      '<path d="M4 41.6 Q10 39.2 16.4 41.6"/><path d="M70 42 Q76.8 44.6 84 42"/>', 'quietnight');
  };
  // the finish: the sloop across the line under the blue flag, the line a dotted vertical behind it
  A.finishLine = function (size) {
    return svg('0 0 72 48', (size || 48) * 1.5, size || 48,
      '<path d="M58 4 V44" stroke-dasharray="2 6"/><path class="blueflag" d="M58 6 Q61 5.2 64 6.4 L63.8 13.2 Q61 12.4 58 13 Z" fill="var(--flag)" stroke="none"/>' +
      '<path d="M21 36.3 L21 15.3 Q14.4 23.1 10.2 30.3 L19.2 30.3"/><path d="M24 18.3 Q30.6 24.3 33.6 30.3 L24.6 30.3"/><path d="M6.6 36.3 L41.4 36.3 Q37.8 43.5 16.2 43.5 Q10.2 42.9 7.56 39.9"/>' +
      '<g transform="translate(40 10) scale(.22)">' + rays(40) + '</g>', 'finishline');
  };
  // Later, empty: a buoy with nothing tied to it
  A.nothingLater = function (size) { return svg('0 0 48 48', size || 40, size || 40, BODY.safe + WATER, 'buoy empty'); };
  // Skippers, empty: the wheel with no hand on it, the water under it
  A.noSkippers = function (size) {
    return svg('0 0 48 48', size || 40, size || 40, '<path d="M28.68 13.49 A11.5 11.5 0 1 1 25.2 12.56"/><path d="M24.16 19.5 L24.65 5.41"/><path d="M31.99 15.73 L36.09 11.48"/><path d="M28.5 23.92 L42.5 23.68"/><path d="M31.84 32.41 L36 36.87"/><path d="M24.08 28.5 L24.32 42.2"/><path d="M16.01 32.27 L11.64 36.8"/><path d="M19.5 23.84 L5.61 23.36"/><path d="M15.73 16.01 L11.56 11.98"/>', 'noskippers');
  };
  // the Embark memo's own mark: a sealed letter with a wave under it (the memo arrives by the week's tide)
  A.memo = function (size) {
    return svg('0 0 48 48', size || 28, size || 28, '<path d="M8.4 12.6 L39.2 11.8 L39.8 31.4 L9 32.2 Z"/><path d="M9.2 13.4 L24 23.6 L39 12.4"/><path d="M5 40.4 Q11 37.2 17.2 40.4 T29.6 40.4 T42 40.4"/>', 'memo');
  };

  /* the sheet: every drawing above, at three sizes, on paper and on ink (`keel ui sheet` shows them) */
  A.sheet = function () {
    var rows = [];
    A.TIERS.forEach(function (t) { rows.push(['buoy · ' + t, A.buoy(t, t, 48), A.buoy(t, t, 24), A.buoy(t, t, 16)]); });
    rows.push(['buoy · taken', A.buoy('safe', 'taken', 48), A.buoy('safe', 'taken', 24), A.buoy('safe', 'taken', 16)]);
    rows.push(['buoy · picked', A.buoy('safe', 'picked', 48), A.buoy('safe', 'picked', 24), A.buoy('safe', 'picked', 16)]);
    rows.push(['pennant', A.pennant(48), A.pennant(24), A.pennant(12)], ['flag', A.flag(48), A.flag(24), A.flag(12)], ['due flag', A.dueFlag(32), A.dueFlag(16), A.dueFlag(10)]);
    rows.push(['sloop', A.sloop(48), A.sloop(24), A.sloop(16)], ['burst mark', A.burstMark(48), A.burstMark(24), A.burstMark(16)]);
    rows.push(['quiet night', A.quietNight(64), A.quietNight(40), A.quietNight(24)], ['finish line', A.finishLine(64), A.finishLine(40), A.finishLine(24)]);
    rows.push(['nothing later', A.nothingLater(48), A.nothingLater(32), A.nothingLater(20)], ['no skippers', A.noSkippers(48), A.noSkippers(32), A.noSkippers(20)], ['memo', A.memo(48), A.memo(28), A.memo(16)]);
    return rows;
  };
})();
