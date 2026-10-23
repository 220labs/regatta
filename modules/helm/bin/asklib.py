"""The relay seam (S1) of session-asks: one sender, two callers (bin/ask, bin/plan; memo notify, E15,
is to be the third). docs/session-asks-2026-10-09.md R4.

Every backend has the same four functions — available(ctx), send(ctx, text), receive(ctx),
describe() — so an internal replacement is one more class, never a rewrite. Which backends are
tried, in which order, is `ask.relay` in settings/surfaces.json. Stdlib only, Python 3.9, nothing
of Claude's imported (R8): CLAUDE_CODE_SESSION_ID is read only as one of the ids accepted.

The context (`ctx`) a backend reads, all optional:
    manager          the manager's session id (DISPATCH_SKIPPER, or the older DISPATCH_MANAGER)
    manager_host     the Mac the manager runs on (DISPATCH_SKIPPER_HOST, or DISPATCH_MANAGER_HOST)
    manager_account  the manager's login: its config dir, or a registry label ('' = ~/.claude)
    account          this session's login, in either form — account_home() makes both one
    space            the manager's plan page (uuid or link; DISPATCH_PLAN_SPACE) — the Talk address
    session          this session's id
    plan             the ship id (DISPATCH_SHIP, or DISPATCH_PLAN)
    standing         set by with_standing(): the manager is the Mac's standing one (stray-manager M5)
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _common():
    """The regatta core's common.py through lib/find_core.py, loaded on first use; None when there
    is no core. Never exits: keel's Stop lint loads this file alone (G24), and a missing core must
    cost that caller one check, not the hook."""
    if "common" in sys.modules:
        return sys.modules["common"]
    lib = str(HERE.parent / "lib")
    if lib not in sys.path:
        sys.path.insert(0, lib)
    try:
        import find_core
        hooks = find_core.hooks()
    except (ImportError, SystemExit):
        return None
    if hooks not in sys.path:
        sys.path.insert(0, hooks)
    try:
        import common
    except Exception:
        return None
    return common


def _peer(name):
    """A peer's file through the core's tool() (keel's sheep, plumb's attention.py), or None."""
    c = _common()
    return c.tool(name) if c else None


# P2 (2026-10-10): Python's default agent gets Cloudflare's 403 code 1010 on the Talk service's
# hosts; a curl agent passes. Every call here sets it.
UA = "curl/8.7.1 (bin/ask)"
TIMEOUT = 20


def talk_url():
    """The Talk service's base URL: $SPACESHEEP_URL, else the config dir's `helm/talk-url` (the
    overlay writes it); "" when neither names one, and the talk backend says so."""
    v = os.environ.get("SPACESHEEP_URL")
    if v:
        return v.rstrip("/")
    c = _common()
    return (c.config_line("helm/talk-url") if c else "").rstrip("/")


def owner():
    """The owner's name, lower-case, as the core reads it (`regatta/owner`); `owner` without one."""
    c = _common()
    return ((getattr(c, "OWNER_NAME", "") if c else "") or "owner").lower()


def _home():
    return Path(os.environ.get("HOME") or Path.home())


def sessions_dir():
    """The shared registry: every login dir's sessions/ links to ~/.claude/sessions."""
    return Path(os.environ.get("ASK_SESSIONS_DIR") or _home() / ".claude" / "sessions")


def queue_dir():
    return Path(os.environ.get("ASK_QUEUE_DIR") or _home() / "Library/Logs/claude-weekly/asks")


def sheep_cli():
    """The Talk service's CLI, `spacesheep` (memo's sheep_bin order): $MEMO_SHEEP_BIN, PATH, ~/.local/bin, Homebrew."""
    import shutil
    if "MEMO_SHEEP_BIN" in os.environ:
        c = os.environ["MEMO_SHEEP_BIN"]
        return c if c and os.access(c, os.X_OK) else None
    for c in (shutil.which("spacesheep"), str(_home() / ".local/bin/spacesheep"), "/opt/homebrew/bin/spacesheep"):
        if c and os.access(c, os.X_OK):
            return c
    return None


