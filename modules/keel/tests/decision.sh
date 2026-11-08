#!/usr/bin/env bash
# helm-ui S8 (docs/helm-board-ux-2026-10-26.md): keel's decision component — decision_html(item, ctx), decision_css(),
# decision_js() — and the Course page drawn through it. Static: one item rendered by the seam and by the page is the
# same markup (the entry's "two renderers drift" check), the tiers, the flag, the hidden answer box Save reads. In
# headless Chrome (a Mac, as keel.sh's browser cases): a case per key, per exclusive pick, the Accept-all guard of
# actions D1 (the owner's C) and the mode switch. Scratch paths only.
#   bash modules/keel/tests/decision.sh
set -u
T=$(mktemp -d); O=$(mktemp -d); trap 'rm -rf "$T" "$O"' EXIT
. "$(dirname "$0")/config.sh"; keel_config "$T/config"
B="$(cd "$(dirname "$0")/../bin" && pwd)"; U="$(cd "$B/../ui" && pwd)"
export MEMO_STATE_DIR="$T/state" KEEL_CACHE_DIR="$T/keel-cache" KEEL_MERMAID_FETCH=0 MEMO_SHEEP_BIN="" MEMO_SHEEP_STATE="$T/sheep"
unset KEEL_UI_DIR
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

cat > "$T/doc.md" <<'EOF'
# A sample design

## Decisions

- **D1 — Where the drainer runs**
  - A — on every host that runs the queue's sweep, after a ten-minute grace
  - B — on the host that holds the worktree, at once
  - C — on GitHub, in an Actions job that commits for the owner

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:

- **D2 — The old answers file**
  - A — keep it
  - B — rewrite it
  - C — leave it
  - D — move it

  Reversible: no

  ➤ Recommended: B

  ➤ Answer:

- **D3 — Who pays the hosting**
  - A — a subscription at $20 a month
  - B — the free tier

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:

- **D4 — When the grace ends**
  - A — ten minutes
  - B — an hour

  Reversible: yes

  ➤ Recommended: A if the probe shows under 3 s, else B

  ➤ Answer:

- **D5 — The receipt's words**
  - A — sent, drained, committed, pushed
  - B — one word, pushed or not

  ➤ Recommended: A

  ➤ Answer:
  B — fewer words

## Open feedback
EOF


echo "the seam"
"$B/keel" build "$T/doc.md" -o "$T/page.html" > /dev/null; check "$?" "0" "the page builds"
check "$(python3 - "$B/keel" "$T/doc.md" "$T/page.html" <<'PY'
import re, sys
from importlib.machinery import SourceFileLoader as L
m = L("m", sys.argv[1]).load_module()
page = open(sys.argv[3]).read()
lines, items, _ = m.parse(open(sys.argv[2]).read())
same = []
for it in items:
    ctx = {"lines": lines, "anchors": {}, "figs": None, "mermaid": {}, "mmd_missed": 0}
    one = m.decision_html(it, ctx)
    same.append(it["id"] if one in page else it["id"] + "≠")
print(" ".join(same))
PY
)" "D1 D2 D3 D4 D5" "each decision the seam draws alone is the page's own markup, unchanged (two renderers never drift)"
check "$(grep -oE 'id="card-D[0-9]" data-id="D[0-9]" data-item data-shape="new" data-tier="[a-z]+" data-cls="[a-z ]*" data-rec="[A-Z]?"' "$T/page.html" | sed -E 's/.*card-(D[0-9]).*tier="([a-z]+)" data-cls="([a-z ]*)" data-rec="([A-Z]?)"/\1:\2:\3:\4/' | tr '\n' ' ')" \
  "D1:safe::A D2:irreversible::B D3:held:money:A D4:yours:conditional: D5:yours:unmarked:A " "the tiers: safe, irreversible, held (money), the owner's for a condition and an unmarked one; a condition names no letter"
