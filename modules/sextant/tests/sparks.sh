#!/usr/bin/env bash
# Tests for bin/sparks — scratch dirs, stub whisper and stub claude, no network, no model.
# The one thing it cannot stub is Apple's audio converter, so it makes a real recording with
# `say` and lets afconvert do its job.        bash modules/sextant/tests/sparks.sh (macOS only)
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# A config dir of the suite's own, before any case moves HOME: the core is found from this
# checkout (lib/find_core.py), and no private value of the Mac's leaks into a case — no `legacy`
# file, so it reads as a stranger's install: every sextant/ key absent, its default in force.
export REGATTA_CONFIG="$T/regatta-config"; mkdir -p "$REGATTA_CONFIG"
unset REGATTA_HOME CLAUDE_REPOS_JSON
mkdir -p "$T/out" "$T/archive" "$T/bin"   # not "$T/in": the first case is a missing inbox
# No config by default: the runner must be useless without one, and the env must still win.
export SPARKS_CONFIG="$T/none.json"
export SPARKS_IN="$T/in" SPARKS_OUT="$T/out" SPARKS_ARCHIVE="$T/archive" SPARKS_STATE="$T/state.json" SPARKS_COMMIT=0
export SPARKS_LOG="$T/memo.log" CLAUDE_CODE_SESSION_ATTENDED=1   # the log is never the real one
export WHISPER_BIN="$T/bin/whisper" WHISPER_MODEL="$T/model.bin" CLAUDE_BIN="$T/bin/claude"
# The model comes from bin/gate's table, never the real one here: a scratch table per case.
table() {  # $1 the shape row, $2 the route row (default: claude, nothing else)
  local d='{"kind": "generate", "provider": "claude"}'
  printf '{"defaults": {"claude": {"model": "opus"}}, "sites": {"sparks.shape": %s, "sparks.route": %s}}\n' \
    "${1:-$d}" "${2:-$d}" > "$T/models.json"
}
HAIKU='{"kind": "generate", "provider": "claude", "model": "haiku"}'
export GATE_TABLE="$T/models.json"; table "$HAIKU"
for v in $(env | sed -n 's/^\(GATE_[A-Z0-9_]*\)=.*/\1/p'); do [ "$v" = GATE_TABLE ] || unset "$v"; done   # the caller's overrides
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }

touch "$T/model.bin"
cat > "$T/bin/whisper" <<'EOF'
#!/bin/sh
# stub: ignore the model, print a fixed Russian transcript
echo "$@" > "$TMPDIR_CAPTURE/whisper-args.txt"
echo " Напомни проверить календарь. Это тест, не надо."
EOF
cat > "$T/bin/claude" <<'EOF'
#!/bin/sh
# stub: a note in the shape the real prompt asks for; also record that it was called
echo "$@" > "$TMPDIR_CAPTURE/claude-args.txt"
printf '# Trash calendar and a test\n\n## Summary\nThe owner wants the bin calendar checked.\n\n## Topics\n### Trash calendar\n**Action:** check it.\n\n## Bin\n- "это тест"\n'
EOF
chmod +x "$T/bin/whisper" "$T/bin/claude"
export TMPDIR_CAPTURE="$T"

echo "config: the personal half lives outside this repo"
out=$(env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE python3 "$B/sparks")
check "$(echo "$out" | grep -c 'no config at')" "1" "no config and no SPARKS_IN: says so, exits 0"
grep -qE '/Users/|projects/_' "$B/sparks"; check $? 1 "the runner names no owner's path (the repo's helloworld check is the whole gate)"
cat > "$T/config.json" <<EOF
{ "inbox": "$T/in", "notes": "$T/out", "archive": "$T/archive",
  "prompt": "p.md", "model": "sonnet", "language": "ru", "commit": false }
EOF
printf 'PERSONAL PROMPT from the vault\n\nTranscript:\n' > "$T/p.md"

echo "sparks"
out=$(python3 "$B/sparks")
check "$(echo "$out" | grep -c 'no inbox at')" "1" "missing inbox: says so, exits 0"
mkdir -p "$T/in"
check "$(python3 "$B/sparks"; echo $?)" "0" "empty inbox: quiet, exits 0"

say -o "$T/in/memo one.aiff" "This is the first memo" 2>/dev/null
out=$(python3 "$B/sparks")
note=$(ls "$T/out" | head -1)
check "$(echo "$out" | grep -c '^✓')" "1" "one memo: one note reported"
[ -n "$note" ]; check $? 0 "  a note file was written"
grep -q '^## Summary' "$T/out/$note"; check $? 0 "  the note carries Claude's sections"
grep -q '^# Trash calendar and a test$' "$T/out/$note"; check $? 0 "  the title is Claude's, whole, used once"
[ "$(grep -c '^# ' "$T/out/$note")" = 1 ]; check $? 0 "  the title is not repeated"
grep -q 'source: voice memo' "$T/out/$note"; check $? 0 "  frontmatter names the source"
grep -q 'Напомни проверить календарь' "$T/out/$note"; check $? 0 "  the verbatim transcript is kept, in the original language"
grep -q -- '--allowedTools' "$T/claude-args.txt"; check $? 0 "  Claude is called with no tools"
[ -f "$T/archive/memo one.aiff" ]; check $? 0 "  the audio moved to the archive, outside any repo"
[ -z "$(ls "$T/in")" ]; check $? 0 "  the inbox is left empty"

out=$(python3 "$B/sparks")
check "$(echo "$out" | grep -c '^✓')" "0" "a second run: nothing to do"

check "$(ls "$T/out" | wc -l | tr -d ' ')" "1" "  and no duplicate note"

# Now drive it from the config file alone — no SPARKS_* in the environment at all.
say -o "$T/in/from config.aiff" "A memo routed by the config file" 2>/dev/null
out=$(env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_COMMIT \
  SPARKS_CONFIG="$T/config.json" SPARKS_STATE="$T/state.json" \
  WHISPER_BIN="$T/bin/whisper" WHISPER_MODEL="$T/model.bin" CLAUDE_BIN="$T/bin/claude" \
  python3 "$B/sparks")
check "$(echo "$out" | grep -c '^✓')" "1" "config alone routes a memo"
grep -q 'PERSONAL PROMPT from the vault' "$T/claude-args.txt"; check $? 0 "  the vault's prompt is the one sent"
grep -q -- '--model haiku' "$T/claude-args.txt"; check $? 0 "  the table picks the model"
grep -q -- '--model sonnet' "$T/claude-args.txt"; check $? 1 "  and a model left in the config is ignored"
grep -q '"-l" "ru"\|-l ru' "$T/whisper-args.txt"; check $? 0 "  the config picks the language"
say -o "$T/in/override.aiff" "A memo on one run's model" 2>/dev/null
GATE_SPARKS_SHAPE_MODEL=sonnet python3 "$B/sparks" >/dev/null
grep -q -- '--model sonnet' "$T/claude-args.txt"; check $? 0 "GATE_SPARKS_SHAPE_MODEL overrides the table for a run"
table '{"kind": "generate", "provider": "claude", "effort": "low"}'
say -o "$T/in/effort.aiff" "A memo on the default model" 2>/dev/null
python3 "$B/sparks" >/dev/null
grep -q -- '--model opus --effort low' "$T/claude-args.txt"; check $? 0 "  a row without a model takes the default, and its effort"
table "$HAIKU"

say -o "$T/in/memo two.aiff" "The second memo" 2>/dev/null
cat > "$T/bin/claude" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$T/bin/claude"
out=$(python3 "$B/sparks")
check "$(echo "$out" | grep -c '^⚠')" "1" "Claude fails: reported, not silent"
[ -f "$T/in/memo two.aiff" ]; check $? 0 "  the audio stays in the inbox for the next run"
check "$(ls "$T/out" | wc -l | tr -d ' ')" "4" "  no half-written note (still the four good ones)"

table '{"kind": "generate", "provider": "off", "when_off": "fail"}'
rm -f "$T/claude-args.txt"
out=$(python3 "$B/sparks")
check "$(echo "$out" | grep -c 'is off (when_off: fail)')" "1" "shaping off in the table: reported"
[ ! -f "$T/claude-args.txt" ]; check $? 0 "  no Claude call"
[ -f "$T/in/memo two.aiff" ]; check $? 0 "  and the audio waits"
table "$HAIKU"

printf '#!/bin/sh\nexit 3\n' > "$T/bin/whisper"; chmod +x "$T/bin/whisper"
out=$(python3 "$B/sparks")
check "$(echo "$out" | grep -c 'transcription failed')" "1" "whisper fails: reported, audio kept"

rm "$T/model.bin"
out=$(python3 "$B/sparks")
check "$(echo "$out" | grep -c 'brew install whisper-cpp')" "1" "model missing: says how to fix it, exits 0"


echo "the rename (2026-10-07): memo-run's state is honoured, nothing is filed twice"
H="$T/home"; mkdir -p "$H/.cache/memo-run" "$T/in-old"; touch "$T/model.bin"
printf '#!/bin/sh\necho " Старая запись."\n' > "$T/bin/whisper"
printf '#!/bin/sh\necho "$@" > "$TMPDIR_CAPTURE/claude-args.txt"\nprintf "# Old\\n\\n## Summary\\nx\\n"\n' > "$T/bin/claude"
chmod +x "$T/bin/whisper" "$T/bin/claude"
say -o "$T/in-old/old.aiff" "a memo memo-run filed before the rename" 2>/dev/null
python3 -c 'import importlib.machinery as m, importlib.util as u, json, sys; from pathlib import Path
l = m.SourceFileLoader("sparks", sys.argv[1]); r = u.module_from_spec(u.spec_from_loader("sparks", l)); l.exec_module(r)
Path(sys.argv[2]).write_text(json.dumps({r.digest(Path(sys.argv[3])): {"file": "old.aiff", "note": "old.md"}}))' \
  "$B/sparks" "$H/.cache/memo-run/processed.json" "$T/in-old/old.aiff"
rm -f "$T/claude-args.txt"; n=$(ls "$T/out" | wc -l | tr -d ' ')
old() { env -u SPARKS_STATE HOME="$H" SPARKS_IN="$T/in-old" python3 "$B/sparks" -v; }
out=$(old)
echo "$out" | grep -q "state moved from $H/.cache/memo-run/processed.json"; check $? 0 "  the pass says it moved the state"
[ -f "$H/.cache/sparks/processed.json" ] && [ ! -f "$H/.cache/memo-run/processed.json" ]; check $? 0 "  the file now lives under ~/.cache/sparks"
[ ! -f "$T/claude-args.txt" ] && [ "$(ls "$T/out" | wc -l | tr -d ' ')" = "$n" ]; check $? 0 "  the recording in it is not shaped or filed again"
echo '{}' > "$H/.cache/memo-run/processed.json"; out=$(old)
echo "$out" | grep -q 'state moved'; check $? 1 "  once: a new state is never overwritten by an old one"
rm -rf "$T/in-old"

