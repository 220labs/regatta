#!/usr/bin/env bash
# Tests for the helm board's shell (helm-board-ux S3, docs/helm-board-ux-2026-10-26.md): board_page() fills board.html
# with board.css, board.js, keel's foundation and the first snapshot in one pass; without keel or a shell file it is the
# plain page; overview() writes the shell; the header carries the week's ratio. Then, under headless Chrome, the shell at
# 1440, 720 and a true 390 (an iframe of that width: headless Chrome lays a narrower window out at 500), both themes,
# read by tests/board_selftest.js, and the poll's reconcile case: a typed answer and the find field survive three polls,
# a reorder and their card leaving. Without Chrome the render cases say they are skipped; off a Mac too, unless
# HELM_BOARD_ANY_OS=1. No network, no model.
#   bash modules/helm/tests/test_board.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
TD="$(cd "$(dirname "$0")" && pwd)"
export REGATTA_HOME="$(cd "$B/../../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$TD/config_fixture.sh"; fixture_config "$T/config"
export PLANS_DIR="$T/plans" PLAN_HOST=testhost PLAN_PROJECTS_DIR="$T/projects" PLAN_CACHE_DIR="$T/cache" HOME="$T/home" \
  PLAN_NO_GH=1 PLAN_NO_DEPLOY=1 SURFACES_FILE="$T/surfaces.json" ASK_SESSIONS_DIR="$T/sess" ASK_CACHE_DIR="$T/askcache" \
  COST_RATIO="$T/ratio.json" PLAN_NO_MEMO=1 PLAN_PROJECTS_ROOT="$T/projects-root" \
  STALLS_PEERS= STALLS_REPOS= STALLS_ORCA=0 STALLS_CANARY=0 PLAN_NO_WHARF=1 PLAN_NO_HOSTS=1   # test_helm.sh's guards (PLAN_NO_HOSTS: no `hosts --json`, test_engine.sh's): no ssh, no Orca app, no real repo
unset CLAUDE_CONFIG_DIR   # the week line from the moved HOME, never this login's
printf %s "{\"providers\": {\"anthropic\": {\"ratio\": 0.0166, \"week_ending\": \"2026-11-01\"}}}" > "$T/ratio.json"
unset CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS HELM_BOARD_POLL
mkdir -p "$HOME" "$PLANS_DIR" "$PLAN_PROJECTS_DIR"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }

# the fixture: an owner's column of asks in three docs, the other columns with costs, fifteen ships at sea and two home
cat > "$T/fixture.py" <<'PY'
import json, sys, time
sys.path.insert(0, sys.argv[1])
import helm_render as h
def state():
    cols = h.board_columns(); own = cols[0]; now = time.time()
    cards, docs = [], []
    for d, (title, n) in enumerate((("Tide tables for the fleet queue", 3), ("Harbour lights </script><b>x</b> and <!--<script> too", 2), ("{{STATE}} in a title", 2))):
        key = "demo@claude/laptop/2026-11-01-d%d:docs/d%d.md" % (d, d)
        items = []
        for i in range(1, n + 1):
            k = key + "#D%d" % i
            items.append(k)
            cards.append({"column": own, "kind": "ask", "key": k, "title": "D%d of %s" % (i, title), "repo": "demo",
                          "ref": "docs/d%d.md#D%d" % (d, i), "reversible": "no" if i == 2 else "yes", "recommended": "A",
                          "updated": now - 3600 * (d + 1), "github": "https://example.invalid/d%d" % d})
        docs.append({"key": key, "title": title, "repo": "demo", "items": items, "open": n, "rank": d, "why": "oldest first",
                     "oldest": h.helmlib.iso(now - 86400)})
    cards.append({"column": own, "kind": "pr", "key": "pr-1", "title": "A ready pull request", "repo": "demo", "url": "https://example.invalid/pr/1"})
    others = [{"column": "Running", "kind": "task", "title": "S3 the shell", "plan": "board", "cost": 0.7, "est": 0.2},
              {"column": "Blocked", "kind": "task", "title": "S5 waits on D3", "plan": "board", "cost": 0.05, "blockers": ["D3"]},
              {"column": "Done today", "kind": "done", "title": "S2 landed", "plan": "board", "cost": 1.2},
              {"column": "Done today", "kind": "done", "title": "a tiny run", "plan": "board", "cost": 0.00005},
              {"column": "Parked / Relayed", "kind": "task", "title": "S6 parked", "plan": "board", "parked": ["S4", "S5"], "open": 3}]
    columns = [{"name": n, "cards": [c for c in cards + others if c["column"] == n]} for n in cols]
    ships = []
    for i in range(17):
        done = 4 if i >= 15 else i % 4
        bars = [{"id": "s%d" % j, "title": "step %d" % j, "status": "done" if j < done else "running" if j == done else "planned",
                 "start": now - 7200, "end": now + 3600 * j, "cost": 0.3} for j in range(4)]
        ships.append({"id": "ship%d" % i, "plan": "ship %d" % i, "bars": bars, "totals": {"cost": 1.0, "est_to_go": 0.5}})
    # ship 0 carries what the old timeline drew: a milestone, an open ask's flag, a parked hatch, a blocked planned step
    ships[0]["milestones"] = [{"name": "S3 lands", "on": now + 7200, "open": 2}]
    ships[0]["bars"][1]["flags"] = ["D2"]
    ships[0]["bars"][2]["parked_at"] = now - 600
    ships[0]["bars"][3].update(blockers=["D2"], start=now - 7200)
    ships[0]["totals"]["open_asks"] = 1
    return {"kind": "overview", "as_of": now, "host": "laptop", "columns": columns, "timeline": ships,
            "queue": {"docs": docs, "groups": [["land", ["pr-1"]]]}, "later": [],
            "header": {"needs_owner": len([c for c in cards]), "owner": "Sam", "today_cost": 1.2, "week": "week 37% used",
                       "ratio": 0.0166, "sheep": "sheep: paused until 18:00", "talk": "talk: not listening", "stalled": 0}}
