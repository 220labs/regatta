#!/usr/bin/env bash
# lighthouse's bin/reef: the bounds it reads (and `regatta limit`'s trial read of them), the rule that moves a host's
# check slots and run cap by its load, `apply` through a stand-in `regatta limit` that checks its arguments as the real
# one does, the cooldown, the unattended refusal, and the sweep's hand-off from `hosts`. Scratch HOME and config dir;
# every name made up (host `host-a`).
#   bash modules/lighthouse/tests/reef.sh
set -u
for v in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH[A-Za-z0-9_]*\)=.*/\1/p; s/^\(REEF_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset REGATTA_HOME REGATTA_UNATTENDED AUTOFINISH_CALLER_UNATTENDED
C="$(cd "$(dirname "$0")/.." && pwd)"; R="$(cd "$C/../.." && pwd -P)"
RF="$C/bin/reef"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home" REGATTA_CONFIG="$T/config"; LC="$HOME"; LC="${LC%/}/Library/Caches/lighthouse"
mkdir -p "$HOME" "$REGATTA_CONFIG/lighthouse" "$T/bin"
echo "$R" > "$REGATTA_CONFIG/home"
export REEF_HOST=host-a
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:400}]"; fails=$((fails+1));; esac; }
hasnt() { case "$1" in *"$2"*) echo "  FAIL $3: [$2] in [${1:0:400}]"; fails=$((fails+1));; *) echo "  ok   $3";; esac; }
line() { printf '%s\n' "$@" > "$REGATTA_CONFIG/lighthouse/reef"; }

echo "-- the bounds"
rm -f "$REGATTA_CONFIG/lighthouse/reef"
check "$(python3 "$RF" bounds 2>/dev/null)" "mode=advise" "no line: advise"
line "host-a:mode=on,run=1-4,check=1-2"
check "$(python3 "$RF" bounds 2>/dev/null)" "mode=on,run=1-4,check=1-2" "a host's line, read back in its words"
line "host-a:check=1-2, run=2-3"
check "$(python3 "$RF" bounds 2>/dev/null)" "run=2-3,check=1-2" "no mode said: none printed (advise)"
line "*:mode=advise,run=1-3,check=1-3"
check "$(python3 "$RF" bounds 2>/dev/null)" "mode=advise,run=1-3,check=1-3" "the *: line serves a host without one"
line "host-a:mode=off" "*:mode=on,run=1-3,check=1-3"
check "$(python3 "$RF" bounds 2>/dev/null)" "mode=off" "the host's own line before *:"
for bad in "host-a:mode=on" "host-a:mode=on,run=1-3" "host-a:run=3-1" "host-a:run=0-2" "host-a:run=1-40" "host-a:mode=onn" \
           "host-a:runs=1-2" "host-a:run=1-2,run=1-3" "host-a:" "host-a:run=1" "host-a:mode"; do
  line "$bad"; python3 "$RF" bounds >/dev/null 2>&1; check "$?" "2" "refused: $bad"
done
line "no colon here"; python3 "$RF" bounds >/dev/null 2>&1; check "$?" "2" "refused: a line without <host>:"

echo "-- regatta limit's trial read of the key"
cat > "$T/trial.py" <<'PY'
import importlib.machinery, importlib.util, sys
p = sys.argv[1] + "/modules/regatta/libexec/limit"
spec = importlib.util.spec_from_loader("limit", importlib.machinery.SourceFileLoader("limit", p))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
tab = m.table()
s = tab.get("lighthouse/reef")
if not s:
    print("no key"); sys.exit()
print(s["shape"], s["star"], m.trial("lighthouse/reef", s, sys.argv[2], sys.argv[3]) or "takes it")
PY
check "$(python3 "$T/trial.py" "$R" host-a "host-a:mode=on,run=1-3,check=1-2" 2>&1)" "host True takes it" "limit takes a good line"
check "$(python3 "$T/trial.py" "$R" host-a "host-a:check=1-2,mode=on,run=1-3" 2>&1)" "host True takes it" "limit takes it in another order"
check "$(python3 "$T/trial.py" "$R" '*' "*:mode=advise" 2>&1)" "host True takes it" "limit's reader takes a *: line (the base file's; set takes <host>: or --all)"
has "$(python3 "$T/trial.py" "$R" host-a "host-a:mode=on" 2>&1)" "its reader refuses it" "limit refuses mode=on without ranges"
has "$(python3 "$T/trial.py" "$R" host-a "host-a:run=5-2" 2>&1)" "its reader refuses it" "limit refuses a floor over its ceiling"

