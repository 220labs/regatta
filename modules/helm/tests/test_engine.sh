#!/usr/bin/env bash
# Tests for the Engine room (docs/engine-room-2026-11-02.md S3): the adapter's proof and the view's html in node
# (tests/engine_proof.js on tests/engine_fixture.js, the real tools' shapes); the poll's document (helm_render's
# engine_state: the five reads through the page's field allowlist, each source with its own state and `at`, a read that
# fails unread, never zero); board_sig over it (no ages, gauges or history); overview() writing engine.json beside
# state.json and into the page; then, under headless Chrome, the view at 1440, 720 and a true 390, both themes and both
# roads, read by tests/engine_selftest.js. Chrome runs on a Mac only, as test_board.sh's frames, unless
# HELM_BOARD_ANY_OS=1 asks for it elsewhere (KEEL_CHROME names the browser). No network, no model.
#   bash modules/helm/tests/test_engine.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
TD="$(cd "$(dirname "$0")" && pwd)"
export REGATTA_HOME="$(cd "$B/../../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$TD/config_fixture.sh"; fixture_config "$T/config"
export PLANS_DIR="$T/plans" PLAN_HOST=testhost PLAN_PROJECTS_DIR="$T/projects" PLAN_CACHE_DIR="$T/cache" HOME="$T/home" \
  PLAN_NO_GH=1 PLAN_NO_DEPLOY=1 SURFACES_FILE="$T/surfaces.json" ASK_SESSIONS_DIR="$T/sess" ASK_CACHE_DIR="$T/askcache" \
  COST_RATIO="$T/ratio.json" PLAN_NO_MEMO=1 PLAN_PROJECTS_ROOT="$T/projects-root" \
  STALLS_PEERS= STALLS_REPOS= STALLS_ORCA=0 STALLS_CANARY=0 PLAN_NO_WHARF=1   # test_helm.sh's guards: no ssh, no Orca app, no real repo
unset CLAUDE_CONFIG_DIR PLAN_NO_HOSTS HELM_HOSTS HELM_OPS
unset CLAUDE_CODE_SESSION_ID CLAUDE_UNATTENDED REGATTA_UNATTENDED CLAUDE_CODE_DISABLE_BACKGROUND_TASKS HELM_BOARD_POLL
printf %s "{\"providers\": {\"anthropic\": {\"ratio\": 0.0166, \"week_ending\": \"2026-11-01\"}}}" > "$T/ratio.json"
mkdir -p "$HOME" "$PLANS_DIR" "$PLAN_PROJECTS_DIR" "$T/config/lighthouse"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }

echo "the adapter's proof and the view's html (node: tests/engine_proof.js)"
if ! command -v node >/dev/null; then
  echo "  FAIL node is not on PATH: the Engine room's adapter proof needs it"; fails=$((fails+1))
else
  node "$TD/engine_proof.js" > "$T/proof.out" 2>&1; prc=$?
  sed -n 's/^PASS /  ok   /p; s/^FAIL /  FAIL /p' "$T/proof.out"
  n=$(grep -c '^FAIL' "$T/proof.out"); fails=$((fails+n))
  [ "$prc" = 0 ] || [ "$n" != 0 ] || { echo "  FAIL the proof exited $prc: $(tail -3 "$T/proof.out")"; fails=$((fails+1)); }
  check "$(grep -c '^PASS' "$T/proof.out")" "89" "the proof ran every case (89)"
fi

# the stubs: a hosts tool and an ops tool that print what the real ones may, private fields included
cat > "$T/hosts-stub.py" <<'PY'
import json, os, sys, time
mode = open(os.environ["STUB_MODE"]).read().strip() if os.environ.get("STUB_MODE") else "ok"
if mode == "fail":
    sys.exit(1)