echo "two inboxes (2026-10-10): a file another inbox of the same speaker filed is archived, not filed again"
S="$T/states"; H2="$T/home2"; mkdir -p "$S" "$H2" "$T/in-two" "$T/arch-two"
echo '{"speaker": "sam"}' > "$T/sam.json"
say -o "$T/in-two/twice.aiff" "the same recording in two inboxes" 2>/dev/null
sib() {  # sib <state file> <speaker> <note>: a sibling state that filed twice.aiff
  python3 -c 'import importlib.machinery as m, importlib.util as u, json, sys; from pathlib import Path
l = m.SourceFileLoader("sparks", sys.argv[1]); r = u.module_from_spec(u.spec_from_loader("sparks", l)); l.exec_module(r)
Path(sys.argv[2]).write_text(json.dumps({"_speaker": sys.argv[4], r.digest(Path(sys.argv[3])): {"file": "twice.aiff", "note": sys.argv[5]}}))' \
    "$B/sparks" "$1" "$T/in-two/twice.aiff" "$2" "$3"; }
two() { HOME="$H2" SPARKS_CONFIG="$T/sam.json" SPARKS_STATE="$S/ideas-this.json" SPARKS_IN="$T/in-two" SPARKS_ARCHIVE="$T/arch-two" python3 "$B/sparks" -v; }
sib "$S/ideas-a.json" sam "(filed by ideas-b: wrong.md)"; sib "$S/ideas-b.json" sam "first.md"
echo '{"x": "not a state"}' > "$S/ideas-this.notes.json"
rm -f "$T/claude-args.txt"; n=$(ls "$T/out" | wc -l | tr -d ' ')
out=$(two)
echo "$out" | grep -q 'already filed from the ideas-b inbox: first.md'; check $? 0 "  the pass names the inbox that really filed it, never a (filed by …) record"
[ ! -f "$T/claude-args.txt" ] && [ "$(ls "$T/out" | wc -l | tr -d ' ')" = "$n" ]; check $? 0 "  not shaped, no note filed"
[ -f "$T/arch-two/twice.aiff" ] && [ ! -f "$T/in-two/twice.aiff" ]; check $? 0 "  archived beside its own inbox; the inbox empties"
grep -q '(filed by ideas-b: first.md)' "$S/ideas-this.json" && grep -q '"_speaker": "sam"' "$S/ideas-this.json"; check $? 0 "  its own state records it and its speaker"
[ ! -e "$S/ideas-this.json.tmp" ]; check $? 0 "  the state is written whole (temp file, then rename)"
mv "$T/arch-two/twice.aiff" "$T/in-two/twice.aiff"; rm -f "$S"/ideas-*.json; sib "$S/ideas-z.json" alex "first.md"
out=$(two)
[ -f "$T/claude-args.txt" ]; check $? 0 "  another speaker's inbox (a friend's shared one) never stops a filing"
echo "  same samples, different bytes (New Recording 5 had three content hashes): filed once"
rm -f "$S"/ideas-*.json "$T/claude-args.txt" "$T/in-two"/* "$T/arch-two"/*
say -o "$T/in-two/a.aiff" "one recording" 2>/dev/null
afconvert -f WAVE -d LEI16 "$T/in-two/a.aiff" "$T/b.wav"
out=$(two); [ -f "$T/claude-args.txt" ]; check $? 0 "  the first copy is transcribed and filed"
rm -f "$T/claude-args.txt"; mv "$T/b.wav" "$T/in-two/b.wav"
out=$(two)
echo "$out" | grep -q 'the same recording was filed from this inbox'; check $? 0 "  a re-saved copy in the same inbox is archived by its samples"
[ ! -f "$T/claude-args.txt" ] && [ -f "$T/arch-two/b.wav" ]; check $? 0 "  not transcribed or shaped again; archived"
# Plain AIFF, not AIFC: `say` writes AIFF-C on macOS 26, so an AIFC BEI16 copy came out byte for byte
# the first recording and the content key, not the samples, caught it (2026-10-19).
mv "$S/ideas-this.json" "$S/ideas-b.json"; afconvert -f AIFF -d BEI16 "$T/arch-two/b.wav" "$T/in-two/c.aiff"
cmp -s "$T/in-two/c.aiff" "$T/arch-two/a.aiff"; check $? 1 "  (the copy's bytes differ from the first recording's)"
out=$(two)
echo "$out" | grep -q 'the same recording was filed from the ideas-b inbox'; check $? 0 "  and one in another inbox of the same speaker"
echo "  a written note: the same words, 5 or more, are filed once; fewer are always filed"
rm -f "$S"/ideas-*.json "$T/claude-args.txt" "$T/in-two"/* "$T/arch-two"/*
echo '{"speaker": "sam", "split": "topics"}' > "$T/sam.json"
printf 'Call the plumber about the leak.\n' > "$T/in-two/n1.txt"; out=$(two)
printf 'call the plumber   about the leak.\n\n' > "$T/in-two/n2.txt"; rm -f "$T/claude-args.txt"; out=$(two)
echo "$out" | grep -q 'the same note was filed from this inbox'; check $? 0 "  case and spacing aside, the same note is archived"
printf 'Это мои\xcc\x86 план на завтра.\n' > "$T/in-two/r1.txt"; out=$(two)   # NFD й (и + breve), as one app exports it
printf 'это мо\xd0\xb9 план на завтра\n' > "$T/in-two/r2.txt"; rm -f "$T/claude-args.txt"; out=$(two)   # NFC й, no full stop
echo "$out" | grep -q 'the same note was filed from this inbox'; check $? 0 "  Unicode form and the closing full stop aside, five words are the same note"
printf 'Would be very cool.\n' > "$T/in-two/s1.txt"; out=$(two); printf 'would be very cool\n' > "$T/in-two/s2.txt"; rm -f "$T/claude-args.txt"; out=$(two)
[ -f "$T/claude-args.txt" ]; check $? 0 "  four words are filed again: too short to call a duplicate"
echo "  an idle inbox stamps its speaker, so its siblings can match it"
echo '{"k": {"note": "x.md"}}' > "$S/ideas-this.json"; rm -f "$T/in-two"/*
cp "$S/ideas-this.json" "$T/before.json"
out=$(HOME="$H2" SPARKS_CONFIG="$T/sam.json" SPARKS_STATE="$S/ideas-this.json" SPARKS_IN="$T/in-two" SPARKS_ARCHIVE="$T/arch-two" python3 "$B/sparks" --dry-run -v)
cmp -s "$S/ideas-this.json" "$T/before.json"; check $? 0 "  a dry run writes nothing, the stamp included"
out=$(two); grep -q '"_speaker": "sam"' "$S/ideas-this.json"; check $? 0 "  stamped with nothing in the inbox"
echo '{"_speaker": "alex", "k": {"note": "x.md"}}' > "$S/ideas-this.json"
out=$(two); grep -q '"_speaker": "sam"' "$S/ideas-this.json"; check $? 0 "  a stale speaker is restamped, not kept because a stamp exists"
printf '{"k": {"note": "x.md"' > "$S/ideas-this.json"; cp "$S/ideas-this.json" "$T/before.json"
out=$(two); cmp -s "$S/ideas-this.json" "$T/before.json"; check $? 0 "  a state that does not parse is left alone, never emptied by the stamp"
rm -rf "$T/in-two" "$T/arch-two" "$S" "$H2"

echo "routing (D18): a fake remote plays GitHub, a stub plays both Claude calls"
# Fresh stubs: whisper echoes, claude answers the shaping call with a note and the routing
# call (the one with read-only tools) with whatever $T/route.json holds.
touch "$T/model.bin"
cat > "$T/bin/whisper" <<'EOF'
#!/bin/sh
echo " Отзыв о монтаже."
EOF
cat > "$T/bin/claude" <<'EOF'
#!/bin/sh
echo "$@" >> "$TMPDIR_CAPTURE/claude-calls.txt"
case "$*" in
  *"Read,Glob,Grep"*) pwd -P > "$TMPDIR_CAPTURE/route-cwd.txt"; echo "I looked around."; cat "$TMPDIR_CAPTURE/route.json" ;;
  *) printf '# Feedback on the rough cut\n\n## Summary\nNotes on cut four.\n\n## Topics\n### Pacing\nShot 3 is long.\n\n## Bin\n- "раз два три"\n' ;;
esac
EOF
chmod +x "$T/bin/whisper" "$T/bin/claude"
P="$T/projects"; mkdir -p "$P"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare "$T/remote.git"
git init -q -b main "$P/film"
mkdir "$P/film/notes"; echo x > "$P/film/notes/feedback-r1.md"; echo r > "$P/film/README.md"
git -C "$P/film" add -A
git -C "$P/film" commit -qm init
git -C "$P/film" remote add origin "$T/remote.git"
git -C "$P/film" push -q origin main 2>/dev/null
# The vault is a real repo: landing there asks git what it tracks and ignores (W2).
git init -q -b main "$P/vault"
mkdir -p "$P/vault/ventures" "$P/vault/outputs" "$P/vault/me"
echo v > "$P/vault/ventures/a.md"; echo m > "$P/vault/me/core.md"; echo 'outputs/' > "$P/vault/.gitignore"
echo o > "$P/vault/outputs/old.md"
git -C "$P/vault" add -A
git -C "$P/vault" commit -qm init
mkdir -p "$P/film/rules"; echo r > "$P/film/rules/a.md"
git -C "$P/film" add -A
git -C "$P/film" commit -qm rules
git -C "$P/film" push -q origin main 2>/dev/null
git -C "$P/film" push -q origin "$(git -C "$P/film" rev-parse main):refs/heads/claude/other/2026-09-29-doc" 2>/dev/null
git init -q -b main "$P/site"
git init -q -b main "$P/twin"
printf '{"repos": {"film": {}, "vault": {"knowledge": true}, "absent": {}, "site": {"published": true, "memos_to": "film"}, "twin": {"twin_of": "film"}}}' > "$T/repos.json"
# rename S2 (M23): the config key `launch` or the old `land`, the env SPARKS_LAUNCH or SPARKS_LAND —
# the owner's sparks.json says "land" until S7, and a key read as absent would default to "pr"
cfgland() { printf '%s' "$1" > "$T/land-config.json"; env -u SPARKS_LAND -u SPARKS_LAUNCH ${2:+"$2"} SPARKS_CONFIG="$T/land-config.json" python3 - "$B/sparks" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("sparks", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sparks", loader)); loader.exec_module(m)
print(m.CFG["land"])
PY
}
check "$(cfgland '{"land": "merge"}') $(cfgland '{"launch": "merge"}') $(cfgland '{}')" "merge merge pr" 'the config key "land" and "launch" both read; neither: pr'
check "$(cfgland '{}' SPARKS_LAND=merge) $(cfgland '{}' SPARKS_LAUNCH=merge)" "merge merge" "  and SPARKS_LAND and SPARKS_LAUNCH both"
# rename S3: launch_vault is a name outside callers load through a shim — a rename here passes this
# suite and breaks theirs, so the name itself is a case
check "$(python3 -c 'import importlib.machinery as m, importlib.util as u, sys
l = m.SourceFileLoader("sparks", sys.argv[1]); r = u.module_from_spec(u.spec_from_loader("sparks", l)); l.exec_module(r)
print(callable(getattr(r, "launch_vault", None)))' "$B/sparks")" "True" "launch_vault is there by that name"
export SPARKS_ROUTE=1 SPARKS_LAND=merge SPARKS_PROJECTS="$P" SPARKS_REPOS="$T/repos.json" SPARKS_FAKE_MERGE=1 SPARKS_HOST=
printf '{"deny": ["vault/me/"]}' > "$T/route-config.json"; export SPARKS_CONFIG="$T/route-config.json"
rm -f "$T/in"/*   # the failure cases above leave their audio for a retry, by design
# memo() runs inside $(…), a subshell, so the counter lives in a file
memo() { n=$(( $(cat "$T/n" 2>/dev/null || echo 0) + 1 )); echo $n > "$T/n"
  say -o "$T/in/r$n.aiff" "routing memo number $n $1" 2>/dev/null; python3 "$B/sparks"; }
route() { printf '%s\n' "$1" > "$T/route.json"; }
branches() { git -C "$P/film" ls-remote origin 'refs/heads/claude/*' | wc -l | tr -d ' '; }

route '{"repo": "film", "path": "notes/feedback-r2.md", "confidence": "high", "why": "cut feedback"}'
out=$(memo a)
check "$(echo "$out" | grep -c '→ film/notes/feedback-r2.md')" "1" "high confidence, folder exists: filed and reported"
git -C "$P/film" fetch -q origin main
git -C "$P/film" cat-file -e origin/main:notes/feedback-r2.md; check $? 0 "  the file is on the remote's main"
git -C "$P/film" show origin/main:notes/feedback-r2.md | grep -q '^## Bin'; check $? 1 "  the project copy carries no Bin section"
git -C "$P/film" show origin/main:notes/feedback-r2.md | grep -q 'Отзыв о монтаже'; check $? 0 "  ... but the verbatim transcript"
check "$(branches)" "2" "  a claude/* branch was pushed (beside the other session's)"
check "$(git -C "$P/film" status --porcelain | wc -l | tr -d ' ')" "0" "  the checkout is untouched"
stub=$(grep -l '^filed: film/notes/feedback-r2.md' "$T/out"/*.md | head -1)
[ -n "$stub" ]; check $? 0 "  the vault keeps a stub naming where it went"
grep -q 'раз два три' "$stub"; check $? 0 "  the stub keeps the Bin proposal for /embark"
check "$(cat "$T/route-cwd.txt")" "$(cd "$P" && pwd -P)" "  the routing call runs in the projects folder"
grep 'Read,Glob,Grep' "$T/claude-calls.txt" | grep -q -- '--disallowedTools Bash,Edit,Write'; check $? 0 "  the routing call cannot write"
check "$(grep -o disableAllHooks "$T/claude-calls.txt" | wc -l | tr -d " ")" "2" "  both calls run with hooks off"
grep -q -- '- film (also takes notes about site)' "$T/claude-calls.txt"; check $? 0 "  a memos_to repo's notes are offered to its target (D1, 2026-10-05)"
got=$(python3 -c 'import importlib.machinery as m, sys; r = m.SourceFileLoader("mr", sys.argv[1]).load_module(); print(r.check({"repo": "film (also takes notes about site)", "path": "notes/x.md", "confidence": "high", "why": "?"}, {"film": {}})[0])' "$B/sparks")
check "$got" "film" "  a reply that copies the annotation still names the bare repo"

refused() {  # $1 = decision JSON, $2 = reason fragment, $3 = label
  route "$1"; out=$(memo "$3")
  f=$(ls -t "$T/out"/*.md | head -1)
  check "$(grep -c "not filed: .*$2" "$f")" "1" "$3: stays in the inbox, reason on the note"
}
refused '{"repo": "film", "path": "notes/x.md", "confidence": "low", "why": "maybe"}' 'not sure' "low confidence"
refused '{"repo": "film", "path": "drafts/x.md", "confidence": "high", "why": "?"}' 'does not exist' "a folder that is not there"
refused '{"repo": "film", "path": "notes/feedback-r1.md", "confidence": "high", "why": "?"}' 'already exists' "a file that is already there"
refused '{"repo": "film", "path": "../escape.md", "confidence": "high", "why": "?"}' 'not a plain .md' "a path that climbs out"
refused '{"repo": "film", "path": ".github/x.md", "confidence": "high", "why": "?"}' 'not a plain .md' "a dot-folder"
refused '{"repo": "film", "path": "notes/x.yaml", "confidence": "high", "why": "?"}' 'not a plain .md' "not markdown"
refused '{"repo": "absent", "path": "x.md", "confidence": "high", "why": "?"}' 'not a repo on this Mac' "a repo not cloned here"
refused '{"repo": "site", "path": "x.md", "confidence": "high", "why": "?"}' 'not a repo on this Mac' "a published repo, though cloned"
refused '{"repo": "twin", "path": "x.md", "confidence": "high", "why": "?"}' 'not a repo on this Mac' "a public twin, though cloned"
refused '{"repo": null, "path": "", "confidence": "low", "why": "two projects"}' 'left for a human' "no single home"
refused 'no json at all' 'no decision' "a reply without a decision"
refused '{"repo": ["film", "vault"], "path": "x.md", "confidence": "high", "why": "?"}' 'not one repo' "a list for a repo (W3)"
refused '{"repo": "film", "path": "rules/memo.md", "confidence": "high", "why": "?"}' 'instructions or code' "a folder Claude Code loads (W1)"
refused '{"repo": "film", "path": "notes/CLAUDE.md", "confidence": "high", "why": "?"}' 'instructions or code' "a CLAUDE.md anywhere (W1)"
refused '{"repo": "vault", "path": "me/memo.md", "confidence": "high", "why": "?"}' 'instructions or code' "the config's own deny list (W1)"
refused '{"repo": "vault", "path": "outputs/memo.md", "confidence": "high", "why": "?"}' 'gitignored\|not a folder git tracks' "a gitignored vault folder (W2)"
refused '{"repo": "film", "path": "notes/Feedback-R1.md", "confidence": "high", "why": "?"}' 'only by case' "a name that differs only by case (R6)"
refused '{"repo": "film", "path": "notes/a\u000ab.md", "confidence": "high", "why": "?"}' 'control character' "a newline in the path"
git -C "$P/film" fetch -q origin
( cd "$P/film" && git checkout -q -b tmp origin/main && echo d > notes/live-doc.md && git add -A && git commit -qm doc \
  && git push -q origin HEAD:refs/heads/claude/other/2026-09-29-doc -f && git checkout -q main ) 2>/dev/null
git -C "$P/film" fetch -q origin
refused '{"repo": "film", "path": "notes/live-doc.md", "confidence": "high", "why": "?"}' 'being written on' "a file another claude/* branch adds (R5)"
f=$(grep -l 'route: film/drafts/x.md' "$T/out"/*.md | head -1)
grep -q '^## Bin' "$f"; check $? 0 "  a note left in the inbox is the whole note"
check "$(branches)" "2" "  and no refused route pushed anything (theirs + the one filed)"

route '{"repo": "vault", "path": "ventures/idea.md", "confidence": "high", "why": "venture"}'
out=$(memo vault)
[ -f "$P/vault/ventures/idea.md" ]; check $? 0 "the vault takes a file directly"

route '{"repo": "film", "path": "notes/feedback-r3.md", "confidence": "high", "why": "cut feedback"}'
out=$(SPARKS_LAND=pr memo pr)
git -C "$P/film" fetch -q origin main
git -C "$P/film" cat-file -e origin/main:notes/feedback-r3.md 2>/dev/null && r=0 || r=1; check $r 1 '"land": "pr": main is not touched'
check "$(branches)" "3" "  the branch is pushed (beside the other session's)"
f=$(ls -t "$T/out"/*.md | head -1)
grep -q 'waiting for a merge' "$f"; check $? 0 "  and the inbox note says it waits for a merge"

table "$HAIKU" '{"kind": "generate", "provider": "off", "when_off": "skip"}'
n0=$(grep -c 'Read,Glob,Grep' "$T/claude-calls.txt")
refused '{"repo": "film", "path": "notes/off.md", "confidence": "high", "why": "x"}' 'routing is off in settings/models.json' "routing off + skip in the table"
check "$(grep -c 'Read,Glob,Grep' "$T/claude-calls.txt")" "$n0" "  no routing call; the note lands unrouted"
table "$HAIKU"

echo "a crash (R2): a landing recorded before a crash is recognised, not filed twice"
route '{"repo": "film", "path": "notes/elsewhere.md", "confidence": "high", "why": "a different guess"}'
say -o "$T/in/crashed.aiff" "a memo whose pass crashed after the merge" 2>/dev/null
k=$(python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()[:16])" "$T/in/crashed.aiff")
python3 - "$T/state.json" "$k" <<'EOF'
import json, sys
s = json.load(open(sys.argv[1])); s[sys.argv[2]] = {"landing": {"repo": "film", "path": "notes/feedback-r2.md"}}
json.dump(s, open(sys.argv[1], "w"))
EOF
before=$(branches)
out=$(python3 "$B/sparks")
check "$(echo "$out" | grep -c '→ film/notes/feedback-r2.md')" "1" "picked up on the recorded path, which is already on main"
check "$(branches)" "$before" "  no second branch, no routing call's new guess"

echo "tool limits (R1)"
grep 'Read,Glob,Grep' "$T/claude-calls.txt" | tail -1 | grep -q -- '--tools Read,Glob,Grep'; check $? 0 "the routing call's tool set is Read, Glob, Grep"
grep 'Read,Glob,Grep' "$T/claude-calls.txt" | tail -1 | grep -q -- '--permission-mode dontAsk'; check $? 0 "  and it cannot ask for more"
grep 'Read,Glob,Grep' "$T/claude-calls.txt" | tail -1 | grep -q 'Read(\*\*/.env\*)'; check $? 0 "  and it may not read a .env"
grep -v 'Read,Glob,Grep' "$T/claude-calls.txt" | grep -q -- '--tools  --allowedTools\|--tools --allowedTools'; check $? 0 "the note call has no tools at all"
check "$(grep -c -- '--strict-mcp-config' "$T/claude-calls.txt")" "$(grep -c -- '--model' "$T/claude-calls.txt")" "  and neither call loads connectors"

