#!/usr/bin/env python3
"""fence — where a council arm runs: one macOS seatbelt over the arm's box, one proxy as its only door out,
a scratch home holding its own login alone, and only until the CLI has signed in, an environment built from
nothing, and the record read from each CLI's own log. docs/principal-council-isolation-2026-10-29.md, F3–F5,
F7 and S1, as amended by "The council's decision", S0's probes and the owner's word of 2026-10-30 (its
probes/record.md, sections P and Q). Stdlib, Python 3.9.

The box: <arm dir>/box, the one folder an arm may write — `copy/` (the commit's tree), `home/` (its scratch
home), `tmp/`. What the caller keeps (the prompt, the paper, the CLI's log, the proxy's log, the profile)
sits beside the box, out of the arm's reach: a log the record is read from is never one the arm could edit.

    profile(box, port, reads, ro)      the seatbelt's text: h-lib's narrowed template (H6) with P2's network
    probe(profile_path, box, port)     [] when the profile holds, else each case that did not (no model call)
    wrap(argv, profile_path)           argv under sandbox-exec
    Proxy(hosts, research, log, on_vendor)   the door: CONNECT and plain http, every address judged at connect
                                       time; ON_VENDOR runs once, at the first allowed connection to a vendor host
    arm_home(cli, box, ...)            the scratch home: (env additions, paths kept read-only, its Credential)
    Credential / FirstTool / f7()      F7: the login withdrawn at the first vendor connection, read at the first
                                       tool call, its strings looked for in every file the arm leaves
    arm_env(cli, box, port, home_env)  the environment, from an allowlist (env -i), never the caller's
    drop_box(box)                      the per-run keychain deleted, the box removed
    codex_features / claude_mcp        the gates, from each CLI's own listing, never a model's word
    features_diff(listing)             `codex features list` against the pinned CODEX_FEATURES (S5's re-probe)
    outcomes(cli, log) / offered(cli, log)   the shell commands a log shows run, with their output; the tools
                                       its init event offers (S5's `council fences` judges both)
    record(cli, log, tools)            F5: tool counts, the commands, and why the arm fails
    leave_paths(root) / leave_text(text)          what may not leave: a vault folder, an env file, a credential

Every arm on macOS only: available() is False elsewhere, and a caller refuses the arm (S6 brings a guest).
Nothing here calls a model.
"""
import hashlib
import ipaddress
import json
import os
import re
import select
import shlex
import shutil
import socket
import socketserver
import stat
import subprocess
import sys
import tempfile
import threading
import time

SANDBOX_EXEC = "/usr/bin/sandbox-exec"
SECURITY = "/usr/bin/security"

# the OS's folders an arm reads (h-lib.sh's template, H6), /Library narrowed by S4's trial: with none of it, the three
# CLIs, curl through the proxy and their live turns ran, while /usr/bin/git and python3 (xcrun's shims) died loading
# libxcrun from the developer dir; so of /Library only that dir, CommandLineTools here, and developer_dir() adds
# the one `xcode-select -p` names when it is elsewhere (an Xcode.app). The unified log keeps no seatbelt report for
# a sandbox-exec'd process, so the list is by trial, not by trace (the doc's "S4 as built").
# Of the OS's db folder only the timezone /etc/localtime names (the seventh landing review: the folder whole held the
# contacts' interaction history, login items, spindump's binary paths and power logs, most of it world-readable), and
# of /dev nothing here: DEV_RULES opens the device nodes a CLI needs and the arm's own ptys, never the owner's
# terminals (the same review: an arm read and wrote another terminal's /dev/ttys node).
VAR_DB = "/private/var/db"
OS_READS = ("/usr", "/bin", "/sbin", "/System", "/Library/Developer/CommandLineTools", "/private/etc",
            os.path.join(VAR_DB, "timezone"), "/private/var/select", "/private/var/run", "/opt/homebrew")
# Apple's shape (its application.sb and com.apple.neagent.sb): a pty only with the sandbox's own pty extension, which
# a pty opened inside the seatbelt carries; /dev itself readable (ttyname() needs the folder); xcrun's link where
# `xcode-select -s` made one
DEV_RULES = """(allow pseudo-tty)
(allow file-read* (literal "/dev") (literal "/dev/autofs_nowait") (literal "%s"))
(allow file-read* file-write* file-ioctl (literal "/dev/null") (literal "/dev/zero") (literal "/dev/random")
  (literal "/dev/urandom") (literal "/dev/dtracehelper") (literal "/dev/tty") (literal "/dev/ptmx") (subpath "/dev/fd"))
(allow file-read* file-write* file-ioctl (require-all (regex #"^/dev/ttys[0-9]+$") (extension "com.apple.sandbox.pty")))""" % (
    os.path.join(VAR_DB, "xcode_select_link"))
_DEVDIR = []

# The hosts each CLI needed through the proxy with research off, as exact names (record P2): a suffix such as
# googleapis.com would admit anyone's bucket. Claude's list has no OAuth refresh host, so a copied token is never
# rotated from an arm; with CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC its telemetry host is not asked for.
VENDOR_HOSTS = {
    "claude": ("api.anthropic.com",),
    "codex": ("chatgpt.com", "ab.chatgpt.com"),
    "agy": ("daily-cloudcode-pa.googleapis.com", "oauth2.googleapis.com", "www.googleapis.com", "play.googleapis.com",
            "antigravity-unleash.goog", "lh3.googleusercontent.com"),
}
PORTS = (443,)            # always; 80 too with research on (plain http)

# Codex 0.162.1's features that are on, each judged (codex features list, record S0; probes/codex-features-0.162.1.txt).
# "off": the arm passes --disable (the Equal terms row, plus the four S1 names) — hygiene, not a fence: a shell can
# start codex again without them, and the account's connectors travel over chatgpt.com, the inference host (P4), so
# what holds is F7, the login gone from disk once codex signed in; "kept": judged harmless to the arm, the shell and
# code mode among them. A feature that is on and not here refuses the arm until it is judged (S1: "a new `stable
# true` name refusing the arm"). codex-cli 0.166.0 turned nine more on (S4's live turn was refused on them,
# probes/codex-features-0.166.0.txt), judged by name, as its binary describes none: off, what reaches plugins, MCP
# OAuth, a setup wizard, API-key programs or an unnamed CLI mode; kept, the model and tool plumbing a turn runs on.
CODEX_FEATURES = {
    "apps": "off", "plugins": "off", "remote_plugin": "off", "plugin_sharing": "off", "skill_mcp_dependency_install": "off",
    "workspace_dependencies": "off", "browser_use": "off", "browser_use_external": "off", "browser_use_full_cdp_access": "off",
    "computer_use": "off", "image_generation": "off", "multi_agent": "off", "daemon_auto_start": "off", "hooks": "off",
    "shell_tool": "kept", "unified_exec": "kept", "code_mode_host": "kept",
    "api_key_model_discovery": "kept", "auth_elicitation": "kept", "browser_annotation_api": "kept",
    "compaction_image_budget": "kept", "content_item_kinds": "kept", "enable_request_compression": "kept",
    "fast_mode": "kept", "goals": "kept", "guardian_approval": "kept", "guardian_reuse_parent_compaction": "kept",
    "in_app_browser": "kept", "in_app_chat": "kept", "in_app_dictation": "kept", "in_app_local_automation": "kept",
    "in_app_updates": "kept", "in_app_voice": "kept", "mentions_v2": "kept", "realtime_conversation": "kept",
    "shell_snapshot": "kept", "skill_search": "kept", "sleep_tool": "kept", "system_proxy_fallback": "kept",
    "tool_call_mcp_elicitation": "kept", "tool_suggest": "kept", "ultrafast_mode": "kept",
    "unbounded_connection_retries": "kept", "unified_exec_tty": "kept", "view_image": "kept", "worktrees": "kept",
    "write_stdin_approval": "kept", "instant_interrupt": "kept",
    "api_key_cyber_access_programs": "off", "bedrock_setup_wizard": "off", "cli_daybreak": "off",
    "mcp_oauth_refresh_coordination": "off", "plugin_discovery_prefetch": "off",
    "code_mode_interrupt": "kept", "incremental_tools": "kept", "prediction_preserve_parent_tools": "kept",
    "reasoning_effort_override": "kept",
}
# default-off features turned off anyway, so a later default cannot turn them on (memories: record B)
CODEX_ALSO_OFF = ("memories",)
# the account's connectors Claude may list and still keep Bash: Anthropic's own docs (record P1)
CLAUDE_MCP_SAFE = ("claude.ai Claude Docs",)
# what `claude mcp list` prints beside its servers (probes/p1-list.txt): its header, and the line when there are none
CLAUDE_MCP_CHATTER = ("Checking MCP server health", "No MCP servers configured")

# What may not leave: lighthouse's secrets guard closes these folders and env files to agents (its FOLDERS and
# CANDIDATE; fence.sh compares the two), and a paper must hold no credential's shape (helloworld's vendor shapes,
# without its generic `token = …` rule: a paper quotes code)
VAULT_FOLDERS = ("_secrets", "_contacts")
ENV_HARMLESS = (".example", ".sample", ".template", ".dist")
CREDENTIAL = re.compile(r"(?<![A-Za-z0-9])(?:sk-[A-Za-z0-9_-]{20,}|sk-ant-[\w-]{8,}|[sr]k_(?:live|test)_\w{16,}|"
                        r"gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|"
                        r"ya29\.[\w-]{20,}|1//0[\w-]{20,}|xox[abprs]-[\w-]{10,}|eyJ[\w-]{10,}\.eyJ[\w-]{10,}\.[\w-]{10,})|"
                        r"-----BEGIN [A-Z ]*PRIVATE KEY-----")


class FenceError(Exception):
    """A fence that cannot be built or does not hold: the caller refuses the arm, naming why."""


def available():
    """The seatbelt is here: macOS with sandbox-exec. Elsewhere every arm is refused (S6: a guest)."""
    return sys.platform == "darwin" and os.access(SANDBOX_EXEC, os.X_OK)


def _q(path):
    """An SBPL string literal."""
    return '"%s"' % str(path).replace("\\", "\\\\").replace('"', '\\"')


def _user():
    import pwd
    return pwd.getpwuid(os.getuid()).pw_name


def login_home():
    """The account's own home from the password database (a moved HOME is a test's)."""
    import pwd
    return os.path.realpath(pwd.getpwuid(os.getuid()).pw_dir)


def homes():
    """$HOME and the login's home, real, each once."""
    out = []
    for h in (os.environ.get("HOME"), login_home()):
        if h and os.path.realpath(h) not in out:
            out.append(os.path.realpath(h))
    return out


def developer_dir():
    """The developer dir `xcode-select -p` names, real, read once (no model call), or None: /usr/bin/git and python3
    exec through xcrun into it, so an arm without it has no git. Under OS_READS already (CommandLineTools): None."""
    if not _DEVDIR:
        d = None
        try:
            r = subprocess.run(["/usr/bin/xcode-select", "-p"], capture_output=True, text=True, timeout=10,
                               stdin=subprocess.DEVNULL)
            d = os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None
        except (OSError, subprocess.TimeoutExpired):
            d = None
        if d and any(d == p or d.startswith(p + "/") for p in OS_READS):
            d = None
        _DEVDIR.append(d)
    return _DEVDIR[0]


def install_of(binary):
    """(the binary's real path, the folder an arm reads it from): the realpath's folder, the CLI's install."""
    real = os.path.realpath(shutil.which(binary) or binary)
    folder = os.path.dirname(real)
    if any(folder == h or folder.startswith(h + os.sep) for h in homes()):
        # a folder in a home (agy's, a user's local bin folder) holds the user's other tools: the arm reads the binary alone (round 4)
        return real, real
    return real, folder


# ---- F4: the seatbelt --------------------------------------------------------------------------

# Denied after the allows above them, as the last matching rule wins (H0): the pasteboard's mach service (the owner's
# clipboard: round 3), Homebrew's data and service configs under /opt/homebrew, which OS_READS opens for the
# tools' sake (its certificate bundles stay readable), and VAR_DB_CLOSED: of the OS's db folder, the raw unified log,
# its string tables and launchd's disabled-job file (the sixth landing review's S2), denied again though OS_READS
# reads the timezone alone since the seventh, so a later widening of OS_READS keeps them shut. launchd's own service
# still answers `launchctl print` over mach (the seventh review's S3: mach-lookup is unscoped; "Limits named").
VAR_DB_CLOSED = tuple(os.path.join(VAR_DB, x) for x in ("diagnostics", "uuidtext", "com.apple.xpc.launchd"))
# what probe() also asks of the folder: world-readable, so the case means something on an account that is no admin
VAR_DB_PROBED = VAR_DB_CLOSED + tuple(os.path.join(VAR_DB, x) for x in ("CoreDuet", "com.apple.backgroundtaskmanagement",
                                                                        "spindump"))