echo "-- the rule"
cat > "$T/rule.py" <<'PY'
import importlib.machinery, importlib.util, json, sys
spec = importlib.util.spec_from_loader("reef", importlib.machinery.SourceFileLoader("reef", sys.argv[1]))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
NOW = 1_000_000
def row(loads, avail=60.0, rate=0.0, busy=2, cap=3, a_lim=15.0, r_lim=30.0):
    hist = [[NOW - 600 * (len(loads) - 1 - i), l, avail, rate] for i, l in enumerate(loads)]
    return {"host": "host-a", "at": NOW, "history": hist, "mem": {"avail": avail, "rate": rate},
            "limits": {"load_max": 1.5, "avail": a_lim, "rate": r_lim, "cap": cap}, "slots": {"busy": busy, "cap": cap}}
ON = {"mode": "on", "run": (1, 4), "check": (1, 3)}
def show(p):
    return "%s %s %s | %s" % (p["state"], ";".join("%s:%d>%d" % c[:3] for c in p["changes"]) or "-", p["note"] or "", p["why"])
cases = {
  "hot-check": (row([2.5, 2.8, 3.0]), ON, {"run": 3, "check": 2}, None),
  "hot-run": (row([2.5, 2.8, 3.0]), ON, {"run": 3, "check": 1}, None),
  "hot-floor": (row([2.5, 2.8, 3.0]), ON, {"run": 1, "check": 1}, None),
  "hot-mem": (row([0.2, 0.3, 0.2], avail=12.0), ON, {"run": 3, "check": 2}, None),
  "hot-swap": (row([0.2, 0.3, 0.2], rate=20.0), ON, {"run": 3, "check": 2}, None),
  "two-spike": (row([0.4, 3.9]), ON, {"run": 3, "check": 2}, None),
  "since-change": (row([2.5, 2.8, 3.0]), ON, {"run": 3, "check": 2}, NOW - 1150),
  "one-spike": (row([0.4, 3.9, 0.5]), ON, {"run": 3, "check": 2}, None),
  "cold-check": (row([0.1, 0.2, 0.1], busy=3), ON, {"run": 3, "check": 2}, None, 2),
  "cold-check-idle": (row([0.1, 0.2, 0.1], busy=3), ON, {"run": 3, "check": 2}, None, 1),
  "cold-check-unread": (row([0.1, 0.2, 0.1], busy=3), ON, {"run": 3, "check": 2}, None, None),
  "cold-run": (row([0.1, 0.2, 0.1], busy=3), ON, {"run": 3, "check": 3}, None),
  "cold-idle": (row([0.1, 0.2, 0.1], busy=1), ON, {"run": 3, "check": 3}, None),
  "cold-ceiling": (row([0.1, 0.2, 0.1], busy=4, cap=4), ON, {"run": 4, "check": 3}, None),
  "cold-swapping-before": (dict(row([0.1, 0.2, 0.1], busy=3), history=[[NOW - 1200, 0.1, 60, 5.0], [NOW - 600, 0.2, 60, 0], [NOW, 0.1, 60, 0]]), ON, {"run": 3, "check": 2}, None),
  "middle": (row([1.0, 1.1, 1.2]), ON, {"run": 3, "check": 2}, None),
  "few": (row([3.0]), ON, {"run": 3, "check": 2}, None),
  "old-points": (dict(row([3.0, 3.0, 3.0]), history=[[NOW - 9000, 3.0, 60, 0], [NOW - 8000, 3.0, 60, 0], [NOW, 3.0, 60, 0]]), ON, {"run": 3, "check": 2}, None),
  "cooldown": (row([2.5, 2.8, 3.0]), ON, {"run": 3, "check": 2}, NOW - 300),
  "cooled": (row([2.5, 2.8, 3.0]), ON, {"run": 3, "check": 2}, NOW - 1500),
  "over-ceiling": (row([0.1, 0.1]), ON, {"run": 6, "check": 2}, NOW - 60),
  "under-floor": (row([2.5, 2.8]), {"mode": "on", "run": (2, 4), "check": (1, 3)}, {"run": 1, "check": 2}, None),
  "off": (row([2.5, 2.8, 3.0]), {"mode": "off"}, {"run": 3, "check": 2}, None),
  "advise-no-bounds-hot": (row([2.5, 2.8, 3.0]), {"mode": "advise"}, {"run": 3, "check": 2}, None),
  "advise-no-bounds-cold": (row([0.1, 0.1, 0.1], busy=3), {"mode": "advise"}, {"run": 3, "check": 2}, None),
  "unread-check": (row([2.5, 2.8, 3.0]), ON, {"run": 3, "check": None}, None),
  "cold-unread-check": (row([0.1, 0.2, 0.1], busy=3), ON, {"run": 3, "check": None}, None, 5),
}
for name in sys.argv[2:]:
    r, b, cur, last, demand = (cases[name] + (None,))[:5]
    print(show(m.decide(r, b, cur, NOW, last, demand)))
