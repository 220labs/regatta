#!/usr/bin/env bash
# sextant's check: Sparks' suite (scratch dirs, stub whisper and claude, a fake GitHub remote and a
# fake TypeSafe server; no network, no model), the redaction bench's --help (it loads the core
# through common.tool(), G37), the launcher template compiled once with its two defines, and
# install.sh's syntax. The suite needs macOS (`say`, `afconvert`): elsewhere it is skipped with one
# printed line and the rest still runs (the design's C5: a macOS-only check stays in /finish on a Mac; off one,
# the pull request's macOS check). The
# sounding queue's suite (tests/soundings.sh) and the weekly job's (tests/schedule.sh: install.sh's
# plist with and without aurora, the module's own runner) run everywhere, and so do pitch's
# (tests/pitch.sh: the renders' checker and builder against their fixtures) and the North Star's
# (tests/north_star.sh: init, show and check against scratch config dirs).
# `sparks --help` prints its usage and an unknown argument exits 2 before anything runs (both
# checked below); a bare `sparks` is still a live pass on the Mac's own config.
#   bash modules/sextant/tests/check.sh            SPARKS_SUITE=0 skips the suite (about 6 min)
set -u
D="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
rc=0
echo "== sparks"
if [ "${SPARKS_SUITE:-1}" = 0 ]; then echo "  skipped: SPARKS_SUITE=0"
elif [ "$(uname)" = Darwin ]; then bash "$D/tests/sparks.sh" || rc=1
else echo "  skipped: the suite needs macOS (say, afconvert), not run on this host (a macOS run of this line covers it; where a pull request's check runs on a Mac, pr merge waits for it)"; fi
echo "== the rest"
ok() { if [ "$1" = 0 ]; then echo "  ok   $2"; else echo "  FAIL $2"; rc=1; fi; }
python3 "$D/bench/redaction/run.py" --help >/dev/null; ok $? "bench/redaction/run.py --help finds the core"
python3 -c "import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]" "$D/bin/sparks" "$D/bin/redactions"; ok $? "bin/sparks and bin/redactions parse"
python3 "$D/bin/sparks" --help | grep -q 'sparks --route'; ok $? "sparks --help prints its usage"
python3 "$D/bin/sparks" --bogus >/dev/null 2>&1; [ $? = 2 ]; ok $? "sparks refuses an unknown argument, running nothing"
# the employer-org filter: only the knowledge repo's GitHub owner routes; with none, no GitHub repo does
mkdir -p "$T/p/mine/.git" "$T/p/work/.git" "$T/p/local/.git" "$T/p/vault/.git"
echo '{"repos": {"vault": {"knowledge": true, "github": "me/vault"}, "mine": {"github": "me/mine"}, "work": {"github": "corp/work"}, "local": {}}}' >"$T/r1.json"
echo '{"repos": {"mine": {"github": "me/mine"}, "local": {}}}' >"$T/r2.json"
cands() { SPARKS_CONFIG="$T/none.json" SPARKS_REPOS="$T/$1" SPARKS_PROJECTS="$T/p" python3 -c "
import sys; from importlib.machinery import SourceFileLoader; sys.argv = ['sparks']
print(' '.join(sorted(SourceFileLoader('sparks', '$D/bin/sparks').load_module().candidates())))"; }
[ "$(cands r1.json)" = "local mine vault" ]; ok $? "routing skips another owner's repo"
[ "$(cands r2.json)" = "local" ]; ok $? "  and every GitHub repo when no knowledge repo names an owner"
# `redactions audit` and `trial` reach the classifier through classify_sentences(), not gate_ready():
# it refuses on its own, before any request, without sextant/source or the vendor's quote
C="$T/c"; mkdir -p "$C/regatta" "$T/proj" "$T/logs"; touch "$C/regatta/overlay"
echo me >"$C/regatta/owner"; echo _vault >"$C/regatta/guarded"; echo none >"$C/regatta/orca-deny"
echo "$T/logs" >"$C/regatta/log-dir"; echo "$T/proj" >"$C/regatta/projects"
echo '{"sites": {"sparks.redact": {"kind": "classify", "provider": "jev", "when_off": "fail"}}}' >"$C/regatta/models.json"
echo '{"redact_approved": {"typesafe": "ok"}}' >"$T/quoted.json"; echo '{}' >"$T/unquoted.json"
classify() { REGATTA_CONFIG="$C" SPARKS_CONFIG="$T/$1" TYPESAFE_BASE_URL=http://127.0.0.1:9 TYPESAFE_API_KEY=x python3 -c "
import sys; from importlib.machinery import SourceFileLoader; sys.argv = ['sparks']
m = SourceFileLoader('sparks', '$D/bin/sparks').load_module()
try: m.classify_sentences({'a': 'hello there.'}); print('sent')
except m.gate.GateError as e: print(e)" 2>&1; }
classify quoted.json | grep -q 'sextant/source is missing'; ok $? "redaction refuses without sextant/source"
echo _vault >"$C/sextant-source.tmp"; mkdir -p "$C/sextant"; mv "$C/sextant-source.tmp" "$C/sextant/source"
classify unquoted.json | grep -q 'redact_approved has no'; ok $? "  and without the vendor's quote"
[ -z "$(ls -A "$T/logs")" ]; ok $? "  having sent nothing"
# launcher.c.in is macOS-only (setiopolicy_np): CI's ubuntu has a cc too (review, 2026-10-19)
if [ "$(uname)" = Darwin ] && command -v cc >/dev/null 2>&1; then
  cc -O2 -Wall -Werror -x c -DSPARKS_SCRIPT='"/x/sparks"' -DSPARKS_CONFIG_PATH='"/x/c.json"' -o "$T/l" "$D/launcher.c.in" 2>"$T/cc.err"
  ok $? "launcher.c.in compiles with its two defines"
  ! cc -x c -o "$T/l2" "$D/launcher.c.in" 2>/dev/null; ok $? "  and refuses to without them"
elif [ "$(uname)" = Darwin ]; then echo "  skipped: no cc"
else echo "  skipped: launcher.c.in is macOS-only, not run on this host (a macOS run of this line covers it; where a pull request's check runs on a Mac, pr merge waits for it)"; fi
# /sounding (the Sounding's S4): its frontmatter, and every `keel <verb> … --flag` it tells a session
# to run is one keel takes — a renamed flag would otherwise fail only when a sounding reaches it.
# keel is a peer (its own module): absent, as in an install of sextant alone, those cases are skipped.
SK="$D/skills/sounding/SKILL.md"
# Without PyYAML, a text check; with it, a description that does not parse fails (no fallback then).
python3 -c '
import sys
t = open(sys.argv[1]).read()
try: import yaml
except ImportError: sys.exit(0 if t.startswith("---\nname: sounding\ndescription: ") else 1)
m = yaml.safe_load(t.split("---")[1]); sys.exit(0 if m["name"] == "sounding" and m["description"] else 1)' "$SK"
ok $? "skills/sounding: its frontmatter names it and says what it does"
for h in architect sr-architect sounder; do grep -q "| \`$h\` |" "$SK"; ok $? "  …and picks \`$h\` by scope"; done
KEEL=$(python3 "$D/../regatta/bin/regatta" which keel 2>/dev/null) || KEEL=""   # through the core, as wharf's test_agents.sh
if [ -n "$KEEL" ]; then
  for v in lint line light yolo pull; do python3 "$KEEL" "$v" --help >/dev/null 2>&1; ok $? "  keel $v, which it runs, is a keel verb"; done
  lh=$(python3 "$KEEL" light --help 2>&1 | sed '/^positional/,$d')   # the usage block alone: other flags' help names these too
  for f in --check --plan --write --record --review --why; do printf '%s' "$lh" | grep -q -- "$f"; ok $? "  keel light $f, which it runs, is a flag"; done
  python3 "$KEEL" yolo --help 2>&1 | grep -q -- --dry-run; ok $? "  keel yolo --dry-run, which it runs, is a flag"
  python3 "$KEEL" lint --help 2>&1 | grep -q -- --strict; ok $? "  keel lint --strict, which it runs, is a flag"
else echo "  skipped: keel is not installed here (an install of sextant alone)"; fi
# /pitch and /captain (pitch-skill-wording, 2026-11-02): a description that parses (pitch's held an
# unquoted colon), and a linked skill runs bin/pitch by the module's real path, never `../../bin/pitch`
# from the link, which no allow rule on that path matches.
for s in pitch captain; do
  python3 -c '
import re, sys
t = open(sys.argv[1]).read()
try: import yaml
except ImportError:
    # No PyYAML: the text check. A single-quoted description doubles each inner apostrophe, a
    # double-quoted one closes, and a plain one is not empty and holds no ": " (the old pitch fault)
    # and no " #" (a comment).
    v = t.split("\n")[2][13:]
    ok = (re.fullmatch("\x27(?:[^\x27]|\x27\x27)+\x27", v) if v[:1] == "\x27"
          else re.fullmatch("\"(?:[^\"\\\\]|\\\\.)+\"", v) if v[:1] == "\""
          else v.strip() and ": " not in v and " #" not in v)
    sys.exit(0 if t.startswith("---\nname: " + sys.argv[2] + "\ndescription: ") and ok else 1)
try: m = yaml.safe_load(t.split("\n---\n")[0][4:])
except yaml.YAMLError as e: print(e, file=sys.stderr); sys.exit(1)
d = m.get("description") if isinstance(m, dict) else None
sys.exit(0 if isinstance(m, dict) and m.get("name") == sys.argv[2] and isinstance(d, str) and d.strip() else 1)' "$D/skills/$s/SKILL.md" "$s"
  ok $? "skills/$s: its frontmatter parses"
  ! grep -q '\.\./\.\./bin/pitch' "$D/skills/$s/SKILL.md"; ok $? "  …and never runs ../../bin/pitch from the link"
  grep -q 'realpath "<base directory>/\.\./\.\."' "$D/skills/$s/SKILL.md" && grep -q '^allowed-tools: .*Bash(realpath \*)' "$D/skills/$s/SKILL.md"
  ok $? "  …and resolves the module with realpath, which its allowed-tools name"
  # Both spellings the skill names, run on a link as a login dir holds it: each prints the module, not
  # the login dir (a plain `cd` drops `..` from the text before following the link, landing in the login dir).
  mkdir -p "$T/lk/$s/.claude/skills"; ln -s "$D/skills/$s" "$T/lk/$s/.claude/skills/$s"; B="$T/lk/$s/.claude/skills/$s"
  want=$(cd -P "$D" && pwd)
  grep -qF '(cd -P "<base directory>/../.." && pwd)' "$D/skills/$s/SKILL.md" && [ "$(cd -P "$B/../.." && pwd)" = "$want" ]
  ok $? "  …and its pre-macOS-13 fallback, run on a linked skill, prints the module"
  if command -v realpath >/dev/null; then [ "$(realpath "$B/../..")" = "$want" ] && [ -x "$want/bin/pitch" ]
    ok $? "  …and realpath, run on a linked skill, prints the module that holds bin/pitch"
  else echo "  skipped: realpath is not on this host (before macOS 13); the fallback case above stands"; fi
done
# /sounding --principal (the principal tier's S4): the council's road, bin/principal, against a council stand-in
# (any OS; the stubbed CLIs through the real council are wharf's test_council.sh), and the skill's section names
# its head by scope and every principal verb it runs, each one principal takes
bash "$D/tests/principal.sh" >"$T/principal.log" 2>&1; pr=$?; grep -E '^  FAIL|all passed|failed$|^skipped' "$T/principal.log"; [ "$pr" = 0 ] || tail -n 30 "$T/principal.log"
ok "$pr" "principal's suite (tests/principal.sh)"
grep -q '^## 6b\. `--principal`' "$SK" && grep -q '`principal-architect`' "$SK" && grep -q 'effort: "xhigh"' "$SK"
ok $? "skills/sounding: --principal picks principal-architect, or sounder at xhigh for a venture"
for v in run examine receipt check; do grep -q "<principal> $v --doc" "$SK" && python3 "$D/bin/principal" "$v" --help >/dev/null 2>&1; ok $? "  principal $v, which it runs, is a principal verb"; done
python3 "$D/bin/principal" run --help | grep -q -- '--approved' && python3 "$D/bin/principal" examine --help | grep -q -- '--research'; ok $? "  …and its flags are principal's"
if [ -n "$KEEL" ]; then python3 "$KEEL" lint --help >/dev/null 2>&1 && grep -q '^PRINCIPAL_SINCE' "$KEEL"; ok $? "  keel's principal rule, which --strict runs, is there"; fi
# the sounding queue (the Sounding's S7): scratch dirs and git only, any OS
bash "$D/tests/soundings.sh" | tail -1; ok "${PIPESTATUS[0]}" "the sounding queue's suite (tests/soundings.sh)"
python3 "$D/bin/soundings" --help | grep -q 'soundings next'; ok $? "soundings --help prints its usage"
# the North Star (Evolve S4): init, show and check against scratch config dirs, any OS
bash "$D/tests/north_star.sh" >"$T/north_star.log" 2>&1; nr=$?; grep -E '^  FAIL|all passed|failed$' "$T/north_star.log"; ok "$nr" "the North Star's suite (tests/north_star.sh)"
python3 "$D/bin/sextant" north-star --help | grep -q 'check'; ok $? "sextant north-star --help prints its verbs"
# /sextant (B13): its frontmatter, and the weekly job and the module's own runner (G29), any OS
SX="$D/skills/sextant/SKILL.md"
head -3 "$SX" | grep -q '^name: sextant$' && grep -q '^disable-model-invocation: true$' "$SX"; ok $? "skills/sextant: named, and never invoked by the model"
grep -q 'libexec/sextant-run where' "$SX"; ok $? "  its paths come from sextant-run where"
grep -q '^8\. \*\*Models, prices, published evals\*\*' "$SX"; ok $? "  step 1's item 8: models, prices, evals (self-tuning S5)"
# its example tag line is what plumb's trim reads as intake (trimlib.sextant_lines), where plumb is installed
TL="$D/../plumb/lib/trimlib.py"
if [ -f "$TL" ]; then
  ex=$(grep -o '`- trim: builder — [^`]*`' "$SX" | tr -d '`'); printf '# entry\n%s\n' "$ex" > "$T/trim-entry.md"
  [ "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import trimlib; print(trimlib.sextant_lines([sys.argv[2]]))' "$(dirname "$TL")" "$T/trim-entry.md")" \
    = "['builder — cost per landed step — sonnet:high']" ]; ok $? "  its trim: tag line reads as trim's intake"
else echo "  skipped: plumb is not installed here (the trim: tag's reader)"; fi
python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])" "$D/libexec/sextant-run"; ok $? "libexec/sextant-run parses"
bash "$D/tests/schedule.sh" | tail -1; ok "${PIPESTATUS[0]}" "the weekly job's suite (tests/schedule.sh)"
# pitch (renders S1): the renders' checker and builder, stdlib Python and temp dirs, any OS
bash "$D/tests/pitch.sh" >"$T/pitch.log" 2>&1; pr=$?; grep -E '^  FAIL|passed in|failed in' "$T/pitch.log"; [ "$pr" = 0 ] || tail -n 30 "$T/pitch.log"; ok "$pr" "pitch's suite (tests/pitch.sh)"
sh -n "$D/install.sh"; ok $? "install.sh parses"
sh "$D/install.sh" --bogus >/dev/null 2>&1; [ $? = 2 ]; ok $? "install.sh refuses an unknown verb"
exit $rc