echo "session start, host, lock"
say -o "$T/in/elsewhere.aiff" "a memo on the wrong Mac" 2>/dev/null
check "$(SPARKS_HOST=nowhere python3 "$B/sparks" -v)" "" "another host: does nothing, says nothing"
[ -f "$T/in/elsewhere.aiff" ]; check $? 0 "  and leaves the audio alone"
rm "$T/in/elsewhere.aiff"
check "$(python3 "$B/sparks" --session-start)" "" "session start, empty inbox: silent"
sleep 2   # the case above spawned a detached pass; let it finish
say -o "$T/in/weekly.aiff" "a memo while the weekly loop runs" 2>/dev/null
CLAUDE_CODE_SESSION_ATTENDED=0 python3 "$B/sparks" --session-start; sleep 2
[ -f "$T/in/weekly.aiff" ]; check $? 0 "an unattended session (claude -p, the weekly loop) never starts a pass"
rm "$T/in/weekly.aiff"
route '{"repo": null, "path": "", "confidence": "low", "why": "test"}'
say -o "$T/in/bg.aiff" "a memo for the background" 2>/dev/null

start=$(date +%s); out=$(python3 "$B/sparks" --session-start); took=$(( $(date +%s) - start ))
check "$out" "" "session start with audio: prints nothing"
[ "$took" -le 2 ]; check $? 0 "  and returns at once"
for i in $(seq 1 30); do [ -z "$(ls "$T/in")" ] && break; sleep 0.5; done
sleep 0.5
check "$(grep -c 'bg.aiff' "$T/memo.log")" "1" "  the detached pass filed it and logged it"
say -o "$T/in/locked.aiff" "a memo while locked" 2>/dev/null
python3 -c "import fcntl,sys,time; f=open(sys.argv[1],'w'); fcntl.flock(f, fcntl.LOCK_EX); time.sleep(4)" "${SPARKS_STATE%.json}.lock" &
sleep 1
check "$(python3 "$B/sparks" -v | grep -c 'another sparks')" "1" "a second pass while one runs: steps aside"
[ -f "$T/in/locked.aiff" ]; check $? 0 "  and leaves the audio for the next"
wait

echo "ideas: one note per topic, the words with the audio (docs/record/ideas-pipeline-2026-10-02.md)"
I="$T/ideas"; mkdir -p "$I/in" "$I/notes" "$I/archive"
cat > "$T/bin/claude" <<'EOF2'
#!/bin/sh
echo "$@" > "$TMPDIR_CAPTURE/claude-args.txt"
printf '# Dinner talk about two things\n\n## Summary\nTwo ideas.\n\n## Topics\n### A tool for film editors\nTags: Product, film\nEditors want a faster cut.\n\n### Birthday party in a barn\nTags: party\nA barn, forty people.\n'
EOF2
printf '#!/bin/sh\necho " Verbatim words of the conversation."\n' > "$T/bin/whisper"
printf '#!/bin/sh\necho "$@" > "$TMPDIR_CAPTURE/publish-args.txt"\n' > "$T/bin/publish"
chmod +x "$T/bin/claude" "$T/bin/whisper" "$T/bin/publish"
cat > "$I/ideas.json" <<EOF2
{ "inbox": "$I/in", "notes": "$I/notes", "archive": "$I/archive", "state": "$I/state.json",
  "split": "topics", "transcript": "archive", "publish": "vault", "source": "conversation",
  "label": "Ideas", "commit": false }
EOF2
ideas() { env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE SPARKS_CONFIG="$I/ideas.json" \
  PUBLISH_BIN="$T/bin/publish" python3 "$B/sparks" "$@"; }
