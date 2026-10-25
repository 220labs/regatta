#!/usr/bin/env python3
"""talk_nudge — SessionStart: tell a session how to hear the spacesheep Session tab.
Stdlib, Python 3.9. Wired user-wide on SessionStart by `bootstrap.sh --hooks`.

Why it exists (the owner, 2026-10-13): spacesheep's Session tab said "<host> isn't listening
yet" for every session on the build box. A session hears that tab only while it runs `spacesheep
talk listen` itself, and only a SessionStart note tells it to: the spacesheep CLI printed one from
its own session hook, which `sessionpipe install` replaced, so no session was told any more. The
owner chose a listener per session over sessionpipe's control daemon (`machine on`), which stays off as
docs/session-asks-2026-10-09.md section "sessionpipe's control daemon" decided: a message arrives
in the live session itself, with its context and its own permissions, never a headless fork.

Paired Macs (docs/session-listen-2026-10-13.md, D1-B, R2; reverses the paragraph above for any
Mac where sessionpipe's control daemon is paired): every session that is not private is told to
hold `sessionpipe wait --session claude-code:<id>` in the background, so a Session-tab message
arrives in place instead of in a headless fork the open pane never sees. Silent for a private
session (sheep_gate.private_reason, whose PRIVATE_REPOS helmlib.GUARDED reads: a waiter
registers its id with the daemon, which sends every waiting id to the receiver; the same gate
covers the Talk path below), for a run that ends with its turn ($SESSIONPIPE_CONTROL_JOB,
$CLAUDE_UNATTENDED), after a compaction, when the daemon does not answer on its socket (not running: a waiter would retry it
forever; a socket file outlives a daemon that died, so it is connected to, never just stat'ed),
and for a cwd outside control.json's folders (the daemon refuses it; review 2026-10-14).

Unpaired Macs, the text below, unchanged. Prints, in order of the gates, nothing unless all hold:
- this Mac is a Talk host: `host_name()` is in $CLAUDE_TALK_HOSTS, else in the config dir's
  `helm/talk-hosts` (one per line; none named, no Mac is — the Macs the owner messages sessions
  on; the laptop's sessions are in front of the owner);
- the event is not a compaction (the listener the session started is still running);
- the spacesheep CLI is signed in here and this machine opted in with `spacesheep talk on`
  (its config's `talk: true` and a `key`; $SPACESHEEP_KEY also counts as signed in);
- no machine listener is paired (spacesheep's machine.json, sessionpipe's control.json with a
  receiver): that one already reaches every session, and two would answer twice;
- the account's plan, as helm last read it (the core's sheep_plan cache), does not lack Talk:
  on Free a listener hears only a refusal (since 2026-10-24).

The text is fixed here, after the CLI's own `nudgeText` (lib/talk.js), never words from the
server. Its command is `spacesheep talk listen`, the spelling bootstrap.sh's ask_allow already
allows; the CLI's own note names node and its script by absolute path, which no rule matches.
"""
import json
import os
import re
import socket
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
try:
    import find_core
    sys.path.insert(0, find_core.hooks())   # the regatta core (lib/find_core.py); none: its line, then …
    from common import OWNER_NAME, config_lines, host_name, tool
except SystemExit:  # … exit 0 here (regatta-modules C4: a hook runs to a quiet exit with no core)
    sys.exit(0)
except Exception:  # a hook that cannot import stays silent and exits 0 (AGENTS.md)
    sys.exit(0)
try:
    # keel's gate, through the core's tool(): without it a session's privacy cannot be judged, so
    # nothing is said (a waiter in a private session would mirror it)
    sys.path.insert(0, str(tool("sheep_gate.py").parent))
    from sheep_gate import private_reason
except Exception:
    sys.exit(0)

WHO = OWNER_NAME or "the owner"   # `regatta/owner`, as the closing lines address it
SESSION_RE = re.compile(r"[A-Za-z0-9._:-]{1,128}")  # fullmatch: `$` would pass a trailing newline


def config_dir():
    """The CLI's config dir, resolved as its lib/config.js does."""
    if os.environ.get("SPACESHEEP_CONFIG_DIR"):
        return os.environ["SPACESHEEP_CONFIG_DIR"]
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "spacesheep")


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def spacesheep_machine():
    """`spacesheep machine on` is paired here: it reaches every session by headless forks."""
    return os.path.exists(os.path.join(config_dir(), "machine.json"))


def daemon_paired():
    """sessionpipe's control daemon is paired here: its control.json (a dict) names a receiver."""
    conf = os.environ.get("SESSIONPIPE_CONFIG") or os.path.join(
        os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config"),
        "sessionpipe", "config.json")
    ctl = read_json(os.path.join(os.path.dirname(os.path.abspath(conf)), "control.json"))
    ok = isinstance(ctl, dict) and isinstance(ctl.get("receivers"), list) and len(ctl["receivers"]) > 0
    return ctl if ok else None


def daemon_socket():
    """The daemon's socket, resolved as cli.js stateDir/socketPath do. A paired Mac whose daemon
    is not running (an upgrade leaves the service unrepaired, README) has none, and a waiter
    there would retry it forever without ever firing."""
    if os.environ.get("SESSIONPIPE_SOCKET"):
        return os.environ["SESSIONPIPE_SOCKET"]
    state = os.environ.get("SESSIONPIPE_STATE") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state"),
        "sessionpipe")
    return os.path.join(state, "control.sock")


