#!/usr/bin/env bash
# Tests for bin/berth (docs/skipper-modes-2026-10-21.md S6b): the scope's berths crossed with the
# repo's clone hosts, the load rule, the log-only week, the row in berth.jsonl, and dispatch's
# --on auto and --slots. A scratch registry and config dir; a stand-in ssh; no network, no model.
#   bash modules/wharf-runs/tests/test_berth.sh
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/config_fixture.sh"; fixture_config "$T/config"
export HOME="$T/home"; mkdir -p "$HOME"
unset DISPATCH_HOST CLAUDE_UNATTENDED REGATTA_UNATTENDED DISPATCH_LABEL DISPATCH_MODE
# the running session's id would make each case a typed skipper, whose dispatch runs the real `helm page` (S1)
unset CLAUDE_CODE_SESSION_ID
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
# hosts are fixture names (h1 the Mac under test, h2 its peer): no real host in the suite (the design's S6b)
cat > "$T/repos.json" <<'EOF'
{"repos": {"pub": {"hosts": ["h1", "h2"]}, "solo": {"hosts": ["h1"]}, "free": {"hosts": ["h1", "h2"]}, "far": {"hosts": ["h2"]}},
 "scopes": {"open": {"file": "o.code-workspace", "repos": ["pub", "solo"], "berths": ["h2", "h1"]},
            "loose": {"file": "l.code-workspace", "repos": ["free"]},
            "tight": {"file": "t.code-workspace", "repos": ["far"], "berths": ["h1"]}}}
EOF
export CLAUDE_REPOS_JSON="$T/repos.json" BERTH_HOST=h1
mkdir -p "$T/config/wharf-runs"; echo "h2:h2-alias" > "$T/config/wharf-runs/ssh"
# the peer: prints what the probe asks for — its load and cores, then its dispatch --slots — from $PEER
cat > "$T/ssh" <<EOF
#!/bin/sh
echo "ssh \$*" >> "$T/ssh.calls"
[ -n "\${PEER_DOWN:-}" ] && exit 255
printf '%s\n' "\${PEER:-1.0 10}" "\${PEER_SLOTS:-2 10}"
EOF
chmod +x "$T/ssh"; export BERTH_SSH="$T/ssh"
bj() { python3 "$B/berth" "$@" --json | python3 -c 'import json, sys; d = json.load(sys.stdin); print(d["pick"], d["would"], d["enforced"])'; }

echo "privacy: the scope's berths, in order, crossed with the clone hosts"
check "$(python3 "$B/berth" pub --json --no-log | python3 -c 'import json, sys; print(json.load(sys.stdin)["candidates"])')" "['h2', 'h1']" "berths in the scope's order"
check "$(python3 "$B/berth" solo --json --no-log | python3 -c 'import json, sys; print(json.load(sys.stdin)["candidates"])')" "['h1']" "  a host the repo is not cloned on is left out"
python3 "$B/berth" far --no-log > "$T/out" 2>&1; check "$?" "3" "berths and clone hosts that share none: no berth, exit 3"
grep -q "no host may take far" "$T/out"; check "$?" "0" "  …saying why"
check "$(python3 "$B/berth" free --json --no-log | python3 -c 'import json, sys; d = json.load(sys.stdin); print(d["candidates"], d["source"])')" \
  "['h2', 'h1'] no berths: each peer, then this Mac" "a scope with no berths: dispatch's order before berth (each peer, then here)"

echo "log-only (neither key set): the first that answers, the load rule's pick beside it"
check "$(PEER="20.0 10" BERTH_LOADAVG="1.0 10" BERTH_SLOTS="1 3" bj pub --no-log)" "h2 h1 False" "a loaded peer: still the pick, the load rule would take this Mac"
check "$(PEER_DOWN=1 BERTH_LOADAVG="1.0 10" BERTH_SLOTS="1 3" bj pub --no-log)" "h1 h1 False" "a peer that does not answer is no candidate"
PEER_DOWN=1 python3 "$B/berth" pub --no-log --json > /dev/null 2>&1; check "$?" "0" "  …this Mac still answers: a pick"
check "$(PEER_DOWN=1 python3 "$B/berth" pub --no-log --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["samples"]["h2"]["answered"])')" "False" "  the peer's row says it did not answer"

