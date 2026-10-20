#!/usr/bin/env bash
# Tests for bin/helloworld — a throwaway private repo with a bare origin and a bare public twin,
# a scratch word list of made-up names; every scan pattern planted once on its own branch. No
# network, nothing outside a scratch dir.   bash modules/helloworld/tests/helloworld.sh
# publish's positive cases run under a pseudo-terminal (answer.py below; never tty.py, which
# shadows the stdlib module pty imports) with CLAUDECODE unset: the tool refuses an agent's shell
# and a stdin that is not a terminal, and these cases prove the path behind both refusals works.
set -u
B="$(cd "$(dirname "$0")/../bin" && pwd)"
T=$(mktemp -d); T=$(cd "$T" && pwd -P); trap 'rm -rf "$T"' EXIT
# The core is this checkout's; the config dir, Claude Code's plugin registry and the old checkout
# are scratch, so no real word list, installed module or guard is read. The old checkout holds a
# stand-in for wharf's pre-push guard (G30): it lets claude/* through and refuses anything else.
for v in $(env | sed -n 's/^\(REGATTA[A-Za-z0-9_]*\)=.*/\1/p; s/^\(HELLOWORLD[A-Za-z0-9_]*\)=.*/\1/p; s/^\(OPENSOURCE[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export REGATTA_CONFIG="$T/config" CLAUDE_CONFIG_DIR="$T/cc" REGATTA_LEGACY="$T/legacy"
mkdir -p "$T/config" "$T/cc" "$T/legacy/templates/code/git-hooks"
cat > "$T/legacy/templates/code/git-hooks/pre-push" <<'EOF'
#!/bin/sh
while read -r _l _s ref _r; do case "$ref" in refs/heads/claude/*) ;; *) echo "pre-push: $ref refused" >&2; exit 1;; esac; done
EOF
chmod +x "$T/legacy/templates/code/git-hooks/pre-push"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; sed 's/^/         | /' "$T/out" | head -20; fails=$((fails+1)); fi; }
has()   { if grep -qF -- "$2" "$1"; then echo "  ok   $3"; else echo "  FAIL $3: missing [$2]"; sed 's/^/         | /' "$1" | head -20; fails=$((fails+1)); fi; }
lacks() { if grep -qF -- "$2" "$1"; then echo "  FAIL $3: found [$2]"; fails=$((fails+1)); else echo "  ok   $3"; fi; }

export HELLOWORLD_WORDLIST="$T/words.txt"
# The planted credentials, each assembled at run time: written whole in this file, a real-looking
# key stops GitHub's push protection (the twin's first publish, 2026-10-19), and the scan reads
# the source, so the gate still meets every one whole in the test's own tree.
K_ANT="sk-""ant-api03-abcdefghijklmnop"
K_GH="ghp""_abcdefghijklmnopqrstuvwxyz0123"
K_SKL="sk_""live_abcdefghijklmnopqrstuvwx"
K_RKL="rk_""live_abcdefghijklmnopqrstuvwx"
K_AWS="AKIA""ABCDEFGHIJKLMNOP"
K_GOO="AIza""SyA1234567890abcdefghijklmnopqrstu"
K_SLK="xoxb""-1234567890-abcdefghij"
K_PRV="-----BEGIN OPENSSH ""PRIVATE KEY-----"
K_OAI="sk-""proj-abcdefghijklmnopqrstuvwxyz0123"
K_OAE="sk-""proj-AbCdEfGhIjKlMnOpQrSt"
# One entry per category the real list holds: the house, household names, a machine, the
# employer, an account, a login dir, a person who may credit themselves, a short name, an address.
# A short entry needs at least one non-hex letter: `ED` matched a commit hash in a PR body (2026-10-18).
printf '# private words\nHarbourview\nMyLaptop\nZed Quill\nAna Bell\nOZ\nGartenstraße\nHarbourview house\nInitech\nzq-machine\n.claude-z\nprivate.example\n' > "$HELLOWORLD_WORDLIST"
R="$T/priv"; PUB="$T/public.git"
git init -q --bare -b main "$T/origin.git"; git init -q --bare -b main "$PUB"
git init -q -b main "$R"
git -C "$R" config user.name "Film Maker"; git -C "$R" config user.email maker@example.org
git -C "$R" config commit.gpgsign false
git -C "$R" remote add origin "$T/origin.git"
mkdir -p "$R/.helloworld" "$R/edl" "$R/scripts" "$R/docs" "$R/config"
printf '# Film\nContact: hello@example.org\nWith Zed Quill.\n' > "$R/README.md"
cat > "$R/edl/clean.yaml" <<'EOF'
# the clean edition
- machine:
    - {t: "09:29", who: "dispatch", text: "started by dispatch on MyLaptop at 09:29"}
    - {t: "09:30", who: "Max", text: "fix: the brief"}
- clip: A
  label: "10:31"
EOF
printf "import os\nWORK = os.environ['WORK']\n" > "$R/scripts/cut.py"
printf 'people:\n  - {name: "Zed Quill", role: driver, as_given: true}\n' > "$R/CREDITS.yaml"
printf 'lines: 3\n' > "$R/config/render.yaml"
printf 'Harbourview, at /Users/someone/film\n' > "$R/docs/private.md"
printf 'README.md\nedl/clean.yaml\nscripts/cut.py\nCREDITS.yaml\nconfig/render.yaml\n' > "$R/.helloworld/allowlist.txt"
printf '# text already in the film\nREADME.md:hello@example.org\nedl/clean.yaml:dispatch on MyLaptop\n' > "$R/.helloworld/exemptions.txt"
echo "$PUB" > "$R/.helloworld/remote"
git -C "$R" add -A; git -C "$R" commit -q -m base; git -C "$R" push -q origin main
# From here on, any push from the private repo leaves a line: where to, and the override.
printf '#!/bin/sh\necho "$2 GIT_PUSH_OK=${GIT_PUSH_OK:-unset}" >> "%s"\n' "$T/pushed" > "$R/.git/hooks/pre-push"
chmod +x "$R/.git/hooks/pre-push"

# Unmasked: inside an agent's shell (this check runs in one) private words print masked; one case
# below proves that, the rest read the words.
chk() { env -u CLAUDECODE python3 "$B/helloworld" check "$R" "$@" > "$T/out" 2>&1; echo $?; }
# branch <name> <file> <line>: main plus one line appended to <file>, allowlisted if new
# (never a file of the gate's own: a case that edits a list must not also publish it).
branch() {
  git -C "$R" checkout -q -B "$1" main
  mkdir -p "$(dirname "$R/$2")"; printf '%s\n' "$3" >> "$R/$2"
  case "$2" in .helloworld/*) ;; *) grep -qxF "$2" "$R/.helloworld/allowlist.txt" || echo "$2" >> "$R/.helloworld/allowlist.txt";; esac
  git -C "$R" add -A; git -C "$R" commit -q -m "$1"; git -C "$R" checkout -q main
}
# refused <name> <file> <line> <category>: the planted line is refused under that category.
refused() {
  branch "$1" "$2" "$3"
  check "$(chk --ref "$1")" 1 "$1: refused"
  has "$T/out" "$4" "  as $4"
}

echo "the baseline"
check "$(chk)" 0 "a clean tree at origin/main passes"
has "$T/out" 'exemption used: README.md: "hello@example.org" cleared 1' "  it prints each exemption it used, with what it cleared"
has "$T/out" 'exemption used: edl/clean.yaml: "dispatch on MyLaptop" cleared 1' "  the film's own words, in their own file"
has "$T/out" "allowlist 5 files" "  and the lists it read"
has "$T/out" "first publish" "  no public main yet: says so"
has "$T/out" "Nothing was pushed" "  and says nothing was pushed"
lacks "$T/out" "/Users/someone" "  a file outside the allowlist is not scanned (docs/private.md)"
check "$(chk --ref main)" 0 "--ref names another commit"

echo "the old names still read (opensource until 2026-10-18)"
git -C "$R" checkout -q -B oldconf main; git -C "$R" mv .helloworld .opensource; git -C "$R" commit -qm oldconf; git -C "$R" checkout -q main
check "$(chk --ref oldconf)" 0 "a ref with .opensource/ and no .helloworld/: its lists are read from there"
has "$T/out" "read from .opensource/, the old name — git mv .opensource .helloworld" "  with a note to rename it"
has "$T/out" "allowlist 5 files" "  the same lists"
refused oldself .helloworld/allowlist.txt '.opensource/remote' "the gate's own lists are never published"
check "$(HELLOWORLD_WORDLIST= OPENSOURCE_WORDLIST="$T/words.txt" chk)" 0 "the old variable, OPENSOURCE_WORDLIST: read"
has "$T/out" "word list $T/words.txt" "  that list"
mkdir -p "$T/config/helloworld" "$T/home/.config/opensource"; cp "$T/words.txt" "$T/config/helloworld/wordlist.txt"
check "$(env -u HELLOWORLD_WORDLIST HOME="$T/home" python3 "$B/helloworld" check "$R" > "$T/out" 2>&1; echo $?)" 0 "no variable: the config dir's helloworld/wordlist.txt"
has "$T/out" "word list $T/config/helloworld/wordlist.txt" "  that list"
rm -r "$T/config/helloworld"; cp "$T/words.txt" "$T/home/.config/opensource/wordlist.txt"
check "$(env -u HELLOWORLD_WORDLIST HOME="$T/home" python3 "$B/helloworld" check "$R" > "$T/out" 2>&1; echo $?)" 0 "neither: the old default in the home folder"
has "$T/out" "word list $T/home/.config/opensource/wordlist.txt" "  that list"
mkdir -p "$T/config/helloworld"; ln -s "$T/drive-not-synced/wordlist.txt" "$T/config/helloworld/wordlist.txt"
check "$(env -u HELLOWORLD_WORDLIST HOME="$T/home" python3 "$B/helloworld" check "$R" > "$T/out" 2>&1; echo $?)" 2 "the config dir's list a broken link, the old one present: refused, not the old list"
has "$T/out" "no private word list at $T/config/helloworld/wordlist.txt" "  naming the broken one"
rm -r "$T/config/helloworld"
check "$(env -u HELLOWORLD_WORDLIST HOME="$T/nohome" python3 "$B/helloworld" check "$R" > "$T/out" 2>&1; echo $?)" 2 "no list anywhere: refused"
has "$T/out" "no private word list at $T/config/helloworld/wordlist.txt" "  naming the new default"
git init -q "$T/gd"
gitdir() { python3 -c '
import importlib.machinery as m, importlib.util as u, sys
from pathlib import Path
sp = u.spec_from_loader("helloworld", m.SourceFileLoader("helloworld", sys.argv[1]))
mod = u.module_from_spec(sp); sp.loader.exec_module(mod)
print(mod.log_path(Path(sys.argv[2])))' "$B/helloworld" "$T/gd"; }
check "$(gitdir)" "$T/gd/.git/helloworld/PUBLISHED.md" "a fresh clone keeps its log in <git dir>/helloworld/"
mkdir -p "$T/gd/.git/opensource"
check "$(gitdir)" "$T/gd/.git/opensource/PUBLISHED.md" "  one that published before the rename: <git dir>/opensource/, read as it is"
mkdir -p "$T/gd/.git/helloworld"
check "$(gitdir)" "$T/gd/.git/helloworld/PUBLISHED.md" "  once <git dir>/helloworld/ exists, that"

echo "each pattern, planted once"
refused machine   scripts/cut.py "p = '/Users/someone/film'"                 "machine path — /Users/someone"
refused home      scripts/cut.py "W = '~/Movies/220/work'"                   "home path — ~/M"
refused drive     scripts/cut.py "d = 'GoogleDrive-x/Shared drives/data'"    "Drive or scratchpad path — GoogleDrive-"
refused scratch   scripts/cut.py "# notes in the scratchpad"                 "Drive or scratchpad path — scratchpad"
refused lan       scripts/cut.py "host = '192.168.1.20'"                     "LAN address — 192.168.1.20"
refused email     scripts/cut.py "# by someone@example.com"                  "e-mail address — someone@example.com"
refused session   scripts/cut.py "# https://claude.ai/code/session_01UUNBmp" "session link — claude.ai/code/session"
refused trailer   scripts/cut.py "Claude-Session: x"                         "session link — Claude-Session"
refused cred      scripts/cut.py "key = '$K_ANT'"     "credential — sk…"
lacks "$T/out" "abcdefghijklmnop" "  a credential is printed masked"
refused ghtoken   scripts/cut.py "t = '$K_GH'"  "credential — gh…"
refused word      scripts/cut.py "# from the Harbourview house"               "private word — Harbourview"
refused wordcase  scripts/cut.py "# HARBOURVIEW-smart-home"                   "private word — HARBOURVIEW"
refused uncredit  README.md      "Thanks to Ana Bell."                       "private word — Ana Bell"
refused filename  docs/mylaptop-notes.md "clean"                             "docs/mylaptop-notes.md (its path): private word"
refused fileunder docs/mylaptop_notes.md "clean"                             "docs/mylaptop_notes.md (its path): private word"
refused snake     scripts/cut.py "HARBOURVIEW_HOME = 1"                       "private word — HARBOURVIEW"
refused camel     scripts/cut.py "harbourviewHost = 1"                        "private word — harbourview"
refused digit     scripts/cut.py "host = 'mylaptop2'"                        "private word — mylaptop"
refused wrapped   README.md      "Thanks to Ana"$'\n'"Bell, for the drive."   "README.md:4: private word — Ana Bell"
refused nbsp      README.md      "Thanks to Ana"$'\xc2\xa0'"Bell."          "private word — Ana Bell"
refused homevar   scripts/cut.py 'cd $HOME/projects'                         "home path — \$HOME/"
refused lanstop   README.md      "It runs at 192.168.1.50."                  "LAN address — 192.168.1.50"
refused skproj    scripts/cut.py "OPENAI_API_KEY=$K_OAE" "credential — AP…"
refused sklive    scripts/cut.py "k = '$K_SKL'"    "credential — sk…"
refused unquoted  config/render.yaml "password: hunter2hunter2"              "credential — pa…"
refused cctld     README.md      "Write to founder@company.sh."              "e-mail address — founder@company.sh"
refused qsymbol   scripts/cut.py 'password = "p@ssw0rd!x9"'                "credential — pa…"
refused edsnake   scripts/cut.py "OZ_home = 1"                               "private word — OZ"
refused eddigit   scripts/cut.py "kid = 'OZ2'"                               "private word — OZ"
refused eszett    README.md      "Gartenstraße 5"                            "private word — Gartenstraße"
# The PR mode's review (2026-10-09): every category of the word list, and the wider shapes, each
# planted once. A credential prints its first two characters only.
refused employer  scripts/cut.py "# written at Initech"                      "private word — Initech"
refused account   scripts/cut.py "# pushed as zq-machine"                    "private word — zq-machine"
refused logindir  scripts/cut.py "# CLAUDE_CONFIG_DIR=.claude-z"             "private word — .claude-z"
refused allowed   scripts/cut.py "# mail hello@example.org"                  "scripts/cut.py:3: e-mail address — hello@example.org"
refused cgnat     scripts/cut.py "host = '100.101.102.103'"                  "LAN address — 100.101.102.103"
refused linklocal scripts/cut.py "host = '169.254.10.20'"                    "LAN address — 169.254.10.20"
refused ula       scripts/cut.py "host = 'fd7a:115c:a1e0::1'"                "LAN address — fd7a:115c:a1e0::1"
refused v6link    scripts/cut.py "host = 'fe80::1ff:fe23:4567:890a'"         "LAN address — fe80::1ff:fe23:4567:890a"
refused lanhost   scripts/cut.py "url = 'http://homeassistant.local:8123'"   "LAN host name — homeassistant.local"
refused lanstop2  README.md      "The NAS answers at tower.lan."             "LAN host name — tower.lan"
refused homearpa  scripts/cut.py "url = 'http://nas.home.arpa/x'"            "LAN host name — nas.home.arpa"
refused tailnet   scripts/cut.py "url = 'https://studio.tail1234.ts.net/'"   "LAN host name — studio.tail1234.ts.net"
refused dataimg   README.md      '![x](data:image/png;base64,iVBORw0KGgo)'   "embedded data — data:image/png;base64,"
refused dataparam README.md      '![x](data:image/png;charset=utf-8;base64,iVBO)' "embedded data"
refused dataaudio README.md      '<audio src="data:audio/mp4;base64,AAAA">'  "embedded data — data:audio/mp4;base64,"
refused lantick   README.md      'See `tower.local` for the NAS.'            "LAN host name — tower.local"
refused lanangle  README.md      '<http://nas.lan>'                          "LAN host name — nas.lan"
refused lanquery  README.md      'Is it at tower.lan?'                       "LAN host name — tower.lan"
refused aws       scripts/cut.py "# $K_AWS"                    "credential — AK…"
refused google    scripts/cut.py "# $K_GOO"   "credential — AI…"
refused slack     scripts/cut.py "# $K_SLK"              "credential — xo…"
refused ghpat     scripts/cut.py "# github_pat_11ABCDEFG0123456789abcdef"     "credential — gi…"
refused privkey   scripts/cut.py "$K_PRV"       "credential — --…"
refused homebrace scripts/cut.py 'cd ${HOME}/projects'                       "home path — \${HOME}/"
branch identifiers scripts/cut.py $'def run_task1_processing_pipeline(): pass
def test_risk_test_cases_for_portfolio(): pass
mask1_threshold_values_list = 1'
check "$(chk --ref identifiers)" 0 "a vendor shape needs a left edge: task1_, risk_test_ and mask1_ inside identifiers pass"
refused jwt       scripts/cut.py "t = eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fw" "credential — ey…"
refused telegram  scripts/cut.py "# bot 123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw" "credential — 12…"
refused porkbunpk scripts/cut.py "# pk1_0123456789abcdef0123456789abcdef"    "credential — pk…"
refused porkbunsk scripts/cut.py "# sk1_0123456789abcdef0123456789abcdef"    "credential — sk…"
refused skprojbare scripts/cut.py "k = '$K_OAI'" "credential — sk…"
refused stripebare scripts/cut.py "# $K_RKL"        "credential — rk…"
refused unquotedenv scripts/cut.py "API_KEY=abcd1234efgh5678ijkl"            "credential — AP…"
branch threadlocal scripts/cut.py "store = threading.local()"
check "$(chk --ref threadlocal)" 0 "python's threading.local() is not a LAN host name"
printf 'Harbourview  # the house\n' > "$T/words-comment.txt"
check "$(HELLOWORLD_WORDLIST="$T/words-comment.txt" chk --ref word)" 1 "a trailing comment in the word list is stripped, not matched as part of the word"
has "$T/out" "private word — Harbourview" "  the word still hits"
printf 'Harbourview#house\n' > "$T/words-hash.txt"
check "$(HELLOWORLD_WORDLIST="$T/words-hash.txt" chk)" 2 "a '#' left inside a word-list entry: refused, it would never match"
has "$T/out" "a comment goes on its own line" "  and said, without printing the entry"
lacks "$T/out" "Harbourview#house" "  the entry itself never printed"
branch fred scripts/cut.py "# Dozen, cozy, and a flask-sqlalchemy-extension"
check "$(chk --ref fred)" 0 "a short entry needs non-letters around it (Dozen, cozy), and sk- needs a left edge"
git -C "$R" checkout -q -B overlap main; echo "Harbourview house" >> "$R/README.md"
echo "README.md:Harbourview" >> "$R/.helloworld/exemptions.txt"; git -C "$R" commit -qam overlap; git -C "$R" checkout -q main
check "$(chk --ref overlap)" 1 "overlapping entries are each found: an exemption for one leaves the other"
has "$T/out" "private word — Harbourview house" "  Harbourview house still refused"
branch codetoken scripts/cut.py "token = os.environ.get('TOKEN')"
check "$(chk --ref codetoken)" 0 "a credential name assigned from code (os.environ.get) is not a secret"
git -C "$R" checkout -q -B binary main; printf '\377\376\000x' > "$R/scripts/blob.bin"; echo scripts/blob.bin >> "$R/.helloworld/allowlist.txt"
git -C "$R" add -A; git -C "$R" commit -q -m binary; git -C "$R" checkout -q main
check "$(chk --ref binary)" 1 "a file that is not UTF-8 text: refused"
has "$T/out" "not UTF-8 text" "  as not UTF-8 text"
branch fname scripts/cut.py "# see IMG_5814@496.json"
check "$(chk --ref fname)" 0 "a file name with an @ (IMG_5814@496.json) is not an address"
branch credited README.md "Driven by Zed Quill."
check "$(chk --ref credited)" 0 "a word-list name that CREDITS.yaml credits passes"
git -C "$R" checkout -q -B credblock main
printf 'people:\n  # name: Ana Bell (asked, not yet)\n  - name: Zed Quill\n    role: driver\nplace:\n  - {name: Harbourview}\n' > "$R/CREDITS.yaml"
printf 'Zed Quill drove. Ana Bell waved. Harbourview.\n' >> "$R/README.md"
git -C "$R" commit -qam credblock; git -C "$R" checkout -q main
check "$(chk --ref credblock)" 1 "credits: a block-style name counts, a comment and a name outside people: do not"
lacks "$T/out" "Zed Quill" "  Zed Quill (block style) passes"
has "$T/out" "private word — Ana Bell" "  a commented-out credit is no credit"
has "$T/out" "README.md:4: private word — Harbourview" "  a name: outside people: is no credit"
git -C "$R" checkout -q -B credaddr main
printf '  - {name: "zed@gmail.com"}\n  - {name: "Ana"}\n' >> "$R/CREDITS.yaml"
printf 'Mail zed@gmail.com. Thanks Ana Bell.\n' >> "$R/README.md"
git -C "$R" commit -qam credaddr; git -C "$R" checkout -q main
check "$(chk --ref credaddr)" 1 "a credit hides no address and no longer name"
has "$T/out" "README.md:4: e-mail address — zed@gmail.com" "  the credited address is still refused in README.md"
has "$T/out" "private word — Ana Bell" "  a credited \"Ana\" does not pass Ana Bell"
git -C "$R" checkout -q -B part main; echo '  - {name: "Harb"}' >> "$R/CREDITS.yaml"; echo "Harbourview" >> "$R/README.md"
git -C "$R" commit -qam part; git -C "$R" checkout -q main
check "$(chk --ref part)" 1 "a credited name hides only itself, whole: \"Harb\" does not pass Harbourview"
has "$T/out" "README.md:4: private word — Harbourview" "  refused as the private word"

echo "exemptions: only in the named file, only the exact string"
refused elsewhere scripts/cut.py "# dispatch on MyLaptop"                    "scripts/cut.py:3: private word — MyLaptop"
git -C "$R" checkout -q -B exsub main
printf 'Mail me@private.example. Harbourview.\n' >> "$R/README.md"
printf 'README.md:@\nREADME.md:Harb\n' >> "$R/.helloworld/exemptions.txt"
git -C "$R" commit -qam exsub; git -C "$R" checkout -q main
check "$(chk --ref exsub)" 1 "an exemption that is a part of a finding clears nothing"
has "$T/out" "e-mail address — me@private.example" "  README.md:@ does not clear an address"
has "$T/out" "private word — Harbourview" "  README.md:Harb does not clear Harbourview"
has "$T/out" "exemption: README.md:@ — clears no finding in README.md" "  and an exemption that clears nothing is refused"
refused bare      edl/clean.yaml "# MyLaptop alone"                          "edl/clean.yaml:7: private word — MyLaptop"
git -C "$R" checkout -q -B excase main
sed 's/dispatch on MyLaptop/dispatch on mylaptop/' "$R/.helloworld/exemptions.txt" > "$T/ex" && cp "$T/ex" "$R/.helloworld/exemptions.txt"
git -C "$R" commit -qam excase; git -C "$R" checkout -q main
check "$(chk --ref excase)" 1 "an exemption whose exact string is not in its file: refused"
has "$T/out" "exemption: edl/clean.yaml:dispatch on mylaptop — the string is not in edl/clean.yaml" "  and named"
has "$T/out" "private word — MyLaptop" "  the hit it would have covered is refused too"
branch exother .helloworld/exemptions.txt "docs/private.md:Harbourview"
check "$(chk --ref exother)" 1 "an exemption naming a file that is not published: refused"
has "$T/out" "docs/private.md is not published" "  and named"

echo "cut lists: the people's words never go public"
refused lines  edl/clean.yaml '  lines: [{t: 1.0, text: "a spoken line"}]'   "edl/clean.yaml:7: people's words in a cut list"
refused fix    edl/clean.yaml '  fix: {"wisper": "whisper"}'                 "people's words in a cut list — fix:"
lacks "$T/out" "wisper" "  the finding prints the key, never the words"
refused quoted edl/clean.yaml '  "lines": [x]'                              "people's words in a cut list"
refused squote edl/clean.yaml "  'fix': {a: b}"                             "people's words in a cut list"
refused nested edl/clean.yaml '- - lines: [x]'                              "people's words in a cut list"
refused jsonflow edl/clean.yaml '- {"clip": "B", "lines": [{"text": "x"}]}' "people's words in a cut list"
refused edljson edl/cut.json '{"items": [{"lines": ["x"]}]}'                "people's words in a cut list"
refused flow   edl/clean.yaml '- {clip: B, in: 1, lines: [x]}'               "people's words in a cut list"
git -C "$R" checkout -q -B exlines lines; echo 'edl/clean.yaml:lines:' >> "$R/.helloworld/exemptions.txt"
git -C "$R" commit -qam exlines; git -C "$R" checkout -q main
check "$(chk --ref exlines)" 1 "an exemption does not reach a lines: key"
has "$T/out" "people's words in a cut list" "  still refused as the people's words"
check "$(chk --ref main)" 0 "a lines: key outside edl/ (config/render.yaml) and a quoted \"fix:\" pass"

echo "the allowlist: files, one by one"
refused glob     .helloworld/allowlist.txt 'scripts/*.py'      "allowlist: scripts/*.py: a glob"
refused folder   .helloworld/allowlist.txt 'scripts'           "allowlist: scripts: a folder"
refused missing  .helloworld/allowlist.txt 'nope.md'           "allowlist: nope.md: not in the tree"
refused itself   .helloworld/allowlist.txt '.helloworld/remote' "the gate's own lists are never published"

echo "inside an agent's shell, private words and addresses print masked"
branch masked README.md "Harbourview, and mail to someone@example.com"
CLAUDECODE=1 python3 "$B/helloworld" check "$R" --ref masked > "$T/out" 2>&1
check "$?" 1 "refused as before"
has "$T/out" "private word — Ha…" "  the word masked"
has "$T/out" "e-mail address — so…" "  the address masked"
lacks "$T/out" "Harbourview" "  the word itself never printed"
branch maskpath docs/mylaptop-notes.md "see /Users/harbourview/film"
CLAUDECODE=1 python3 "$B/helloworld" check "$R" --ref maskpath > "$T/out" 2>&1
lacks "$T/out" "mylaptop" "  nor in a file's path"
lacks "$T/out" "/Users/harbourview" "  nor inside a machine-path finding"

echo "setup errors"
git -C "$R" checkout -q -B noallow main; printf '# nothing yet\n' > "$R/.helloworld/allowlist.txt"
git -C "$R" commit -qam noallow; git -C "$R" checkout -q main
check "$(chk --ref noallow)" 2 "an allowlist that names no file: refused, not an empty tree"
has "$T/out" "names no file" "  and said"
HELLOWORLD_WORDLIST="$T/none.txt" python3 "$B/helloworld" check "$R" > "$T/out" 2>&1
check "$?" 2 "no private word list: refused, nothing scanned"
has "$T/out" "no private word list" "  and said"
git init -q -b main "$T/plain"; git -C "$T/plain" commit -q --allow-empty -m x
python3 "$B/helloworld" check "$T/plain" --ref main > "$T/out" 2>&1
check "$?" 2 "a repo without .helloworld/: refused"
has "$T/out" "has not opted in" "  and said"
git -C "$R" checkout -q -B ownremote main; echo "file://$T/origin.git/" > "$R/.helloworld/remote"
git -C "$R" commit -qam ownremote; git -C "$R" checkout -q main
check "$(chk --ref ownremote)" 2 "a remote that is the private repo's own origin: refused"
has "$T/out" "one of this repo's own remotes" "  and said"

echo "check never pushes"
check "$(git -C "$PUB" for-each-ref | wc -l | tr -d ' ')" 0 "after every check above, the public repo has no refs"
check "$([ -e "$T/pushed" ] && echo pushed || echo none)" none "  and the private repo's pre-push never ran"

echo "publish: the owner's terminal only"
cat > "$T/answer.py" <<'EOF'
# answer.py <answer> <cmd>…: run cmd under a pseudo-terminal, type <answer> at the name prompt.
import os, pty, select, sys
answer, cmd = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
out, sent = b"", False
while True:
    try:
        ready, _, _ = select.select([fd], [], [], 60)
        chunk = os.read(fd, 4096) if ready else b""
    except OSError:
        chunk = b""
    if not chunk:
        break
    out += chunk
    if not sent and b"Type the public repo" in out:
        os.write(fd, (answer + "\n").encode()); sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(status))
EOF
pub() { local a=$1; shift; python3 "$T/answer.py" "$a" env -u CLAUDECODE python3 "$B/helloworld" publish "$R" "$@" > "$T/out" 2>&1; echo $?; }
pubmain() { git -C "$PUB" rev-parse -q --verify refs/heads/main || echo none; }
CLAUDECODE=1 python3 "$B/helloworld" publish "$R" > "$T/out" 2>&1
check "$?" 2 "publish with CLAUDECODE set: refused"
has "$T/out" "CLAUDECODE is set" "  and said why"
env -u CLAUDECODE python3 "$B/helloworld" publish "$R" < /dev/null > "$T/out" 2>&1
check "$?" 2 "publish without a terminal on stdin: refused"
has "$T/out" "not a terminal" "  and said why"
NAME="$(basename "$T" | tr 'A-Z' 'a-z')/public"
check "$(pub public)" 2 "the repo's last segment alone is not its name: not published"
check "$(pub wrong-name)" 2 "the wrong name typed back: not published"
has "$T/out" "the name did not match" "  and said"
check "$(pubmain)" none "  nothing reached the public repo"
check "$([ -e "$T/pushed" ] && echo pushed || echo none)" none "  and nothing was pushed at all"

check "$(TZ=America/Los_Angeles pub "$NAME")" 0 "the right name typed back: published"
P1=$(pubmain)
has "$T/out" "Published ${P1:0:7}" "  it names the commit it read back from the public repo"
check "$(git -C "$PUB" ls-tree -r --name-only main | tr '\n' ' ')" \
      "CREDITS.yaml README.md config/render.yaml edl/clean.yaml scripts/cut.py " "  the public tree is the allowlist, nothing else"
check "$(git -C "$PUB" rev-list --count main)" 1 "  the first publish is an orphan: one commit, no history"
check "$(git -C "$PUB" log -1 --format=%B main | head -1)" "Published $(TZ=UTC date +%F)" "  with the default message, its date the UTC one"
has "$T/pushed" "$PUB GIT_PUSH_OK=1" "  pushed through the repo's own pre-push, with GIT_PUSH_OK=1"
has "$R/.git/helloworld/PUBLISHED.md" "$P1 $PUB" "  logged in the git dir, not the working tree"
check "$(git -C "$PUB" log -1 --format='%ai|%ci' main | grep -c '+0000|.*+0000')" 1 "  both dates in UTC: no time zone goes public"
has "$T/out" "author: Film Maker <maker@example.org>" "  both identities shown"
# The public repo's DCO check wants a Signed-off-by equal to the commit's author (220-film's
# public-check.yml): the trailer is read from the commit as git parses it, not grepped.
signoff() { git -C "$1" log -1 --format='%(trailers:key=Signed-off-by,valueonly,separator=%x2C)' "$2" | sed '/^$/d'; }
check "$(signoff "$PUB" main)" "$(git -C "$PUB" log -1 --format='%an <%ae>' main)" "  exactly one Signed-off-by, equal to the commit's author"
check "$(git -C "$PUB" log -1 --format=%B main | grep -c '^Signed-off-by:')" 1 "  and one line of it"
has "$T/out" "trailer: Signed-off-by: Film Maker <maker@example.org>" "  the preview shows the trailer before the name is asked"

check "$(git -C "$R" status --porcelain | wc -l | tr -d ' ')" 0 "  and the working tree stays clean"

check "$(pub "$NAME")" 0 "publish with nothing new: exits clean"
has "$T/out" "nothing — the public main already has exactly this tree" "  and says so"
check "$(pubmain)" "$P1" "  without a push"

git -C "$R" checkout -q -B badmain main; echo "# Harbourview" >> "$R/scripts/cut.py"; git -C "$R" commit -qam bad
git -C "$R" push -q -f origin badmain:main 2>/dev/null
check "$(pub "$NAME")" 1 "a hit on origin/main: publish refuses"
lacks "$T/out" "Type the public repo" "  before asking for the name"
check "$(pubmain)" "$P1" "  and the public main is unchanged"
git -C "$R" push -q -f origin main:main 2>/dev/null; git -C "$R" checkout -q main

check "$(pub "$NAME" -m 'From MyLaptop, with love')" 1 "a private word in the commit message: refused"
has "$T/out" "commit message:1: private word — MyLaptop" "  the message is scanned too"
check "$(GIT_AUTHOR_NAME='Harbourview Bot' pub "$NAME")" 1 "a private word in the author identity: refused"
has "$T/out" "commit author: private word — Harbourview" "  the identities are scanned too"

# A credit merged on GitHub: the public main moves past the last publish.
git clone -q "$PUB" "$T/gh"; git -C "$T/gh" config user.name gh; git -C "$T/gh" config user.email 7+gh@users.noreply.github.com
echo "  - {name: \"New Person\"}" >> "$T/gh/CREDITS.yaml"; git -C "$T/gh" commit -qam "A credit"; git -C "$T/gh" push -q origin main
P2=$(pubmain)
echo "With Zed Quill and friends." >> "$R/README.md"; git -C "$R" commit -qam more; git -C "$R" push -q origin main
check "$(pub "$NAME" -m 'Second cut')" 0 "a later publish: published"
check "$(git -C "$PUB" log -1 --format=%B main | grep -c '^Signed-off-by:')" 1 "  that commit too carries one Signed-off-by"
P3=$(pubmain)
# signed_off alone (a message carrying the trailer is refused by the message scan, its address
# being an address; the helper still must not double one): the same trailer, any case, is kept once.
check "$(python3 -c '
import importlib.machinery as m, importlib.util as u, sys
sp = u.spec_from_loader("helloworld", m.SourceFileLoader("helloworld", sys.argv[1]))
mod = u.module_from_spec(sp); sp.loader.exec_module(mod)
ids = [("author", "A B <a@b.c>"), ("committer", "C D <c@d.e>")]
once = mod.signed_off("T", ids)
print(once.count("Signed-off-by:"), mod.signed_off(once, ids) == once, mod.signed_off("T\n\nsigned-off-by: a b <A@b.c>", ids).count("-by:"), mod.signed_off("T", []) == "T")
' "$B/helloworld")" "1 True 1 True" "signed_off: one trailer, the author's, not doubled in any case, none without an author"
has "$T/out" "is not the last publish logged here" "  it says the public main moved since the last publish"
has "$T/out" "CREDITS.yaml" "  and the diff shows what this tree does to the merged credit"
check "$(git -C "$PUB" rev-parse "$P3^")" "$P2" "  a child of the public main: a fast-forward, no force"

echo "check after a publish"
check "$(chk)" 0 "check passes"
has "$T/out" "nothing — the public main already has exactly this tree" "  and diffs against the public repo"
check "$(git -C "$R" for-each-ref refs/helloworld | wc -l | tr -d ' ')" 0 "  after check and publish fetched the public main, no ref of the gate's own"

echo "the public history: identities GitHub or a contributor wrote, not the gate"
# Stand-ins only. The incident's shape: a squash commit GitHub authored with the merging account's
# own address (here stand-in@private.example, on the scratch word list), the publishing identity in
# a Signed-off-by, the gate blind because it scanned the tree and its own commit alone.
PUBID="Film Maker <maker@example.org>"
GHC="GitHub <noreply@github.com>"
# hist <name> [branch]: a bare "public" repo $T/<name>.git and a work clone of it, on that branch.
hist() {
  git init -q --bare -b main "$T/$1.git"; git init -q -b "${2:-main}" "$T/$1.work"; git -C "$T/$1.work" remote add origin "$T/$1.git"
  git -C "$T/$1.work" config user.name "Film Maker"; git -C "$T/$1.work" config user.email maker@example.org
}
addr() { local v="${1##*<}"; echo "${v%>}"; }
# hc <name> <author> <committer> <message> [date]: an empty commit with those identities ("Name <addr>").
hc() {
  env GIT_AUTHOR_NAME="${2%% <*}" GIT_AUTHOR_EMAIL="$(addr "$2")" GIT_COMMITTER_NAME="${3%% <*}" GIT_COMMITTER_EMAIL="$(addr "$3")" \
    ${5:+"GIT_AUTHOR_DATE=$5" "GIT_COMMITTER_DATE=$5"} \
    git -C "$T/$1.work" -c commit.gpgsign=false commit -q --allow-empty -m "$4" 2>/dev/null
}
# hpush <name>: send every branch and tag of the work clone to its scratch bare repo.
hpush() { git -C "$T/$1.work" push -q origin --all; git -C "$T/$1.work" push -q origin --tags; }
# histbranch <name> [identities]: the private branch hist-<name> whose .helloworld/remote is the bare
# repo of that name ($HB_REMOTE: another), and with a second argument its .helloworld/identities.
histbranch() {
  git -C "$R" checkout -q -B "hist-$1" main; echo "$T/${HB_REMOTE:-$1}.git" > "$R/.helloworld/remote"
  [ -n "${2:-}" ] && printf '%s\n' "$2" > "$R/.helloworld/identities"
  git -C "$R" add -A; git -C "$R" commit -qm "hist $1"; git -C "$R" checkout -q main
}
snap() { git -C "$T/leak.git" for-each-ref --format='%(refname) %(objectname)'; git -C "$R" for-each-ref --format='%(refname) %(objectname)'; }

hist leak
hc leak "$PUBID" "$GHC" "Initial work"
hc leak "Someone <stand-in@private.example>" "$GHC" $'Publish\n\nSigned-off-by: '"$PUBID"
hpush leak; histbranch leak
LEAK_SHA=$(git -C "$T/leak.work" rev-parse --short=7 HEAD)
SNAP=$(snap)
check "$(chk --ref hist-leak)" 1 "a squash commit GitHub authored with a private address: refused"
has "$T/out" "history $LEAK_SHA author: e-mail address — stand-in@private.example" "  as the author of that commit, by its short sha"
lacks "$T/out" "history $LEAK_SHA committer: e-mail" "  GitHub's noreply committer passes"
has "$T/out" "hard push, which is the owner's" "  and the remedy is named in one line"
has "$T/out" "WARNING: identities from this machine's git config" "  with no .helloworld/identities, it says whose config it fell back on"
check "$(env CLAUDECODE=1 python3 "$B/helloworld" check "$R" --ref hist-leak > "$T/out" 2>&1; echo $?)" 1 "  the same run in an agent's shell: refused"
has "$T/out" "history $LEAK_SHA author: e-mail address — st…" "  the address prints two characters only"
lacks "$T/out" "stand-in@private.example" "  and nowhere in full"
check "$(snap)" "$SNAP" "  a history check changes no ref, in the public repo or the private one"
check "$(git -C "$PUB" for-each-ref | grep -c leak)" 0 "  and pushes nothing"

hist sidebranch
hc sidebranch "$PUBID" "$GHC" "Clean main"
git -C "$T/sidebranch.work" checkout -q -b side; hc sidebranch "Other <stand-in@private.example>" "$GHC" "On a side branch"
hpush sidebranch; histbranch sidebranch
check "$(chk --ref hist-sidebranch)" 1 "a private address on a branch that is not main: refused, every branch is read"
has "$T/out" "author: e-mail address" "  as an author"

hist committer
hc committer "$PUBID" "Someone <stand-in@private.example>" "Rebased by a contributor"
hpush committer; histbranch committer
check "$(chk --ref hist-committer)" 1 "a private committer address: refused"
has "$T/out" "committer: e-mail address" "  as the committer"

hist trailer
hc trailer "$PUBID" "$GHC" $'Credit\n\nCo-Authored-By: Someone <stand-in@private.example>'
hpush trailer; histbranch trailer
check "$(chk --ref hist-trailer)" 1 "a Co-Authored-By line with a private address: refused"
has "$T/out" "message:3: e-mail address" "  in the message, on its line"

hist reviewed
hc reviewed "$PUBID" "$GHC" $'Review\n\nReviewed-by: Someone <stand-in@private.example>'
hpush reviewed; histbranch reviewed
check "$(chk --ref hist-reviewed)" 1 "a Reviewed-by line with a private address: refused, every address in a message is read"
has "$T/out" "message:3: e-mail address" "  in the message"

hist indented
hc indented "$PUBID" "$GHC" $'Squash\n\n    Cc: Someone <stand-in@private.example>'
hpush indented; histbranch indented
check "$(chk --ref hist-indented)" 1 "an indented Cc: line with a private address: refused"

hist subject
hc subject "$PUBID" "$GHC" "Fix the Harbourview script"
hpush subject; histbranch subject
check "$(chk --ref hist-subject)" 1 "a word-list entry in a commit's subject: refused"
has "$T/out" "message:1: private word — Harbourview" "  by the word list, on line 1"

hist control
hc control "$PUBID" "$GHC" $'Subject\x1eReviewed-by: Someone <stand-in@private.example>'
hpush control; histbranch control
check "$(chk --ref hist-control)" 1 "a 0x1e byte in a message cannot shift or hide the fields"
lacks "$T/out" "Traceback" "  no traceback"
has "$T/out" "message:1: e-mail address" "  and the address behind it is found"

hist latin
hc latin "$PUBID" "$GHC" $'Caf\xe9 \xff\xfe\n\nCc: Someone <stand-in@private.example>'
hpush latin; histbranch latin
check "$(chk --ref hist-latin)" 1 "a message that is not UTF-8: read with replacement, not a crash"
lacks "$T/out" "Traceback" "  no traceback"
has "$T/out" "message:3: e-mail address" "  and the address in it is found"

hist refname
hc refname "$PUBID" "$GHC" "Clean"
git -C "$T/refname.work" branch harbourview-fix
hpush refname; histbranch refname
check "$(chk --ref hist-refname)" 1 "a word-list entry in a branch name: refused"
has "$T/out" "history ref refs/heads/harbourview-fix: private word — harbourview" "  as the ref"

hist tagger
hc tagger "$PUBID" "$GHC" "Clean"
GIT_COMMITTER_NAME=Someone GIT_COMMITTER_EMAIL=stand-in@private.example git -C "$T/tagger.work" -c commit.gpgsign=false tag -a v1 -m "release"
hpush tagger; histbranch tagger
TAG_SHA=$(git -C "$T/tagger.work" rev-parse --short=7 v1)
check "$(chk --ref hist-tagger)" 1 "an annotated tag whose tagger has a private address: refused"
has "$T/out" "history $TAG_SHA tagger: e-mail address" "  as the tagger, by the tag object's sha"

# A tag of a tag: the outer tag is clean, the inner one is not. Peeled in one step, only the outer is read.
hist nested
hc nested "$PUBID" "$GHC" "Clean"
GIT_COMMITTER_NAME=Someone GIT_COMMITTER_EMAIL=stand-in@private.example git -C "$T/nested.work" -c commit.gpgsign=false tag -a inner -m "inner"
INNER=$(git -C "$T/nested.work" rev-parse inner)
OUTER=$(printf 'object %s\ntype tag\ntag outer\ntagger Film Maker <maker@example.org> 1700000000 +0000\n\nouter\n' "$INNER" | git -C "$T/nested.work" mktag)
git -C "$T/nested.work" update-ref refs/tags/outer "$OUTER"
git -C "$T/nested.work" tag -d inner > /dev/null
hpush nested; histbranch nested
check "$(chk --ref hist-nested)" 1 "a tag of a tag whose inner tagger has a private address: refused"
has "$T/out" "history ${INNER:0:7} tagger: e-mail address" "  as the inner tag's tagger"

hist word
hc word "Harbourview Bot <bot@users.noreply.github.com>" "$GHC" "A private word in a name"
hpush word; histbranch word
check "$(chk --ref hist-word)" 1 "a private word in a commit's author name: refused"
has "$T/out" "author: private word — Harbourview" "  by the word list"

hist bot
hc bot "dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>" "$GHC" "Bump a dependency"
hpush bot; histbranch bot
check "$(chk --ref hist-bot)" 0 "a bot's noreply address (<id>+<name>[bot]) passes"

hist zone
hc zone "$PUBID" "$PUBID" "Dated in Los Angeles" "2026-10-10T10:00:00 -0700"
hpush zone; histbranch zone
ZONE_SHA=$(git -C "$T/zone.work" rev-parse --short=7 HEAD)
check "$(chk --ref hist-zone)" 0 "a -0700 commit in the public history: passes, with a warning"
has "$T/out" "history $ZONE_SHA author: time zone -0700 (warning)" "  the author's offset"
has "$T/out" "history $ZONE_SHA committer: time zone -0700 (warning)" "  and the committer's"

hist contrib
hc contrib "$PUBID" "$GHC" "Mine"
hc contrib "Guest <guest@contrib.example>" "$GHC" $'A credit\n\nSigned-off-by: Guest <guest@contrib.example>'
hpush contrib
histbranch contrib $'# consented contributors\nmaker@example.org\nGuest <guest@contrib.example>'
check "$(chk --ref hist-contrib)" 0 "a contributor listed in .helloworld/identities: passes"
lacks "$T/out" "WARNING: identities" "  and with the file there, no warning about the machine's config"
HB_REMOTE=contrib histbranch contrib2 'maker@example.org'
check "$(chk --ref hist-contrib2)" 1 "the same history without the contributor in the file: refused"
has "$T/out" "author: e-mail address" "  as the author"
hist clean0; hc clean0 "$PUBID" "$GHC" "Mine"; hpush clean0
HB_REMOTE=clean0 histbranch contrib3 'someone-else@example.org'
check "$(chk --ref hist-contrib3)" 1 "a file that does not list the publishing identity: its own commits refused (the file is the only list)"

hist clean
hc clean "$PUBID" "$GHC" $'Squash\n\nSigned-off-by: '"$PUBID"
hc clean "Octo Cat <12345+octocat@users.noreply.github.com>" "$GHC" "A contributor's PR, merged on GitHub"
git -C "$T/clean.work" -c commit.gpgsign=false tag -a v1 -m "release"
hpush clean; histbranch clean
check "$(chk --ref hist-clean)" 0 "history by the publishing identity, a noreply contributor and GitHub's committer, with a tag: passes"
has "$T/out" "clean:" "  and says clean"

git -C "$R" checkout -q -B hist-gone main; echo "$T/gone.git" > "$R/.helloworld/remote"
git -C "$R" commit -qam "hist gone"; git -C "$R" checkout -q main
check "$(chk --ref hist-gone)" 2 "a public remote that cannot be read: not clean, the history was not scanned (exit 2)"
has "$T/out" "history: not scanned" "  and said"
git -C "$R" checkout -q -B hist-gone2 main; echo "$T/gone.git" > "$R/.helloworld/remote"; echo "p = '/Users/someone/film'" >> "$R/scripts/cut.py"
git -C "$R" commit -qam "hist gone2"; git -C "$R" checkout -q main
check "$(chk --ref hist-gone2)" 1 "an unreadable remote and a finding in the tree: exit 1"

# A replace ref in the private repo would show the gate another tree than the one that goes public.
git -C "$R" checkout -q -B replaced main; echo "p = '/Users/someone/film'" >> "$R/scripts/cut.py"; git -C "$R" commit -qam "leaky"
LEAKY=$(git -C "$R" rev-parse HEAD); git -C "$R" checkout -q main
git -C "$R" replace -f "$(git -C "$R" rev-parse main)" "$LEAKY"
check "$(chk --ref main)" 0 "a replace ref pointing main at a leaky commit: ignored, the real tree is scanned"
git -C "$R" replace -d "$(git -C "$R" rev-parse main)" > /dev/null

echo "publish --pr: a pull request on the public repo, never its main"
# The public URL is a GitHub one, mapped onto the local bare twin by insteadOf (a scratch global
# config), so the slug, the clone's origin and the push all take the real path. gh is a fake on
# PATH that records its arguments and the body it was given. CLAUDECODE is set: PR mode is the
# agent's verb, so private words print masked, as in any agent's shell.
printf '[url "%s"]\n\tinsteadOf = https://github.com/acme/film.git\n' "$PUB" > "$T/gitconfig"
mkdir -p "$T/fakebin"
cat > "$T/fakebin/gh" <<EOF
#!/bin/sh
[ "\$1" = api ] && case "\$2" in repos/*) [ -n "\${FAKE_GH_NOREPO:-}" ] && { echo "gh: HTTP 403" >&2; exit 1; }; printf '%s\n' "\${FAKE_GH_MERGE-false false}"; exit 0;; esac
[ "\$1 \$2 \$3 \$4" = "api -X GET search/issues" ] && { printf '%s\n' "\$@" > "$T/gh.search"; [ -n "\${FAKE_GH_SEARCH_FAIL:-}" ] && { echo '{"message":"Validation Failed"}'; echo "gh: HTTP 422" >&2; exit 1; }; printf '%s' "\${FAKE_GH_PUBLIC_PR-}"; exit 0; }
[ "\$1" = api ] && { [ -n "\${FAKE_GH_NOLOGIN:-}" ] && exit 1; printf '%s\n' "\${FAKE_GH_LOGIN-acme-bot}"; exit 0; }
[ "\$2" = list ] && { printf '%s\n' "\${FAKE_GH_LIST-https://github.com/acme/film/pull/7}"; exit 0; }
printf '%s\n' "\$@" > "$T/gh.args"
while [ \$# -gt 0 ]; do [ "\$1" = --body-file ] && cp "\$2" "$T/gh.body"; shift; done
[ -n "\${FAKE_GH_FAIL:-}" ] && { echo "gh: not logged in" >&2; exit 1; }
echo https://github.com/acme/film/pull/7
EOF
chmod +x "$T/fakebin/gh"
prun() { GIT_CONFIG_GLOBAL="$T/gitconfig" PATH="$T/fakebin:$PATH" CLAUDECODE=1 TZ=America/Los_Angeles python3 "$B/helloworld" publish --pr "$R" "$@" < /dev/null > "$T/out" 2>&1; echo $?; }
pubrefs() { git -C "$PUB" for-each-ref --format='%(refname) %(objectname)' | sort; }
gaterefs() { git -C "$R" for-each-ref refs/helloworld | wc -l | tr -d ' '; }
check "$(prun)" 2 "a public remote that is not on GitHub: refused"
has "$T/out" "is not a GitHub URL" "  and said"
git init -q --bare -b main "$T/empty.git"; printf '[url "%s"]\n\tinsteadOf = https://github.com/acme/empty.git\n' "$T/empty.git" >> "$T/gitconfig"
echo https://github.com/acme/empty.git > "$R/.helloworld/remote"; git -C "$R" commit -qam "empty twin"; git -C "$R" push -q origin main
check "$(prun)" 2 "a public repo with no main yet: refused, the first publish is publish"
has "$T/out" "has no main yet" "  and said"
check "$(git -C "$T/empty.git" for-each-ref | wc -l | tr -d ' ')" 0 "  nothing pushed to it"
echo https://github.com/acme/film.git > "$R/.helloworld/remote"; git -C "$R" commit -qam "public URL"; git -C "$R" push -q origin main
CLONE="$R/.git/helloworld/public"
python3 "$B/helloworld" publish "$R" --note x > "$T/out" 2>&1
check "$?" 2 "--note without --pr: a usage error"

check "$(prun)" 0 "nothing new since the last publish: exits clean"
has "$T/out" "nothing to propose — the public main already has exactly this tree" "  and says so"
check "$(pubrefs)" "refs/heads/main $P3" "  nothing pushed: the public repo still has main alone"
check "$([ -e "$T/gh.args" ] && echo opened || echo none)" none "  and no PR opened"

echo "With Zed Quill, a friend." >> "$R/README.md"; git -C "$R" commit -qam "a new line"; git -C "$R" push -q origin main
BR="claude/publish/$(TZ=UTC date +%F)-publish"   # the tool dates its branch in UTC
before=$(pubrefs)
check "$(prun -m 'From MyLaptop')" 1 "a private word in the PR title: refused"
has "$T/out" "PR title:1: private word — My…" "  as the title, masked"
check "$(prun --note 'Recorded at the Harbourview house.')" 1 "a private word in the PR body (--note): refused"
has "$T/out" "PR body:3: private word — Ha…" "  as the body"
check "$(prun --note 'Driven by Zed Quill.')" 1 "a credited name in the PR body: refused, a credit covers the tree only"
has "$T/out" "PR body:3: private word — Ze…" "  as the body"
check "$(prun --note 'Rendered from /Users/someone/film')" 1 "a machine path in the PR body: refused"
has "$T/out" "PR body:3: machine path — /Users/someone" "  as a machine path"
check "$(prun --note 'Rendered on 192.168.1.20.')" 1 "a LAN address in the PR body: refused"
check "$(prun --topic 'Initech cut')" 1 "a private word in the branch name: refused"
has "$T/out" "PR branch:1: private word — in…" "  as the branch"
git -C "$R" config user.name zq-machine
check "$(prun)" 1 "a private word in the commit identity: refused"
has "$T/out" "commit author:1: private word — zq…" "  as the author"
has "$T/out" "commit committer:1: private word — zq…" "  and the committer"
git -C "$R" config user.name "Film Maker"
check "$(FAKE_GH_LOGIN=zq-machine prun)" 1 "a private word in the gh login (the PR's author): refused"
has "$T/out" "PR author (gh login):1: private word — zq…" "  as the PR's author"
has "$T/gh.search" "is:pr is:merged is:public author:zq-machine org:acme" "  after looking for a public merged PR of that login in the target org"
has "$T/gh.search" 'select(.user.login == "zq-machine")' "  whose author is that login"
check "$(FAKE_GH_LOGIN=zq-machine FAKE_GH_SEARCH_FAIL=1 prun)" 1 "a login on the word list whose search fails: scanned, refused"
has "$T/out" "the search for a public merged PR failed, so the login is scanned" "  and said"
has "$T/out" "PR author (gh login):1: private word — zq…" "  as the PR's author (the error body on stdout is not taken for a URL)"
lacks "$T/out" "already public" "  never passed"
check "$(FAKE_GH_LOGIN=zq-machine FAKE_GH_PUBLIC_PR=https://github.com/acme/film/pull/1 prun --topic 'Initech cut')" 1 \
      "a login on the word list that already authored a public merged PR in the org: the author passes"
has "$T/out" "PR author: zq…, already public as the author of https://github.com/acme/film/pull/1" "  and says why, the login masked"
lacks "$T/out" "PR author (gh login)" "  no finding for the author"
has "$T/out" "PR branch:1: private word — in…" "  the run is still refused for the branch (nothing pushed)"
check "$(FAKE_GH_NOLOGIN=1 prun)" 2 "a gh login that cannot be read: refused, never pushed unscanned"
has "$T/out" "cannot read the gh login" "  and said"
check "$(FAKE_GH_MERGE='true false' prun)" 2 "the public repo allows squash merges: refused, GitHub would author that commit"
has "$T/out" "gh api -X PATCH repos/acme/film -F allow_squash_merge=false -F allow_merge_commit=false" "  the PATCH that fixes it is named"
check "$(FAKE_GH_MERGE='false true' prun)" 2 "the public repo allows merge commits: refused"
check "$(FAKE_GH_NOREPO=1 prun)" 2 "merge settings that cannot be read: refused, never pushed unchecked"
has "$T/out" "could not be read" "  and said"
check "$(GIT_AUTHOR_EMAIL=me@studio-mac.local prun)" 1 "an identity whose address names a LAN host (git's auto-detected one): refused"
has "$T/out" "commit author:1: LAN host name — studio-mac.local" "  as a LAN host name"
check "$(GIT_DIR="$R/.git" prun)" 2 "GIT_DIR set: refused, the clone's calls would act on the private repo"
has "$T/out" "GIT_DIR is set" "  and said"
git -C "$R" checkout -q -B badpr main; echo "# Harbourview" >> "$R/scripts/cut.py"; git -C "$R" commit -qam bad
git -C "$R" push -q -f origin badpr:main 2>/dev/null
check "$(prun)" 1 "a hit in a file on origin/main: refused"
has "$T/out" "Nothing was pushed" "  and says nothing was pushed"
git -C "$R" push -q -f origin main:main 2>/dev/null; git -C "$R" checkout -q main
git -C "$R" checkout -q -B automerge main; mkdir -p "$R/.github/workflows"; echo "on: pull_request" > "$R/.github/workflows/auto-merge.yml"
echo .github/workflows/auto-merge.yml >> "$R/.helloworld/allowlist.txt"; git -C "$R" add -A; git -C "$R" commit -qm automerge
git -C "$R" push -q -f origin automerge:main 2>/dev/null
check "$(prun)" 2 "an auto-merge workflow in the tree: refused, auto-merge stays off"
has "$T/out" "this tree has .github/workflows/auto-merge.yml — a PR would merge itself" "  by its name"
GIT_CONFIG_GLOBAL="$T/gitconfig" PATH="$T/fakebin:$PATH" CLAUDECODE=1 python3 "$B/helloworld" publish --pr "$R/scripts" < /dev/null > "$T/out" 2>&1
check "$?" 2 "a subfolder passed as the repo: still refused"
has "$T/out" "auto-merge.yml — a PR would merge itself" "  the workflow is seen from the repo's root"
git -C "$R" checkout -q -B prmerge main; mkdir -p "$R/.github/workflows"; printf 'on: pull_request\njobs: {m: {steps: [{run: gh pr merge --auto --rebase}]}}\n' > "$R/.github/workflows/pr.yml"
echo .github/workflows/pr.yml >> "$R/.helloworld/allowlist.txt"; git -C "$R" add -A; git -C "$R" commit -qm prmerge
git -C "$R" push -q -f origin prmerge:main 2>/dev/null
check "$(prun)" 2 "a workflow of any name that runs gh pr merge --auto: refused"
has "$T/out" "pr.yml — a PR would merge itself" "  by its content"
git -C "$R" checkout -q -B mergify main; printf 'pull_request_rules: []\n' > "$R/.mergify.yml"
echo .mergify.yml >> "$R/.helloworld/allowlist.txt"; git -C "$R" add -A; git -C "$R" commit -qm mergify
git -C "$R" push -q -f origin mergify:main 2>/dev/null
check "$(prun)" 2 "a Mergify config: refused"
has "$T/out" ".mergify.yml — a PR would merge itself" "  and named"
git -C "$R" checkout -q -B accent main; mkdir -p "$R/.github/workflows"; printf 'on: pull_request\njobs: {m: {steps: [{run: gh pr merge --auto}]}}\n' > "$R/.github/workflows/mergé.yml"
printf '.github/workflows/mergé.yml\n' >> "$R/.helloworld/allowlist.txt"; git -C "$R" add -A; git -C "$R" commit -qm accent
git -C "$R" push -q -f origin accent:main 2>/dev/null
check "$(prun)" 2 "a merging workflow whose name is not ASCII: refused (git quotes such a path)"
has "$T/out" "a PR would merge itself" "  and said"
git -C "$R" checkout -q -B kodiak main; printf 'version = 1\n' > "$R/.kodiak.toml"
echo .kodiak.toml >> "$R/.helloworld/allowlist.txt"; git -C "$R" add -A; git -C "$R" commit -qm kodiak
git -C "$R" push -q -f origin kodiak:main 2>/dev/null
check "$(prun)" 2 "a merge bot's config (Kodiak): refused"
git -C "$R" checkout -q -B ghscript main; mkdir -p "$R/.github/workflows"; printf 'on: pull_request\njobs: {m: {steps: [{uses: actions/github-script@v7, with: {script: "github.rest.pulls.merge({})"}}]}}\n' > "$R/.github/workflows/land.yml"
echo .github/workflows/land.yml >> "$R/.helloworld/allowlist.txt"; git -C "$R" add -A; git -C "$R" commit -qm ghscript
git -C "$R" push -q -f origin ghscript:main 2>/dev/null
check "$(prun)" 2 "a workflow that merges through github-script's pulls.merge: refused"
git -C "$R" push -q -f origin main:main 2>/dev/null; git -C "$R" checkout -q main
check "$(pubrefs)" "$before" "after every refusal, the public repo is unchanged"
check "$([ -e "$T/gh.args" ] && echo opened || echo none)" none "  and no PR was opened"
check "$(gaterefs)" 0 "  and the private repo holds no ref of the gate's own"

refs0=$(pubrefs)
# Hides both guards: the legacy one by REGATTA_LEGACY, and wharf's own — in this repo since B5 —
# by running a copy of the tree without the wharf module (guard_path() tries modules/wharf first).
NW="$T/nowharf"; mkdir -p "$NW/.claude-plugin" "$NW/modules"; : > "$NW/.claude-plugin/marketplace.json"
cp -R "$B/../../regatta" "$NW/modules/regatta"; cp -R "$B/.." "$NW/modules/helloworld"
check "$(B="$NW/modules/helloworld/bin" REGATTA_LEGACY="$T/none" prun --note 'One new line in the README.')" 2 "no wharf pre-push guard installed (G30): --pr refused"
has "$T/out" "no pre-push guard: the wharf module's templates/code/git-hooks/pre-push is not installed" "  in one line"
check "$(pubrefs)" "$refs0" "  nothing pushed unguarded"
rm -f "$T/gh.search"
check "$(prun --note 'One new line in the README.')" 0 "a clean tree: pushed as a branch, a PR opened"
check "$([ -e "$T/gh.search" ] && echo searched || echo none)" none "  no search for a login on no word list (the search API's limit is small)"
SHA=$(git -C "$PUB" rev-parse -q --verify "refs/heads/$BR")
check "$(git -C "$PUB" rev-parse main)" "$P3" "  the public main is untouched"
check "$(git -C "$PUB" for-each-ref --format='%(refname)' | sort | tr '\n' ' ')" "refs/heads/$BR refs/heads/main " "  one new ref, the claude/publish branch"
check "$(git -C "$PUB" rev-parse "$SHA^")" "$P3" "  a child of the public main, so the PR is one commit"
check "$(git -C "$PUB" diff --name-only "$P3" "$SHA")" "README.md" "  carrying only what changed"
check "$(git -C "$PUB" log -1 --format=%B "$SHA" | head -1)" "a new line" "  replayed: the private commit's own subject (the replay section below goes further)"
check "$(git -C "$PUB" log -1 --format='%ai|%ci' "$SHA" | grep -c '+0000|.*+0000')" 1 "  both dates in UTC, as publish's: no time zone goes public"
check "$(gaterefs)" 0 "  the ref it fetched by is gone again"
check "$(signoff "$PUB" "$SHA")" "$(git -C "$PUB" log -1 --format='%an <%ae>' "$SHA")" "  exactly one Signed-off-by, equal to the commit's author (the DCO check)"
check "$(git -C "$PUB" log -1 --format=%B "$SHA" | grep -c '^Signed-off-by:')" 1 "  and one line of it"
check "$(git -C "$PUB" log -1 --format=%B "$SHA" | sed -n 2,3p | tr '\n' '|')" "|Signed-off-by: $(git -C "$PUB" log -1 --format='%an <%ae>' "$SHA")|" "  a blank line between the title and the trailer"
has "$T/out" "trailer: Signed-off-by: Film Maker <maker@example.org>" "  the preview shows the trailer before the push"
has "$T/out" "https://github.com/acme/film/pull/7" "  it prints the PR's URL"
check "$(sed -n 1,4p "$T/gh.args" | tr '\n' ' ')" "pr create --repo acme/film " "  gh pr create --repo <the slug>"
has "$T/gh.args" "$BR" "  and the branch as --head"
lacks "$T/gh.args" "--draft" "  not a draft (as public as a PR, and the merge is the gate)"
lacks "$T/gh.args" "--auto" "  and no auto-merge"
has "$T/gh.body" "One new line in the README." "  the note is in the body"
has "$T/gh.body" "0 findings" "  and the scan's verdict"
has "$T/gh.body" "the commit identities and the PR's author; 0 findings" "  the author among what was scanned"
has "$T/gh.body" "README.md ×1" "  the exemptions as file and count"
lacks "$T/gh.body" "dispatch on MyLaptop" "  never their strings"
lacks "$T/gh.body" "$T" "  no local path in the body"
lacks "$T/gh.body" "$(git -C "$R" rev-parse --short=7 main)" "  no private sha in the body, not even a short one"
has "$R/.git/helloworld/PUBLISHED.md" "pr $BR $SHA" "  logged as a PR, not a publish"
check "$([ -x "$CLONE/.git/hooks/pre-push" ] && echo guarded || echo bare)" guarded "  the clone carries the pre-push guard"
GIT_CONFIG_GLOBAL="$T/gitconfig" git -C "$CLONE" push -q origin "refs/heads/$BR:refs/heads/main" > "$T/out" 2>&1
check "$?" 1 "a hand push from the clone onto the public main: refused by its guard"
check "$(git -C "$PUB" rev-parse main)" "$P3" "  the public main is untouched"

mv "$CLONE" "$T/clone.saved"; mkdir -p "$CLONE/.git"
check "$(prun)" 2 "an emptied clone (public/.git no repo): refused, never acts on the private repo"
has "$T/out" "is not a clone of its own" "  and said"
check "$(git -C "$R" remote get-url origin)" "$T/origin.git" "  the private repo's origin is untouched"
rm -rf "$CLONE"; mv "$T/clone.saved" "$CLONE"
rm -f "$T/gh.args"
check "$(prun)" 0 "the same tree again: exits clean"
has "$T/out" "branch $BR already has exactly this tree" "  names the open branch"
check "$([ -e "$T/gh.args" ] && echo opened || echo none)" none "  no second PR"
check "$(FAKE_GH_LIST= prun)" 2 "the same tree, its PR closed: not silently clean"
has "$T/out" "has no open PR" "  says the branch has no open PR"
has "$T/out" "gh pr create --repo acme/film --base main --head $BR" "  and how to open one"
# A proposal the gate pushed before it signed: same tree, same parent, no trailer. It fails the
# public DCO check for good, so a run must push a signed one beside it, not point at it.
SIGNED=$(git -C "$PUB" rev-parse "refs/heads/$BR")
AN=$(git -C "$PUB" log -1 --format=%an "$SIGNED"); AE=$(git -C "$PUB" log -1 --format=%ae "$SIGNED")
U=$(GIT_AUTHOR_NAME="$AN" GIT_AUTHOR_EMAIL="$AE" GIT_COMMITTER_NAME="$AN" GIT_COMMITTER_EMAIL="$AE" \
    GIT_AUTHOR_DATE="1700000000 +0000" GIT_COMMITTER_DATE="1700000000 +0000" GIT_CONFIG_GLOBAL="$T/gitconfig" git -C "$PUB" commit-tree "$(git -C "$PUB" rev-parse "$BR^{tree}")" -p "$P3" -m "Unsigned")
git -C "$PUB" update-ref "refs/heads/$BR" "$U"
rm -f "$T/gh.args"
check "$(prun)" 0 "the same tree, unsigned: proposed again"
check "$(git -C "$PUB" rev-parse -q --verify "refs/heads/$BR-2" > /dev/null && echo pushed || echo none)" pushed "  as a new branch beside the unsigned one"
check "$(git -C "$PUB" log -1 --format=%B "$BR-2" | grep -c '^Signed-off-by:')" 1 "  and signed"
has "$T/gh.args" "$BR-2" "  with its own PR"
git -C "$PUB" update-ref "refs/heads/$BR" "$SIGNED"; git -C "$PUB" update-ref -d "refs/heads/$BR-2"
git -C "$CLONE" update-ref -d "refs/heads/$BR-2"; git -C "$CLONE" update-ref -d "refs/remotes/origin/$BR-2"

echo "A later line." >> "$R/README.md"; git -C "$R" commit -qam "another"; git -C "$R" push -q origin main
check "$(FAKE_GH_FAIL=1 prun)" 2 "gh fails: exit 2"
has "$T/out" "but no PR" "  says the branch went up without a PR"
has "$T/out" "gh pr create --repo acme/film --base main --head $BR-2" "  a second branch the same day gets -2, and the command to open it"
check "$(git -C "$PUB" rev-parse main)" "$P3" "  the public main is still untouched"

grep -vxF config/render.yaml "$R/.helloworld/allowlist.txt" > "$T/al" && cp "$T/al" "$R/.helloworld/allowlist.txt"
git -C "$R" commit -qam "drop a file"; git -C "$R" push -q origin main
check "$(FAKE_GH_LOGIN=zq-machine FAKE_GH_PUBLIC_PR=https://github.com/acme/film/pull/1 prun)" 0 \
      "a tree that removes a public file, opened by a login already public in the org: a PR"
has "$T/gh.body" "(the PR's author is already public in this org); 0 findings" "  the body says the author was not scanned"
has "$T/gh.body" "Removes 1 file from main, not named here." "  the body counts the removed file"
lacks "$T/gh.body" "render.yaml" "  without naming it (a take-back must not be refused for its own subject)"
# A file merged on GitHub whose name holds a private word and a space; the take-back keeps its
# content under a clean name. The body names neither the old path nor a rename of it, counts the
# spaced path once, and an agent's output masks the word.
git -C "$T/gh" pull -q origin main; mkdir -p "$T/gh/docs"; echo "same words" > "$T/gh/docs/Harbourview notes.md"
git -C "$T/gh" add -A; git -C "$T/gh" commit -qm "A note"; git -C "$T/gh" push -q origin main
echo "same words" > "$R/docs/notes.md"; echo docs/notes.md >> "$R/.helloworld/allowlist.txt"
git -C "$R" add -A; git -C "$R" commit -qm "take back"; git -C "$R" push -q origin main
check "$(prun)" 0 "a take-back that renames a leaked file: a PR, not refused for naming it"
has "$T/gh.body" "Removes 2 files from main, not named here." "  a removed path with a space counts once"
lacks "$T/gh.body" "Harbourview" "  the body never names the old path, not even as a rename"
lacks "$T/out" "Harbourview" "  and the agent's output masks it in the diff-stat"

# A commit GitHub authored on the public main with a private address: PR mode refuses before any
# push, and publish does too. (The scratch public main is then put back, as the owner's hard push would.)
GOOD=$(git -C "$PUB" rev-parse main); git -C "$T/gh" pull -q origin main
GIT_AUTHOR_NAME=Someone GIT_AUTHOR_EMAIL=stand-in@private.example git -C "$T/gh" commit -q --allow-empty -m "Squash"
git -C "$T/gh" push -q origin main; before=$(pubrefs)
check "$(prun)" 1 "publish --pr: a private address in the public main's history: refused"
has "$T/out" "author: e-mail address" "  as an author"
has "$T/out" "Nothing was pushed" "  and says nothing was pushed"
check "$(pubrefs)" "$before" "  the public repo is unchanged"
check "$(GIT_CONFIG_GLOBAL="$T/gitconfig" pub "$NAME")" 1 "publish: the same history: refused before asking for the name"
has "$T/out" "author: e-mail address — stand-in@private.example" "  with the history finding in its output"
lacks "$T/out" "Type the public repo" "  before asking for the name"
git -C "$PUB" update-ref refs/heads/main "$GOOD"; git -C "$T/gh" reset -q --hard "$GOOD"

# .helloworld/identities at origin/main that lacks the address git would commit as: publish and
# publish --pr refuse (exit 2) and say where to add it, without printing the address.
git -C "$R" checkout -q -B noident main; printf 'someone-else@example.org\n' > "$R/.helloworld/identities"
git -C "$R" add -A; git -C "$R" commit -qm "identities"; git -C "$R" push -q -f origin noident:main 2>/dev/null
check "$(prun)" 2 "publish --pr: an identities file without the committing address: refused"
has "$T/out" "is not in .helloworld/identities" "  and said where to add it"
lacks "$T/out" "maker@example.org" "  without printing the address"
check "$(GIT_CONFIG_GLOBAL="$T/gitconfig" pub "$NAME")" 2 "publish: the same file: refused before asking for the name"
# A GitHub noreply committing address passes without a line, as the history scan and the files'
# headers promise; the private word in the title stops the run at the scan (1), so nothing is pushed.
git -C "$R" config user.email 9+maker@users.noreply.github.com; before=$(pubrefs)
check "$(prun -m 'From MyLaptop')" 1 "publish --pr: a noreply committing address, not listed: past the identities check"
lacks "$T/out" "is not in .helloworld/identities" "  without the identities refusal"
has "$T/out" "PR title:1: private word" "  stopped by the title, as planned"
lacks "$T/out" "e-mail address — 9+" "  and the noreply address is no finding (a guard on the identity scan's skips)"
check "$(pubrefs)" "$before" "  the public repo is unchanged"
git -C "$R" config user.email '9+maker[bot]@users.noreply.github.com'
check "$(prun)" 2 "publish --pr: a bot's noreply address, not listed: refused, the gate's commit is a person's"
has "$T/out" "is not in .helloworld/identities" "  with the identities refusal"
git -C "$R" config user.email noreply@github.com
check "$(prun)" 2 "publish --pr: GitHub's committer address as git's own: refused"
git -C "$R" config user.email maker@example.org
git -C "$R" push -q -f origin main:main 2>/dev/null; git -C "$R" checkout -q main

# A workflow merged on GitHub that lands PRs: the public main itself would merge the next one.
git -C "$T/gh" pull -q origin main; mkdir -p "$T/gh/.github/workflows"
printf 'on: pull_request_target\njobs: {m: {steps: [{run: gh pr merge --squash}]}}\n' > "$T/gh/.github/workflows/land.yml"
git -C "$T/gh" add -A; git -C "$T/gh" commit -qm "A workflow"; git -C "$T/gh" push -q origin main
echo "One more." >> "$R/README.md"; git -C "$R" commit -qam "one more"; git -C "$R" push -q origin main
check "$(prun)" 2 "a workflow on the public main that merges PRs: refused"
has "$T/out" "the public main has .github/workflows/land.yml — a PR would merge itself" "  and named"
check "$(gaterefs)" 0 "after every PR run, no ref of the gate's own in the private repo"

echo "the replay: the curated commits since the public main's tree, one by one (D1-B)"
# A second scratch pair: a private repo published once, then six commits of every kind. The
# agent trailers are assembled at run time, so this file carries no address or session link.
R2="$T/rp"; PUB2="$T/rp-public.git"
git init -q --bare -b main "$T/rp-origin.git"; git init -q --bare -b main "$PUB2"
git init -q -b main "$R2"; git -C "$R2" config user.name "Film Maker"; git -C "$R2" config user.email maker@example.org
git -C "$R2" config commit.gpgsign false; git -C "$R2" remote add origin "$T/rp-origin.git"
printf '[url "%s"]\n\tinsteadOf = https://github.com/acme/tool.git\n' "$PUB2" >> "$T/gitconfig"
mkdir -p "$R2/.helloworld"; printf '# Tool\n' > "$R2/README.md"; printf 'print(1)\n' > "$R2/tool.py"; printf 'a\n' > "$R2/notes.md"
printf 'README.md\ntool.py\n' > "$R2/.helloworld/allowlist.txt"; echo https://github.com/acme/tool.git > "$R2/.helloworld/remote"
# rc <subject> [body]: commit everything; up: send main to the scratch origin.
rc() { git -C "$R2" add -A; git -C "$R2" commit -q -m "$1" ${2:+-m "$2"}; }
up() { git -C "$R2" push -q origin main; }
rc "Docs: the first README"; up
python3 "$T/answer.py" acme/tool env -u CLAUDECODE GIT_CONFIG_GLOBAL="$T/gitconfig" python3 "$B/helloworld" publish "$R2" > "$T/out" 2>&1
check "$?" 0 "the first publish of a second twin (one commit, as ever)"
P0=$(git -C "$PUB2" rev-parse main)
CA1="Co-Authored-By: Claude Opus 5.5 <noreply@""anthropic.com>"
CA2="Co-authored-by: Claude Opus 4.6 (1M context) <noreply@""anthropic.com>"
CS="Claude-""Session: https://claude.ai/code/""sess""ion_01ABCDEFGHIJKLMN"
printf 'print(2)\n' > "$R2/tool.py"; rc "Tool: prints two" "Why: one was not enough.

$CA1
$CA2
$CS
Signed-off-by: Film Maker <maker@example.org>"
C1=$(git -C "$R2" rev-parse HEAD)
printf '# Tool, half\n' > "$R2/README.md"; rc "wip: changes between turns"
printf 'print(2)  # Harbourview\n' > "$R2/tool.py"; rc "Tool: a leak"
printf 'print(3)\n' > "$R2/tool.py"; rc "Tool: the leak taken back"
printf 'b\n' >> "$R2/notes.md"; rc "Project: notes"
printf '# Tool\nRun it.\n' > "$R2/README.md"; rc "Docs: the README says how to run it" "Written at the Harbourview house."
C6=$(git -C "$R2" rev-parse HEAD)
up
chk2() { GIT_CONFIG_GLOBAL="$T/gitconfig" env -u CLAUDECODE python3 "$B/helloworld" check "$R2" "$@" > "$T/out" 2>&1; echo $?; }
prun2() { GIT_CONFIG_GLOBAL="$T/gitconfig" PATH="$T/fakebin:$PATH" CLAUDECODE=1 TZ=America/Los_Angeles python3 "$B/helloworld" publish --pr "$R2" "$@" < /dev/null > "$T/out" 2>&1; echo $?; }
pub2refs() { git -C "$PUB2" for-each-ref --format='%(refname) %(objectname)' | sort; }
check "$(chk2)" 0 "check: the dry replay, nothing pushed"
has "$T/out" "replay: base $(git -C "$R2" rev-parse --short=7 main~6)" "  the base found by tree: the commit the first publish was made from"
has "$T/out" "3 commit(s) would go up, 2 folded, 1 private only" "  three commits, two folds, one private"
has "$T/out" "$(git -C "$R2" rev-parse --short=7 main~4)   fold: a checkpoint" "  a wip: commit folds"
has "$T/out" "$(git -C "$R2" rev-parse --short=7 main~3)   fold: its tree has 1 finding(s)" "  a leak planted in a middle commit folds"
has "$T/out" "→ Tool: the leak taken back [carries 2 folded]" "  into the next commit that passes"
has "$T/out" "private: no published file changed" "  a commit that changes no published file stays private"
has "$T/out" "→ Docs: the README says how to run it [its body has findings: the subject goes alone]" "  a body that fails: the subject alone"
check "$(pub2refs)" "refs/heads/main $P0" "  check pushed nothing"
check "$(prun2 --squash)" 0 "--squash: one commit, as before the replay"
BR2="claude/publish/$(TZ=UTC date +%F)-publish"
check "$(git -C "$PUB2" rev-list --count "$P0..$BR2")" 1 "  one commit on the public main"
has "$T/gh.body" "as one commit on main (squashed: on request)" "  the body says why"
git -C "$PUB2" update-ref -d "refs/heads/$BR2"
check "$(prun2)" 0 "publish --pr: the replay"
TIP=$(git -C "$PUB2" rev-parse "$BR2")
check "$(git -C "$PUB2" log --reverse --format=%s "$P0..$TIP" | tr '\n' '|')" \
      "Tool: prints two|Tool: the leak taken back|Docs: the README says how to run it|" "  three public commits, the curated subjects, in order"
leaked=0; for c in $(git -C "$PUB2" rev-list "$P0..$TIP"); do git -C "$PUB2" grep -q Harbourview "$c" && leaked=1; done
check "$leaked" 0 "  the planted leak is in no public tree"
check "$(git -C "$PUB2" log -1 --format=%B "$TIP~2" | sed '/^$/d' | tr '\n' '|')" \
      "Tool: prints two|Why: one was not enough.|Signed-off-by: Film Maker <maker@example.org>|" "  the body kept, every trailer dropped but the gate's Signed-off-by"
check "$(git -C "$PUB2" log --format=%B "$P0..$TIP" | grep -ciE 'co-authored-by|claude-session|anthropic')" 0 "  both Co-Authored-By spellings and the session link: gone"
check "$(git -C "$PUB2" log -1 --format=%B "$TIP" | sed '/^$/d' | tr '\n' '|')" \
      "Docs: the README says how to run it|Signed-off-by: Film Maker <maker@example.org>|" "  the failing body dropped, the subject alone"
check "$(git -C "$PUB2" log -1 --format='%at %ct' "$TIP~2")" "$(git -C "$R2" log -1 --format='%at %ct' "$C1")" "  each commit keeps its private dates"
check "$(git -C "$PUB2" log --format='%ai|%ci' "$P0..$TIP" | grep -c '+0000|.*+0000')" 3 "  in UTC"
check "$(git -C "$PUB2" log --format='%an <%ae>' "$P0..$TIP" | sort -u)" "Film Maker <maker@example.org>" "  under the publishing identity"
check "$(git -C "$PUB2" ls-tree -r "$TIP")" "$(git -C "$R2" ls-tree -r "$C6" README.md tool.py)" "  ending on origin/main's published files"
has "$T/gh.body" "as 3 commits replayed from the private history one by one, each scanned on its own, 2 folded into the commit after them, 1 with the subject alone" "  the body counts them"
lacks "$T/gh.body" "Harbourview" "  and names no fold's reason"
lacks "$T/gh.body" "$(git -C "$R2" rev-parse --short=7 "$C1")" "  nor a private sha"
git -C "$PUB2" update-ref -d "refs/heads/$BR2"
check "$(prun2)" 0 "the same span again, its branch gone"
check "$(git -C "$PUB2" rev-parse "$BR2")" "$TIP" "  the same shas: the dates are the private ones"
check "$(prun2)" 0 "  and with the branch there, nothing proposed twice"
has "$T/out" "branch $BR2 already has exactly this tree" "  (a replay of three counts as on top of the public main)"

printf 'print(4)\n' > "$R2/tool.py"; rc "Tool: tuned on MyLaptop"; C7=$(git -C "$R2" rev-parse HEAD); up
before=$(pub2refs)
check "$(chk2)" 0 "check: a subject the scan refuses is printed, not counted (a work branch's checkpoints)"
has "$T/out" "replay REFUSED: ${C7:0:7}'s subject has a private word — MyLaptop" "  as the replay's refusal"
has "$T/out" ".helloworld/messages: ${C7:0:12} <a public subject>" "  naming the fix"
check "$(prun2)" 1 "publish --pr: a private word in a replayed subject: refused"
has "$T/out" "replay ${C7:0:12} subject: private word — My…" "  as that commit's subject, masked"
has "$T/out" "in .helloworld/messages" "  with the override line to add"
check "$(pub2refs)" "$before" "  nothing pushed"
printf '# reviewed\n%s Tool: tuned\n' "${C7:0:12}" > "$R2/.helloworld/messages"; rc "Project: a public subject for the tuning commit"; up
check "$(prun2)" 0 "with its line in .helloworld/messages: the run goes on"
check "$(git -C "$PUB2" log -1 --format=%s "$BR2-2")" "Tool: tuned" "  the commit goes up under the reviewed subject"
check "$(git -C "$PUB2" rev-list --count "$P0..$BR2-2")" 4 "  after the three before it"
printf '%s nope\n' "zz" > "$R2/.helloworld/messages"; rc "Project: a bad line"; up
check "$(chk2)" 2 "a messages line that is not <sha> <subject>: refused"
has "$T/out" "is not <private sha> <public subject>" "  and said"
git -C "$R2" revert --no-edit HEAD > /dev/null; up
# The reviewed ref's lists bound every public tree: a file and a credit it took back fold, and a
# replayed message meets the whole word list, a credit or not (the /finish review, 2026-10-20).
BEFORE=$(git -C "$R2" rev-parse HEAD)
printf 'README.md\ntool.py\nnotes.md\nCREDITS.yaml\n' > "$R2/.helloworld/allowlist.txt"; printf 'people:\n  - {name: "Zed Quill"}\n' > "$R2/CREDITS.yaml"
rc "Project: the notes and a credit go public"; CX=$(git -C "$R2" rev-parse HEAD)
printf 'README.md\ntool.py\n' > "$R2/.helloworld/allowlist.txt"; rm "$R2/CREDITS.yaml"; printf 'print(5)\n' > "$R2/tool.py"; rc "Tool: five"; up
check "$(chk2)" 0 "a file and a credit allowlisted, then taken back: check passes"
has "$T/out" "${CX:0:7}   fold: its lists hold 3 entr(ies) origin/main took back" "  the commit that listed them folds"
check "$(prun2)" 0 "  publish --pr: the replay goes up"
leaked=0; for c in $(git -C "$PUB2" rev-list --all); do git -C "$PUB2" cat-file -e "$c:notes.md" 2>/dev/null && leaked=1; done
check "$leaked" 0 "  the taken-back file is in no public tree"
printf 'README.md\ntool.py\nCREDITS.yaml\n' > "$R2/.helloworld/allowlist.txt"; printf 'people:\n  - {name: "Zed Quill"}\n' > "$R2/CREDITS.yaml"; rc "Project: the credits go public"
printf 'print(6)\n' > "$R2/tool.py"; rc "Tool: six, reviewed by Zed Quill"; CQ=$(git -C "$R2" rev-parse HEAD); up
check "$(chk2)" 0 "a credited name in a replayed subject: printed, not counted"
has "$T/out" "replay REFUSED: ${CQ:0:7}'s subject has a private word" "  refused all the same: a credit is consent for the tree, not the message"
git -C "$R2" diff --binary HEAD "$BEFORE" | git -C "$R2" apply; rc "Project: back as it was"; up

# A message's own patterns (D2 of the S2 digest, the owner's A, 2026-10-20): a sha, a cross-repo
# ref, a session id. Made up, the session id assembled at run time like the trailers above.
P_SHA="1a2b3c4d"; P_REF="acme/tool#12"; P_REPO="tool#3"; P_URL="github.com/acme/tool/pull/12"
P_UUID="12345678-90ab-cdef-1234-567890abcdef"; P_SID="sess""ion_9XYZ12345"
printf '%s Tool: six\n' "${CQ:0:12}" >> "$R2/.helloworld/messages"; rc "Project: a public subject for the credited commit"
n=7; BODIES=""
for v in "$P_SHA" "$P_REF" "$P_REPO" "$P_URL" "$P_UUID" "$P_SID"; do
  printf 'print(%s)\n' "$n" > "$R2/tool.py"; rc "Tool: $n" "Why: as $v said."; BODIES="$BODIES|Tool: $n"; n=$((n+1))
done
up
check "$(chk2)" 0 "a body with a sha, a cross-repo ref or a session id: check passes"
for k in 7 8 9 10 11 12; do
  has "$T/out" "→ Tool: $k [its body has findings: the subject goes alone]" "  Tool: $k's body is dropped"
done
lacks "$T/out" "replay REFUSED" "  and no subject is refused"
check "$(prun2 -m "Publish after $P_SHA")" 1 "publish --pr: a sha in the PR title (a squash's or a tail's message): refused"
has "$T/out" "PR title: commit sha — $P_SHA" "  and named"
check "$(prun2 -m "Publish for $P_REF")" 1 "publish --pr: a cross-repo ref in the PR title: refused"
check "$(prun2)" 0 "publish --pr: the replay goes up without those bodies"
TIPD=$(git -C "$PUB2" for-each-ref --sort=-creatordate --format='%(objectname)' refs/heads/claude/publish | head -1)
check "$(git -C "$PUB2" log --format=%B "$P0..$TIPD" | grep -cE "$P_SHA|tool#|acme/tool/pull|$P_UUID|$P_SID")" 0 "  no public commit carries any of them"
check "$(git -C "$PUB2" log -1 --format=%B "$TIPD" | sed '/^$/d' | tr '\n' '|')" \
      "Tool: 12|Signed-off-by: Film Maker <maker@example.org>|" "  the subject alone, then the gate's trailer"
BEFORE=$(git -C "$R2" rev-parse HEAD)
for v in "$P_SHA" "$P_REF" "$P_REPO" "$P_URL" "$P_UUID" "$P_SID"; do
  printf 'print(%s)\n' "$n" > "$R2/tool.py"; rc "Tool: after $v"; n=$((n+1))
done
SUBJ=$(git -C "$R2" rev-list --reverse "$BEFORE..HEAD" | tr '\n' ' '); up
check "$(chk2)" 0 "a subject with a sha, a cross-repo ref or a session id: printed, not counted"
set -- $SUBJ
has "$T/out" "replay REFUSED: ${1:0:7}'s subject has a commit sha — $P_SHA" "  a sha refuses its subject, the commit named"
has "$T/out" "replay REFUSED: ${2:0:7}'s subject has a cross-repo ref — $P_REF" "  owner/repo#N refuses"
has "$T/out" "replay REFUSED: ${3:0:7}'s subject has a cross-repo ref — $P_REPO" "  repo#N refuses"
has "$T/out" "replay REFUSED: ${4:0:7}'s subject has a cross-repo ref — $P_URL" "  a link to a pull refuses"
has "$T/out" "replay REFUSED: ${5:0:7}'s subject has a session id — $P_UUID" "  a uuid refuses"
has "$T/out" "replay REFUSED: ${6:0:7}'s subject has a session id — $P_SID" "  session_<id> refuses"
lacks "$T/out" "replay REFUSED: ${5:0:7}'s subject has a commit sha" "  a uuid's hex blocks are not a sha too"
before=$(pub2refs)
check "$(prun2)" 1 "  publish --pr refuses them"
check "$(pub2refs)" "$before" "  nothing pushed"
set --
git -C "$R2" diff --binary HEAD "$BEFORE" | git -C "$R2" apply; rc "Project: back as it was, again"; up

# An open replay branch vouches only for trees this run scans (review 2026-10-20): a word added
# to the list since must not ride in on an earlier commit's tree when that branch is merged.
for c in $SUBJ; do printf '%s Tool: after a reference\n' "${c:0:12}" >> "$R2/.helloworld/messages"; done
rc "Project: public subjects for the six refused above"
BEFORE=$(git -C "$R2" rev-parse HEAD)
printf 'print(50)  # Gizmoworks\n' > "$R2/tool.py"; rc "Tool: fifty"
printf 'print(51)\n' > "$R2/tool.py"; rc "Tool: fifty-one"; up
check "$(prun2 --topic vouch)" 0 "two commits go up as a replay branch"
check "$(prun2 --topic vouch)" 0 "  run again: that open branch is enough"
has "$T/out" "nothing to propose — branch" "  and named"
cp "$HELLOWORLD_WORDLIST" "$T/words.bak"; echo Gizmoworks >> "$HELLOWORLD_WORDLIST"
before=$(pub2refs)
check "$(prun2 --topic vouch)" 0 "the first commit's word now listed: the open branch is not enough"
lacks "$T/out" "nothing to propose" "  it pushes the replay as it stands"
check "$([ "$(pub2refs)" != "$before" ] && echo pushed)" pushed "  a new branch went up"
mv "$T/words.bak" "$HELLOWORLD_WORDLIST"
git -C "$R2" diff --binary HEAD "$BEFORE" | git -C "$R2" apply; rc "Project: back as it was, a third time"; up

echo "check-message: one message as the replay would scan it, when the private commit is made (D2)"
cm() { env -u CLAUDECODE python3 "$B/helloworld" check-message "$@" > "$T/out" 2>&1; echo $?; }
printf 'Why: it was slow.\n' > "$T/body"
check "$(cm --subject 'Tool: faster' --body-file "$T/body")" 0 "a clean subject and body pass"
has "$T/out" "clean: the subject and body would go public as written" "  and said"
check "$(cm --subject 'Wharf: the Gizmo host takes the runs')" 0 "a product name off the list passes (the owner's answer to D2)"
check "$(cm --subject 'Core: read session_id from the hook, as #12 said')" 0 "session_id is a word, a bare #12 this repo's own"
i=0
for v in "$P_SHA" "$P_REF" "$P_REPO" "$P_URL" "$P_UUID" "$P_SID"; do
  i=$((i+1)); case $i in 1) cat="commit sha";; 2|3|4) cat="cross-repo ref";; *) cat="session id";; esac
  printf 'After %s.\n' "$v" > "$T/body"
  check "$(cm --subject 'Tool: x' --body-file "$T/body")" 1 "a body with a $cat ($v): a finding"
  has "$T/out" "body:1: $cat — $v (the replay drops this body)" "  the replay would drop it"
  check "$(cm --subject "Tool: after $v")" 1 "a subject with a $cat: a finding"
  has "$T/out" "subject: $cat — $v (the replay refuses this subject)" "  the replay would refuse it"
done
printf 'Tool: faster\n\nWhy: it was slow.\n\n%s\n%s\n' "$CA1" "$CS" > "$T/msg"
check "$(cm --message-file "$T/msg")" 0 "--message-file: the trailers are dropped first, as the replay drops them"
check "$(printf 'Tool: on MyLaptop\n' | CLAUDECODE=1 python3 "$B/helloworld" check-message --message-file - 2>&1 > "$T/out"; echo $?)" 1 \
      "a private word in the subject, from stdin: a finding"
has "$T/out" "subject: private word — My…" "  masked in an agent's shell"
check "$(cm --body-file "$T/body")" 2 "no subject: a usage error"
for v in github.com/acme/tool/issues/4 github.com/acme/tool/commit/abc github.com/acme/tool/blob/main/x.py \
         https://github.com/acme/tool a/b/c#5; do
  check "$(cm --subject "Tool: see $v")" 1 "a subject with $v: a cross-repo ref"
done
printf 'Tool: faster\n\nWhy: it was slow.\n\n# On branch claude/MyLaptop/x\n# ------------------------ >8 ------------------------\nOZ diff\n' > "$T/msg"
check "$(cm --message-file "$T/msg")" 0 "a commit-msg hook's file: git's comment block and the diff below the scissors are cut"
printf 'Tool: faster\n\nDeployed: on MyLaptop\nStood-By: autofinish\n' > "$T/msg"
check "$(cm --message-file "$T/msg")" 0 "Deployed: and Stood-By: are dropped with the trailers"
check "$(cm --message-file "$T/nothing-here")" 2 "a file it cannot read: exit 2, not a finding"
check "$(cm --subject 'Tool: x' --message-file "$T/msg")" 2 "--subject with --message-file: refused, not one ignored"

git clone -q "$PUB2" "$T/gh2"; git -C "$T/gh2" config user.name gh; git -C "$T/gh2" config user.email 7+gh@users.noreply.github.com
printf 'people:\n  - {name: "New Person"}\n' > "$T/gh2/CREDITS.yaml"; git -C "$T/gh2" add -A; git -C "$T/gh2" commit -qm "A credit"
git -C "$T/gh2" push -q origin main
P9=$(git -C "$PUB2" rev-parse main)
check "$(chk2)" 0 "a credit merged on GitHub: check passes"
has "$T/out" "no commit on origin/main's line has the public main's tree" "  and says the replay has no base"
has "$T/out" "publish --pr squashes, one commit" "  so a publish squashes"
check "$(prun2)" 0 "publish --pr after a credit merged on GitHub: the span squashes"
SQ=$(git -C "$PUB2" for-each-ref --sort=-creatordate --format='%(refname)' refs/heads/claude/publish | head -1)
check "$(git -C "$PUB2" rev-list --count "$P9..$SQ")" 1 "  one commit on the new public main"
check "$(git -C "$PUB2" log -1 --format=%s "$SQ")" "Publish $(TZ=UTC date +%F)" "  under the run's title"
has "$T/gh.body" "squashed: no private commit has the public main's tree" "  the body says why"
python3 "$B/helloworld" publish "$R2" --squash > "$T/out" 2>&1
check "$?" 2 "--squash without --pr: a usage error"

echo
[ $fails -eq 0 ] && echo "all passed" || { echo "$fails FAILED"; exit 1; }
