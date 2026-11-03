#!/usr/bin/env bash
# lighthouse's bin/hosts and wharf-runs' `dispatch-queue hosts` (the Engine room design's S2,
# docs/fleet-page-2026-11-01.md): the row a host builds, the fence it passes, the put that writes it to
# refs/regatta/hosts only when it changed, the reader that merges the rows. A bare repo stands for the queue
# home; stand-ins answer for dispatch and account; a `sleep` is each live run. Scratch HOME and config dir;
# every name made up (hosts `alpha` and `beta`, logins `acct-work` and `acct-spare`).
#   bash modules/lighthouse/tests/hosts.sh
set -u
for v in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH[A-Za-z0-9_]*\)=.*/\1/p; s/^\(HOSTS_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset REGATTA_HOME REGATTA_UNATTENDED HEADROOM_HOST HEADROOM_OS HEADROOM_PROC
C="$(cd "$(dirname "$0")/.." && pwd)"; R="$(cd "$C/../.." && pwd -P)"
H="$C/bin/hosts"; Q="$R/modules/wharf-runs/bin/dispatch-queue"
T=$(mktemp -d); trap 'kill $RUNS 2>/dev/null; rm -rf "$T"' EXIT
RUNS=""
export HOME="$T/home" REGATTA_CONFIG="$T/config"
mkdir -p "$HOME" "$REGATTA_CONFIG/regatta" "$REGATTA_CONFIG/wharf-runs" "$T/projects"
echo "$R" > "$REGATTA_CONFIG/home"
echo "$T/projects" > "$REGATTA_CONFIG/regatta/projects"
echo laptop > "$REGATTA_CONFIG/regatta/laptop"
echo beta > "$REGATTA_CONFIG/wharf-runs/dispatch-host"
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "$T/gitconfig"; export GIT_CONFIG_GLOBAL="$T/gitconfig"
git init -q --bare "$T/home.git"; echo "$T/home.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
export ACCOUNTS_FILE="$T/no-accounts.json" HEADROOM_SAMPLE="60 1.5 0" DISPATCH_HOST=alpha
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has() { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:300}]"; fails=$((fails+1));; esac; }
hasnt() { case "$1" in *"$2"*) echo "  FAIL $3: [$2] in [${1:0:300}]"; fails=$((fails+1));; *) echo "  ok   $3";; esac; }
j() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }

# the stand-ins: dispatch (--cap, --slots) and account (limits --cached), as the real ones print
mkdir -p "$T/bin"
# each checks the arguments the real one takes and refuses the rest, as the real one does (AGENTS.md: a stub that
# takes any argument hides the tool's refusal)
printf '#!/bin/sh\ncase "$*" in --cap) echo 3;; --slots) echo "1 3";; *) echo "dispatch: unknown option $1" >&2; exit 2;; esac\n' > "$T/bin/dispatch"
cat > "$T/bin/account" <<PY
import json, sys
if sys.argv[1:] != ["limits", "--all", "--parked", "--json", "--cached"]:
    sys.exit("account: the stand-in takes limits --all --parked --json --cached only, not %s" % sys.argv[1:])
print(json.dumps([{"label": "acct-work", "home": "$T/logins/work", "eligible": True, "why": "week 10% < 90% (week ceiling)",
                   "limits": {"seven_day": 10, "five_hour": 3, "email": "someone@example.invalid"}},
                  {"label": "acct-spare", "home": "$T/logins/spare", "eligible": False, "why": "parked; same login as acct-work (someone@example.invalid)", "limits": {}}]))
PY
mkdir -p "$T/logins/work" "$T/logins/spare"
export HOSTS_TOOL_DISPATCH="$T/bin/dispatch" HOSTS_TOOL_ACCOUNT="$T/bin/account"

# two repos under the projects folder, one in a confidential scope; an umbrella scope listed first
for r in open secret; do git init -q -b main "$T/projects/$r"; (cd "$T/projects/$r" && echo x > f && git add f && git commit -qm init); done
printf '{"repos": {"open": {}, "secret": {}}, "scopes": {"wide": {"repos": ["*"]}, "vault": {"confidential": true, "repos": ["secret"]}}}\n' > "$T/repos.json"
export CLAUDE_REPOS_JSON="$T/repos.json"

