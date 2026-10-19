#!/usr/bin/env bash
# crew-report's suite: synthetic transcripts under a scratch HOME and config dir, every name made
# up. The design's fixtures 1 (only typed prompts count; launchers dropped), 2 (one session in two
# login dirs and the archive counts once), 3 (two notes, one save minute, two audio files: both
# count), 4 (a scratch repo: docs added under the default excludes and with none), 5 (no config, no
# usage-report: prompts-only rows and the "not found" line), 6 (a gap across Sunday midnight splits
# into two weeks) and 7 (an HTML doc with Chrome missing: read statically); plus a recording that
# overlaps a prompt run (counted once), the size fallback and the unresolved count; then, for
# measured reading, 8 (heartbeats join at 5 min: two runs, 5 min), 9 (two tabs, two docs: one
# minute), 10 (another viewer: never charged), 11 (a repo outside projects_root: a "?" row), 12
# (reading inside a prompt run: 25 min, not 30), and the drain's lines.
#   bash modules/plumb/tests/crew-report.sh
set -u
D="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" REGATTA_CONFIG="$T/config" TZ=UTC ACCOUNTS_FILE="$T/accounts.json"
unset CLAUDE_CONFIG_DIR CREW_REPORT_CONFIG REGATTA_LEGACY REGATTA_HOME
# `week` asks keel to drain first: never in a test unless the case is about the drain. Peer tools
# are pinned per case (a stub, or "none"), never found: a module moving into the checkout would
# otherwise swap a stub for the real tool.
export CREW_REPORT_NO_DRAIN=1 CREW_REPORT_KEEL=none CREW_REPORT_PUBLISH=none CREW_REPORT_USAGE_REPORT=none
mkdir -p "$HOME/.claude/projects/-alpha" "$HOME/.claude-b/projects/-alpha" "$HOME/projects/alpha/.git" \
         "$HOME/projects/alpha/docs" "$HOME/projects/beta/.git" "$HOME/projects/transcripts/alpha" "$REGATTA_CONFIG"
printf '{"accounts": [{"label": "one", "provider": "claude", "home": "~/.claude", "primary": true},
 {"label": "two", "provider": "claude", "home": "~/.claude-b"}]}\n' > "$ACCOUNTS_FILE"

python3 - "$HOME" <<'PY'
import json, sys
home = sys.argv[1]
A, B = home + "/projects/alpha", home + "/projects/beta"
n = [0]
def ev(sid, ts, cwd, content, origin="human", entry="claude-vscode", **kw):
    n[0] += 1
    d = {"type": "user", "uuid": "u%03d" % n[0], "sessionId": sid, "timestamp": ts, "cwd": cwd,
         "entrypoint": entry, "message": {"role": "user", "content": content}}
    if origin:
        d["origin"] = {"kind": origin}
    d.update(kw)
    return d
def write(path, rows):
    with open(path, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
s1 = [
    ev("s1", "2026-03-02T10:00:00Z", A, "hello there"),
    ev("s1", "2026-03-02T10:01:00Z", A, [{"type": "tool_result", "tool_use_id": "t1", "content": "ok"}], origin=None),
    ev("s1", "2026-03-02T10:02:00Z", A, [{"type": "text", "text": "skill body"}], origin=None, isMeta=True),
    ev("s1", "2026-03-02T10:03:00Z", A, "<task-notification>done</task-notification>", origin="task-notification"),
    ev("s1", "2026-03-02T10:04:00Z", A, "a hand-back", origin="peer", isMeta=True),
    ev("s1", "2026-03-02T10:05:00Z", A + "/docs", "<command-message>name</command-message>\n<command-name>/name</command-name>"),
    {"type": "attachment", "uuid": "q1", "sessionId": "s1", "timestamp": "2026-03-02T10:06:00Z", "cwd": A,
     "attachment": {"type": "queued_command", "prompt": "hello there", "origin": {"kind": "human"}}},
    ev("s1", "2026-03-02T10:07:00Z", A, "a relayed message", origin=None, promptSource="sdk"),
    ev("s1", "2026-03-02T10:08:00Z", A, "<command-name>/model</command-name>\n<command-args></command-args>", origin=None),
]
s2 = [
    ev("s2", "2026-03-02T11:00:00Z", A, "You are an unattended session started by dispatch for a branch", entry="cli"),
    ev("s2", "2026-03-02T11:05:00Z", A, "carry on", entry="cli"),
]
s3 = [
    ev("s3", "2026-03-02T12:00:00Z", A, "<command-message>pickup</command-message>\n<command-name>/pickup</command-name>\n<command-args>'claude/x' --fresh</command-args>"),
    ev("s3", "2026-03-02T12:03:00Z", A, "go"),
]
s4 = [
    ev("s4", "2026-03-08T23:50:00Z", B, "late on a Sunday"),
    ev("s4", "2026-03-09T00:10:00Z", B, "early on a Monday"),
]
write(home + "/.claude/projects/-alpha/s1.jsonl", s1)
write(home + "/.claude/projects/-alpha/s2.jsonl", s2)
write(home + "/.claude/projects/-alpha/s3.jsonl", s3)
write(home + "/.claude/projects/-alpha/s4.jsonl", s4)
PY

rc=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; echo "$2" | sed 's/^/     /'; rc=1; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "$2" ;; esac; }
run() { python3 "$D/bin/crew-report" week "$@" 2>&1; }

out=$(run --week 2026-W10)
has "1: typed prompts only — hello, /name, /model, the line after a pickup prefill" "$out" "| alpha | 4 · 8 min |"
has "1: a subfolder's session is its repo's" "$out" "| alpha |"
case "$out" in *"alpha/docs"*) bad "1: no row for a subfolder" "$out" ;; *) ok "1: no row for a subfolder" ;; esac
has "1: the dispatch session and the pickup prefill are machine starts" "$out" "machine starts 3"
has "1: the relay is not counted" "$out" "relays 1"

cp "$HOME/.claude/projects/-alpha/s1.jsonl" "$HOME/.claude-b/projects/-alpha/s1.jsonl"
cp "$HOME/.claude/projects/-alpha/s1.jsonl" "$HOME/projects/transcripts/alpha/2026-03-02-s1.jsonl"
out=$(run --week 2026-W10)
has "2: two copies of one session count once" "$out" "| alpha | 4 · 8 min |"

has "5: no config — defaults, said" "$out" "No config at"
has "5: no usage-report — the not-found line" "$out" "Cost: usage-report not found."

has "6: Sunday's side of a midnight gap" "$out" "| beta | 1 · 10 min |"
out=$(run --week 2026-W11)
has "6: Monday's side, in the next week" "$out" "| beta | 1 · 10 min |"

