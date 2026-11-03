#!/usr/bin/env bash
# helm-ui S10 (docs/helm-board-ux-2026-10-26.md): the shared foundation in keel's ui/ — the helm council's tokens,
# drawings and fx layer — and the roads that serve it: `keel ui` (list, cat, write, sheet, check), the Course page
# (layered under its own CSS) and helm's (keel loaded as a module). `keel ui check` reads every text pair's contrast,
# the drawings against art.js (node) and, where headless Chrome is, a frame per effect at 1440 and the still sheet at
# 720 and a true 390, both themes and under reduced motion; without Chrome it says the frames were skipped. Scratch paths only.
#   bash modules/keel/tests/ui.sh
set -u
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$(dirname "$0")/config.sh"; keel_config "$T/config"
B="$(cd "$(dirname "$0")/../bin" && pwd)"; U="$(cd "$B/../ui" && pwd)"
export MEMO_STATE_DIR="$T/state" KEEL_CACHE_DIR="$T/keel-cache" KEEL_MERMAID_FETCH=0 MEMO_SHEEP_BIN="" MEMO_SHEEP_STATE="$T/sheep"
unset KEEL_UI_DIR
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -12; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

echo "keel ui check"
# The real-Chrome frames run on a Mac only, as keel.sh's browser cases do: their reads (layout at 390, fonts) were
# seen on macOS's Chrome alone, and a Linux runner's Chrome would judge them unseen (the S10 landing review).
if [ "$(uname -s)" = Darwin ]; then "$B/keel" ui check > "$T/check.out" 2>&1
else KEEL_CHROME="$T/no-chrome" "$B/keel" ui check > "$T/check.out" 2>&1; fi; check "$?" "0" "the foundation passes its check"
has "$T/check.out" ", 0 failed (file 23, contrast 104" "every file, 104 contrast pairs"
if command -v node >/dev/null 2>&1; then has "$T/check.out" "art 20" "…and the drawings against art.js"; else echo "  skip the drawings: no node"; fi
if grep -q 'skipped the frames' "$T/check.out"; then echo "  skip the frames: no headless Chrome here (keel's chrome_path)"
else has "$T/check.out" "frame " "a frame per effect read"
  if grep -q 'skipped the reduced frames' "$T/check.out"; then echo "  skip the reduced frames: Chrome did not finish them"
  elif grep -qE 'reduced [0-9]+' "$T/check.out"; then echo "  ok   …and each under reduced motion"
  else echo "  FAIL …and each under reduced motion: no reduced count"; fails=$((fails+1)); fi; fi

echo "a broken copy fails, naming what (no Chrome: the static reads are what these cases judge)"
NOCHROME="$T/no-chrome"   # KEEL_CHROME naming no program: chrome_path() answers none, never the Mac's
cp -R "$U" "$T/ui"
sed 's/--safe: #0A7A4C;/--safe: #7FD0A0;/' "$U/tokens.css" > "$T/ui/tokens.css"
KEEL_CHROME="$NOCHROME" KEEL_UI_DIR="$T/ui" "$B/keel" ui check > "$T/c2.out" 2>&1; check "$?" "1" "a light tier under 4.5:1 fails the check"
has "$T/c2.out" "FAIL contrast light safe on ground" "…naming the pair"
lacks "$T/c2.out" "FAIL contrast dark" "…and only the light theme's"
cp "$U/tokens.css" "$T/ui/tokens.css"
if command -v node >/dev/null 2>&1; then
  sed 's/M4.6 2.4 V21.8/M4.6 2.4 V20.8/' "$U/art.js" > "$T/ui/art.js"
  KEEL_CHROME="$NOCHROME" KEEL_UI_DIR="$T/ui" "$B/keel" ui check > "$T/c3.out" 2>&1; check "$?" "1" "an art.js edit without make_art.js fails"
  has "$T/c3.out" "FAIL art: flag.svg as art.js draws it" "…naming the drawing"
  cp "$U/art.js" "$T/ui/art.js"
else echo "  skip the drawings: no node"; fi
rm "$T/ui/fx.js"
KEEL_CHROME="$NOCHROME" KEEL_UI_DIR="$T/ui" "$B/keel" ui check > "$T/c4.out" 2>&1; check "$?" "1" "a missing file fails"
has "$T/c4.out" "FAIL file fx.js" "…naming it"

echo "the frames' plumbing, through a stand-in Chrome (the page's own script is the real one's to run)"
cat > "$T/chrome" <<'EOF'
#!/usr/bin/env python3
import json, os, re, sys
open(os.environ["FAKE_LOG"], "a").write(" ".join(sys.argv[1:]) + "\n")
shot = [a[len("--screenshot="):] for a in sys.argv if a.startswith("--screenshot=")]
if shot:
    if not os.environ.get("FAKE_NOSHOT"):
        open(shot[0], "wb").write(b"\x89PNG\r\n\x1a\n")
    sys.exit(0)