if __name__ == "__main__":
    print(json.dumps(state()))
PY
python3 "$T/fixture.py" "$B" > "$T/state.json" || { echo "  FAIL the fixture does not build"; exit 1; }

echo "board_page: one pass over board.html, keel's foundation inlined (S3)"
cat > "$T/page.py" <<'PY'
import json, re, sys, html
sys.path.insert(0, sys.argv[1])
import helm_render as h
st = json.load(open(sys.argv[2]))
p = h.board_page(st, "Helm · board")
snap = re.findall(r'<script type="application/json" id="snapshot">(.*?)</script>', p, re.S)
back = json.loads(snap[0]) if len(snap) == 1 else None
print(re.findall(r"\{\{[A-Z_]+\}\}", p.replace("{{STATE}} in a title", "")) == [],
      '<meta name="ss-streams" content="plans/*">' in p, "window.ART" in p and "window.FX" in p or "FX = window.FX" in p,
      len(snap), back == st, "</script><b>" not in p and "<!--<script>" not in p, "id=\"strip\"" in p and "#savebar" in p)
PY
check "$(python3 "$T/page.py" "$B" "$T/state.json" 2>&1)" "True True True 1 True True True" \
  "every slot filled, the stream meta kept, the foundation in, one snapshot that reads back as the state, a title's </script> and <!--<script> escaped, a {{STATE}} in a title left as text"
cat > "$T/fallback.py" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import helm_render as h
st = json.load(open(sys.argv[2]))
h._KEEL[:] = [None]
a = h.board_page(st, "t")
h._KEEL[:] = []
h.BOARD_FILES = ("board.html", "board.css", "no-such-board.js")
b = h.board_page(st, "t")
print("S.header.ops_stale?'stale':''" in a, "S.header.ops_stale?'stale':''" in b)
PY
out=$(python3 "$T/fallback.py" "$B" "$T/state.json" 2>"$T/fallback.err")
check "$out $(grep -c 'the plain page' "$T/fallback.err")" "True True 2" \
  "no keel, or a shell file that will not read: the plain page, said on stderr at every render, never a traceback"
cat > "$T/overview.py" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1])
import helm_render as h, helmlib
st = h.overview_state()
h.overview()
page = (h.cache_root() / "overview" / "index.html").read_text()
print('id="strip"' in page and 'id="tabbar"' in page, st["header"]["ratio"])
PY
check "$(python3 "$T/overview.py" "$B" 2>&1 | tail -1)" "True 0.0166" \
  "overview() writes the shell; the header's ratio is the core's cost_ratio, read from the suite's ratio file"