out=$(run --week 2026-W10 --until 2026-03-02T10:06:00)
has "--until cuts the replay: a prompt after it never existed" "$out" "| alpha | 2 · 5 min |"

mkdir -p "$REGATTA_CONFIG/plumb"
printf '{"machine_prompts": ["^hello there$"], "reports": "%s/reports"}\n' "$T" > "$REGATTA_CONFIG/plumb/crew-report.json"
out=$(run --week 2026-W10 --write)
has "config: a deployment's own launcher pattern drops its prompt" "$(cat "$T/reports/2026-W10.md")" "| alpha | 3 · 3 min |"
[ ! -e "$T/reports/latest.md" ] && ok "--write: a backfill of an old week leaves latest.md alone" || bad "--write: a backfill wrote latest.md" "$out"
out=$(run --write)
lw=$(python3 -c 'import datetime as d; y, w, _ = (d.datetime.now(d.timezone.utc) - d.timedelta(days=7)).isocalendar(); print(f"{y}-W{w:02d}")')
[ -f "$T/reports/latest.md" ] && [ -f "$T/reports/$lw.md" ] && ok "--write: the last complete week writes latest.md beside it" || bad "--write: latest.md for the last complete week" "$out"
out=$(run --week 2026-W10 --until 2026-03-02T10:06:00 --write)
has "--write: a replay's cut never writes" "$out" "--until is a replay"

# ---- recordings: notes with front matter, audio files under a mapped root, a stub for afinfo ----
mkdir -p "$T/notes/sub" "$T/audio"
for f in one two long-sail; do : > "$T/audio/$f.m4a"; done
# The stub answers like afinfo: 60 s, or 300 s for a file named long.
cat > "$T/afinfo" <<'STUB'
#!/bin/sh
case "$1" in *long*) echo "estimated duration: 300.00 sec" ;; *) echo "estimated duration: 60.00 sec" ;; esac
STUB
chmod +x "$T/afinfo"
note() {  # file recorded audio body [size]
  printf -- '---\nsource: voice\nrecorded: %s\naudio: %s\n%sMade-up title\n---\n%s\n' "$2" "$3" "${5:+size: $5
}" "$4" > "$T/notes/$1"
}
note n1.md "2026-03-04 09:30" /aud/one.m4a "A gizmo plan."
note sub/n2.md "2026-03-04 09:30" /aud/two.m4a "The GIZMO again."
note n3.md "2026-03-04 09:30" /aud/one.m4a "A second note of the same gizmo recording."
note n4.md "2026-03-04 09:31" /aud/other.m4a "Nothing about the topic."
note n5.md "2026-03-02 10:10" /aud/long-sail.m4a "A sailing trip."
note n6.md "2026-03-05 08:00" /aud/gone-one.m4a "Zephyr notes, file gone."
note n7.md "2026-03-05 09:00" /aud/gone-two.m4a "More zephyr notes, file gone, size known." "0.48 MB"
cat > "$T/rec.json" <<EOF
{"machine_prompts": ["^hello there\$"], "notes": "$T/notes", "audio_roots": {"/aud": "$T/audio"},
 "projects": {"delta": {"terms": ["gizm[o]"]}, "alpha": {"terms": ["sail(ing)?"]}, "eps": {"terms": ["zephyr"]}}}
EOF
runc() { CREW_REPORT_CONFIG="$1" CREW_REPORT_AFINFO="$T/afinfo" python3 "$D/bin/crew-report" week "${@:2}" 2>&1; }
out=$(runc "$T/rec.json" --week 2026-W10)
has "3: two notes, one save minute, two files: both count (2 min, 2 files)" "$out" "| delta | 0 · 0 min | 2 · 2 min | — | 2 min |"
has "3: the same file in two notes counts once; a note off the terms none" "$out" "delta 2 files"
has "rec: a recording inside a prompt run is counted once (prompts 3, recording 5 over 10:05-10:10, union 5)" "$out" "| alpha | 3 · 3 min | 1 · 5 min | — | 5 min |"
has "rec: no stub answer and no size is 0 min, said" "$out" "1 file unresolved"
has "rec: no stub answer, size 0.48 MB (the notes' own format) at 64 kbit/s is 60 s, said" "$out" "eps 2 files, 1 est. from size"
has "rec: the row holds the size estimate" "$out" "| eps | 0 · 0 min | 2 · 1 min | — | 1 min |"
case "$out" in *gizm*|*zephyr*|*sail*|*one.m4a*|*Made-up*|*n1.md*) bad "rec: no title, term or file name in the report" "$out" ;; *) ok "rec: no title, term or file name in the report" ;; esac
out=$(runc "$T/rec.json" --week 2026-W10 --until 2026-03-04T09:00)
case "$out" in *"delta "*) bad "rec: a replay cut before the save leaves the recordings out" "$out" ;; *) ok "rec: a replay cut before the save leaves the recordings out" ;; esac
printf '{"notes": "%s/none"}\n' "$T" > "$T/norec.json"
out=$(runc "$T/norec.json" --week 2026-W10)
has "rec: a notes folder that is not there is said, not fatal" "$out" "Recordings: the \`notes\` folder is not found"

# ---- estimated reading: a scratch repo, docs added by author date, content at the newest ref ----
G="$HOME/projects/gamma"
mkdir -p "$G/docs" "$G/research/sources"
words() { i=0; while [ "$i" -lt "$1" ]; do printf 'word '; i=$((i + 1)); done; printf '\n'; }
g() { git -C "$G" -c commit.gpgsign=false -c user.name=t -c user.email=crew-test "$@"; }
git -C "$G" init -q -b main
words 10 > "$G/docs/a.md"                      # the add-commit holds an early draft
words 200 > "$G/research/sources/b.md"
words 200 > "$G/TODO.md"
printf '<html><head><title>Made up</title><style>p{}</style></head><body><p>one two three four</p>
<script>var x = "not text";</script><table><tr><td>a b c d</td></tr></table></body></html>\n' > "$G/docs/page.html"
g add -A
GIT_AUTHOR_DATE=2026-03-03T12:00:00+00:00 GIT_COMMITTER_DATE=2026-03-03T12:00:00+00:00 g commit -q -m "add"
# A doc whose author date is the Sunday before the week, committed (rebased) inside it.
words 300 > "$G/docs/rebased.md"
g add -A
GIT_AUTHOR_DATE=2026-03-01T12:00:00+00:00 GIT_COMMITTER_DATE=2026-03-03T13:00:00+00:00 g commit -q -m "rebased"
# The finished text sits on a branch main never saw: 696 prose words and a 4-word link line, a
# 300-word fenced block and a 300-word table row = 700 + 150 + 150 = 1000 words = 5 min.
g checkout -q -b feat
{ words 696
  printf 'see [two words](http://example.invalid/a/very/long/url) <b>now</b> https://example.invalid/bare\n'
  printf '```\n'; words 300; printf '```\n| '; words 300 | tr -d '\n'; printf ' |\n|---|\n'; } > "$G/docs/a.md"