def sheep_key():
    """SPACESHEEP_KEY: the environment, else the overlay's .env through bin/sheep's reader, else the
    CLI's stored login — bin/keel's sheep_key order. Never printed."""
    if os.environ.get("SPACESHEEP_KEY"):
        return os.environ["SPACESHEEP_KEY"].strip().strip("'\"")
    if os.environ.get("ASK_NO_KEY_FILES"):  # tests
        return None
    try:
        from importlib.machinery import SourceFileLoader
        v = SourceFileLoader("sheep_tool", str(_peer("sheep"))).load_module().env_value("SPACESHEEP_KEY")
        if v:
            return v.strip().strip("'\"")
    except Exception:  # Drive offline, no Full Disk Access, no bin/sheep (a cloud VM)
        pass
    cfg = Path(os.environ.get("SPACESHEEP_CONFIG_DIR") or Path(os.environ.get("XDG_CONFIG_HOME") or _home() / ".config") / "spacesheep") / "config.json"
    try:
        return (json.loads(cfg.read_text()).get("key") or "").strip() or None
    except (OSError, ValueError):
        return None


def space_id(space):
    """A page link or a uuid → the uuid (the last path part of /s/<uuid>), else the text as given."""
    s = (space or "").strip().rstrip("/")
    if "/s/" in s:
        return s.split("/s/", 1)[1].split("/", 1)[0]
    return s


def registry(session_id):
    """The registry record of a session id, or None. Several files may name one id (a session
    picked up again): the newest wins."""
    best = None
    try:
        files = list(sessions_dir().glob("*.json"))
    except OSError:
        return None
    for f in files:
        try:
            d = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        if d.get("sessionId") == session_id and (best is None or d.get("updatedAt", 0) > best.get("updatedAt", 0)):
            best = d
    return best


def pid_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError, TypeError):
        return False


def this_host():
    """The Mac this runs on, as dispatch names it (laptop, buildbox): PLAN_HOST, DISPATCH_HOST, else
    the LocalHostName."""
    h = os.environ.get("PLAN_HOST") or os.environ.get("DISPATCH_HOST")
    if h:
        return h
    try:
        r = subprocess.run(["/usr/sbin/scutil", "--get", "LocalHostName"], capture_output=True, text=True, timeout=5)
        return r.stdout.strip().lower() or None
    except (OSError, subprocess.TimeoutExpired):
        return None


def manager_state(ctx):
    """('live' | 'gone' | 'remote', why) for ctx['manager'] (finding 4 of the launch review,
    2026-10-10): a record in this Mac's registry with a live pid is live, with a dead pid gone; no
    record on the manager's own Mac is gone too — a leftover plan dir is not a manager. A manager
    on another Mac (DISPATCH_MANAGER_HOST names it) has no registry here to read: 'remote', and
    only Talk can reach it. No host recorded and no record here reads as gone."""
    m = ctx.get("manager")
    if not m:
        return "gone", "no manager (DISPATCH_SKIPPER unset)"
    rec = registry(m)
    if rec:
        if pid_alive(rec.get("pid")):
            return "live", "pid %s" % rec.get("pid")
        return "gone", "the manager's session has ended (pid %s is gone)" % rec.get("pid")
    mh, here = ctx.get("manager_host"), this_host()
    if mh and here and mh != here:
        return "remote", "on %s: its registry is not readable here" % mh
    return "gone", "the manager's session has ended (no record in %s)" % sessions_dir()


def manager_dir():
    return Path(os.environ.get("ASK_MANAGER_DIR") or _home() / "Library/Logs/claude-weekly/manager")


def standing_manager(host=None):
    """This Mac's standing manager as the ctx fields relay() needs, or None (stray-manager M5, B1).
    The record is `<manager_dir>/<host>.json`, `{session, name, plan, space, account, host, started,
    pid}`, which bin/manager's runner writes (B2, waiting for the two-week count, D1-A); it is live
    when its pid is alive and the registry's record of its session has a live pid too — a crashed
    manager leaves a record that reads as none. No record, the case until B2: None, and every
    caller does what it did before the seam."""
    h = host or this_host()
    if not h:
        return None
    try:
        rec = json.loads((manager_dir() / ("%s.json" % h)).read_text())
    except (OSError, ValueError):
        return None
    sid = rec.get("session") if isinstance(rec, dict) else None
    if not sid or not pid_alive(rec.get("pid")):
        return None
    reg = registry(sid)
    if not reg or not pid_alive(reg.get("pid")):
        return None
    return {"manager": sid, "manager_host": h, "space": rec.get("space"), "plan": rec.get("plan"),
            "manager_account": rec.get("account") or "", "manager_name": rec.get("name") or "manager · %s" % h,
            "standing": True}


