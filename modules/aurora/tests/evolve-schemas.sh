#!/usr/bin/env bash
# evolve's S3 suite: the schemas, lenses.json, `evolve coverage` (the register, the surface diff, the collector
# manifest a quiet receipt needs) and `evolve conformance` (rules against transcripts), on synthetic scopes — a
# software, a film and a household one, a confidential one whose repos are not on this host, an orphan repo and
# a planted log area nothing reads. Scratch HOME, config dir, projects folder and log dir: nothing live is read
# or written. No network, no `claude`.
#   bash modules/aurora/tests/evolve-schemas.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd -P)"
E="$D/bin/evolve"
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT; [ -n "${KEEP:-}" ] && echo "scratch $T"
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(EVOLVE[A-Za-z0-9_]*\)=.*/\1/p; s/^\(DISPATCH_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset ACCOUNTS_FILE ASKS_STATE
CP="$T/h/.claude/projects"   # the login dir's transcripts (HOME moved here)
export HOME="$T/h" REGATTA_CONFIG="$T/config" GIT_CONFIG_GLOBAL="$T/gitconfig"
printf '[user]\n\tname = t\n\temail = t@example.invalid\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
P="$T/projects"; L="$T/log"; C="$REGATTA_CONFIG"
mkdir -p "$CP" "$C/regatta" "$C/aurora/scopes" "$C/sextant" "$C/helm" "$P" "$L"
printf '%s\n' "$P" > "$C/regatta/projects"; printf '%s\n' "$L" > "$C/regatta/log-dir"
export EVOLVE_STATE="$L/aurora/evolve" CLAUDE_REPOS_JSON="$C/repos.json"
fails=0
check() {
  if [ "$1" = "$2" ]; then echo "  ok  $3"; else echo "  FAIL $3"; echo "       got:  $1"; echo "       want: $2"; fails=$((fails + 1)); fi
}
# j EXPR: evaluate EXPR on the JSON on stdin as `d` (a file, so no quoted heredoc sits inside "$(…)": bash 3.2)
cat > "$T/j.py" <<'PY'
import json, sys
d = json.load(sys.stdin)
cell = lambda s, src: next((c for sc in d["scopes"] if sc["scope"] == s for c in sc["cells"] if c["source"] == src), None)
scope = lambda s: next((sc for sc in d["scopes"] if sc["scope"] == s), None)
print(eval(sys.argv[1]))
PY
j() { python3 "$T/j.py" "$1"; }
now() { python3 -c 'import datetime as d, sys; print((d.datetime.now(d.timezone.utc) + d.timedelta(days=float(sys.argv[1]))).isoformat(timespec="seconds"))' "${1:-0}"; }
mkrepo() { mkdir -p "$P/$1"; git -C "$P/$1" init -q; printf '# %s\n' "$1" > "$P/$1/AGENTS.md"; git -C "$P/$1" add -A; git -C "$P/$1" commit -qm init; }

# ---- the fixtures: four scopes, one orphan repo, one planted area ------------------------------------------
mkrepo soft-knowledge; mkrepo soft-app; mkrepo film-notes; mkrepo house-ops; mkrepo orphan
printf 'todo\n' > "$P/soft-app/TODO.md"
mkdir -p "$P/soft-knowledge/evolve" "$P/soft-knowledge/.claude" "$P/soft-knowledge/meetings"
printf 'pass\n' > "$P/soft-knowledge/.claude/scope-pass.md"; printf 'notes\n' > "$P/soft-knowledge/meetings/brief.md"
cat > "$C/repos.json" <<'J'
{"repos": {"soft-knowledge": {}, "soft-app": {}, "film-notes": {}, "house-ops": {}, "vault-knowledge": {}, "orphan": {}},
 "scopes": {"soft": {"repos": ["soft-knowledge", "soft-app"]},
            "film": {"repos": ["film-notes"]},
            "house": {"repos": ["house-ops"]},
            "group": {"repos": ["soft-*", "vault-*"]},
            "vault": {"repos": ["vault-knowledge"], "confidential": true}}}
J
# the pass's section (S5's evolve-scope.md) names each source it reads; meeting-notes is left out, to be `unread`
mkdir -p "$T/sections"; export EVOLVE_SECTIONS="$T/sections"
python3 - "$D/lenses.json" > "$T/sections/evolve-scope.md" <<'PY'
import json, sys
ids = [s["id"] for l in json.load(open(sys.argv[1]))["lenses"] for s in l["sources"]
       if s["id"] not in ("meeting-notes", "dispatch", "interruptions")]
print("the board, the trim, the meeting-notes and the health of things are prose here: never a read")
print("Run `x --flag` and then the meeting-notes and the dispatch, then `y`: prose between two spans")
print("```bash\n\"$regatta\" interruptions --scope <scope>\n```")   # a verb run in a fenced block is a read
print("\n".join("- `%s`" % i for i in ids + ["cut-feedback", "pipeline-check", "deploy-log", "misfires",
                                           "scheduler", "secretclient-ledger", "secretclient-tool"]))
PY
MARK="confidential:$(printf vault | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.read().encode()).hexdigest()[:8])')"
# what every scope's required collectors read, fresh
printf '{"goals": []}\n' > "$C/sextant/north-star.json"
printf '{"time": "%s"}\n' "$(now)" > "$L/ops.jsonl"; printf '{"time": "%s"}\n' "$(now)" > "$L/ops-verdicts.jsonl"
printf 'a denial\n' > "$L/fence.log"; printf 'people\n' > "$C/helm/people"
mkdir -p "$L/render-farm"; printf 'frame 1\n' > "$L/render-farm/queue.log"     # the planted area nothing reads
# the film scope declares its own sources; commercial does not apply; meetings excluded until a date ahead
mkdir -p "$P/film-notes/production" "$P/film-notes/cuts" "$L/film-pipeline"
mkdir -p "$P/film-notes/.claude"; printf 'Read `production-notes` first.\n' > "$P/film-notes/.claude/scope-pass.md"
printf 'day 1\n' > "$P/film-notes/production/day1.md"; printf '{"time": "%s"}\n' "$(now)" > "$P/film-notes/cuts/feedback.jsonl"
printf '{"time": "%s"}\n' "$(now -30)" > "$L/film-pipeline/check.jsonl"   # a fresh file whose newest record is 30 days old
cat > "$C/aurora/scopes/film.json" <<'J'
{"sources": [
  {"id": "production-notes", "lens": "product", "kind": "path", "at": "{anchor}/production", "fresh_days": 14, "reader": "pass"},
  {"id": "cut-feedback", "lens": "product", "kind": "path", "at": "{anchor}/cuts/feedback.jsonl", "fresh_days": 14, "reader": "pass"},
  {"id": "pipeline-check", "lens": "engineering", "kind": "path", "at": "{log}/film-pipeline/check.jsonl", "fresh_days": 7, "reader": "pass"}],
 "not_applicable": ["commercial"],
 "exclude": {"meeting-notes": {"reason": "no meetings in this production", "review": "2099-01-01"}}}
J
# the household: a deploy log and misfires, a verb that is not installed, an exclusion whose review has passed
mkdir -p "$L/house"; printf '{"time": "%s"}\n' "$(now)" > "$L/house/deploy.jsonl"
cat > "$C/aurora/scopes/house.json" <<'J'
{"sources": [
  {"id": "deploy-log", "lens": "reliability", "kind": "path", "at": "{log}/house/deploy.jsonl", "fresh_days": 7, "reader": "pass", "collector": "health"},
  {"id": "misfires", "lens": "reliability", "kind": "path", "at": "{log}/house/misfires.jsonl", "fresh_days": 7, "reader": "pass"},
  {"id": "scheduler", "lens": "process", "kind": "verb", "name": "no-such-verb", "reader": "pass"}],
 "exclude": {"principles": {"reason": "household, no principles yet", "review": "2020-01-01"}},
 "conformance": [{"id": "h-deploy", "when": "deploy-house"}]}
J
# the confidential scope's profile names a client: none of it may reach an output or a record
cat > "$C/aurora/scopes/vault.json" <<'J'
{"exclude": {"meeting-notes": {"reason": "SECRETCLIENT board", "review": "2099-01-01"}},
 "sources": [{"id": "secretclient-ledger", "lens": "money", "kind": "path", "at": "{anchor}/ledger.jsonl", "reader": "pass"},
             {"id": "secretclient-tool", "lens": "tools", "kind": "verb", "name": "secretclient-cli", "reader": "secretclient-reader"}],
 "conformance": [{"id": "secretclient-rule", "when": "never-said"}]}
J

echo "lenses.json — fourteen lenses, unique ids, readers that exist, the Ring 1 size"
cat > "$T/lenses.py" <<'PY'
import json, sys, glob, os
d = json.load(open(sys.argv[1]))
mods = os.path.dirname(os.path.dirname(sys.argv[1]))
ls = d["lenses"]
srcs = [s for l in ls for s in l["sources"]]
readers = {s.get("reader") for s in srcs} - {None, "pass", "evolve"}
missing = sorted(r for r in readers if not glob.glob(os.path.join(mods, "*", "bin", r)))
ids = [s["id"] for s in srcs]
cols = {x for c in d["collectors"] for x in c["sources"]}
print(len(ls), [l["n"] for l in ls] == list(range(1, 15)), len(ids) == len(set(ids)), missing, sorted(cols - set(ids)),
      sorted(d["outcome_classes"]) == sorted(set(d["outcome_classes"])), sum(1 for _ in open(sys.argv[1])) <= 300)
PY
check "$(python3 "$T/lenses.py" "$D/lenses.json")" "14 True True [] [] True True" "14 lenses numbered 1-14, source ids unique, every reader installed, every collector's source declared, ≤ 300 lines"
check "$(grep -c -E '"/|~/|@' "$D/lenses.json")" 0 "  no absolute path, home folder or address in it: every path under a placeholder"

echo "coverage — the register over every scope, from one registry read"
out=$("$E" coverage --json); rc=$?
echo "$out" > "$T/cov1.json"
check "$rc $(echo "$out" | j '[s["scope"] for s in d["scopes"]], d["skipped_confidential"]')" "1 (['film', 'group', 'house', 'soft'], 1)" "every scope walked, the confidential one counted and never opened (judged under its own --scope): exit 1 (blind spots)"
outv=$("$E" coverage --json --scope vault)
echo "$outv" > "$T/covv.json"
check "$(echo "$outv" | j '[s["scope"] for s in d["scopes"]], d["skipped_confidential"]')" "(['$MARK'], 0)" "  its own run judges it, by its marker"
check "$(echo "$out" | j 'cell("soft", "probes")["state"], cell("soft", "principles")["state"], cell("soft", "people")["state"], cell("soft", "people")["why"]')" \
  "('source_missing', 'source_missing', 'unread', 'nothing reads it yet')" "source_missing (nothing at the path) apart from unread (nothing reads it)"
check "$(echo "$out" | j 'cell("film", "pipeline-check")["state"], cell("film", "pipeline-check")["age_days"] >= 29')" "('stale', True)" "stale: the newest record's own time, not the file's mtime"
check "$(echo "$outv" | j 'cell("'"$MARK"'", "todo")["state"], cell("'"$MARK"'", "todo")["why"]')" \
  "('inaccessible', 'declared, and its repo is not on this host')" "inaccessible: declared and not readable on this yard, apart from stale"
check "$(echo "$out" | j 'sorted({c["state"] for c in scope("film")["cells"] if c["lens"] == "commercial"}), cell("film", "meeting-notes")["state"], cell("film", "meeting-notes").get("overdue")')" \
  "(['not_applicable'], 'excluded', False)" "the film profile: commercial not applicable, meetings excluded until its review"
check "$(echo "$out" | j 'cell("film", "cut-feedback")["state"], cell("film", "production-notes")["state"]')" "('observed', 'observed')" "  its own sources read: cut feedback by the section, production notes by the anchor's own scope-pass.md"
check "$(echo "$out" | j 'cell("house", "scheduler")["state"], cell("house", "misfires")["state"], cell("house", "principles")["overdue"]')" \
  "('source_missing', 'source_missing', True)" "the household: a verb not installed, a log not there, an exclusion past its review"
check "$(echo "$out" | j 'cell("group", "repo-git")["state"], cell("group", "todo")["state"], cell("group", "agents-md")["state"]')" \
  "('observed', 'observed', 'observed')" "an open scope over a confidential repo (by glob): that member skipped, never judged (else inaccessible)"
check "$(echo "$out" | j 'cell("soft", "repo-git")["state"], cell("soft", "scope-pass-md")["state"]')" "('observed', 'observed')" "the anchor's and every member's sources observed"
check "$(echo "$out" | j 'cell("soft", "meeting-notes")["state"], cell("soft", "meeting-notes")["why"]')" \
  "('unread', 'the pass section (evolve-scope.md) does not read it yet')" "  a source the pass's section names only in prose: unread, though it is there"

echo "coverage — the surface diff names the planted area"
check "$(echo "$out" | j '"log:render-farm" in d["surface"]["unobserved"], "repo:orphan" in d["surface"]["unobserved"]')" "(True, True)" "the planted log area and the repo in no scope: named"
check "$(echo "$out" | j '[u for u in d["surface"]["unobserved"] if u.startswith(("log:ops", "log:fence", "log:film", "log:house", "config:aurora", "config:sextant/north", "repo:soft", "config:repos"))]')" "[]" "  what a source reads is not on it"
SLUG=$(python3 -c 'import re, sys; print(re.sub(r"[^A-Za-z0-9]", "-", sys.argv[1]))' "$P/vault-knowledge")
mkdir -p "$L/$SLUG"; printf 'x\n' > "$L/$SLUG/x"
out=$("$E" coverage --json --no-record)
check "$(echo "$out" | j 'd["surface"]["fenced"], [u for u in d["surface"]["unobserved"] if "vault" in u]')" "(2, [])" "  an entry of a confidential scope's, and its repo: counted, not named"
rm -rf "${L:?}/$SLUG"

echo "coverage — nothing of the confidential scope is named"
cp "$C/aurora/scopes/vault.json" "$T/vault.orig"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["sources"].append({"id": "secretclient-books", "lens": "money", "kind": "path", "at": "{log}/secretclient/books.jsonl", "reader": "pass"}); json.dump(d, open(sys.argv[1], "w"))' "$C/aurora/scopes/vault.json"
mkdir -p "$L/secretclient"; printf '{}\n' > "$L/secretclient/books.jsonl"; printf 'x\n' > "$L/secretclient/board-notes.txt"
out=$("$E" coverage --json --no-record)
check "$(echo "$out" | grep -c -i secretclient) $(echo "$out" | j 'd["surface"]["fenced"] >= 2')" "0 True" "a confidential profile's own {log} folder: counted on the surface, never named, nor its siblings"
printf '{"sources": [' > "$C/aurora/scopes/vault.json"
out=$("$E" coverage --json --no-record)
check "$(echo "$out" | grep -c -i secretclient) $(echo "$out" | j '[u for u in d["surface"]["unobserved"] if not u.startswith("repo:")]')" "0 []" "  with its profile torn (its folders unknown), no log or config entry is named at all"
cp "$T/vault.orig" "$C/aurora/scopes/vault.json"; rm -rf "${L:?}/secretclient"
check "$(grep -c -i 'vault\|secretclient' "$T/cov1.json" "$T/covv.json" | tr '\n' ' ')" "$T/cov1.json:0 $T/covv.json:0 " "the JSON names neither the scope nor its profile's words"
"$E" coverage --no-record > "$T/cov.txt"; "$E" coverage --no-record --scope vault > "$T/covv.txt"
check "$(grep -c -i 'vault\|secretclient' "$T/cov.txt" "$T/covv.txt" | tr '\n' ' ')$(grep -c "^scope $MARK" "$T/covv.txt") $(grep -c "^1 confidential scope judged only inside it" "$T/cov.txt")" "$T/cov.txt:0 $T/covv.txt:0 1 1" "  nor the text form: the marker stands for it in its own run, a count in the global one"
check "$(echo "$(cat "$T/covv.json")" | j 'cell("'"$MARK"'", "profile-source-1")["state"]')" "inaccessible" "  its profile's own source is counted under a neutral id"
check "$(j 'cell("'"$MARK"'", "profile-source-2")["state"], cell("'"$MARK"'", "profile-source-2")["reader"], cell("'"$MARK"'", "profile-source-2")["why"]' < "$T/covv.json")" \
  "('source_missing', 'tool', 'nothing there')" "  its profile's verb and reader named by neither word: a neutral reader and why"
check "$(grep -c -i 'vault\|secretclient' "$EVOLVE_STATE/coverage.jsonl") $(ls "$EVOLVE_STATE/manifests" | grep -c -i vault)" "0 0" "  the record and the manifests' names hold none of it"
check "$(j 'sorted(scope("'"$MARK"'")["manifest"]["hashes"])' < "$T/covv.json") $(j '"refs" in scope("soft")["manifest"]' < "$T/cov1.json")" "['lenses', 'north_star'] False" "  the global record: no hash of its entry or profile to confirm a guess against, and nobody's heads"

echo "coverage — the collector manifest a quiet receipt rests on, against the last complete pass"
q() { "$E" coverage --json --scope soft "$@" | j 'scope("soft")["manifest"]["quiet_ok"], scope("soft")["manifest"]["changed"], scope("soft")["manifest"]["changed_sources"]'; }
# a whole pass: its opening run (recorded), then --promote once its receipt is complete
settle() { "$E" coverage --scope "${1:-soft}" --open > /dev/null; "$E" coverage --scope "${1:-soft}" --promote > /dev/null; }
check "$(j 'scope("soft")["manifest"]["quiet_ok"], scope("soft")["manifest"]["changed"]' < "$T/cov1.json")" "(False, ['no complete pass yet'])" "a first run: never quiet"
mkdir -p "$EVOLVE_STATE/receipts/soft"; printf '{"time": "%s"}\n' "$(now)" > "$EVOLVE_STATE/receipts/soft/week-digest.json"
check "$(q)" "(False, ['no complete pass yet'], [])" "a run that only looked moves no baseline: still not quiet"
settle
out=$("$E" coverage --json --scope soft)
check "$(echo "$out" | j 'scope("soft")["manifest"]["quiet_ok"], scope("soft")["manifest"]["why"], d["surface"]["items"]')" "(True, [], 0)" "after a complete pass, nothing changed, every required collector fresh: quiet allowed (--scope: no surface)"
check "$(echo "$out" | j '[c["id"] for c in scope("soft")["manifest"]["collectors"] if not c["fresh"]]')" "['research']" "  a collector not required (the night's research) may be missing"
mv "$EVOLVE_STATE/receipts/soft/week-digest.json" "$T/receipt"
check "$("$E" coverage --json --scope soft --no-record | j 'scope("soft")["manifest"]["why"]')" "['collector digest: week-digest no run receipt']" "an installed verb that never ran: no fresh collector"
mv "$T/receipt" "$EVOLVE_STATE/receipts/soft/week-digest.json"
printf '{"goals": ["g1"]}\n' > "$C/sextant/north-star.json"
check "$(q)" "(False, ['north_star'], ['north-star'])" "the North Star changed: not quiet"
check "$(q)" "(False, ['north_star'], ['north-star'])" "  and still not, however many runs look, until a complete pass"
settle; check "$(q)" "(True, [], [])" "  quiet once a complete pass has seen it (--promote)"
sleep 1; printf '{"time": "%s"}\n' "$(now)" >> "$L/ops.jsonl"
check "$(q)" "(True, [], [])" "a shared log's routine record does not wake the scope"
printf '{"time": "%s"}\n' "$(now)" >> "$L/ops-verdicts.jsonl"
check "$(q)" "(False, [], ['ops-verdicts'])" "  an ops verdict (a source marked wakes) does"
settle; sleep 1
printf 'more\n' >> "$P/soft-app/AGENTS.md"; git -C "$P/soft-app" commit -qam more
check "$(q --no-record)" "(False, ['git'], ['agents-md'])" "a commit in the second member, not only the anchor, wakes the scope (its heads; its file)"
settle
printf 'old\n' > "$P/soft-app/old.txt"; git -C "$P/soft-app" add old.txt
GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" git -C "$P/soft-app" commit -q -m old
check "$(q --no-record)" "(False, ['git'], [])" "  a branch head moved by a commit dated long before the cutoff (a fast-forward): the heads, read as values"
settle; git -C "$P/soft-app" switch -q -c side; printf 'w\n' > "$P/soft-app/w.txt"; git -C "$P/soft-app" add w.txt; git -C "$P/soft-app" commit -qm w; git -C "$P/soft-app" switch -q main
check "$(q --no-record)" "(False, ['git'], [])" "  a commit on another branch (a worktree's) too"
settle; sleep 1
# a whole pass: its opening run, then what it writes itself — the findings in place, its records branch, its session
"$E" coverage --scope soft --open > /dev/null
printf '{}\n' > "$P/soft-knowledge/evolve/2026-11-08.findings.json"
sleep 1; git -C "$P/soft-knowledge" switch -q -c claude/x/2026-11-08-scope-pass; mkdir -p "$P/soft-knowledge/dreams"; printf 'd\n' > "$P/soft-knowledge/dreams/2026-11-08.md"
git -C "$P/soft-knowledge" add dreams; git -C "$P/soft-knowledge" commit -qm dream; git -C "$P/soft-knowledge" switch -q main
git -C "$P/soft-knowledge" merge -q --ff-only claude/x/2026-11-08-scope-pass
KS="$CP/$(python3 -c 'import re, sys; print(re.sub(r"[^A-Za-z0-9]", "-", sys.argv[1]))' "$P/soft-knowledge")"; mkdir -p "$KS"; printf '{}\n' > "$KS/pass-1.jsonl"
"$E" coverage --scope soft --promote --session pass-1 > /dev/null
check "$(q --no-record)" "(True, [], [])" "the pass's own writes (its findings, its records branch and their merge, its session) are no change to it"
sleep 1; printf '{}\n' > "$KS/pass-2.jsonl"   # the next pass is running: its session started before its opening run
check "$("$E" coverage --json --scope soft --open --session pass-2 | j 'scope("soft")["manifest"]["quiet_ok"]')" "True" "  nor is the running pass's own session to its opening run (--open --session)"
"$E" coverage --scope soft --promote > /dev/null
check "$(q --no-record)" "(True, [], [])" "  and the baseline keeps it, promoted without naming it again"
printf '{"findings": [{"evidence_refs": 7}], "x": 1}\n' > "$P/soft-knowledge/evolve/2026-11-09.findings.json"
out=$("$E" coverage --json --no-record); rc=$?
check "$rc $(echo "$out" | j 'len(d["scopes"])')" "1 4" "a findings file of the wrong shape in an anchor: read past, every scope still judged, never a crash"
chmod 000 "$P/soft-knowledge/evolve"
"$E" coverage --json --no-record > /dev/null 2> "$T/err"; rc=$?
chmod 755 "$P/soft-knowledge/evolve"
check "$rc $(grep -c -E 'Errno|soft-knowledge' "$T/err")" "1 0" "  an anchor's findings folder not readable: no count, never a crash, no path on stderr"
printf '{"findings": 1}\n' > "$P/soft-knowledge/evolve/2026-11-09.findings.json"
"$E" coverage --scope soft --no-record > /dev/null; check "$?" 1 "  nor when its findings are no list"
rm -f "$P/soft-knowledge/evolve/2026-11-09.findings.json"
settle; sleep 1; printf '{"time": "%s"}\n' "$(now 30)" >> "$L/ops-verdicts.jsonl"
check "$(q)" "(False, [], ['ops-verdicts'])" "a record stamped ahead of the clock: a change once"
settle; check "$(q --no-record)" "(True, [], [])" "  then seen, never a wake every night until its date"
printf '{"sources": [{"id": "x-todo", "lens": "product", "kind": "path", "at": "{repo}/TODO.md", "need": null, "reader": "evolve"}]}\n' > "$C/aurora/scopes/soft.json"
check "$("$E" coverage --json --scope soft --no-record | j 'cell("soft", "x-todo")["state"]')" "observed" "a source whose need is null reads as any (one member has it), never as all"
rm -f "$C/aurora/scopes/soft.json"
printf '{"ignore": 5}\n' > "$C/aurora/surface.json"; "$E" coverage --no-record > /dev/null; check "$?" 1 "an ignore list of the wrong shape: read past, never a crash"; rm -f "$C/aurora/surface.json"
"$E" coverage --scope soft --open > /dev/null; sleep 1
printf '{"time": "%s"}\n' "$(now)" >> "$L/ops-verdicts.jsonl"
"$E" coverage > /dev/null; "$E" coverage --scope soft > /dev/null   # other runs, recorded, while the pass runs
"$E" coverage --scope soft --promote > /dev/null
check "$(q --no-record)" "(False, [], ['ops-verdicts'])" "--promote takes the opening run's manifest, whatever runs came between: the verdict is still a change"
settle; sleep 1
printf '{"time": "%s"}\n' "$(now -0.01)" >> "$L/ops-verdicts.jsonl"
check "$(q --no-record)" "(False, [], ['ops-verdicts'])" "a record stamped before the cutoff and written after it: still a change (its write)"
settle
settle; sleep 1
mkdir -p "$CP/$(python3 -c 'import re, sys; print(re.sub(r"[^A-Za-z0-9]", "-", sys.argv[1]))' "$P/soft-app")"
printf '{}\n' > "$CP/$(python3 -c 'import re, sys; print(re.sub(r"[^A-Za-z0-9]", "-", sys.argv[1]))' "$P/soft-app")/new.jsonl"
check "$(q --no-record)" "(False, [], ['sessions'])" "a session of the scope since the baseline (its transcript stat'ed, never opened): not quiet"
settle
cp "$C/repos.json" "$T/repos.before"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["scopes"]["soft"]["repos"].append("orphan"); json.dump(d, open(sys.argv[1], "w"))' "$C/repos.json"
check "$(q --no-record)" "(False, ['registry', 'git'], [])" "the scope's registry entry changed (a member added, its refs with it): not quiet"
cp "$T/repos.before" "$C/repos.json"
"$E" coverage --scope soft --since last-week > /dev/null 2>&1; check "$?" 2 "an unreadable --since: exit 2, never a silent pass"
"$E" coverage --scope soft --since 2026-11-01 --no-record > /dev/null 2>&1; check "$?" 2 "  a bare date: exit 2 (the manifest's schema reads a time, and --promote would refuse what --open wrote)"
# a baseline with no heads to compare: git counts as changed, never as not judged
settle
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d.pop("refs", None); json.dump(d, open(sys.argv[1], "w"))' "$EVOLVE_STATE/manifests/soft.complete.json"
check "$(q --no-record | cut -c1-6)" "(False" "a baseline with no heads: not quiet (git is a change, never unjudged)"
settle
# a log written only when something happens: old is not stale, so a quiet week stays quiet
touch -t 202610010000 "$L/fence.log"
check "$(q --no-record) $("$E" coverage --json --scope soft --no-record | j 'cell("soft", "fence-log")["state"]')" "(True, [], []) observed" "  the fence log a month old: still observed, still quiet (it is written only on a denial)"
"$E" coverage --promote > /dev/null 2>&1; check "$?" 2 "--promote without --scope: exit 2"
"$E" coverage --scope soft --session s1 --no-record > /dev/null 2>&1; check "$?" 2 "  --session without --open or --promote (it would be lost): exit 2"
"$E" coverage --scope soft --promote --no-record > /dev/null 2>&1; check "$?" 2 "  --promote with --no-record (it writes the baseline): exit 2"
"$E" coverage --scope soft --open --no-record > /dev/null 2>&1; check "$?" 2 "  --open unrecorded: exit 2"
cp "$C/repos.json" "$T/repos.before"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["repos"]["soft-app-x"] = {}; d["scopes"]["vault"]["repos"].append("soft-app-x"); d["scopes"]["odd"] = ["film-notes"]; d["scopes"]["odd2"] = {"repos": 5}; json.dump(d, open(sys.argv[1], "w"))' "$C/repos.json"
settle; sleep 1; SX="$CP/$(python3 -c 'import re, sys; print(re.sub(r"[^A-Za-z0-9]", "-", sys.argv[1]))' "$P/soft-app-x")"; mkdir -p "$SX"; printf '{}\n' > "$SX/s.jsonl"
check "$(q --no-record)" "(True, [], [])" "a confidential repo whose name starts with a member's: its sessions are not the member's (never stat'ed for it)"
rm -rf "$SX"
"$E" coverage --scope odd --no-record > /dev/null 2>&1; check "$?" 2 "a scope entry that is no object: --scope refuses it, exit 2"
check "$("$E" coverage --json --no-record | j 'd["bad_scopes"]')" "2" "  a full run counts it and one whose repos is no list, a blind spot each, never a crash"
"$E" coverage --scope odd2 --no-record > /dev/null 2>&1; check "$?" 2 "  --scope on one whose repos is no list: exit 2"
"$E" conformance --no-record > /dev/null 2>&1; check "$?" 1 "  conformance skips them, never a crash"
cp "$T/repos.before" "$C/repos.json"
rm -f "$EVOLVE_STATE/manifests/film.opening.json"
mkrepo secret-k; mkdir -p "$P/secret-k/.claude"; printf 'Run `dispatch` here.\n' > "$P/secret-k/.claude/scope-pass.md"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["repos"]["secret-k"] = {}; d["scopes"]["conf2"] = {"repos": ["secret-k"], "confidential": True}; d["scopes"]["umb"] = {"repos": ["secret-k", "soft-knowledge"]}; json.dump(d, open(sys.argv[1], "w"))' "$C/repos.json"
check "$("$E" coverage --json --scope umb --no-record | j 'cell("umb", "dispatch")["state"]')" "unread" "an open scope whose anchor is a confidential repo: that repo's scope-pass.md is never read for it"
check "$("$E" coverage --json --scope conf2 --no-record | j 'cell(d["scopes"][0]["scope"], "dispatch")["state"]')" "observed" "  the confidential scope's own run reads it"
"$E" coverage --scope conf2 --open > /dev/null
check "$(cat "$EVOLVE_STATE"/manifests/confidential-*.json | grep -c 'secret-k')" "0" "  its manifest files, its repo on this host, name no repo: heads under hashed keys"
cp "$T/repos.before" "$C/repos.json"
"$E" coverage --scope film --promote > /dev/null 2>&1; check "$?" 2 "  --promote with no opening run's manifest: exit 2"
printf '{"lenses": [{"id": "a", "sources": [{"id": "x", "kind": "verb", "name": "week-digest", "reader": "evolve"}]}]}\n' > "$T/one-lens.json"
EVOLVE_LENSES="$T/one-lens.json" "$E" coverage --scope soft --no-record > /dev/null; rc1=$?
printf '{"sources": [' > "$C/aurora/scopes/soft.json"
EVOLVE_LENSES="$T/one-lens.json" "$E" coverage --scope soft --no-record > "$T/torn.txt"; rc2=$?
rm -f "$C/aurora/scopes/soft.json"
check "$rc1 $rc2 $(grep -c 'profile        unreadable' "$T/torn.txt")" "0 1 1" "every cell seen: exit 0; the same with the profile torn is a blind spot: exit 1"
settle house; sleep 1; printf '{"time": "%s"}\n' "$(now)" >> "$L/house/misfires.jsonl"
check "$("$E" coverage --json --scope house --no-record | j 'scope("house")["manifest"]["changed_sources"]')" "['misfires']" "a household misfire (a log its own profile declares) wakes the household"
check "$("$E" coverage --json --scope house --no-record | j 'scope("house")["manifest"]["quiet_ok"], scope("house")["manifest"]["overdue"]')" "(False, ['principles'])" "an exclusion past its review: never quiet"
check "$("$E" coverage --json --scope house --no-record | j '[c["sources"] for c in scope("house")["manifest"]["collectors"] if c["id"] == "health"][0]')" "['fence-log', 'deploy-log']" "  a profile source joins the collector it names"
rm -f "$L/ops-verdicts.jsonl"
check "$("$E" coverage --json --scope soft --no-record | j 'scope("soft")["manifest"]["quiet_ok"], scope("soft")["manifest"]["why"][0]')" \
  "(False, 'collector ops: ops-verdicts source_missing')" "a required collector without its source: not quiet, named"
printf '{"time": "%s"}\n' "$(now)" > "$L/ops-verdicts.jsonl"
cp "$C/aurora/scopes/film.json" "$T/film.good"; printf '{"sources": [' > "$C/aurora/scopes/film.json"
check "$("$E" coverage --json --scope film --no-record | j 'scope("film")["manifest"]["quiet_ok"], "the profile cannot be read (JSONDecodeError)" in scope("film")["manifest"]["why"]')" \
  "(False, True)" "a torn profile: never quiet"
cp "$T/film.good" "$C/aurora/scopes/film.json"
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$L/fence.log"
  check "$("$E" coverage --json --scope soft --no-record | j 'cell("soft", "fence-log")["state"]')" "inaccessible" "a file present and unreadable here: inaccessible"
  chmod 644 "$L/fence.log"
else
  echo "  note: running as root, so an unreadable file cannot be made; the absent-repo case above covers inaccessible"
fi

echo "coverage — the record and the manifests hold their schemas"
n=$(grep -c '' "$EVOLVE_STATE/coverage.jsonl")
check "$("$E" validate coverage "$EVOLVE_STATE/coverage.jsonl" | tail -1)" "coverage: $n records, all hold" "coverage.jsonl: a line a recorded run, each one a valid coverage record"
check "$("$E" validate manifest "$EVOLVE_STATE/manifests/soft.json" --quiet; "$E" validate manifest "$EVOLVE_STATE/manifests/soft.complete.json" --quiet; echo "rc=$?")" "rc=0" "  the manifest and the complete pass's baseline"
check "$(j '[(c["source"], c["required"]) for c in scope("soft")["cells"] if c["source"] in ("fence-log", "probes")]' < "$T/cov1.json")" "[('probes', False), ('fence-log', True)]" "  a cell is required when a required collector reads it"
cp "$C/aurora/scopes/house.json" "$T/house.good"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["sources"][0]["fresh_days"] = "two weeks"; json.dump(d, open(sys.argv[1], "w"))' "$C/aurora/scopes/house.json"
out=$("$E" coverage --json --no-record); rc=$?
check "$rc $(echo "$out" | j 'len(d["scopes"]), "the profile cannot be read (profile source 1: source deploy-log: fresh_days is no number)" in scope("house")["manifest"]["why"]')" \
  "1 (4, True)" "a profile value of the wrong type: that scope's profile error, every scope still judged, never a crash"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["sources"][0]["lens"] = ["reliability"]; d["not_applicable"] = [["x"]]; json.dump(d, open(sys.argv[1], "w"))' "$C/aurora/scopes/house.json"
out=$("$E" coverage --json --no-record); rc=$?
check "$rc $(echo "$out" | j 'len(d["scopes"]), scope("house")["manifest"]["quiet_ok"]')" "1 (4, False)" "  a lens or a not_applicable entry of the wrong shape: the same, never a TypeError"
cp "$T/house.good" "$C/aurora/scopes/house.json"
for typo in 'd["sources"][0]["collector"] = "helth"' 'd["sources"][0]["need"] = "some"'; do
  python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); exec(sys.argv[2]); json.dump(d, open(sys.argv[1], "w"))' "$C/aurora/scopes/house.json" "$typo"
  check "$("$E" coverage --json --scope house --no-record | j 'any("the profile cannot be read" in w for w in scope("house")["manifest"]["why"])')" "True" "  a typo ($typo) is a profile error, never a requirement silently dropped"
  cp "$T/house.good" "$C/aurora/scopes/house.json"