g add -A
GIT_AUTHOR_DATE=2026-03-04T12:00:00+00:00 GIT_COMMITTER_DATE=2026-03-04T12:00:00+00:00 g commit -q -m "finish"
g checkout -q main
cat > "$T/read.json" <<EOF
{"chrome": "$T/no-such-chrome", "projects": {"gamma": {}}}
EOF
out=$(runc "$T/read.json" --week 2026-W10)
has "4: default excludes — one doc plus the page; TODO.md and the sources dir out" "$out" "- gamma — docs added: 2; html: 0 rendered, 1 static"
has "4: the newest ref's text (not the draft), links and fences weighed: 1000 + 6 words = 5 min" "$out" "| gamma | 0 · 0 min | — | — | 0 min | 0 min / 0 min | 5 min |"
has "4: reading is reference only — the total stays the prompts' (10 + 8) and the column holds 5" "$out" "**18 min** | 8 min / 18 min | 5 min |"
python3 - "$D/bin/crew-report" "$G" <<'PY' && ok "4: word weights exact — 1000 words of the finished text, 6 of the page" || bad "4: word weights exact" "see the python error above"
import importlib.machinery as m, importlib.util as u, subprocess, sys
l = m.SourceFileLoader("cr", sys.argv[1]); s = u.spec_from_loader("cr", l); cr = u.module_from_spec(s); l.exec_module(cr)
md = subprocess.run(["git", "-C", sys.argv[2], "show", "feat:docs/a.md"], capture_output=True, text=True).stdout
assert cr.md_words(md) == 1000.0, cr.md_words(md)
html = subprocess.run(["git", "-C", sys.argv[2], "show", "main:docs/page.html"], capture_output=True, text=True).stdout
assert cr.html_words(html) == 6.0, cr.html_words(html)
PY
has "7: Chrome missing — the HTML doc is read statically, said" "$out" "html: 0 rendered, 1 static"
printf '{"exclude": [], "chrome": "%s/no-such-chrome", "projects": {"gamma": {}}}\n' "$T" > "$T/read-none.json"
out=$(runc "$T/read-none.json" --week 2026-W10)
has "4: an empty exclude — four docs, not the one rebased from the week before" "$out" "- gamma — docs added: 4"
has "4: and their words, 1406 = 7 min" "$out" "| 7 min |"
printf '{"exclude": [], "chrome": "%s/no-such-chrome", "projects": {"gamma": {"reading": {"exclude": ["b.md", "docs/page.*", "TODO.md"]}}}}\n' "$T" > "$T/read-pe.json"
out=$(runc "$T/read-pe.json" --week 2026-W10)
has "4: a project's excludes — a bare name anywhere, a path glob" "$out" "- gamma — docs added: 1"
out=$(runc "$T/read.json" --week 2026-W11)
case "$out" in *"- gamma"*) bad "4: nothing added in the next week" "$out" ;; *) ok "4: nothing added in the next week" ;; esac

# ---- G5: the render cache — a doc rendered once is never rendered again ----
cat > "$T/chrome" <<'STUB'
#!/bin/sh
echo run >> "$STUB_CHROME_CALLS"
echo '<html><body><p>one two three four five six</p></body></html>'
STUB
chmod +x "$T/chrome"
export STUB_CHROME_CALLS="$T/chrome.calls"
printf '{"chrome": "%s/chrome", "cache": "%s/cache", "projects": {"gamma": {}}}\n' "$T" "$T" > "$T/cached.json"
: > "$STUB_CHROME_CALLS"
out=$(runc "$T/cached.json" --week 2026-W10)
has "G5: the first pass renders the page" "$out" "html: 1 rendered, 0 static"
[ "$(wc -l < "$STUB_CHROME_CALLS" | tr -d ' ')" = 1 ] && ok "G5: Chrome ran once" || bad "G5: Chrome ran once" "$(cat "$STUB_CHROME_CALLS")"
has "G5: rendered words are the DOM's (1000 of the finished text + 6 of Chrome's, not the page's own)" "$out" "| gamma | 0 · 0 min | — | — | 0 min | 0 min / 0 min | 5 min |"
out=$(runc "$T/cached.json" --week 2026-W10)
[ "$(wc -l < "$STUB_CHROME_CALLS" | tr -d ' ')" = 1 ] && ok "G5: the second pass renders nothing — the cache answers" || bad "G5: the second pass renders nothing" "$(cat "$STUB_CHROME_CALLS")"
has "G5: and still counts the page as rendered" "$out" "html: 1 rendered, 0 static"
case "$(cat "$T"/cache/render-v2.json)" in *one*|*gamma*|*page*|*docs*) bad "G5: the cache holds no text or path" "$(cat "$T"/cache/render-v2.json)" ;; *) ok "G5: the cache holds no text or path" ;; esac
printf '{"chrome": "%s/chrome", "cache": "", "projects": {"gamma": {}}}\n' "$T" > "$T/nocache.json"
out=$(runc "$T/nocache.json" --week 2026-W10)
[ "$(wc -l < "$STUB_CHROME_CALLS" | tr -d ' ')" = 2 ] && ok "G5: \"cache\": \"\" renders again" || bad "G5: cache off renders again" "$(cat "$STUB_CHROME_CALLS")"