now = float(os.environ.get("STUB_NOW") or time.time())
age = float(os.environ.get("STUB_AGE") or 0)
row = lambda name, at, **kw: dict({"host": name, "os": "Linux", "at": at, "source": "ref", "cores": 8, "ram_gb": 32,
    "load": {"per_core_5m": 0.4 + age / 1e5, "l1": 3}, "mem": {"avail": 50 - age / 600, "swap_gb": 0, "rate": 0, "swap_total_gb": 4},
    "limits": {"cap": 2, "avail": 15, "rate": 8, "load_max": 1.2}, "headroom": {"room": True, "reason": "room: %d %% free" % (50 - age / 600), "near": []},
    "slots": {"busy": 1, "cap": 2, "reserved": 0}, "fence": {"confined": 0, "unreadable": False},
    "runs": [{"topic": "tide-s3", "repo": "tide", "login": "acct-a", "started": now - 600, "state": "busy", "session": "sess-secret-1", "wt": "/srv/fx-owner/projects/tide"}],
    "records": {"stale": 0, "oldest_days": 0}, "history": [[now - 600 - age, 0.3, 51, 0], [now - age, 0.4, 50, 0]], "procs": ["/usr/bin/x"]}, **kw)
d = {"at": now, "here": "node-1",
     "hosts": {"node-1": row("node-1", now - 60 - age, source="here"), "node-2": row("node-2", now - 120 - age)},
     "queue": {"entries": [{"qid": "fleet:tide-s4", "topic": "tide-s4", "repo": "tide", "state": "queued", "priority": "normal", "kind": "step",
                            "host": "", "prefer": "", "queued_at": now - 900 - age, "attempts": 0, "needs": [], "after": [], "refused_by": {},
                            "args": ["--secret"], "note": "a caller's note", "caller": "acct-a@node-1", "env": {"TOKEN": "x"}}],
               "dropped": 0, "fence_unreadable": False, "unreadable": False},
     "logins": [{"label": "acct-a", "eligible": True, "primary": True, "parked": False, "why": "week 40% < 90%", "sampled": now - 240 - age,
                 "home": "/srv/fx-owner/.claude", "env": {"CLAUDE_CONFIG_DIR": "/srv/fx-owner/.claude"}, "same_as": "acct-b",
                 "limits": {"plan": "max", "five_hour": 20 + age / 1e4, "seven_day": 40, "email": "mail-marker-x"}}],
     "records": {"stale": 0, "oldest_days": 0}, "ref": {"unreadable": None, "offline": None}}
if mode == "newrun":
    d["hosts"]["node-2"]["runs"].append({"topic": "dock-s2", "repo": "dock", "login": "acct-a", "started": now - 30, "state": "busy"})
if mode == "path":
    d["hosts"]["node-2"]["headroom"]["reason"] = "memory unreadable (FileNotFoundError: /srv/fx-owner/.local/x) see https://example.invalid/a"
if mode == "guarded":   # the suite's guarded repo (config_fixture.sh), in no confidential scope: hosts keeps it, helm must not
    d["hosts"]["node-2"]["runs"].append({"topic": "plan-s3", "repo": "transcripts", "login": "acct-a", "started": now - 30, "state": "busy"})
    d["queue"]["entries"].append({"qid": "fleet:plan-s4", "topic": "plan-s4", "repo": "transcripts", "state": "queued", "priority": "normal", "kind": "step",
                                  "host": "", "queued_at": now - 60, "attempts": 0, "needs": [], "after": [], "refused_by": {}, "by": "abcdef0123456789"})
if mode == "fencenull":   # a peer's row with a null fence and a guarded repo's run: the guard must not crash the board
    d["hosts"]["node-2"]["fence"] = None
    d["hosts"]["node-2"]["runs"].append({"topic": "plan-s3", "repo": "transcripts", "login": "acct-a", "started": now - 30, "state": "busy"})
print(json.dumps(d))
PY
cat > "$T/ops-stub.py" <<'PY'
import json, os, sys, time
verb = sys.argv[1]
mode = open(os.environ["STUB_MODE"]).read().strip() if os.environ.get("STUB_MODE") else "ok"
if mode == "opsfail":
    sys.exit(2)
now = time.time()
if mode == "opsnull" and verb == "status":   # ops.jsonl there, no whole row in it: ops exits 3
    print(json.dumps({"row": None, "why": "no whole row in the log"})); sys.exit(3)
if mode == "opsnull":   # the intake's read failed (a torn registry): ops answers no cards and a why
    print(json.dumps({"open": [], "why": "the registry cannot be read", "sig": "x"})); sys.exit(0)
if mode == "guardedintake" and verb == "intake":   # a dead-man alarm in the suite's guarded repo, beside an open bug
    print(json.dumps({"open": [{"repo": "transcripts", "number": 4, "kind": "deadman", "created": now - 60, "author": "bot", "scope": None},
                               {"repo": "tide", "number": 5, "kind": "bug", "created": now - 60, "author": "member", "scope": None}], "why": None})); sys.exit(0)