PY
rule() { python3 "$T/rule.py" "$RF" "$1"; }
has "$(rule hot-check)" "hot check:2>1" "hot: a check slot given back first"
has "$(rule hot-run)" "hot run:3>2" "hot, checks at their floor: a run slot"
has "$(rule hot-floor)" "every floor" "hot at both floors: said, nothing changed"
has "$(rule hot-mem)" "hot check:2>1" "hot by free memory under 1.2× headroom's avail"
has "$(rule hot-swap)" "hot check:2>1" "hot by swapping over half headroom's rate"
has "$(rule one-spike)" "hold -" "one spike in three samples: the median holds"
has "$(rule two-spike)" "2 sample(s)" "two samples, one a spike: no median of two, holds"
has "$(rule since-change)" "2 sample(s) in the last 35 min since the last change" "past the cooldown, only the samples since the change count"
has "$(rule cold-check)" "cold check:2>3" "cold, checks filling both slots: a check slot back first"
has "$(rule cold-check-idle)" "1 of 2 check slots" "cold with a check slot free: check slots hold"
has "$(rule cold-check-unread)" "? of 2 check slots" "cold, check demand unread: check slots hold"
has "$(rule cold-run)" "cold run:3>4" "cold, checks at their ceiling, every slot busy: a run slot"
has "$(rule cold-idle)" "no need to grow" "cold with slots free: the cap holds"
has "$(rule cold-ceiling)" "every ceiling" "cold at both ceilings: holds"
has "$(rule cold-swapping-before)" "hold -" "swapping inside the window: no growth"
has "$(rule middle)" "hold -" "between the bands: holds"
has "$(rule few)" "1 sample(s)" "one sample: holds, says why"
has "$(rule old-points)" "1 sample(s)" "samples older than the window do not count"
has "$(rule cooldown)" "held: the last change was 5 min ago" "a change 5 min ago: held"
has "$(rule cooled)" "hot check:2>1" "a change 25 min ago: free again"
has "$(rule over-ceiling)" "run:6>4" "a cap over the ceiling comes back inside, cooldown or not"
has "$(rule under-floor)" "run:1>2" "a cap under the floor comes back inside"
has "$(rule off)" "off (lighthouse/reef)" "mode=off: nothing"
has "$(rule advise-no-bounds-hot)" "hot check:2>1" "advise with no bounds still says what a hot host gives back"
has "$(rule advise-no-bounds-cold)" "no bounds to grow into" "advise with no bounds never grows"
has "$(rule unread-check)" "hot run:3>2" "check slots unread: the run cap gives"
has "$(rule cold-unread-check)" "check-slots unread: holds" "cold, check slots unread: the run cap does not grow past them"

echo "-- apply"
# the stand-in `regatta`: `limit get <key> --on <host>` and `limit set <key> <host>:<n>` only, as the real one takes them
cat > "$T/bin/regatta" <<PY
#!/usr/bin/env python3
import json, os, sys
st = "$T/limits.json"
d = json.load(open(st)) if os.path.exists(st) else {}
a = sys.argv[1:]
open("$T/calls", "a").write(" ".join(a) + " LIMIT_HOST=%s\n" % os.environ.get("LIMIT_HOST"))
keys = ("wharf-runs/run-cap", "wharf-runs/check-slots")
if a[:2] == ["limit", "get"] and len(a) == 5 and a[2] in keys and a[3] == "--on":
    print("%s  %s  %s  live" % (a[2], a[4], d.get(a[2], {}).get(a[4], 3))); sys.exit()
if a[:2] == ["limit", "set"] and len(a) == 4 and a[2] in keys and ":" in a[3]:
    h, n = a[3].split(":")
    if not n.isdigit() or os.environ.get("STUB_FAIL"):
        print("regatta limit: refused", file=sys.stderr); sys.exit(2)
    d.setdefault(a[2], {})[h] = int(n); json.dump(d, open(st, "w")); sys.exit()