has "$T/page.html" '<button type="button" class="opt rec" data-letter="A"><span class="kcw"><span class="kc">A</span><span class="recflag" role="img" title="recommended" data-art="flag"></span></span>' "the recommended flag beside its letter"
has "$T/page.html" '<span class="tier held" title="held — only yolo would take it; your pick asks for its confirm (money)"><span class="tb" data-buoy="held"></span>held · money</span>' "the tier as a buoy and the words"
has "$T/page.html" '<div class="opts grid" role="group" title="Options for D2" style="--cols:2">' "four short options side by side, two across"
has "$T/page.html" '<textarea id="ans-D1" rows="2" hidden></textarea>' "the hidden answer box Save reads, empty"
has "$T/page.html" '<textarea id="free-D5" rows="2" placeholder="In your words — instead of a letter" title="Your answer to D5, in your words">B — fewer words</textarea>' "a worded answer shows in the words row…"
lacks "$T/page.html" 'class="opt pick" data-letter="B"' "…and picks no letter"
has "$T/page.html" '<span>Recommended: A if the probe shows under 3 s, else B <em>— conditional, so no mode takes it</em></span>' "a conditional pick shown whole, said why no mode takes it"
has "$T/page.html" '<div class="cmode" id="modes"><span class="cl">Skipper mode</span>' "the mode switch"
has "$T/page.html" '<div class="takeall" id="takeall" hidden></div>' "Accept all's second question, waiting"
check "$(python3 -c 'import sys; h=open(sys.argv[1]).read(); print(h.index("window.KDC = {}") < h.index("var KDC = window.KDC || {"))' "$T/page.html")" "True" "the component's script before the page's"
"$B/keel" ui list > "$T/list.out"; has "$T/list.out" "decision.js" "keel ui list names the component's files"
AP="$(printf "ar%sa-" i)"   # the accessibility prefix, never written out: the gate's word list holds it
lacks "$U/decision.js" "$AP" "no attribute by the accessibility prefix in the component (the publish gate's trap)"
lacks "$U/decision.css" "$AP" "…nor in its CSS"
cp -R "$U" "$T/ui"; rm "$T/ui/decision.js"
KEEL_UI_DIR="$T/ui" "$B/keel" build "$T/doc.md" -o "$T/bare.html" > /dev/null 2> "$T/bare.err"; check "$?" "0" "a missing component file: the page still builds"
has "$T/bare.err" "without the decision component" "…and says what it went without"
has "$T/bare.html" 'id="save"' "…its Save still there"
has "$T/bare.html" '<textarea id="ans-D1" rows="2" placeholder="A letter, words, or both" title="Your answer to D1">' "…and the answer box itself the field, not hidden"
lacks "$T/bare.html" 'id="free-D1"' "…with no words row nothing would read"
lacks "$T/bare.html" 'id="take-D1"' "…and no Take, nor Accept all, whose guard is the component's"
lacks "$T/bare.html" 'id="acceptall"' "…(Accept all)"

# A doc with no checkout is tiered by its decision lines.
cp "$T/doc.md" "$O/d.md"; "$B/keel" build "$O/d.md" -o "$O/d.html" > /dev/null
check "$(grep -oE 'id="card-D[12]"[^>]*data-tier="[a-z]+"' "$O/d.html" | sed -E 's/.*card-(D[0-9]).*tier="([a-z]+)"/\1:\2/' | tr '\n' ' ')" \
  "D1:safe D2:irreversible " "a doc in no checkout uses its own reversible marks"
check "$(python3 - "$B/keel" "$T/doc.md" <<'PY2'
import sys
from importlib.machinery import SourceFileLoader as L
from unittest.mock import patch
m = L("compat", sys.argv[1]).load_module()
lines, items, _ = m.parse(m.Path(sys.argv[2]).read_text())
with patch.object(m.Path, "read_text", side_effect=AssertionError("contract read")), \
     patch.object(m, "git", side_effect=AssertionError("checkout read")):
    old = m.doc_physical(m.Path("/absent/docs/d.md"))
    print(old == "- physical: none", m.dnd_held(items[0], lines, old) is None,
          m.dnd_held(items[0], lines, object()) is None)
PY2
)" "True True True" "older Wharf's helper and three-argument call stay inert, without reading a checkout or contract"
lacks "$T/page.html" 'id="take-D4"' "no Take on a decision R refuses (the owner's own: conditional)"
lacks "$T/page.html" 'id="take-D5"' "…nor on an unmarked one"
has "$T/page.html" 'id="take-D1"' "…while a plain pick has it"
has "$T/page.html" 'title="yours — dnd holds it; plain yolo takes it (unmarked)"' "an unmarked pick's tier says plain yolo takes it"
check "$(python3 - "$B/keel" <<'PY2'
import sys
from importlib.machinery import SourceFileLoader as L
m = L("m", sys.argv[1]).load_module()
opts = [["A", "one"], ["B", "two"]]
print(" ".join(m.pick_letter({"recommended": r, "options": opts}) or "-" for r in ("B", "B, cheaper", "B.", "**B**", "B — why", "A simple start", "A if X, else B")))
PY2
)" "B B B B B - -" "the recommended letter as yolo reads it: B, B with a comma or a stop, bold B, B — why; never the article A, never a condition"