def resolve(ctx):
    """(ctx, (state, why)): where a relay from this run goes, decided once — ctx with the Mac's
    standing manager in place of a manager that is unset or gone (M1: a run with no live manager of
    its own is the standing manager's), and manager_state of the result. A remote or live manager
    stays. The run's own plan, if any, keeps its events; the Talk address is the standing manager's
    page. bin/ask relay resolves once and hands both to relay(), so the registry is read once a
    manager and the host once a run (review gate, 2026-10-16: it was twice and up to four times)."""
    if ctx.get("standing"):
        return ctx, ("live", "this Mac's standing manager")
    st = manager_state(ctx) if ctx.get("manager") else ("gone", "no manager (DISPATCH_SKIPPER unset)")
    if st[0] != "gone":
        return ctx, st
    sm = standing_manager()  # live by its own test: its pid and its session's registry pid
    if not sm:
        return ctx, st
    out = dict(ctx)
    out.update({k: v for k, v in sm.items() if k != "plan"})
    out["plan"] = ctx.get("plan") or sm.get("plan")
    return out, ("live", "this Mac's standing manager")


def with_standing(ctx):
    """resolve()'s ctx alone."""
    return resolve(ctx)[0]


# Who answered a relayed D-item, from bin/ask answer's line `Relayed from <who> (<source>, <date>):
# <text>` (bin/ask RELAYED_ANSWER). One predicate for bin/keel (taken_answer: an answer the owner
# never gave is `taken`, which rule D never launches) and bin/ask (log_relay: escalated vs answered),
# so the two never disagree (review gate, 2026-10-16: memo's own pattern failed open on a `who`
# holding a parenthesis, `--from "manager (buildbox)"`, and ask tested for the name anywhere in the
# source). The owner's only when the source names the owner (`regatta/owner`) AND one of the routes
# the owner's own word arrives on — the form, GitHub, chat, the Session tab signed on the owner's
# device; anything else (`manager`, `yes item`, the bare name, an unsigned tab line, a line this
# cannot parse) is somebody else's, so it fails closed.
OWNER_ROUTES = r"(?:'s|\u2019s|,)?\s+(?:form|github|chat|session tab(?:,\s*|\s+)\(?signed\)?)$"
RELAYED_HEAD_RE = re.compile(r"^\s*Relayed from (.*?), \d{4}-\d{2}-\d{2}\): ")


def owner_source(source):
    """True when a relayed answer's --source is one of the owner's routes (OWNER_ROUTES after the
    owner's name)."""
    return bool(re.match("^" + re.escape(owner()) + OWNER_ROUTES, " ".join(str(source or "").split()), re.I))


def relayed_by_owner(line):
    """None when line is not a `Relayed from` answer; else True when its source is the owner's.
    `who` may hold a parenthesis of its own (`manager (buildbox)`), the source too (`<owner>,
    Session tab (signed)`), so the text after every " (" of the head is tried as the source, and only
    one that runs whole to the date counts; a line with no date is not the owner's."""
    if not re.match(r"^\s*Relayed from ", line or ""):
        return None
    m = RELAYED_HEAD_RE.match(line)
    if not m:
        return False
    head, i = m.group(1), 0
    while True:
        i = head.find(" (", i)
        if i < 0:
            return False
        if owner_source(head[i + 2:]):
            return True
        i += 2


def __getattr__(name):
    """The predicate's name before the scrub (`relayed_by_<owner>`) for a caller that still uses it:
    keel's main called it so until its own scrub (which reads relayed_by_owner first). Any other
    `relayed_by_*` is the same test; anything else is the usual AttributeError."""
    if name.startswith("relayed_by_"):
        return relayed_by_owner
    raise AttributeError("module %r has no attribute %r" % (__name__, name))


