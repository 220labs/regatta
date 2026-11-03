#!/usr/bin/env bash
# evolve's suite (Evolve S2): `evolve probes`, the owner's answer surface end to end at zero tokens.
# The journey runs on its own scratch repo; here under a scratch config dir and state folder, with this
# checkout's keel (every stage holds) and a copy of it from before local_href (the link and render
# stages fail, naming the symptom). No network, no `claude`, nothing live written.
#   bash modules/aurora/tests/evolve.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
E="$D/bin/evolve"; K="$D/../keel"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT; [ -n "${KEEP:-}" ] && echo "scratch $T"
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(EVOLVE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(MEMO_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export REGATTA_CONFIG="$T/config" EVOLVE_STATE="$T/state" GIT_CONFIG_GLOBAL="$T/gitconfig"
printf '[user]\n\tname = t\n\temail = t@example.invalid\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
mkdir -p "$REGATTA_CONFIG"
fails=0
check() {
  if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3"; echo "       got:  $1"; echo "       want: $2"; fails=$((fails + 1)); fi
}
st() { python3 -c 'import json, sys; d = json.load(sys.stdin); print(" ".join("%s:%s" % (s["stage"], "ok" if s["ok"] else "FAIL") for s in d["journey"]))'; }

echo "probes — the journey on this checkout's keel"
out=$("$E" probes --json); rc=$?
check "$rc $(echo "$out" | st)" "0 board:ok link:ok render:ok saved:ok ingested:ok resumed:ok" "every stage holds: board, link, render, saved, ingested, resumed"
check "$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["not_probed"][:12])')" "not probed: " "  what no script can probe, said in every run"
check "$(wc -l < "$T/state/probes.jsonl" | tr -d ' ')" 1 "  one record line a run"
check "$(grep -c 'probe decision\|the target' "$T/state/probes.jsonl")" 0 "  the record holds verdicts and counts, never a doc's text"
"$E" probes --no-record > "$T/out.txt"; check "$? $(wc -l < "$T/state/probes.jsonl" | tr -d ' ')" "0 1" "--no-record: nothing appended"
check "$(tail -1 "$T/out.txt")" "probes: every stage holds" "  the text form's last line"

echo "probes — a keel from before local_href (every course page's file links were text)"
mkdir -p "$T/oldkeel/bin"; cp -R "$K/lib" "$T/oldkeel/lib"
python3 - "$K/bin/keel" "$T/oldkeel/bin/keel" <<'PY'
import sys
s = open(sys.argv[1]).read()
s = s.replace("    s = LOCAL_LINK_RE.sub(local, s)\n", "").replace("def local_href(", "def _gone_local_href(")
open(sys.argv[2], "w").write(s)
PY
out=$(REGATTA_HOME="$(cd "$D/../.." && pwd -P)" EVOLVE_KEEL="$T/oldkeel/bin/keel" "$E" probes --json --no-record); rc=$?   # the copy finds the core by REGATTA_HOME
check "$rc $(echo "$out" | st)" "1 board:ok link:FAIL render:FAIL saved:ok ingested:ok resumed:ok" "link and render fail, the rest holds: exit 1"
check "$(echo "$out" | python3 -c 'import json,sys; print([s["detail"] for s in json.load(sys.stdin)["journey"] if s["stage"] == "render"][0].split("; ")[1])')" \
  "1 local link, 1 shown as text, not a link" "  the render stage names the symptom, read from the page's visible text"

echo "probes --doc — a real doc, read-only"
mkdir -p "$T/r/docs"; git -C "$T/r" init -q; printf 'x\n' > "$T/r/docs/t.md"; git -C "$T/r" add -A; git -C "$T/r" commit -qm i
git -C "$T/r" remote add origin https://github.com/acme/r.git; git -C "$T/r" update-ref refs/remotes/origin/main HEAD
printf '# A doc\n\nSee [t](%s/docs/t.md#L1), [gone](%s/docs/gone.md) and [new](%s/docs/new.md).\n\n- **D1 — One**\n  - A — a\n  - B — b\n\n  Reversible: yes\n\n  ➤ Recommended: A\n\n  ➤ Answer:\n' "$T/r" "$T/r" "$T/r" > "$T/r/docs/d.md"
printf 'n\n' > "$T/r/docs/new.md"; cp "$T/r/docs/d.md" "$T/d.before"
out=$("$E" probes --doc "$T/r/docs/d.md" --json --no-record); rc=$?
check "$rc" 1 "a doc with a dead link: exit 1"
check "$(echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin)["docs"][0]["stages"][0]; print(d["ok"], d["detail"])')" \
  "False 3 local links: 2 open here, 1 with a GitHub address; open nothing here: gone.md; no GitHub address (on no origin ref): new.md" \
  "  the link stage names the link that opens nothing and the one GitHub cannot show"
check "$(cmp -s "$T/d.before" "$T/r/docs/d.md" && echo same) $(ls "$T/r/docs" | tr '\n' ' ')" "same d.md new.md t.md " "  the doc untouched, nothing written beside it"
out=$("$E" probes --doc "$T/no-such.md" --json --no-record); check "$? $(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["docs"][0]["stages"][0]["detail"])')" "1 no such file" "a doc that is not there: exit 1"

echo "probes --doc — a confidential scope's doc is fenced (S2's landing review, finding 10)"
mkdir -p "$T/p/sec/docs" "$REGATTA_CONFIG/regatta"; cp "$T/r/docs/d.md" "$T/p/sec/docs/secret-plan.md"
printf '%s\n' "$T/p" > "$REGATTA_CONFIG/regatta/projects"
printf '{"repos": {"sec": {}}, "scopes": {"s": {"repos": ["sec"], "confidential": true}}}\n' > "$T/repos.json"
out=$(CLAUDE_REPOS_JSON="$T/repos.json" "$E" probes --doc "$T/p/sec/docs/secret-plan.md" --json); rc=$?
check "$rc $(echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["docs"]), d["fenced"])')" "0 0 1" "  neither probed nor named: counted"
check "$(grep -c 'secret-plan' "$T/state/probes.jsonl")" 0 "  its name in no record (the record is global)"
head -c 20 "$T/repos.json" > "$T/torn.json"
out=$(CLAUDE_REPOS_JSON="$T/torn.json" "$E" probes --doc "$T/r/docs/d.md" --json --no-record)
check "$(echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["docs"]), d["fenced"])')" "0 1" "  a torn registry fences every doc"
rm -f "$REGATTA_CONFIG/regatta/projects"

echo "probes — no keel"
EVOLVE_KEEL="$T/no-keel" "$E" probes --no-record > /dev/null 2> "$T/err"; rc=$?
check "$rc $(grep -c 'keel' "$T/err")" "2 1" "a keel that is not there: exit 2, one line"

echo; [ "$fails" -eq 0 ] && echo "evolve: all ok" || { echo "evolve: $fails failed"; exit 1; }