# live runs: a sleep each, its record as dispatch writes it (pid, proc_start, config_dir or none)
HL="$HOME"/Library   # the scratch HOME's
RR="$HL/Logs/claude-weekly/run-seed-runs"; mkdir -p "$RR/peer"
run_rec() {   # name repo topic [config_dir [login [extra json fields]]]
  # started from a subshell, so no job of this shell: its kill at the end prints no "Terminated" line
  local pid; pid=$(sleep 600 > /dev/null 2>&1 & echo $!); RUNS="$RUNS $pid"
  local ps; ps=$(TZ=UTC LC_ALL=C ps -o lstart= -p "$pid" | tr -s ' ' | sed 's/^ //; s/ $//')
  python3 - "$RR/$1.json" "$pid" "$ps" "$2" "$3" "${4:-}" "${5:-}" "${6:-}" <<'PY'
import json, sys, time
p, pid, ps, repo, topic, cfg, login, extra = sys.argv[1:]
rec = {"mode": "rc", "pid": int(pid), "proc_start": ps, "repo": repo, "topic": topic, "branch": "claude/alpha/2026-11-01-" + topic,
       "session": "0123abcd-ffff-4444-8888-000000000000", "started": int(time.time()) - 60, "prio": "normal",
       "title": "the session's own words", "wt": repo + "/.claude/worktrees/" + topic, "log": "/var/tmp/run.log"}
if cfg:
    rec["config_dir"] = cfg
if login:
    rec["login"] = login
rec.update(json.loads(extra or "{}"))
json.dump(rec, open(p, "w"))
PY
}
run_rec r1 "$T/projects/open" plain "$T/logins/work"
run_rec r2 "$T/projects/open" nologin
run_rec r3 "$T/projects/secret" hidden "$T/logins/work"
run_rec r4 "$T/projects/open" picked "" acct-default
run_rec r5 "$T/projects/open" addressed "" "someone@example.invalid"
run_rec r6 "$T/projects/open" inside "" "" "{\"wt\": \"$T/projects/secret/wt-inside\"}"
run_rec r7 "$T/projects/open" spawned "" "" '{"queue": "local=_spawn:k1", "origin": "vault"}'
run_rec r8 "$T/projects/open" nodeq "" "" '{"queue": "local=vault:k2"}'
printf '{"started": "%s", "topic": "gone", "repo": "%s"}\n' "$(python3 -c 'import datetime; print((datetime.datetime.now().astimezone() - datetime.timedelta(days=3, hours=2)).isoformat())')" "$T/projects/open" > "$RR/peer/p1.json"
printf '{"started": "%s", "ended": "2026-11-01T10:00:00", "topic": "done"}\n' "$(python3 -c 'import datetime; print(datetime.datetime.now().isoformat())')" > "$RR/peer/p2.json"