if verb == "status":
    print(json.dumps({"row": {"as_of": now - 300, "host": "node-1", "partial": False, "why": {"x": "no token at /srv/fx-owner/.config/t"},
                              "check": {"slots_busy": 1, "waiting": 0},
                              "budget": {"gh": {"state": "ok", "used": 900, "week_used": 300, "unit": "minutes", "net_amount": 0, "cap": 3000, "share": 0.3},
                                         "cc": {"state": "absent", "why": "no CIRCLECI_TOKEN in /srv/fx-owner/.config/regatta/x"}},
                              "token": {"plan": "ok"}},
                      "age_s": 300, "stale": False, "line": "a line", "sig": "s1"}))
else:
    print(json.dumps({"open": [{"repo": "acct-owner/logbook", "slug": "acct-owner/logbook", "number": 7, "kind": "stall", "label": "stall",
                                "created": now - 3600, "author": "bot", "url": "https://github.com/acct-owner/logbook/issues/7", "scope": None}],
                      "why": None, "sig": "x"}))
PY
cat > "$T/engine.py" <<'PY'
import json, os, sys, time
sys.path.insert(0, sys.argv[1])
import helm_render as h
what = sys.argv[2]
def eng():
    return h.engine_state({"ops": h.ops_json("status"), "intake": h.ops_json("intake")})
if what == "doc":
    print(json.dumps(eng(), sort_keys=True))
elif what == "sig":
    print(h.engine_sig(eng()))
elif what == "boardsig":
    st = {"columns": [], "header": {}}
    e = eng()
    print(h.board_sig(st) == h.board_sig(st, None), h.board_sig(st, e) != h.board_sig(st))
PY
echo "the poll's document: the five reads through the page's field allowlist (helm_render.engine_state)"
export HELM_HOSTS="$T/hosts-stub.py" HELM_OPS="$T/ops-stub.py" STUB_MODE="$T/mode"
echo ok > "$T/mode"
printf '%s' '{"reserve": 0.2, "accounts": {"gh": {"provider": "github", "user": "acct-user", "month_minutes": 3000, "week_share": 0.35}, "cc": {"provider": "circleci", "org_slug": "gh/acct-org", "month_credits": 30000}}}' > "$T/config/lighthouse/ci-budgets.json"
python3 "$T/engine.py" "$B" doc > "$T/doc.json" 2>"$T/doc.err" || { echo "  FAIL engine_state raised: $(tail -3 "$T/doc.err")"; fails=$((fails+1)); }
cat > "$T/read.py" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); blob = json.dumps(d)
s = d["sources"]
print(" ".join(str(x) for x in (
    s["hosts"]["state"], s["ops"]["state"], s["budgets"]["state"], s["alarms"]["state"], s["intake"]["state"],
    isinstance(s["hosts"]["at"], (int, float)), isinstance(s["ops"]["at"], (int, float)), isinstance(s["budgets"]["at"], (int, float)),
    not any(w in blob for w in ("sess-secret", "/srv/fx-owner", "mail-marker", "same_as", "--secret", "a caller's note", "TOKEN", "acct-user", "acct-org", "https://", '"why": {', "procs", "cores", '"wt"', '"url"', '"scope"', '"slug"')),
    d["hosts"]["hosts"]["node-1"]["runs"][0] == {"login": "acct-a", "repo": "tide", "started": d["hosts"]["hosts"]["node-1"]["runs"][0]["started"], "state": "busy", "topic": "tide-s3"},
    d["intake"]["open"][0]["repo"], len(d["hosts"]["hosts"]["node-1"]["history"]))))
PY
check "$(python3 "$T/read.py" "$T/doc.json" 2>&1)" "ok ok ok off ok True True True True True acct-owner/logbook 2" \
  "every source read: its state and its own at; no session, path, email, home, env, same_as, arg, note, caller, budget user or org, desk why, url, scope or slug passes; a run keeps its topic, repo, login, state and start; the history its samples"
echo path > "$T/mode"
python3 "$T/engine.py" "$B" doc > "$T/doc2.json" 2>/dev/null
check "$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))["hosts"]["hosts"]["node-2"]["headroom"]["reason"]; print("/home" not in r and "https" not in r and "<path>" in r)' "$T/doc2.json" 2>&1)" "True" \
  "a path or an address in a text that passes is cut to <path>"