echo "enforced (the keys set without log)"
echo "1.5" > "$T/config/wharf-runs/load-max"; echo "0.5" > "$T/config/wharf-runs/load-margin"
check "$(PEER="5.0 10" BERTH_LOADAVG="20.0 10" BERTH_SLOTS="1 3" bj pub --no-log)" "h2 h2 True" "the first host with a slot under load-max: taken"
check "$(PEER="20.0 10" BERTH_LOADAVG="10.0 10" BERTH_SLOTS="1 3" bj pub --no-log)" "h1 h1 True" "the first loaded, a later one lighter by the margin: the later one"
check "$(PEER="20.0 10" BERTH_LOADAVG="18.0 10" BERTH_SLOTS="1 3" bj pub --no-log)" "h2 h2 True" "  lighter, but not by the margin: the first stays the pick (its cap refuses at fire time)"
check "$(PEER="5.0 10" PEER_SLOTS="10 10" BERTH_LOADAVG="30.0 10" BERTH_SLOTS="1 3" bj pub --no-log)" "h1 h1 True" "the first full: a later one with a slot, whatever its load (no bar to beat)"
check "$(PEER="5.0 10" PEER_SLOTS="slots-unknown" BERTH_LOADAVG="1.0 10" BERTH_SLOTS="1 3" bj pub --no-log)" "h2 h2 True" "a peer whose dispatch predates --slots counts as free"
echo "1.5 log" > "$T/config/wharf-runs/load-max"
check "$(PEER="20.0 10" BERTH_LOADAVG="1.0 10" BERTH_SLOTS="1 3" bj pub --no-log)" "h2 h1 False" "\`1.5 log\`: log-only again"
echo "1.2" > "$T/config/wharf-runs/load-max"; rm -f "$T/config/wharf-runs/load-margin"
check "$(PEER="20.0 10" BERTH_LOADAVG="1.0 10" BERTH_SLOTS="1 3" bj pub --no-log)" "h1 h1 True" \
  "load-max set alone, load-margin unset: enforced, the margin at its default (landing review 19)"
echo "0.5" > "$T/config/wharf-runs/load-margin"

echo "a torn registry: no candidates, exit 3, the reason names it (landing review B1)"
head -c 60 "$T/repos.json" > "$T/torn.json"
CLAUDE_REPOS_JSON="$T/torn.json" python3 "$B/berth" pub --no-log > "$T/out" 2>&1; check "$?" "3" "a repos.json that will not read: refused, never every host"
grep -q "no host may take pub: the registry .* will not read" "$T/out"; check "$?" "0" "  …the reason names the registry"

echo "the row, the time (G4: no model call, under 2 s)"
s0=$(python3 -c 'import time; print(time.time())')
PEER="1.0 10" BERTH_LOADAVG="1.0 10" BERTH_SLOTS="1 3" python3 "$B/berth" pub > /dev/null
s1=$(python3 -c 'import time; print(time.time())')
check "$(python3 -c "print($s1 - $s0 < 2)")" "True" "a pick takes under 2 s"
check "$(python3 -c 'import json, sys; r = [json.loads(l) for l in open(sys.argv[1])][-1]; print(r["repo"], r["pick"], sorted(r["samples"]), r["samples"]["h2"]["load"], r["scope"])' "$HOME/Library/Logs/claude-weekly/berth.jsonl")" \
  "pub h2 ['h1', 'h2'] 1.0 open" "its row in berth.jsonl: the repo, the pick, each host's samples, the scope"
grep -q -- "-o BatchMode=yes -o ConnectTimeout=10 h2-alias" "$T/ssh.calls"; check "$?" "0" "the peer read over its wharf-runs/ssh alias, BatchMode, 10 s connect"