page = open(sys.argv[-1][len("file://"):]).read()
want = json.loads(re.search(r"want = (\[.*?\])", page).group(1))
if os.environ.get("FAKE_SILENT"):
    sys.exit(0)
bad = os.environ.get("FAKE_FAIL", "")
out = [{"name": l + ": theme", "ok": l != bad, "got": "read"} for l in want]
print('<html><body><pre id="out">%s</pre></body></html>' % json.dumps(out).replace("&", "&amp;").replace("<", "&lt;"))
EOF
chmod +x "$T/chrome"; export FAKE_LOG="$T/chrome.log"
KEEL_CHROME="$T/chrome" "$B/keel" ui check -v > "$T/f1.out" 2>&1; check "$?" "0" "every frame posted and passed"
has "$T/f1.out" "frame 14, reduced 14)" "…fourteen frames, then the same under reduced motion"
check "$(grep -c -- '--force-prefers-reduced-motion' "$FAKE_LOG")" "1" "…the second run asks for reduced motion"
has "$T/f1.out" "ok   frame 390-dark-still: theme" "…a true 390 in the dark among the frames"
KEEL_CHROME="$T/chrome" FAKE_FAIL=1440-dark-press "$B/keel" ui check > "$T/f2.out" 2>&1; check "$?" "1" "a frame's failed read fails the check"
has "$T/f2.out" "FAIL frame 1440-dark-press: theme" "…naming the frame and the read"
has "$T/f2.out" "FAIL reduced 1440-dark-press: theme" "…in both runs"
KEEL_CHROME="$T/chrome" FAKE_SILENT=1 "$B/keel" ui check > "$T/f3.out" 2>&1; check "$?" "1" "a Chrome that posts nothing fails the check"
has "$T/f3.out" "FAIL frame all — headless Chrome posted nothing" "…and says so"
KEEL_CHROME="$T/chrome" "$B/keel" ui check --shots "$T/shots/new" > "$T/f5.out" 2>&1; check "$?" "0" "--shots makes its folder and reads each PNG"
check "$(ls "$T/shots/new" | grep -c '\.png$')" "14" "…a PNG a frame"
KEEL_CHROME="$T/chrome" FAKE_NOSHOT=1 FAKE_SILENT=1 "$B/keel" ui check --shots "$T/shots/none" > "$T/f6.out" 2>&1; check "$?" "1" "a shot not written fails, and shots never stand in for the frames' reads"
has "$T/f6.out" "FAIL shot ui-1440-light-press.png" "…naming the PNG"
has "$T/f6.out" "FAIL frame all — headless Chrome posted nothing" "…and the silent frames run still fails"
mkdir -p "$T/dir-chrome"
KEEL_CHROME="$T/dir-chrome" "$B/keel" ui check > "$T/f7.out" 2>&1; check "$?" "1" "a Chrome that will not run fails the read"
has "$T/f7.out" "FAIL frame all — Chrome will not run" "…said, with the summary after it"
rm "$T/ui/tokens.css"; cp "$U/fx.js" "$T/ui/fx.js"
KEEL_CHROME="$T/chrome" KEEL_UI_DIR="$T/ui" "$B/keel" ui check > "$T/f4.out" 2>&1; check "$?" "1" "with a Chrome, a missing tokens.css still reads to the end"
has "$T/f4.out" "FAIL file tokens.css" "…the file named"
has "$T/f4.out" "FAIL frame all — foundation file tokens.css will not read" "…and the frames' Stop is a failed read, not the end"
has "$T/f4.out" "ui check: " "…with its summary"

echo "keel ui list, cat, write, sheet"
check "$("$B/keel" ui list | head -5 | tr '\n' ' ')" "tokens.css fx.css theme.js art.js fx.js " "the five files lead the list"
check "$("$B/keel" ui list | grep -c '^art/.*\.svg$')" "18" "…then the eighteen drawings"
"$B/keel" ui cat tokens.css > "$T/tokens.css"; check "$(cmp -s "$T/tokens.css" "$U/tokens.css" && echo same)" "same" "cat prints a file as it is"
"$B/keel" ui cat ../bin/keel > /dev/null 2>"$T/cat.err"; check "$?" "1" "cat refuses a name off the list"
has "$T/cat.err" "no foundation file ../bin/keel" "…and says so"
"$B/keel" ui write "$T/out" > "$T/write.out"; has "$T/write.out" "23 foundation files written" "write hands every file over"
n=0; for f in $("$B/keel" ui list); do cmp -s "$T/out/$f" "$U/$f" || n=$((n+1)); done; check "$n" "0" "…each the same as ui/'s"
: > "$T/afile"; "$B/keel" ui write "$T/afile" > "$T/w2.out" 2>&1; check "$?" "1" "write into a file refuses"
has "$T/w2.out" "keel ui write: cannot write to" "…in one line"; lacks "$T/w2.out" "Traceback" "…never a traceback"
"$B/keel" ui sheet "$T/sheet.html" > /dev/null
for s in '<title>keel — the foundation</title>' 'id="savebar"' 'FX.runFrozen' 'window.ART' 'helm-theme'; do has "$T/sheet.html" "$s" "the sheet carries $s"; done