echo fail > "$T/mode"
python3 "$T/engine.py" "$B" doc > "$T/doc3.json" 2>/dev/null
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["hosts"], d["sources"]["hosts"]["state"], d["sources"]["ops"]["state"])' "$T/doc3.json" 2>&1)" "None unread ok" \
  "hosts --json failing: the hosts null and their source unread (the page: unread, never zero), the rest still read"
echo opsfail > "$T/mode"
python3 "$T/engine.py" "$B" doc > "$T/doc4.json" 2>/dev/null
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); s=d["sources"]; print(s["ops"]["state"], s["intake"]["state"], d["ops"], d["intake"])' "$T/doc4.json" 2>&1)" "unread unread None None" \
  "ops failing (a crash, not a missing desk): the CI and Intake sources unread, never off"
echo opsnull > "$T/mode"
python3 "$T/engine.py" "$B" doc > "$T/doc6.json" 2>/dev/null
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); s=d["sources"]; print(s["ops"]["state"], s["intake"]["state"], d["intake"])' "$T/doc6.json" 2>&1)" "unread unread None" \
  "the desk's file there but no row that reads (ops exits 3), and an intake that answers a why with no cards (a torn registry): unread, never off or no alarms"
echo guarded > "$T/mode"
python3 "$T/engine.py" "$B" doc > "$T/doc7.json" 2>/dev/null
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); b=json.dumps(d); h=d["hosts"]; print("transcripts" not in b and "plan-s" not in b, h["hosts"]["node-2"]["fence"]["confined"], h["queue"]["dropped"], [r["topic"] for r in h["hosts"]["node-2"]["runs"]])' "$T/doc7.json" 2>&1)" "True 1 1 ['tide-s3']" \
  "a guarded repo's run and entry (hosts fences confidential scopes only): never listed, counted in the fence's counts, as the board guards its cards"
echo fencenull > "$T/mode"
python3 "$T/engine.py" "$B" doc > "$T/doc8.json" 2>"$T/doc8.err"
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); r=d["hosts"]["hosts"]["node-2"]; print(r["fence"], [x["topic"] for x in r["runs"]])' "$T/doc8.json" 2>&1)" "{'confined': 1} ['tide-s3']" \
  "a peer's row with a null fence and a guarded run: the guard counts it in a fresh fence, never crashes the board"
echo guardedintake > "$T/mode"
python3 "$T/engine.py" "$B" doc > "$T/doc9.json" 2>/dev/null
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); i=d["intake"]; print([c["repo"] for c in i["open"]], i["guarded"], "transcripts" in json.dumps(d), d["sources"]["intake"]["state"])' "$T/doc9.json" 2>&1)" "['tide'] {'deadman': 1} False ok" \
  "a guarded repo's Intake card: counted by its kind (the page counts its alarm), never listed"
cat > "$T/torn.py" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import helm_render as h
def boom():
    raise ValueError("torn")
h.helmlib._common().read_registry = boom   # a read that raises: every card guarded
e = h.engine_state({"ops": h.ops_json("status"), "intake": h.ops_json("intake")})
print(e["sources"]["intake"]["state"], e["intake"])
PY
check "$(python3 "$T/torn.py" "$B" 2>&1 | tail -1)" "unread None" \
  "the scopes that do not read: Intake unread, never an empty Intake that reads as no alarms"
echo ok > "$T/mode"
cat > "$T/guardunread.py" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import helm_render as h
h.helmlib.guard_unread = lambda fresh=False: True
e = h.engine_state({"ops": h.ops_json("status"), "intake": h.ops_json("intake")})
q = e["hosts"]["queue"]
print(q["guard_unread"], q["entries"], q["dropped"], e["hosts"]["hosts"]["node-1"]["runs"], "someone@" in json.dumps(h._scalar("a.someone" + "@" + "example" + ".org")))   # in parts: the publish gate's address scan
PY
check "$(python3 "$T/guardunread.py" "$B" 2>&1 | tail -1)" "True [] 1 [] False" \
  "a guarded list that does not read: every run and entry hidden and the queue marked so (the page: unknown, not empty); an address is cut"