# ---- G5: the transcript cache — the same answer, from fewer reads, and no prompt text kept ----
printf '{"cache": "%s/tcache"}\n' "$T" > "$T/tc-on.json"
printf '{"cache": ""}\n' > "$T/tc-off.json"
on1=$(runc "$T/tc-on.json" --week 2026-W10)
on2=$(runc "$T/tc-on.json" --week 2026-W10)
off=$(runc "$T/tc-off.json" --week 2026-W10)
[ "$on1" = "$off" ] && ok "G5: the transcript cache changes nothing in the report (cold)" || bad "G5: cold report differs from the uncached one" "$on1"
[ "$on2" = "$off" ] && ok "G5: the transcript cache changes nothing in the report (warm)" || bad "G5: warm report differs from the uncached one" "$on2"
tf=$(ls "$T"/tcache/transcripts-*.json 2>/dev/null | head -1)
[ -n "$tf" ] && ok "G5: the transcript cache file is written" || bad "G5: the transcript cache file is written" "$(ls "$T/tcache" 2>&1)"
case "$(cat "$tf" 2>/dev/null)" in *"hello there"*|*"late on a Sunday"*|*"a gizmo"*) bad "G5: the cache holds no prompt text" "see $tf" ;; *) ok "G5: the cache holds no prompt text" ;; esac
printf '{"type":"user","uuid":"u900","sessionId":"s4","timestamp":"2026-03-09T00:20:00Z","cwd":"%s/projects/beta","entrypoint":"claude-vscode","origin":{"kind":"human"},"message":{"role":"user","content":"a later line"}}\n' "$HOME" >> "$HOME/.claude/projects/-alpha/s4.jsonl"
out=$(runc "$T/tc-on.json" --week 2026-W11)
has "G5: a file that grew is read again (the cache keys on size and mtime)" "$out" "| beta | 2 · 20 min |"
printf '{"cache": "%s/tcache", "machine_prompts": ["^a later line$"]}\n' "$T" > "$T/tc-pat.json"
out=$(runc "$T/tc-pat.json" --week 2026-W11)
has "G5: a changed launcher pattern is not answered from the old cache" "$out" "| beta | 1 · 10 min |"
[ "$(ls "$T"/tcache/transcripts-*.json | wc -l | tr -d ' ')" = 1 ] && ok "G5: the old pattern's cache file is removed" || bad "G5: the old pattern's cache file is removed" "$(ls "$T/tcache")"

# ---- publish: lighthouse's tool through common.tool(); a stub on the legacy root ----
mkdir -p "$T/legacy/bin"
cat > "$T/legacy/bin/publish" <<'STUB'
#!/usr/bin/env python3
import os, sys
open(os.environ["STUB_PUBLISH_ARGS"], "a").write(" ".join(sys.argv[1:]) + "\n")
print("stub copied")
sys.exit(int(os.environ.get("STUB_PUBLISH_RC", "0")))
STUB
export STUB_PUBLISH_ARGS="$T/publish.args"
pub() {  # scope [env...] — the job's run of W10 (--write --publish) with the stub tool pinned
  printf '{"reports": "%s/pubrep", "publish": "%s"}\n' "$T" "$1" > "$T/pub.json"
  shift
  env CREW_REPORT_PUBLISH="$T/legacy/bin/publish" CREW_REPORT_CONFIG="$T/pub.json" "$@" python3 "$D/bin/crew-report" week --week 2026-W10 --write --publish 2>&1
}
: > "$STUB_PUBLISH_ARGS"
out=$(pub vault)
has "publish: the vault scope and the week file reach the tool" "$(cat "$STUB_PUBLISH_ARGS")" "--vault $T/pubrep/2026-W10.md"
has "publish: the tool's output lands in the job's log" "$out" "  stub copied"
: > "$STUB_PUBLISH_ARGS"
pub data > /dev/null
has "publish: the data scope" "$(cat "$STUB_PUBLISH_ARGS")" "--data $T/pubrep/2026-W10.md"
: > "$STUB_PUBLISH_ARGS"
pub "" > /dev/null
[ ! -s "$STUB_PUBLISH_ARGS" ] && ok "publish: \"\" stays local — the tool is not called" || bad "publish: \"\" stays local" "$(cat "$STUB_PUBLISH_ARGS")"
out=$(pub nas)
has "publish: a scope that is neither vault nor data is said" "$out" "'nas' is not a scope"
[ ! -s "$STUB_PUBLISH_ARGS" ] && ok "publish: and nothing is published" || bad "publish: nothing published for a bad scope" "$(cat "$STUB_PUBLISH_ARGS")"
out=$(pub vault STUB_PUBLISH_RC=1); rc2=$?
has "publish: a failing tool is one logged line, local only" "$out" "publish FAILED (exit 1) — local only"
[ "$rc2" = 0 ] && ok "publish: and the run is not fatal" || bad "publish: a failure is never fatal" "exit $rc2"
[ -s "$T/pubrep/2026-W10.md" ] && ok "publish: the local file stands after a failure" || bad "publish: the local file stands" ""
printf '{"reports": "%s/pubrep2", "publish": "vault"}\n' "$T" > "$T/pub.json"
out=$(env CREW_REPORT_CONFIG="$T/pub.json" python3 "$D/bin/crew-report" week --week 2026-W10 --write --publish 2>&1)
has "publish: tool absent — the report file says local only" "$(cat "$T/pubrep2/2026-W10.md")" "publish: lighthouse not installed — local only"
case "$out" in *FAILED*) bad "publish: an absent tool is not a failure" "$out" ;; *) ok "publish: an absent tool is not a failure" ;; esac
: > "$STUB_PUBLISH_ARGS"
printf '{"reports": "%s/pubrep3", "publish": "vault"}\n' "$T" > "$T/pub.json"
out=$(env CREW_REPORT_PUBLISH="$T/legacy/bin/publish" CREW_REPORT_CONFIG="$T/pub.json" python3 "$D/bin/crew-report" week --week 2026-W10 --write 2>&1)
[ ! -s "$STUB_PUBLISH_ARGS" ] && ok "publish: a hand --write never publishes (one publisher per file: the job)" || bad "publish: a hand --write published" "$(cat "$STUB_PUBLISH_ARGS")"
has "publish: and says so" "$out" "not published — the weekly job publishes (--publish)"