CLOSED = """(deny mach-lookup (global-name "com.apple.pasteboard.1") (global-name-prefix "com.apple.pasteboard")
  (global-name "com.apple.coreservices.uauseractivitypasteboardclient.xpc"))
(deny file-read* (subpath "/opt/homebrew/var") (subpath "/opt/homebrew/etc"))
(deny file-read* %s)
(allow file-read* (subpath "/opt/homebrew/etc/openssl@3") (subpath "/opt/homebrew/etc/ca-certificates"))""" % " ".join(
    '(subpath "%s")' % p for p in VAR_DB_CLOSED)


def profile(box, port, reads=(), ro=()):
    """The seatbelt over BOX: h-lib.sh's narrowed template (H6: signals and process info within the sandbox,
    writes under the box only, and of /dev the nodes DEV_RULES names) with P2's network — every remote denied but localhost:PORT, the proxy;
    no DNS (the proxy resolves); a bind and an inbound connection on localhost (agy listens on 127.0.0.1:0).
    READS: the CLI's install folders. RO: paths in the box the arm may not write (its scratch configs, our hook),
    denied after the allow, since the last matching rule wins (H0)."""
    if os.path.realpath(box) != os.path.normpath(os.path.abspath(box)):
        # a link at the box's path (a leftover's, round 4) would open its target to the arm's writes
        raise FenceError("the box %s is not where it says (a link on its path): no profile" % box)
    box = os.path.realpath(box)
    net = '(allow network-outbound (remote ip "localhost:%d"))' % int(port) if port else ""
    dev = developer_dir() if available() else None
    rd = " ".join("(%s %s)" % ("literal" if os.path.isfile(p) else "subpath", _q(os.path.realpath(p)))
                  for p in tuple(OS_READS) + ((dev,) if dev else ()) + tuple(reads) + (box,))
    deny = "\n".join('(deny file-write* (%s %s))' % ("subpath" if p.endswith("/") else "literal", _q(p.rstrip("/")))
                     for p in ro)
    # each folder between the box and a read-only path, literal: renamed, it would carry the path away and leave the
    # arm free to put its own file (a hooks.json behind a link) where the CLI reads it (the fourth landing review,
    # finding 6). Files inside stay writable: a literal rule is the folder's own node, never its contents
    anc = ro_ancestors(box, ro)
    if anc:
        deny += "\n(deny file-write* %s)" % " ".join("(literal %s)" % _q(a) for a in anc)
    return """(version 1)
(deny default)
(allow process-fork) (allow process-exec) (allow process-info* (target same-sandbox)) (allow signal (target same-sandbox))
(deny network*) %s
(allow network-bind (local ip "localhost:*")) (allow network-inbound (local ip "localhost:*"))
(allow sysctl-read) (allow mach-lookup) (allow mach-register)
(allow ipc-posix*) (allow system-socket) (allow file-read-metadata) (allow file-ioctl) (allow iokit-open)
(allow file-read* (literal "/") %s)
(allow file-write* (subpath %s))
%s
%s
%s
""" % (net, rd, _q(box), DEV_RULES, deny, CLOSED)


def ro_ancestors(box, ro):
    """The folders strictly between BOX and each path in RO, in order, each once: the ones profile() holds still."""
    box = os.path.realpath(box)
    out = []
    for p in ro:
        q = os.path.dirname(os.path.abspath(p.rstrip("/")))
        chain = []
        while q.startswith(box + os.sep):
            chain.append(q)
            q = os.path.dirname(q)
        for a in reversed(chain):
            if a not in out:
                out.append(a)
    return out


def write_profile(path, text):
    with open(path, "w") as f:
        f.write(text)
    os.chmod(path, 0o600)
    return path


def wrap(argv, profile_path):
    """ARGV under the seatbelt: the kernel holds it for the process and everything it starts. The caller starts it
    in a session of its own (start_new_session, as council and harness do): DEV_RULES opens /dev/tty, which is the
    caller's terminal when the arm shares its session (the seventh landing review's re-review)."""
    return [SANDBOX_EXEC, "-f", profile_path] + list(argv)


def _usertmp():
    try:
        d = os.confstr("CS_DARWIN_USER_TEMP_DIR")
    except (ValueError, OSError):
        d = None
    return os.path.realpath(d or tempfile.gettempdir())


_AQUA = []


def _aqua():
    """This user has a GUI login (launchd's gui/<uid> domain is there), so LaunchServices can start an app for it,
    whatever the caller's own session (an ssh shell beside a console login still reaches it). Read once a process."""
    if not _AQUA:
        try:
            r = subprocess.run(["/bin/launchctl", "print", "gui/%d" % os.getuid()], capture_output=True, timeout=10)
            _AQUA.append(r.returncode == 0)
        except (OSError, subprocess.SubprocessError):
            _AQUA.append(False)
    return _AQUA[0]


def probe(profile_path, box, port=None, ro=(), timeout=20, holders=None):
    """[] when PROFILE_PATH holds over BOX, else one line per case that did not: no model call
    (F4's probe, run before every arm starts, failing closed; about 3 s on the laptop since S5's LaunchServices
    case). Each case runs from /bin/sh outside the seatbelt
    first, and only a case that works outside is judged inside: the home folder, its real config dirs, its .ssh and
    projects folders and its keychain folder unreadable; /Users and /private/tmp unreadable; a write under the user's temp folder,
    a unix socket outside, a signal to a process outside and a localhost port other than the proxy's refused;
    /etc/hosts read, a write in the box and the proxy's port (PORT) allowed; each RO path (a scratch config, our
    hook) refused a write inside, with no outside run: the box's own write is its control; and, inside only, an app
    started through LaunchServices and a job submitted to launchd refused (each would run outside the seatbelt)."""
    if not available():
        return ["sandbox-exec is not here (%s): no seatbelt" % sys.platform]
    # what no profile closes: a credential in any same-user process's environment (env_holders, finding 1)
    why = holders_why(holders)
    if why:
        return [why]
    box = os.path.realpath(box)
    deny, allow = [], [("hosts", "head -1 /etc/hosts"), ("box-write", "touch %s && rm -f %s" % (
        shlex.quote(os.path.join(box, ".fence-probe")), shlex.quote(os.path.join(box, ".fence-probe"))))]
    seen = set()
    for h in homes():
        for p in [h] + [os.path.join(h, x) for x in (".ssh", "projects", ".claude", ".codex", ".gemini",
                                                      os.path.join("Library", "Keychains"))]:
            if p not in seen and not p.startswith(box + "/") and os.path.exists(p):
                seen.add(p)
                deny.append(("read " + p, ("ls %s" if os.path.isdir(p) else "head -c1 %s") % shlex.quote(p)))
    for v in ("CLAUDE_CONFIG_DIR", "CODEX_HOME"):
        p = os.environ.get(v)
        if p and os.path.isdir(p) and os.path.realpath(p) not in seen:
            seen.add(os.path.realpath(p))
            deny.append(("read $%s" % v, "ls %s" % shlex.quote(p)))
    # /Library beyond the developer dir (S4's narrowing): its preferences folder stands for the rest
    # and VAR_DB_CLOSED (the sixth landing review's S2)
    for p in ("/Users", "/private/tmp", "/Library/Preferences", "/opt/homebrew/var", "/opt/homebrew/etc") + VAR_DB_PROBED:
        if os.path.isdir(p):
            deny.append(("read " + p, "ls %s" % p))
    out_dir = tempfile.mkdtemp(prefix="fence-probe-")   # the user's temp folder, outside the box
    mark = os.path.join(_usertmp(), "fence-probe-%d-%s" % (os.getpid(), os.urandom(6).hex()))   # arms probe in threads
    deny.append(("write under the user's temp folder", "touch %s" % shlex.quote(mark)))
    sock_path = os.path.join(out_dir, "s")
    us = socket.socket(socket.AF_UNIX)
    ts = socket.socket()
    sleeper, label, pty = None, None, ()
    try:
        # a terminal of the owner's, stood in for by a pty opened here: an open only, so neither run blocks (the
        # seventh landing review's S2: an arm read and wrote another terminal's node)
        pty = os.openpty()
        deny.append(("open a terminal outside", ": < %s" % shlex.quote(os.ttyname(pty[1]))))
        us.bind(sock_path)
        us.listen(8)
        ts.bind(("127.0.0.1", 0))
        ts.listen(8)
        sleeper = subprocess.Popen(["/bin/sleep", "60"])
        deny.append(("a unix socket outside", "nc -U -w 1 %s </dev/null" % shlex.quote(sock_path)))
        deny.append(("a signal to a process outside", "kill -0 %d" % sleeper.pid))
        deny.append(("localhost:%d (not the proxy)" % ts.getsockname()[1], "nc -z -G 2 127.0.0.1 %d" % ts.getsockname()[1]))
        if port:
            allow.append(("the proxy's port %d" % port, "nc -z -G 2 127.0.0.1 %d" % int(port)))
        made = []
        for p in ro:
            q = p.rstrip("/")
            if p.endswith("/"):
                q = os.path.join(q, ".fence-probe")
            if not os.path.exists(q):
                made.append(q)
            # `: >>` opens for writing and writes nothing: an existing file keeps its bytes
            deny.append(("write %s" % p, ": >> %s" % shlex.quote(q)))
        for a in ro_ancestors(box, ro):
            # renamed and put back: a fence that lets the first go loses nothing (finding 6)
            if os.path.isdir(a):
                t = a + ".fence-probe"
                deny.append(("write %s (rename)" % a, "mv %s %s && mv %s %s" % (
                    shlex.quote(a), shlex.quote(t), shlex.quote(t), shlex.quote(a))))
        # starting a process outside the seatbelt through a service the profile's mach-lookup reaches (S5's landing
        # review): LaunchServices (`open` of a faceless app; the kernel's lsopen denial, error -54, holds it today) and
        # launchd (`submit` of a job, refused today). Inside only: run outside they would launch the thing
        # (the label is per call: arms probe in threads of one process). The LaunchServices case only where the user
        # has a GUI login (gui/<uid>): elsewhere `open` fails whatever the profile says, so it proves nothing
        label = "dev.220labs.fence-probe-%d-%s" % (os.getpid(), os.urandom(4).hex())
        inside_only = [("start a job through launchd", "/bin/launchctl submit -l %s -- /usr/bin/true" % label)]
        if _aqua():
            inside_only.append(("start an app through LaunchServices", "/usr/bin/open -g -j -b com.apple.systemevents"))
        deny += inside_only
        cases = [(n, c, False) for n, c in deny] + [(n, c, True) for n, c in allow]
        skip_outside = {n for n, _ in inside_only}
        script = "\n".join("( %s ) >/dev/null 2>&1; echo \"%d $?\"" % (c, i) for i, (_, c, _) in enumerate(cases))
        env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": box, "TMPDIR": box, "LANG": "C"}

        def run(argv):
            r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=env, cwd=box,
                               stdin=subprocess.DEVNULL)
            got = {}
            for line in r.stdout.splitlines():
                a, _, b = line.partition(" ")
                if a.isdigit() and b.strip().isdigit():
                    got[int(a)] = int(b)
            return got
        outside = run(["/bin/sh", "-c", "\n".join(l for l, (n, _, _) in zip(script.splitlines(), cases)
                                                   if not n.startswith("write " + box) and n not in skip_outside)])
        if os.path.exists(mark):
            os.remove(mark)
        inside = run(wrap(["/bin/sh", "-c", script], profile_path))
        for q in made:
            if os.path.exists(q):
                os.remove(q)
    except (OSError, subprocess.SubprocessError) as e:
        return ["the probe could not run (%s: %s): the fence is not known to hold" % (type(e).__name__, e)]
    finally:
        if label:
            try:   # a job that got in, whatever ended the run
                subprocess.run(["/bin/launchctl", "remove", label], capture_output=True, timeout=timeout)
            except (OSError, subprocess.SubprocessError):
                pass
        for s in (us, ts):
            s.close()
        for fd in pty:
            os.close(fd)
        if sleeper:
            sleeper.kill()
            sleeper.wait()
        shutil.rmtree(out_dir, ignore_errors=True)
        if os.path.exists(mark):
            os.remove(mark)
    bad = []
    if not inside:
        return ["nothing ran under the profile %s: the fence is not known to hold" % profile_path]
    for i, (name, _, ok) in enumerate(cases):
        if ok and inside.get(i) != 0:
            bad.append("%s: refused inside" % name)
        elif not ok and inside.get(i) == 0 and (outside.get(i) == 0 or name.startswith("write " + box) or name in skip_outside):
            bad.append("%s: allowed inside" % name)
    return bad