echo "hosts sample: the row"
row=$(python3 "$H" sample); echo "$row" > "$T/row.json"
check "$(echo "$row" | j 'd["host"], d["limits"]["cap"], d["slots"]["busy"], d["mem"]["avail"], d["headroom"]["room"]')" "('alpha', 3, 1, 60.0, True)" "host, cap, slots, memory and headroom read"
check "$(echo "$row" | j 'sorted(r["topic"] for r in d["runs"])')" "['addressed', 'nologin', 'picked', 'plain']" "the open repo's four runs are rows"
check "$(echo "$row" | j 'd["fence"]')" "{'confined': 4, 'unreadable': False}" "a confidential run is a count, never a row (the umbrella scope listed first hides nothing); so is an open repo's worktree inside a confidential folder, a spawn out of a scope and a run from a node's queue"
check "$(echo "$row" | j 'sorted((r["topic"], r["login"]) for r in d["runs"] if r["login"]), sorted(r["topic"] for r in d["runs"] if r["login"] is None)')" "([('picked', 'acct-default'), ('plain', 'acct-work')], ['addressed', 'nologin'])" "the recorded login first (the default login's too), else config_dir's label; neither, or an address, reads login null"
check "$(echo "$row" | j '[(r["repo"], r["state"], r["session"]) for r in d["runs"]][0]')" "('open', 'busy', '0123abcd')" "a run's repo is its registry key, its session the first 8"
check "$(echo "$row" | j 'd["records"]["stale"], d["records"]["oldest_days"]')" "(1, 3)" "the stale peer records: one with no end, three days old"
hasnt "$row" "$T" "the row names no path of this host"
hasnt "$row" "session's own words" "the row carries no session text"
hasnt "$row" "hidden" "the confidential run's topic is nowhere in the row"
hasnt "$row" "spawned" "  nor a spawn's out of a scope"
hasnt "$row" "nodeq" "  nor a node queue's run's"
hasnt "$row" "inside" "  nor the run in a confidential folder's"
hasnt "$row" "/var/tmp" "a record's log path stays out"
check "$(echo "$row" | j 'sorted(d["mem"]), d["os"] in ("macOS", "Linux")')" "(['avail', 'rate', 'swap_gb', 'swap_total_gb'], True)" "memory under the schema's keys (swap_gb)"
check "$(HOSTS_TOOL_DISPATCH_RC="$T/none" python3 "$H" sample | j 'd["runs"], d["fence"].get("runs_unread")')" "(None, True)" "no dispatch-rc to read the records: runs unknown (null), never none"

echo "the fence: a torn registry drops every run"
printf '{"repos": {"open": {}}, "scopes": {"vault": {"confidential": true, "repos": "secret"}}}\n' > "$T/repos-torn.json"
check "$(CLAUDE_REPOS_JSON="$T/repos-torn.json" python3 "$H" sample | j 'd["runs"], d["fence"]["unreadable"]')" "(None, True)" "a registry that does not read: runs null, fence.unreadable"
head -c 20 "$T/repos.json" > "$T/repos-cut.json"
check "$(CLAUDE_REPOS_JSON="$T/repos-cut.json" python3 "$H" sample | j 'd["runs"]')" "None" "a torn write too"

