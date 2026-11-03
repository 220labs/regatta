#!/usr/bin/env bash
# sextant north-star (Evolve S4): init, show and check against scratch config dirs and a stand-in
# cost-ratio file; no network, no model, any OS.
#   bash modules/sextant/tests/north_star.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: missing [$2] in [$1]"; fails=$((fails+1));; esac; }
hasnt() { case "$1" in *"$2"*) echo "  FAIL $3: found [$2] in [$1]"; fails=$((fails+1));; *) echo "  ok   $3";; esac; }
# the run's own inputs, none of the Mac's: the config dir, the ratios and the file's path
unset NORTH_STAR
export REGATTA_CONFIG="$T/cfg" COST_RATIO="$T/ratio.json"
mkdir -p "$T/cfg/sextant"
printf '{"providers": {"anthropic": {"ratio": 0.02, "week_ending": "2026-10-25"}, "codex": {"ratio": 0.075, "week_ending": "2026-10-25"}, "agy-gemini": {"ratio": 0.05, "week_ending": "2026-10-25"}}}\n' >"$T/ratio.json"
NS() { python3 "$D/bin/sextant" north-star "$@"; }
F="$T/cfg/sextant/north-star.json"
val() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."): d = d[k]
print(json.dumps(d) if isinstance(d, (dict, list)) else d)' "${2:-$F}" "$1"; }
edit() { python3 -c 'import json,sys
p, expr = sys.argv[1], sys.argv[2]; d = json.load(open(p)); exec(expr); json.dump(d, open(p, "w"), indent=2)' "$F" "$1"; }

echo "no file"
out=$(NS check 2>&1); rc=$?
check $rc 3 "check: maintenance only"
has "$out" "strategic allocation blocked" "  and says what is blocked"
NS show >/dev/null 2>&1; check $? 3 "show: the same exit, nothing printed as a North Star"
[ ! -e "$F" ]; check $? 0 "  nothing written by either"

echo "init — what the owner decided, nothing inferred"
out=$(NS init); check $? 0 "init writes the file"
has "$out" "0 goals" "  and counts the goals it imported"
check "$(val caps.builds_per_week)" 3 "builds a week: 3 (D2-B)"
check "$(val caps.builds_usd_list_per_week)" 45 "  builds spend: \$45 list"
check "$(val caps.soundings_per_week)" 2 "soundings a week: 2 (D1)"
check "$(val meta.trials_in_flight)" 1 "meta.trials_in_flight: 1"
has "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["provenance"]["meta.trials_in_flight"])' "$F")" "design default" "  written as the design's default, not the owner's answer"
check "$(val ceilings.weekly.claude.usd) $(val ceilings.weekly.claude.unit)" "10 effective" "Claude ceiling: \$10 effective"
check "$(val ceilings.weekly.codex.usd) $(val ceilings.weekly.codex.unit)" "150 list" "Codex ceiling: \$150 list"
check "$(val ceilings.weekly.gemini.usd) $(val ceilings.weekly.gemini.unit)" "350 list" "Gemini ceiling: \$350 list"
check "$(val framework_share.reservation)" None "framework share: no reservation (D26)"
check "$(val confidential_reservation)" None "confidential reservation: not set, the owner's"
check "$(val allowances)" '{"cash": null, "model": null, "ci": null, "host": null, "owner_attention": null}' "allowances: all empty"
check "$(val error_budgets)" "{}" "error budgets: none, the owner's"
out=$(NS init 2>&1); check $? 5 "a second init refuses to overwrite"
has "$out" "--force" "  and names the flag"
NS init --force >/dev/null; check $? 0 "--force replaces it"
NS check >/dev/null; check $? 3 "a fresh file has no complete goal: maintenance only"

echo "init — goals and ventures"
printf '# About\n\n## Work\n- not a goal\n\n## Goals (since: 2026-09-16)\n\n- Become productive\n  with agents\n- Earn on the side\n\n## Stack\n- not a goal either\n' >"$T/about.md"
mkdir "$T/v"
printf '# Venture One\n\nStatus: **Build** since 2026-09-13 · Time box: 2026-11-15\n\n## Gates\n\n1. evidence one\n   continued\n2. open: next step\n\n## Notes\n- not a gate\n' >"$T/v/one.md"
printf '# The folder\n' >"$T/v/README.md"
NS init --force --goals "$T/about.md" --ventures "$T/v" >/dev/null; check $? 0 "init with goals and ventures"
check "$(val goals | python3 -c 'import json,sys; g=json.load(sys.stdin); print(len(g), g[0]["id"], g[0]["outcome"], g[1]["outcome"])')" "2 g1 Become productive with agents Earn on the side" "  two goals from the bullets under Goals, a wrapped one joined"
check "$(val goals | python3 -c 'import json,sys; g=json.load(sys.stdin)[0]; print(g["measure"], g["horizon"], g["priority"])')" "None None None" "  measure, horizon and priority left to the owner"
check "$(val ventures | python3 -c 'import json,sys; v=json.load(sys.stdin); print(len(v), v[0]["id"], v[0]["title"]); print(v[0]["gates"])')" "1 one Venture One
['1. evidence one continued', '2. open: next step']" "  one venture, its README skipped, its gates joined and bounded by the next heading"
has "$(val ventures)" "Time box: 2026-11-15" "  its Status line copied"
NS init --force --goals "$T/nosuch.md" >/dev/null 2>&1; check $? 5 "an unreadable --goals file stops init"
check "$(val goals | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" 2 "  and leaves the file as it was"

echo "init — writes through the config dir's link"
mkdir "$T/vault"; rm -f "$F"; ln -s "$T/vault/ns.json" "$F"
NS init >/dev/null; check $? 0 "a link to where the owner keeps it (dangling): init writes the target"
[ -L "$F" ] && [ -f "$T/vault/ns.json" ]; check $? 0 "  the link stays a link, the vault holds the file"
NS check >/dev/null; check $? 3 "  and check reads through it"
rm -f "$F"; cp "$T/vault/ns.json" "$F"

echo "check — what the file permits"
complete='d["goals"] = [{"id": "g1", "outcome": "o", "measure": "m", "horizon": "h", "priority": 1}]'
edit "$complete"; out=$(NS check); check $? 0 "one complete goal: strategic allocation permitted"
has "$out" "ok: strategic allocation permitted" "  said so"
has "$out" "revision " "  with the revision"
edit 'd["goals"].append({"id": "g2", "outcome": "half"})'; out=$(NS check); check $? 0 "an incomplete goal beside a complete one: still permitted"
has "$out" "warning: goal g2: empty measure, horizon, priority" "  and warned of"
edit 'd["goals"] = [{"id": "g2", "outcome": "half"}]'; NS check >/dev/null; check $? 3 "only an incomplete goal: maintenance only"
edit "$complete"
edit 'd["mystery"] = 1'; out=$(NS check); check $? 0 "an unknown key is a warning, not a failure"
has "$out" "warning: mystery: not a key this verb knows" "  named"
edit "$complete"
for case in 'd["version"] = 2|version' 'd["goals"] = {}|goals: not a list' 'd["goals"].append(dict(d["goals"][0]))|twice' \
            'd["ceilings"]["weekly"]["claude"]["unit"] = "bucks"|unit' 'd["ceilings"]["weekly"]["codex"]["usd"] = -1|usd' \
            'd["caps"]["builds_per_week"] = "3"|builds_per_week' 'd["meta"]["trials_in_flight"] = True|trials_in_flight' \
            'd["ceilings"]["weekly"] = []|ceilings.weekly' 'd["error_budgets"] = []|error_budgets'; do
  edit "${case%%|*}"; out=$(NS check); rc=$?
  check $rc 4 "unusable: ${case%%|*}"
  has "$out" "${case##*|}" "  names it"
  NS init --force >/dev/null; edit "$complete"
done
edit 'del d["ceilings"]["weekly"]["gemini"]'; out=$(NS check); check $? 4 "a ceiling left out is unusable: a ceiling only narrows, so it fails closed"
has "$out" "ceilings.weekly.gemini: missing" "  naming the provider"
NS init --force >/dev/null; edit "$complete"
edit 'd["ceilings"]["weekly"]["Gemini"] = d["ceilings"]["weekly"].pop("gemini")'; out=$(NS check); check $? 4 "a ceiling under a misspelt provider key is unusable"
has "$out" "ceilings.weekly.Gemini: not a provider this verb knows" "  naming the unknown key"
has "$out" "ceilings.weekly.gemini: missing" "  and the provider it left without a ceiling"
NS init --force >/dev/null; edit "$complete"
edit 'd["goals"][0]["priority"] = "high"'; out=$(NS check); check $? 3 "a goal whose priority is no number is not counted"
has "$out" "is not a number" "  and says why"
edit 'd["goals"][0]["priority"] = 1; d["goals"][0]["measure"] = False'; NS check >/dev/null; check $? 3 "a boolean is no measure"
NS init --force >/dev/null; edit "$complete"
python3 -c 'import sys; b = open(sys.argv[1], "rb").read(); open(sys.argv[1], "wb").write(b"\xef\xbb\xbf" + b)' "$F"; NS check >/dev/null; check $? 0 "a byte-order mark an editor wrote reads"
NS init --force >/dev/null
ln -s "$T/unmounted/ns.json" "$T/gone-link.json"; out=$(NORTH_STAR="$T/gone-link.json" NS check 2>&1); check $? 4 "check: a link that leads nowhere is unusable, not absent"
has "$out" "leads nowhere" "  and says why"
mkdir -p "$T/cfg4"; ln -s "$T/unmounted2" "$T/cfg4/sextant"; NORTH_STAR="$T/cfg4/sextant/ns.json" NS check >/dev/null 2>&1; check $? 4 "  a folder link higher up too"
printf '{"goals": [' >"$F"; out=$(NS check); check $? 4 "a torn file is unusable, never maintenance-only by accident"
has "$out" "not JSON" "  and says why"
printf '[1]\n' >"$F"; NS check >/dev/null; check $? 4 "a file that is not an object is unusable"
out=$(NS check --json); check "$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["exit"], d["strategic"], len(d["errors"]))')" "4 False 1" "check --json carries the exit and the errors"
NS show >/dev/null 2>&1; check $? 4 "show: a torn file exits 4 too"

echo "show — ceilings in both columns"
NS init --force >/dev/null; edit "$complete"
out=$(NS show); check $? 0 "show prints"
has "$out" "strategic allocation: permitted" "  what it permits"
has "$out" "claude: \$500 list (\$10 effective), set in effective" "  Claude's list figure read from the ratio file (10 / 0.02)"
has "$out" "codex: \$150 list (\$11 effective), set in list" "  Codex's effective figure read from it (150 × 0.075)"
has "$out" "gemini: \$350 list (\$18 effective), set in list" "  Gemini's from the agy-gemini entry (350 × 0.05)"
has "$out" "  meta.trials_in_flight — design default" "  a default the owner did not give is marked"
has "$out" "  caps.control_slots_per_week — design default" "  the control slot too"
has "$out" "builds per week 3" "  the builds cap"
has "$out" "soundings per week 2" "  the soundings cap"
printf '{"providers": {"anthropic": {"ratio": 0.02}}}\n' >"$T/ratio.json"
out=$(NS show)
has "$out" "codex: \$150 list; the other column unknown: no usable ratio 'codex'" "a ceiling's provider the ratio file does not name: effective unknown, never the pay-per-use fallback"
has "$out" "gemini: \$350 list; the other column unknown: no usable ratio 'agy-gemini'" "  Gemini too"
printf '{"providers": {}}\n' >"$T/ratio.json"
out=$(NS show); has "$out" "claude: \$10 effective; the other column unknown" "no usable Anthropic ratio: the list column is unknown, never invented"
out=$(NS show --json); check "$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["strategic"], d["north_star"]["caps"]["builds_per_week"])')" "True 3" "show --json"

echo "the file is its own verb's business"
cat >"$T/api.py" <<'PY'
import sys
from importlib.machinery import SourceFileLoader
m = SourceFileLoader("sextant", sys.argv[1]).load_module()
print(m.status()["strategic"], bool(m.memo_line()))
PY
check "$(python3 "$T/api.py" "$D/bin/sextant")" "True False" "status() and memo_line() for a consumer: permitted, no memo line"
edit 'd["goals"] = []'
check "$(python3 "$T/api.py" "$D/bin/sextant")" "False True" "  and with no goals: blocked, and the memo's one line"
has "$(python3 -c 'import sys; from importlib.machinery import SourceFileLoader as L; print(L("s", sys.argv[1]).load_module().memo_line())' "$D/bin/sextant")" "already-authorised maintenance runs, strategic allocation is blocked" "  worded as the design words it"
printf 'torn' >"$F"
if [ -d "$D/../regatta/hooks" ]; then
  ! grep -rn 'north-star\|north_star' "$D/../regatta/hooks" >/dev/null; check $? 0 "no core hook names the file: config_problems() never validates it, a torn file breaks only this verb"
else echo "  skip no core hook names the file (the core's hooks folder is not beside this module)"; fi
NORTH_STAR="$T/elsewhere.json" NS init >/dev/null; [ -f "$T/elsewhere.json" ]; check $? 0 "NORTH_STAR names another file"

echo "off-shape files: show never crashes where check judged"
NS init --force >/dev/null; edit "$complete"
for case in 'd["ceilings"]["weekly"] = None' 'd["ceilings"]["weekly"]["claude"]["ratio_key"] = 5' 'd["ceilings"]["weekly"]["codex"]["usd"] = float("inf")' 'del d["caps"]' 'd["version"] = True'; do
  edit "$case"; out=$(NS show 2>&1); rc=$?
  hasnt "$out" "Traceback" "show: $case, no traceback"
  check $rc 0 "  and it still prints (check says what is wrong)"
  NS check >/dev/null; check $? 4 "  while check calls it unusable"
  NS init --force >/dev/null; edit "$complete"
done
edit 'd["goals"][0].update(measure=" ", horizon={}, priority=[])'; NS check >/dev/null; check $? 3 "a goal whose measure, horizon and priority are blank text or empty is not complete"
edit 'd["goals"][0].update(measure="m", horizon="h", priority=0)'; NS check >/dev/null; check $? 0 "  while a priority of 0 is a value"
edit 'del d["caps"]["soundings_per_week"]'; out=$(NS check); check $? 4 "a deleted cap is an error (every cap is a North Star line)"
has "$out" "caps.soundings_per_week" "  and names it"

echo "init — inputs"
printf '# P\n\n## Non-goals\n- home automation\n\n## Goals\n\n- ship regatta\n  - a sub-bullet\n\n### Detail\n\n- second goal\n\n```\n# a comment\n- in a fence\n```\n\n## Stack\n- nope\n' >"$T/p.md"
NS init --force --goals "$T/p.md" >/dev/null
check "$(val goals | python3 -c 'import json,sys; print([g["outcome"] for g in json.load(sys.stdin)])')" "['ship regatta - a sub-bullet', 'second goal']" "goals: Non-goals is not Goals, a sub-bullet joins its goal, a sub-heading and a fence stay inside"
NS init --force --ventures "$T/nosuch" >/dev/null 2>&1; check $? 5 "a --ventures folder that is not there stops init"
NS init --force >/dev/null; chmod 640 "$F"; NS init --force >/dev/null
check "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$F")" 0o640 "--force keeps the file's mode (a vault's readers)"
rm -f "$F".prev*; edit 'd["caps"]["builds_per_week"] = 7'; NS init --force >/dev/null
check "$(val caps.builds_per_week "$F.prev")" 7 "--force keeps the replaced file beside it as .prev"
NS init --force >/dev/null; check "$(val caps.builds_per_week "$F.prev.1")" 7 "  a second --force moves the older .prev to .prev.1, never over it"
rm -f "$F".prev*
ls -a "$T/cfg/sextant" | grep -q '^\.north-star\.'; check $? 1 "  and leaves no temp file"
NS init --force >/dev/null
printf '# D\n\n### Goals\n\n1. numbered\n2. second\n\n### Stack\n- not a goal\n' >"$T/h3.md"; printf '# Goals\n- one\n\n## Detail\n- two\n\n# Next\n- no\n' >"$T/h1.md"
NS init --force --goals "$T/h3.md" >/dev/null; check "$(val goals | python3 -c 'import json,sys; print([g["outcome"] for g in json.load(sys.stdin)])')" "['numbered', 'second']" "goals under an H3 Goals heading: numbered items count, a sibling H3 ends the section"
NS init --force --goals "$T/h1.md" >/dev/null; check "$(val goals | python3 -c 'import json,sys; print([g["outcome"] for g in json.load(sys.stdin)])')" "['one', 'two']" "  under an H1: a deeper heading stays inside, the next H1 ends it"
printf '# V\n\n## Gates\n\n### Evidence\n\n1. one\n   - detail\n2. two\n\n```\n# c\n```\n\n## Notes\n' >"$T/v/two.md"
NS init --force --ventures "$T/v" >/dev/null; check "$(val ventures | python3 -c 'import json,sys; v=[x for x in json.load(sys.stdin) if x["id"]=="two"][0]; print(v["gates"])')" "['1. one - detail', '2. two']" "venture gates: a sub-heading stays inside, a sub-bullet joins its gate"
rm "$T/v/two.md"
mkdir "$T/ro"; chmod 555 "$T/ro"
if [ "$(id -u)" = 0 ]; then echo "  skip an unwritable folder (root writes anywhere)"; else
NORTH_STAR="$T/ro/sub/ns.json" NS init >/dev/null 2>&1; rc=$?; chmod 755 "$T/ro"
check $rc 5 "an unwritable folder: exit 5, no traceback"; fi
chmod 755 "$T/ro"
NS init --force >/dev/null; edit 'd["ceilings"]["weekly"]["claude"]["usd"] = 10**400'; out=$(NS check 2>&1); rc=$?
check $rc 4 "an int too large for a float: a shape error (exit 4), not a crash"
hasnt "$out" "Traceback" "  and no traceback"; out=$(NS show 2>&1); hasnt "$out" "Traceback" "  show never crashes on it either"
printf 'import sys\nfrom importlib.machinery import SourceFileLoader as L\nm = L("s", sys.argv[1]).load_module()\nprint(m.status([1])["strategic"])\n' >"$T/shape.py"
check "$(python3 "$T/shape.py" "$D/bin/sextant")" "False" "status() of a doc that is no object: blocked, not a crash"
NS init --force >/dev/null; edit 'd["goals"] = [{"id": "g1", "outcome": "o", "measure": "m", "horizon": "h", "priority": 1}]'; cp "$F" "$T/before.json"
printf '# About\n\n## Aims\n- x\n' >"$T/noheading.md"; NS init --force --goals "$T/noheading.md" >/dev/null 2>&1; check $? 5 "--goals with no bullets under a Goals heading: exit 5"
check "$(cmp -s "$F" "$T/before.json"; echo $?)" 0 "  and the owner's file is as it was"
printf '# V\n\nStatus: wrapped (a note that\n  runs on) ·\nRepos: x\n\n## Gates\n1. g\n' >"$T/v/wrap.md"
NS init --force --ventures "$T/v" >/dev/null; check "$(val ventures | python3 -c 'import json,sys; print([x for x in json.load(sys.stdin) if x["id"]=="wrap"][0]["status"])')" "Status: wrapped (a note that runs on)" "a wrapped Status line is whole, its trailing separator and the next key line left out"
rm "$T/v/wrap.md"
printf '# V\n\n## Gates\n\nEach gate needs a date:\n\n1. one\n2. two\n' >"$T/v/intro.md"
NS init --force --ventures "$T/v" >/dev/null; check "$(val ventures | python3 -c 'import json,sys; print([x for x in json.load(sys.stdin) if x["id"]=="intro"][0]["gates"])')" "['1. one', '2. two']" "a Gates intro sentence ending in a colon is no gate"
rm "$T/v/intro.md"
printf '# V\n\n## Gates\n\nFour gates, each dated.\n\n1. one\n2. two\n\nAll four must hold before money.\n' >"$T/v/tail.md"
NS init --force --ventures "$T/v" >/dev/null; check "$(val ventures | python3 -c 'import json,sys; print([x for x in json.load(sys.stdin) if x["id"]=="tail"][0]["gates"])')" "['1. one', '2. two']" "gates: an intro sentence and trailing prose are no gates"
rm "$T/v/tail.md"
printf '# V\n\n## Gates\n\n1. one\n2. two\n\nAll four must hold\nbefore money.\n' >"$T/v/tail2.md"
NS init --force --ventures "$T/v" >/dev/null; check "$(val ventures | python3 -c 'import json,sys; print([x for x in json.load(sys.stdin) if x["id"]=="tail2"][0]["gates"])')" "['1. one', '2. two']" "  a two-line trailer too"
rm "$T/v/tail2.md"
printf '# V\n\n## Gates\n\n**Pain** — open\n\n**Wallet** — open\n\n- a later note\n' >"$T/v/para.md"
printf '# W\n\n## Gates\n\n**Pain** — open\n\n**Wallet** — open\n' >"$T/v/para2.md"
NS init --force --ventures "$T/v" >/dev/null; check "$(val ventures | python3 -c 'import json,sys; print([x for x in json.load(sys.stdin) if x["id"]=="para2"][0]["gates"])')" "['**Pain** — open', '**Wallet** — open']" "gates written as paragraphs: one each"
NS init --force --ventures "$T/v" >/dev/null; check "$(val ventures | python3 -c 'import json,sys; print([x for x in json.load(sys.stdin) if x["id"]=="para"][0]["gates"])')" "['**Pain** — open', '**Wallet** — open', '- a later note']" "  bold-led paragraph gates stay beside a later item"
rm "$T/v/para.md" "$T/v/para2.md"
printf '# V\n\n## Gates\n\n1. one\n\n#2 is the hard one\n2. two\n' >"$T/v/hash.md"
NS init --force --ventures "$T/v" >/dev/null; check "$(val ventures | python3 -c 'import json,sys; print([x for x in json.load(sys.stdin) if x["id"]=="hash"][0]["gates"])')" "['1. one', '2. two']" "a #-led line is text, not a heading"
rm "$T/v/hash.md"
mkdir "$T/emptyv"; printf '# r\n' >"$T/emptyv/README.md"; NS init --force --ventures "$T/emptyv" >/dev/null 2>&1; check $? 5 "--ventures with no venture file: exit 5"
printf '# About\n\n## Goals 2027\n- a goal\n\n### Why not now matters\n- still a goal\n' >"$T/g27.md"
NS init --force --goals "$T/g27.md" >/dev/null; check "$(val goals | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" 2 "a Goals heading with a suffix reads, and a sub-heading merely mentioning not now stays inside"
NS init --force >/dev/null
ln -s "$T/missing-drive/ns.json" "$T/dangling.json"; NORTH_STAR="$T/dangling.json" NS init >/dev/null 2>&1; check $? 5 "a link into a folder that is not there: exit 5"
[ ! -e "$T/missing-drive" ]; check $? 0 "  and no folder built for it"
mkdir -p "$T/cfg2"; ln -s "$T/gone/vault" "$T/cfg2/sextant"; NORTH_STAR="$T/cfg2/sextant/ns.json" NS init >/dev/null 2>&1; check $? 5 "a link to a missing folder higher up the path: exit 5"
[ ! -e "$T/gone" ]; check $? 0 "  and no folder built for it"
mkdir -p "$T/cfg3" "$T/vault5"; ln -s "$T/vault5/sextant" "$T/cfg3/sextant"; NORTH_STAR="$T/cfg3/sextant/ns.json" NS init >/dev/null 2>&1; check $? 5 "a folder link whose target is missing, its parent there: exit 5"
[ ! -e "$T/vault5/sextant" ]; check $? 0 "  and the folder not built through it"
printf '# About\n\n## Goals\n- one\n\n~~~\n# not a heading\n~~~\n\n- two\n' >"$T/tf.md"
NS init --force --goals "$T/tf.md" >/dev/null; check "$(val goals | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" 2 "a ~~~ fence hides a # line too"
printf '# About\n\n## Goals\n- one\n\n~~~markdown\n```\n## Stack\n```\n~~~\n\n- two\n' >"$T/tf2.md"
NS init --force --goals "$T/tf2.md" >/dev/null; check "$(val goals | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" 2 "  a backtick fence inside a tilde fence closes nothing"
printf '# V\n\nStatus: Build\n- Repos: a\n\n## Gates\n1. g\n' >"$T/v/bul.md"
NS init --force --ventures "$T/v" >/dev/null; check "$(val ventures | python3 -c 'import json,sys; print([x for x in json.load(sys.stdin) if x["id"]=="bul"][0]["status"])')" "Status: Build" "a Status stops at a list item"
rm "$T/v/bul.md"
printf '# About\n\n## Goal-setting process\n- a step\n\n## Goals\n- real\n\n### Non-goals\n- home automation\n' >"$T/ng.md"
NS init --force --goals "$T/ng.md" >/dev/null; check "$(val goals | python3 -c 'import json,sys; print([g["outcome"] for g in json.load(sys.stdin)])')" "['real']" "goals: Goal-setting is not the heading, a deeper Non-goals ends the list"
python3 -c 'print("["*100000)' >"$F"; out=$(NS check 2>&1); rc=$?
check $rc 4 "a file nested 100000 deep: unusable (exit 4), not a crash"; hasnt "$out" "Traceback" "  and no traceback"
for depth in 985 988 991 994; do
  python3 -c 'import sys; n=int(sys.argv[1]); print("{\"x\": " + "["*n + "]"*n + "}")' "$depth" >"$F"
  out=$(NS check 2>&1); rc=$?; check $rc 4 "an object nested $depth deep: unusable, never a crash"; hasnt "$out" "Traceback" "  and no traceback"
  out=$(NS show 2>&1); hasnt "$out" "Traceback" "  show neither"