echo ok > "$T/mode"
cat > "$T/torn2.py" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import helm_render as h
h.helmlib._common().read_registry = lambda path=None: (None, True)   # a torn file: confidential_scopes() would read no scopes
e = h.engine_state({"ops": h.ops_json("status"), "intake": h.ops_json("intake")})
print(e["sources"]["intake"]["state"], e["intake"])
PY
check "$(python3 "$T/torn2.py" "$B" 2>&1 | tail -1)" "unread None" \
  "a registry that is there but torn (registry_unreadable, which confidential_scopes never says): Intake unread, no card listed"
cat > "$T/umbrella.py" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import helm_render as h
c = h.helmlib._common()
reg = {"repos": {}, "scopes": {"all": {"repos": ["*"]}, "acme": {"repos": ["tide"], "confidential": True}}}
c.read_registry = lambda path=None: (reg, False)
i = h.engine_intake({"open": [{"repo": "tide", "number": 7, "kind": "deadman", "scope": "all"}, {"repo": "reef", "number": 8, "kind": "bug", "scope": "all"}]})
h.helmlib.guard_unread = lambda fresh=False: True
j = h.engine_intake({"open": [{"repo": "reef", "number": 8, "kind": "bug"}]})
print([x["repo"] for x in i["open"]], i["guarded"], j["open"], j["guarded"], j["torn"])
PY
check "$(python3 "$T/umbrella.py" "$B" 2>&1 | tail -1)" "['reef'] {'deadman': 1} [] {'bug': 1} False" \
  "a card whose repo a confidential scope lists, under an umbrella scope ops named first: counted, never listed; a guarded list that does not read counts every card"
check "$(PLAN_NO_HOSTS=1 python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helm_render as h; e = h.engine_state({}); print(e["sources"]["hosts"]["state"], e["hosts"])' "$B" 2>&1 | tail -1)" "off None" \
  "no hosts tool on this host: the hosts source off, said apart from a read that failed"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import helm_render as h; print(h._scalar("fetch git" + "@" + "example.org:o/r.git failed"), "|", h._scalar("as owner" + "@" + "hostb"), "|", h._scalar("x;/var/x"))' "$B" 2>&1 | tail -1)" "fetch <url> failed | as <address> | x;<path>" \
  "the second scrub is hosts' own: a git remote, a bare user at host and a path after any punctuation are cut"
cat > "$T/sigmove.py" <<'PY'
import copy, json, sys
sys.path.insert(0, sys.argv[1])
import helm_render as h
d = json.load(open(sys.argv[2]))
d["hosts"]["queue"]["entries"][0]["refused_by"] = {"node-1": 1000}
a = h.engine_sig(d)
m = copy.deepcopy(d)
for r in (m.get("hosts") or {}).get("hosts", {}).values():
    r.setdefault("headroom", {})["near"] = ["load"]
es = ((m.get("hosts") or {}).get("queue") or {}).get("entries") or []
for e in es:
    if isinstance(e.get("refused_by"), dict):
        e["refused_by"] = {k: (v or 0) + 3600 for k, v in e["refused_by"].items()}
x, y = copy.deepcopy(d), copy.deepcopy(d)
x["ops"]["row"]["check"], y["ops"]["row"]["check"] = {"slots_busy": 2, "waiting": 1}, {"slots_busy": 1, "waiting": 3}
print(a == h.engine_sig(m), any(isinstance(e.get("refused_by"), dict) and e["refused_by"] for e in es), h.engine_sig(x) == h.engine_sig(y))
PY
check "$(python3 "$T/sigmove.py" "$B" "$T/doc.json" 2>&1 | tail -1)" "True True True" \
  "a headroom near-flip, a refusal re-stamped and a check count moving are no new version"
echo ok > "$T/mode"
cat > "$T/off.py" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1])
os.environ.pop("HELM_OPS", None)
import helm_render as h
peer = h.helmlib.peer
h.helmlib.peer = lambda name: None if name == "ops" else peer(name)
e = h.engine_state({})
print(e["sources"]["ops"]["state"], e["sources"]["intake"]["state"], e["ops"], e["intake"])
PY
check "$(python3 "$T/off.py" "$B" 2>&1 | tail -1)" "off off None None" \
  "no desk on this host (no lighthouse ops, or no desk's file): CI and Intake off, said apart from unread"