echo "dispatch-queue hosts put"
out=$(python3 "$Q" hosts put --file "$T/row.json"); rc=$?
check "$rc $(echo "$out" | j 'd["result"]')" "0 pushed" "a new row is pushed"
check "$(git --git-dir="$T/home.git" ls-tree -r --name-only refs/regatta/hosts)" "hosts/alpha.json" "hosts/alpha.json on refs/regatta/hosts"
check "$(git --git-dir="$T/home.git" rev-parse -q --verify refs/regatta/queue || echo none)" "none" "the queue's ref untouched"
sha=$(git --git-dir="$T/home.git" rev-parse refs/regatta/hosts)
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['at'] += 60; d['history'].append([d['at'], 0, 0, 0]); json.dump(d, open(sys.argv[2], 'w'))" "$T/row.json" "$T/row-later.json"
out=$(python3 "$Q" hosts put --file "$T/row-later.json"); rc=$?
check "$rc $(echo "$out" | j 'd["result"]')" "0 unchanged" "the same row a minute later (only its clocks moved) is not pushed"
check "$(git --git-dir="$T/home.git" rev-parse refs/regatta/hosts)" "$sha" "the ref did not move"
python3 - "$T/row.json" "$T/row-fine.json" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1]))
b = d["load"].get("per_core_5m") or 0
d["load"] = {"l1": 99.0, "l5": 98.0, "l15": 97.0, "per_core_5m": round(b / 0.5) * 0.5 + 0.01 if b % 0.5 < 0.2 else b}
d["mem"]["rate"] = d["mem"].get("rate", 0) + 1; d["headroom"]["reason"] = "room: other words"
d["runs"][0]["started"] += 5
json.dump(d, open(sys.argv[2], "w"))
PY2
check "$(python3 "$Q" hosts put --file "$T/row-fine.json" | j 'd["result"]')" "unchanged" "fine gauges, headroom's words and a start time moved, nothing the page acts on: not pushed"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['runs'][0]['state'] = 'waiting'; json.dump(d, open(sys.argv[2], 'w'))" "$T/row.json" "$T/row-changed.json"
check "$(python3 "$Q" hosts put --file "$T/row-changed.json" | j 'd["result"]')" "pushed" "a changed row (a run now waiting) is pushed"
check "$(DISPATCH_QUEUE_NOW=$(( $(date +%s) + 16 * 60 )) python3 "$Q" hosts put --file "$T/row-changed.json" | j 'd["result"]')" "pushed" "an unchanged row whose copy is a sweep old is put again (it never reads stale)"
check "$(python3 "$Q" hosts put --refresh --file "$T/row-changed.json" | j 'd["result"]')" "pushed" "the sweep's put (--refresh) pushes an unchanged row at once: a claim's push between sweeps never makes the sweep skip"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['runs'][0]['session'] = 'ffff0000'; json.dump(d, open(sys.argv[2], 'w'))" "$T/row-changed.json" "$T/row-session.json"
check "$(python3 "$Q" hosts put --file "$T/row-session.json" | j 'd["result"]')" "pushed" "a run replaced by another of its topic (a new session) is a change"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['host'] = 'beta'; d['load']['per_core_5m'] = 0.5; json.dump(d, open(sys.argv[2], 'w'))" "$T/row.json" "$T/row-beta.json"
DISPATCH_HOST=beta python3 "$Q" hosts put --file "$T/row-beta.json" > /dev/null
check "$(git --git-dir="$T/home.git" ls-tree -r --name-only refs/regatta/hosts | tr '\n' ' ')" "hosts/alpha.json hosts/beta.json " "a second host's put keeps the first host's row"
check "$(python3 "$Q" hosts put --file "$T/row-beta.json" 2>&1 >/dev/null; echo "rc=$?")" "dispatch-queue hosts put: the row names host 'beta', and this host is 'alpha': a host puts its own row only
rc=2" "a row naming another host is refused, exit 2"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['headroom']['reason'] = 'unreadable: /etc/whatever'; json.dump(d, open(sys.argv[2], 'w'))" "$T/row.json" "$T/row-path.json"
python3 "$Q" hosts put --file "$T/row-path.json" > /dev/null 2> "$T/err"; check "$?" 2 "a row holding a path is refused"
has "$(cat "$T/err")" "reads as a path" "  and says why"
echo '{"host": "alpha", "at": 1}' | python3 "$Q" hosts put > /dev/null 2> "$T/err"; check "$?" 2 "a row lacking the schema's keys is refused"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['at'] = 'x'; json.dump(d, open(sys.argv[2], 'w'))" "$T/row.json" "$T/row-at.json"
python3 "$Q" hosts put --file "$T/row-at.json" > /dev/null 2>&1; check "$?" 2 "a row whose at is no number is refused"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['headroom']['reason'] = 'vm_stat:/usr/bin/vm_stat failed'; json.dump(d, open(sys.argv[2], 'w'))" "$T/row.json" "$T/row-colon.json"
python3 "$Q" hosts put --file "$T/row-colon.json" > /dev/null 2>&1; check "$?" 2 "a path after a colon is a path too"
python3 "$Q" hosts put --host alpha --file "$T/row.json" > /dev/null 2> "$T/err"; check "$?" 2 "hosts put takes no --host: a host puts its own row"
echo off > "$REGATTA_CONFIG/wharf-runs/queue-repo"
check "$(python3 "$Q" hosts put --file "$T/row.json" >/dev/null 2>&1; echo $?)" 6 "no queue home: exit 6, nothing written"
echo "$T/home.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"