# ---- schedule: a stub launchctl and a scratch LaunchAgents dir; the real ones are never touched ----
cat > "$T/launchctl" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_LAUNCHCTL_LOG"
[ "$1" = print ] && [ -f "$STUB_LAUNCHCTL_LOADED" ] && exit 0
[ "$1" = print ] && exit 113
exit 0
STUB
chmod +x "$T/launchctl"
export STUB_LAUNCHCTL_LOG="$T/launchctl.log" STUB_LAUNCHCTL_LOADED="$T/loaded"
: > "$STUB_LAUNCHCTL_LOG"
inst() { PLUMB_LAUNCH_DIR="$T/la" PLUMB_LAUNCHCTL="$T/launchctl" sh "$D/install.sh" "$@" 2>&1; }
LABEL=dev.regatta.plumb.crew-report
out=$(inst --check)
has "schedule: --check says off before --schedule" "$out" "schedule:     off"
out=$(inst --schedule)
has "schedule: --schedule says what it scheduled" "$out" "scheduled $LABEL"
[ -f "$T/la/$LABEL.plist" ] && ok "schedule: the plist is under the given LaunchAgents dir" || bad "schedule: the plist is written" "$(ls "$T/la" 2>&1)"
[ ! -e "$HOME/Library/LaunchAgents" ] && ok "schedule: the real LaunchAgents dir is not touched" || bad "schedule: real LaunchAgents touched" "$(ls "$HOME/Library/LaunchAgents")"
# The plist names the main checkout's plumb when there is one (a worktree is removed at /finish).
common=$(git -C "$D" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
JOB=$D
[ -n "$common" ] && [ "$(basename "$common")" = .git ] && [ -d "$(dirname "$common")/modules/plumb" ] && JOB="$(dirname "$common")/modules/plumb"
python3 - "$T/la/$LABEL.plist" "$JOB" <<'PY' && ok "schedule: label, ProgramArguments (the main checkout, --publish), Monday 07:30, PATH, log" || bad "schedule: plist content" "see the python error above"
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
assert p["Label"] == "dev.regatta.plumb.crew-report", p["Label"]
a = p["ProgramArguments"]
assert a[1:] == [sys.argv[2] + "/bin/crew-report", "week", "--write", "--publish"], a
assert p["StartCalendarInterval"] == {"Weekday": 1, "Hour": 7, "Minute": 30}, p["StartCalendarInterval"]
path = p["EnvironmentVariables"]["PATH"].split(":")
for d in ("/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"):
    assert d in path, path
assert p["StandardOutPath"].endswith("/crew-report.log"), p["StandardOutPath"]
PY
has "schedule: the plist is bootstrapped into the user's launchd domain" "$(cat "$STUB_LAUNCHCTL_LOG")" "bootstrap gui/$(id -u) $T/la/$LABEL.plist"
out=$(inst --check)
has "schedule: --check sees a plist that is not loaded" "$out" "plist written but not loaded"
touch "$STUB_LAUNCHCTL_LOADED"
out=$(inst --check)
has "schedule: --check says loaded" "$out" "schedule:     loaded ($LABEL, Mondays 07:30)"
has "schedule: --check names the publish tool state" "$out" "publish:"
out=$(inst --remove)
has "schedule: --remove says so" "$out" "removed $LABEL"
[ ! -e "$T/la/$LABEL.plist" ] && ok "schedule: --remove deletes the plist" || bad "schedule: --remove deletes the plist" "$(ls "$T/la")"
has "schedule: and unloads it" "$(cat "$STUB_LAUNCHCTL_LOG")" "bootout gui/$(id -u)/$LABEL"

# ---- measured reading: keel's heartbeat rows (reads.jsonl), joined at 5 min, one union ----
# W12 is 2026-03-16 to 03-22. Times in the rows end in Z (UTC), as the room's events do; the zone
# of this run is UTC too, so a row's minute and the report's minute are the same one.
RA="$HOME/projects/reada"
rd() {  # file repo who doc hh:mm... — one row per time, on Tuesday 2026-03-17
  f=$1; repo=$2; who=$3; doc=$4; shift 4
  for t in "$@"; do
    printf '{"doc":"%s","repo":"%s","branch":"claude/x","path":"%s/%s","ts":"2026-03-17T%s:00Z","who":"%s"}\n' "$doc" "$repo" "$repo" "$doc" "$t" "$who"
  done >> "$f"
}
rcfg() {  # file [viewer] — a config reading that one reads file
  printf '{"reads": ["%s"], "viewer": "%s"}\n' "$1" "${2:-}" > "$1.cfg"
}

# 8: 09:00, 09:01, 09:02, 09:09, 09:10. The 7-minute gap (09:02 to 09:09) is over the 5-minute join,
# so two runs: [08:59, 09:02] = 3 min and [09:08, 09:10] = 2 min, 5 min in all.
: > "$T/r8.jsonl"
rd "$T/r8.jsonl" "$RA" Quinn docs/a.md 09:00 09:01 09:02 09:09 09:10
rcfg "$T/r8.jsonl"
out=$(runc "$T/r8.jsonl.cfg" --week 2026-W12)
has "8: two runs, 3 + 2 = 5 min (the 7-minute gap is a break), in the reading column and the total" "$out" "| reada | 0 · 0 min | — | 5 min | 5 min | 5 min / 5 min | — | — |"
has "8: the header says the reading gap beside the prompt gap" "$out" "total (gap ≤ 20, reading ≤ 5)"
has "8: reading raw, before overlap removal" "$out" "reading raw: 5 min before overlap removal"
has "8: with no viewer set every name is charged and the distinct count is said" "$out" "every name is charged (1 distinct this week)"
has "8: the newest heartbeat's time, in the report's zone" "$out" "newest heartbeat: 2026-03-17 09:10 UTC"
has "8: with no drain this run, a newest row older than 6 h is said" "$out" "No drain this run and the newest heartbeat is"
has "8: what is not measured is said" "$out" "Not measured:"
out=$(runc "$T/r8.jsonl.cfg" --week 2026-W12 --until 2026-03-17T09:02:00)
has "8: a replay cut at 09:02 keeps the first run only (3 min); rows after it did not exist" "$out" "| reada | 0 · 0 min | — | 3 min | 3 min |"
printf '{"reads": ["%s"], "read_gap_minutes": 7}\n' "$T/r8.jsonl" > "$T/r8g.cfg"
out=$(runc "$T/r8g.cfg" --week 2026-W12)
has "8: read_gap_minutes 7 joins the runs: [08:59, 09:10] = 11 min" "$out" "| reada | 0 · 0 min | — | 11 min | 11 min |"
out=$(runc "$T/none.cfg" --week 2026-W12)
has "8: no reads file at all is said, not fatal" "$out" "Measured reading: no reads file found"

# 9: the same minutes from a second tab, and a second doc of the project in the same minutes: still
# one minute each, so still 5. Raw counts per doc and tab-merged runs: 5 + 5.
rd "$T/r8.jsonl" "$RA" Quinn docs/a.md 09:00 09:01 09:02 09:09 09:10
rd "$T/r8.jsonl" "$RA" Quinn docs/b.md 09:00 09:01 09:02 09:09 09:10
out=$(runc "$T/r8.jsonl.cfg" --week 2026-W12)
has "9: two tabs and two docs in the same minutes are still 5 min" "$out" "| reada | 0 · 0 min | — | 5 min | 5 min | 5 min / 5 min | — | — |"
has "9: raw counts each doc's runs: 10 min before overlap removal" "$out" "reading raw: 10 min before overlap removal"

# 10: another viewer's rows (11:00 to 11:10, the same shape: 5 min) are never charged under `viewer`.
: > "$T/r10.jsonl"
rd "$T/r10.jsonl" "$RA" Quinn docs/a.md 09:00 09:01 09:02 09:09 09:10
rd "$T/r10.jsonl" "$RA" Rae docs/a.md 11:00 11:01 11:02 11:09 11:10
rcfg "$T/r10.jsonl" Quinn
out=$(runc "$T/r10.jsonl.cfg" --week 2026-W12)
has "10: under viewer only Quinn's 5 min are charged" "$out" "| reada | 0 · 0 min | — | 5 min | 5 min |"
has "10: the other viewer's minutes are counted, not charged: \"other viewers: 5 min\"" "$out" "other viewers: 5 min, never charged"
case "$out" in *Rae*) bad "10: a viewer's name is never printed" "$out" ;; *) ok "10: a viewer's name is never printed" ;; esac
rcfg "$T/r10.jsonl"
out=$(runc "$T/r10.jsonl.cfg" --week 2026-W12)
has "10: with viewer empty both are charged: 10 min" "$out" "| reada | 0 · 0 min | — | 10 min | 10 min |"
has "10: and the distinct count is printed" "$out" "every name is charged (2 distinct this week)"

