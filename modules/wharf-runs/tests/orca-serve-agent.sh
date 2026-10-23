#!/usr/bin/env bash
# Tests for bin/orca-serve-agent --dry-run on `here`: the LaunchAgent label read from the config dir
# (the default without the key, the configured one with it, the first non-blank line), the previous
# label only when its key exists, a label that is not a launchd label refused, and nothing written or
# run. Scratch HOME and config; no Orca, no launchctl, no network (a dry run only reads).
#   bash modules/wharf-runs/tests/orca-serve-agent.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:300}]"; fails=$((fails+1));; esac; }
hasnt() { case "$1" in *"$2"*) echo "  FAIL $3: [$2] in [${1:0:300}]"; fails=$((fails+1));; *) echo "  ok   $3";; esac; }
mkdir -p "$T/home" "$T/cfg/wharf-runs"
sa() { env -u REGATTA_HOME HOME="$T/home" REGATTA_CONFIG="$T/cfg" bash "$M/bin/orca-serve-agent" "$@" 2>&1; }

echo "orca-serve-agent: syntax, and ASCII only (a C-locale bash over ssh misreads a multibyte character)"
bash -n "$M/bin/orca-serve-agent"; check $? 0 "bash -n"
LC_ALL=C grep -q '[^ -~	]' "$M/bin/orca-serve-agent"; check $? 1 "no byte outside printable ASCII and tab"

echo "orca-serve-agent: the label"
out=$(sa here --dry-run); check $? 0 "--dry-run here succeeds"
check "$(printf '%s\n' "$out" | sed -n 1p)" "label: org.regatta.orca-serve" "no key: the default label"
has "$out" "<key>Label</key><string>org.regatta.orca-serve</string>" "  and the plist carries it"
has "$out" "plist: $T/home/Library/LaunchAgents/org.regatta.orca-serve.plist" "  at the user's LaunchAgents path"
hasnt "$out" "previous label" "  and no previous-label line"
check "$(printf '%s\n' "$out" | grep -c 'launchctl bootout')" 1 "  and one bootout only (its own label), none for an older one"
printf '\n  \n  com.example.serve  \r\nignored.second.line\n' > "$T/cfg/wharf-runs/serve-label"
out=$(sa here --dry-run)
check "$(printf '%s\n' "$out" | sed -n 1p)" "label: com.example.serve" "key set: its first non-blank line, trimmed"
has "$out" "<key>Label</key><string>com.example.serve</string>" "  and the plist carries it"
hasnt "$out" "previous label" "  and still no previous-label line without its key"
has "$out" "+ launchctl bootstrap gui/$(id -u) $T/home/Library/LaunchAgents/com.example.serve.plist" "  and the bootstrap command names it"

echo "orca-serve-agent: the previous label"
echo "org.example.old" > "$T/cfg/wharf-runs/serve-label-previous"
out=$(sa here --dry-run)
has "$out" "previous label: org.example.old" "key set: the line is printed"
has "$out" "+ launchctl bootout gui/$(id -u)/org.example.old" "  its agent booted out"
has "$out" "+ rm -f $T/home/Library/LaunchAgents/org.example.old.plist" "  its plist removed"
echo "com.example.serve" > "$T/cfg/wharf-runs/serve-label-previous"
out=$(sa here --dry-run)
hasnt "$out" "previous label" "equal to the label: ignored, never booted out"
echo "org.example.old" > "$T/cfg/wharf-runs/serve-label-previous"
out=$(sa here --dry-run --remove)
has "$out" "+ launchctl bootout gui/$(id -u)/com.example.serve" "--remove: the agent booted out"
has "$out" "+ rm -f $T/home/Library/LaunchAgents/com.example.serve.plist" "  its plist removed"
has "$out" "+ launchctl bootout gui/$(id -u)/org.example.old" "  and the previous one too"
hasnt "$out" "launchctl bootstrap" "  and nothing started"

echo "orca-serve-agent: refusals, and nothing changed"
echo "bad label" > "$T/cfg/wharf-runs/serve-label-previous"
out=$(sa here --dry-run); check $? 2 "a previous label with a space: exit 2"
has "$out" "serve-label-previous is not a launchd label" "  and the line says so"
echo "org.example.old" > "$T/cfg/wharf-runs/serve-label-previous"
printf '\xef\xbb\xbfcom.bom.label\r\n' > "$T/cfg/wharf-runs/serve-label"
out=$(sa here --dry-run)
check "$(printf '%s\n' "$out" | sed -n 1p)" "label: com.bom.label" "a BOM and a CR: dropped"
printf 'com.\xc3\xa9x\n' > "$T/cfg/wharf-runs/serve-label"
out=$(LC_ALL=en_US.UTF-8 sa here --dry-run); check $? 2 "a non-ASCII label under a UTF-8 locale: exit 2"
echo "not a label" > "$T/cfg/wharf-runs/serve-label"
out=$(sa here --dry-run); check $? 2 "a label with a space: exit 2"
has "$out" "serve-label is not a launchd label" "  and the line says so"
echo "com.example.serve" > "$T/cfg/wharf-runs/serve-label"
out=$(sa here --frobnicate); check $? 2 "an unknown argument: exit 2"
out=$(sa); check $? 1 "no host: usage, exit 1"
[ ! -e "$T/home/Library" ]; check $? 0 "the dry runs wrote nothing under HOME"

echo "orca-serve-agent: another agent already serving"
H2="$T/home2"; mkdir -p "$H2/Library/LaunchAgents"
printf '<plist><dict><key>Label</key><string>net.other.serve</string><key>ProgramArguments</key><array><string>/Applications/Orca.app/Contents/Resources/bin/orca</string><string>serve</string></array></dict></plist>\n' > "$H2/Library/LaunchAgents/net.other.serve.plist"
out=$(env -u REGATTA_HOME HOME="$H2" REGATTA_CONFIG="$T/cfg" bash "$M/bin/orca-serve-agent" here --dry-run 2>&1); check $? 2 "an orca serve agent under an unknown label: exit 2"
has "$out" "net.other.serve.plist already runs orca serve" "  and the line names it"
echo "net.other.serve" > "$T/cfg/wharf-runs/serve-label-previous"
out=$(env -u REGATTA_HOME HOME="$H2" REGATTA_CONFIG="$T/cfg" bash "$M/bin/orca-serve-agent" here --dry-run 2>&1); check $? 0 "  named as the previous label: taken back instead"
has "$out" "+ launchctl bootout gui/$(id -u)/net.other.serve" "  its agent booted out"
exit $fails