echo "dispatch-queue hosts get, and a torn row"
got=$(python3 "$Q" hosts get)
check "$(echo "$got" | j 'sorted(d["rows"]), d["torn"], d["unreadable"]')" "(['alpha', 'beta'], [], None)" "get: every row"
# a torn row for a third host, written straight into the home (no put would write one)
blob=$(printf 'not json{' | git --git-dir="$T/home.git" hash-object -w --stdin)
tree=$( { git --git-dir="$T/home.git" ls-tree refs/regatta/hosts:hosts; printf '100644 blob %s\tgamma.json\n' "$blob"; } | git --git-dir="$T/home.git" mktree)
root=$(printf '040000 tree %s\thosts\n' "$tree" | git --git-dir="$T/home.git" mktree)
git --git-dir="$T/home.git" update-ref refs/regatta/hosts "$(git --git-dir="$T/home.git" commit-tree "$root" -m torn)"
got=$(python3 "$Q" hosts get)
check "$(echo "$got" | j 'd["rows"]["gamma"], d["torn"], d["rows"]["beta"]["host"]')" "(None, ['gamma'], 'beta')" "a torn row reads null and is named; the others read"
check "$(python3 "$Q" hosts put --file "$T/row-changed.json" | j 'd["result"]')" "pushed" "a put beside a torn row works"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['slots']['busy'] = 99; json.dump(d, open(sys.argv[2], 'w'))" "$T/row.json" "$T/row-4.json"
python3 "$Q" hosts put --file "$T/row-4.json" > /dev/null
check "$(git --git-dir="$T/home.git" cat-file blob refs/regatta/hosts:hosts/gamma.json)" "not json{" "  and keeps the torn row as it was, never parsed or dropped"
# a file and a folder no put wrote, beside the rows
nb=$(printf 'notes\n' | git --git-dir="$T/home.git" hash-object -w --stdin)
sub=$(printf '100644 blob %s\told.json\n' "$nb" | git --git-dir="$T/home.git" mktree)
# two names git quotes in its plain listing: a non-ASCII one (per the host's core.quotePath) and one with a quote
tree=$( { git --git-dir="$T/home.git" ls-tree -z refs/regatta/hosts:hosts
          # one record an argument: a `\0` before the next mode's digits would read as one octal escape
          printf '%s\0' "100644 blob $nb"$'\t'README "040000 tree $sub"$'\t'legacy "100644 blob $nb"$'\t'$'caf\303\251.md' \
            "100644 blob $nb"$'\t''with"quote'
        } | git --git-dir="$T/home.git" mktree -z)
root=$(printf '100644 blob %s\tREADME.md\n040000 tree %s\thosts\n' "$nb" "$tree" | git --git-dir="$T/home.git" mktree)
git --git-dir="$T/home.git" update-ref refs/regatta/hosts "$(git --git-dir="$T/home.git" commit-tree "$root" -m foreign)"
check "$(python3 "$Q" hosts put --refresh --file "$T/row-4.json" | j 'd["result"]')" "pushed" "a put beside files and a folder it never wrote works"
want=$(printf 'README alpha.json beta.json caf\303\251.md gamma.json legacy with"quote ')
check "$(git --git-dir="$T/home.git" ls-tree -z --name-only refs/regatta/hosts:hosts | tr '\0' ' ')" "$want" "  and keeps each as it was, a name git quotes included"
check "$(git --git-dir="$T/home.git" ls-tree --name-only refs/regatta/hosts | tr '\n' ' ')" "README.md hosts " "  and what sits beside hosts/ at the ref's top"
check "$(python3 "$Q" hosts get | j 'sorted(d["rows"])')" "['alpha', 'beta', 'gamma']" "  get reads the rows alone"
# a name that is no UTF-8, one holding a CR, and a row blob of stray bytes: read as git wrote them
bad=$(printf 'x\377y' | git --git-dir="$T/home.git" hash-object -w --stdin)
tree=$( { git --git-dir="$T/home.git" ls-tree -z refs/regatta/hosts:hosts
          printf '%s\0' "100644 blob $nb"$'\t'$'caf\351.md' "100644 blob $nb"$'\t'$'cr\rname' "100644 blob $bad"$'\t'delta.json
        } | git --git-dir="$T/home.git" mktree -z)
root=$(printf '040000 tree %s\thosts\n' "$tree" | git --git-dir="$T/home.git" mktree)
git --git-dir="$T/home.git" update-ref refs/regatta/hosts "$(git --git-dir="$T/home.git" commit-tree "$root" -m bytes)"
check "$(python3 "$Q" hosts put --refresh --file "$T/row-4.json" | j 'd["result"]')" "pushed" "a put beside a name that is no UTF-8 and one with a CR works"
check "$(git --git-dir="$T/home.git" ls-tree -z --name-only refs/regatta/hosts:hosts | python3 -c 'import sys; n = sys.stdin.buffer.read().split(b"\0"); print(b"caf\xe9.md" in n, b"cr\rname" in n)')" "True True" "  and keeps both byte for byte"
check "$(python3 "$Q" hosts get | j 'd["rows"]["delta"], "delta" in d["torn"]')" "(None, True)" "a row of stray bytes reads torn, the others still read"

