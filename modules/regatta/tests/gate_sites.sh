#!/usr/bin/env bash
# Every gate call site the modules name has a row in the module's table (Evolve S11; before it nine of fifteen
# had none, and a stranger's install met "no row for <site>" at each: docs/self-improvement-2026-10-30/probes/
# gate-sites.txt). gate_sites.py finds the sites by an AST walk, never a regex: a name in a comment or a docstring
# is no site. This suite proves the walk on a made-up tree, then walks the real one and resolves each site under an
# empty config dir with every GATE_* variable cleared, so only the table beside the gate answers. An `off` row is a
# row. Reads the tree; writes only a scratch folder. check.sh runs it, as it runs classes.sh.
#   bash modules/regatta/tests/gate_sites.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$M/../.." && pwd)"
W="$M/tests/gate_sites.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(GATE_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3"; echo "       got:  $1"; echo "       want: $2"; fails=$((fails+1)); fi; }
walk() { python3 -I "$W" "$@" 2>&1; }

echo "the walk, on a made-up tree"
F="$T/fx"; mkdir -p "$F/modules/a/bin" "$F/modules/a/lib" "$F/modules/a/tests" "$F/modules/regatta/bin" "$F/modules/b/hooks"
cat > "$F/modules/a/bin/tool" <<'PY'
#!/usr/bin/env python3
"""Docstring naming doc.site and gate.resolve("doc.call") as an example."""
import gate
# gate.classify("comment.site", {}, "q", {})
SITE_A = "const.site"
SHADOW: str = 'shadow.site'
OTHER = "not.asite"
def go(g, label):
    g.resolve("dq.site")
    g.classify('sq.site', {}, "q", {})
    model_flags("bare.site")
    review_provider("review.site")
    g.generate("gen.site", "x")
    label("wrap.site", 1)
    g.resolve(f"fstr.{go}")
    g.resolve("example.site")
    g.resolve("data.json")
    g.resolve("Upper.case")
    g.resolve(name)
    x = ("tuple.site", "yes")
    w = ("tokens.css", "fx.js", "art/a.svg")
    y = ["list.site", "no"]
    z = "after the call: gate.resolve(\"in.string\")"
PY
cat > "$F/modules/a/lib/helper.py" <<'PY'
ROWS = {"k": ("lib.tuple", 1)}
PY
cat > "$F/modules/b/hooks/loads" <<'PY'
#!/usr/bin/env python3
from importlib.machinery import SourceFileLoader
gate = SourceFileLoader("gate", "x").load_module()
ROW = ("loader.tuple", 1)
PY
cat > "$F/modules/b/hooks/pathload.py" <<'PY'
G = P / "bin" / "gate"
ROW = ("path.tuple", 1)
PY
cat > "$F/modules/b/hooks/toolload.py" <<'PY'
g = tool("gate")
h = peer("gate")
ROW = ("tool.tuple", 1)
PY
cat > "$F/modules/a/tests/skipped.py" <<'PY'
resolve("tests.site")
PY
printf '#!/bin/sh\necho gate.resolve\\(\\"shell.site\\"\\)\n' > "$F/modules/a/bin/script"
printf 'resolve("gate.itself")\n' > "$F/modules/regatta/bin/gate"
check "$(walk scan "$F" | cut -f1 | tr '\n' ' ')" "bare.site const.site dq.site gen.site loader.tuple path.tuple review.site shadow.site sq.site tool.tuple tuple.site wrap.site " \
  "calls (either quote, attribute or bare), constants, and tuples where the gate is loaded, sorted: no comment, docstring, f-string, string, example, file name, tests, shell script or the gate itself"
check "$(walk scan "$F" | grep -c 'lib.tuple')" 0 "  a tuple in a file that does not load the gate is no site"
check "$(walk scan "$F" | grep '^dq.site' | cut -f2)" "modules/a/bin/tool:9" "  a site is reported at its call line"
printf 'def broken(:\n' > "$F/modules/a/lib/broken.py"
walk scan "$F" | grep -q '^ERROR.*broken.py: does not parse'; check $? 0 "a python file that does not parse is an error, never skipped"
walk scan "$F" > /dev/null; check $? 1 "  and the scan exits 1"
rm -f "$F/modules/a/lib/broken.py"

echo "the walk finds a missing row, and an off row is a row"
mkdir -p "$F/modules/regatta/settings" "$F/modules/regatta/hooks"
cp "$M/bin/gate" "$F/modules/regatta/bin/gate"; cp -R "$M/hooks/." "$F/modules/regatta/hooks/"
rm -rf "$F/modules/b" "$F/modules/a/lib"
cat > "$F/modules/a/bin/tool" <<'PY'
#!/usr/bin/env python3
def go(g):
    g.resolve("has.row")
    g.resolve("has.off")
    g.resolve("has.offfail")
    g.resolve("has.none")
PY
cat > "$F/modules/regatta/settings/models.json" <<'JSON'
{"sites": {"has.row": {"kind": "classify", "provider": "claude", "model": "m", "when_off": "fail"},
           "has.off": {"kind": "classify", "provider": "off", "when_off": "skip"},
           "has.offfail": {"kind": "classify", "provider": "off", "when_off": "fail"}}}
