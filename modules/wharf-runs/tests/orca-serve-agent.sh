#!/usr/bin/env bash
# Tests for bin/orca-serve-agent --dry-run on `here`: the LaunchAgent label read from the config dir
# (the default without the key, the configured one with it, the first non-blank line), the previous
# label only when its key exists, a label that is not a launchd label refused, and nothing written or
# run. Then the Linux branch (ORCA_SERVE_UNAME=Linux): the systemd user unit orca-serve.service,
# the guest's wrapper or orca-ide serve on the Tailscale address, output to null, linger, another
# serving unit refused, --remove, a real run against stand-ins, and the unit equal to the one the
# guest's cloud-init writes. Scratch HOME and config; no Orca, no launchctl, no systemd, no network.
#   bash modules/wharf-runs/tests/orca-serve-agent.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }
has()   { case "$1" in *"$2"*) echo "  ok   $3";; *) echo "  FAIL $3: [$2] not in [${1:0:300}]"; fails=$((fails+1));; esac; }
hasnt() { case "$1" in *"$2"*) echo "  FAIL $3: [$2] in [${1:0:300}]"; fails=$((fails+1));; *) echo "  ok   $3";; esac; }
mkdir -p "$T/home" "$T/cfg/wharf-runs"
# The Mac cases pin the platform: on an Ubuntu runner (the public twin's CI) uname says Linux.
sa() { env -u REGATTA_HOME ORCA_SERVE_UNAME=Darwin HOME="$T/home" REGATTA_CONFIG="$T/cfg" bash "$M/bin/orca-serve-agent" "$@" 2>&1; }

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
out=$(env -u REGATTA_HOME ORCA_SERVE_UNAME=Darwin HOME="$H2" REGATTA_CONFIG="$T/cfg" bash "$M/bin/orca-serve-agent" here --dry-run 2>&1); check $? 2 "an orca serve agent under an unknown label: exit 2"
has "$out" "net.other.serve.plist already runs orca serve" "  and the line names it"
echo "net.other.serve" > "$T/cfg/wharf-runs/serve-label-previous"
out=$(env -u REGATTA_HOME ORCA_SERVE_UNAME=Darwin HOME="$H2" REGATTA_CONFIG="$T/cfg" bash "$M/bin/orca-serve-agent" here --dry-run 2>&1); check $? 0 "  named as the previous label: taken back instead"
has "$out" "+ launchctl bootout gui/$(id -u)/net.other.serve" "  its agent booted out"