echo "the shell under headless Chrome: 1440, 720 and a true 390, both themes; the poll's reconcile"
cat > "$T/frames.py" <<'PY'
import json, os, sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import helm_render as h
k = h._keel()
chrome = k.chrome_path() if k else None
# as keel's ui.sh: a Linux runner's Chrome would judge these frames unseen; HELM_BOARD_ANY_OS=1 asks for them anyway
# (a Linux session with a Chrome of its own, KEEL_CHROME: engine-room S3 ran them so, 184 of 184)
if sys.platform != "darwin" and os.environ.get("HELM_BOARD_ANY_OS") != "1":
    print("SKIP the render cases run on a Mac only (keel's frames do the same; HELM_BOARD_ANY_OS=1 runs them here)")
    sys.exit(0)
if not chrome:
    print("SKIP no headless Chrome here (keel's chrome_path): the render cases are not run")
    sys.exit(0)
work = Path(sys.argv[3]); work.mkdir(parents=True, exist_ok=True)
st = json.load(open(sys.argv[2]))
page = h.board_page(st, "Helm · board")
# each frame its own storage: the frames share file:'s localStorage, and one frame's draft would light another's strip
STUB = ("window.__errs=[];window.onerror=function(m,u,l){window.__errs.push(m+' :'+l)};"
        "(function(){var m={};try{Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:function(k){return k in m?m[k]:null},"
        "setItem:function(k,v){m[k]=String(v)},removeItem:function(k){delete m[k]}}})}catch(e){}})();")
page = page.replace("<head>", "<head><script>" + STUB + "</script>", 1)
page = page.replace("</body>", "<script>" + Path(sys.argv[4]).read_text() + "</script></body>", 1)
(work / "board.html").write_text(page, encoding="utf-8")
runs = [(w, th, "%d-%s" % (w, th)) for th in ("light", "dark") for w in (1440, 720, 390)] + [(1440, "light", "reconcile")]
frames = "".join('<iframe style="width:%dpx;height:900px;border:0" src="board.html?selftest=%s&theme=%s"></iframe>' % (w, lab, th) for w, th, lab in runs)
labels = [lab for _, _, lab in runs]
wrap = ('<!doctype html><meta charset="utf-8"><pre id="out"></pre>%s<script>var got = [], want = %s, end = false;'
        'function done() { if (end) return; end = true; want.forEach(function (l) { got.push({ name: l + ": posted nothing", ok: false,'
        ' got: "a script error or a frame that never loaded" }); }); document.getElementById("out").textContent = JSON.stringify(got); }'
        'addEventListener("message", function (e) { var i = e.data ? want.indexOf(e.data.board) : -1; if (i < 0) return; want.splice(i, 1);'
        ' e.data.out.forEach(function (r) { r.name = e.data.board + ": " + r.name; got.push(r); }); if (!want.length) done(); });'
        ' setTimeout(done, 9000);</script>' % (frames, json.dumps(labels)))
try:
    got = k.chrome_results(chrome, wrap, work, "frames", timeout=int(os.environ.get("HELM_BOARD_CHROME_S") or 150), flags=["--window-size=1500,1000"])
except Exception as e:   # keel's Stop: Chrome never returned
    # keel's ui_check reads a Chrome that never finished as skipped (no window server for this session)
    print(("SKIP " if "did not finish in" in str(e) else "FAIL ") + "headless Chrome: %s" % e)
    sys.exit(0)
if not got:
    print("FAIL headless Chrome wrote no reads")
for r in got or []:
    print(("ok   " if r["ok"] else "FAIL ") + r["name"] + ("" if r["ok"] else ": " + r["got"][:300]))
PY
python3 "$T/frames.py" "$B" "$T/state.json" "$T/frames" "$TD/board_selftest.js" > "$T/frames.out" 2>&1
sed 's/^/  /' "$T/frames.out"
n=$(grep -c '^FAIL' "$T/frames.out"); fails=$((fails+n))
grep -q '^SKIP' "$T/frames.out" || check "$(grep -c '^ok' "$T/frames.out")" "184" \
  "every frame posted every read (27 per shell frame at 1440, 26 at 720 and 390, where the strip drops the host; 26 for the reconcile)"

echo
skipped=$(grep -q "^SKIP" "$T/frames.out" && echo " (the render cases skipped: $(sed -n "s/^SKIP //p" "$T/frames.out" | head -1))")
[ "$fails" = 0 ] && echo "test_board: all passed$skipped" || { echo "test_board: $fails failed"; exit 1; }