# the older pre-filled shape keeps its options as anchored lines; a fold reads the pick as plain text
cat > "$T/old.md" <<'EOF'
# Older shapes

- **D1 — Keep both caches**
  - A — keep `--fast` on, per [the note](https://example.com/x) and **always**
  - B — drop one

  ➤ Answer: A — every host, as recommended

- **D2 — Where it runs**
  - A — keep `--fast` on, per [the note](https://example.com/x) and **always**
  - B — elsewhere

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:
EOF
"$B/keel" build "$T/old.md" -o "$T/old.html" > /dev/null
check "$(python3 -c 'import re,sys; h=open(sys.argv[1]).read(); c=re.search(r"<section class=\"dq[^\"]*\" id=\"card-D1\".*?</section>", h, re.S).group(0); print(len(re.findall(r"<div class=\"opt\" data-at=", c)), c.count("data-letter="))' "$T/old.html")" "2 0"   "a pre-filled decision's options stay anchored lines a note can take, never picks that would replace its answer"
has "$T/old.html" '<span class="what">keep --fast on, per the note and always</span>' "a folded decision's pick reads as plain text, its Markdown off"
cat > "$T/two.md" <<'EOF'
# Two runs

- **D1 — Which road**
  - A — the first
  - B — the second

  Reversible: yes

  ➤ Recommended: A

  If A, then which:
  - A — this one
  - B — that one

  ➤ Answer:
EOF
"$B/keel" build "$T/two.md" -o "$T/two.html" > /dev/null
check "$(python3 -c 'import sys; h=open(sys.argv[1]).read(); print(h.count("id=\"free-D1\""), h.index("id=\"free-D1\"") > h.rindex("title=\"Options for D1\""))' "$T/two.html")" "1 True" \
  "options in two runs: one words row, in the last group (the owner's words last)"

CHROME="$(python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; print(L("m", sys.argv[1]).load_module().chrome_path() or "")' "$B/keel" 2>/dev/null)"
# A question with fenced source and code in its options. The selected row changes its text colour;
# source must retain a readable pair, including while that question has the keyboard cursor.
cat > "$T/code.md" <<'EOF'
# Source in a question

- **D1 — Which command keeps the source readable?**

  - A — keep `regatta check` as the command and inspect the whole source block
  - B — use `regatta help` before the next pass

  Reversible: yes

  ➤ Recommended: A

  ➤ Answer:
EOF
"$B/keel" build "$T/code.md" -o "$T/code.html" > /dev/null
# Exercise the component's block styling through the real Markdown renderer. The document parser
# treats a fence as an item's boundary, so feeding it a fence before Recommended would quietly
# turn this into the older, non-selectable shape instead of testing the picked option.
python3 - "$B/keel" "$T/code.html" <<'PY'
import sys
from importlib.machinery import SourceFileLoader as L
m = L("code_render", sys.argv[1]).load_module()
p = sys.argv[2]
h = open(p).read()
source = m.render_md(["```sh", "regatta check", "```"])
open(p, "w").write(h.replace('<div class="dq-ctx body">', '<div class="dq-ctx body">' + source, 1))
PY
has "$T/code.html" 'data-shape="new" data-tier="safe"' "the source case is selectable, not an older pre-filled question"
has "$T/code.html" '<pre><code>regatta check</code></pre>' "fenced source renders inside the question through render_md"
has "$T/code.html" '<span class="ot">keep <code>regatta check</code>' "inline source renders inside an option"
has "$T/code.html" '.dq code, .dq pre { color: var(--ink); background: var(--wash); }' "source carries a text/surface pair independent of the selected row"