say -o "$I/in/talk.aiff" "two ideas over dinner" 2>/dev/null
out=$(ideas)
check "$(ls "$I/notes" | wc -l | tr -d ' ')" "2" "two topics: two notes"
check "$(echo "$out" | grep -o '[a-z-]*\.md' | sed 's/^[0-9-]*//' | tr '\n' ' ')" "a-tool-for-film-editors.md birthday-party-in-a-barn.md " "  in the order Claude gave them"
f=$(ls "$I/notes"/*film-editors.md)
grep -q '^status: new$' "$f"; check $? 0 "  each starts as status: new"
grep -q '^tags: \[product, film\]$' "$f"; check $? 0 "  the Tags line becomes frontmatter, lowercased"
grep -q '^Tags:' "$f"; check $? 1 "  and leaves the body"
grep -q '^from: "Dinner talk about two things"$' "$f"; check $? 0 "  the recording's title is kept, quoted for YAML"
grep -q '^source: conversation$' "$f"; check $? 0 "  the config names the source"
[ "$(tail -3 "$f" | head -1)" = "## Your notes" ]; check $? 0 "  it ends with an empty ## Your notes"
grep -rq 'Verbatim words' "$I/notes"; check $? 1 "  no verbatim transcript in any note"
grep -q 'Verbatim words' "$I/archive/talk.aiff.txt"; check $? 0 "  it sits beside the audio in the archive"
[ -f "$I/archive/talk.aiff" ] && [ -z "$(ls "$I/in")" ]; check $? 0 "  the audio moved out of the inbox"
grep -q -- '--vault' "$T/publish-args.txt" && [ "$(tr ' ' '\n' < "$T/publish-args.txt" | grep -c '\.md$')" = 2 ]
check $? 0 "  publish --vault gets both notes"
grep -q 'Read,Glob,Grep' "$T/claude-args.txt"; check $? 1 "  no routing call"
say -o "$I/in/talk2.aiff" "more ideas" 2>/dev/null
ideas >/dev/null
grep -q 'reuse these where they fit: film, party, product' "$T/claude-args.txt"; check $? 0 "the next prompt offers the tags in use"
grep -q 'By:' "$T/claude-args.txt"; check $? 1 "  a config with no speaker asks for no By: line"
[ -f "$I/state.lock" ]; check $? 0 "  each config has its own lock"
printf '#!/bin/sh\nprintf "# Unintelligible recording\\n\\n## Summary\\nNoise.\\n\\n## Topics\\n"\n' > "$T/bin/claude"
n=$(ls "$I/notes" | wc -l | tr -d ' ')
say -o "$I/in/noise.aiff" "noise" 2>/dev/null
ideas >/dev/null
check "$(ls "$I/notes" | wc -l | tr -d ' ')" "$n" "an empty Topics section files no note"
[ -f "$I/archive/noise.aiff.txt" ]; check $? 0 "  but the audio and transcript are archived"
printf '#!/bin/sh\nprintf "# Drifted reply\\n\\n## Summary\\nOne idea.\\n\\n## Topics\\n**A boat club**\\nTags: boats\\nSaid in prose.\\n"\n' > "$T/bin/claude"
say -o "$I/in/drift.aiff" "drift" 2>/dev/null
ideas >/dev/null
check "$(ls "$I/notes" | wc -l | tr -d ' ')" "$((n + 1))" "a Topics section without ### is filed whole, not lost"

echo "ideas: a written note (a .txt in the inbox) takes the same path, minus whisper"
cat > "$T/bin/claude" <<'EOF2'
#!/bin/sh
echo "$@" > "$TMPDIR_CAPTURE/claude-args.txt"
printf '# A rooftop cinema\n\n## Summary\nOne idea.\n\n## Topics\n### Rooftop cinema\nTags: party\nFilms on the roof in summer.\n'
EOF2
printf '#!/bin/sh\necho called > "$TMPDIR_CAPTURE/whisper-called.txt"; exit 1\n' > "$T/bin/whisper"
chmod +x "$T/bin/claude" "$T/bin/whisper"; rm -f "$T/whisper-called.txt"
n=$(ls "$I/notes" | wc -l | tr -d ' ')
printf 'Rooftop cinema\nFilms on the roof every Friday in July.\n' > "$I/in/2026-10-07-2210.txt"
out=$(WHISPER_MODEL="$T/no-model.bin" ideas)
check "$(ls "$I/notes" | wc -l | tr -d ' ')" "$((n + 1))" "a .txt in the inbox: one note, with no whisper model installed"
[ -f "$T/whisper-called.txt" ]; check $? 1 "  whisper is never called"
grep -q 'Films on the roof every Friday' "$T/claude-args.txt"; check $? 0 "  the note's words are the transcript"
grep -q 'a written note, not a recording' "$T/claude-args.txt"; check $? 0 "  and the prompt is told it is written"
f=$(ls "$I/notes"/*rooftop-cinema.md)
grep -q '^source: written note$' "$f"; check $? 0 "  source: written note"
grep -q '^size:' "$f"; check $? 1 "  no size line"
grep -q '^audio: archive/2026-10-07-2210.txt$' "$f"; check $? 0 "  audio: names the archived original (bin/redactions reads it)"
[ -f "$I/archive/2026-10-07-2210.txt" ] && [ ! -f "$I/archive/2026-10-07-2210.txt.txt" ] && [ -z "$(ls "$I/in")" ]
check $? 0 "  the note moves to the archive, with no second copy as a transcript"
n=$(ls "$I/notes" | wc -l | tr -d ' '); rm -f "$T/claude-args.txt"
printf 'Rooftop cinema\nFilms on the roof every Friday in July.\n' > "$I/in/2026-10-07-2215.txt"
out=$(WHISPER_MODEL="$T/no-model.bin" ideas)
check "$(ls "$I/notes" | wc -l | tr -d ' ')" "$n" "the same note saved twice: filed once"
[ ! -f "$T/claude-args.txt" ]; check $? 0 "  with no second shaping call"
[ -z "$(ls "$I/in")" ] && [ -f "$I/archive/2026-10-07-2215.txt" ]; check $? 0 "  and the copy is archived, not left in the inbox"
printf '{\\rtf1\\ansi Rich rooftop words.}' > "$I/in/rich.rtf"
WHISPER_MODEL="$T/no-model.bin" ideas >/dev/null
grep -q 'Rich rooftop words' "$T/claude-args.txt" && ! grep -q 'rtf1' "$T/claude-args.txt"
check $? 0 "an .rtf is read as plain text through textutil"
cp "$T/bin/claude" "$T/claude.keep"  # the tests below this block run on the rooftop reply again
cat > "$T/bin/claude" <<'EOF2'
#!/bin/sh
echo "$@" > "$TMPDIR_CAPTURE/claude-args.txt"
printf '# Nothing to say\n\n## Summary\nToo vague.\n\n## Topics\n'
EOF2
chmod +x "$T/bin/claude"
n=$(ls "$I/notes" | wc -l | tr -d ' ')
printf 'Would be cool\n' > "$I/in/2026-10-07-212949-1.txt"
WHISPER_MODEL="$T/no-model.bin" ideas >/dev/null
check "$(ls "$I/notes" | wc -l | tr -d ' ')" "$((n + 1))" "a written note the reply finds no topic in is still one note"
f=$(ls "$I/notes"/*would-be-cool.md 2>/dev/null)
grep -q '^Would be cool$' "$f" 2>/dev/null; check $? 0 "  its own words are the body"
grep -q 'never leave `## Topics` empty' "$T/claude-args.txt"; check $? 0 "  and the prompt says a written note is never empty"
python3 - "$I/state.json" <<'PY'
import json, sys
p = sys.argv[1]; s = json.load(open(p))
for v in s.values():
    if isinstance(v, dict) and v.get("file") == "2026-10-07-212949-1.txt":
        v["note"] = "(empty)"  # as the runner before the floor left it
json.dump(s, open(p, "w"))
PY
n=$(ls "$I/notes" | wc -l | tr -d ' ')
printf 'Would be cool\n' > "$I/in/2026-10-07-214759-1.txt"
out=$(WHISPER_MODEL="$T/no-model.bin" ideas)
check "$(ls "$I/notes" | wc -l | tr -d ' ')" "$((n + 1))" "a written note once filed as nothing is filed when saved again, not archived as a copy"
printf '#!/bin/sh\nprintf "# Nothing to say\\n\\n## Summary\\nToo vague.\\n\\n## Topics\\n_(none)_\\n\\n## Bin\\n- nothing\\n"\n' > "$T/bin/claude"
printf '# Rooftop bar\nBy: Friday we need a venue\nTags: maybe later\n' > "$I/in/2026-10-07-2300-1.md"
WHISPER_MODEL="$T/no-model.bin" ideas >/dev/null
f=$(ls "$I/notes"/*-rooftop-bar.md 2>/dev/null)
[ -n "$f" ] && grep -q '^# Rooftop bar$' "$f"; check $? 0 "a reply whose Topics holds no ### still files the note's words, under its first line"
grep -q '^By: Friday we need a venue$' "$f" && grep -q '^Tags: maybe later$' "$f" && grep -q '^tags: \[\]$' "$f"
check $? 0 "  the owner's By: and Tags: lines stay words, not metadata"
grep -q 'Too vague' "$f"; check $? 1 "  and the reply's own prose is not what is filed"
printf 'Idea intro\n## Details\nsecond part that must not vanish\n### Sub one\nTags: secret-tag\nbody one\n' > "$I/in/2026-10-07-2310-1.md"
WHISPER_MODEL="$T/no-model.bin" ideas >/dev/null
f=$(ls "$I/notes"/*-idea-intro.md 2>/dev/null)
check "$(echo "$f" | grep -c .)" "1" "a .md note with ## and ### lines stays one note"
grep -q 'second part that must not vanish' "$f" && grep -q '^\\### Sub one$' "$f" && grep -q '^tags: \[\]$' "$f"
check $? 0 "  every word kept, its heading lines escaped, its Tags: line still words"
cp "$T/claude.keep" "$T/bin/claude"
printf '.' > "$I/in/.icloud-placeholder.txt"
check "$(ideas --dry-run)" "" "a dot-file in the inbox is not a note"
printf 'stray\n' > "$T/in/stray.txt"
python3 "$B/sparks" --dry-run | grep -q stray; check $? 1 "a routed (unsplit) inbox takes no written note"
rm -f "$T/in/stray.txt"
rm -f "$I/in/.icloud-placeholder.txt"
say -o "$I/in/mixed.aiff" "audio again" 2>/dev/null
printf 'A written idea beside it\n' > "$I/in/beside.md"
out=$(WHISPER_MODEL="$T/no-model.bin" ideas --limit 1)
echo "$out" | grep -q 'brew install whisper-cpp'; check $? 0 "a recording with no model still says how to fix it"
[ -f "$I/in/mixed.aiff" ] && [ ! -f "$I/in/beside.md" ]; check $? 0 "  it waits, and the .md beside it is filed anyway, --limit 1 or not"
rm -f "$I/in/mixed.aiff"
printf '#!/bin/sh\necho " Verbatim words of the conversation."\n' > "$T/bin/whisper"; chmod +x "$T/bin/whisper"
printf '{"also": ["ideas/ideas.json"]}' > "$T/main.json"
say -o "$I/in/talk3.aiff" "ideas from the session start" 2>/dev/null
# HOME is a scratch one: main.json names no state, so the chain would take the real
# ~/.cache/sparks/chain.lock — on the always-on Mac the live job's (review, 2026-10-08).
mkdir -p "$T/chainhome"
env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE SPARKS_CONFIG="$T/main.json" \
  HOME="$T/chainhome" PUBLISH_BIN="$T/bin/publish" python3 "$B/sparks" --session-start
for i in $(seq 1 30); do [ -z "$(ls "$I/in")" ] && break; sleep 0.5; done
[ -f "$I/archive/talk3.aiff" ]; check $? 0 "session start runs every \"also\" config, even with no inbox of its own"
say -o "$I/in/talk4.aiff" "a second chain" 2>/dev/null
python3 -c 'import fcntl, sys, time; f = open(sys.argv[1], "w"); fcntl.flock(f, fcntl.LOCK_EX); time.sleep(4)' "$T/chain.lock" &
sleep 0.5
env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_ROUTE SPARKS_CONFIG="$T/main.json" SPARKS_STATE="$T/x.json" \
  PUBLISH_BIN="$T/bin/publish" python3 "$B/sparks" --chain
[ -f "$I/in/talk4.aiff" ]; check $? 0 "  a second chain while one runs leaves the inbox alone"
wait
grep -rq '^by:' "$I/notes"; check $? 1 "a config with no speaker writes no by: line"

echo "Apple Notes: the pass exports a settled note from one folder, files it, moves it (2026-10-08)"
# A stub osascript plays Notes from $T/notes.json: folders by name, each a list of notes. It logs
# every call's mode and folder names; $T/osa.mode "deny" answers like a missing Automation grant,
# "nomove" accepts the move and moves nothing.
cat > "$T/bin/osascript" <<'EOF2'
#!/usr/bin/env python3
import json, os, sys
cap = os.environ["TMPDIR_CAPTURE"]; a = sys.argv[1:]
assert a[:2] == ["-l", "JavaScript"] and a[2] == "-e", a
mode, account, src, dst, ids = a[4], a[5], a[6], a[7], a[8:]
open(cap + "/osa-calls.txt", "a").write(" ".join([mode, account, src, dst] + ids) + "\n")
how = open(cap + "/osa.mode").read().strip() if os.path.exists(cap + "/osa.mode") else ""
if how == "deny":
    sys.stderr.write("execution error: Error: Not authorized to send Apple events to Notes. (-1743)\n"); sys.exit(1)
db = json.load(open(cap + "/notes.json"))
if mode == "move":
    if how != "nomove":
        for i in ids:
            n = next(x for x in db[src] if x["id"] == i)
            db[src].remove(n); db[dst].append(n)
        json.dump(db, open(cap + "/notes.json", "w"))
    print(json.dumps([x["id"] for x in db[src]]))
else:
    print(json.dumps(db[src]))
EOF2
chmod +x "$T/bin/osascript"
export OSASCRIPT_BIN="$T/bin/osascript"
N="$T/notesin"; mkdir -p "$N/in" "$N/notes" "$N/archive"
cat > "$N/c.json" <<EOF2
{ "inbox": "$N/in", "notes": "$N/notes", "archive": "$N/archive", "state": "$N/state.json",
  "split": "topics", "transcript": "archive", "source": "conversation", "commit": false,
  "apple_notes": {"account": "iCloud", "from": "_ideas", "to": "_ideas_filed", "settle_minutes": 10} }
EOF2
notes() { env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE SPARKS_CONFIG="$N/c.json" \
  WHISPER_MODEL="$T/no-model.bin" SPARKS_NOTES=1 python3 "$B/sparks" "$@"; }
ago() { python3 -c 'import datetime as d, sys; print((d.datetime.now(d.timezone.utc) - d.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%S.000Z"))' "$1"; }
in_folder() {  # $1 folder: the ids in it, space-separated
  python3 -c 'import json, sys; print(" ".join(x["id"].rsplit("/", 1)[1] for x in json.load(open(sys.argv[1]))[sys.argv[2]]))' "$T/notes.json" "$1"
}
cat > "$T/notes.json" <<EOF2
{ "_ideas": [
    {"id": "x-coredata://S/ICNote/p1", "created": "2026-10-07T21:05:00.000Z", "modified": "$(ago 60)", "locked": false,
     "text": "Rooftop cinema\nFilms on the roof every Friday in July."},
    {"id": "x-coredata://S/ICNote/p2", "created": "$(ago 3)", "modified": "$(ago 2)", "locked": false, "text": "Half an ide"},
    {"id": "x-coredata://S/ICNote/p3", "created": "$(ago 90)", "modified": "$(ago 90)", "locked": true, "text": ""}],
  "_ideas_filed": [],
  "Private": [{"id": "x-coredata://S/ICNote/p9", "created": "$(ago 900)", "modified": "$(ago 900)", "locked": false, "text": "PASSPORT 12345"}] }
EOF2
rm -f "$T/osa-calls.txt" "$T/osa.mode" "$T/claude-args.txt"
env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE SPARKS_CONFIG="$N/c.json" python3 "$B/sparks" >/dev/null
[ ! -f "$T/osa-calls.txt" ] && [ -z "$(ls "$N/in")" ]; check $? 0 "without SPARKS_NOTES=1 (only sextant-host sets it) Notes is never asked"
grep -q '"SPARKS_NOTES=1"' "$B/../launcher.c.in"; check $? 0 "  and the launcher template sets it"
out=$(notes --dry-run)
echo "$out" | grep -q '^would export from Notes: 2026-10-0[78]-[0-9]\{4\}-note-[0-9a-f]\{8\}\.txt$'; check $? 0 "--dry-run says which note it would export"
[ -z "$(ls "$N/in")" ] && ! grep -q '^move' "$T/osa-calls.txt"; check $? 0 "  and writes nothing, moves nothing"
n=$(ls "$N/notes" | wc -l | tr -d ' ')
out=$(notes)
check "$(ls "$N/notes" | wc -l | tr -d ' ')" "$((n + 1))" "a settled note in _ideas: one note filed"
grep -q 'Films on the roof every Friday' "$T/claude-args.txt" && grep -q 'a written note, not a recording' "$T/claude-args.txt"
check $? 0 "  its words are the transcript, shaped as a written note"
f=$(ls "$N/notes"/*.md | head -1)
grep -q '^source: written note$' "$f"; check $? 0 "  source: written note"
want=$(python3 -c 'import datetime as d; print(d.datetime(2026,10,7,21,5,tzinfo=d.timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M"))')
grep -q "^recorded: $want$" "$f"; check $? 0 "  recorded: is when the note was created ($want)"
check "$(in_folder _ideas_filed)" "p1" "  the note moved to _ideas_filed"
check "$(in_folder _ideas)" "p2 p3" "  a note edited in the last 10 min and a locked note stay in _ideas"
[ -z "$(ls "$N/in")" ] && ls "$N/archive" | grep -q -- '-note-[0-9a-f]\{8\}\.txt$'; check $? 0 "  the exported text is filed and archived, the inbox left empty"
grep -q 'Private\|p9' "$T/osa-calls.txt"; check $? 1 "  Notes is asked for no folder but the two named"
sed -n '/^NOTES_JXA/,/^"""/p' "$B/sparks" > "$T/jxa.txt"
# An allowlist, not a blocklist: every `notes` is src's, every `folders` is acc's `whose`.
[ -s "$T/jxa.txt" ] && [ -z "$(grep -o '[A-Za-z_]*\.notes' "$T/jxa.txt" | grep -v '^src\.notes$')" ] \
  && [ -z "$(grep -o '[A-Za-z_]*\.folders[.(]*[a-z]*' "$T/jxa.txt" | grep -v '^acc\.folders\.whose$')" ] \
  && ! grep -q "Application('Notes')\.\|\[.notes.\]\|\[.folders.\]" "$T/jxa.txt"
check $? 0 "  and the script never lists the account's notes or folders, nor reads the filed folder's notes"
rm -f "$T/osa-calls.txt" "$T/claude-args.txt"
notes >/dev/null
[ ! -f "$T/claude-args.txt" ] && ! grep -q '^move' "$T/osa-calls.txt"; check $? 0 "a second pass: nothing exported, nothing moved"

python3 - "$T/notes.json" "$(ago 30)" <<'EOF2'
import json, sys
d = json.load(open(sys.argv[1]))
d["_ideas"].append({"id": "x-coredata://S/ICNote/p4", "created": sys.argv[2], "modified": sys.argv[2],
                    "locked": False, "text": "Tiny library\nA shelf in the lobby."})
json.dump(d, open(sys.argv[1], "w"))
EOF2
echo nomove > "$T/osa.mode"; n=$(ls "$N/notes" | wc -l | tr -d ' ')
out=$(notes)
check "$(ls "$N/notes" | wc -l | tr -d ' ')" "$((n + 1))" "a move that does not happen: the note is still filed"
echo "$out" | grep -q 'did not move to _ideas_filed — the next pass tries the move again'; check $? 0 "  and the pass says the move failed"
rm -f "$T/osa.mode" "$T/claude-args.txt"; n=$(ls "$N/notes" | wc -l | tr -d ' ')
out=$(notes)
check "$(ls "$N/notes" | wc -l | tr -d ' ')" "$n" "  the next pass moves it without filing it again"
[ ! -f "$T/claude-args.txt" ]; check $? 0 "  with no shaping call"
echo "$out" | grep -q 'exported a note'; check $? 1 "  nor exporting it again"
check "$(in_folder _ideas_filed)" "p1 p4" "  and it is in _ideas_filed"

echo deny > "$T/osa.mode"
printf 'Dropped by hand\nA file in the inbox still files.\n' > "$N/in/hand.txt"; n=$(ls "$N/notes" | wc -l | tr -d ' ')
out=$(notes)
echo "$out" | grep -q 'Automation grant for sextant-host'; check $? 0 "Notes refuses (no Automation grant): the pass says which grant"
check "$(ls "$N/notes" | wc -l | tr -d ' ')" "$((n + 1))" "  and the inbox's own file is filed anyway"
out=$(notes --background --dry-run)
echo "$out" | grep -q 'Automation grant'; check $? 0 "  a dry run says it too"
ls "$N" | grep -q '^said-.*-notes-'; check $? 1 "  and spends no once-a-day mark the job's own pass needs"
rm -f "$T/osa.mode" "$T/osa-calls.txt"
printf 'No notes config\n' > "$I/in/plain.txt"; SPARKS_NOTES=1 ideas >/dev/null
[ ! -f "$T/osa-calls.txt" ]; check $? 0 "a config without apple_notes never asks Notes, even with SPARKS_NOTES=1"

cp "$T/bin/claude" "$T/claude.keep"
printf '#!/bin/sh\necho call >> "$TMPDIR_CAPTURE/claude-calls.txt"; exit 1\n' > "$T/bin/claude"
printf 'Stuck idea\nShaping fails for this one.\n' > "$N/in/stuck.txt"; rm -f "$T/claude-calls.txt"
notes --background >/dev/null; notes --background >/dev/null
check "$(wc -l < "$T/claude-calls.txt" | tr -d ' ')" 1 "a failed filing waits out SPARKS_RETRY_WAIT in the job: one try in two passes"
notes >/dev/null
check "$(wc -l < "$T/claude-calls.txt" | tr -d ' ')" 2 "  a run by hand tries it at once"
SPARKS_RETRY_WAIT=0 notes >/dev/null; rm -f "$T/claude-calls.txt"; notes --background >/dev/null
check "$(wc -l < "$T/claude-calls.txt" | tr -d ' ')" 1 "  and once the wait is over, the job tries again"
mv "$T/claude.keep" "$T/bin/claude"; rm -f "$N/in/stuck.txt"
unset OSASCRIPT_BIN

echo "whose idea: the inbox names the default speaker, the By: line names the topic's"
S="$T/shared"; mkdir -p "$S/in" "$S/notes" "$S/Shared drives/data/ideas/archive"
cat > "$T/bin/claude" <<'EOF2'
#!/bin/sh
echo "$@" > "$TMPDIR_CAPTURE/claude-args.txt"
printf '# Three ideas\n\n## Summary\nThree.\n\n## Topics\n### A boat club\nTags: boats\n**By:** Alex\nA club.\n\n### A night market\nTags: food\nStalls.\n\n### A choir\nTags: music\nBy: Bob\nSinging.\n\n### A garden\nTags: garden\nBy: `both`\nBeds.\n'
EOF2
chmod +x "$T/bin/claude"
cat > "$S/shared.json" <<EOF2
{ "inbox": "$S/in", "notes": "$S/notes", "archive": "$S/Shared drives/data/ideas/archive",
  "state": "$S/state.json", "split": "topics", "transcript": "archive", "source": "conversation",
  "speaker": "Sam", "people": ["sam", "alex"], "commit": false }
EOF2
say -o "$S/in/call.aiff" "three ideas" 2>/dev/null
env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE SPARKS_CONFIG="$S/shared.json" \
  python3 "$B/sparks" >/dev/null
grep -q 'sam, alex, both or unclear; unless the words show otherwise, the voice is sam' "$T/claude-args.txt"
check $? 0 "  the prompt names the people, the speaker first among them, and the default"
grep -q '^by: alex$' "$S/notes"/*boat-club.md; check $? 0 "  a By: line becomes by:, lowercased, bold or not"
grep -q '^By:' "$S/notes"/*boat-club.md; check $? 1 "  and leaves the body"
grep -q '^by: sam$' "$S/notes"/*night-market.md; check $? 0 "  no By: line: the inbox's speaker"
grep -q '^by: unclear$' "$S/notes"/*choir.md; check $? 0 "  a name not in people: unclear"
grep -q '^By: Bob$' "$S/notes"/*choir.md; check $? 0 "  and its line stays, for whoever corrects it"
grep -q '^by: both$' "$S/notes"/*garden.md; check $? 0 "  a name in backticks still counts"
grep -q '^audio: data/ideas/archive/call.aiff$' "$S/notes"/*boat-club.md; check $? 0 "  audio: names the shared drive it went to"
label() { python3 -c 'import importlib.machinery as m, importlib.util as u, sys; from pathlib import Path
l = m.SourceFileLoader("sparks", sys.argv[1]); r = u.module_from_spec(u.spec_from_loader("sparks", l))
l.exec_module(r); print(r.archive_label(Path(sys.argv[2])))' "$B/sparks" "$1"; }
check "$(label "/Users/x/Library/Mobile Documents/com~apple~CloudDocs/vault/ideas/archive/a.m4a")" \
  "iCloud Drive/vault/ideas/archive/a.m4a" "  audio: names iCloud Drive when it went there"
check "$(label "/Users/x/projects/audio-archive/a.m4a")" "audio-archive/a.m4a" "  and an archive elsewhere keeps <folder>/<file>"

echo "a recording filed but never archived: the next run only moves it"
rm -f "$I/in"/*; say -o "$I/in/retry.aiff" "filed already" 2>/dev/null
python3 -c 'import importlib.machinery as m, importlib.util as u, json, sys; from pathlib import Path
l = m.SourceFileLoader("sparks", sys.argv[1]); r = u.module_from_spec(u.spec_from_loader("sparks", l)); l.exec_module(r)
st = json.loads(Path(sys.argv[2]).read_text()); st[r.digest(Path(sys.argv[3]))] = {"file": "retry.aiff", "note": "x.md", "archived": False}
Path(sys.argv[2]).write_text(json.dumps(st))' "$B/sparks" "$I/state.json" "$I/in/retry.aiff"
rm -f "$T/claude-args.txt"; n=$(ls "$I/notes" | wc -l | tr -d ' ')
ideas >/dev/null
[ -f "$I/archive/retry.aiff" ] && [ ! -f "$I/in/retry.aiff" ]; check $? 0 "  the audio moves to the archive"
[ ! -f "$T/claude-args.txt" ]; check $? 0 "  with no new Claude call"
check "$(ls "$I/notes" | wc -l | tr -d ' ')" "$n" "  and no duplicate note"

echo "the watcher: what to watch, and Whisper's VAD"
out=$(env -u SPARKS_IN SPARKS_CONFIG="$T/main.json" python3 "$B/sparks" --inboxes)
check "$out" "$I/in" "--inboxes lists every also config's inbox"
printf '#!/bin/sh\necho "$@" > "$TMPDIR_CAPTURE/whisper-args.txt"\necho " words"\n' > "$T/bin/whisper"; chmod +x "$T/bin/whisper"
touch "$T/vad.bin"
say -o "$I/in/vad.aiff" "vad" 2>/dev/null
WHISPER_VAD="$T/vad.bin" ideas >/dev/null
grep -q -- "--vad -vm $T/vad.bin" "$T/whisper-args.txt"; check $? 0 "  WHISPER_VAD turns on Whisper's voice detection"
say -o "$I/in/novad.aiff" "no vad" 2>/dev/null
WHISPER_VAD="$T/missing.bin" ideas >/dev/null
grep -q -- "--vad" "$T/whisper-args.txt"; check $? 1 "  and a missing model leaves it off"

echo "redaction (docs/idea-redaction-2026-10-04.md): a fake TypeSafe server, a stub shaping call"
# The fake flags a sentence that mentions a hospital (p 0.9, category health) and nothing else;
# $T/jev.mode "error" answers HTTP 400. The stub claude writes what it was asked to shape and echoes
# the transcript's markers into the first topic ($T/shape.mode "invent" adds one nobody issued).
cat > "$T/fake_jev.py" <<'EOF2'
import json, os, sys, http.server
T = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        qs = body["questions"]
        with open(os.path.join(T, "jev-requests.jsonl"), "a") as f:
            f.write(json.dumps({"n": len(qs), "types": sorted({q["type"] for q in qs.values()})}) + "\n")
        mode = open(os.path.join(T, "jev.mode")).read().strip() if os.path.exists(os.path.join(T, "jev.mode")) else ""
        if mode == "error":
            out = json.dumps({"detail": [{"loc": ["body"], "msg": "refused by the fake"}]}).encode()
            self.send_response(400); self.send_header("Content-Type", "application/json"); self.end_headers()
            self.wfile.write(out); return
        ans = {}
        for k, q in qs.items():
            hit = "hospital" in q["instructions"]
            if q["type"] == "noul":
                ans[k] = {"type": "noul", "noul": 0.9 if hit else 0.05}
            else:
                c = "health" if hit else list(q["criteria"])[0]
                ans[k] = {"type": "choice", "choice": c, "probabilities": {c: 0.8}, "confidence": 0.5}
        out = json.dumps({"model": "jev-1.13.0", "answers": ans, "usage": {"input_tokens": 1000}}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(out)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(T, "jev.port"), "w").write(str(s.server_address[1]))
s.serve_forever()
EOF2
python3 "$T/fake_jev.py" "$T" & FAKE=$!
trap 'kill $FAKE 2>/dev/null; wait $FAKE 2>/dev/null; rm -rf "$T"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$T/jev.port" ] && break; sleep 0.2; done
export TYPESAFE_BASE_URL="http://127.0.0.1:$(cat "$T/jev.port")" TYPESAFE_API_KEY=sk-test-fake \
       JEV_LOG="$T/jev.jsonl" GATE_LOG="$T/gate.jsonl"
cat > "$T/bin/claude" <<'EOF2'
#!/usr/bin/env python3
import os, re, sys
T = os.environ["TMPDIR_CAPTURE"]
a = sys.argv[1:]
p = a[a.index("-p") + 1]
open(os.path.join(T, "shape-input.txt"), "w").write(p)
marks = re.findall(r"\[redacted: [a-z-]+ · [a-z0-9]{6}\]", p.split("Transcript:")[-1])
mode = open(os.path.join(T, "shape.mode")).read().strip() if os.path.exists(os.path.join(T, "shape.mode")) else ""
extra = " [redacted: health · zzzzzz]" if mode == "invent" else ""
if mode == "empty":  # a written note the reply finds no topic in
    print("# Nothing here\n\n## Summary\nVague.\n\n## Topics\n"); sys.exit(0)
print(("" if mode == "notitle" else "# Editors and a timeline\n\n") + "## Summary\nA tool.\n\n## Topics\n### A tool for editors\nTags: product\n"
      "Editors want a timeline. " + " ".join(marks) + extra + "\n\n### A timeline view\nTags: product\n"
      "The tool needs a timeline.\n")
EOF2
printf '#!/bin/sh\ntouch "$TMPDIR_CAPTURE/whisper-ran"\ncat "$TMPDIR_CAPTURE/red-transcript.txt"\n' > "$T/bin/whisper"
chmod +x "$T/bin/claude" "$T/bin/whisper"
echo "We could build a tool for editors. My father was in the hospital last week. Call me at 0123456789 tomorrow. The tool needs a timeline." > "$T/red-transcript.txt"
D="$T/red"; mkdir -p "$D/in" "$D/notes" "$D/archive"
redcfg() {  # $1 the redact_approved value
  printf '{ "inbox": "%s", "notes": "%s", "archive": "%s", "state": "%s", "split": "topics", "transcript": "archive", "publish": "vault", "source": "conversation", "label": "Ideas", "speaker": "sam", "people": ["sam"], "commit": false, "redact_approved": %s }\n' \
    "$D/in" "$D/notes" "$D/archive" "$D/state.json" "$1" > "$D/red.json"
}
redcfg '{"typesafe": "test: the fake server only"}'
cat > "$T/models.json" <<'EOF2'
{"defaults": {"claude": {"model": "opus"}, "jev": {"model": "jev-latest", "threshold": 0.5}},
 "sites": {"sparks.shape": {"kind": "generate", "provider": "claude"},
           "sparks.route": {"kind": "generate", "provider": "claude"},
           "sparks.redact": {"kind": "classify", "provider": "jev", "threshold": 0.3, "when_off": "fail"}}}
EOF2
red() { env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE SPARKS_CONFIG="$D/red.json" \
  PUBLISH_BIN="$T/bin/publish" python3 "$B/sparks" "$@"; }
reds() { env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE PUBLISH_BIN="$T/bin/publish" \
  python3 "$B/redactions" --config "$D/red.json" "$@"; }
say -o "$D/in/Home Street 12.aiff" "a recording about a tool" 2>/dev/null
out=$(red)
check "$(echo "$out" | grep -c '^✓')" "1" "a redacting config files the recording"
grep -q 'hospital' "$T/shape-input.txt"; check $? 1 "  a flagged sentence never reaches the shaping call"
grep -q '0123456789' "$T/shape-input.txt"; check $? 1 "  nor a 10-digit number Jev did not flag (the regex layer)"
grep -q 'We could build a tool for editors.' "$T/shape-input.txt"; check $? 0 "  the rest of the transcript does"
grep -q 'keep its marker verbatim' "$T/shape-input.txt"; check $? 0 "  and the prompt carries the marker rule"
shaped() { python3 -c 'import sys; print(open(sys.argv[1]).read().split("Transcript:")[-1])' "$T/shape-input.txt"; }
check "$(shaped | grep -o '\[redacted: [a-z-]* · [a-z0-9]*\]' | sed 's/ · .*//' | sort | tr '\n' ' ')" \
  "[redacted: health [redacted: secret " "  one marker per flagged sentence, health and secret"
ids=$(shaped | grep -o '· [a-z0-9]\{6\}\]' | tr -d '·] ' | sort -u)
check "$(echo "$ids" | grep -c '^[abcdefghjkmnpqrstuvwxyz23456789]\{6\}$')" "2" "  two distinct ids from the 31-letter alphabet"
side=$(ls "$D/archive"/*.redactions.json 2>/dev/null | head -1)
[ -n "$side" ]; check $? 0 "  a sidecar sits in the archive"
grep -q 'hospital' "$side"; check $? 0 "  and holds the original sentence"
grep -q '"original_name": "Home Street 12.aiff"' "$side"; check $? 0 "  and the phone's file name"
a=$(ls "$D/archive" | grep '\.aiff$')
echo "$a" | grep -q '^[0-9]\{4\}-[0-9][0-9]-[0-9][0-9]-[0-9]\{4\}-[0-9a-f]\{8\}\.aiff$'; check $? 0 "  the audio is archived as <date>-<HHMM>-<key8> ($a)"
[ -f "$D/archive/$a.txt" ] && [ "$side" = "$D/archive/$a.redactions.json" ]; check $? 0 "  the verbatim .txt and the sidecar beside it"
grep -rq 'Home Street' "$D/notes"; check $? 1 "  no note names the place the phone named the file after"
grep -rq 'hospital\|0123456789' "$D/notes"; check $? 1 "  no note carries a hidden sentence"
check "$(grep -l '^redactions: pending$' "$D/notes"/*.md | wc -l | tr -d ' ')" "2" "  every note of the recording is redactions: pending"
grep -q '\[redacted: health · ' "$D/notes"/*a-tool-for-editors.md; check $? 0 "  the marker Claude kept is in the note"
grep -q 'hospital\|0123456789' "$T/gate.jsonl" "$T/jev.jsonl"; check $? 1 "  the gate's and Jev's logs carry no sentence"
check "$(sed -n 2p "$T/jev-requests.jsonl")" '{"n": 1, "types": ["choice"]}' "  the category call asks only about Jev's flag, not the regex hit"
grep -q 'redaction [0-9a-f]\{8\}: 4 sentences, 2 flagged' <<<"$out"; check $? 0 "  one log line: sentences, flagged, cost"

note1=$(ls "$D/notes"/*a-tool-for-editors.md)
hid=$(grep -o '\[redacted: health · [a-z0-9]*\]' "$note1" | sed 's/.* · //; s/\]//')
out=$(CLAUDECODE=1 reds show "$a"; echo "exit $?")
echo "$out" | grep -q 'own terminal'; check $? 0 "show refuses inside a Claude Code session (D2)"
echo "$out" | grep -q 'hospital'; check $? 1 "  and prints no original"
echo "$out" | grep -q 'exit 2'; check $? 0 "  exit 2, with the line to paste"
out=$(env -u CLAUDECODE -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE \
  python3 "$B/redactions" --config "$D/red.json" show "${a%.aiff}")
echo "$out" | grep -q 'hospital'; check $? 0 "show in the owner's terminal prints the hidden sentence"
echo "$out" | grep -q 'We could build a tool'; check $? 0 "  with the sentence before it"
out=$(reds list)
echo "$out" | grep -q "$a.*2 pending.*health 1, secret 1"; check $? 0 "list: the recording, its pending notes, a count per category"
cp "$note1" "$T/note1.bak"; sed -i '' 's/^Editors want a timeline\./Editors want a timeline, edited after filing./' "$note1"; rm -f "$T/shape-input.txt"
out=$(reds release "$hid" 2>&1; echo "exit $?")
echo "$out" | grep -q 'edited since filing'; check $? 0 "release refuses a note edited since filing"
[ ! -f "$T/shape-input.txt" ]; check $? 0 "  without a re-shape"
cp "$T/note1.bak" "$note1"; sed -i '' 's/^status: new$/status: kept/' "$note1"
out=$(reds release "$hid")
echo "$out" | grep -q 'released 1, 1 still hidden'; check $? 0 "release: one put back, one still hidden"
grep -q 'My father was in the hospital last week.' "$T/shape-input.txt"; check $? 0 "  the sentence is back in the re-shape's input"
grep -q '0123456789' "$T/shape-input.txt"; check $? 1 "  the one not released stays out"
[ -f "$note1" ]; check $? 0 "  the note keeps its file name"
grep -q '^status: kept$' "$note1"; check $? 0 "  and its status"
grep -q "^released: \[$hid\]$" "$note1"; check $? 0 "  and says what was released"
grep -q '^redactions: pending$' "$note1"; check $? 0 "  still pending: a sentence stays hidden"
grep -q "\"released\": \[" "$side" && grep -A1 '"released": \[' "$side" | grep -q "$hid"; check $? 0 "  the sidecar records the release"
out=$(reds release "$hid" 2>&1)
echo "$out" | grep -q 'already released'; check $? 0 "  a second release of the same id is said, not redone"
out=$(reds done "$a")
check "$(grep -l '^redactions: reviewed$' "$D/notes"/*.md | wc -l | tr -d ' ')" "2" "done: the recording's notes are redactions: reviewed"
echo "$(reds list)" | grep -q 'no recording has pending notes'; check $? 0 "  and list has nothing pending"

echo "redaction of a written note: its lines are its sentences, and ## Your notes is the owner's"
printf 'Rooftop cinema\nFilms every Friday in July\nTickets at the door\nMy father was in the hospital last week\nAsk the landlord\n' > "$D/in/2026-10-07-2230-1.txt"
out=$(WHISPER_MODEL="$T/no-model.bin" red)
grep -q 'redaction [0-9a-f]\{8\}: 5 sentences, 1 flagged' <<<"$out"; check $? 0 "a note with no stops splits at its line breaks"
grep -q 'hospital' "$T/shape-input.txt"; check $? 1 "  the flagged line never reaches the shaping call"
grep -q 'Films every Friday in July' "$T/shape-input.txt"; check $? 0 "  the other lines do"
grep -q 'a written note, not a recording' "$T/shape-input.txt"; check $? 0 "  and the prompt says it is written"
w=$(ls "$D/archive" | grep '^2026-.*\.txt$' | grep -v '\.aiff\.txt$')
[ -f "$D/archive/$w.redactions.json" ] && [ ! -f "$D/archive/$w.txt" ]; check $? 0 "  the sidecar sits beside the archived note, with no transcript copy"
out=$(env -u CLAUDECODE -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE \
  python3 "$B/redactions" --config "$D/red.json" show "$w")
echo "$out" | grep -q '… Tickets at the door$' && echo "$out" | grep -q '… Ask the landlord$'
check $? 0 "show reads context from the archived note itself: the lines before and after"
wn=$(grep -l "^audio: archive/$w$" "$D/notes"/*a-tool-for-editors*.md)
whid=$(grep -o '\[redacted: health · [a-z0-9]*\]' "$wn" | sed 's/.* · //; s/\]//')
printf 'Try it in the courtyard first.\n' >> "$wn"; rm -f "$T/shape-input.txt"
out=$(reds release "$whid" 2>&1)
echo "$out" | grep -q 'released 1, 0 still hidden'; check $? 0 "release does not count ## Your notes as an edit"
grep -q 'My father was in the hospital last week' "$T/shape-input.txt"; check $? 0 "  the hidden line is back in the re-shape's input"
grep -q 'Try it in the courtyard first.' "$wn"; check $? 0 "  and what the owner wrote there survives the re-shape"
grep -q 'a written note, not a recording' "$T/shape-input.txt"; check $? 0 "  the re-shape is told it is written too"
printf 'Quoted [redacted: health · r7f3ak] line\xe2\x80\xa8Second soft line\n' > "$D/in/2026-10-07-2240-1.txt"
out=$(WHISPER_MODEL="$T/no-model.bin" red)
check "$(echo "$out" | grep -c '^✓')" "1" "a note quoting a filed marker is filed, not refused as an invented id"
grep -q '(redacted: health · r7f3ak)' "$T/shape-input.txt"; check $? 0 "  the quoted marker reaches Claude disarmed"
grep -q 'redaction [0-9a-f]\{8\}: 2 sentences' <<<"$out"; check $? 0 "  a soft line break (U+2028) ends a sentence too"

echo "redaction of a written note the reply finds no topic in"
echo empty > "$T/shape.mode"
printf 'Gate idea\nMy father was in the hospital last week\nCall me at 0123456789 tomorrow\n' > "$D/in/2026-10-07-2250-1.txt"
out=$(WHISPER_MODEL="$T/no-model.bin" red)
en=$(echo "$out" | sed -n 's/^    \(.*\.md\)$/\1/p' | sed "s|^|$D/notes/|")
check "$(echo "$en" | grep -c .)" "1" "an empty reply to a redacted written note: one note, of the redacted words"
grep -q 'hospital' "$en" || grep -q '0123456789' "$en"; check $? 1 "  neither the flagged line nor the number reaches it"
grep -q '\[redacted: secret · ' "$en"; check $? 0 "  the number the regex layer finds is wrapped, as in any reply"
printf 'Room 123\n4567 guests\n' > "$D/in/2026-10-07-2255-1.txt"
out=$(WHISPER_MODEL="$T/no-model.bin" red)
rn=$(echo "$out" | sed -n 's/^    \(.*\.md\)$/\1/p' | sed "s|^|$D/notes/|")
grep -q '\[redacted: secret · ' "$rn" && ! grep -q '123 4567' "$rn"; check $? 0 "  digits only the joined lines make are wrapped too: wrap_secrets runs over the fallback"
grep -q '^# Room$' "$rn" && [ "$(grep -o 'redacted: secret · [a-z0-9]*' "$rn" | sort -u | wc -l | tr -d ' ')" = 1 ]
check $? 0 "  the heading is the first words no secret touches, and the number has one id"
ehid=$(grep -o '\[redacted: health · [a-z0-9]*\]' "$en" | sed 's/.* · //; s/\]//')
out=$(reds release "$ehid" 2>&1)
grep -q 'My father was in the hospital last week' "$en"; check $? 0 "  a release re-shaped to no topic still puts the line back"
rm -f "$T/shape.mode"

echo "redaction fails closed"
n=$(ls "$D/notes" | wc -l | tr -d ' ')
echo error > "$T/jev.mode"; rm -f "$T/shape-input.txt"
say -o "$D/in/two.aiff" "a second recording" 2>/dev/null
out=$(red)
echo "$out" | grep -q 'redaction failed.*HTTP 400.*audio kept'; check $? 0 "a Jev error: reported, audio kept"
[ -f "$D/in/two.aiff" ] && [ ! -f "$T/shape-input.txt" ]; check $? 0 "  the audio waits and nothing is shaped"
check "$(ls "$D/notes" | wc -l | tr -d ' ')" "$n" "  and nothing is filed"
rm -f "$T/jev.mode"; echo invent > "$T/shape.mode"
out=$(red)
echo "$out" | grep -q 'marker id the transcript did not (zzzzzz)'; check $? 0 "an invented marker id in the reply is refused"
[ -f "$D/in/two.aiff" ] && [ "$(ls "$D/notes" | wc -l | tr -d ' ')" = "$n" ]; check $? 0 "  the audio waits, nothing filed"
rm -f "$T/shape.mode"
redcfg '{}'; rm -f "$T/shape-input.txt"
out=$(red)
echo "$out" | grep -q "refused: data from sparks goes to typesafe only with"; check $? 0 "a config without the vendor's quote: the gate refuses (no sextant/source: the source is sparks)"
[ -f "$D/in/two.aiff" ] && [ ! -f "$T/shape-input.txt" ]; check $? 0 "  the audio waits, Claude sees nothing"
redcfg '{"typesafe": "test: the fake server only"}'
python3 - "$T/models.json" <<'EOF2'
import json, sys
t = json.load(open(sys.argv[1])); t["sites"]["sparks.redact"] = {"kind": "classify", "provider": "off", "when_off": "skip"}
json.dump(t, open(sys.argv[1], "w"))
EOF2
rm -f "$T/whisper-ran"
out=$(red)
echo "$out" | grep -q 'wait: sparks.redact is off'; check $? 0 "the redaction row off + skip: the pass says so"
[ ! -f "$T/whisper-ran" ] && [ -f "$D/in/two.aiff" ]; check $? 0 "  before any transcription, and the audio waits"
GATE_SPARKS_REDACT_PROVIDER=jev red >/dev/null
[ -f "$D/archive/$(ls "$D/archive" | grep -v "$a" | grep '\.aiff$' | head -1)" ] && [ ! -f "$D/in/two.aiff" ]; check $? 0 "  and with the row back on it is filed"

python3 - "$T/models.json" <<'EOF3'
import json, sys
t = json.load(open(sys.argv[1])); t["sites"]["sparks.redact"] = {"kind": "classify", "provider": "jev", "threshold": 0.3}
json.dump(t, open(sys.argv[1], "w"))
EOF3

echo "audit: a note filed before redaction"
cat > "$D/notes/old-idea.md" <<'EOF2'
---
source: conversation
recorded: 2026-09-30 10:00
audio: archive/old talk.m4a
status: new
tags: [product]
---

# An old idea

A club for boat owners. His wife spent a week in hospital. Fees could fund the dock.
EOF2
out=$(reds audit --dry-run "$D/notes/old-idea.md")
echo "$out" | grep -q 'would audit old-idea.md: 4 sentence'; check $? 0 "audit --dry-run counts the heading too, calls nothing"
grep -q '^redactions:' "$D/notes/old-idea.md"; check $? 1 "  and writes nothing"
out=$(reds audit "$D/notes/old-idea.md")
grep -q 'hospital' "$D/notes/old-idea.md"; check $? 1 "audit hides the sentence in the note"
grep -q 'A club for boat owners. \[redacted: health · [a-z0-9]\{6\}\] Fees could fund the dock.' "$D/notes/old-idea.md"; check $? 0 "  with a marker in its place, the rest untouched"
grep -q '^redactions: pending$' "$D/notes/old-idea.md"; check $? 0 "  and stamps it pending"
grep -q 'hospital' "$D/archive/old talk.m4a.redactions.json"; check $? 0 "  the original goes to a sidecar beside its audio"
aid=$(grep -o 'health · [a-z0-9]*' "$D/notes/old-idea.md" | sed 's/.* //')
rm -f "$T/shape-input.txt"; reds release "$aid" >/dev/null
grep -q 'His wife spent a week in hospital.' "$D/notes/old-idea.md" && [ ! -f "$T/shape-input.txt" ]
check $? 0 "  releasing an audited id puts it back in place, no re-shape"
grep -q '^redactions: reviewed$' "$D/notes/old-idea.md"; check $? 0 "  and nothing hidden is left: reviewed"
echo "trial (S2): the classifier over an archived transcript, nothing shaped"
echo "An old talk. Her mother is in hospital again. The dock needs a crane." > "$D/archive/old talk.m4a.txt"
rm -f "$D/archive/old talk.m4a.redactions.json" "$T/shape-input.txt"
out=$(reds trial "$D/archive/old talk.m4a.txt")
echo "$out" | grep -Eq '^✓ trial [0-9a-f]{8}: 3 sentences, 1 hidden \(health 1; 0 by the regex layer\)'; check $? 0 "trial: counts per category"
echo "$out" | grep -q 'old talk'; check $? 1 "  under its key: the audio name (the place) is not printed"
echo "$out" | grep -q 'hospital'; check $? 1 "  and never a sentence"
[ ! -f "$T/shape-input.txt" ]; check $? 0 "  nothing shaped"
out=$(env -u CLAUDECODE -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE \
  python3 "$B/redactions" --config "$D/red.json" show "old talk")
echo "$out" | grep -q 'Her mother is in hospital again.' && echo "$out" | grep -q 'An old talk.'; check $? 0 "  show reads the trial, with context"
out=$(reds trial "$D/archive/old talk.m4a.txt" 2>&1)
echo "$out" | grep -q 'exists — --force'; check $? 0 "  a second trial does not overwrite a sidecar"

echo "review fixes (2026-10-05)"
tid=$(python3 -c 'import json, sys; print(next(iter(json.load(open(sys.argv[1]))["ids"])))' "$D/archive/old talk.m4a.redactions.json")
rm -f "$T/shape-input.txt"; out=$(reds release "$tid" 2>&1)
echo "$out" | grep -q 'from a trial' && [ ! -f "$T/shape-input.txt" ]; check $? 0 "release of a trial id: refused before any shaping call"
printf '{"audio": "filed.m4a", "recorded": "2026-10-01 09:00", "ids": {}, "notes": {"x.md": "h"}, "released": []}\n' > "$D/archive/filed.m4a.redactions.json"
echo "A filed talk." > "$D/archive/filed.m4a.txt"
out=$(reds trial --force "$D/archive/filed.m4a.txt" 2>&1)
echo "$out" | grep -q 'a trial never replaces it' && grep -q '"x.md"' "$D/archive/filed.m4a.redactions.json"; check $? 0 "trial --force never replaces a filed sidecar"
rm -f "$D/archive/filed.m4a.redactions.json" "$D/archive/filed.m4a.txt"
printf -- '---\nsource: conversation\nstatus: new\n---\n\n# No audio\n\nHis wife spent a week in hospital.\n' > "$D/notes/no-audio.md"
out=$(reds audit "$D/notes/no-audio.md")
echo "$out" | grep -q 'no audio: line' && grep -q 'hospital' "$D/notes/no-audio.md"; check $? 0 "audit of a note with no audio: line writes nothing (no sidecar, no marker)"
rm -f "$D/notes/no-audio.md"
out=$(env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE SPARKS_CONFIG="$D/red.json" \
  PUBLISH_BIN="$T/bin/publish" python3 "$B/redactions" list)
echo "$out" | grep -q 'no config with redact_approved'; check $? 1 "redactions with no --config reads \$SPARKS_CONFIG"
check "$(env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE SPARKS_CONFIG="$D/red.json" python3 - "$B/sparks" <<'EOF2' | tr '\n' ' '
import sys
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
l = SourceFileLoader("mr", sys.argv[1]); m = module_from_spec(spec_from_loader("mr", l)); l.exec_module(m)
t = "---\nstatus: new\ntags:\n  - product\n  - boats\n# a comment\nredactions: pending\n---\n\nbody\n"
u = m.set_front(t, {"redactions": "reviewed"})
print("block" if u == t.replace("pending", "reviewed") else "BAD " + repr(u))
print("acct" if m.secret_spans("Account 40 817 810 099 910 004 312 please.") else "BAD-acct")
print("phone" if m.secret_spans("Phone 916 123 456.") else "BAD-phone")
print("round" if not m.secret_spans("A market of 2 500 000 people and 1 000 000 more.") else "BAD-round")
run = ("word " * 600).strip()
s = m.split_sentences(run)
print("runon" if max(map(len, s)) <= 300 and " ".join(s) == run else "BAD-runon")
print("example" if not m.MARKER_RE.search(m.MARKER_RULE) else "BAD-example")
EOF2
)" "block acct phone round runon example " "set_front keeps a block list; grouped account and phone numbers stay secret, round ones do not; a comma-less run-on is cut; the rule's example is no marker"
say -o "$D/in/Elm Road 7.aiff" "a recording with no title" 2>/dev/null
echo notitle > "$T/shape.mode"; out=$(red); rm -f "$T/shape.mode"
[ ! -f "$D/in/Elm Road 7.aiff" ]; check $? 0 "a reply with no title line is filed"
grep -rq 'Elm Road' "$D/notes"; check $? 1 "  and its from: is the archived name, not the place"
say -o "$D/in/Oak Lane 3.aiff" "a recording whose sidecar fails" 2>/dev/null
n=$(ls "$D/notes" | wc -l | tr -d ' ')
chmod 555 "$D/archive"; out=$(red); chmod 755 "$D/archive"
echo "$out" | grep -q 'sidecar could not be written.*withdrawn, audio kept'; check $? 0 "a sidecar that cannot be written: said"
[ -f "$D/in/Oak Lane 3.aiff" ] && [ "$(ls "$D/notes" | wc -l | tr -d ' ')" = "$n" ]; check $? 0 "  its notes withdrawn, the audio waits"
rm -f "$D/in/Oak Lane 3.aiff"
grep -qE '/Users/|projects/_' "$B/redactions"; check $? 1 "bin/redactions names no owner's path"

echo "Voice Memos: the library is read, never written; each new recording is copied into the inbox (2026-10-16)"
V="$T/vm"; mkdir -p "$V/lib" "$V/in" "$V/notes" "$V/archive"
cat > "$T/bin/claude" <<'EOF2'
#!/bin/sh
printf '# A short spoken idea\n\n## Summary\nOne idea.\n\n## Topics\n### Dog water bowl sensor\nTags: home\nA sensor that says when the bowl is empty.\n'
EOF2
printf '#!/bin/sh\necho " A short spoken idea about the dog bowl."\n' > "$T/bin/whisper"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/notify.txt"\n' "$V" > "$T/bin/notify"
chmod +x "$T/bin/claude" "$T/bin/whisper" "$T/bin/notify"
: > "$T/model.bin"
rec() {  # $1 file name in the library, $2 words: a real m4a, as Voice Memos keeps them
  say -o "$V/$1.aiff" "$2" 2>/dev/null && afconvert -f m4af -d aac "$V/$1.aiff" "$V/lib/$1" && rm -f "$V/$1.aiff"
}
rec "a.m4a" "a fresh idea"; rec "b.m4a" "an idea from last week"; rec "c.m4a" "one in a folder"
rec "d.m4a" "shared by hand before"; rec "e.m4a" "still downloading"; rec "f.m4a" "from september"
touch -t 202610010000 "$V/lib/a.m4a" "$V/lib/b.m4a" "$V/lib/c.m4a" "$V/lib/d.m4a" "$V/lib/f.m4a"   # settled; e.m4a is being written now
echo shared > "$V/archive/Market St.m4a"   # the share sheet's copy, re-encoded: a different hash
python3 - "$V/lib" <<'EOF2'
import datetime as dt, sqlite3, subprocess, sys, re
lib = sys.argv[1]
def secs(f):
    return float(re.search(r"estimated duration:\s*([0-9.]+)", subprocess.run(["afinfo", f"{lib}/{f}"], capture_output=True, text=True).stdout).group(1))
def apple(d):
    return d.timestamp() - 978307200
now = dt.datetime.now()
rows = [("AAAA1111-0000-0000-0000-000000000001", apple(now - dt.timedelta(minutes=5)), secs("a.m4a"), None, "a.m4a", "Elm St"),
        ("BBBB2222-0000-0000-0000-000000000002", apple(now - dt.timedelta(days=6)), secs("b.m4a"), None, "b.m4a", "Recording 7"),
        ("CCCC3333-0000-0000-0000-000000000003", apple(now - dt.timedelta(days=1)), secs("c.m4a"), 1, "c.m4a", "Doctor"),
        ("DDDD4444-0000-0000-0000-000000000004", apple(now - dt.timedelta(days=2)), secs("d.m4a"), None, "d.m4a", "Market St"),
        ("EEEE5555-0000-0000-0000-000000000005", apple(now - dt.timedelta(minutes=1)), secs("e.m4a"), None, "e.m4a", "Oak Ave"),
        ("FFFF6666-0000-0000-0000-000000000006", apple(dt.datetime(2026, 9, 20)), secs("f.m4a"), None, "f.m4a", "Old one"),
        ("GGGG7777-0000-0000-0000-000000000007", apple(now - dt.timedelta(days=1)), 300.0, None, "g.m4a", "Not here yet"),
        ("HHHH8888-0000-0000-0000-000000000008", apple(now - dt.timedelta(days=1)), 300.0, None, "a.m4a", "Wrong length")]
c = sqlite3.connect(f"{lib}/CloudRecordings.db")
c.execute("PRAGMA journal_mode=WAL")  # as Voice Memos keeps it
c.execute("CREATE TABLE ZCLOUDRECORDING (Z_PK INTEGER PRIMARY KEY, ZUNIQUEID, ZDATE, ZDURATION, ZFOLDER, ZPATH, ZENCRYPTEDTITLE, ZEVICTIONDATE)")
c.execute("INSERT INTO ZCLOUDRECORDING (ZUNIQUEID, ZDATE, ZDURATION, ZFOLDER, ZPATH, ZENCRYPTEDTITLE, ZEVICTIONDATE) VALUES (?,?,?,?,?,?,?)", ("KKKK1212-0000-0000-0000-000000000012", apple(now - dt.timedelta(days=1)), secs("b.m4a"), None, "b.m4a", "Deleted one", apple(now)))
c.executemany("INSERT INTO ZCLOUDRECORDING (ZUNIQUEID, ZDATE, ZDURATION, ZFOLDER, ZPATH, ZENCRYPTEDTITLE) VALUES (?,?,?,?,?,?)", rows)
c.commit(); c.close()
EOF2
cat > "$V/c.json" <<EOF2
{ "inbox": "$V/in", "notes": "$V/notes", "archive": "$V/archive", "state": "$V/state.json",
  "split": "topics", "transcript": "archive", "source": "conversation", "commit": false,
  "voice_memos": {"since": "2026-10-01", "settle_seconds": 60},
  "notify": {"command": ["$T/bin/notify"], "on": ["received", "filed", "failed"]} }
EOF2
vm() { env -u SPARKS_IN -u SPARKS_OUT -u SPARKS_ARCHIVE -u SPARKS_STATE -u SPARKS_ROUTE SPARKS_CONFIG="$V/c.json" \
  SPARKS_VOICEMEMOS="$V/lib" python3 "$B/sparks" "$@"; }
sum_lib() { find "$V/lib" -type f -exec shasum {} + | sort | shasum; }
before=$(sum_lib)
out=$(vm --dry-run)
check "$(echo "$out" | grep -c 'would copy from Voice Memos')" "2" "dry run: names the two it would copy"
check "$(ls "$V/in" | wc -l | tr -d ' ')" "0" "  and copies nothing"
python3 - "$V/c.json" <<'EOF2'
import json, sys; c = json.load(open(sys.argv[1])); c["voice_memos"]["settle_seconds"] = 60; json.dump(c, open(sys.argv[1], "w"))
EOF2
s0=$(date +%s); out=$(SPARKS_VM_WAIT=6 vm); waited=$(( $(date +%s) - s0 ))
[ "$waited" -ge 5 ]; check $? 0 "a file being written right now: the pass waits for it, up to its cap"
check "$(echo "$out" | grep -c 'copied from Voice Memos')" "2" "a pass copies the two new, settled recordings"
check "$(echo "$out" | grep -c '^✓')" "2" "  and files both in the same pass"
grep -q 'Elm St vm-aaaa1111' "$V/state.json"; check $? 0 "  named after the title, with the recording's id"
check "$(sum_lib)" "$before" "  the library is untouched: every file, the database included"
f=$(grep -l '^from: ' "$V/notes"/*.md | head -1)
grep -q "^audio: archive/Elm St vm-aaaa1111.m4a\|^audio: archive/Recording 7 vm-bbbb2222.m4a" "$f"; check $? 0 "  the note names the archived copy"
grep -q "^recorded: $(date -v-6d +%Y-%m-%d)" "$V/notes"/*.md; check $? 0 "  recorded: is when it was recorded, not when it was copied"
ls "$V/archive" | grep -q 'Recording 7 vm-bbbb2222.m4a'; check $? 0 "  the copy is archived like any recording"
grep -q 'Doctor' "$V/state.voicememos.json"; check $? 1 "a recording in a folder is never copied"
grep -q 'Old one' "$V/state.voicememos.json" || ls "$V/archive" | grep -q 'Old one'; check $? 1 "one from before since: left alone"
grep -q '"DDDD4444-0000-0000-0000-000000000004": "filed by hand"' "$V/state.voicememos.json"; check $? 0 "one shared by hand before (its title in the archive): counted as filed"
ls "$V/archive" | grep -q 'Oak Ave'; check $? 1 "one still being written: waits"
grep -q 'GGGG7777\|HHHH8888' "$V/state.voicememos.json"; check $? 1 "audio not downloaded, or not yet its full length: waits"
grep -q 'Got it' "$V/notify.txt"; check $? 1 "notify: the first pass is the backfill, and texts nothing on arrival"
grep -q 'Deleted one' "$V/state.voicememos.json"; check $? 1 "a recording deleted in Voice Memos (eviction date set) is never copied"
check "$(grep -c '^⚡ Filed 2 recordings → 2 notes: Dog water bowl sensor; Dog water bowl sensor$' "$V/notify.txt")" "1" "  one text for the pass, with the notes' titles"
: > "$V/notify.txt"
python3 - "$V/c.json" <<'EOF2'
import json, sys; c = json.load(open(sys.argv[1])); c["voice_memos"]["settle_seconds"] = 10; json.dump(c, open(sys.argv[1], "w"))
EOF2
touch "$V/lib/e.m4a"; s0=$(date +%s); out=$(SPARKS_VM_WAIT=40 vm); waited=$(( $(date +%s) - s0 ))
check "$(echo "$out" | grep -c 'copied from Voice Memos: Oak Ave')" "1" "written a moment ago: the same pass waits, then takes it"
check "$(grep -c '^🎙 Got it: Oak Ave (0:0[0-9])\. Filing now\.$' "$V/notify.txt")" "1" "  after the backfill, an arrival says so at once"
[ "$waited" -ge 9 ] && [ "$waited" -lt 60 ]; check $? 0 "  after its settle time, not the 90 s cap (${waited} s)"
out=$(vm)
check "$(echo "$out" | grep -c 'copied from Voice Memos')" "0" "a recording is copied once, ever"
check "$(grep -c '^⚡ Filed ' "$V/notify.txt")" "1" "  nothing filed: no text"
python3 - "$V/c.json" <<'EOF2'
import json, sys; c = json.load(open(sys.argv[1])); c["voice_memos"]["folders"] = True; json.dump(c, open(sys.argv[1], "w"))
EOF2
out=$(vm)
check "$(echo "$out" | grep -c 'copied from Voice Memos: Doctor')" "1" '"folders": true takes a recording in a folder too'
rec "h.m4a" "a recording whose filing fails"; touch -t 202610010000 "$V/lib/h.m4a"
python3 - "$V/lib" <<'EOF2'
import datetime as dt, sqlite3, subprocess, sys, re
lib = sys.argv[1]
s = float(re.search(r"estimated duration:\s*([0-9.]+)", subprocess.run(["afinfo", f"{lib}/h.m4a"], capture_output=True, text=True).stdout).group(1))
c = sqlite3.connect(f"{lib}/CloudRecordings.db")
c.execute("INSERT INTO ZCLOUDRECORDING (ZUNIQUEID, ZDATE, ZDURATION, ZFOLDER, ZPATH, ZENCRYPTEDTITLE) VALUES (?,?,?,?,?,?)",
          ("IIII9999-0000-0000-0000-000000000009", dt.datetime.now().timestamp() - 978307200 - 120, s, None, "h.m4a", "Pine Rd"))
c.commit(); c.close()
EOF2
printf '#!/bin/sh\nexit 1\n' > "$T/bin/claude"; : > "$V/notify.txt"
out=$(SPARKS_RETRY_WAIT=0 vm); out=$(SPARKS_RETRY_WAIT=0 vm)
check "$(grep -c '^⚠ Not filed yet: Pine Rd — ' "$V/notify.txt")" "1" "a filing that fails: one text, not one per retry"
check "$(grep -c '^🎙 Got it: Pine Rd' "$V/notify.txt")" "1" "  after the one saying it arrived"
printf '#!/bin/sh\nprintf "# A short spoken idea\\n\\n## Summary\\nOne idea.\\n\\n## Topics\\n### Dog water bowl sensor\\nTags: home\\nA sensor.\\n"\n' > "$T/bin/claude"
printf '#!/bin/sh\necho "no such buddy" >&2; exit 3\n' > "$T/bin/notify"
rec "j.m4a" "a notifier that fails"; touch -t 202610010000 "$V/lib/j.m4a"
python3 - "$V/lib" <<'EOF2'
import datetime as dt, sqlite3, subprocess, sys, re
lib = sys.argv[1]
s = float(re.search(r"estimated duration:\s*([0-9.]+)", subprocess.run(["afinfo", f"{lib}/j.m4a"], capture_output=True, text=True).stdout).group(1))
c = sqlite3.connect(f"{lib}/CloudRecordings.db")
c.execute("INSERT INTO ZCLOUDRECORDING (ZUNIQUEID, ZDATE, ZDURATION, ZFOLDER, ZPATH, ZENCRYPTEDTITLE) VALUES (?,?,?,?,?,?)",
          ("JJJJ0000-0000-0000-0000-000000000010", dt.datetime.now().timestamp() - 978307200 - 120, s, None, "j.m4a", "Birch Ln"))
c.commit(); c.close()
EOF2
out=$(vm)
echo "$out" | grep -q 'copied from Voice Memos: Birch Ln'; check $? 0 "a notifier that fails never stops the copy"
echo "$out" | grep -q 'notify received: no such buddy'; check $? 0 "  and says why, once"
rm -f "$V/lib/CloudRecordings.db"*; echo x > "$V/in/loose.txt"
out=$(vm)
echo "$out" | grep -q '⚠ Voice Memos: the library at .* is not readable'; check $? 0 "no library: said, and the pass goes on"
check "$(echo "$out" | grep -c '^✓ loose.txt')" "1" "  the inbox's own files are still filed"
cat > "$V/chain.json" <<EOF2
{ "host": "", "also": ["c.json"] }
EOF2
check "$(SPARKS_CONFIG="$V/chain.json" SPARKS_VOICEMEMOS="$V/lib" python3 "$B/sparks" --inboxes | tail -1)" "$V/lib" "--inboxes lists the library when an also config reads it (the job's WatchPaths)"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/notify.txt"\n' "$V" > "$T/bin/notify"

echo "the private values, through the config dir (the design's C3)"
say -o "$D/in/source.aiff" "a recording that waits for its source" 2>/dev/null
redcfg '{}'; mkdir -p "$REGATTA_CONFIG/sextant"; printf 'owner-vault\n' > "$REGATTA_CONFIG/sextant/source"
out=$(red)
echo "$out" | grep -q "refused: data from owner-vault goes to typesafe only with"; check $? 0 "sextant/source names the guarded source the refusal states"
rm -f "$REGATTA_CONFIG/sextant/source"; : > "$REGATTA_CONFIG/legacy"
for k in owner guarded orca-deny log-dir projects; do mkdir -p "$REGATTA_CONFIG/regatta"; printf 'x\n' > "$REGATTA_CONFIG/regatta/$k"; done
printf '%s\n' "$T" > "$REGATTA_CONFIG/regatta/log-dir"; printf '%s\n' "$T" > "$REGATTA_CONFIG/regatta/projects"
redcfg '{"typesafe": "test: the fake server only"}'
out=$(red)
echo "$out" | grep -q "sextant/source is missing"; check $? 0 "an overlay installed and sextant/source missing: redaction refuses, fail-closed"
rm -rf "$REGATTA_CONFIG/legacy" "$REGATTA_CONFIG/regatta"
printf '%s\n' "$T/where.log" > "$REGATTA_CONFIG/sextant/log"
check "$(env -u SPARKS_LOG python3 -c "from importlib.machinery import SourceFileLoader as L; print(L('sparks', '$B/sparks').load_module().CFG['log'])")" "$T/where.log" "sextant/log moves the log; SPARKS_LOG still wins"
rm -f "$REGATTA_CONFIG/sextant/log"
check "$(env -u SPARKS_LOG -u SPARKS_CONFIG python3 -c "from importlib.machinery import SourceFileLoader as L; print(L('sparks', '$B/sparks').load_module().CONFIG)")" "$REGATTA_CONFIG/sextant/sparks.json" "the default config is sextant/sparks.json in the config dir"
check "$(env -u SPARKS_REPOS python3 -c "from importlib.machinery import SourceFileLoader as L; s = L('sparks', '$B/sparks').load_module(); print(s.CFG['repos'], s.candidates())")" "None {}" "no registry at all: no candidates, no stack trace"
check "$(env -u SPARKS_REPOS CLAUDE_REPOS_JSON="$T/repos.json" python3 -c "from importlib.machinery import SourceFileLoader as L; print(L('sparks', '$B/sparks').load_module().CFG['repos'])")" "$T/repos.json" "  the registry through the core's repos_json()"

echo "optional peers: atlas's knowledge-commit (G34), lighthouse's publish (G21)"
W="$T/peers"; mkdir -p "$W/vault/notes"; git -C "$W/vault" init -q; echo n > "$W/vault/notes/a.md"
printf '#!/bin/sh\necho "$@" > "%s/kc-args.txt"; echo "committed"\n' "$W" > "$W/kc"; chmod +x "$W/kc"
peers() {  # $1 python lines run on the loaded module before commit_publish
  python3 - "$B/sparks" "$W/vault/notes/a.md" <<EOF2
import sys
from importlib.machinery import SourceFileLoader
s = SourceFileLoader("sparks", sys.argv[1]).load_module()
s.CFG["commit"], s.CFG["publish"] = True, "vault"
$1
print("\n".join(s.commit_publish([sys.argv[2]], "Ideas: 1 note(s)")))
EOF2
}
out=$(peers 's.KNOWLEDGE_COMMIT, s.PUBLISH = None, None; s.common.tool = lambda n: None')
echo "$out" | grep -q '^  vault commit: atlas not installed'; check $? 0 "no knowledge-commit: one line, the note still filed"
echo "$out" | grep -q '^  publish --vault: lighthouse not installed'; check $? 0 "no publish: one line, the note still filed"
[ -f "$W/vault/notes/a.md" ]; check $? 0 "  the note is where it was written"
out=$(peers "s.KNOWLEDGE_COMMIT, s.PUBLISH = '$W/kc', None; s.common.tool = lambda n: None")
echo "$out" | grep -q '^  vault commit: committed$'; check $? 0 "knowledge-commit found: it commits"
check "$(cat "$W/kc-args.txt")" "vault -m Ideas: 1 note(s) $W/vault/notes/a.md" "  named by the vault's own folder, the files after -m"
out=$(peers "s.KNOWLEDGE_COMMIT = None; s.PUBLISH = None; s.common.tool = lambda n: '$W/kc' if n == 'knowledge-commit' else None")
echo "$out" | grep -q '^  vault commit: committed$'; check $? 0 "  found through the core's tool(), as on an installed Mac"

echo; [ $fails -eq 0 ] && echo "all passed" || { echo "$fails FAILED"; exit 1; }