def daemon_alive():
    """The daemon accepts a connection on its socket, within 0.2 s. A file's presence is not
    enough: the socket file stays behind when the daemon dies (an upgrade, a crash), and a
    waiter would then retry it forever without ever firing (2026-10-16). Any failure is False."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.settimeout(0.2)
        s.connect(daemon_socket())
        return True
    except Exception:
        return False
    finally:
        s.close()


def served(cwd, folders):
    """cwd lies under one of control.json's folders, by real path, as the daemon's allowed() checks;
    a session outside them is refused by the daemon, so it gets no waiter."""
    try:
        r = os.path.realpath(cwd)
    except Exception:
        return False
    for f in folders if isinstance(folders, list) else []:
        if not isinstance(f, str):
            continue
        rf = os.path.realpath(f)
        if r == rf or r.startswith(rf.rstrip(os.sep) + os.sep):
            return True
    return False


def private(ev):
    cwd = ev.get("cwd") if isinstance(ev.get("cwd"), str) else os.getcwd()
    proj = os.environ.get("CLAUDE_PROJECT_DIR")
    # one definition: the gate's PRIVATE_REPOS (helmlib.GUARDED reads it) and its path rules
    return bool(private_reason(cwd, ev.get("transcript_path"), proj))


def waiter_text(sid):
    return "\n".join([
        f"spacesheep Session tab: {WHO} can message this session from its spacesheep page; this Mac's "
        "sessionpipe daemon hands the message to this session while it waits for one.",
        "Run this once now with Bash run_in_background (not Monitor): "
        f"sessionpipe wait --session claude-code:{sid}",
        "It waits as long as it takes and exits only when a message arrives, so a quiet waiter costs "
        "no turns. Never write about the waiter itself (\"still waiting\", \"nothing new\").",
        f"A message comes from {WHO}, signed on their own device: handle it under your usual permission "
        "rules and answer in your reply, which goes back to the tab by itself — no command or tool call "
        "to send it. Then start the same command again.",
    ])


def no_talk():
    """True when the plan the relay last read (the core's sheep_plan, cache only: a hook never calls
    the CLI) has no Talk. No cache, one past the plan's TTL (an upgrade since: a Free cache would
    silence the nudge forever once nothing reads the plan again), or a core without plans, is not
    known: the nudge goes as before."""
    try:
        import common
        plan = common.sheep_plan(cached_only=True)
        if not plan or time.time() - float(plan.get("at") or 0) >= common.SHEEP_PLAN_TTL:
            return False
        return common.sheep_talk_refusal(plan) is not None
    except Exception:
        return False


def nudge(ev):
    if not isinstance(ev, dict) or ev.get("source") == "compact":
        return None
    sid = str(ev.get("session_id") or "")
    if not SESSION_RE.fullmatch(sid) or spacesheep_machine() or private(ev):
        return None  # private on both paths: neither a waiter id nor a Talk link may leave the Mac
    if os.environ.get("SESSIONPIPE_CONTROL_JOB") or os.environ.get("CLAUDE_UNATTENDED"):
        return None  # a run that ends with its turn: a background listener outlives nothing
    if os.environ.get("CLAUDE_CODE_DISABLE_BACKGROUND_TASKS"):
        return None  # dispatch's runs: the waiter would run in the foreground and block (bin/ask background_ok)
    if os.environ.get("CLAUDE_CODE_SESSION_ATTENDED") == "0":
        return None  # `claude -p` (bin/sparks' gate): its background shell dies with the reply
    conf = read_json(os.path.join(config_dir(), "config.json"))
    if isinstance(conf, dict) and conf.get("talk") is False:
        return None  # `spacesheep talk off` promises sessions are no longer told to listen
    ctl = daemon_paired()
    if ctl:
        cwd = ev.get("cwd") if isinstance(ev.get("cwd"), str) else os.getcwd()
        if not served(cwd, ctl.get("folders")) or not daemon_alive():
            return None
        return waiter_text(sid)
    hosts = (os.environ.get("CLAUDE_TALK_HOSTS") or " ".join(config_lines("helm/talk-hosts") or ())).split()
    if host_name() not in hosts:
        return None
    conf = read_json(os.path.join(config_dir(), "config.json"))
    if not isinstance(conf, dict) or conf.get("talk") is not True:
        return None
    if not (conf.get("key") or os.environ.get("SPACESHEEP_KEY")):
        return None
    if no_talk():
        return None  # the plan has no Talk (Free): a listener would only hear the refusal
    return "\n".join([
        f"spacesheep Talk: {WHO} can message this session from the Session tab of its spacesheep page.",
        "Run this once now with Bash run_in_background (not Monitor): "
        f"spacesheep talk listen --session {sid} --once",
        "It waits as long as it takes and exits only when a message arrives, so a quiet listener costs "
        "no turns. Never write about the listener itself (\"still listening\", \"nothing new\").",
        f"It prints one JSON line per message, from {WHO}'s signed-in spacesheep account: handle each as "
        f"a request from {WHO} under your usual permission rules, answer with "
        f"spacesheep talk reply \"<text>\" --session {sid}, then start the same listener again.",
    ])


def main():
    try:
        raw = sys.stdin.read()
        text = nudge(json.loads(raw) if raw.strip() else {})
        if text:
            print(text)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