def account_home(value):
    """One vocabulary for a login (finding 6): dispatch wrote the manager's from `account which`
    (nothing for the default dir) and the run's from `account pick` (a label, `claude-a`), so one
    account looked like two. A config dir or a label → the config dir's real path ('' → ~/.claude;
    a label through the account registry, ACCOUNTS_FILE in tests). A label the registry does not
    know is compared as written."""
    v = (value or "").strip()
    if not v:
        p = _home() / ".claude"
    elif "/" in v or v.startswith("~"):
        p = Path(os.path.expanduser(v))
    else:
        p = None
        try:
            # lighthouse's registry, by the config dir's key (C3), as bin/account reads it
            cfg = Path(os.environ.get("REGATTA_CONFIG") or _home() / ".config" / "regatta").expanduser()
            reg = json.loads(Path(os.environ.get("ACCOUNTS_FILE") or cfg / "lighthouse" / "accounts.json").read_text())
            common = _common()  # a `via: orca` row's dir is this Mac's read-back (docs/orca-accounts-2026-10-16.md)
            for a in common.account_rows(reg.get("accounts"), _home()):  # Orca's logins are rows too
                if a.get("label") == v and (a.get("provider") or "claude") == "claude":
                    p = common.account_home(a, _home())
                    break
        except (OSError, ValueError, AttributeError, ImportError):
            pass
        if p is None:
            return v
    try:
        return str(p.resolve())
    except OSError:
        return str(p)


def own_account():
    """This process's login, as account_home() spells it: $ASK_ACCOUNT (dispatch's), else the
    config dir it runs under."""
    return account_home(os.environ.get("ASK_ACCOUNT") or os.environ.get("CLAUDE_CONFIG_DIR") or "")


def same_named(rec):
    """Other live records carrying the same name (K2: `coding-50` twice): the cwd tells them apart."""
    if not rec or not rec.get("name"):
        return []
    out = []
    for f in sessions_dir().glob("*.json"):
        try:
            d = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        if d.get("name") == rec["name"] and d.get("sessionId") != rec.get("sessionId") and pid_alive(d.get("pid")):
            out.append(d)
    return out


# ---------------------------------------------------------------------------- backends