# 11: a repo outside projects_root is a "?" row, as a prompt's cwd would be.
: > "$T/r11.jsonl"
rd "$T/r11.jsonl" /elsewhere/outside Quinn docs/a.md 09:00 09:01 09:02 09:09 09:10
rcfg "$T/r11.jsonl"
out=$(runc "$T/r11.jsonl.cfg" --week 2026-W12)
has "11: a repo outside projects_root reads as \"?\"" "$out" "| ? | 0 · 0 min | — | 5 min | 5 min |"
case "$out" in *outside*|*elsewhere*|*a.md*) bad "11: no repo or doc path in the report" "$out" ;; *) ok "11: no repo or doc path in the report" ;; esac

# 12: heartbeats 10:01 .. 10:10 every minute are a run [10:00, 10:10] = 10 min; prompts at 10:05 and
# 10:25 are 20 min at gap 20. Union [10:00, 10:25] = 25 min, not the sum 30. At gap 10 the prompts
# are two points and the total is the reading's 10; at gap 30 it is 25 again.
mkdir -p "$HOME/.claude/projects/-readb"
python3 - "$HOME" <<'PY'
import json, sys
home = sys.argv[1]
rows = [{"type": "user", "uuid": "r12-%d" % i, "sessionId": "s12", "timestamp": ts, "cwd": home + "/projects/readb",
         "entrypoint": "claude-vscode", "origin": {"kind": "human"}, "message": {"role": "user", "content": "line %d" % i}}
        for i, ts in enumerate(["2026-03-17T10:05:00Z", "2026-03-17T10:25:00Z"])]
with open(home + "/.claude/projects/-readb/s12.jsonl", "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
PY
: > "$T/r12.jsonl"
rd "$T/r12.jsonl" "$HOME/projects/readb" Quinn docs/a.md 10:01 10:02 10:03 10:04 10:05 10:06 10:07 10:08 10:09 10:10
rcfg "$T/r12.jsonl"
out=$(runc "$T/r12.jsonl.cfg" --week 2026-W12)
has "12: prompts 10:05 and 10:25 (20 min) with reading 10:00-10:10 (10 min): total 25, not 30" "$out" "| readb | 2 · 20 min | — | 10 min | 25 min | 10 min / 25 min | — | — |"
has "12: the overlap is visible: prompts already held 5 min of the reading" "$out" "already held 5 min of the reading"

# A heartbeat run across Sunday midnight is split there, as a prompt gap is: 23:58, 23:59, 00:00,
# 00:01 is the run [23:57, 00:01], 3 min in W12 and 1 min in W13.
: > "$T/r13.jsonl"
printf '{"doc":"docs/a.md","repo":"%s","ts":"2026-03-22T23:58:00Z","who":"Quinn"}\n{"doc":"docs/a.md","repo":"%s","ts":"2026-03-22T23:59:00Z","who":"Quinn"}\n{"doc":"docs/a.md","repo":"%s","ts":"2026-03-23T00:00:00Z","who":"Quinn"}\n{"doc":"docs/a.md","repo":"%s","ts":"2026-03-23T00:01:00Z","who":"Quinn"}\nnot json\n' "$RA" "$RA" "$RA" "$RA" >> "$T/r13.jsonl"
rcfg "$T/r13.jsonl"
out=$(runc "$T/r13.jsonl.cfg" --week 2026-W12)
has "split: Sunday's side of the run, 3 min" "$out" "| reada | 0 · 0 min | — | 3 min | 3 min |"
has "split: a line that is not JSON is skipped, said" "$out" "1 unreadable row skipped"
out=$(runc "$T/r13.jsonl.cfg" --week 2026-W13)
has "split: Monday's side, 1 min" "$out" "| reada | 0 · 0 min | — | 1 min | 1 min |"

# docs added: n, with a course: m — gamma (the estimated-reading repo above) added docs/a.md and the
# page in W10; a heartbeat on docs/a.md and on two docs that were not added in the week.
: > "$T/r14.jsonl"
printf '{"doc":"docs/a.md","repo":"%s","ts":"2026-03-04T15:00:00Z","who":"Quinn"}\n{"doc":"docs/old.md","repo":"%s","ts":"2026-03-04T15:00:00Z","who":"Quinn"}\n{"doc":"TODO.md","repo":"%s","ts":"2026-03-04T15:00:00Z","who":"Quinn"}\n' "$G" "$G" "$G" >> "$T/r14.jsonl"
printf '{"reads": ["%s"], "chrome": "%s/no-such-chrome", "projects": {"gamma": {}}}\n' "$T/r14.jsonl" "$T" > "$T/r14.cfg"
out=$(runc "$T/r14.cfg" --week 2026-W10)
has "course: of the 2 docs added, 1 has a heartbeat (an excluded doc and an old one do not count)" "$out" "- gamma — docs added: 2; html: 0 rendered, 1 static; with a course: 1"
has "course: the reading column holds the 1 min of the three docs' shared minute; the estimate stays 5 min, reference" "$out" "| gamma | 0 · 0 min | — | 1 min | 1 min | 1 min / 1 min | 5 min | — |"

# A run across midnight with a gap over a minute: 23:57 and 00:02 (gap 5) is the run [23:56, 00:02]:
# 4 min in W12, 2 in W13. Rows past the week's end are kept up to one gap, then clipped.
: > "$T/r15.jsonl"
printf '{"doc":"docs/a.md","repo":"%s","ts":"2026-03-22T23:57:00Z","who":"Quinn"}\n{"doc":"docs/a.md","repo":"%s","ts":"2026-03-23T00:02:00Z","who":"Quinn"}\n' "$RA" "$RA" >> "$T/r15.jsonl"
rcfg "$T/r15.jsonl"
out=$(runc "$T/r15.jsonl.cfg" --week 2026-W12)
has "split: a 5-minute gap across midnight keeps Sunday's 4 min" "$out" "| reada | 0 · 0 min | — | 4 min | 4 min |"
out=$(runc "$T/r15.jsonl.cfg" --week 2026-W13)
has "split: and Monday's 2" "$out" "| reada | 0 · 0 min | — | 2 min | 2 min |"

# An epoch-seconds ts (keel's opens.jsonl writes them so): read as UTC, not skipped.
: > "$T/r16.jsonl"
for e in 1773738000 1773738060 1773738120; do printf '{"doc":"docs/a.md","repo":"%s","ts":%s.5,"who":"Quinn"}\n' "$RA" "$e"; done >> "$T/r16.jsonl"
rcfg "$T/r16.jsonl"
out=$(runc "$T/r16.jsonl.cfg" --week 2026-W12)
has "ts: epoch seconds count — 09:00..09:02 is 3 min" "$out" "| reada | 0 · 0 min | — | 3 min | 3 min |"
case "$out" in *unreadable*) bad "ts: and no row is unreadable" "$out" ;; *) ok "ts: and no row is unreadable" ;; esac
printf '{"reads": ["%s"], "read_gap_minutes": 0}\n' "$T/r8.jsonl" > "$T/r8z.cfg"
out=$(runc "$T/r8z.cfg" --week 2026-W12)
has "read_gap_minutes 0 is applied, not read as unset: every heartbeat its own minute, 5 min" "$out" "| reada | 0 · 0 min | — | 5 min | 5 min |"
has "and the header says 0" "$out" "reading ≤ 0)"