JSON
check "$(walk rows "$F" | cut -f1,2 | tr '\t\n' ': ')" \
  "has.none:no row has.off:off (when_off skip) has.offfail:off (when_off fail) has.row:classify/claude " \
  "a row, an off row (skip and fail) and a site with no row, told apart"
cat > "$F/modules/regatta/settings/models.json" <<'JSON'
{"sites": {"has.row": {"kind": "bogus"}}}
JSON
check "$(walk rows "$F" | grep '^has.row' | cut -f2 | cut -c1-6)" "error:" "a row the gate refuses is an error, not a missing row"
# the environment: a config table, GATE_TABLE and a per-site override must not answer
cat > "$F/modules/regatta/settings/models.json" <<'JSON'
{"sites": {"has.row": {"kind": "classify", "provider": "claude", "model": "m", "when_off": "fail"}}}
JSON
mkdir -p "$T/cfg/regatta"; echo '{"sites": {"has.none": {"kind": "classify", "provider": "off", "when_off": "skip"}}}' > "$T/cfg/regatta/models.json"
check "$(REGATTA_CONFIG="$T/cfg" GATE_TABLE="$T/cfg/regatta/models.json" GATE_HAS_ROW_PROVIDER=off walk rows "$F" | grep -E '^has\.(row|none)' | cut -f1,2 | tr '\t\n' ': ')" \
  "has.none:no row has.row:classify/claude " "under an empty config with every GATE_* cleared: the caller's table, GATE_TABLE and an override are not read"

echo "this tree"
out=$(walk rows "$ROOT"); rc=$?
check "$rc" 0 "the walk reads every python file under modules/*/bin|libexec|hooks|lib"
n=$(echo "$out" | grep -v '^ERROR' | grep -c .)
[ "$n" -ge 18 ]; check $? 0 "  at least the eighteen sites found when this suite was written ($n)"
for s in evolve.ask evolve.theme evolve.match keel.comment lighthouse.importance lighthouse.urgency lighthouse.cost lighthouse.clarity \
         plan.stall review-gate.reviewer review-gate.code-review review-gate.merge review-gate.same-shadow \
         scope.brief scope.upstream sparks.shape sparks.route sparks.redact; do
  echo "$out" | cut -f1 | grep -qx "$s"; check $? 0 "  the walk finds $s"
done
check "$(echo "$out" | awk -F'\t' '$1 == "ERROR" || $2 == "no row" || $2 ~ /^error/ || $2 ~ /^ERROR/ {print $1 ": " $2}' | tr '\n' ' ')" "" \
  "every site resolves under an empty config (a row, or an off row): none has no row, none errors"
echo "$out" | grep -E 'no row|error' | sed 's/^/       /'

echo "the rows' contracts (the callers' own)"
row() { echo "$out" | awk -F'\t' -v s="$1" '$1 == s {print $2}'; }
check "$(row scope.brief)" "classify/claude" "scope.brief: classify, claude"
check "$(row plan.stall)" "classify/claude" "plan.stall: classify, claude"
check "$(row review-gate.reviewer)" "review/claude" "review-gate.reviewer: review, claude"
check "$(row review-gate.code-review)" "review/claude" "review-gate.code-review: review, claude"
check "$(row review-gate.merge)" "generate/claude" "review-gate.merge: generate, claude"
check "$(row review-gate.same-shadow)" "off (when_off skip)" "review-gate.same-shadow: off, skip"
check "$(row sparks.shape)" "generate/claude" "sparks.shape: generate, claude"
check "$(row sparks.route)" "generate/claude" "sparks.route: generate, claude"
check "$(row sparks.redact)" "off (when_off fail)" "sparks.redact: off, fail until a vendor is approved"
check "$(row scope.upstream)" "classify/claude" "scope.upstream: classify, claude"
python3 -I - "$M/settings/models.json" <<'PY' > "$T/contracts"
import json, sys
s = json.load(open(sys.argv[1]))["sites"]
want = {"scope.brief": ("claude-sonnet-5-5", "fail"), "plan.stall": ("claude-sonnet-5-5", "fail"),
        "review-gate.merge": ("claude-opus-5-5", "skip"), "review-gate.same-shadow": (None, "skip"),
        "sparks.shape": (None, "fail"), "sparks.route": (None, "skip"), "sparks.redact": (None, "fail"),
        "scope.upstream": ("claude-sonnet-5-5", "fail")}
for k, (model, off) in want.items():
    r = s.get(k) or {}
    print(k, "ok" if r.get("model") == model and r.get("when_off") == off else "WRONG model=%s when_off=%s" % (r.get("model"), r.get("when_off")))
r = s.get("review-gate.merge") or {}
print("review-gate.merge effort", "ok" if r.get("effort") == "medium" else "WRONG %s" % r.get("effort"))
PY
check "$(grep -vc ' ok$' "$T/contracts")" 0 "models and when_off as the caller's contract has them (Sonnet 5.5 for the classify rows, Opus 5.5 medium for the merge)"
grep -v ' ok$' "$T/contracts" | sed 's/^/       /'
mkdir -p "$T/emptycfg"; REGATTA_CONFIG="$T/emptycfg" python3 "$M/bin/gate" check > "$T/gc" 2>&1; check $? 0 "bin/gate check, under an empty config: the module's table validates"

[ "$fails" -eq 0 ] && echo "gate sites: all ok" || echo "gate sites: $fails failed"
[ "$fails" -eq 0 ]