echo "hosts --json: the reader"
d=$(python3 "$H" --json)
check "$(echo "$d" | j 'd["hosts"]["gamma"]["no_sample"]')" "its row does not parse" "a torn ref row reads no sample"
check "$(echo "$d" | j 'd["hosts"]["beta"]["source"], d["hosts"]["alpha"]["source"]')" "('ref', 'here')" "other hosts from the ref, this host sampled here"
check "$(echo "$d" | j '[(l["label"], "home" in l, "email" in l["limits"]) for l in d["logins"]]')" "[('acct-work', False, False), ('acct-spare', False, False)]" "the logins by label, no home folder, no address"
hasnt "$d" "$T" "the page's state names no path of this host"
hasnt "$d" "example.invalid" "  nor a login's address"
hasnt "$d" "@" "  the page JSON holds no @ at all (a login's why quotes its address)"
echo "$T/no-such-home.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"
d=$(python3 "$H" --json)
check "$(echo "$d" | j 'd["ref"]["offline"]')" "the queue home did not answer; its last fetch shown" "a home that does not answer: fixed words"
hasnt "$d" "no-such-home" "  never git's line, which quotes the home's address"
echo off > "$REGATTA_CONFIG/wharf-runs/queue-repo"
check "$(python3 "$H" --json | j 'sorted(d["hosts"]), d["ref"]["unreadable"]')" "(['alpha'], 'no queue home here (wharf-runs/queue-repo)')" "no queue home: this host alone, and the ref said unreadable"
echo "$T/home.git" > "$REGATTA_CONFIG/wharf-runs/queue-repo"

echo "the queue as the page reads it"
cat > "$T/drive.py" <<'PY'
import importlib.machinery, importlib.util, json, sys
ld = importlib.machinery.SourceFileLoader("hosts", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("hosts", ld)); ld.exec_module(m)
q = {"entries": [
    {"qid": "fleet:open--a", "key": "open--a", "topic": "a", "repo": "open", "state": "queued", "priority": "normal",
     "args": ["--note", "the session's words"], "env": {"DISPATCH_SKIPPER": "x"}, "by": "0123abcd", "cwd": sys.argv[2],
     "after": [{"branch": "claude/alpha/2026-11-01-b"}], "last_refusal": "no room in " + sys.argv[2]},
    {"qid": "fleet:open--c", "key": "open--c", "topic": "c", "repo": "open", "state": "queued", "confined": True},
    {"qid": "local=vault:secret--d", "key": "secret--d", "topic": "d", "repo": "secret", "state": "queued"},
    {"qid": "local=_spawn:open--e", "key": "open--e", "topic": "e", "repo": "open", "state": "queued"},
    {"qid": "fleet:open--f", "key": "open--f", "topic": "f", "repo": "open", "state": "queued", "kind": "finish"},
    {"qid": "fleet:secret--g", "key": "secret--g", "topic": "g", "repo": "secret", "state": "queued", "kind": "finish", "confined": False},
    {"qid": "local=_land:open--h", "key": "open--h", "topic": "h", "repo": "open", "state": "queued", "kind": "landing"}],
    "unreadable": False}
print(json.dumps(m.queue_view(q), sort_keys=True))
PY
v=$(python3 "$T/drive.py" "$H" "$T/projects/open")
check "$(echo "$v" | j '[e["qid"] for e in d["entries"]], d["dropped"]')" "(['fleet:open--a', 'fleet:open--f'], 5)" "the fleet store kept, a finish among it; a confined entry, a scope's, _spawn's, the old local=_land and a confidential repo's finish dropped"
hasnt "$v" '"g"' "  the confidential finish's topic is nowhere"
check "$(CLAUDE_REPOS_JSON="$T/repos-torn.json" python3 "$T/drive.py" "$H" "$T/projects/open" | j 'len(d["entries"]), d["fence_unreadable"]')" "(0, True)" "a registry that does not read drops every entry"
check "$(echo "$v" | j 'd["entries"][0]["after"], sorted(set(d["entries"][0]) & {"args", "env", "by", "cwd"})')" "(['b'], [])" "an entry passes its names and numbers: after by topic, no args, env, caller or cwd"
hasnt "$v" "$T" "an entry's refusal text is cut of its path"