# Opens without a heartbeat: keel's opens.jsonl beside the reads file names a doc loaded in the week
# that never heartbeat (and one that did, which is not counted).
mkdir -p "$T/st"
rd "$T/st/reads.jsonl" "$RA" Quinn docs/a.md 09:00 09:01
printf '{"doc":"docs/a.md","repo":"%s","ts":1773737940.0}\n{"doc":"docs/b.md","repo":"%s","ts":1773737940.0}\n{"doc":"docs/c.md","repo":"%s","ts":1773737940.0}\n' "$RA" "$RA" "$RA" > "$T/st/opens.jsonl"
rcfg "$T/st/reads.jsonl"
out=$(runc "$T/st/reads.jsonl.cfg" --week 2026-W12)
has "opens: two docs opened without a heartbeat, per project, counts only" "$out" "Opened without a heartbeat (docs): reada 2."
case "$out" in *b.md*|*c.md*) bad "opens: no doc path" "$out" ;; *) ok "opens: no doc path" ;; esac

# ---- the drain: keel sheep drain once at the start of `week`, a stub keel pinned ----
mkdir -p "$T/dleg/bin"
cat > "$T/dleg/bin/keel" <<'STUB'
#!/usr/bin/env python3
import os, sys
open(os.environ["STUB_KEEL_ARGS"], "a").write(" ".join(sys.argv[1:]) + " in " + str(len(os.listdir("."))) + " files\n")
if os.environ.get("STUB_KEEL_RC", "0") != "0":
    sys.stderr.write(os.environ.get("STUB_KEEL_ERR", "") + "\n")
    sys.exit(int(os.environ["STUB_KEEL_RC"]))
# A drain files the room's heartbeats: five rows on Tuesday 2026-03-17.
with open(os.environ["STUB_KEEL_FILE"], "a") as f:
    for t in ("09:00", "09:01", "09:02", "09:09", "09:10"):
        f.write('{"doc":"docs/a.md","repo":"%s","ts":"2026-03-17T%s:00Z","who":"Quinn"}\n' % (os.environ["STUB_KEEL_REPO"], t))
STUB
export STUB_KEEL_ARGS="$T/keel.args" STUB_KEEL_FILE="$T/rd.jsonl" STUB_KEEL_REPO="$RA"
: > "$T/rd.jsonl"
rcfg "$T/rd.jsonl"
dr() {  # [env...] — a run of W12 with the drain on and the stub pinned
  ( cd "$G" && env -u CREW_REPORT_NO_DRAIN CREW_REPORT_KEEL="$T/dleg/bin/keel" "$@" CREW_REPORT_CONFIG="$T/rd.jsonl.cfg" python3 "$D/bin/crew-report" week --week 2026-W12 2>&1 )
}
: > "$STUB_KEEL_ARGS"
out=$(dr CREW_REPORT_NO_DRAIN=1)
[ ! -s "$STUB_KEEL_ARGS" ] && ok "drain: CREW_REPORT_NO_DRAIN=1 does not call keel" || bad "drain: NO_DRAIN skips" "$(cat "$STUB_KEEL_ARGS")"
: > "$T/rd.jsonl"
out=$(dr STUB_KEEL_RC=0)
has "drain: keel is called as 'sheep drain'" "$(cat "$STUB_KEEL_ARGS")" "sheep drain"
has "drain: in an empty folder, not the caller's repo (an old keel reads 'drain' as a doc to deploy)" "$(cat "$STUB_KEEL_ARGS")" "sheep drain in 0 files"
has "drain: a good drain says when it ran" "$out" "drained: "
case "$out" in *"No drain this run"*) bad "drain: no stale line after a good drain" "$out" ;; *) ok "drain: no stale line after a good drain" ;; esac
has "drain: it runs before the file is read — the rows it filed are in this report" "$out" "| reada | 0 · 0 min | — | 5 min | 5 min |"
case "$out" in *"drain: failed"*|*"drain: keel"*) bad "drain: a good drain adds no line" "$out" ;; *) ok "drain: a good drain adds no line" ;; esac
out=$(dr STUB_KEEL_RC=1 STUB_KEEL_ERR="memo: drain: no such file")
has "drain: a keel without the subcommand (today's reply) is one line, not a stack trace" "$out" "drain: failed — exit 1: memo: drain: no such file."
has "drain: and the report still prints" "$out" "# crew-report — 2026-W12"
out=$(env -u CREW_REPORT_NO_DRAIN CREW_REPORT_CONFIG="$T/rd.jsonl.cfg" python3 "$D/bin/crew-report" week --week 2026-W12 2>&1)
has "drain: keel not found is one line" "$out" "drain: keel not found."