# ---- the door: one proxy per arm ---------------------------------------------------------------

MAX_HEADERS = 64 * 1024   # a request's header block, before it is judged

NAT64 = ipaddress.ip_network("64:ff9b::/96")          # RFC 6052's well-known prefix: the low 32 bits are the IPv4
NAT64_LOCAL = ipaddress.ip_network("64:ff9b:1::/48")  # RFC 8215's local-use prefix: where it sits is the network's


def embedded_v4(ip):
    """The IPv4 address an IPv6 one carries to a translator (mapped, 6to4, Teredo's client, NAT64's well-known
    prefix), or None; a local-use NAT64 address as 0.0.0.0, never global, since its layout is the network's own.
    Python 3.9 reads these as global whatever they carry (the sixth landing review's S3, decided by the seventh)."""
    if ip.version != 6:
        return None
    if ip in NAT64_LOCAL:
        return ipaddress.IPv4Address(0)
    if ip in NAT64:
        return ipaddress.IPv4Address(int(ip) & 0xFFFFFFFF)
    if ip.ipv4_mapped:
        return ip.ipv4_mapped
    if ip.sixtofour:
        return ip.sixtofour
    if ip.teredo:
        return ip.teredo[1]
    return None


class Proxy:
    """The arm's one way out: the seatbelt allows localhost:PORT and nothing else remote. It takes CONNECT
    host:port and a plain-http absolute URI, resolves the host itself and judges every address it resolves to
    at connect time — anything not global (private, loopback, link-local, CGNAT and so the tailnet, multicast,
    reserved) is refused, so a public name pointing at 127.0.0.1 or the LAN is refused too — then connects to
    the address it judged, never resolving again. HOSTS (exact names) pass on 443; any other host, and port 80,
    only with RESEARCH (the brief asked for the web). Each decision is one JSON line in LOG (P2's p2-proxy.py,
    exact names since S0). ON_VENDOR (F7: the arm's Credential.withdraw) runs once, at the first request for one
    of HOSTS on a port the rule passes, before the name is resolved and before any answer goes back: the CLI read
    its login to sign that request, and nothing reaches the vendor, so no model's reply and no tool call, until
    the login is off the disk. Its result is a line of LOG ({"withdraw": …}) and self.withdrawal. With ON_VENDOR,
    RESEARCH opens only once that withdrawal has run and held (or the login is kept by design): until then only
    HOSTS pass, as with research off, so a CLI whose vendor request goes to a host HOSTS lacks fails as it would
    without research, never reaching the model with its login still on disk (round 6). stop() closes every tunnel
    and request still open, not only the listening socket: a leftover of the arm keeps no door (round 6)."""

    def __init__(self, hosts, research=False, log=None, on_vendor=None):
        self.hosts = {h.lower().rstrip(".") for h in hosts}
        self.research = bool(research)
        self.log = log
        self.lock = threading.Lock()
        self.server = None
        self.decisions = []
        self.on_vendor = on_vendor
        self.withdrawal = None
        self._vendor_lock = threading.Lock()
        self._open = set()   # the sockets of every request in flight and tunnel open: stop() closes them

    def judge(self, host, port):
        """((family, sockaddr), None) to connect to, or (None, why)."""
        h = (host or "").lower().rstrip(".").strip("[]")
        w = self.withdrawal
        if w is not None and not (w.get("ok") or w.get("kept")):
            # the login is still on disk: no connection at all, the vendor's included, so no model answers and no
            # tool runs with it there (round 6's fourth review: the vendor's was still let through)
            return None, "the login's withdrawal did not hold (F7): every connection refused"
        if h not in self.hosts and not self.research:
            return None, "not the CLI's vendor host and research is off"
        if h not in self.hosts and not self._research_open():
            return None, "not the CLI's vendor host, and research opens only once the login is withdrawn (F7)"
        if port not in PORTS and not (self.research and self._research_open() and port == 80):
            return None, "port %s" % port
        try:
            infos = socket.getaddrinfo(h, port, type=socket.SOCK_STREAM)
        except (OSError, UnicodeError, ValueError) as e:
            # a label over 63 bytes or an empty one raises UnicodeError: refused and logged, never a dead thread
            return None, "resolve: %s" % e
        if not infos:
            return None, "resolve: no address"
        for fam, _, _, _, sa in infos:
            ip = ipaddress.ip_address(sa[0].split("%")[0])
            if not ip.is_global:
                return None, "%s resolves to %s, not global" % (h, ip)
            inner = embedded_v4(ip)
            if inner is not None and not inner.is_global:
                return None, "%s resolves to %s, which carries %s, not global" % (h, ip, inner)
        return (infos[0][0], infos[0][4]), None

    def _research_open(self):
        w = self.withdrawal
        return self.on_vendor is None or (w is not None and bool(w.get("ok") or w.get("kept")))

    def note(self, **kw):
        kw["t"] = round(time.time(), 3)
        with self.lock:
            if "method" in kw:
                self.decisions.append(kw)
            if self.log:
                with open(self.log, "a") as f:
                    f.write(json.dumps(kw) + "\n")

    def vendor_once(self, host):
        """ON_VENDOR, the first time a connection to HOST, one of the vendor's, is allowed; every later caller waits
        for that first one to finish, so no connection to the vendor opens while the login is still on disk."""
        if not self.on_vendor:
            return
        with self._vendor_lock:
            if self.withdrawal is not None:
                return
            try:
                out = self.on_vendor()
            except Exception as e:   # noqa: BLE001 — a withdrawal that crashed is one that did not happen
                out = {"ok": False, "why": "%s: %s" % (type(e).__name__, e)}
            if not isinstance(out, dict):
                out = {"ok": False, "why": "the withdrawal returned no record"}
            out["host"] = host   # in place: the Credential's own record names the host too
            self.withdrawal = out
            self.note(withdraw=out)

    def start(self):
        proxy = self

        class Handler(socketserver.StreamRequestHandler):
            # unbuffered: the request is read a byte at a time, so nothing past its headers sits in a buffer the
            # pipe never sees (a POST body, a ClientHello sent at once; the fourth landing review, finding 7)
            rbufsize = 0

            def handle(self):
                with proxy.lock:
                    if proxy.server is None:
                        return
                    proxy._open.add(self.connection)
                try:
                    proxy.serve(self)
                finally:
                    up = getattr(self, "up", None)
                    with proxy.lock:
                        proxy._open.discard(self.connection)
                        proxy._open.discard(up)
                    if up is not None:
                        try:
                            up.close()
                        except OSError:
                            pass

        class Server(socketserver.ThreadingTCPServer):
            daemon_threads = True
            allow_reuse_address = True

        self.server = Server(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        return self.server.server_address[1]

    @property
    def port(self):
        return self.server.server_address[1] if self.server else None

    def stop(self):
        """The accept loop ended, the listening socket closed, then every connection still open shut both ways: a
        tunnel an arm's leftover (a process out of the group) still holds ends here, not PIPE_IDLE later."""
        if self.server:
            srv, self.server = self.server, None
            srv.shutdown()
            srv.server_close()
        with self.lock:
            left, self._open = list(self._open), set()
        for c in left:
            try:
                c.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                c.close()
            except OSError:
                pass

    def serve(self, h):
        line = h.rfile.readline(8192).decode("latin-1").strip()
        try:
            method, target, _ = line.split(" ", 2)
        except ValueError:
            return
        headers, size = [], 0
        while True:
            x = h.rfile.readline(8192)
            if x in (b"\r\n", b"\n", b""):
                break
            size += len(x)
            if size > MAX_HEADERS:
                return   # a header block that never ends grows nothing past this (the seventh landing review)
            headers.append(x)
        if self.server is None:
            return   # stopped while the request was read: nothing judged, answered or withdrawn (round 6's third review)
        path = ""
        try:
            if method == "CONNECT":
                host, _, p = target.rpartition(":")
                port = int(p or 443)
            elif target.startswith("http://"):
                hostport, _, path = target[len("http://"):].partition("/")
                host, _, p = hostport.partition(":")
                port = int(p or 80)
            else:
                h.wfile.write(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
                return
        except ValueError:
            h.wfile.write(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
            return
        body = b""
        if method != "CONNECT":
            if (host or "").lower().rstrip(".").strip("[]") in self.hosts and port in PORTS:
                self.vendor_once(host)   # F7 before the name resolves, as below
            addr0, why0 = self.judge(host, port) if host else (None, "no host")
            if addr0 is None:
                # judged before a byte of the body is read: a refused request costs no memory (round 2)
                self.note(method=method, host=host, port=port, ok=False, why=why0)
                h.wfile.write(("HTTP/1.1 403 Forbidden\r\nX-Council-Proxy: %s\r\nContent-Length: 0\r\n\r\n" % why0).encode())
                return
            names = {x.split(b":", 1)[0].strip().lower(): x.split(b":", 1)[1].strip() for x in headers if b":" in x}
            if b"transfer-encoding" in names:
                # a chunked body has no length to stop at: refused rather than read past its end (finding 7)
                h.wfile.write(b"HTTP/1.1 411 Length Required\r\nContent-Length: 0\r\n\r\n")
                return
            try:
                left = int(names.get(b"content-length") or 0)
            except ValueError:
                h.wfile.write(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")
                return
            if left < 0 or left > MAX_BODY:
                h.wfile.write(b"HTTP/1.1 413 Payload Too Large\r\nContent-Length: 0\r\n\r\n")
                return
            while left > 0:
                x = h.rfile.read(min(left, 65536))
                if not x:
                    return
                body += x
                left -= len(x)
        if (host or "").lower().rstrip(".").strip("[]") in self.hosts and port in PORTS:
            self.vendor_once(host)
        addr, why = self.judge(host, port) if method == "CONNECT" else (addr0, why0)
        self.note(method=method, host=host, port=port, ok=addr is not None, why=why)
        if addr is None:
            h.wfile.write(("HTTP/1.1 403 Forbidden\r\nX-Council-Proxy: %s\r\nContent-Length: 0\r\n\r\n" % why).encode())
            return
        try:
            up = socket.socket(addr[0], socket.SOCK_STREAM)
            with self.lock:
                if self.server is None:   # stopped meanwhile: no new door
                    up.close()
                    return
                self._open.add(up)
            h.up = up   # the handler's finally drops and closes it
            up.settimeout(15)
            up.connect(addr[1])
            up.settimeout(None)
        except OSError as e:
            self.note(method=method, host=host, port=port, ok=False, why="connect: %s" % e)
            h.wfile.write(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            return
        if method == "CONNECT":
            h.wfile.write(b"HTTP/1.1 200 Connection established\r\n\r\n")
            h.wfile.flush()
            _pipe(h.connection, up)
            return
        # plain http: this one request, its body by its length, then the answer back and the connection closed. Never
        # a pipe from the arm: a second request on a kept-alive connection would reach this judged address unjudged
        # (finding 7), so the request says `Connection: close` and nothing more of the arm's is read
        up.sendall(("%s /%s HTTP/1.1\r\n" % (method, path)).encode() +
                   b"".join(x for x in headers if not x.lower().startswith(HOP_BY_HOP)) + b"Connection: close\r\n\r\n" +
                   body)
        _relay(up, h.connection)


PIPE_IDLE = 7200   # s a tunnel may sit silent: two hours, past the timeouts council and harness use by default, so a long silent turn is rarely cut; a --timeout above it can be (round 4; round 5 reworded)
MAX_BODY = 16 << 20   # bytes of a plain-http body the proxy holds: past it, 413 (round 2)
HOP_BY_HOP = (b"proxy-", b"connection", b"keep-alive", b"transfer-encoding", b"upgrade", b"te:")


def _relay(src, dst):
    """SRC's bytes to DST until SRC ends: one way, the answer to a plain-http request. Closes both."""
    try:
        while True:
            r, _, _ = select.select([src], [], [], 300)
            if not r:
                return
            data = src.recv(65536)
            if not data:
                return
            dst.sendall(data)
    except (OSError, ValueError):   # ValueError: stop() closed the socket under select (round 6's second review)
        return
    finally:
        src.close()


def _pipe(a, b):
    try:
        while True:
            r, _, _ = select.select([a, b], [], [], PIPE_IDLE)
            if not r:
                return
            for s in r:
                data = s.recv(65536)
                if not data:
                    return
                (b if s is a else a).sendall(data)
    except (OSError, ValueError):   # ValueError: stop() closed the socket under select (round 6's second review)
        return
    finally:
        b.close()


# ---- F3: the scratch homes ---------------------------------------------------------------------

def _secret_file(path, data):
    """DATA into a new 0600 file at PATH (never through an existing one)."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)


def _keychain_read(service, account, env=None):
    """The keychain item's secret, read by /usr/bin/security with stdin closed and a timeout (an item whose ACL
    would prompt cannot hang an unattended run), or FenceError."""
    try:
        r = subprocess.run([SECURITY, "find-generic-password", "-s", service, "-a", account, "-w"], capture_output=True,
                           stdin=subprocess.DEVNULL, timeout=20, env=env)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FenceError("the keychain item %r did not read (%s)" % (service, type(e).__name__))
    if r.returncode:
        raise FenceError("the keychain item %r is not in this login's keychain (security exit %d)" % (service, r.returncode))
    return r.stdout[:-1] if r.stdout.endswith(b"\n") else r.stdout


def claude_source(cfg=None):
    """(config dir, its keychain service, its .claude.json): --claude-config, else the caller's
    CLAUDE_CONFIG_DIR, else the home folder's .claude. Claude Code names a non-default dir's item by the first 8 hex of the
    dir's sha256 (record P3)."""
    named = cfg or os.environ.get("CLAUDE_CONFIG_DIR")
    d = named or os.path.join(os.path.expanduser("~"), ".claude")
    svc = "Claude Code-credentials" + ("-" + hashlib.sha256(named.encode()).hexdigest()[:8] if named else "")
    meta = os.path.join(d, ".claude.json") if named else os.path.join(os.path.expanduser("~"), ".claude.json")
    return d, svc, meta


def _signed_in(data):
    try:
        return isinstance(json.loads(data).get("claudeAiOauth"), dict)
    except (ValueError, AttributeError, UnicodeDecodeError):
        return False


def _claude_login(src, svc):
    """The login's credential: its keychain item, where Claude Code keeps it on macOS, else the dir's
    .credentials.json — whichever holds a sign-in (`claudeAiOauth`). A file holding only an MCP server's OAuth
    signs nothing in (a config dir on 2026-10-30), so it is passed over, never copied as the login."""
    tried = []
    try:
        data = _keychain_read(svc, _user())
        if _signed_in(data):
            return data
        tried.append("the keychain item %r holds no sign-in" % svc)
    except FenceError as e:
        tried.append(str(e))
    f = os.path.join(src, ".credentials.json")
    try:
        with open(f, "rb") as x:
            data = x.read()
        if _signed_in(data):
            return data
        tried.append("%s holds no sign-in" % f)
    except OSError:
        tried.append("no %s" % f)
    raise FenceError("no Claude login to copy: %s" % "; ".join(tried))


# Claude Code's own variables for a login handed on a file descriptor (its binary, 2.1.314): the CLI drains the pipe
# once and no file holds the login. A .credentials.json in the box is read again after the first connection: withdrawn
# there, claude said "Not logged in" (record Q1a), so the Claude arm's login is never in its box at all.
CLAUDE_FD = dict([("CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR"),
                  ("ANTHROPIC_API_KEY", "CLAUDE_CODE_API_KEY_FILE_DESCRIPTOR")])
CLAUDE_EXPIRY_MARGIN = 120   # s past the run's end an access token must still hold


def _home_claude(box, cfg=None, token_env=None, until=None):
    """The box's scratch config dir: a .claude.json holding oauthAccount alone (H4) and no login. The login goes on a
    pipe (Credential.pipe, CLAUDE_FD): the access token of the login's credential (its keychain item, else the dir's
    .credentials.json; P3), or with TOKEN_ENV (the caller's own CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY, no
    --claude-config) that token — never a refresh token, never a file or a variable the arm's shell could read
    (F7). An access token that expires before UNTIL (the run's end, epoch seconds) refuses the arm: it holds no
    refresh token and its proxy no refresh host, so it would fail mid-run."""
    d = os.path.join(box, "home", ".claude")
    os.makedirs(d, mode=0o700)
    src, svc, meta = claude_source(cfg)
    if token_env:
        var = "ANTHROPIC_API_KEY" if token_env.get("ANTHROPIC_API_KEY") else "CLAUDE_CODE_OAUTH_TOKEN"
        tok, values = token_env.get(var) or "", secret_strings(*token_env.values())
    else:
        data = _claude_login(src, svc)
        oauth = json.loads(data).get("claudeAiOauth") or {}
        var = "CLAUDE_CODE_OAUTH_TOKEN"
        tok, values = oauth.get("accessToken") or "", secret_strings(data)
        exp = oauth.get("expiresAt")
        if until and isinstance(exp, (int, float)) and exp / 1000.0 < until + CLAUDE_EXPIRY_MARGIN:
            raise FenceError("the Claude login's access token expires at %s, before the run can end (%s): the arm holds "
                             "no refresh token and its proxy no refresh host; a session on that login refreshes it"
                             % (time.strftime("%H:%M", time.localtime(exp / 1000.0)),
                                time.strftime("%H:%M", time.localtime(until))))
    if not isinstance(tok, str) or not tok:
        raise FenceError("the Claude login holds no access token to hand the arm")
    cred = Credential("claude", secrets=values, pipe=(CLAUDE_FD[var], tok.encode("utf-8")))
    try:
        with open(meta) as x:
            acct = json.load(x).get("oauthAccount")
    except (OSError, ValueError, AttributeError):
        acct = None
    with open(os.path.join(d, ".claude.json"), "w") as x:
        json.dump({"oauthAccount": acct} if acct else {}, x)
    env = {"CLAUDE_CONFIG_DIR": d}
    # what a Claude started again by the arm's shell would read as its own config
    ro = [os.path.join(d, n) for n in ("settings.json", "settings.local.json", "CLAUDE.md", ".mcp.json")]
    return env, ro, cred


def _home_codex(box):
    """The box's scratch CODEX_HOME holding the login's auth.json alone, 0600 (record B, P3: the owner's file is not rewritten)."""
    d = os.path.join(box, "home", ".codex")
    os.makedirs(d, mode=0o700)
    src = os.path.join(os.environ.get("CODEX_HOME") or os.path.join(os.path.expanduser("~"), ".codex"), "auth.json")
    try:
        with open(src, "rb") as x:
            data = x.read()
        _secret_file(os.path.join(d, "auth.json"), data)
    except OSError as e:
        raise FenceError("Codex's %s does not read (%s): no sign-in to copy" % (src, e.strerror or e))
    cred = Credential("codex", files=[os.path.join(d, "auth.json")], secrets=secret_strings(data))
    return {"CODEX_HOME": d}, codex_ro(d), cred


# read-only to the Codex arm, in its scratch CODEX_HOME: the configs codex would load, and auth.json, which F7
# withdraws at the first vendor request (from outside the box) and which a token refresh would otherwise write back
# where the arm's shell reads it (as agy 1.4.12 did with its token file, S4). harness's research mode builds the
# Codex arm's profile, so it names the same list (S5's landing review: it named none)
CODEX_RO = ("config.toml", "AGENTS.md", "hooks.json", "auth.json")


def codex_ro(codex_home):
    return [os.path.join(codex_home, n) for n in CODEX_RO]


def hook_python():
    """The interpreter agy runs our hook with: this one where the profile reads it, else /usr/bin/python3."""
    real = os.path.realpath(sys.executable)
    return real if any(real.startswith(p + "/") for p in OS_READS) else "/usr/bin/python3"


AGY_SIGNIN_FILE = "antigravity-oauth-token"   # beside agy's state, .gemini/antigravity-cli under HOME: 1.4.12's (S4)


def _home_agy(box, research=False):
    """box/home as agy's HOME (H5, P3): its three small state files, an empty mcp_config.json, our hook as the
    only one (box/hook, read-only to the arm), and a per-run login keychain holding agy's item alone — made
    under the scratch HOME, whose search list follows HOME, so the owner's list is untouched; never a link to the
    login's own Keychains folder, through which a shell read Claude's credential and the gh token (P3's control)."""
    h = os.path.join(box, "home")
    cli, cfg = os.path.join(h, ".gemini", "antigravity-cli"), os.path.join(h, ".gemini", "config")
    for d in (cli, cfg, os.path.join(h, "Library", "Keychains"), os.path.join(box, "hook")):
        os.makedirs(d, mode=0o700, exist_ok=True)
    # the owner's agy home as agy and account read it ($GEMINI_CLI_HOME, else .gemini under HOME; round 6: the tenancy was
    # judged on one home and the state copied from another)
    src = os.path.join(os.environ.get("GEMINI_CLI_HOME") or os.path.join(os.path.expanduser("~"), ".gemini"),
                       "antigravity-cli")
    try:
        with open(os.path.join(src, "settings.json")) as x:
            s = json.load(x)
        s = {k: s[k] for k in ("colorScheme",) if isinstance(s, dict) and k in s}
    except (OSError, ValueError):
        s = {}
    with open(os.path.join(cli, "settings.json"), "w") as x:
        json.dump(s, x)
    for n in ("installation_id", "jetski_state.pbtxt"):
        if os.path.isfile(os.path.join(src, n)):
            shutil.copyfile(os.path.join(src, n), os.path.join(cli, n))
    open(os.path.join(cfg, "mcp_config.json"), "w").close()
    hook = os.path.join(box, "hook", "agy_hook.py")
    shutil.copyfile(os.path.join(os.path.dirname(os.path.abspath(__file__)), "agy_hook.py"), hook)
    os.chmod(hook, 0o444)
    with open(os.path.join(cfg, "hooks.json"), "w") as x:
        json.dump({"council": {"PreToolUse": [{"matcher": "*", "hooks": [
            {"type": "command", "command": "%s -I %s%s" % (shlex.quote(hook_python()), shlex.quote(hook),
                                                           " --research" if research else ""), "timeout": 10}]}]}}, x)
    secret = _keychain_read("gemini", "antigravity")
    kc = os.path.join(h, "Library", "Keychains", "login.keychain-db")
    kenv = {"HOME": h, "PATH": "/usr/bin:/bin"}
    try:
        r = subprocess.run([SECURITY, "create-keychain", "-p", "council", kc], capture_output=True, env=kenv,
                           stdin=subprocess.DEVNULL, timeout=20)
        if r.returncode:
            raise FenceError("the per-run keychain was not made (security exit %d)" % r.returncode)
        subprocess.run([SECURITY, "set-keychain-settings", kc], capture_output=True, env=kenv,
                       stdin=subprocess.DEVNULL, timeout=20)
        # the secret on stdin as hex, never on argv (`ps` shows argv to every account)
        cmd = 'add-generic-password -s gemini -a antigravity -T %s -X %s "%s"\n' % (SECURITY, secret.hex(), kc)
        r = subprocess.run([SECURITY, "-i"], input=cmd.encode(), capture_output=True, env=kenv, timeout=20)
        if r.returncode:
            raise FenceError("agy's item was not copied into the per-run keychain (security exit %d)" % r.returncode)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise FenceError("the per-run keychain: %s" % type(e).__name__)
    # agy 1.4.12 writes its sign-in back as a file beside its state once it has refreshed it (S4's live run: F7's end
    # scan found the login's strings there, the paper withheld), where the arm's shell could read it and start agy
    # again. The arm may not write it (the kernel refuses), and F7 withdraws and looks for it like any login file.
    token = os.path.join(cli, AGY_SIGNIN_FILE)
    ro = [os.path.join(cfg, "hooks.json"), os.path.join(cfg, "mcp_config.json"), os.path.join(cli, "settings.json"),
          token, os.path.join(box, "hook") + "/"]
    return {"HOME": h}, ro, Credential("agy", files=[token], keychain=kc, secrets=secret_strings(secret))


def arm_home(cli, box, cfg=None, token_env=None, until=None, research=False):
    """The scratch home for CLI ("claude", "codex", "agy") in BOX: (env additions, paths the profile keeps
    read-only to the arm, its Credential for F7), or FenceError. UNTIL: the run's end, which Claude's access token
    must outlive. The caller removes it with drop_box()."""
    box = os.path.realpath(box)
    os.makedirs(os.path.join(box, "tmp"), mode=0o700, exist_ok=True)
    if cli == "claude":
        out = _home_claude(box, cfg, token_env, until)
    elif cli == "codex":
        out = _home_codex(box)
    elif cli == "agy":
        out = _home_agy(box, research)   # RESEARCH: agy's web tools allowed by its hook (agy_hook.WEB)
    else:
        raise FenceError("no scratch home for %r" % cli)
    cred = out[2]
    if cred is not None and not cred.keep and not cred.needles():
        # a login shape secret_strings finds nothing in (a CLI update renamed its keys) would leave F7's scans
        # passing without looking: refused, never blind (the sixth landing review's S3, decided by the seventh)
        raise FenceError("the %s login holds nothing F7 can look for (no key named token, secret, key or password): "
                         "no arm runs whose withdrawal cannot be checked" % cli)
    return out


def _common():
    """The core's common, beside this file (its callers loaded it already; a test may not have)."""
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.append(here)
    import common
    return common


def box_why(cwd):
    """Why CWD is not the copy (or the review's repo) in a council arm's box, or None: the one rule harness's research
    mode keeps over its --cwd (the isolation design's S3). The seatbelt opens the box and nothing else of the user's
    (F4), so what an arm reads is the box; what is left to ask is whether the box is a council's — named `box`, CWD
    its `copy` or `repo`, two folders (the review's) or three (an arm's) under a run dir that holds the council's
    marker, is this account's and is closed to others (0700). The rules this replaced read what F4 now holds: a copy
    under ~ or in the home repo, a dot in its path (the old Codex profile's keys), a `.git` with a remote or
    alternates (S2's copy has none; the review's repo is git_copy's, and a shell in it reaches no other repo's objects
    and no login to fetch with). The marker is a statement, not a proof: a caller who builds such a folder by hand is
    trusted, as every caller of research mode is."""
    real = os.path.realpath(cwd)
    box = os.path.dirname(real)
    if os.path.basename(real) not in ("copy", "repo") or os.path.basename(box) != "box":
        return ("--cwd %s is no council arm's copy (<run>/<phase>/<arm>/box/copy, or <run>/review/box/repo): research "
                "mode reads what wharf's council made" % real)
    marker = _common().COUNCIL_MARKER
    up = lambda p, n: up(os.path.dirname(p), n - 1) if n else p
    def marked(d):
        # a regular file of this account's, never a link: keel's sheep_gate judges a run dir the same way (round 6)
        try:
            st = os.lstat(os.path.join(d, marker))
        except OSError:
            return False
        return stat.S_ISREG(st.st_mode) and st.st_uid == os.getuid()
    run = next((d for d in (up(box, 2), up(box, 3)) if marked(d)), None)
    if not run:
        return "--cwd %s: no run dir holding %s two or three folders above its box" % (real, marker)
    st = os.stat(run)
    if st.st_uid != os.getuid() or st.st_mode & 0o077:
        return "the run dir %s is not this account's alone (0700): no copy is read from it" % run
    return None


def in_box(box, path):
    """True when PATH lies inside BOX with no link on the way: no folder between them, nor PATH itself, is a link,
    and its real path is under BOX's. A path an arm could have redirected is never one the owner's process acts on
    (round 2: a link planted at the scratch home's Library/Keychains would have had `security delete-keychain` delete the
    owner's login keychain)."""
    rb = os.path.realpath(box)
    rel = os.path.relpath(os.path.abspath(path), os.path.abspath(box))
    if rel.startswith(".."):
        return False
    q = os.path.abspath(box)
    for part in rel.split(os.sep):
        q = os.path.join(q, part)
        if os.path.islink(q):
            return False
    return os.path.realpath(path).startswith(rb + os.sep)


def drop_box(box):
    """The per-run keychain out of securityd's list (its search list is the scratch HOME's), then BOX removed:
    the copy, the scratch home and its credential. Never raises."""
    if os.path.isdir(box) and not os.path.islink(box):
        # first out of the profile's write rule: a renamed box is no path an arm's process may write, so nothing it
        # left running can swap a folder for a link between the check below and `security` (round 3: in_box alone
        # lost that race 13 times in 30)
        closed = "%s.closed-%d-%s" % (box, os.getpid(), os.urandom(4).hex())
        try:
            os.rename(box, closed)
            box = closed
        except OSError as e:
            # not closed (an arm can set uchg on its box): never `security` on a path its leftovers may still flip
            # (round 4). The per-run keychain was withdrawn at the first vendor connection; a box whose CLI never got
            # that far ran no tool, so nothing of it lingers to race. The box stays for the owner to remove
            print("fence: the box %s could not be closed (%s): left as it is, no keychain call" % (box, e), file=sys.stderr)
            return
    kc = os.path.join(box, "home", "Library", "Keychains", "login.keychain-db")
    if os.path.exists(kc) and in_box(box, kc):
        try:
            subprocess.run([SECURITY, "delete-keychain", kc], capture_output=True, stdin=subprocess.DEVNULL, timeout=20,
                           env={"HOME": os.path.join(box, "home"), "PATH": "/usr/bin:/bin"})
        except (OSError, subprocess.TimeoutExpired):
            pass
    if os.path.isdir(box) and not os.path.islink(box):
        for d, dirs, _ in os.walk(box):
            for x in dirs:
                q = os.path.join(d, x)
                if os.path.islink(q):
                    # os.walk lists a link to a folder among the folders, and chmod follows it: the arm's link would
                    # have the owner's process open a folder outside the box (the fourth landing review, finding 3)
                    continue
                try:
                    os.chmod(q, 0o700, follow_symlinks=False)
                except (OSError, NotImplementedError):
                    pass
        shutil.rmtree(box, ignore_errors=True)


# ---- F7: the login withdrawn -------------------------------------------------------------------
# An arm's shell runs as the owner, inside its box: whatever its login leaves on disk there, the shell can read,
# and with it start its CLI again with the connectors on (P4: Codex's travel over chatgpt.com, the inference host,
# so no network rule tells them apart). So the login leaves the disk once the CLI has read it: at its first request
# to the vendor through the proxy, before any answer comes back, so before the model's first tool call. Claude's
# never enters the box: it goes on a pipe (CLAUDE_FD). What a CLI holds in memory stays out of the shell's reach:
# the three binaries carry the hardened runtime and no get-task-allow, and an attach from inside the arm was
# refused (P6, P7; record Q1, Q4) — the OS's rule, not ours (the doc's "Limits named").

SECRET_KEY = re.compile(r"token|secret|key|password", re.I)
# a value that is an address is no secret, whatever its key (agy's id_token_email, which its own log prints: Q3)
NOT_SECRET = re.compile(r"[^@\s]+@[^@\s]+\.[A-Za-z]{2,}")
MIN_SECRET = 16           # characters: anything shorter is no needle (it would hit at random)
WINDOW = 24               # a long secret is also looked for by three windows of it, so a cut copy is found too
# what F7 writes in place of a login's strings in a file the arm left (round 5's second review: a CLI's log and the
# harness record kept a withdrawn, unrevoked token in plaintext after the paper was withheld)
F7_MARK = b"[login withdrawn: F7]"
CODEX_TOOL_ITEMS = ("command_execution", "file_change", "web_search", "mcp_tool_call")


def secret_strings(*blobs):
    """The values a credential holds, to look for and never to show: from JSON (or base64 of JSON, a keyring's
    form), every string under a key naming a token, a secret, a key or a password — an account id, an expiry, a
    scope list or an email address is no secret; else the whole blob. Each MIN_SECRET characters or more."""
    import base64
    out = []

    def walk(x, key=""):
        if isinstance(x, dict):
            for k, v in x.items():
                walk(v, str(k))
        elif isinstance(x, list):
            for v in x:
                walk(v, key)
        elif isinstance(x, str) and SECRET_KEY.search(key) and len(x) >= MIN_SECRET and not NOT_SECRET.fullmatch(x):
            out.append(x)
    for blob in blobs:
        text = (blob.decode("utf-8", "replace") if isinstance(blob, bytes) else str(blob or "")).strip()
        parsed = False
        for cand in (text, text.split(":", 1)[-1]):
            for form in (cand, None):
                try:
                    j = json.loads(form if form is not None else base64.b64decode(cand, validate=True).decode("utf-8"))
                except (ValueError, UnicodeDecodeError):
                    continue
                if isinstance(j, (dict, list)):
                    parsed = True
                    walk(j)
        if not parsed and len(text) >= MIN_SECRET:
            out.append(text)
    return list(dict.fromkeys(out))


class Credential:
    """F7: one arm's login. FILES: its files in the box (Codex's auth.json); KEYCHAIN: the per-run keychain under the
    scratch HOME (agy's), deleted whole; PIPE: (the CLI's variable, the bytes) for a login handed on a file
    descriptor and never written (Claude's: open_pipe()); SECRETS: the values, held in memory for the scan and
    never written, logged or printed — a scan says which files, never what matched. KEEP: why the arm keeps its
    login for the whole run (a CLI that needs it again: the doc's "Limits named"), else None. withdraw() is the
    proxy's ON_VENDOR."""

    def __init__(self, cli, files=(), keychain=None, secrets=(), keep=None, pipe=None):
        self.cli, self.files, self.keychain, self.secrets, self.keep = cli, list(files), keychain, list(secrets), keep
        self.pipe = pipe
        self.withdrawn = None

    def open_pipe(self):
        """(the CLI's variable, a read fd): a new pipe holding the login, its write end closed, inheritable. The caller
        sets the variable to the fd's number, passes the fd to the CLI (pass_fds) and closes it once the CLI ran."""
        var, data = self.pipe
        r, w = os.pipe()
        try:
            os.write(w, data)
        finally:
            os.close(w)
        os.set_inheritable(r, True)
        return var, r

    @classmethod
    def in_box(cls, cli, box):
        """The login's places in BOX alone, no secrets: for a caller that only withdraws (harness, for Codex)."""
        h = os.path.join(os.path.realpath(box), "home")
        if cli == "codex":
            return cls(cli, files=[os.path.join(h, ".codex", "auth.json")])
        if cli == "claude":
            return cls(cli)
        return cls(cli, files=[os.path.join(h, ".gemini", "antigravity-cli", AGY_SIGNIN_FILE)],
                   keychain=os.path.join(h, "Library", "Keychains", "login.keychain-db"))

    def present(self):
        """What of the login is still on disk, by name: its files that exist, the per-run keychain's file."""
        left = [os.path.basename(f) for f in self.files if os.path.lexists(f)]
        if self.keychain and os.path.lexists(self.keychain):
            left.append("the per-run keychain")
        return left

    def withdraw(self):
        """Every file unlinked and the per-run keychain deleted (`security delete-keychain` under its scratch HOME,
        the file unlinked after it should that fail), then read back: ok only when nothing is left. A kept login
        is not touched. Never raises."""
        if self.keep:
            self.withdrawn = {"ok": False, "kept": self.keep, "t": round(time.time(), 3)}
            return self.withdrawn
        errs = []
        for f in self.files:
            try:
                os.unlink(f)
            except FileNotFoundError:
                pass
            except OSError as e:
                errs.append("%s: %s" % (os.path.basename(f), e.strerror or e))
        home = os.path.dirname(os.path.dirname(os.path.dirname(self.keychain))) if self.keychain else None
        if self.keychain and os.path.lexists(self.keychain) and in_box(os.path.dirname(home), self.keychain):
            try:
                subprocess.run([SECURITY, "delete-keychain", self.keychain], capture_output=True, stdin=subprocess.DEVNULL,
                               timeout=20, env={"HOME": home, "PATH": "/usr/bin:/bin"})
            except (OSError, subprocess.TimeoutExpired) as e:
                errs.append("delete-keychain: %s" % type(e).__name__)
            try:
                os.unlink(self.keychain)
            except FileNotFoundError:
                pass
            except OSError as e:
                errs.append("the per-run keychain: %s" % (e.strerror or e))
        left = self.present()
        self.withdrawn = {"ok": not left and not errs, "left": left, "why": "; ".join(errs) or None,
                          "t": round(time.time(), 3)}
        return self.withdrawn

    def needles(self):
        out = []
        for s in self.secrets:
            b = s.encode("utf-8")
            out.append(b)
            if len(b) > 2 * WINDOW:
                out += [b[-WINDOW:], b[len(b) // 2:len(b) // 2 + WINDOW], b[len(b) // 4:len(b) // 4 + WINDOW]]
        return list(dict.fromkeys(out))

    def scan(self, roots=(), files=(), own=True, scrub=False, no_scrub=()):
        """The names of the files that hold one of the login's secrets, whole or by a window: every regular file
        under each of ROOTS (links not followed) and each of FILES; the login's own files and keychain skipped
        unless OWN. Names relative to their root, never what matched. SCRUB: each such file is rewritten with
        F7_MARK in place of every secret and window, longest first, through a descriptor opened without following
        a link, so no copy of the login outlives the verdict that names it — except under NO_SCRUB (the arm's box),
        judged by the path as spelt: a folder there is still the arm's to write, and a leftover that swaps one for a
        link would turn the rewrite on a file outside it, the owner's login among them (round 6). A hit there is
        named all the same, and the box is removed whole once the arm ends (drop_box)."""
        needles = self.needles()
        if not needles:
            return []
        skip = set() if own else {os.path.realpath(p) for p in self.files + [self.keychain] if p}
        walled = [os.path.abspath(b) + os.sep for b in no_scrub if b]
        hits, seen = [], set()

        def look(path, name):
            real = os.path.realpath(path)
            if real in seen or real in skip or os.path.islink(path) or not os.path.isfile(path):
                return
            seen.add(real)
            try:
                # never a link, never a FIFO an arm swapped in after the test above (it would block): the file as
                # opened is judged, by its own descriptor (round 3)
                fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            except OSError:
                return
            try:
                if not stat.S_ISREG(os.fstat(fd).st_mode):
                    return
                with os.fdopen(fd, "rb") as f:
                    fd = None
                    data = f.read()
            except OSError:
                return
            finally:
                if fd is not None:
                    os.close(fd)
            if any(n in data for n in needles):
                hits.append(name)
                if scrub and not any(os.path.abspath(path).startswith(w) for w in walled):
                    _scrub(path, data, needles)
        for root in roots:
            for d, dirs, fs in os.walk(root):
                for f in fs:
                    look(os.path.join(d, f), os.path.relpath(os.path.join(d, f), root))
        for f in files:
            if f:
                look(f, os.path.basename(f))
        return hits

    def in_text(self, text):
        """Whether TEXT (a paper, a reply) holds one of the secrets, whole or by a window."""
        data = (text or "").encode("utf-8", "replace")
        return any(n in data for n in self.needles())


def _scrub(path, data, needles):
    """PATH rewritten as DATA with F7_MARK for each of NEEDLES, longest first; a link, a non-file or a file that
    cannot be opened left as it is (scan already named it)."""
    for n in sorted(needles, key=len, reverse=True):
        data = data.replace(n, F7_MARK)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return
        os.ftruncate(fd, 0)
        os.write(fd, data)
    except OSError:
        pass
    finally:
        os.close(fd)


def tool_event(cli, e):
    """Whether E, one event of CLI's own log as F5 reads it, is a tool call: Claude's tool_use block, a Codex tool
    item (a command, a patch, a search, an MCP call), an agy tool step."""
    if not isinstance(e, dict):
        return False
    if cli == "claude":
        return e.get("type") == "assistant" and any(isinstance(b, dict) and b.get("type") == "tool_use"
                                                    for b in (e.get("message") or {}).get("content") or [])
    if cli == "codex":
        it = e.get("item")
        return str(e.get("type") or "").startswith("item.") and isinstance(it, dict) and it.get("type") in CODEX_TOOL_ITEMS
    if cli == "agy":
        s = e.get("step_update")
        # a step of a type no probe saw counts as a tool call: the login's check runs at it (the review's S3)
        return e.get("event") == "step_update" and isinstance(s, dict) and s.get("step_type") not in AGY_TALK_STEPS
    return False


class FirstTool:
    """F7's second read: a thread tailing LOG, the CLI's own (a file that may not exist yet), until the first tool
    call in it, when it reads what of CRED is still on disk. FOUND: None while no tool call was seen, else that
    list — empty is the login gone. stop() ends the watch; a tool call it had not reached by then is read late,
    from the whole log, and the login judged as it is then."""

    def __init__(self, cli, log, cred, poll=0.05):
        self.cli, self.log, self.cred, self.poll = cli, log or "", cred, poll   # no log: nothing to read, never a crash
        self.found = None
        self.at = None
        self.late = False
        self._stop = threading.Event()
        self._t = threading.Thread(target=self._run, daemon=True)
        self._t.start()

    def _run(self):
        pos, buf = 0, b""
        while not self._stop.is_set():
            try:
                with open(self.log, "rb") as f:
                    f.seek(pos)
                    chunk = f.read()
            except OSError:
                chunk = b""
            pos += len(chunk)
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if tool_event(self.cli, e):
                    self.found, self.at = self.cred.present(), round(time.time(), 3)
                    return
            self._stop.wait(self.poll)

    def stop(self):
        self._stop.set()
        self._t.join(5)
        if self.found is None and any(tool_event(self.cli, e) for e in _events(self.log)):
            self.found, self.at, self.late = self.cred.present(), round(time.time(), 3), True
        return self


def f7(cred, first=None, roots=(), files=(), text=None, box=None):
    """F7's verdict on one arm once its CLI ended: (a summary for run.json, [why the arm fails]). A login not kept
    fails the arm when its withdrawal never ran though the CLI made a tool call, when it ran and left something,
    or when anything of it was on disk at the first tool call (FIRST, a FirstTool); every login, kept or not,
    when its strings are in a file under ROOTS or among FILES (the arm's dir, the CLI's own log), or in TEXT — its
    own files counted only once a withdrawal ran (a kept login, or one whose CLI never reached its vendor, is still
    where it was put). Each file holding it is rewritten without it, except under BOX (Credential.scan)."""
    w = cred.withdrawn
    seen = first.found if first else None
    summary = {"kept": cred.keep} if cred.keep else {"withdrawn": w, "at_first_tool": seen,
                                                      "first_tool_t": getattr(first, "at", None),
                                                      "read_late": bool(first and first.late)}
    bad = []
    if not cred.keep:
        if w is None and seen is not None:
            bad.append("the login was never withdrawn, yet the CLI called a tool: no allowed connection to its vendor "
                       "reached the proxy first (F7)")
        elif w is not None and not w.get("ok"):
            bad.append("the login's withdrawal left %s%s (F7)" % (", ".join(w.get("left") or []) or "an error",
                                                                 ": %s" % w["why"] if w.get("why") else ""))
        if seen:
            bad.append("the login was on disk at the first tool call: %s (F7)" % ", ".join(seen))
    if cred.pipe:
        summary["pipe"] = cred.pipe[0]
    hits = cred.scan(roots, files, own=not cred.keep and w is not None, scrub=True, no_scrub=[box] if box else ())
    summary["files_holding_it"] = len(hits)
    if hits:
        bad.append("the login's strings are in %d file(s) the arm left: %s (F7)" % (len(hits), ", ".join(hits[:5])))
    if text and cred.in_text(text):
        summary["paper_holds_it"] = True
        bad.append("the paper holds the login's strings: withheld (F7)")
    return summary, bad


def proxy_env(port):
    """The proxy in both cases (curl reads only the lowercase http_proxy for http URLs: record P2)."""
    url = "http://127.0.0.1:%d" % int(port)
    return {k: url for k in ("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "ALL_PROXY", "all_proxy")}


def arm_env(cli, box, port, home_env, extra=None, path_first=None):
    """The arm's environment, built from nothing (`env -i` and an allowlist; the third landing review's 21): PATH,
    HOME (the box's), LANG, TMPDIR (the box's), USER, LOGNAME, SHELL, the proxy, REGATTA_COUNCIL_ARM (keel's
    sheep_gate drops an arm's sessionpipe events by it), HOME_ENV (each CLI's own: its config dir or home) and
    EXTRA. Never the session's messaging socket or token, SSH_AUTH_SOCK, a login token of the caller's (bar the
    one HOME_ENV carries), Orca's pane variables or Claude Code's nesting mark."""
    user = _user()
    path = [p for p in (path_first if path_first and not os.path.isfile(path_first) else None,
                        "/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin") if p]
    env = {"PATH": ":".join(dict.fromkeys(path)), "HOME": os.path.join(box, "home"), "TMPDIR": os.path.join(box, "tmp"),
           "LANG": os.environ.get("LANG") or "en_US.UTF-8", "USER": user, "LOGNAME": user,
           "SHELL": os.environ.get("SHELL") or "/bin/zsh", "REGATTA_COUNCIL_ARM": "1"}
    if os.environ.get("LC_ALL"):
        env["LC_ALL"] = os.environ["LC_ALL"]
    if port:
        env.update(proxy_env(port))
        env["NO_PROXY"] = env["no_proxy"] = ""
    if cli == "claude":
        env.update(CLAUDE_CODE_TMPDIR=env["TMPDIR"], CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1", DISABLE_AUTOUPDATER="1")
    env.update(home_env or {})
    env.update(extra or {})
    return env


# ---- what any same-user process's environment shows an arm (the fourth landing review, finding 1) ----------
# An arm reads the environment every process of its user started with, its ancestors included, through sysctl
# KERN_PROCARGS2: no seatbelt rule closes it ((deny sysctl-read) and (deny process-info*) were probed and do not).
# So council and harness re-exec themselves from nothing (reexec_clean: no credential-named variable on their own
# start, the ones they need on a pipe), and F4's start probe refuses while any process of the user holds a
# credential-named variable (env_holders: names only, never a value). The doc's "Limits named" says what is left.

CTL_KERN, KERN_ARGMAX, KERN_PROCARGS2 = 1, 8, 49
CLEAN_KEEP = ("PATH", "HOME", "USER", "LOGNAME", "SHELL", "LANG", "TMPDIR", "TERM", "TERM_PROGRAM", "TZ",
              # agy's home: a path, no credential; account's tenancy and _home_agy read it (round 6), never the arm
              "GEMINI_CLI_HOME",
              "__CF_USER_TEXT_ENCODING", "__PYVENV_LAUNCHER__")   # what macOS's Python sets in itself at every start
CLEAN_MARK = "REGATTA_FENCE_CLEAN"   # set on the one re-exec: never a second (round 1: a whole-dict test looped)
CLEAN_PREFIXES = ("LC_", "COUNCIL_", "HARNESS_", "STUB_", "GATE_", "REGATTA_", "DISPATCH_", "CLAUDE_", "GIT_", "CODEX_",
                  "AUTOFINISH_CALLER_", "PLAN_")
CLEAN_PIPE = "REGATTA_FENCE_PIPE"   # the fd the parent's credentials arrive on, read once into PIPED
HOLDERS_STAND_IN = "REGATTA_FENCE_HOLDERS"   # a suite's file of names, honoured for an attended caller only
PIPED = {}


_LIBC = []


def _libc():
    import ctypes
    import ctypes.util
    if not _LIBC:
        _LIBC.append(ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True))
    return _LIBC[0]


def _sysctl_procargs(pid, cap, buf=None):
    import ctypes
    libc = _libc()
    mib = (ctypes.c_int * 3)(CTL_KERN, KERN_PROCARGS2, pid)
    # the scan's own buffer, reused across its processes (round 1: a MiB each; round 2: never one kept per thread)
    buf = buf if buf is not None else ctypes.create_string_buffer(cap)
    size = ctypes.c_size_t(cap)
    if libc.sysctl(mib, 3, buf, ctypes.byref(size), None, 0) != 0:
        return None
    return buf.raw[:size.value]


def _argmax():
    import ctypes
    libc = _libc()
    mib = (ctypes.c_int * 2)(CTL_KERN, KERN_ARGMAX)
    v = ctypes.c_int(0)
    size = ctypes.c_size_t(ctypes.sizeof(v))
    libc.sysctl(mib, 2, ctypes.byref(v), ctypes.byref(size), None, 0)
    return v.value or (1 << 20)


def env_names(pid, cap=None, buf=None):
    """The names of the variables process PID started with, as KERN_PROCARGS2 shows them to any process of its
    user, an arm's shell included; None when it does not read (another user's, gone, off macOS). Never a value.
    The kernel shows no environment for Apple's own system binaries (/bin/sleep, /bin/sh: round 1's probe)."""
    if sys.platform != "darwin":
        return None
    try:
        raw = _sysctl_procargs(pid, cap or _argmax(), buf)
    except (OSError, ValueError, AttributeError):
        return None
    if not raw or len(raw) < 4:
        return None
    return _env_from_procargs(raw)


_ASSIGN = re.compile(rb"^([^=\0]+)=")   # any name an exec environment can hold (round 3: MY-TOKEN too)


def _env_from_procargs(raw):
    """The NAME of every NAME=… string after the exec path, as an arm's parser would take them: never counted from
    argc, since a process that retitles itself (libuv's process.title) zero-fills its argv area and an argc count
    then stops early while the raw bytes still hold every variable (round 2). An argument shaped like an
    assignment counts too: the safe side."""
    rest = raw[4:]
    i = rest.find(b"\0") + 1      # past the exec path
    out = []
    for e in rest[i:].split(b"\0"):
        m = _ASSIGN.match(e)
        if m:
            out.append(m.group(1).decode("utf-8", "surrogateescape"))
    return out


def env_holders():
    """{name: processes} of the credential-named variables (SECRET_KEY) any process of this user holds, as an arm
    would read them: names only. REGATTA_FENCE_HOLDERS (a file of names, one a line) stands in for a suite, never
    for an unattended caller: a fence a dispatched run could switch off is none."""
    stand_in = os.environ.get(HOLDERS_STAND_IN)
    if stand_in and not _common().unattended_caller():
        try:
            names = [x.strip() for x in open(stand_in) if x.strip()]
        except OSError:
            names = ["(%s does not read)" % HOLDERS_STAND_IN]
        return {n: 1 for n in names}
    if sys.platform != "darwin":
        return {}
    try:
        r = subprocess.run(["/bin/ps", "-axo", "pid=,uid="], capture_output=True, text=True, timeout=20)
        pids = [int(a) for a, b in (l.split() for l in r.stdout.splitlines() if len(l.split()) == 2)
                if int(b) == os.getuid()]
    except (OSError, ValueError, subprocess.SubprocessError):
        return {"(the process list does not read)": 1}
    if os.getpid() not in pids or env_names(os.getpid()) is None:
        # a list without this very process, or a read that fails even on it, reads nothing: no holder is known
        return {"(the process list or KERN_PROCARGS2 does not read here)": 1}
    import ctypes
    cap = _argmax()
    buf = ctypes.create_string_buffer(cap)
    out = {}
    for pid in pids:
        for n in set(env_names(pid, cap, buf) or ()):
            if SECRET_KEY.search(n) and n not in FD_NAMES:
                out[n] = out.get(n, 0) + 1
    return out


# the Claude arm's own variables naming the fd its login is read from: a number, never a credential (round 1: the
# arms refused each other while opus's claude ran)
FD_NAMES = ("CLAUDE_CODE_OAUTH_TOKEN_FILE_DESCRIPTOR", "CLAUDE_CODE_API_KEY_FILE_DESCRIPTOR")


def is_stand_in(path):
    """True when PATH is a suite's stand-in: a `#!` script that is no node launcher (npm installs the CLIs so). The
    three CLIs are compiled binaries where this was built; a copy of one is the real CLI (round 4)."""
    try:
        with open(os.path.realpath(shutil.which(path) or path), "rb") as fh:
            line = fh.readline(200)
    except OSError:
        return False
    return line.startswith(b"#!") and b"node" not in line


def stand_in_holders(binary, name):
    """The suite's stand-in list (REGATTA_FENCE_HOLDERS) for an arm whose CLI is a stand-in — BINARY is not NAME
    on PATH — attended or not: no vendor is reached there, so no credential could leave by it. None otherwise:
    the probe reads every process (env_holders' own rule, attended only)."""
    f = os.environ.get(HOLDERS_STAND_IN)
    real = shutil.which(name)
    mine = os.path.realpath(shutil.which(binary) or binary)   # a bare name resolved on PATH, as install_of does
    if not f or (real and os.path.realpath(real) == mine):
        return None
    script = is_stand_in(mine)
    if not script:
        # the three CLIs are compiled binaries: a copy of one elsewhere is the real CLI, never a stand-in (round 2)
        return None
    try:
        return {n: 1 for n in (x.strip() for x in open(f)) if n}
    except OSError:
        return {"(%s does not read)" % HOLDERS_STAND_IN: 1}


def holders_why(holders=None):
    """F4's refusal while any process of this user holds a credential-named variable an arm could read, or None."""
    h = env_holders() if holders is None else holders
    if not h:
        return None
    return ("processes of this user hold credential-named variables an arm reads through sysctl (KERN_PROCARGS2), "
            "which no seatbelt rule closes: %s — no arm starts while one does (the fourth landing review, finding 1)"
            % ", ".join("%s in %d" % kv for kv in sorted(h.items())))


def clean_env(environ=None):
    """ENVIRON (the caller's) cut to the allowlist and with no credential-named variable: what reexec_clean starts
    from."""
    environ = os.environ if environ is None else environ
    return {k: v for k, v in environ.items()
            if (k in CLEAN_KEEP or k.startswith(CLEAN_PREFIXES)) and not SECRET_KEY.search(k)}


def reexec_clean(argv, pipe=()):
    """Run this program again from nothing unless its environment is clean already: env -i, the allowlist
    (clean_env), and the variables PIPE names, which it needs, on a pipe (CLEAN_PIPE names the fd) rather than in
    its environment, where KERN_PROCARGS2 would show them to an arm (the fourth landing review, finding 1). In the
    clean run, the pipe is read into PIPED. ARGV: the program and its arguments (sys.argv)."""
    fd = os.environ.pop(CLEAN_PIPE, None)   # read once, here: a child given the number would read another fd
    if fd and fd.isdigit():
        try:
            with os.fdopen(int(fd), "r") as f:
                PIPED.update(json.load(f))
        except (OSError, ValueError):
            pass
    if os.environ.get(CLEAN_MARK) == "1":
        # re-exec'd once already: never again (round 2). A credential-named variable here came back by the start
        # itself, or a caller set the mark to skip the cut: either way the fence cannot say what an arm reads
        back = sorted(k for k in os.environ if SECRET_KEY.search(k) or not (k in CLEAN_KEEP or k.startswith(CLEAN_PREFIXES)))
        if back:
            raise FenceError("this process's start environment holds %s after its clean re-exec: an arm would read "
                             "it through sysctl (names only here)" % ", ".join(back))
        return
    env = clean_env()
    env[CLEAN_MARK] = "1"
    secrets = {k: os.environ[k] for k in pipe if os.environ.get(k)}
    secrets.update({k: v for k, v in PIPED.items() if k in pipe and k not in secrets})
    if secrets:
        r, w = os.pipe()
        data = json.dumps(secrets).encode()
        if len(data) > 60000:
            raise FenceError("the credentials to pipe are %d bytes, past one pipe's buffer" % len(data))
        os.write(w, data)
        os.close(w)
        os.set_inheritable(r, True)
        env[CLEAN_PIPE] = str(r)
    sys.stdout.flush()
    sys.stderr.flush()
    os.execve(sys.executable, [sys.executable] + list(argv), env)


# ---- the gates: each CLI's own listing, no model call --------------------------------------------

def _listing(argv, env, cwd=None, timeout=60, fds=()):
    try:
        r = subprocess.run(argv, capture_output=True, text=True, env=env, cwd=cwd, stdin=subprocess.DEVNULL, timeout=timeout,
                           pass_fds=tuple(fds))
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, "`%s` did not answer (%s)" % (" ".join(argv[-3:]), type(e).__name__)
    if r.returncode:
        tail = ((r.stderr or r.stdout) or "").strip().splitlines()
        return None, "`%s` exit %d%s" % (" ".join(argv[-3:]), r.returncode, ": %s" % tail[-1][:160] if tail else "")
    return r.stdout, None


def features_diff(listing):
    """`codex features list`'s text against the pinned CODEX_FEATURES: {"on": names on, "new": on and never judged,
    "gone": judged and no longer on (dropped, removed or off by default now)}, or None when LISTING is not the table
    (no feature on). A removed feature is no feature. The S5 re-probe prints it; codex_features refuses on "new"."""
    rows = [l.split() for l in (listing or "").splitlines() if l.strip()]
    on = [r[0] for r in rows if len(r) >= 3 and r[-1] == "true" and r[1] != "removed"]
    if not on:
        return None
    return {"on": on, "new": [n for n in on if n not in CODEX_FEATURES],
            "gone": sorted(n for n in CODEX_FEATURES if n not in on)}


def codex_features(env, codex="codex", cwd=None):
    """(None, None) when every feature `codex features list` shows on is judged in CODEX_FEATURES, else
    (unjudged names, why), or (None, why) when the list does not read. A removed feature is no feature."""
    out, why = _listing([codex, "features", "list"], env, cwd)
    if out is None:
        return None, why
    diff = features_diff(out)
    if diff is None:
        return None, "`codex features list` printed no feature that is on: not the table this check reads"
    new = diff["new"]
    if new:
        return new, ("Codex has features on that no one judged (%s): the arm is refused until fence.CODEX_FEATURES "
                     "names each" % ", ".join(new))
    return None, None


def codex_flags():
    """`--disable` for every feature judged off: hygiene (CODEX_FEATURES' comment)."""
    off = [n for n, v in CODEX_FEATURES.items() if v == "off"] + list(CODEX_ALSO_OFF)
    return [x for n in off for x in ("--disable", n)]


def claude_mcp(env, claude="claude", cwd=None, fds=()):
    """(servers, None): every MCP server `claude mcp list` names under the scratch config dir, the account's
    connectors and the copy's .mcp.json included, bar CLAUDE_MCP_SAFE; or (None, why) when it does not read. FDS:
    the login's pipe (ENV names it), which the account's connectors need."""
    out, why = _listing([claude, "mcp", "list"], env, cwd, timeout=90, fds=fds)
    if out is None:
        return None, why
    servers = []
    for line in out.splitlines():
        x = line.strip()
        if not x or x.startswith(CLAUDE_MCP_CHATTER):
            continue
        m = re.match(r"^(.+?): (\S.*?) - ", x)
        if not m:
            # a line this gate cannot read may be a server it would miss: refused, never read as none (the fourth
            # landing review, finding 8: a new format read as no servers, and the arm kept Bash beside them)
            return None, "`claude mcp list` printed a line this gate cannot read (%r): the arm is refused" % x[:120]
        if m.group(1) not in CLAUDE_MCP_SAFE:
            servers.append(m.group(1))
    return servers, None


# ---- F5: the record, from each CLI's own log ---------------------------------------------------

# Codex's item kinds (OpenAI's documented names): the reply, its reasoning, the shell, its patches and the web
CODEX_ITEMS = ("agent_message", "reasoning", "command_execution", "file_change", "web_search", "todo_list", "error")
CAP = 200


def _events(path):
    if not path:
        return   # no log (a Codex arm whose raw result F7 withheld): no events, never a TypeError (the landing review)
    try:
        with open(path, errors="replace") as f:
            for line in f:
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if isinstance(e, dict):
                    yield e
    except OSError:
        return


def record(cli, log, tools=None, research=False):
    """F5, from CLI's own log at LOG: {"readable", "tools": {name: count}, "commands": [...], "denied": [...],
    "bad": [why...], "result": the CLI's last result event}. TOOLS: the names the start allowed (Claude). An arm
    fails on an unreadable log, a tool or item the start did not allow (a connector, a browser, a sub-agent), or an
    agy step outside our hook's allowlist that the hook did not deny. RESEARCH off: a web step that ran fails it too
    (agy's search_web or read_url_content that our hook did not deny, Codex's web_search item), so a CLI that
    stops asking the hook, or a renamed flag, is caught rather than read as allowed (round 6's third review).
    Paths are not judged: the kernel refused what it refused."""
    rec = {"readable": False, "tools": {}, "commands": [], "denied": [], "bad": [], "result": None}
    if not log or not os.path.isfile(log):
        rec["bad"].append("no log at %s" % log)
        return rec
    n = 0
    for e in _events(log):
        n += 1
        if cli == "claude":
            _claude_event(e, rec, tools or ())
        elif cli == "codex":
            _codex_event(e, rec)
        elif cli == "agy":
            _agy_event(e, rec)
    rec["readable"] = n > 0
    if not n:
        rec["bad"].append("the log %s holds no event" % log)
    for name in (rec.pop("_outside", None) or {}).values():
        # no refusal read back for it: it may have run (fail closed). "cut" names it too, and nothing else in "bad":
        # a reader of a log the timeout ended may call it unproven rather than broken (council fences). Its words are
        # its own, never a returned call's ("claude used …"): that reader drops "cut" reasons by text (S5's round 4)
        why = "claude called %s, a tool the start did not allow, and its log holds no result for it" % name
        rec["bad"].append(why)
        rec.setdefault("cut", []).append(why)
    if cli == "agy":
        _agy_judge(rec, research)
    if cli == "codex" and not research and rec["tools"].get("web_search"):
        rec["bad"].append("codex ran web_search with research off: the start turned it off")
    rec["commands"] = rec["commands"][:CAP]
    return rec


def _count(rec, name):
    rec["tools"][name] = rec["tools"].get(name, 0) + 1


# claude's own tool_use_error for a name outside --tools (2.1.316), as its result begins: a tool that ran and erred
# with the phrase somewhere in its text is not this
CLAUDE_REFUSED = r"<tool_use_error>Error: No such tool available: %s(?:\.|</tool_use_error>)"


def _claude_event(e, rec, allowed):
    t = e.get("type")
    if t == "system" and e.get("subtype") == "init":
        extra = [x for x in e.get("tools") or [] if x not in allowed]
        if extra:
            rec["bad"].append("claude's init lists tools the start did not allow: %s" % ", ".join(extra)[:200])
        servers = [s.get("name") if isinstance(s, dict) else str(s) for s in e.get("mcp_servers") or []]
        if servers:
            rec["bad"].append("claude's init lists MCP servers: %s" % ", ".join(map(str, servers))[:200])
    elif t == "user":
        # a call outside the start's tools that claude refused itself (S5's live turn: "No such tool available:
        # Agent. Agent is disabled for this session") is a denial, as our hook's are for agy; any other result runs
        for b in (e.get("message") or {}).get("content") or []:
            pending = rec.get("_outside") or {}
            if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("tool_use_id") in pending:
                name = pending.pop(b["tool_use_id"])
                if b.get("is_error") and re.match(CLAUDE_REFUSED % re.escape(name), _text(b.get("content")).lstrip()):
                    rec["denied"].append(name)
                else:
                    rec["bad"].append("claude used %s, a tool the start did not allow" % name)
    elif t == "assistant":
        for b in (e.get("message") or {}).get("content") or []:
            if isinstance(b, dict) and b.get("type") == "tool_use":
                name = str(b.get("name") or "?")
                _count(rec, name)
                if name not in allowed:
                    rec.setdefault("_outside", {})[b.get("id") or "?%d" % len(rec.get("_outside") or {})] = name
                inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                c = inp.get("command") or inp.get("url") or inp.get("file_path") or inp.get("pattern")
                if c:
                    rec["commands"].append("%s: %s" % (name, str(c)[:400]))
    elif t == "result":
        rec["result"] = e


def _codex_event(e, rec):
    t = str(e.get("type") or "")
    if t in ("turn.failed", "error"):
        inner = e.get("error")
        rec.setdefault("errors", []).append(str(e.get("message") or (inner.get("message") if isinstance(inner, dict) else inner))[:300])
    if not t.startswith("item."):
        return
    it = e.get("item")
    if not isinstance(it, dict):
        return
    kind = str(it.get("type") or "?")
    if t == "item.completed" or kind == "command_execution":
        key = (it.get("id"), kind)
        if key in rec.setdefault("_seen", set()):
            return
        rec["_seen"].add(key)
        _count(rec, kind)
    if kind not in CODEX_ITEMS:
        why = "codex's turn held %s, an item the start turned off" % kind
        if why not in rec["bad"]:
            rec["bad"].append(why)
    if kind == "command_execution" and it.get("command"):
        rec["commands"].append(str(it["command"])[:400])


# agy's step types that are no tool call, as the S0–S5 probes' logs show them; any other type is no step F5 may skip
AGY_TALK_STEPS = ("agent_response", "system_message", "user_input")


def _agy_error(err):
    """A step's error as its message: agy logs {'type', 'message'} (probes/s5/fences-3), and a fixture its repr. Read
    whole, so a denial is our hook's only when the message is exactly its (the seventh landing review: a substring
    match took an echoed argument for one)."""
    if isinstance(err, str) and err.startswith("{"):
        try:
            import ast
            err = ast.literal_eval(err)
        except (ValueError, TypeError, SyntaxError, MemoryError, RecursionError):
            pass
    if isinstance(err, dict):
        return str(err.get("message") or "")
    return str(err or "")


def _agy_event(e, rec):
    if e.get("event") == "step_update" and isinstance(e.get("step_update"), dict):
        s = e["step_update"]
        if s.get("step_type") in AGY_TALK_STEPS:
            return
        if s.get("step_type") != "tool":
            # skipped, it would be a tool no one judged (the fourth landing review's S3): the arm fails, named
            why = "agy's step type %r is none the probes saw: F5 cannot judge it" % s.get("step_type")
            if why not in rec["bad"]:
                rec["bad"].append(why)
            return
        steps = rec.setdefault("_steps", {})
        info = s.get("tool_info") if isinstance(s.get("tool_info"), dict) else {}
        idx = s.get("step_index")
        steps[idx if idx is not None else ("no index", len(steps))] = (str(s.get("tool_name") or "?"), s.get("state"),
                                                                       _agy_error(info.get("error")),
                                                                       str(info.get("parameters") or "")[:400])
    elif e.get("event") == "result":
        rec["result"] = e.get("result")


_AGY_HOOK = []
_AGY_HOOK_LOCK = threading.Lock()


def agy_hook():
    """Our agy hook, beside this file: its ALLOW and REASON are the list F5 judges by. Loaded once, under a lock:
    two agy arms end together from fan()'s threads, and two load_module calls at once can drop one's module
    (gate's _jev_module, the same race; round 6's fourth review)."""
    with _AGY_HOOK_LOCK:
        if not _AGY_HOOK:
            from importlib.machinery import SourceFileLoader
            _AGY_HOOK.append(SourceFileLoader("agy_hook", os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                                       "agy_hook.py")).load_module())
        return _AGY_HOOK[0]


def _agy_judge(rec, research=False):
    hook = agy_hook()
    # in the order they ran: an int index by number, before any step agy logged without one
    for _, (name, state, err, params) in sorted(rec.pop("_steps", {}).items(), key=lambda kv: (
            (0, kv[0], "") if isinstance(kv[0], int) else (1, 0, str(kv[0])))):
        _count(rec, name)
        ours = state == "ERROR" and err == "tool call denied by pre-tool hook: " + hook.REASON   # whole (review 7)
        if ours:
            rec["denied"].append(name)
        elif not research and name in hook.WEB:
            # the hook allows these only with --research: one that ran without it was never put to the hook
            rec["bad"].append("agy's web step %s (%s) ran with research off: our hook did not deny it" % (name, state))
        elif name not in hook.ALLOW:
            # ACTIVE as its last state too: a step still running, or not yet judged by our hook (agy writes ACTIVE
            # before the hook's ERROR: probes/s5/fences-3), when the log ended; that one also in "cut", as record()'s
            # Claude calls with no result
            why = "agy's step %s (%s) is outside our hook's allowlist and the hook did not deny it" % (name, state)
            rec["bad"].append(why)
            if state == "ACTIVE":
                rec.setdefault("cut", []).append(why)
        if name == "run_command" and params:
            rec["commands"].append(params)


AGY_EXIT = re.compile(r"Command exited with code (-?\d+)")
SH_WRAP = re.compile(r"^\S*/(?:ba|z)?sh -l?c '(.*)'$", re.S)


def _text(content):
    """A tool result's content as text: a string, or Claude's list of text blocks."""
    if isinstance(content, list):
        return "\n".join(str(b.get("text") or "") for b in content if isinstance(b, dict))
    return "" if content is None else str(content)


def outcomes(cli, log):
    """Every shell command CLI's own log at LOG shows run, in order, with what it printed: [{"command", "output",
    "exit"}] (exit None where the log does not say; output cut to 600 characters). Read from the log alone, never
    the arm's answer: S5's re-probe judges these (council fences). Codex's `/bin/zsh -lc '…'` wrapper is taken
    off, so a command reads as it was asked."""
    out, uses = [], {}
    for e in _events(log):
        if cli == "claude":
            t = e.get("type")
            for b in (e.get("message") or {}).get("content") or [] if t in ("assistant", "user") else []:
                if not isinstance(b, dict):
                    continue
                if t == "assistant" and b.get("type") == "tool_use" and b.get("name") == "Bash":
                    inp = b.get("input") if isinstance(b.get("input"), dict) else {}
                    uses[b.get("id")] = {"command": str(inp.get("command") or ""), "output": "", "exit": None}
                    out.append(uses[b.get("id")])
                elif t == "user" and b.get("type") == "tool_result" and b.get("tool_use_id") in uses:
                    u, text = uses[b["tool_use_id"]], _text(b.get("content"))
                    m = re.match(r"Exit code (-?\d+)", text)
                    u.update(output=text[:600], exit=int(m.group(1)) if m else (1 if b.get("is_error") else 0))
        elif cli == "codex":
            it = e.get("item") if isinstance(e.get("item"), dict) else {}
            if e.get("type") == "item.completed" and it.get("type") == "command_execution":
                cmd = str(it.get("command") or "")
                m = SH_WRAP.match(cmd)
                code = it.get("exit_code")
                out.append({"command": m.group(1) if m else cmd, "output": str(it.get("aggregated_output") or "")[:600],
                            "exit": code if isinstance(code, int) else None})
        elif cli == "agy" and e.get("event") == "step_update" and isinstance(e.get("step_update"), dict):
            s = e["step_update"]
            info = s.get("tool_info") if isinstance(s.get("tool_info"), dict) else {}
            if s.get("tool_name") != "run_command" or s.get("state") not in ("DONE", "ERROR"):
                continue
            params = info.get("parameters") if isinstance(info.get("parameters"), dict) else {}
            text = str(info.get("output") or info.get("error") or "")
            m = AGY_EXIT.search(text)
            body = text.split("Command output:", 1)[-1].strip() if "Command output:" in text else text
            out.append({"command": str(params.get("CommandLine") or ""), "output": body[:600],
                        "exit": int(m.group(1)) if m else (1 if s.get("state") == "ERROR" else None)})
    return out


def offered(cli, log):
    """The tool names CLI's init event says it offers (Claude's `tools`, agy's `init.tools`), or None: what a CLI
    update adds shows here first. Codex prints no such list."""
    for e in _events(log):
        if cli == "claude" and e.get("type") == "system" and e.get("subtype") == "init":
            return [str(x) for x in e.get("tools") or []]
        if cli == "agy" and e.get("event") == "init" and isinstance(e.get("init"), dict):
            return [str(x) for x in e["init"].get("tools") or []]
    return None


def clean(rec):
    """REC without the readers' working keys, for run.json."""
    return {k: v for k, v in rec.items() if not k.startswith("_")}


# ---- what may not leave ------------------------------------------------------------------------

def leave_paths(root):
    """[(path under ROOT, why)] for every path the secrets guard closes to agents: a vault's _secrets or
    _contacts folder, an env file (.env, .env.<x> bar an example or a template). Links are not followed."""
    hits = []
    root = os.path.realpath(root)
    for d, dirs, files in os.walk(root):
        rel = os.path.relpath(d, root)
        for x in list(dirs):
            if fold(x) in VAULT_FOLDERS:
                hits.append((os.path.normpath(os.path.join(rel, x)), "a vault folder the secrets guard closes"))
                dirs.remove(x)
        for f in files:
            if _env_file(f):
                hits.append((os.path.normpath(os.path.join(rel, f)), "an env file the secrets guard closes"))
    return hits


def fold(name):
    """NAME as APFS compares it, near enough: NFD, then case-folded (`ſ` is `s`, the Kelvin sign `k`; round 2)."""
    import unicodedata
    return unicodedata.normalize("NFD", name).casefold()


def _env_file(f):
    """True when the file name F is an env file the secrets guard closes (an example or a template is not), its
    name compared as the file system compares it."""
    f = fold(f)
    return f == ".env" or (f.startswith(".env.") and not f.endswith(ENV_HARMLESS))


def leave_names(paths):
    """[(path, why)] for the /-separated relative PATHS (a tree's, as `git ls-tree -r --name-only` lists them) that
    leave_paths would name in a checkout: a vault folder anywhere in one, an env file at its end. For what a copy's
    .git carries beside its checkout (the fourth landing review, finding 4)."""
    hits = []
    for p in paths:
        if not p:
            continue
        parts = p.split("/")
        if any(fold(x) in VAULT_FOLDERS for x in parts[:-1]):
            hits.append((p, "a vault folder the secrets guard closes"))
        elif _env_file(parts[-1]):
            hits.append((p, "an env file the secrets guard closes"))
    return hits


CREDENTIAL_KIND = re.compile(r"sk-ant-|sk-|[sr]k_(?:live|test)_|gh[pousr]_|github_pat_|AKIA|AIza|ya29\.|1//0|"
                             r"xox[abprs]-|eyJ")


def leave_text(text):
    """The credential shapes TEXT holds, by kind and never by value (a paper that quotes its own token)."""
    out = []
    for m in CREDENTIAL.finditer(text or ""):
        s = m.group(0)
        k = CREDENTIAL_KIND.match(s)
        # the vendor's own prefix and nothing after it: s[:6] printed a character or two of the secret (round 6's
        # second review)
        kind = "a private key" if s.startswith("-----") else "a %s… token" % (k.group(0).rstrip("-") if k else "credential")
        if kind not in out:
            out.append(kind)
    return out

