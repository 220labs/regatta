#!/usr/bin/env bash
# Tests for bin/principal, the council's road for /sounding --principal (the principal tier's S4): run, examine,
# receipt and check against a stand-in for wharf's council that writes the run.json and papers the real one does,
# and hands `receipt` to the real council (it reads run.json alone, no arm), so the Receipt's shape is council's
# own. No model, no CLI, any OS. An answered run, a partial one (an arm failed, one refused), one the council
# refused before any arm started, one where no arm answered (council's road off macOS), a paper holding a token's
# shape, an examine that refused, a council that is not installed: each leaves the record and the Receipt saying so
# and exits 0, so the sounding goes on; `check` holds the doc's Receipt to the record. The stubbed CLIs through the
# real council: wharf's tests/test_council.sh, its principal cases.
#   bash modules/sextant/tests/principal.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd)"
P="$D/bin/principal"
REAL="$D/../wharf/bin/council"
T=$(mktemp -d "${TMPDIR:-/tmp}/principal-test-XXXXXX"); T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; fails=$((fails+1)); fi; }
hasnt() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: has [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }
jget()  { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1"; }
unset PRINCIPAL_COUNCIL STUB_MODE
# the cases are an attended caller's: $PRINCIPAL_COUNCIL is refused to an unattended one (council_path), and a
# dispatched run or an unattended /finish runs this suite with the markers set (AGENTS.md: reset them by name)
unset CLAUDE_UNATTENDED REGATTA_UNATTENDED AUTOFINISH_CALLER_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS

# the stand-in: STUB_MODE picks what the council did; every call is logged to $T/calls
cat > "$T/council" <<'PY'
#!/usr/bin/env python3
import json, os, sys
mode, args = os.environ.get("STUB_MODE", "ok"), sys.argv[1:]
with open(os.environ["STUB_CALLS"], "a") as f:
    f.write(" ".join(args) + "\n")
def opt(name):
    return args[args.index(name) + 1] if name in args else None
def write(p, text):
    with open(p, "w") as f:
        f.write(text)
verb = args[0]
if verb == "receipt":
    os.execv(sys.executable, [sys.executable, os.environ["REAL_COUNCIL"]] + args)
if verb == "run":
    if mode == "refused":
        print("council: refused: site is a confidential scope's repo: no arm gets it", file=sys.stderr); sys.exit(2)
    if mode == "crash":
        print("Traceback (most recent call last):\nValueError: boom", file=sys.stderr); sys.exit(1)
    import tempfile; run = tempfile.mkdtemp(prefix="run-%s-" % mode, dir=os.environ["STUB_RUNS"])
    states = {"ok": ("ok", "ok", "ok"), "partial": ("ok", "failed", "refused"), "noarm": ("refused",) * 3,
              "leak": ("ok", "ok", "ok")}[mode]
    arms = {}
    for arm, st in zip(("opus", "codex", "antigravity"), states):
        r = {"arm": arm, "state": st, "login": "acct-%s" % arm[0], "requested": {"model": "m-" + arm}}
        if st == "ok":
            r["paper"] = os.path.join(run, arm + ".md")
            body = "# %s's paper\nthe premise holds\n\n## Owner decisions\n\n**D1 — Which?** pick A\n➤ Answer:\n- [ ] probe it\nsee docs/handoff/x.md\n" % arm
            if mode == "leak" and arm == "codex":
                body += "a key: %s%s\n" % ("sk-ant-", "x" * 24)
            write(r["paper"], body)
        else:
            r["why"] = {"failed": "F5: a tool the start did not allow", "refused": "no seatbelt here"}[st]
        arms[arm] = r
    write(os.path.join(run, "run.json"), json.dumps({"id": "u1", "commit": "c0ffee" * 6, "source": "site",
                                                     "brief": os.path.join(run, "brief.md"), "home": "/x", "arms": arms}))
    print(json.dumps({"run": run, "completion": "x", "arms": {}}))
    sys.exit(0 if "ok" in states else 1)
if verb == "examine":
    if mode == "exrefused":
        print("council: refused: --draft holds a credential shape: no examiner gets it", file=sys.stderr); sys.exit(2)
    run = opt("--run"); d = json.load(open(os.path.join(run, "run.json")))
    d["examine"], d["examine_keys"] = {}, {}
    ok = sorted(a for a, r in d["arms"].items() if r["state"] == "ok" and a not in d.get("withheld", {}))
    for arm in ok:
        # each examiner its own labels, the draft among them (council's per-arm shuffle): reversed here
        d["examine_keys"][arm] = dict(zip("ABCDEFG", list(reversed(["draft"] + ok))))
        p = os.path.join(run, arm + "-critique.md"); write(p, "# a critique\nPaper A is weakest\n")
        d["examine"][arm] = {"arm": arm, "state": "ok", "paper": p}
        if mode == "exfail" and arm == "codex":
            d["examine"][arm] = {"arm": arm, "state": "failed", "why": "F5 broke"}
    write(os.path.join(run, "run.json"), json.dumps(d))
    print(json.dumps({"run": run})); sys.exit(0)
sys.exit(2)
PY
chmod +x "$T/council"
export PRINCIPAL_COUNCIL="$T/council" STUB_CALLS="$T/calls" STUB_RUNS="$T/runs" REAL_COUNCIL="$REAL"
mkdir -p "$T/runs" "$T/repo/docs"
printf '# the brief\nIs the premise sound?\n' > "$T/brief.md"
printf '# the draft\n' > "$T/draft.md"
REC="$T/repo/docs/x-2026-11-03/council"
doc() {  # doc <file> <completion> <rows…>: a doc whose Receipt holds these rows and that completion
  local f=$1 c=$2; shift 2
  { printf '# X — a test (design, 2026-11-03)\n\n## Summary\n\nx\n\n## Receipt — who ran, at what, for how much\n\n'
    printf '| Arm (login) | Requested / observed | Cost | Caught | State |\n| --- | --- | --- | --- | --- |\n'
    for r in "$@"; do printf '%s\n' "$r"; done
    printf '\nCompletion: **%s** — test.\n\n## Open feedback\n' "$c"; } > "$f"
}

if [ ! -f "$REAL" ]; then
  echo "skipped: wharf's council is not beside this module (an install of sextant alone): the Receipt is its"
  exit 0
fi

echo "run: three arms answered"
X="$T/repo/docs/x-2026-11-03.md"
STUB_MODE=ok python3 "$P" run --doc "$X" --brief "$T/brief.md" --home "$T/repo" --files a.md > "$T/out" 2>&1
check "$?" 0 "exits 0"
check "$([ -e "$REC/papers" ] && echo there || echo none)" none "  no paper in the doc's folder yet: the head drafts blind beside it"
has "$T/out" "answered: 3" "  saying how many answered"
has "$REC/brief.md" "Is the premise sound?" "  the brief kept"
has "$T/calls" "run --home $T/repo --brief $T/brief.md --json --timeout 1200 --arms opus,codex,antigravity --files a.md" "  council run with the brief, the arms it records, the files, a timeout"
has "$REC/receipt.md" "Completion: **complete**" "  the receipt: council's own word"
has "$REC/receipt.md" "| opus (acct-o) |" "  …a row per arm, from council receipt"
has "$REC/receipt.md" "Examine: not run." "  …examine not run yet"
check "$(jget "$REC/state.json" '(d["receipt"]["completion"], sorted(d["receipt"]["states"].items()))')" \
  "('complete', [('antigravity', 'ok'), ('codex', 'ok'), ('opus', 'ok')])" "  council's Receipt kept in the record"
STUB_MODE=ok python3 "$P" run --doc "$X" --brief "$T/brief.md" --home "$T/repo" >/dev/null 2>"$T/err"
check "$?" 2 "a second run on the same doc is refused"
has "$T/err" "--again" "  naming --again"

echo "examine"
STUB_MODE=ok python3 "$P" examine --doc "$X" --draft "$T/draft.md" --approved google=yes > "$T/out" 2>&1
check "$?" 0 "exits 0"
check "$(ls "$REC/papers" | tr '\n' ' ')" "A.md B.md C.md " "  three papers now, under labels"
check "$(jget "$REC/state.json" 'sorted(d["labels"]["papers"].values())')" "['antigravity', 'codex', 'opus']" "  the key in state.json"
hasnt "$REC/papers/A.md" "acct-" "  a paper names no login"
check "$(ls "$REC/critiques" | wc -l | tr -d ' ')" 3 "  three critiques, under labels"
has "$T/calls" "--draft $T/draft.md --json --timeout 1200 --approved google=yes" "  the owner's quote handed to council examine too (a guarded home)"
check "$(python3 -c '
import json, re, sys
st = json.load(open(sys.argv[1] + "/state.json")); arm_of = st["labels"]["papers"]; label_of = {a: l for l, a in arm_of.items()}
ok = True
for cl, examiner in st["labels"]["critiques"].items():
    first = open("%s/critiques/%s.md" % (sys.argv[1], cl)).readline()
    want = dict(zip("ABCD", reversed(["draft", "antigravity", "codex", "opus"])))
    for theirs, src in want.items():
        say = "the draft" if src == "draft" else "papers/%s.md" % label_of[src]
        ok = ok and ("%s = %s" % (theirs, say)) in first
print(ok)' "$REC")" True "  each critique opens with its examiner's labels: which is the draft, which papers/<label>.md"
hasnt "$REC/critiques/A.md" "opus" "  …never naming an arm"
check "$(grep -l 'D1 — Which' "$REC"/papers/*.md | wc -l | tr -d ' ')/$(cat "$REC"/papers/*.md | grep -c '\*\*D1 —\|➤ Answer:\|- \[ \]\|docs/handoff/')" "3/0" \
  "  the papers' owner decisions kept, none reading as an open ask to autofinish (D-item, answer box, checkbox, handoff path)"
has "$REC/papers/A.md" "**Paper D1 — Which?**" "  …a D-item as the paper's"
has "$REC/draft.md" "# the draft" "  the pen's draft copied into the record for the synthesis"
check "$(jget "$REC/state.json" 'd["examine"]["rc"]')" 0 "  recorded"
hasnt "$REC/receipt.md" "Examine:" "  the receipt has examine's rows, no line for it"
python3 "$P" receipt --doc "$X" > "$T/rcpt"; check "$?" 0 "receipt prints"
check "$(grep -c '^| [a-z]*, examine (' "$T/rcpt")" 3 "  …examine's rows"

echo "check: the doc's Receipt against the record"
doc "$X" complete "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | ok |"
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 0 "every arm, complete: passes"
doc "$X" complete "| Opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | ok |"
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 0 "  an arm's name in another case is its row"
doc "$X" complete "| opus (acct-o) | m / m | — | x | ok |" "| antigravity-claude (—) | m | — | — | off |"
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 1 "an arm left out: fails"
has "$T/out" "no row for the council's codex arm" "  naming it"
has "$T/out" "no row for the council's antigravity arm" "  antigravity-claude's row is not antigravity's"
printf '# X\n\n## Summary\n' > "$X"; python3 "$P" check --doc "$X" > "$T/out"; check "$?" 1 "no Receipt: fails"
has "$T/out" "no \`## Receipt\` section" "  saying so"
doc "$X" "" "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | ok |"
sed -i.bak '/^Completion:/d' "$X" && rm -f "$X.bak"
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 1 "no completion state: fails"

echo "check: the run dir gone (another host, a restart)"
PRUN=$(jget "$REC/state.json" 'd["run"]["dir"]'); mv "$PRUN" "$PRUN.gone"
doc "$X" complete "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | ok |"
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 0 "a correct doc still passes, judged against the recorded Receipt"
python3 "$P" receipt --doc "$X" > "$T/rcpt"
has "$T/rcpt" "| opus, examine (—) |" "  receipt prints council's Receipt as recorded"
has "$T/rcpt" "does not read here: council's Receipt as recorded at" "  …saying the dir is gone"
hasnt "$T/rcpt" "refused" "  …never a false refusal"
mv "$PRUN.gone" "$PRUN"

echo "check: the doc's folder holds no open ask"
doc "$X" complete "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | ok |"
printf '# a note\n\n**D2 — Left here?** yes\n' > "$T/repo/docs/x-2026-11-03/note.md"
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 1 "a D-item in a file of the doc's folder fails check"
has "$T/out" "x-2026-11-03/note.md:3 reads as an open ask to autofinish" "  naming the file and line"
printf '# a note\n\nthe `**D2 —` shape, in a code span\n' > "$T/repo/docs/x-2026-11-03/note.md"
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 0 "  one in a code span is prose, as autofinish reads it"
rm -f "$T/repo/docs/x-2026-11-03/note.md"

echo "check: the Receipt's shape — any heading level, a --- ends it, the bold label, an arm's row by its shape"
R3="| opus (acct-o) | m / m | — | x | ok |"; R4="| codex (acct-c) | m / m | — | x | ok |"; R5="| antigravity (acct-a) | m / m | — | x | ok |"
doc "$X" complete "$R3" "$R4" "$R5"; sed -i.bak 's/^## Receipt/### Receipt/' "$X" && rm -f "$X.bak"
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 0 "a ### Receipt is the Receipt, as keel reads it"
doc "$X" complete "$R3" "$R4" "$R5"; sed -i.bak 's/^Completion: \*\*complete\*\* — test\./**Completion:** **complete** — test./' "$X" && rm -f "$X.bak"
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 0 "  the bold label, \`**Completion:** **complete**\`, reads"
doc "$X" complete "| Opus 5.5, this session (the parent) | m | — | x | complete |" "$R4" "$R5"
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 1 "  the parent's row (\"Opus 5.5, …\") is not the opus arm's"
has "$T/out" "no row for the council's opus arm" "  …naming the missing row"
doc "$X" complete "$R3" "$R4" "$R5"; sed -i.bak 's/^Completion: \*\*complete\*\* — test\./---\
\
Completion: **complete** — a later note./' "$X" && rm -f "$X.bak"
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 1 "  a completion line after a --- is not the Receipt's"
has "$T/out" "no completion state" "  …the Receipt states none"

echo "check: nothing in the doc's folder holds a login's shape"
python3 -c 'import sys; open(sys.argv[1], "w").write("draft quoting " + "sk-" + "ant-" + "x" * 30 + "\n")' "$T/draft-tok.md"
STUB_MODE=exrefused python3 "$P" examine --doc "$X" --draft "$T/draft-tok.md" > /dev/null 2>&1; check "$?" 0 "examine with a draft holding a token's shape: exits 0"
has "$REC/draft.md" "the draft is not copied here: it holds a sk-ant… token" "  the draft is not copied into the record"
check "$(grep -rl 'sk-ant-x' "$T/repo/docs/x-2026-11-03" | wc -l | tr -d ' ')" 0 "  nothing in the doc's folder holds it"
python3 -c 'import sys; open(sys.argv[1], "w").write("a probe printed " + "sk-" + "ant-" + "x" * 30 + "\n")' "$T/repo/docs/x-2026-11-03/probe.txt"
doc "$X" incomplete "$R3" "$R4" "$R5" "" "Examine: refused."
python3 "$P" check --doc "$X" > "$T/out"; check "$?" 1 "check refuses a file of the doc's folder holding a login's shape"
has "$T/out" "x-2026-11-03/probe.txt:1 holds a login's shape" "  naming it, by place, never by value"
hasnt "$T/out" "sk-ant-x" "  …and never printing it"
rm -f "$T/repo/docs/x-2026-11-03/probe.txt"
STUB_MODE=ok python3 "$P" examine --doc "$X" --draft "$T/draft.md" > /dev/null 2>&1

echo "examine again: the same papers keep their labels; one that does not answer drops the old critiques"
before=$(jget "$REC/state.json" 'sorted(d["labels"]["papers"].items())')
STUB_MODE=ok python3 "$P" examine --doc "$X" --draft "$T/draft.md" > /dev/null 2>&1
check "$(jget "$REC/state.json" 'sorted(d["labels"]["papers"].items())')" "$before" "a second examine keeps the papers' labels"
STUB_MODE=exrefused python3 "$P" examine --doc "$X" --draft "$T/draft.md" > /dev/null 2>&1
check "$(jget "$REC/state.json" 'sorted(d["labels"]["papers"].items())')/$([ -e "$REC/critiques" ] && echo kept || echo gone)/$(jget "$REC/state.json" '"critiques" in d["labels"]')" \
  "$before/gone/False" "  a refused one: the labels kept, the old critiques and their key gone"

echo "check: an examine arm that failed"
W="$T/repo/docs/w-2026-11-03.md"
STUB_MODE=ok python3 "$P" run --doc "$W" --brief "$T/brief.md" --home "$T/repo" > /dev/null 2>&1
STUB_MODE=exfail python3 "$P" examine --doc "$W" --draft "$T/draft.md" > /dev/null 2>&1
doc "$W" incomplete "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | ok |" "| codex, examine (acct-c) | m / m | — | x | ok |"
python3 "$P" check --doc "$W" > "$T/out"; check "$?" 1 "an examine row saying ok where the record says failed: fails"
has "$T/out" "the codex arm's examine row does not say failed" "  naming it"
doc "$W" incomplete "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | ok |" "| codex, examine (acct-c) | m / m | — | x | failed: F5 |"
python3 "$P" check --doc "$W" > "$T/out"; check "$?" 0 "  saying failed: passes"
doc "$W" incomplete "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | ok |" "| opus, examine (acct-o) | m / m | — | x | ok |" "| codex, examine (acct-c) | m / m | — | x | failed: F5 |"
python3 "$P" check --doc "$W" > "$T/out"; check "$?" 1 "  an arm's examine row is not its run row"
has "$T/out" "no row for the council's opus arm" "  …naming the missing run row"
doc "$W" incomplete "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | ok |" "| codex, examine #1 (acct-c) | m / m | — | x | failed: F5 |" "| codex, examine (acct-c) | m / m | — | x | ok |"
python3 "$P" check --doc "$W" > "$T/out"; check "$?" 1 "  an earlier round's examine row saying failed does not stand for the last one's"

echo "run: an arm failed, one refused (partial)"
Y="$T/repo/docs/y-2026-11-03.md"; RY="$T/repo/docs/y-2026-11-03/council"
STUB_MODE=partial python3 "$P" run --doc "$Y" --brief "$T/brief.md" --home "$T/repo" > "$T/out" 2>&1
check "$?" 0 "exits 0: the sounding goes on"
has "$T/out" "codex                failed" "  saying what each arm did"
has "$RY/receipt.md" "| codex (acct-c) | m-codex / unknown, effort unknown | — | — | failed: F5: a tool the start did not allow |" "  the receipt names the failure"
has "$RY/receipt.md" "refused: no seatbelt here" "  …and the refusal"
has "$RY/receipt.md" "Completion: **incomplete**" "  …incomplete"
doc "$Y" complete "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | refused: no seatbelt |"
python3 "$P" check --doc "$Y" > "$T/out"; check "$?" 1 "a doc that hides the failure fails check"
has "$T/out" "the codex arm's row does not say failed" "  naming the arm"
has "$T/out" "the completion state says complete, the council's is incomplete" "  …and the completion"
has "$T/out" "examine was not run, and the Receipt does not say so" "  …and examine"
doc "$Y" "complete with limitation" "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | failed: F5 |" "| antigravity (acct-a) | m / m | — | x | refused: no seatbelt |" "" "Examine: not run yet."
python3 "$P" check --doc "$Y" > "$T/out"; check "$?" 1 "complete with limitation while the council is incomplete: fails"
doc "$Y" incomplete "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | failed: F5 |" "| antigravity (acct-a) | m / m | — | x | refused: no seatbelt |" "" "Examine: not run yet."
python3 "$P" check --doc "$Y" > "$T/out"; check "$?" 0 "one that says so passes"
STUB_MODE=ok python3 "$P" examine --doc "$Y" --draft "$T/draft.md" > /dev/null 2>&1
check "$(ls "$RY/papers" | tr '\n' ' ')" "A.md " "  examine: one paper"

echo "examine: refused by the council"
STUB_MODE=ok python3 "$P" run --doc "$T/repo/docs/e-2026-11-03.md" --brief "$T/brief.md" --home "$T/repo" > /dev/null 2>&1
E="$T/repo/docs/e-2026-11-03.md"; RE="$T/repo/docs/e-2026-11-03/council"
STUB_MODE=exrefused python3 "$P" examine --doc "$E" --draft "$T/draft.md" > "$T/out" 2>&1
check "$?" 0 "exits 0"
has "$RE/receipt.md" "Examine: refused or failed — --draft holds a credential shape: no examiner gets it." "  the receipt says why"
check "$(ls "$RE/critiques" 2>/dev/null | wc -l | tr -d ' ')/$(ls "$RE/papers" | wc -l | tr -d ' ')" "0/3" "  no critiques; the papers for the pen all the same"
doc "$E" complete "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | ok |"
python3 "$P" check --doc "$E" > "$T/out"; check "$?" 1 "check: complete with examine refused and unsaid fails"
has "$T/out" "examine did not answer" "  naming examine"
has "$T/out" "the completion state says complete, the council's is incomplete" "  …and the completion"
doc "$E" incomplete "| opus (acct-o) | m / m | — | x | ok |" "| codex (acct-c) | m / m | — | x | ok |" "| antigravity (acct-a) | m / m | — | x | ok |" "" "Examine: refused (a draft holding a token's shape)."
python3 "$P" check --doc "$E" > "$T/out"; check "$?" 0 "  saying so, incomplete: passes"

echo "run: the council refused before any arm started"
Z="$T/repo/docs/z-2026-11-03.md"; RZ="$T/repo/docs/z-2026-11-03/council"
STUB_MODE=refused python3 "$P" run --doc "$Z" --brief "$T/brief.md" --home "$T/repo" --arms opus,codex > "$T/out" 2>&1
check "$?" 0 "exits 0"
check "$(jget "$RZ/state.json" '[d["run"]["rc"], d["run"]["dir"]]')" "[2, None]" "  recorded: rc 2, no run dir"
has "$RZ/receipt.md" "| codex (—) | unknown / unknown | — | — | refused: site is a confidential scope's repo: no arm gets it |" "  a row per arm asked, refused with the reason"
check "$(grep -c '^| [a-z]* (—)' "$RZ/receipt.md")" 2 "  …the two asked, no more"
has "$RZ/receipt.md" "Completion: **incomplete** — the council refused before any arm started" "  …incomplete"
n0=$(grep -c '^examine' "$T/calls")
STUB_MODE=ok python3 "$P" examine --doc "$Z" --draft "$T/draft.md" > "$T/out" 2>&1
check "$?" 0 "examine: exits 0"
has "$T/out" "examine not run: no arm answered the run" "  not run, saying why"
check "$(grep -c '^examine' "$T/calls")" "$n0" "  …council examine not called"
has "$RZ/receipt.md" "Examine: not run — no arm answered the run." "  the receipt says so"
doc "$Z" incomplete "| opus (—) | — | — | — | refused: a confidential scope |" "| codex (—) | — | — | — | refused: likewise |" "" "Examine: not run — no arm answered."
python3 "$P" check --doc "$Z" > "$T/out"; check "$?" 0 "check: the refused arms said, incomplete: passes"

echo "run: no arm answered (council's road off macOS)"
N="$T/repo/docs/n-2026-11-03.md"
STUB_MODE=noarm python3 "$P" run --doc "$N" --brief "$T/brief.md" --home "$T/repo" > "$T/out" 2>&1
check "$?" 0 "exits 0, where council exits 1"
has "$T/repo/docs/n-2026-11-03/council/receipt.md" "| opus (acct-o) | m-opus / unknown, effort unknown | — | — | refused: no seatbelt here |" "  the receipt is council's, each arm refused"
STUB_MODE=ok python3 "$P" examine --doc "$N" --draft "$T/draft.md" > /dev/null 2>&1
check "$(ls "$T/repo/docs/n-2026-11-03/council/papers" 2>/dev/null | wc -l | tr -d ' ')" 0 "  no papers"

echo "run: a council that crashed, none installed, and an interrupted run"
C="$T/repo/docs/c-2026-11-03.md"
STUB_MODE=crash python3 "$P" run --doc "$C" --brief "$T/brief.md" --home "$T/repo" > /dev/null 2>&1; check "$?" 0 "a crash: exits 0"
has "$T/repo/docs/c-2026-11-03/council/receipt.md" "refused: ValueError: boom" "  the receipt says what it said last"
PRINCIPAL_COUNCIL="$T/nothing" python3 "$P" run --doc "$T/repo/docs/m-2026-11-03.md" --brief "$T/brief.md" --home "$T/repo" > /dev/null 2>&1
check "$?" 0 "none installed: exits 0"
has "$T/repo/docs/m-2026-11-03/council/receipt.md" "refused: council is not installed" "  the receipt says so"
I="$T/repo/docs/i-2026-11-03.md"; mkdir -p "$T/repo/docs/i-2026-11-03/council"; cp "$T/brief.md" "$T/repo/docs/i-2026-11-03/council/brief.md"
STUB_MODE=ok python3 "$P" run --doc "$I" --brief "$T/brief.md" --home "$T/repo" > /dev/null 2>"$T/err"
check "$?" 2 "a folder an interrupted run left: refused, never a traceback"
has "$T/err" "--again" "  naming --again"
STUB_MODE=ok python3 "$P" run --doc "$I" --brief "$T/brief.md" --home "$T/repo" --again > /dev/null 2>&1; check "$?" 0 "  --again moves it aside and runs"
check "$(jget "$T/repo/docs/i-2026-11-03/council/state.json" 'd["run"]["rc"]')" 0 "  …a fresh record"
check "$(python3 -c '
import sys; from importlib.machinery import SourceFileLoader as L
m = L("principal", sys.argv[1]).load_module(); m.call = lambda *a, **k: (_ for _ in ()).throw(KeyboardInterrupt)
try: m.main(["run", "--doc", sys.argv[2], "--brief", sys.argv[3], "--home", "/x"])
except KeyboardInterrupt: pass
import json; print(json.load(open(sys.argv[4]))["run"]["why"])' "$P" "$T/repo/docs/k-2026-11-03.md" "$T/brief.md" "$T/repo/docs/k-2026-11-03/council/state.json")" \
  "interrupted: \`principal run\` did not finish" "  a run interrupted mid-council leaves a record saying so"

echo "a paper holding a token's shape is not written into the repo"
L="$T/repo/docs/l-2026-11-03.md"; RL="$T/repo/docs/l-2026-11-03/council"
STUB_MODE=leak python3 "$P" run --doc "$L" --brief "$T/brief.md" --home "$T/repo" > /dev/null 2>&1; check "$?" 0 "exits 0"
STUB_MODE=ok python3 "$P" examine --doc "$L" --draft "$T/draft.md" > /dev/null 2>&1
check "$(ls "$RL/papers" | wc -l | tr -d ' ')" 2 "  two papers, the third left out"
check "$(grep -rl 'sk-ant-' "$RL" | wc -l | tr -d ' ')" 0 "  nothing in the record holds it"
has "$RL/receipt.md" "Not handed to the pen: codex (holds a sk-ant… token)" "  the receipt says which, by kind"

echo "an unattended caller: \$PRINCIPAL_COUNCIL is refused (council's own override rule); a row's 'timed out'"
check "$(python3 -c '
import os, sys; from importlib.machinery import SourceFileLoader as L
m = L("principal", sys.argv[1]).load_module()
os.environ["REGATTA_UNATTENDED"] = "1"; u = m.council_path()
os.environ.pop("REGATTA_UNATTENDED"); a = m.council_path()
print(u != os.environ["PRINCIPAL_COUNCIL"], a == os.environ["PRINCIPAL_COUNCIL"])' "$P")" "True True" \
  "  unattended: the override is not the council; attended: it is"
check "$(python3 -c '
import re, sys; from importlib.machinery import SourceFileLoader as L
m = L("principal", sys.argv[1]).load_module()
print(bool(re.search(m.said("timeout"), "| codex (a) | x | timed out after 1200 s |", re.I)),
      bool(re.search(m.said("timeout"), "| codex (a) | x | timeout |", re.I)),
      bool(re.search(m.said("refused"), "| codex (a) | x | ok |", re.I)))' "$P")" "True True False" \
  "  a row saying 'timed out' says the record's timeout, as keel reads it"

echo "usage"
python3 "$P" run --doc "$T/none/x.md" --brief "$T/brief.md" --home "$T/repo" >/dev/null 2>&1; check "$?" 2 "a doc whose folder does not exist: 2"
python3 "$P" examine --doc "$T/repo/docs/q-2026-11-03.md" --draft "$T/draft.md" >/dev/null 2>&1; check "$?" 2 "examine with no record: 2"
python3 "$P" check --doc "$T/repo/docs/q-2026-11-03.md" >/dev/null 2>&1; check "$?" 2 "check with no record: 2"
python3 "$P" >/dev/null 2>&1; check "$?" 2 "no verb: 2"
STUB_MODE=ok python3 "$P" run --doc "$X" --brief "$T/brief.md" --home "$T/repo" --again >/dev/null 2>&1; check "$?" 0 "--again: a fresh record"
check "$(ls -d "$T/repo/docs/x-2026-11-03/council-"* | wc -l | tr -d ' ')" 1 "  the old one moved aside"
for _ in 1 2; do PRINCIPAL_COUNCIL="$T/nothing" python3 "$P" run --doc "$X" --brief "$T/brief.md" --home "$T/repo" --again >/dev/null 2>&1 || echo bad; done > "$T/out"
check "$(cat "$T/out")/$(ls -d "$T/repo/docs/x-2026-11-03/council-"* | wc -l | tr -d ' ')" "/3" "  --again twice in a second: each old record aside under its own name"

if [ "$fails" = 0 ]; then echo "principal: all passed"; else echo "principal: $fails failed"; fi
[ "$fails" = 0 ]
