/* theme.js — the theme before first paint, as the helm council's round-6 page heads set it (helm-ui S10): ?theme=, a
   stored choice (`helm-theme`), else the system's, which it follows while nothing chose. A theme the host already set
   on <html> stands. tokens.css's dark set is keyed on data-theme alone, so every page that takes the foundation runs
   this first (keel's foundation_head). */
(function () {
  var r = document.documentElement, q = new URLSearchParams(location.search || window.__q || ''), t = q.get('theme');
  var m = matchMedia('(prefers-color-scheme: dark)'), ok = function (x) { return x === 'light' || x === 'dark'; };
  var stored = function () { try { return localStorage.getItem('helm-theme'); } catch (e) { return null; } };
  if (r.dataset.theme) return;
  if (!ok(t)) t = stored();
  if (!ok(t)) {
    t = m.matches ? 'dark' : 'light';
    if (m.addEventListener) m.addEventListener('change', function (e) {   // only while the page still wears what this wrote
      if (!ok(stored()) && r.dataset.theme === t) r.dataset.theme = t = e.matches ? 'dark' : 'light';
    });
  }
  r.dataset.theme = t;
})();