echo "dispatch: --slots, and --on auto placing by berth"
check "$(DISPATCH_HOST=h1 DISPATCH_MAX_RUNS=4 "$B/dispatch" --slots)" "0 4" "--slots: the busy runs and the cap"
git init -q --bare "$T/origin.git"; git init -q -b main "$T/repo"
(cd "$T/repo" && git config user.email t@t && git config user.name t && echo x > f && git add f && git commit -qm init \
  && git checkout -q -b claude/h1/2026-10-21-demo && mkdir -p docs/handoff && echo "# b" > docs/handoff/2026-10-21-demo.md \
  && git add . && git commit -qm seed && git remote add origin "$T/origin.git" && git push -q origin claude/h1/2026-10-21-demo 2>/dev/null \
  && git checkout -q main) || cp -R "$T/repo/.git/." "$T/origin.git/"
printf -- '- physical: none\n' > "$T/repo/AGENTS.md"
mkdir -p "$HOME/projects"; ln -s "$T/repo" "$HOME/projects/pub"; ln -s "$T/repo" "$HOME/projects/far"
cat > "$T/launchctl" <<EOF
#!/bin/sh
echo "\$*" >> "$T/lc.calls"; exit 0
EOF
chmod +x "$T/launchctl"
echo "1.5" > "$T/config/wharf-runs/load-max"   # enforced again for the first dispatch case
dsp() { env -u DISPATCH_DEFAULT_ON DISPATCH_HOST=h1 DISPATCH_LAUNCHCTL="$T/launchctl" DISPATCH_SSH="$T/ssh" "$B/dispatch" claude/h1/2026-10-21-demo "$@"; }
: > "$T/ssh.calls"
PEER="20.0 10" BERTH_LOADAVG="1.0 10" BERTH_SLOTS="0 3" dsp --repo "$HOME/projects/pub" --at @$(( $(date +%s) + 86400 )) > "$T/d1" 2>&1
grep -q "dispatch: berth — h1" "$T/d1"; check "$?" "0" "the default is auto: berth picks this Mac (enforced, the peer loaded)"
check "$(grep -c 'h2-alias.*bin/dispatch"* claude/' "$T/ssh.calls")" "0" "  …and nothing is scheduled on the peer"
: > "$T/ssh.calls"
echo "1.5 log" > "$T/config/wharf-runs/load-max"
PEER="20.0 10" BERTH_LOADAVG="1.0 10" BERTH_SLOTS="0 3" dsp --repo "$HOME/projects/pub" --at @$(( $(date +%s) + 86400 )) > "$T/d2" 2>&1
grep -q "dispatch: berth — h2" "$T/d2"; check "$?" "0" "log-only: the first berth that answers (the peer), as dispatch did before"
grep -q 'h2-alias.*bin/dispatch"* claude/h1/2026-10-21-demo --at' "$T/ssh.calls"; check "$?" "0" "  scheduled on the peer through its alias"
PEER="1.0 10" dsp --repo "$HOME/projects/far" --at @$(( $(date +%s) + 86400 )) > "$T/d3" 2>&1; check "$?" "2" "a repo no berth may take: refused"
grep -q "dispatch: no berth for" "$T/d3"; check "$?" "0" "  …saying so"
rows0=$(wc -l < "$HOME/Library/Logs/claude-weekly/berth.jsonl")
PEER="1.0 10" dsp --repo "$HOME/projects/pub" --at @$(( $(date +%s) + 86400 )) --dry-run > "$T/d5" 2>&1
check "$(wc -l < "$HOME/Library/Logs/claude-weekly/berth.jsonl")" "$rows0" "--dry-run: berth asked with --no-log, no row in the log-only week (landing review 21)"
PEER="1.0 10" dsp --repo "$HOME/projects/pub" --on nowhere --at @$(( $(date +%s) + 86400 )) > "$T/d4" 2>&1; check "$?" "2" "--on a host with no wharf-runs/ssh alias: refused"

echo
[ "$fails" = 0 ] && echo "test_berth: all passed" || { echo "test_berth: $fails failed"; exit 1; }