done

echo "coverage — refusals"
cp "$C/repos.json" "$T/repos.good"; head -c 30 "$T/repos.good" > "$C/repos.json"
out=$("$E" coverage 2>&1); rc=$?
check "$rc $(echo "$out" | grep -c 'cannot be read') $(echo "$out" | grep -c '^scope ')" "2 1 0" "a torn registry: exit 2, nothing judged, no scope named"
cp "$T/repos.good" "$C/repos.json"
"$E" coverage --scope nosuch > /dev/null 2>&1; check "$?" 2 "an unknown scope: exit 2"
EVOLVE_LENSES="$T/no-lenses.json" "$E" coverage > /dev/null 2>&1; check "$?" 2 "no lenses.json: exit 2"
printf '{"lenses": [{"id": "a", "sources": [{"id": "x", "kind": "verb", "name": "x"}]}], "collectors": [{"id": "c", "sources": ["y"]}]}\n' > "$T/bad-lenses.json"
check "$(EVOLVE_LENSES="$T/bad-lenses.json" "$E" coverage 2>&1; echo " rc=$?")" "evolve coverage: lenses.json cannot be read (collector 'c' names no declared source ['y'])
 rc=2" "  a collector naming no declared source: exit 2, named"
printf '{"lenses": [{"id": "a", "sources": [{"id": "x", "kind": "path"}, {"kind": "verb"}]}]}\n' > "$T/bad-lenses.json"
check "$(EVOLVE_LENSES="$T/bad-lenses.json" "$E" coverage 2>&1; echo " rc=$?")" "evolve coverage: lenses.json cannot be read (lens a: source x: its \`at\` starts with none of {log}, {config}, {anchor}, {repo})
 rc=2" "  a path source with no root (it would be judged against the cwd): exit 2"