print("regatta: the stand-in takes limit get KEY --on HOST and limit set KEY HOST:N, not %s" % a, file=sys.stderr); sys.exit(2)
PY
chmod +x "$T/bin/regatta"; export REEF_TOOL_REGATTA="$T/bin/regatta"
mkrow() {   # loads… → $T/row.json, sampled now
  python3 - "$T/row.json" "$@" <<'PY'
import json, sys, time
now = int(time.time()); loads = [float(x) for x in sys.argv[2:]]
hist = [[now - 600 * (len(loads) - 1 - i), l, 60.0, 0.0] for i, l in enumerate(loads)]
json.dump({"host": "host-a", "at": now, "history": hist, "mem": {"avail": 60.0, "rate": 0.0},
           "limits": {"load_max": 1.5, "avail": 15.0, "rate": 30.0, "cap": 3}, "slots": {"busy": 3, "cap": 3}}, open(sys.argv[1], "w"))
PY
}
printf '{"wharf-runs/run-cap": {"host-a": 3}, "wharf-runs/check-slots": {"host-a": 3}}' > "$T/limits.json"
line "host-a:mode=on,run=1-4,check=1-3"
mkrow 2.6 2.9 3.1
out=$(python3 "$RF" apply --row "$T/row.json" 2>&1); check "$?" "0" "apply: exit 0"
has "$out" "change wharf-runs/check-slots 3 → 2" "apply says the change"
has "$(cat "$T/calls")" "limit set wharf-runs/check-slots host-a:2 LIMIT_HOST=host-a" "apply writes through regatta limit set, naming its host"
check "$(python3 -c "import json;print(json.load(open('$T/limits.json'))['wharf-runs/check-slots']['host-a'])")" "2" "the stand-in holds 2"
has "$(python3 "$RF" log)" "check-slots 3 → 2  done" "the ledger records it done"
: > "$T/calls"
out=$(python3 "$RF" apply --row "$T/row.json" 2>&1)
has "$out" "held: the last change was 0 min ago" "a second turn inside the cooldown holds"
hasnt "$(cat "$T/calls")" "limit set" "and writes nothing"
rm -f "$LC/reef.jsonl"; : > "$T/calls"
STUB_FAIL=1 python3 "$RF" apply --row "$T/row.json" >/dev/null 2>&1; check "$?" "3" "a refused write: exit 3"
has "$(python3 "$RF" log)" "FAILED" "and the ledger says FAILED"
has "$(python3 "$RF" plan --row "$T/row.json")" "held:" "a failed write starts the cooldown too (never a write every sweep)"
rm -f "$LC/reef.jsonl"; : > "$T/calls"
line "host-a:mode=advise,run=1-4,check=1-3"
out=$(python3 "$RF" apply --row "$T/row.json" 2>&1)
has "$out" "would change wharf-runs/check-slots 2 → 1" "advise: says what it would do"
hasnt "$(cat "$T/calls")" "limit set" "advise: writes nothing"
has "$(python3 "$RF" log)" "advised" "advise: the ledger says advised"
line "host-a:mode=on,run=1-4,check=1-3"; : > "$T/calls"
REGATTA_UNATTENDED=1 python3 "$RF" apply --row "$T/row.json" >/dev/null 2>&1; check "$?" "2" "apply under an unattended caller: refused"
AUTOFINISH_CALLER_UNATTENDED=1 python3 "$RF" apply --row "$T/row.json" >/dev/null 2>&1; check "$?" "2" "and under a peer's unattended caller"
hasnt "$(cat "$T/calls")" "limit" "an unattended caller reads and writes nothing"
REGATTA_UNATTENDED=1 python3 "$RF" plan --row "$T/row.json" >/dev/null 2>&1; check "$?" "0" "plan stays open to an unattended caller"
python3 - "$T/row.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["at"] -= 3600; json.dump(d, open(sys.argv[1], "w"))
PY
out=$(python3 "$RF" apply --row "$T/row.json" 2>&1); check "$?" "4" "a row an hour old: exit 4"
has "$out" "no reading of now" "and says why"
python3 "$RF" apply --row "$T/nowhere.json" >/dev/null 2>&1; check "$?" "4" "no row: exit 4"
mkrow 2.6 2.9 3.1
python3 - "$T/row.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["host"] = "host-b"; json.dump(d, open(sys.argv[1], "w"))
PY
python3 "$RF" apply --row "$T/row.json" >/dev/null 2>&1; check "$?" "4" "another host's row: exit 4"