done
rm -f "$F"; NS init >/dev/null
check "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$F")" "0o600" "a new North Star file is private (0600)"
NS init --force >/dev/null; edit 'd["ceilings"]["weekly"]["gemini"]["usd"] = 0'; NS check >/dev/null; check $? 3 "a ceiling of 0 is a value (forbids the provider), not an error"
printf '{"providers": {"anthropic": {"ratio": 0.02}}}\n' >"$T/ratio.json"
edit 'd["ceilings"]["weekly"]["claude"]["usd"] = 1e308'; out=$(NS show 2>&1); has "$out" " effective; the other column unknown: no usable ratio 'anthropic'" "  show prints an overflowing column as unknown"
hasnt "$out" "Traceback" "  and never crashes on it"
NS init --force >/dev/null; edit 'd["ceilings"]["weekly"]["gemini"]["ratio_key"] = ""'; out=$(NS show 2>&1); has "$out" "gemini: not readable" "an empty ratio_key reads as broken in show too, as in check"
NS check --json >/dev/null; check "$(NS check --json | python3 -c 'import json,sys; print("why" in json.load(sys.stdin))')" True "check --json always carries why"
NS init --force >/dev/null
echo '{' >"$F"; check "$(NS check --json | python3 -c 'import json,sys; print("why" in json.load(sys.stdin))')" True "  torn file too"
NS init --force >/dev/null
edit 'd["goals"] = [{"id": "g1", "outcome": "o", "measure": "m", "horizon": "h", "priority": 0}]'; out=$(NS show); has "$out" "priority 0" "show prints a priority of 0, as check counts it"

echo "usage and the public rule"
NS >/dev/null 2>&1; check $? 2 "north-star without a verb: exit 2"
python3 "$D/bin/sextant" >/dev/null 2>&1; check $? 2 "no command: exit 2"
python3 "$D/bin/sextant" north-star bogus >/dev/null 2>&1; check $? 2 "an unknown verb: exit 2"
NS init --bogus >/dev/null 2>&1; check $? 2 "an unknown flag: exit 2"
! grep -n '/Users/\|@' "$D/bin/sextant" >/dev/null; check $? 0 "bin/sextant names no home path or address (the publish gate holds the word list)"

if [ "$fails" = 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