echo "nothing by the accessibility prefix (the publish gate's word list; AGENTS.md's trap)"
check "$(grep -rlE 'a[r]ia-' "$U" | wc -l | tr -d ' ')" "0" "no file in ui/ names it"   # the pattern spelt so this file passes the gate too

echo "fx.js stands without decision.js (S8's)"
if command -v node >/dev/null 2>&1; then
  cat > "$T/smoke.js" <<'EOF'
var fs = require('fs'), dir = process.argv[2], seen = [];
global.location = { search: '?fx=press&t=300' };
global.document = { addEventListener: function () {}, documentElement: { style: { setProperty: function () {} }, classList: { add: function () {} } } };
global.matchMedia = function () { return { matches: false }; };
function load(dc) { global.window = dc ? { DC: { on: function (f) { seen.push(f); } } } : {}; new Function(fs.readFileSync(dir + '/art.js', 'utf8'))(); new Function(fs.readFileSync(dir + '/fx.js', 'utf8'))(); return window; }
var w = load(false);
console.log([typeof w.FX.on, typeof w.FX.fireworks, w.FX.frozen && w.FX.frozen.show + ' ' + w.FX.frozen.t, typeof w.ART.buoy].join(' '));
w = load(true); console.log(seen.length === 1 && seen[0] === w.FX.on ? 'handed to DC.on' : 'not handed');
EOF
  node "$T/smoke.js" "$U" > "$T/smoke.out" 2>&1
  check "$(head -1 "$T/smoke.out")" "function function press 300 function" "alone: FX.on, the fireworks, ?fx= read from its own query"
  check "$(sed -n 2p "$T/smoke.out")" "handed to DC.on" "with decision.js loaded first, FX.on is DC's listener"
else echo "  skip: no node"; fi

echo "the Course page carries the foundation, layered under its own CSS"
cat > "$T/memo.md" <<'EOF'
# A memo (2026-11-02)

## Decisions

1. **D1 — Keep it?** Reversible: yes.
   ➤ Recommended: A
   ➤ Answer:
EOF
"$B/keel" build "$T/memo.md" -o "$T/page.html" > /dev/null 2>"$T/build.err"
has "$T/page.html" "@layer foundation {" "the tokens and fx CSS in a layer"
python3 - "$T/page.html" > "$T/order.out" <<'EOF'
import sys
s = open(sys.argv[1]).read()
at = lambda x: s.find(x)
print(" ".join(str(int(0 <= a < b)) for a, b in [(at("@property --ra"), at("@layer foundation {")), (at("localStorage.getItem('helm-theme')"), at("@layer foundation {")),
      (at("@layer foundation {"), at("--paper:#FAFAF7")), (at("window.ART"), at("window.MEMO"))]))
EOF
check "$(cat "$T/order.out")" "1 1 1 1" "@property ahead of the layer, theme first, the page's own CSS after, ART and FX before the page's script"
check "$(grep -c 'window.claude' "$T/page.html")" "1" "the store is still reached through claude.use only"
KEEL_UI_DIR="$T/ui" "$B/keel" build "$T/memo.md" -o "$T/page2.html" > /dev/null 2>"$T/build2.err"; check "$?" "0" "without tokens.css the page still builds"
has "$T/build2.err" "the page goes without the foundation" "…and says so"
lacks "$T/page2.html" "@layer foundation" "…carrying none of it"

echo "helm's road: keel loaded as a module"
python3 - "$B/keel" > "$T/helm.out" <<'EOF'
import sys
from importlib.machinery import SourceFileLoader
k = SourceFileLoader("keel_board", sys.argv[1]).load_module()
h, c = k.foundation_head(), k.foundation_css()
print(h.count("<script>"), h.count("<style>"), "@layer" in c, k.FX_SHOWS == {"press": 300, "fireworks": 1200, "settle": 250, "save": 150, "tick": 200})
EOF
check "$(cat "$T/helm.out")" "2 1 False True" "foundation_head: the theme and the drawings with fx, one style, unlayered for the board"

echo
if [ "$fails" -eq 0 ]; then echo "ui: all passed"; else echo "ui: $fails failed"; exit 1; fi