printf '{torn' > "$T/config/lighthouse/ci-budgets.json"
python3 "$T/engine.py" "$B" doc > "$T/doc5.json" 2>/dev/null
check "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["sources"]["budgets"]["state"], d["budgets"])' "$T/doc5.json" 2>&1)" "unread None" \
  "a ci-budgets.json that does not parse: its source unread"
printf '%s' '{"reserve": 0.2, "accounts": {"gh": {"provider": "github", "month_minutes": 3000, "week_share": 0.35}}}' > "$T/config/lighthouse/ci-budgets.json"

echo "board_sig over the Engine room: no ages, no gauges, no history (AGENTS.md: a change check over a rendered state)"
export STUB_NOW=$(python3 -c 'import time; print(int(time.time()))')
a=$(STUB_AGE=0 python3 "$T/engine.py" "$B" sig)
b=$(STUB_AGE=420 python3 "$T/engine.py" "$B" sig)
check "$([ -n "$a" ] && [ "$a" = "$b" ] && echo same || echo "differs: $a $b")" "same" \
  "the same fleet sampled 7 min later (every at, age, gauge, judge line's digits and history moved): the same sig"
echo newrun > "$T/mode"
c=$(STUB_AGE=0 python3 "$T/engine.py" "$B" sig); echo ok > "$T/mode"
check "$([ "$a" != "$c" ] && echo differs || echo same)" "differs" "a run that started is a new version"
d=$(STUB_AGE=2400 python3 "$T/engine.py" "$B" sig)
check "$([ "$a" != "$d" ] && echo differs || echo same)" "differs" "a host row aging past the page's 30 minutes (it reads unread then) is a new version"
check "$(python3 "$T/engine.py" "$B" boardsig 2>&1)" "True True" "board_sig without the Engine room is as before; with it, the Engine room counts"

echo "overview(): engine.json beside state.json, the page's first document, the deploy's files"
cat > "$T/overview.py" <<'PY'
import json, re, sys
sys.path.insert(0, sys.argv[1])
import helm_render as h
h.overview()
d = h.cache_root() / "overview"
eng = json.loads((d / "engine.json").read_text())
page = (d / "index.html").read_text()
snap = re.findall(r'<script type="application/json" id="engine-snapshot">(.*?)</script>', page, re.S)
print(sorted(eng["sources"]) == ["alarms", "budgets", "hosts", "intake", "ops"], len(snap) == 1 and json.loads(snap[0]) == eng,
      "window.ENGINE_ADAPT" in page and "window.ENGINE_VIEW" in page and ".eroom" in page, h.BOARD_DEPLOYED == ("index.html", "state.json", "engine.json"),
      "{{ENGINE" not in page)
PY
check "$(python3 "$T/overview.py" "$B" 2>&1 | tail -1)" "True True True True True" \
  "overview() writes engine.json with its five sources, inlines it as the page's first document with the adapter, the view and its rules, and deploys the three files"

echo "the Engine room under headless Chrome: 1440, 720 and a true 390, both themes, both roads"
cat > "$T/fixture.js" <<'JS'
const fs = require('fs'), vm = require('vm');
const ctx = { ENGINE_NOW: Math.round(Date.now() / 1000) }; ctx.window = ctx; vm.createContext(ctx);
vm.runInContext(fs.readFileSync(process.argv[2], 'utf8'), ctx);
const s = ctx.ENGINE_SRC, now = ctx.ENGINE_NOW;
s.at = now;
s.sources = { hosts: { state: 'ok', at: now }, ops: { state: 'ok', at: s.ops.row.as_of }, budgets: { state: 'ok', at: now - 86400 }, alarms: { state: 'ok', at: now - 3 * 3600 }, intake: { state: 'ok', at: now - 360 } };
process.stdout.write(JSON.stringify(s));
JS
node "$T/fixture.js" "$TD/engine_fixture.js" > "$T/engine.json" 2>"$T/fixture.err" || { echo "  FAIL the page's fixture does not build: $(tail -2 "$T/fixture.err")"; fails=$((fails+1)); }
cat > "$T/frames.py" <<'PY'
import json, os, sys, time
from pathlib import Path
sys.path.insert(0, sys.argv[1])
import helm_render as h
k = h._keel()
chrome = k.chrome_path() if k else None
if sys.platform != "darwin" and os.environ.get("HELM_BOARD_ANY_OS") != "1":   # as test_board.sh's frames
    print("SKIP the render cases run on a Mac only (HELM_BOARD_ANY_OS=1 runs them here)")
    sys.exit(0)