echo "-- the owner's hand set, mode=off, one turn at a time"
rm -f "$LC/reef.jsonl"; rm -f "$T/limits.json"; : > "$T/calls"
line "host-a:mode=on,run=1-4,check=1-3"; mkrow 2.6 2.9 3.1
python3 "$RF" apply --row "$T/row.json" >/dev/null 2>&1
python3 - "$LC/reef.jsonl" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
for r in rows: r["at"] -= 3600
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
python3 -c "import json;d=json.load(open('$T/limits.json'));d['wharf-runs/check-slots']['host-a']=3;json.dump(d,open('$T/limits.json','w'))"
: > "$T/calls"
out=$(python3 "$RF" apply --row "$T/row.json" 2>&1)
has "$out" "held: wharf-runs/check-slots 3 set by hand (reef left 2)" "a value reef never left there: held as the owner's word"
hasnt "$(cat "$T/calls")" "limit set" "and nothing written over it"
has "$(python3 "$RF" log)" "seen" "the ledger records what it saw"
has "$(python3 "$RF" plan --row "$T/row.json")" "held: the last change was 0 min ago" "the next turn holds a cooldown from the sighting"
line "host-a:mode=off"; : > "$T/calls"
check "$(python3 "$RF" apply --row "$T/row.json" 2>&1)" "" "mode=off: apply says nothing"
check "$(cat "$T/calls")" "" "and reads no limit"
line "host-a:mode=on,run=1-4,check=1-3"
python3 - "$LC/reef.lock" <<'PY' &
import fcntl, sys, time
f = open(sys.argv[1], "a"); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[1] + ".held", "w").close(); time.sleep(20)
PY
holder=$!
for _ in $(seq 1 50); do [ -f "$LC/reef.lock.held" ] && break; sleep 0.2; done
: > "$T/calls"
out=$(python3 "$RF" apply --row "$T/row.json" 2>&1); check "$?" "0" "a turn while another holds the lock: exit 0"
has "$out" "another reef turn is running here" "and says so"
check "$(cat "$T/calls")" "" "and reads and writes nothing"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; rm -f "$LC/reef.lock.held"

echo "-- check demand (check's slot folder)"
cat > "$T/demand.py" <<'PY'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader("reef", importlib.machinery.SourceFileLoader("reef", sys.argv[1]))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.check_demand())
PY
SD="$T/slots"; mkdir -p "$SD/slot-1" "$SD/queue"; sleep 30 & live=$!
echo "$live" > "$SD/slot-1/pid"; printf '%s\nx\n/w\n' "$live" > "$SD/queue/1.$live"; printf '999999\nx\n/w\n' > "$SD/queue/2.999999"
check "$(CHECK_SLOT_DIR="$SD" python3 "$T/demand.py" "$RF")" "1" "a live holder, its own ticket and a dead ticket: one check"
check "$(CHECK_SLOT_DIR="$T/none" python3 "$T/demand.py" "$RF")" "None" "no slot folder: unknown"
kill "$live" 2>/dev/null; wait "$live" 2>/dev/null

echo "-- the bounds through the core's entries reader"
printf '%s\n' "# reef's bounds" "host-a:" "mode=on,run=1-3,check=1-2 (set 2026-11-04)" > "$REGATTA_CONFIG/lighthouse/reef"
check "$(python3 "$RF" bounds 2>/dev/null)" "mode=on,run=1-3,check=1-2" "a comment, one word a line and a note: read as one entry"

echo "-- the sweep's hand-off (hosts reef_soon)"
cat > "$T/soon.py" <<'PY'
import importlib.machinery, importlib.util, json, sys, time
spec = importlib.util.spec_from_loader("hosts", importlib.machinery.SourceFileLoader("hosts", sys.argv[1]))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
row = json.load(open(sys.argv[2]))
p = m.reef_soon(row)
if p is None:
    print("not started"); sys.exit()
p.wait(60)
print("started", p.returncode)
PY
mkrow 2.6 2.9 3.1
rm -f "$REGATTA_CONFIG/lighthouse/reef" "$LC/reef.out" "$LC/reef.jsonl"
check "$(python3 "$T/soon.py" "$C/bin/hosts" "$T/row.json")" "not started" "no lighthouse/reef line: reef is not started"
line "host-b:mode=on,run=1-4,check=1-3"
check "$(python3 "$T/soon.py" "$C/bin/hosts" "$T/row.json")" "not started" "only another host's line: not started"
line "host-a:mode=advise"
check "$(python3 "$T/soon.py" "$C/bin/hosts" "$T/row.json")" "started 0" "this host's line: reef apply runs on the row"
has "$(cat "$LC/reef.out")" "reef host-a: hot" "its words land in reef.out"
check "$(python3 -c "import json;print(json.load(open('$LC/hosts-row.json'))['host'])")" "host-a" "the row it was handed is the sampler's"

echo
[ "$fails" -eq 0 ] && echo "reef: all passed" || { echo "reef: $fails failed"; exit 1; }