echo "orca-serve-agent: Linux, the systemd user unit"
L="$T/linux"; LH="$L/home"; LB="$L/bin"; mkdir -p "$LH" "$LB"
log="$L/calls"; : > "$log"
# stand-ins: each logs its argv; loginctl answers the Linger value in $L/linger
for c in systemctl pkill screen; do printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$c" "$log" > "$LB/$c"; done
printf '#!/bin/sh\nexit 1\n' > "$LB/pgrep"
printf '#!/bin/sh\necho 192.0.2.51\n' > "$LB/tailscale"
printf '#!/bin/sh\nif [ "$1" = show-user ]; then cat "%s"; else echo "loginctl $*" >> "%s"; fi\n' "$L/linger" "$log" > "$LB/loginctl"
printf '#!/bin/sh\nif [ "$1" = status ]; then echo "{\\"state\\": \\"ready\\"}"; fi\n' > "$LB/orca-ide"
chmod +x "$LB"/*
echo no > "$L/linger"
lsa() { env -u REGATTA_HOME -u XDG_CONFIG_HOME -u XDG_RUNTIME_DIR HOME="$LH" REGATTA_CONFIG="$T/cfg" PATH="$LB:$PATH" \
  ORCA_SERVE_UNAME=Linux ORCA_SERVE_WRAPPER="${WRAP:-$L/no-wrapper}" bash "$M/bin/orca-serve-agent" "$@" 2>&1; }
units="$LH/.config/systemd/user"
out=$(lsa here --dry-run); check $? 0 "--dry-run here on Linux succeeds"
check "$(printf '%s\n' "$out" | sed -n 1p)" "unit: orca-serve.service" "  the unit is orca-serve.service, the serve-label keys unread"
has "$out" "unit file: $units/orca-serve.service" "  under the user's systemd dir"
has "$out" "ExecStart=$LB/orca-ide serve --pairing-address 192.0.2.51" "  no wrapper: orca-ide serve on the Tailscale address"
has "$out" "StandardOutput=null" "  output to null (the pairing link is a credential)"
has "$out" "StandardError=null" "  and errors too"
has "$out" "WantedBy=default.target" "  a unit of the user's default target"
has "$out" "+ loginctl enable-linger $(id -un)" "  linger off: turned on"
has "$out" "+ systemctl --user restart orca-serve.service" "  the unit restarted"
hasnt "$out" "launchctl" "  and no launchctl"
hasnt "$out" "Library" "  and no LaunchAgents path"
[ ! -e "$units" ]; check $? 0 "  and nothing written"
echo yes > "$L/linger"
out=$(lsa here --dry-run)
hasnt "$out" "enable-linger" "linger already on: left alone"

echo "orca-serve-agent: Linux, the guest's own unit"
printf '#!/bin/sh\n' > "$L/orca-serve-node"; chmod +x "$L/orca-serve-node"
out=$(WRAP="$L/orca-serve-node" lsa here --dry-run)
has "$out" "ExecStart=$L/orca-serve-node" "the guest's wrapper present: the unit runs it"
hasnt "$out" "--pairing-address" "  and leaves the address to it"
# the unit as the guest's cloud-init writes it: its content block, dedented, the wrapper at its real path.
# node/ is private until the wharf-runs scrub, so the public twin skips this case.
if [ -f "$M/node/agent.user-data.yaml" ]; then
  awk '/orca-serve.service$/ {f=1; next} f && /content: \|/ {c=1; next} c && !/^      / && !/^$/ {exit} c {sub(/^      /, ""); print}' \
    "$M/node/agent.user-data.yaml" > "$L/node.unit"
  printf '%s\n' "$out" | awk '/^\[Unit\]$/ {f=1} f {print} /^WantedBy=/ {exit}' | sed "s|$L/orca-serve-node|/usr/local/bin/orca-serve-node|" > "$L/agent.unit"
  [ -s "$L/node.unit" ] && diff "$L/node.unit" "$L/agent.unit" >/dev/null; check $? 0 "  the unit is the one the guest's cloud-init writes, line for line"
else echo "  --   the guest's unit: node/ not in this checkout, skipped"; fi

echo "orca-serve-agent: Linux, another unit serving, --remove"
mkdir -p "$units"
printf '[Service]\nExecStart=/opt/other/orca-ide serve --port 6768\n' > "$units/hand-orca.service"
out=$(lsa here --dry-run); check $? 2 "another unit running orca serve: exit 2"
has "$out" "hand-orca.service already runs orca serve" "  and the line names it"
rm "$units/hand-orca.service"
out=$(lsa here --dry-run --remove)
has "$out" "+ systemctl --user disable --now orca-serve.service" "--remove: the unit stopped and disabled"
has "$out" "+ rm -f $units/orca-serve.service" "  its file removed"
has "$out" "+ systemctl --user daemon-reload" "  and systemd told"

echo "orca-serve-agent: Linux, a real run against stand-ins"
echo no > "$L/linger"
out=$(lsa here); check $? 0 "the run succeeds"
has "$out" "ready under orca-serve.service" "  and says the server is ready"
has "$(cat "$units/orca-serve.service" 2>/dev/null)" "ExecStart=$LB/orca-ide serve --pairing-address 192.0.2.51" "  the unit written"
[ ! -e "$units/orca-serve.service.new" ]; check $? 0 "  no .new left behind"
calls=$(cat "$log")
has "$calls" "loginctl enable-linger $(id -un)" "  linger turned on"
has "$calls" "systemctl --user daemon-reload" "  systemd reloaded"
has "$calls" "systemctl --user enable orca-serve.service" "  the unit enabled"
has "$calls" "systemctl --user restart orca-serve.service" "  and restarted"
exit $fails