printf '{"lenses": [{"id": "a", "sources": [{"kind": "verb", "name": "x"}]}]}\n' > "$T/bad-lenses.json"
check "$(EVOLVE_LENSES="$T/bad-lenses.json" "$E" coverage 2>&1; echo " rc=$?")" "evolve coverage: lenses.json cannot be read (lens a: a source with no id)
 rc=2" "  a source with no id: exit 2, named, never a crash"

echo "conformance — rules against the transcripts' tool calls"
cat > "$C/aurora/conformance.json" <<'J'
{"rules": [
  {"id": "no-bare-stash", "ref": "rules/git.md", "when": "git stash", "breach": "git stash( pop)?\\s*$"},
  {"id": "no-amend", "when": "git commit", "breach": "--amend"},
  {"id": "sed-portable", "when": "sed -i", "breach": "sed -i ''"},
  {"id": "never-touched", "when": "rm -rf /nowhere"},
  {"id": "push-names-ref", "when": "git push", "breach": "git push\\s*$"},
  {"id": "never-measured", "breach": "never-ran-x"}]}
J
cat > "$T/tx.py" <<'PY'
import json, sys, datetime as d
out, sess, days = sys.argv[1], sys.argv[2], float(sys.argv[3])
calls = sys.argv[4:]
t = (d.datetime.now(d.timezone.utc) + d.timedelta(days=days)).isoformat()
with open(out, "a") as fh:
    for i, c in enumerate(calls):
        cmd, _, res = c.partition("=>")
        uid = "%s-%s-%d-%s" % (out.rsplit("/", 1)[-1], sess, i, abs(hash(c)))
        fh.write(json.dumps({"type": "assistant", "sessionId": sess, "timestamp": t,
                             "message": {"content": [{"type": "tool_use", "id": uid, "name": "Bash", "input": {"command": cmd}}]}}) + "\n")
        err = res in ("fail", "deny", "perm", "perm2", "auto", "noverdict")
        # the guards' own shapes, as transcripts hold them; "okhook" succeeded though its output talks of a denial
        body = {"deny": "PreToolUse:Bash hook error: \u26d4 An agent may stash only by its tag",
                "perm": "Permission to use Bash with command git stash pop\nand a second line has been denied.",
                "perm2": "Permission for this command was denied by a built-in Claude Code safety check, not by the user.",
                "auto": "Permission for this action was denied by the Claude Code auto mode classifier. Reason: x",
                "noverdict": "The server-side auto mode classifier gave no verdict (error)",
                "okhook": "grep: the hook denied it earlier", "fail": "boom"}.get(res, "ok")
        if res == "none":
            continue   # a call with no result: the session was killed mid-call
        fh.write(json.dumps({"type": "user", "sessionId": sess, "timestamp": t,
                             "message": {"content": [{"type": "tool_result", "tool_use_id": uid, "is_error": err, "content": body}]}}) + "\n")