class Talk:
    """The Talk service (`helm/talk-url`): `POST /api/talk/send` as the owner, to a session that published `space`.
    The target is woken by its own background `spacesheep talk listen --once` (R4)."""
    name = "talk"

    def available(self, ctx):
        if not ctx.get("space") or not ctx.get("manager"):
            return False, "no plan space or manager id to address"
        if not sheep_key():
            return False, "no SPACESHEEP_KEY (environment, the overlay's .env or the CLI's login)"
        if not talk_url():
            return False, "no Talk service named (SPACESHEEP_URL, or the config dir's helm/talk-url)"
        return True, "key and address"

    def request(self, ctx, text):
        body = {"space": space_id(ctx["space"]), "session_id": ctx["manager"], "text": text}
        return talk_url() + "/api/talk/send", body

    def send(self, ctx, text):
        url, body = self.request(ctx, text)
        req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={
            "Authorization": "Bearer " + (sheep_key() or ""), "Content-Type": "application/json", "User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                res = json.loads(r.read().decode() or "{}")
            return ("sent", "talk: %s" % (res.get("id") or "ok")) if res.get("ok", True) else ("unreachable", "talk: %s" % res)
        except urllib.error.HTTPError as e:
            try:
                err = json.loads(e.read().decode() or "{}")
            except ValueError:
                err = {}
            code = err.get("code") or e.code
            # K10: Talk switched off says so; the next backend takes the message
            return "unreachable", "talk: %s %s" % (code, err.get("error") or "")
        except (urllib.error.URLError, OSError, ValueError) as e:
            return "unreachable", "talk: %s" % e

    def receive(self, ctx):
        """The messages for ctx['session'] (blocks until one arrives): the CLI's `talk listen --once`.
        A list of dicts, each with a str `text`; [{"stopped": True}] when the link ended with no
        message; None when there is no CLI or the listen failed.

        The wire format is unverified until B0a (section 8): one JSON object per stdout line, its
        text in `text` or `message`, is read off the plugin's /talk skill, not a recorded exchange.
        So every JSON line of a body is a message — a listen that returns two must not drop the
        second — and a line whose JSON is not an object, or whose text is not a string, is coerced
        rather than trusted."""
        cli = sheep_cli()
        if not cli:
            return None
        sid = ctx.get("session") or os.environ.get("CLAUDE_CODE_SESSION_ID")
        r = subprocess.run([cli, "talk", "listen", "--once"] + (["--session", sid] if sid else []),
                           capture_output=True, text=True)
        out = []
        for line in r.stdout.splitlines():
            line = line.strip()
            if not line.startswith(("{", "[", '"')):
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if not isinstance(d, dict):
                d = {"text": d}
            t = d.get("text") if d.get("text") is not None else d.get("message")
            d["text"] = t if isinstance(t, str) else ("" if t is None else json.dumps(t, ensure_ascii=False))
            out.append(d)
        if out:
            return out
        return [{"stopped": True, "raw": r.stdout[-500:]}] if r.returncode == 0 else None

    def curl(self, ctx, text):
        """The exact POST for a brief (a cloud run has no bin/ask): the key stays a variable, since a
        brief is committed and logged."""
        url, body = self.request(ctx, text)
        return ("curl -sS -X POST %s -H \"Authorization: Bearer $SPACESHEEP_KEY\" -H 'Content-Type: application/json' "
                "-A 'curl/8.7.1' --data %s" % (url, _shq(json.dumps(body, ensure_ascii=False))))

    def describe(self):
        return "talk — the Talk service's POST /api/talk/send to the manager's plan page; any Mac, login or harness"


class SendMessage:
    """Claude Code's own SendMessage — a model tool, so this backend resolves the road and prints the
    call for the session to make: same account and a live record with a socket (R4)."""
    name = "sendmessage"

    def available(self, ctx):
        m = ctx.get("manager")
        if not m:
            return False, "no manager id"
        rec = registry(m)
        if not rec:
            return False, "the manager has no record in %s (another Mac, or it ended)" % sessions_dir()
        if not pid_alive(rec.get("pid")):
            return False, "the manager's process %s is gone" % rec.get("pid")
        if not rec.get("messagingSocketPath"):
            return False, "the manager binds no inbox (a -p session)"
        theirs, mine = account_home(ctx.get("manager_account")), account_home(ctx.get("account"))
        if theirs != mine:
            return False, "a different login (%s vs %s): no road across accounts" % (theirs, mine)
        return True, rec.get("status") or "live"

    def send(self, ctx, text):
        rec = registry(ctx["manager"]) or {}
        twins = same_named(rec)
        name = rec.get("name") or ctx["manager"][:8]
        hint = " (cwd %s — %d other live session(s) share the name)" % (rec.get("cwd"), len(twins)) if twins else ""
        verdict = "busy" if rec.get("status") == "busy" else "live"
        return verdict, "sendmessage: call SendMessage to %s%s with the text above" % (name, hint)

    def receive(self, ctx):
        return None  # the inbox is the session's own; nothing for a script to read

    def describe(self):
        return "sendmessage — Claude Code's SendMessage, same account and a live socket; nothing leaves the Mac"


class File:
    """A JSON line in ~/Library/Logs/claude-weekly/asks/<manager>.jsonl, printed into the manager's
    context by its UserPromptSubmit hook at its next prompt. Nothing wakes it."""
    name = "file"

    def path(self, ctx):
        return queue_dir() / ("%s.jsonl" % ctx["manager"])

    def available(self, ctx):
        """A live manager on this Mac: its registry record with a live pid (finding 4). A plan dir
        left behind by a session that ended is not one — the queue would wait for a prompt that
        never comes."""
        if not ctx.get("manager"):
            return False, "no manager id"
        rec = registry(ctx["manager"])
        if rec is None:
            return False, "the manager is not on this Mac"
        if not pid_alive(rec.get("pid")):
            return False, "the manager's process %s is gone" % rec.get("pid")
        return True, "this Mac, pid %s" % rec.get("pid")

    def send(self, ctx, text):
        p = self.path(ctx)
        p.parent.mkdir(parents=True, exist_ok=True)
        line = json.dumps({"t": int(time.time()), "from": ctx.get("session"), "text": text}, ensure_ascii=False)
        fd = os.open(str(p), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        try:
            os.write(fd, (line + "\n").encode())
        finally:
            os.close(fd)
        return "queued", "file: %s" % p

    def receive(self, ctx):
        p = self.path(ctx)
        try:
            lines = p.read_text().splitlines()
        except OSError:
            return []
        return [json.loads(x) for x in lines if x.strip().startswith("{")]

    def describe(self):
        return "file — a line the manager's next prompt prints; one Mac, always deliverable"


BACKENDS = {b.name: b for b in (Talk(), SendMessage(), File())}


def relay(ctx, text, order, dry=False, resolved=None):
    """Try each backend of `order` until one delivers. Returns (backend, verdict, detail, tried):
    verdict is sent | live | busy | queued | none | unreachable; `tried` lists each skip with why.
    A run whose manager is unset or gone relays to the Mac's standing manager when one runs (M5).
    `resolved` is resolve(ctx) when the caller has it already (bin/ask relay); else it runs here."""
    tried = []
    ctx, (alive, why) = resolved or resolve(ctx)
    if not ctx.get("manager"):
        return None, "none", "no live manager (DISPATCH_SKIPPER unset)", tried
    # finding 4: a dead or gone manager is `none` — the run takes the WAITING path — whatever
    # backend would carry the message (a Talk send to an ended session goes to a thread nobody
    # reads, and the file queue in a prompt that never comes). A remote one: Talk alone.
    if alive == "gone":
        return None, "none", "no live manager: %s" % why, tried
    for name in order:
        b = BACKENDS.get(name)
        if not b:
            tried.append((name, "unknown backend"))
            continue
        ok, why = b.available(ctx)
        if not ok:
            tried.append((name, why))
            continue
        if dry:
            return name, "dry-run", why, tried
        verdict, detail = b.send(ctx, text)
        if verdict == "unreachable":
            tried.append((name, detail))
            continue
        return name, verdict, detail, tried
    return None, "unreachable", "every backend refused", tried


def _shq(s):
    return "'" + s.replace("'", "'\"'\"'") + "'"


# ---------------------------------------------------------------------------- the interruption log

def log_relay(kind, detail, session=None, cwd=None):
    """One interruption row per settled relay, in the class hooks/attention.py defines (DESIGN.md
    number 6 of the interruptions design, owned by session coding-d1): event "Relay",
    type "answered" (the manager settled it without the owner — an interruption avoided) or "escalated"
    (it went on to the owner). bin/interruptions counts relay apart from the total, since an escalation
    reaches the owner again as an ask or a handoff; a managerless WAITING line is already a handoff row.
    attention.record() when that module is here; until it launches, the same row by hand, to the same
    file, so the shape stays one (coding-d1, 2026-10-10: a new field is agreed with it first).
    Never raises."""
    import datetime as _dt
    import sys as _sys
    try:
        at = _peer("attention.py")   # plumb's (G26): absent → the row by hand, below
        if not at:
            raise ImportError("attention.py not installed (plumb)")
        if str(at.parent) not in _sys.path:
            _sys.path.insert(0, str(at.parent))
        import attention  # noqa: F401
        if kind in getattr(attention, "RELAY_KINDS", (kind,)):
            return attention.record("Relay", kind, detail=detail, session=session, cwd=cwd)
    except Exception:
        pass
    try:
        c = _common()   # the core's log dir (`regatta/log-dir`), as plumb's attention.py writes there
        d = Path(os.environ.get("ATTENTION_LOG_DIR") or (c.LOG_DIR if c else _home() / ".local" / "state" / "regatta") / "attention")
        now = _dt.datetime.now().astimezone()
        row = {"ts": now.isoformat(timespec="seconds"), "event": "Relay", "type": kind, "tool": "",
               "detail": (detail or "")[:300], "session": (session or "")[:8], "cwd": cwd or os.getcwd(),
               "login": Path(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude").name}
        d.mkdir(parents=True, exist_ok=True)
        with open(d / ("%s.jsonl" % now.strftime("%Y-%m")), "a") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
        return True
    except Exception:
        return False


# ---------------------------------------------------------------------------- message lines

PREFIXES = ("ASK", "ANSWER", "REPORT")


def classify(text):
    """(kind, rest): ASK | ANSWER | REPORT from a session; CHAT for an unprefixed line — unverified:
    the account owner's page, or any session holding the key, sends one (K13). Shown to the manager
    as that, never taken as an answer to a D-item, never as the owner's word."""
    t = (text or "").strip()
    for p in PREFIXES:
        if t.startswith(p + " "):
            return p, t[len(p) + 1:]
    return "CHAT", t