if not chrome:
    print("SKIP no headless Chrome here (keel's chrome_path): the render cases are not run")
    sys.exit(0)
work = Path(sys.argv[3]); work.mkdir(parents=True, exist_ok=True)
eng = json.loads(Path(sys.argv[2]).read_text())
st = {"kind": "overview", "as_of": time.time(), "host": "host-a", "columns": [{"name": n, "cards": []} for n in h.board_columns()],
      "timeline": [], "queue": {"docs": [], "groups": []}, "later": [],
      "header": {"needs_owner": 0, "owner": "Sam", "today_cost": 0, "week": "week 37% used", "ratio": 0.0166, "stalled": 0}}
page = h.board_page(st, "Helm · board", eng)
STUB = ("window.__errs=[];window.onerror=function(m,u,l){window.__errs.push(m+' :'+l)};window.__engine=" + h.snapshot(eng) + ";"
        "(function(){var m={};try{Object.defineProperty(window,'localStorage',{configurable:true,value:{getItem:function(k){return k in m?m[k]:null},"
        "setItem:function(k,v){m[k]=String(v)},removeItem:function(k){delete m[k]}}})}catch(e){}})();")
page = page.replace("<head>", "<head><script>" + STUB + "</script>", 1)
page = page.replace("</body>", "<script>" + Path(sys.argv[4]).read_text() + "</script></body>", 1)
(work / "board.html").write_text(page, encoding="utf-8")
runs = [(w, th, "", "%d-%s" % (w, th)) for th in ("light", "dark") for w in (1440, 720, 390)] + [(1440, "light", "&road=token", "1440-token")]
frames = "".join('<iframe style="width:%dpx;height:900px;border:0" src="board.html?view=engine&selftest=%s&theme=%s%s"></iframe>' % (w, lab, th, rd) for w, th, rd, lab in runs)
labels = [lab for _, _, _, lab in runs]
wrap = ('<!doctype html><meta charset="utf-8"><pre id="out"></pre>%s<script>var got = [], want = %s, end = false;'
        'function done() { if (end) return; end = true; want.forEach(function (l) { got.push({ name: l + ": posted nothing", ok: false,'
        ' got: "a script error or a frame that never loaded" }); }); document.getElementById("out").textContent = JSON.stringify(got); }'
        'addEventListener("message", function (e) { var i = e.data ? want.indexOf(e.data.board) : -1; if (i < 0) return; want.splice(i, 1);'
        ' e.data.out.forEach(function (r) { r.name = e.data.board + ": " + r.name; got.push(r); }); if (!want.length) done(); });'
        ' setTimeout(done, 9000);</script>' % (frames, json.dumps(labels)))
try:
    got = k.chrome_results(chrome, wrap, work, "frames", timeout=int(os.environ.get("HELM_BOARD_CHROME_S") or 150), flags=["--window-size=1500,1000"])
except Exception as e:   # keel's Stop: Chrome never returned
    print(("SKIP " if "did not finish in" in str(e) else "FAIL ") + "headless Chrome: %s" % e)
    sys.exit(0)
if not got:
    print("FAIL headless Chrome wrote no reads")
for r in got or []:
    print(("ok   " if r["ok"] else "FAIL ") + r["name"] + ("" if r["ok"] else ": " + r["got"][:300]))
PY
python3 "$T/frames.py" "$B" "$T/engine.json" "$T/frames" "$TD/engine_selftest.js" > "$T/frames.out" 2>&1
sed 's/^/  /' "$T/frames.out"
n=$(grep -c '^FAIL' "$T/frames.out"); fails=$((fails+n))
grep -q '^SKIP' "$T/frames.out" || check "$(grep -c '^ok' "$T/frames.out")" "248" \
  "every frame posted every read (35 per press frame, 38 on the token road)"

echo
skipped=$(grep -q "^SKIP" "$T/frames.out" && echo " (the render cases skipped: $(sed -n "s/^SKIP //p" "$T/frames.out" | head -1))")
[ "$fails" = 0 ] && echo "test_engine: all passed$skipped" || { echo "test_engine: $fails failed"; exit 1; }