echo "the history: one point a step, a missing reading kept null"
cat > "$T/hist.py" <<'PY'
import importlib.machinery, importlib.util, sys
ld = importlib.machinery.SourceFileLoader("hosts", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("hosts", ld)); ld.exec_module(m)
m.history_file().unlink(missing_ok=True)
for t in (1000, 1030, 1060, 1600, 1630, 2200):
    h = m.history({"at": t, "load": {"per_core_5m": 1.0}, "mem": {"avail": None if t == 2200 else 50.0, "rate": 0.0}})
print([p[0] for p in h], h[-1][2])
PY
check "$(python3 "$T/hist.py" "$H")" "[1000, 1600, 2200] None" "claims 30 s apart replace the provisional point: about 8 h in 48; no reading is null, never 0"

echo "dispatch-queue's sample_soon: the sweep and the claim start the sampler"
cat > "$T/soon.py" <<'PY'
import importlib.machinery, importlib.util, sys, types
ld = importlib.machinery.SourceFileLoader("dq", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("dq", ld)); ld.exec_module(m)
p = m.sample_soon()
print("started" if p else "none")
if p:
    p.wait(120)
    print("again:", "started" if m.sample_soon() else "none")
    import subprocess
    ref = lambda: subprocess.run(["git", "--git-dir=" + sys.argv[2], "rev-parse", "refs/regatta/hosts"], capture_output=True, text=True).stdout
    before = ref()
    f = m.sample_soon(refresh=True)
    print("the sweep's:", "started" if f else "none")
    if f:
        f.wait(120)
        # the row says what the claim's said a moment ago: only --refresh, passed on to the put, moves the ref
        print("moved:", ref() != before)
PY
STAMP="$HL/Caches/run-seed/queue/hosts-sample.stamp"   # dispatch-queue's qdir(): the sampler's last start
rm -f "$STAMP"
check "$(python3 "$T/soon.py" "$Q" "$T/home.git")" "started
again: none
the sweep's: started
moved: True" "sample_soon starts the sampler, not twice within SAMPLE_GAP, and the sweep's (refresh) whatever the gap, which puts an unchanged row"
# the sampler's lock: a claim's gives way to one holding it, the sweep's waits for it and then puts
LK="$HL/Caches/lighthouse/hosts-sample.lock"; mkdir -p "$(dirname "$LK")"
python3 -c "import fcntl, sys, time; f = open(sys.argv[1], 'w'); fcntl.flock(f, fcntl.LOCK_EX); open(sys.argv[2], 'w').close(); time.sleep(4)" "$LK" "$T/held" &
holder=$!
for _ in $(seq 1 100); do [ -e "$T/held" ] && break; sleep 0.1; done   # polled: a fixed sleep raced a loaded Mac
has "$(python3 "$H" sample --put 2>&1)" "another sample is putting this host's row" "a claim's sampler gives way to one holding the lock"
check "$(python3 "$H" sample --put --refresh | j 'd["result"]')" "pushed" "the sweep's waits for the lock, then puts"
wait "$holder" 2>/dev/null
check "$(python3 "$Q" hosts get | j 'd["rows"]["alpha"]["limits"]["cap"], d["rows"]["alpha"]["slots"]["busy"]')" "(3, 1)" "  its row reached the ref (the stand-in's slots, not the 99 put by hand)"
rm -f "$STAMP"
echo off > "$REGATTA_CONFIG/wharf-runs/hosts-sample"
check "$(python3 "$T/soon.py" "$Q" "$T/home.git")" "none" "wharf-runs/hosts-sample off: no sampler"
rm -f "$REGATTA_CONFIG/wharf-runs/hosts-sample"

[ "$fails" = 0 ] && echo "hosts: all passed" || { echo "hosts: $fails failed"; exit 1; }