# ---- review fixes (the /finish review, 2026-10-19) ----
# A fork of a dispatch session (pickup's move): the copied rows carry the fork's sessionId and a
# forked-from record names the source and cutoff; the person's lines after the move count. And a
# /pickup typed with no quoted branch is the person's own, not the prefill. W14: 2026-03-30 on.
mkdir -p "$HOME/projects/forky/.git" "$HOME/.claude/projects/-forky"
python3 - "$HOME" <<'PYF'
import json, sys
home = sys.argv[1]; A = home + "/projects/forky"
def ev(sid, uid, ts, content):
    return {"type": "user", "uuid": uid, "sessionId": sid, "timestamp": ts, "cwd": A, "entrypoint": "cli",
            "origin": {"kind": "human"}, "message": {"role": "user", "content": content}}
rows = [ev("new", "f1", "2026-03-31T09:00:00Z", "You are an unattended session started by dispatch for a branch"),
        ev("new", "f2", "2026-03-31T09:05:00Z", "carry on"),
        {"type": "forked-from", "sessionId": "new", "from": {"sessionId": "old", "host": "h"}, "cutoff": "2026-03-31T09:05:00Z", "records": 2},
        ev("new", "f3", "2026-03-31T10:00:00Z", "my own line after the move"),
        ev("new", "f4", "2026-03-31T10:10:00Z", "<command-name>/pickup</command-name>\n<command-args>next</command-args>")]
with open(home + "/.claude/projects/-forky/new.jsonl", "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
PYF
out=$(run --week 2026-W14)
has "fork: the person's lines after the move count; the inherited dispatch rows do not" "$out" "| forky | 2 · 10 min |"
has "fork: the inherited rows are the source session's machine starts" "$out" "machine starts 2"

# The static fallback: a page that never closes <head>, and a table whose rows are never closed.
python3 - "$D/bin/crew-report" <<'PYH' && ok "html: an unclosed <head> ends at <body>; an unclosed <tr> ends at the next row or the table" || bad "html: unclosed head or row" "see the python error above"
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("cr", sys.argv[1]); s = u.spec_from_loader("cr", l); cr = u.module_from_spec(s); l.exec_module(cr)
assert cr.html_words("<html><head><title>T</title><body><p>one two three four</p></body></html>") == 4.0
assert cr.html_words("<table><tr><td>a b<tr><td>c d</table><p>one two three four</p>") == 6.0
PYH

# An audio root matches whole segments only: /aud is not the start of /audio-other.
python3 - "$D/bin/crew-report" <<'PYA' && ok "audio: a root prefix matches whole path segments" || bad "audio: root prefix boundary" "see the python error above"
import importlib.machinery as m, importlib.util as u, sys
from pathlib import Path
l = m.SourceFileLoader("cr", sys.argv[1]); s = u.spec_from_loader("cr", l); cr = u.module_from_spec(s); l.exec_module(cr)
c = {"audio_roots": {"/aud": "/here"}}
assert cr.audio_path(c, "/aud/x.m4a") == Path("/here/x.m4a"), cr.audio_path(c, "/aud/x.m4a")
assert cr.audio_path(c, "/audio-other/x.m4a") == Path("/audio-other/x.m4a"), cr.audio_path(c, "/audio-other/x.m4a")
PYA

# A zone name, not today's fixed offset: weeks on either side of a DST change meet with no hole.
TZ=America/Los_Angeles python3 - "$D/bin/crew-report" <<'PYZ' && ok "zone: the named zone, so two weeks across a DST change meet" || bad "zone: DST hole" "see the python error above"
import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("cr", sys.argv[1]); s = u.spec_from_loader("cr", l); cr = u.module_from_spec(s); l.exec_module(cr)
tz = cr.zone({"tz": ""})
assert cr.week_bounds("2026-W44", tz)[1] == cr.week_bounds("2026-W45", tz)[0]
assert cr.week_bounds("2026-W44", tz)[1].utcoffset() != cr.week_bounds("2026-W43", tz)[0].utcoffset()
PYZ

# reading.include brings an excluded doc back; two repos of one project adding the same path are two docs.
H="$HOME/projects/hrepo"
mkdir -p "$H/docs" "$G/../gamma2"
git -C "$H" init -q -b main
words 200 > "$H/docs/a.md"
git -C "$H" add -A
GIT_AUTHOR_DATE=2026-03-03T12:00:00+00:00 GIT_COMMITTER_DATE=2026-03-03T12:00:00+00:00 git -C "$H" -c commit.gpgsign=false -c user.name=t -c user.email=crew-test commit -q -m add
printf '{"chrome": "%s/no-such-chrome", "projects": {"gamma": {"repos": ["gamma", "hrepo"], "reading": {"include": ["TODO.md"]}}}}\n' "$T" > "$T/inc.json"
out=$(runc "$T/inc.json" --week 2026-W10)
has "reading: include brings TODO.md back, and hrepo's docs/a.md is a doc beside gamma's (2 + 1 + 1)" "$out" "- gamma — docs added: 4"

# Cost: usage-report's keys re-keyed through crew's project_of — a subfolder joins its repo's row.
cat > "$T/usage-report" <<'STUB'
def data_dir():
    return "/nowhere"
import os
def load_rows(c, a, b):
    h = os.environ.get("STUB_HOST", "")
    return [{"project": "alpha/docs", "cost": "1.50", "host": h}, {"project": "alpha", "cost": "2.00", "host": "zz-other"},
            {"project": "~/elsewhere", "cost": "0.25", "host": h}]
STUB
out=$(CREW_REPORT_USAGE_REPORT="$T/usage-report" run --week 2026-W10)
has "cost: a subfolder's cost joins its repo's row" "$out" "| alpha | 3 · 3 min | — | — | 3 min | 3 min / 3 min | — | \$3.50"
case "$out" in *'$3.50'*) ok "cost: alpha holds 2.00 + 1.50" ;; *) bad "cost: alpha holds 2.00 + 1.50" "$out" ;; esac
hn=$(printf '%s\n' "$out" | sed -n 's/.*cover this Mac (\([^)]*\)).*/\1/p')
out=$(STUB_HOST="$hn" CREW_REPORT_USAGE_REPORT="$T/usage-report" run --week 2026-W10 --this-host)
has "cost: --this-host keeps this Mac's rows only (1.50 of alpha's 3.50)" "$out" "| alpha | 3 · 3 min | — | — | 3 min | 3 min / 3 min | — | \$1.50"
has "cost: and the header says so" "$out" "Cost covers this Mac only (--this-host)."
out=$(run --week 2026-W10)
case "$out" in *"(text #"*) ok "first prompts: a text opening is counted by a digest of its first 40 characters" ;; *) bad "first prompts: text digest" "$out" ;; esac
case "$out" in *"hello"*|*"late on"*) bad "first prompts: no prompt text" "$out" ;; *) ok "first prompts: no prompt text" ;; esac

exit $rc