# run <name> <probe js>: the page with a probe that writes its log into <pre id="probe">, at 1440 wide, read back
run() {   # run <name> <probe js> [<page>, the suite's page by default]
  python3 - "${3:-$T/page.html}" "$T/$1.html" "$2" <<'PY'
import sys
h = open(sys.argv[1]).read()
probe = "<script>addEventListener('load',function(){var log=[],$=function(i){return document.getElementById(i);};" + sys.argv[3] + \
        "});</script>"
open(sys.argv[2], "w").write(h + probe)
PY
  local ud="$T/ud-$1" end=$((SECONDS + 90)) cp
  "$CHROME" --headless=new --disable-gpu --no-first-run --user-data-dir="$ud" --virtual-time-budget=6000 \
    --window-size=1440,1800 --dump-dom "file://$T/$1.html" 2>/dev/null > "$T/$1.dom" & cp=$!
  while [ "$SECONDS" -lt "$end" ]; do grep -q '</html>' "$T/$1.dom" 2>/dev/null && break; kill -0 "$cp" 2>/dev/null || break; sleep 0.1; done
  kill "$cp" 2>/dev/null; sleep 0.3; kill -0 "$cp" 2>/dev/null && kill -KILL "$cp" 2>/dev/null; wait "$cp" 2>/dev/null
  sed -n 's/.*<pre id="probe">\([^<]*\)<.*/\1/p' "$T/$1.dom"
}
if [ "$(uname -s)" != Darwin ] || [ -z "$CHROME" ] || [ ! -x "$CHROME" ]; then
  echo "  skip the keys in Chrome: no headless Chrome on this Mac, or not a Mac"