PY
tx() { python3 "$T/tx.py" "$@"; }
slug() { python3 -c 'import re, sys; print(re.sub(r"[^A-Za-z0-9]", "-", sys.argv[1]))' "$1"; }
S1="$CP/$(slug "$P/soft-app")"; S2="$CP/$(slug "$P/soft-knowledge")"
V="$CP/$(slug "$P/vault-knowledge")"; H="$CP/$(slug "$P/house-ops")"
mkdir -p "$S1/a/subagents" "$S2" "$V" "$H"
tx "$S1/a.jsonl" a 0 "git stash push -m x=>ok" "git stash=>deny" "git stash pop=>perm" "git stash=>perm2" "git stash=>auto" "never-ran-x=>noverdict" "never-ran-x=>none" "git commit --amend -m y=>ok" "git commit --amend -m z=>okhook" "sed -i '' s/a/b/ f=>ok" "git push -u origin claude/x=>ok"
cp "$S1/a.jsonl" "$S1/a-resumed.jsonl"   # a resumed session's file carries the same calls, the same ids
grep '"type": "assistant"' "$S1/a.jsonl" > "$S1/0-fork.jsonl"   # a fork that sorts first and holds the calls, not their results
tx "$S2/b.jsonl" b 0 "never-ran-x=>noverdict"
mkdir -p "$T/h/acct-two"; ln -s "$CP" "$T/h/acct-two/projects"   # a second login dir that links the same projects folder
printf '{"accounts": [{"label": "acct-two", "home": "%s"}]}\n' "$T/h/acct-two" > "$T/accounts.json"; export ACCOUNTS_FILE="$T/accounts.json"
tx "$S1/a/subagents/agent-1.jsonl" a 0 "sed -i '' s/c/d/ f=>ok"   # a worker's call: its session's subagent transcript
tx "$S2/b.jsonl" b 0 "sed -i '' s/e/f/ g=>ok" "sed -i.bak s/e/f/ g=>ok" "echo deploy-house=>ok"
tx "$S2/b.jsonl" b -30 "rm -rf /nowhere=>ok"
tx "$V/c.jsonl" c 0 "git push=>ok" "never-said=>ok"
out=$("$E" conformance --json); rc=$?
echo "$out" > "$T/conf.json"
cat > "$T/rule.py" <<'PY'
import json, sys
d = json.load(sys.stdin)
r = {x["rule"]: x for x in d["rules"]}
print(eval(sys.argv[1]))
PY
rule() { python3 "$T/rule.py" "$1"; }
check "$rc $(echo "$out" | rule 'd["transcripts"], d["fenced"]')" "1 (8, 1)" "the confidential scope's transcript fenced before any open; eight read (a subagent's, a resumed copy, a fork, the coverage cases'), each once though two login dirs link them: exit 1"
check "$(echo "$out" | rule 'r["no-bare-stash"]["class"], r["no-bare-stash"]["blocked"], r["no-bare-stash"]["unknown"], r["no-bare-stash"]["applied"]')" "('holds', 4, 0, 5)" "breaches a hook, the permission system (a multi-line command), a safety check and the classifier refused: holds"
check "$(echo "$out" | rule 'r["no-amend"]["class"], r["no-amend"]["breached_ok"], r["no-amend"]["blocked"]')" "('violated', 2, 0)" "breaches that succeeded (one whose output talks of a denial): violated, never blocked; a resumed file's copies counted once, a fork's resultless copy never over the outcome"
check "$(echo "$out" | rule 'r["never-measured"]["class"], r["never-measured"]["unknown"]')" "('unknown', 3)" "breaches with no verdict or no result at all: unknown, neither ok nor failed, and the rule unknown, never holds"
check "$(echo "$out" | rule 'r["sed-portable"]["class"], r["sed-portable"]["breached_ok"], r["sed-portable"]["sessions"]')" "('worked_around', 3, 2)" "three successful breaches in two sessions: a workaround that keeps succeeding"
check "$(echo "$out" | rule 'r["never-touched"]["class"]')" "dead" "a rule whose only use is outside the window: dead"
check "$(echo "$out" | rule 'r["push-names-ref"]["class"], r["push-names-ref"]["breached_ok"]')" "('holds', 0)" "  the confidential transcript's bare push counted nowhere"
check "$(echo "$out" | rule 'r["house/h-deploy"]["class"]')" "dead" "a scope's profile rule reads that scope's transcripts only"
check "$(echo "$out" | rule 'd["skipped_confidential"], [k for k in r if k.startswith("confidential")]')" "(1, [])" "a confidential scope's rules: not judged where its transcripts are fenced (never a false dead)"
out=$("$E" conformance --json --no-record --scope vault); echo "$out" > "$T/conf-vault.json"
check "$(echo "$out" | rule 'd["transcripts"], d["fenced"], r["'"$MARK"'/rule-1"]["class"], r["'"$MARK"'/rule-1"]["ref"]')" "(1, 0, 'holds', None)" "  judged inside it (--scope): a neutral id, no ref"
check "$(grep -c -i 'vault\|secretclient' "$T/conf.json" "$T/conf-vault.json" "$EVOLVE_STATE/conformance.jsonl" | tr '\n' ' ')" "$T/conf.json:0 $T/conf-vault.json:0 $EVOLVE_STATE/conformance.jsonl:0 " "  neither its name nor its words anywhere"
check "$(grep -c 'git stash\|sed -i' "$EVOLVE_STATE/conformance.jsonl")" 0 "the record holds ids and counts, never a command's text"
cat > "$T/rows.py" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    for r in json.loads(line)["rules"]:
        print(json.dumps(r))