else
  echo "code contrast, in Chrome"
  CODE='var lum=function(c){var a=c.match(/[\d.]+/g).slice(0,3).map(function(x){x=+x/255;return x<=.04045?x/12.92:Math.pow((x+.055)/1.055,2.4);});return .2126*a[0]+.7152*a[1]+.0722*a[2];};
    var pair=function(el){var s=getComputedStyle(el),bg=el;while(getComputedStyle(bg).backgroundColor==="rgba(0, 0, 0, 0)")bg=bg.parentElement;
      var a=lum(s.color),b=lum(getComputedStyle(bg).backgroundColor);return (Math.max(a,b)+.05)/(Math.min(a,b)+.05);};
    var bad=[],n=0,s=$("card-D1"),a=s.querySelector("button.opt[data-letter=A]");
    ["light","dark"].forEach(function(t){document.documentElement.dataset.theme=t;
      [false,true].forEach(function(picked){$("ans-D1").value=picked?"A":"";KDC.sync(s);
        [false,true].forEach(function(focus){if(focus)KDC.K.focus(s,"A",false);else KDC.K.release();
          s.querySelectorAll("pre,code").forEach(function(el){n++;if(pair(el)<4.5)bad.push(t+":"+picked+":"+focus+":"+el.tagName);});});});});
    var x=document.createElement("pre");x.id="probe";x.textContent=n+" reads; "+(bad.length?bad.join(","):"all at least 4.5:1");document.body.appendChild(x);'
  out=$(run code "$CODE" "$T/code.html")
  check "$out" "32 reads; all at least 4.5:1" "fenced and inline code: both themes, selected and unselected, focused and released"

  echo "the keys, in Chrome"
  KEYS='var key=function(k,o){var e=new KeyboardEvent("keydown",Object.assign({key:k,bubbles:true,cancelable:true},o||{}));(document.activeElement||document.body).dispatchEvent(e);};
    var at=function(){var s=KDC.K.cur();return (s?s.dataset.id:"-")+":"+(KDC.K.kopt==null?"-":KDC.K.kopt);};
    var v=function(i){return JSON.stringify($("ans-"+i).value);};
    var steps=[
      function(){key("ArrowDown");log.push(at());key("ArrowDown");log.push(at());key("ArrowDown");key("ArrowDown");log.push(at());key("ArrowDown");log.push(at());},
      function(){key("ArrowRight");log.push(at());key("ArrowDown");log.push(at());key("ArrowLeft");log.push(at());key("ArrowUp");log.push(at());key("ArrowUp");log.push(at());},
      function(){key("j");log.push(at());key("k");log.push(at());key("Enter");log.push(at());key("Enter");log.push(v("D1"));},
      function(){log.push(at());key("b");log.push(v("D2")+($("card-D2").classList.contains("confirming")?" asks":" picked"));key("Enter");log.push(v("D2"));},
      function(){KDC.K.focus($("card-D3"),null);key("r");log.push(v("D3")+($("card-D3").classList.contains("confirming")?" asks":""));key("Escape");log.push(v("D3")+($("card-D3").classList.contains("confirming")?" asks":" cancelled"));},
      function(){KDC.K.focus($("card-D4"),null);key("r");log.push(v("D4")+" "+($("status").textContent.indexOf("conditional")>=0?"refused":"taken"));key("a");log.push(v("D4"));},
      function(){KDC.click($("card-D5").querySelector("button.opt[data-letter=A]"));log.push(v("D5")+" "+JSON.stringify($("free-D5").value)+($("free-D5").closest(".opt").classList.contains("pick")?" words":""));
        var f=$("free-D5");f.focus();f.value="my own words";f.dispatchEvent(new Event("input",{bubbles:true}));log.push(v("D5")+($("card-D5").querySelector("button.opt.pick")?" letter":" no letter"));},
      function(){f=$("free-D5");key("Enter");log.push(document.activeElement===f?"typing":"left the words");KDC.K.focus($("card-D1"),null);key("Escape");log.push(at());
        key("Enter",{metaKey:true});log.push($("status").textContent.indexOf("Kept in this browser only")===0?"saved":"not saved: "+$("status").textContent);},
      function(){["D1","D2"].forEach(function(i){$("ans-"+i).value="";KDC.sync($("card-"+i));});KDC.K.focus($("card-D2"),null);key("a");key("ArrowRight");log.push(($("card-D2").classList.contains("confirming")?"asks":"cancelled")+" "+at());
        key("Enter");log.push(v("D2")+" "+(KDC.pending?KDC.pending.letter:"-"));key("Escape");key("Escape");
        var ce=document.createElement("div");ce.contentEditable="true";document.body.appendChild(ce);KDC.K.focus($("card-D1"),null,false);ce.focus();
        var e=new KeyboardEvent("keydown",{key:"b",bubbles:true,cancelable:true});ce.dispatchEvent(e);log.push(v("D1")+" "+(e.defaultPrevented?"taken":"typed"));ce.blur();
        KDC.K.release();var r=new KeyboardEvent("keydown",{key:"ArrowRight",bubbles:true,cancelable:true});document.body.dispatchEvent(r);
        var dn=new KeyboardEvent("keydown",{key:"ArrowDown",bubbles:true,cancelable:true});KDC.K.focus($("card-D5"),"free",false);document.body.dispatchEvent(dn);
        log.push((r.defaultPrevented?"→ taken":"→ left to the page")+" "+(dn.defaultPrevented?"↓ taken":"↓ left to the page"));}
    ];
    var i=0;(function go(){if(i<steps.length){steps[i++]();setTimeout(go,400);return;}var p=document.createElement("pre");p.id="probe";p.textContent=log.join(" | ");document.body.appendChild(p);})();'
  out=$(run keys "$KEYS")
  IFS='|' read -ra got <<< "$out"; g() { echo "${got[$1]}" | sed 's/^ *//; s/ *$//'; }
  check "$(g 0) $(g 1) $(g 2) $(g 3)" "D1:A D1:B D1:free D2:A" "↓ enters the first row, walks a stacked list row by row to the words, and only then on to the next question's first row"
  check "$(g 4) $(g 5) $(g 6) $(g 7) $(g 8)" "D2:B D2:D D2:C D2:A D1:free" "→ ← across a row of side-by-side buttons; ↓ ↑ to the nearest in the next row; ↑ from the first row back to the question before, its last row"
  check "$(g 9) $(g 10) $(g 11) $(g 12)" 'D2:- D1:- D1:A "A"' "J K question to question, nothing ringed; Return rings the recommended, Return again chooses it"
  check "$(g 13) $(g 14) $(g 15)" 'D2:- "" asks "B"' "after a pick the keys go on to the next owed question; B on a one-way decision asks first, Return confirms it"
  check "$(g 16) $(g 17)" '"" asks "" cancelled' "R on a held pick asks first too; Esc cancels and nothing is written"
  check "$(g 18) $(g 19)" '"" refused "A"' "R refuses a conditional pick, saying so; a letter key picks it, the owner's own choice"
  check "$(g 20)" '"A" ""' "a letter picked empties the words (one answer per question)"
  check "$(g 21)" '"my own words" no letter' "words typed unpick the letter at once"
  check "$(g 22) $(g 23)" "left the words -:-" "Return in the words row leaves it, the words kept; Esc lets go of the ring"
  check "$(g 24)" "saved" "⌘↩ saves (a file page has no store: Save's own line, Kept in this browser only)"
  check "$(g 25) $(g 26)" 'cancelled D2:B "" B' "a waiting confirm goes when the ring moves off its option: Return then asks for the ringed one, never confirms the old"
  check "$(g 27)" '"" typed' "a key typed into a contenteditable is typing, never a pick"
  check "$(g 28)" "→ left to the page ↓ left to the page" "with nothing ringed ← → are the page's, and ↓ past the last decision's last row scrolls the page"

  echo "Accept all and the modes, in Chrome"
  GUARD='var v=function(i){return $("ans-"+i).value||"-";};var folded=function(){return KDC.items().filter(function(s){return s.classList.contains("folded");}).map(function(s){return s.dataset.id;}).join(",")||"none";};
    ["auto","dnd","yolo","ask"].forEach(function(m){document.querySelector(".cmode [data-mode="+m+"]").click();log.push(m+"="+folded());});
    $("acceptall").click();log.push(["D1","D2","D3","D4"].map(v).join(","));log.push($("takeall").hidden?"no offer":"offers "+$("takeall").querySelector(".tw b").textContent);
    $("takeall").querySelector("[data-act=takeirr]").click();log.push(v("D2"));log.push($("takeall").hidden?"offer gone":"offer stays");
    $("ans-D2").value="";$("ans-D2").dispatchEvent(new Event("input"));
    KDC.click($("card-D2").querySelector("button.opt[data-letter=B]"));KDC.click($("card-D3").querySelector("button.opt[data-letter=A]"));
    log.push(($("card-D2").classList.contains("confirming")?"D2 asks":"D2 let go")+" "+($("card-D3").classList.contains("confirming")?"D3 asks":"D3 quiet"));
    $("card-D2").querySelector(".confirm [data-act=confirm]").click();log.push(v("D2")+","+v("D3"));
    KDC.K.focus($("card-D1"),"A",false);$("card-D2").querySelector("button.opt[data-letter=C]").focus();var at=function(){var s=KDC.K.cur();return (s?s.dataset.id:"-")+":"+(KDC.K.kopt==null?"-":KDC.K.kopt);};log.push(at());
    document.activeElement.dispatchEvent(new KeyboardEvent("keydown",{key:"ArrowRight",bubbles:true,cancelable:true}));log.push(at());
    var fr=$("card-D2").querySelector(".opt.free");fr.focus();log.push(at()+" "+(document.activeElement===fr?"on the row":"lost"));
    ["D2","D3"].forEach(function(i){$("ans-"+i).value="";$("ans-"+i).dispatchEvent(new Event("input"));});KDC.cancel();
    document.querySelector(".cmode [data-mode=dnd]").click();KDC.K.focus($("card-D2"),null,false);
    var kd=function(k){document.body.dispatchEvent(new KeyboardEvent("keydown",{key:k,bubbles:true,cancelable:true}));};
    kd("b");log.push(v("D2")+" "+($("card-D2").classList.contains("folded")?"folded":"open")+" "+($("card-D2").classList.contains("confirming")?"asks":"quiet"));
    kd("b");log.push(v("D2")+" "+(getComputedStyle($("card-D2").querySelector(".confirm")).display!=="none"?"confirm shown":"confirm hidden"));kd("Enter");log.push(v("D2"));
    var mb=document.querySelector(".cmode [data-mode=ask]");mb.click();mb.focus();kd("j");log.push(document.activeElement===mb?"focus kept on the mode":"focus let go");
    $("acceptall").click();log.push($("status").textContent.indexOf("left for you")>=0?"says what was left":"silent: "+$("status").textContent);
    $("ans-D4").value="A";$("ans-D4").dispatchEvent(new Event("input"));document.querySelector(".cmode [data-mode=yolo]").click();log.push("yolo="+folded());
    $("ans-D4").value="";document.querySelector(".cmode [data-mode=auto]").click();var f1=$("free-D1");$("ans-D1").value="mine";KDC.syncAll();
    KDC.K.focus($("card-D1"),"free",false);f1.focus();f1.value="mine";f1.dispatchEvent(new Event("input",{bubbles:true}));f1.value="";f1.dispatchEvent(new Event("input",{bubbles:true}));
    log.push($("card-D1").classList.contains("folded")?"folded while typing":"fold kept open while typing");
    var p=document.createElement("pre");p.id="probe";p.textContent=log.join(" | ");document.body.appendChild(p);'
  out=$(run guard "$GUARD")
  IFS='|' read -ra got <<< "$out"
  check "$(g 0) $(g 1) $(g 2) $(g 3)" "auto=D1 dnd=D1,D2 yolo=none ask=none" "each mode folds what it takes: auto the safe, dnd the irreversible too; yolo nothing while D4's conditional pick is open, as keel yolo writes nothing"
  check "$(g 18)" "yolo=D3" "…and with D4 answered yolo takes what is open, the held pick too (D1 and D2 are answered by now)"
  check "$(g 19)" "fold kept open while typing" "clearing the words row keeps the card open under the owner's hands"
  check "$(g 4)" "= recommended (accept all),-,-,-" "Accept all takes the safe one-letter pick only: never a one-way, held or conditional one"
  check "$(g 5)" "offers Also the 1 irreversible?" "…then offers the irreversible behind one confirm"
  check "$(g 6) $(g 7)" "= recommended (accept all) offer gone" "…which takes them, marked as Accept all's"
  check "$(g 8)" "D2 let go D3 asks" "one confirm on the page: a second one-way pick lets the first decision's box go"
  check "$(g 9)" "-,-" "…and a confirm button another pick left behind confirms nothing, on either decision"
  check "$(g 10) $(g 11)" "D2:C D2:D" "Tab (the browser's focus) onto an option moves the ring there; the arrows walk on from it"
  check "$(g 12)" "D2:free on the row" "…onto the words row too, the browser's focus kept on it"
  check "$(g 13)" "- open quiet" "a letter on a folded decision only opens it: nothing is asked or picked out of sight"
  check "$(g 14) $(g 15)" "- confirm shown B" "…then the letter asks, its confirm in sight, and Return confirms it"
  check "$(g 16)" "focus let go" "J after a click on a mode lets the button go, so Return reaches the decision, not the mode again"
  check "$(g 17)" "says what was left" "Accept all with nothing safe to take saves nothing and says what it left, and why"

  echo "the bare page and the pre-filled shape, in Chrome"
  out=$(run bare 'var p=function(){var x=document.createElement("pre");x.id="probe";x.textContent=log.join(" | ");document.body.appendChild(x);};
    var err=[];window.addEventListener("error",function(e){err.push(e.message);});
    document.querySelector("#card-D2 button.opt[data-letter=B]").click();log.push($("ans-D2").value);
    $("save").click();setTimeout(function(){log.push($("status").textContent.indexOf("Kept in this browser only")===0?"saved":"not saved");log.push(err.length?"errors: "+err.join("; "):"no errors");p();},300);' "$T/bare.html")
  IFS='|' read -ra got <<< "$out"
  check "$(g 0) $(g 1) $(g 2)" "B saved no errors" "a page without decision.js: a tapped option is its letter, Save saves, and nothing throws"
  out=$(run old 'KDC.K.focus($("card-D1"),null,false);document.body.dispatchEvent(new KeyboardEvent("keydown",{key:"r",bubbles:true,cancelable:true}));
    log.push($("status").textContent.indexOf("pre-filled")>=0?"says pre-filled":"says: "+$("status").textContent);
    var x=document.createElement("pre");x.id="probe";x.textContent=log.join(" | ");document.body.appendChild(x);' "$T/old.html")
  IFS='|' read -ra got <<< "$out"
  check "$(g 0)" "says pre-filled" "R on a pre-filled decision says its answer is the recommendation already"
fi
[ "$fails" -eq 0 ] && { echo "decision: all passed"; exit 0; }
echo "decision: $fails failed"; exit 1