PY
python3 "$T/rows.py" "$EVOLVE_STATE/conformance.jsonl" > "$T/rows.jsonl"
check "$("$E" validate conformance "$T/rows.jsonl" | tail -1)" "conformance: 7 records, all hold" "  each row a valid conformance row"
SX="$CP/$(python3 -c 'import re, sys; print(re.sub(r"[^A-Za-z0-9]", "-", sys.argv[1]))' "$P/soft-app-x")"; mkdir -p "$SX"
tx "$SX/z.jsonl" z 0 "git commit --amend -m q=>ok"   # a sibling repo whose name starts with a member's
out=$("$E" conformance --json --no-record --scope soft); rm -rf "$SX"
check "$(echo "$out" | rule 'r["no-amend"]["breached_ok"]')" "2" "--scope soft: a sibling repo sharing a member's prefix is not the scope's (its calls never counted for it)"
check "$(echo "$out" | rule 'd["transcripts"], d["fenced"], sorted(r)')" \
  "(8, 1, ['never-measured', 'never-touched', 'no-amend', 'no-bare-stash', 'push-names-ref', 'sed-portable'])" "--scope soft: its eight transcripts, the global rules only"
cp "$C/aurora/scopes/vault.json" "$T/vault.good"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["conformance"][0]["when"] = "("; json.dump(d, open(sys.argv[1], "w"))' "$C/aurora/scopes/vault.json"
"$E" conformance --no-record --scope vault > /dev/null 2> "$T/err"; rc=$?
check "$rc $(grep -c 'rule 1: a pattern does not compile' "$T/err") $(grep -c -i 'secretclient' "$T/err")" "2 1 0" "  its bad rule named by its place, never its id: exit 2"
cp "$T/vault.good" "$C/aurora/scopes/vault.json"
printf '{"sources": [' > "$C/aurora/scopes/film.json"
out=$("$E" conformance --json --no-record); rc=$?
check "$rc $(echo "$out" | rule 'd["unreadable_profiles"], len(r)')" "1 (1, 7)" "another scope's torn profile: counted, every other rule still judged"
"$E" conformance --no-record --scope film > /dev/null 2>&1; check "$?" 2 "  asked for by name: exit 2"
cp "$T/film.good" "$C/aurora/scopes/film.json"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["conformance"] = [{"id": "f1", "when": "(", "breach": "x"}]; json.dump(d, open(sys.argv[1], "w"))' "$C/aurora/scopes/film.json"
out=$("$E" conformance --json --no-record); rc=$?
check "$rc $(echo "$out" | rule 'd["unreadable_profiles"], len(r)')" "1 (1, 7)" "  another scope's rule that does not compile: counted as its unreadable profile, every other rule still judged"
cp "$T/film.good" "$C/aurora/scopes/film.json"
printf '{"rules": [' > "$C/aurora/conformance.json"
"$E" conformance --no-record > /dev/null 2>&1; check "$?" 2 "a torn rule file: exit 2"
printf '{"rules": [{"id": "x", "when": "("}]}\n' > "$C/aurora/conformance.json"
check "$("$E" conformance --no-record 2>&1 | grep -c 'does not compile'; echo "rc=${PIPESTATUS[0]}")" "1
rc=2" "  a pattern that does not compile: exit 2, named"
rm -f "$C/aurora/conformance.json" "$C"/aurora/scopes/*.json
check "$("$E" conformance --no-record | tail -1; echo "rc=${PIPESTATUS[0]}")" "conformance: no rules declared
rc=1" "no rules anywhere: said, exit 1 (unmeasured is never healthy)"

echo "schemas — the finding, its lifecycle, action_id"
cat > "$T/finding.py" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import evolve_schema as s
f = {"id": "soft-probes-links", "theme_id": None, "scope": "soft", "cycle": "2026-W45", "date": "2026-11-08",
     "need": "course links that open nothing", "process_revision": "evolve-scope@1",
     "kind": "gap", "level": "UX", "lens": "product", "goal_ref": None,
     "evidence_refs": [{"source": "probes", "count": 4}], "source_freshness": {"probes": 0.5},
     "observation": "4 of 6 links opened nothing", "hypothesis": "unknown", "counterevidence": None, "p_success": 0.6,
     "intervention": "a link stage", "alternatives": ["none"], "smallest_test": "one doc", "acceptance_check": "evolve probes exit 0",
     "benefit_check": {"check": "asks on links fall", "due": "2026-12-06"}, "observation_window": 28, "outcome_class": "code",
     "reversible": True, "auto_constructible": True, "auto_activatable": False, "size": "s", "est_list_usd": 4.0,
     "owner_minutes": 2, "maintenance_cost": None, "proposed_route": "build", "privacy_class": "open", "cooldown": 14,
     "prior_ids": [], "supersedes": None, "found_by": "pass", "also_found_by": ["challenger.codex"],
     "status": {"proposal": "proposed", "execution": None, "outcome": None}, "action_version": 1, "target_scope": "soft"}
f["action_id"] = s.action_id(f["id"], 1, "soft")
json.dump(f, open(sys.argv[2] + "/good.json", "w"))
bad = dict(f, action_id="0" * 16, kind="strength", status={"proposal": "proposed", "execution": None, "outcome": "benefit_observed"},
           also_found_by=["pass"], outcome_class="vibes")
del bad["level"], bad["cooldown"]
json.dump(bad, open(sys.argv[2] + "/bad.json", "w"))
json.dump(dict(f, id="soft-w45-links", action_id=s.action_id("soft-w45-links", 1, "soft")), open(sys.argv[2] + "/cyc.json", "w"))
json.dump(dict(f, id="2026-11-08-links", action_id=s.action_id("2026-11-08-links", 1, "soft")), open(sys.argv[2] + "/dated.json", "w"))
json.dump(dict(f, id="build-w64-installer-20251231", action_id=s.action_id("build-w64-installer-20251231", 1, "soft")), open(sys.argv[2] + "/w64.json", "w"))
open(sys.argv[2] + "/nan.json", "w").write(json.dumps(dict(f, p_success=float("nan"), est_list_usd=float("inf"))))
json.dump({"version": 1, "scope": "soft", "cycle": "2026-W45", "cutoff": "2026-11-08T21:00:00+00:00", "findings": [f] * 6},
          open(sys.argv[2] + "/six.json", "w"))
PY
python3 "$T/finding.py" "$D/lib" "$T"
check "$("$E" validate finding "$T/good.json"; echo "rc=$?")" "finding: 1 record, all hold
rc=0" "a whole finding holds"
"$E" validate finding "$T/bad.json" > "$T/bad.txt"; rc=$?
check "$rc $(grep -c '' "$T/bad.txt")" "1 8" "a finding with six faults: exit 1, a line each and the summary"
for w in "level: missing" "action_id: not hash" "capitalize_as: a strength" "wake_when | cooldown" "status.outcome: 'benefit_observed' before anything shipped" \
         "also_found_by: holds found_by" "outcome_class: 'vibes' is no class"; do
  check "$(grep -c -F "$w" "$T/bad.txt")" 1 "  names: $w"
done
check "$("$E" validate findings "$T/six.json" | grep -c 'findings: length 6 above 5')" 1 "a pass proposes at most five findings"
check "$("$E" validate finding "$T/cyc.json" | grep -c '^id: holds a cycle')" 1 "a finding id that names its cycle: refused (next week's retry would be a new action)"
check "$("$E" validate finding "$T/dated.json" | grep -c '^id: holds a cycle')" 1 "  or its date"
check "$("$E" validate finding "$T/w64.json" --quiet; echo "rc=$?")" "rc=0" "  another week's number or a build's 8 digits is no cycle"
check "$("$E" validate finding "$T/nan.json" | grep -c 'is no num')" 2 "a NaN or an infinite number is no number"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d.update(also_found_by=5, outcome_class=["code"], est_list_usd=10 ** 400); json.dump(d, open(sys.argv[2], "w"))' "$T/good.json" "$T/odd.json"
"$E" validate finding "$T/odd.json" > "$T/odd.txt"; rc=$?
check "$rc $(grep -c 'also_found_by: 5 is no list\|outcome_class: .list. is no str\|est_list_usd: .* is no num' "$T/odd.txt")" "1 3" "fields of the wrong type: refused and named (exit 1), never a crash (exit 2)"
check "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import evolve_schema as s; print(s.read_time("2026-11-01T10:00:00+0100").utcoffset(), s._is_time("2026-11-01"), s._is_time("20261101T1000"))' "$D/lib")" \
  "1:00:00 False False" "a time read the same on every Python: a +HHMM offset read, a bare or compact date no time"
EVOLVE_LENSES="$T/no-lenses.json" "$E" validate finding "$T/good.json" > /dev/null 2>&1; check "$?" 2 "  no lenses.json to judge its outcome class by: exit 2, never a pass"
python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); d["acceptance_check"] = ""; d["lens"] = "nonsense"; json.dump(d, open(sys.argv[2], "w"))' "$T/good.json" "$T/empty.json"
"$E" validate finding "$T/empty.json" > "$T/empty.txt"; rc=$?
check "$rc $(grep -c '^acceptance_check: length 0 below 1' "$T/empty.txt") $(grep -c "^lens: 'nonsense' is no lens lenses.json declares" "$T/empty.txt")" "1 1 1" "an empty acceptance check and a lens lenses.json never declared: refused"
a1=$("$E" action-id soft-probes-links 1 soft); a2=$("$E" action-id soft-probes-links 2 soft); a3=$("$E" action-id soft-probes-links 1 film)
want=$(python3 -c 'import hashlib, json; print(hashlib.sha256(json.dumps(["soft-probes-links", 1, "soft"], separators=(",", ":")).encode()).hexdigest()[:16])')
check "$a1 $([ "$a1" != "$a2" ] && [ "$a1" != "$a3" ] && echo distinct)" "$want distinct" "action_id = hash(finding id, action version, target scope), no cycle: a revision or another scope is a new action"

echo "schemas — the receipt and the ledgers"
printf '{"receipt": "complete", "scope": "soft", "day": "2026-11-08", "cycle": "2026-W45", "records_ref": "claude/x/2026-11-08-scope-pass", "sha256": "%s", "judge_rev": null, "time": "2026-11-08T21:00:00+00:00"}\n' "$(printf x | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')" > "$T/rc.json"
check "$("$E" validate receipt "$T/rc.json" --quiet; echo "rc=$?")" "rc=0" "a receipt as scope-pass writes it holds"
sed 's/21:00:00+00:00/21:00:00.5Z/' "$T/rc.json" > "$T/rc-frac.json"
check "$("$E" validate receipt "$T/rc-frac.json" --quiet; echo "rc=$?")" "rc=0" "  a time with a one-digit fraction holds on every Python (3.9 reads 3 or 6 digits alone)"
printf '{"receipt": "done", "scope": "soft", "cycle": "2026-45"}\n' > "$T/rc-bad.json"
check "$("$E" validate receipt "$T/rc-bad.json" --quiet | tr '\n' '|')" "receipt: 'done' is not one of complete | quiet | held | failed | not_due|cycle: '2026-45' does not read as \d{4}-W\d{2}|" "  a receipt word outside the five, a cycle that is no ISO week"
printf '{"id": "a1", "date": "2026-11-01", "ts": "2026-11-01T10:00:00Z", "week": "2026-W44", "project": "soft-app", "session": "abcd1234", "sieve": "ask", "target": "system", "match": {"label": "anticipated", "finding": "soft-probes-links", "lead_days": 3}}\n{"id": "a2", "date": "2026-11-01", "ts": "2026-11-01T10:00:00Z", "week": "2026-W44", "project": null, "session": "abcd1234", "sieve": "ask", "match": {"label": "M9"}}\n' > "$T/asks.jsonl"
check "$("$E" validate ask "$T/asks.jsonl" | tr '\n' '|')" "line 2: match.label: 'M9' is not one of anticipated | M1 | M2 | M3 | M4 | M5 | M6 | M7 | J | unknown|ask: 2 records, 1 refused|" "the asks ledger as plumb's matcher writes it: a cause outside M1–M7 and J refused"
printf '{"t1": {"level": "UX", "kind": "bug", "sessions": {"s": "2026-11-01"}, "first": {"session": "s", "date": "2026-11-01"}, "shipped": null}}\n' > "$T/themes.json"
check "$("$E" validate theme "$T/themes.json" --quiet; echo "rc=$?")" "rc=0" "  the themes file: one theme a key"
printf '{"action_id": "%s", "cycle": "2026-W45", "provider": "codex", "arm": "challenger.codex", "forecast_usd": 2.5, "actual_usd": null, "at": "2026-11-09T09:00:00+00:00", "state": "held"}\n' "$a1" > "$T/res.jsonl"
check "$("$E" validate reservation "$T/res.jsonl" --quiet; echo "rc=$?")" "rc=0" "  a reservation row keyed by action_id"
"$E" validate nosuch "$T/res.jsonl" > /dev/null 2>&1; check "$?" 2 "an unknown schema: exit 2"
check "$("$E" schema | tr '\n' ' ')" "ask cell conformance coverage finding findings manifest overrule receipt reservation start theme " "evolve schema lists every schema"

echo; [ "$fails" -eq 0 ] && echo "evolve-schemas: all ok" || { echo "evolve-schemas: $fails failed"; exit 1; }
