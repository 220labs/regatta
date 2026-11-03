"""surfaces.json — the seams of session-asks (docs/session-asks-2026-10-09.md section 2).

Shared by bin/ask and bin/helm, the way settings/models.json is read by bin/gate: which relay,
render, live and notify backend each seam takes, in order. Stdlib only, Python 3.9, nothing of
Claude's imported — the protocol is harness-neutral (R8). SURFACES_FILE points a test elsewhere.
"""
import json
import os
from pathlib import Path

# The file is the owner's (the overlay's settings/surfaces.json on the owner's Macs), linked into
# the regatta config dir as helm/surfaces.json (the design's C3); its shape is surfaces.schema.json
# beside this module's bin/, and a missing file or row reads as DEFAULTS.
CONFIG = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
FILE = Path(os.environ.get("SURFACES_FILE") or CONFIG / "helm" / "surfaces.json")
SCHEMA = Path(__file__).resolve().parent.parent / "surfaces.schema.json"

# What a missing file or row means: the design's defaults, so a fresh checkout behaves as documented.
# The `helm` seam was `plan` before rename S5 (helm-vocabulary H1): a file that still says `plan` is
# read as helm's row, `helm` winning key by key where both are set; a write goes under `helm`.
OLD_SEAMS = {"plan": "helm"}


def _laptop():
    """The host typing every cross-machine leg, as the core names it (REGATTA_LAPTOP, else the
    config dir's `regatta/laptop`, else `laptop`): read here without the core, which this file never
    loads (the deny hook imports it)."""
    if os.environ.get("REGATTA_LAPTOP"):
        return os.environ["REGATTA_LAPTOP"]
    try:
        lines = [l.strip() for l in (CONFIG / "regatta" / "laptop").read_text(encoding="utf-8-sig").splitlines()]
    except (OSError, UnicodeDecodeError):
        lines = []
    return next((l for l in lines if l), "laptop")


DEFAULTS = {
    "ask": {"relay": ["talk", "sendmessage", "file"], "listen": "talk", "parked": True},
    "helm": {"render": ["local", "sheep", "artifact"], "live": "stream", "live_fallback": "redeploy",
             "state": "state.json"},
    "notify": {_laptop(): ["banner"], "cloud": []},
    # wharf-runs' bin/hail reads this row itself (its roads(), the same file and default): the roads a
    # hail may take, in order (the charterer design's S2); keep ROADS there and this list equal
    "hail": {"roads": ["socket", "codex", "orca", "talk", "mailbox", "file"]},
}
KNOWN = {
    "ask.relay": {"talk", "sendmessage", "file"},
    "ask.listen": {"talk", "sendmessage", "none"},
    "helm.render": {"local", "sheep", "artifact"},
    "helm.live": {"stream", "redeploy", "records", "local-sse"},
    "helm.live_fallback": {"redeploy", "none"},
    # github-issue (skipper-resilience S8): the stall road's — an issue in the config key helm/logbook-repo
    # mentioning helm/mention, opened and closed by the tick's escalate(); it carries stalls only (bin/ask's notice())
    "notify.*": {"banner", "github-issue", "telegram"},
    "hail.roads": {"socket", "codex", "orca", "talk", "mailbox", "file"},
}

# ---------------------------------------------------------------------------- the notify ladder (charterer S3)
#
# The `notify` seam holds two shapes side by side (docs/charterer-2026-11-01.md, "Channels and the ladder"):
#     notify.<kind>   a ladder per kind of message — `update`, `question`, `stall` — each a list of rungs
#                     {"via": <channel>, "after": "10m", "when": "present"}: a rung fires once per message, at
#                     `after` from the message's first moment, while it is unanswered; `when: present` holds it
#                     until the owner is at the Mac (read by S5; until then the rung holds)
#     notify.quiet    {"hours": "22:00-07:00", "except": [<kind>…], "tz": "America/Los_Angeles"}: every
#                     phone-reaching rung of a kind not excepted holds in those hours (in `tz` when it names one,
#                     else the host's local time) and fires when they end; the stall road's issue comments too
#     notify.cap      {"per_hour": 6}: phone-reaching pushes across every channel, the newest message first
#     notify.<host>   the old row, a list of backends per host (KNOWN's notify.*): an ask's banner reads it as
#                     before, and a kind with no ladder of its own reads it as one rung, HOST_ROW: the stall
#                     road's issue machine sends it by bin/ask's notice(), which walks the row's backends in
#                     one call as before the ladder — so a file the owner never edits behaves as before
# A key that is a ladder kind, `quiet` or `cap` is never a host's name. Each kind falls back on its own: a file
# with a `stall` ladder and no `question` one still reads a question's rungs from the host row.
LADDER_KINDS = ("update", "question", "stall")
LADDER_KEYS = LADDER_KINDS + ("quiet", "cap")
# every channel a rung may name; a road is bin/ask's push(): charterer (S4), vscode-question and claude-app (S5),
# telegram (no sender yet) and spacesheep-app (reserved until the app exists) are accepted with no road, and
# orca-app's probe found no notifying verb (Orca 1.4.245, 2026-11-01): each says why, once per message
CHANNELS = {"charterer", "vscode-question", "claude-app", "orca-app", "github-issue", "telegram", "banner", "spacesheep-app"}
# the channels that reach the owner's phone: what quiet hours hold and the cap counts (a banner is the Mac's,
# the charterer and a VS Code question are a session's)
PHONE = {"claude-app", "orca-app", "github-issue", "telegram", "spacesheep-app"}
WHEN = {"present"}
HOST_ROW = "host-row"   # the rung a host row reads as: no channel a rung may name, so the owner never writes it
LEGACY_AFTER = 10 * 60   # the host row's one wait when no caller names it (stalls_tick passes its ESCALATE_AFTER)
MAX_AFTER = 366 * 86400  # an `after` past a year is no duration: "never" is no rung, and a clock past it will not print


def duration(v):
    """Seconds from `after`: an int or float of seconds, or "90s", "5m", "1h", "1h30m", at most MAX_AFTER;
    None when it does not read."""
    import re
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v) if 0 <= v <= MAX_AFTER else None   # NaN fails both sides
    m = re.fullmatch(r"\s*(?:(\d+)h)?\s*(?:(\d+)m)?\s*(?:(\d+)s)?\s*", str(v or ""))
    if not m or not any(m.groups()):
        return None
    h, mi, s = (int(x or 0) for x in m.groups())
    secs = h * 3600 + mi * 60 + s
    return float(secs) if secs <= MAX_AFTER else None


def hours(v):
    """(start, end) in minutes of the day from "22:00-07:00"; None when it does not read."""
    import re
    m = re.fullmatch(r"\s*(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\s*", str(v or ""))
    if not m:
        return None
    a, b, c, d = (int(x) for x in m.groups())
    if a > 23 or b > 59 or c > 23 or d > 59:
        return None
    return a * 60 + b, c * 60 + d


_READ = object()   # load()'s and the ladder readers' default: read the file now (else: what a snapshot() read)


def snapshot(path=None):
    """The file's text, read once for a whole pass, so the ladders, quiet hours, cap and notify_unreadable
    all judge one version of it: None when there is no file, the error itself when it will not read (a
    permission, a folder, no UTF-8), which load() reads as no file and notify_unreadable() names."""
    p = Path(path) if path else FILE
    try:
        return p.read_text()
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as e:   # ValueError: a file that is no UTF-8 (UnicodeDecodeError)
        return e


def _word(x, known):
    """X is one of KNOWN's words: a string first, so a list or a dict in the file is a problem, never a TypeError."""
    return isinstance(x, str) and x in known


def host_row(notify, host):
    """HOST's old row in a notify seam, as a list: a string (an older --set wrote one) is its one backend,
    anything else that is no list is none. bin/ask's notify_row and ask_guard read the row through this too."""
    row = notify.get(host)
    return row if isinstance(row, list) else [row] if isinstance(row, str) else []


def ladder(kind, host, path=None, text=_READ, legacy_after=LEGACY_AFTER):
    """[{"via", "after" (seconds), "when", "at", "legacy", "implicit"}]: KIND's rungs, in order (HOST is the
    caller's, kept for the signature: the host row is resolved by bin/ask's stall_road and notice); `at`
    is the rung's place in the owner's list (in the derived one, for a kind with no ladder). A file with no
    `notify.<kind>` reads as before the ladder: `stall` as HOST_ROW, the host's old row as one rung at
    LEGACY_AFTER (`legacy`: the stall road sends it by notice() and asks stall_road() for its road),
    `question` as `charterer` then that rung, `update` as `charterer`; that implied charterer is `implicit`.
    A `notify.<kind>` that is there and no list reads as no rung. A rung that does not read is dropped here;
    validate() names it."""
    n = load(path, text)["notify"]
    if kind not in n:
        imp = {"via": "charterer", "after": 0.0, "when": None, "legacy": False, "implicit": True}
        row = {"via": HOST_ROW, "after": float(legacy_after), "when": None, "legacy": True, "implicit": False}
        raw = {"stall": [row], "question": [imp, row], "update": [imp]}.get(kind, [])
        return [dict(r, at=i) for i, r in enumerate(raw)]
    raw = n.get(kind)
    if not isinstance(raw, list):
        return []   # there and no list: no rung at all (unrouted, and validate() names it), never the old row instead
    out, vias = [], set()
    for i, r in enumerate(raw):
        if not isinstance(r, dict) or not _word(r.get("via"), CHANNELS) or r["via"] in vias:
            continue   # a channel named twice in one ladder: its first rung alone (validate() names the second)
        vias.add(r["via"])   # taken by its first rung even when that rung does not read: never a later one instead
        after = duration(r.get("after", 0))
        # a misspelt key (`When`, `afer`) is a rung that does not read: dropped, never fired at once and unheld
        if after is None or (r.get("when") is not None and not _word(r.get("when"), WHEN)) or set(r) - {"via", "after", "when"}:
            continue
        out.append({"via": r["via"], "after": after, "when": r.get("when"), "at": i, "legacy": False, "implicit": False})
    return out


def quiet(path=None, text=_READ):
    """{"hours": (start, end) | None, "except": set of kinds, "bad": bool}: notify.quiet, read. A key that is
    there and does not read is `bad`, and holds every phone rung (in_quiet): a setting that only narrows
    never fails open (AGENTS.md's trap); only an absent key means no quiet hours."""
    n = load(path, text)["notify"]
    if "quiet" not in n:
        return {"hours": None, "except": set(), "bad": False}
    if quiet_problems(n["quiet"]):
        return {"hours": None, "except": set(), "bad": True}
    q = n["quiet"]
    return {"hours": hours(q["hours"]), "except": set(q.get("except") or []), "bad": False, "tz": q.get("tz")}


def _zone(name):
    """A zoneinfo zone by its IANA name, or None when it does not load."""
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo(name)
    except Exception:   # noqa: BLE001 — no such zone, no tz database, or a name that is no string
        return None


def in_quiet(t, kind, path=None, q=None):
    """True when a phone-reaching rung of KIND holds at epoch T by notify.quiet — in its `tz` (an IANA name)
    when it names one, else the host's local time; always, for every kind, when notify.quiet is there and does
    not read. Equal ends ("00:00-00:00") are the whole day."""
    q = q or quiet(path)
    if q.get("bad"):
        return True
    if not q["hours"] or kind in q["except"]:
        return False
    import time as _t
    if q.get("tz"):
        import datetime
        lt = datetime.datetime.fromtimestamp(t, _zone(q["tz"])).timetuple()
    else:
        lt = _t.localtime(t)
    m = lt.tm_hour * 60 + lt.tm_min
    a, b = q["hours"]
    if a == b:
        return True   # "00:00-00:00": the whole day
    return (a <= m < b) if a < b else (m >= a or m < b)


def cap(path=None, text=_READ):
    """notify.cap's per_hour: None when the key is absent (no cap), an int > 0, or 0 when the key is there
    and does not read — every phone rung held until it does (never a cap that fails open)."""
    n = load(path, text)["notify"]
    if "cap" not in n:
        return None
    return 0 if cap_problems(n["cap"]) else int(n["cap"]["per_hour"])


def quiet_problems(q):
    if not isinstance(q, dict) or hours(q.get("hours")) is None:
        return ["notify.quiet: {\"hours\": \"HH:MM-HH:MM\", \"except\": [kind…]}"]
    bad = []
    ex = q.get("except", [])
    if not isinstance(ex, list) or not all(_word(k, LADDER_KINDS) for k in ex):
        bad.append("notify.quiet.except: a list of %s" % ", ".join(LADDER_KINDS))
    if "tz" in q and _zone(q["tz"]) is None:
        bad.append("notify.quiet.tz: %r is no time zone (an IANA name, \"America/Los_Angeles\")" % (q["tz"],))
    extra = set(q) - {"hours", "except", "tz"}
    if extra:
        bad.append("notify.quiet: unknown key(s) %s" % ", ".join(sorted(map(str, extra))))
    return bad


def cap_problems(c):
    v = c.get("per_hour") if isinstance(c, dict) else None
    whole = (isinstance(v, int) and not isinstance(v, bool)) or (isinstance(v, float) and v.is_integer())
    if not (whole and v > 0) or set(c) - {"per_hour"}:
        return ["notify.cap: {\"per_hour\": <a whole number above 0>}, nothing else"]
    return []


def validate_ladders(notify):
    """Problems with the ladder keys of a notify seam, as lines."""
    bad = []
    for kind in LADDER_KINDS:
        if kind not in notify:
            continue
        rungs = notify[kind]
        if not isinstance(rungs, list):
            bad.append("notify.%s: a list of rungs" % kind)
            continue
        vias = set()
        for i, r in enumerate(rungs):
            where = "notify.%s[%d]" % (kind, i)
            if not isinstance(r, dict):
                bad.append("%s: a rung is {\"via\": …}" % where)
                continue
            if not _word(r.get("via"), CHANNELS):
                bad.append("%s: unknown channel %r (known: %s)" % (where, r.get("via"), ", ".join(sorted(CHANNELS))))
            elif r["via"] in vias:
                bad.append("%s: %s named twice in notify.%s (one rung per channel: only the first is read, and none while it does not read)" % (where, r["via"], kind))
            else:
                vias.add(r["via"])
            if "after" in r and duration(r["after"]) is None:
                bad.append("%s: after %r is no duration (\"10m\", \"90s\", \"1h\" or seconds, at most a year)" % (where, r["after"]))
            if r.get("when") is not None and not _word(r["when"], WHEN):
                bad.append("%s: when %r (known: %s)" % (where, r["when"], ", ".join(sorted(WHEN))))
            extra = set(r) - {"via", "after", "when"}
            if extra:
                bad.append("%s: unknown key(s) %s" % (where, ", ".join(sorted(map(str, extra)))))
    if "quiet" in notify:
        bad += quiet_problems(notify["quiet"])
    if "cap" in notify:
        bad += cap_problems(notify["cap"])
    return bad


def seam_problems(data):
    """Why DATA (a file's JSON) cannot be read for its notify seam, as lines: a file that is no object, or a
    notify seam (or its old name) that is there and no object. Only notify: load() reads every seam that is
    no object as its defaults, and a typo in ask, helm, plan or hail must not hold the stall road's phone
    rungs (file_problems names those). A notify read as its defaults would drop quiet hours and the cap."""
    if not isinstance(data, dict):
        return ["the file is no JSON object"]
    # an empty one (null, [], "") reads as the defaults, as it always did
    seams = ["notify"] + [old for old, new in OLD_SEAMS.items() if new == "notify"]
    return ["%s is no object (a JSON object of rows)" % k for k in seams
            if data.get(k) and not isinstance(data[k], dict)]


def load(path=None, text=_READ):
    """{seam: rows}: the file over DEFAULTS. A file that is not there, does not read, is no JSON or no object
    reads as the defaults, and so does a seam that is no object: never a traceback in every reader
    (file_problems names each; the stall road holds its phone rungs on notify_unreadable)."""
    p = Path(path) if path else FILE
    if text is _READ:
        try:
            text = p.read_text()
        except (OSError, ValueError):
            text = None
    try:
        data = json.loads(text) if isinstance(text, str) and text else {}
    except ValueError:
        data = {}
    out = {}
    obj = lambda x: x if isinstance(x, dict) else {}   # a seam that is no object reads as its defaults (validate names it)
    data = obj(data)
    for seam, rows in DEFAULTS.items():
        merged = dict(rows)
        for old, new in OLD_SEAMS.items():
            if new == seam:
                merged.update(obj(data.get(old)))
        merged.update(obj(data.get(seam)))
        out[seam] = merged
    return out


def notify_unreadable(path=None, text=_READ):
    """Why the file cannot be read for its notify seam, or None (read, or no file at all). load() reads a
    file that will not read, and a notify seam that is no object, as the defaults, which would drop quiet
    hours and the cap: the stall road holds every phone rung while this says something, as a quiet or cap
    key that does not read does."""
    p = Path(path) if path else FILE
    if text is _READ:
        text = snapshot(p)
    if isinstance(text, Exception):   # a file that will not read (a permission, a folder, no UTF-8) is named so
        return "%s does not read (%s)" % (p.name, type(text).__name__)
    if text is None:
        # a link whose target moved is unreadable, not absent (AGENTS.md's trap): the owner's file is a link
        return "%s is a link to a missing file" % p.name if p.is_symlink() else None
    if not text.strip():
        return "%s is empty (a write cut short reads so: a file with no seams is {})" % p.name
    try:
        data = json.loads(text)
    except ValueError:
        return "%s is no JSON" % p.name
    bad = seam_problems(data)
    return "%s: %s" % (p.name, bad[0]) if bad else None


def row(name, path=None):
    """`ask.relay` → its value (`plan.state` reads `helm.state`)."""
    seam, key = name.split(".", 1)
    return load(path).get(OLD_SEAMS.get(seam, seam), {}).get(key)


def host():
    """laptop | buildbox | cloud | <other>: an ask's notify row key (the stall road keys by helmlib.host()). A cloud VM has no LocalHostName."""
    if os.environ.get("SURFACES_HOST"):
        return os.environ["SURFACES_HOST"]
    if os.environ.get("CLAUDE_CODE_REMOTE") or not Path("/usr/sbin/scutil").exists():
        return "cloud"
    import subprocess
    try:
        r = subprocess.run(["/usr/sbin/scutil", "--get", "LocalHostName"], capture_output=True, text=True, timeout=5)
        return (r.stdout.strip() or "unknown").lower()
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"


def validate(data):
    """Problems with a surfaces dict, as lines; empty when it is fine."""
    bad = []
    for name, ok in KNOWN.items():
        seam, key = name.split(".", 1)
        if data.get(seam) is not None and not isinstance(data.get(seam), dict):
            continue   # named below (hail) or by load(), which reads it as its defaults
        rows = dict(data.get(seam) or {})
        for old, new in OLD_SEAMS.items():
            if new == seam and isinstance(data.get(old), dict):
                rows = dict(data.get(old), **rows)
        # notify.*: the old per-host rows only; the ladder keys are validate_ladders()'
        keys = [k for k in rows if not (seam == "notify" and k in LADDER_KEYS)] if key == "*" else [key]
        for k in keys:
            v = rows.get(k)
            vals = v if isinstance(v, list) else [v]
            for x in vals:
                if not isinstance(x, (str, bool, type(None))) or x not in ok:   # a list or object is no name (and unhashable)
                    bad.append("%s.%s: unknown backend %r (known: %s)" % (seam, k, x, ", ".join(sorted(ok))))
    hail = data.get("hail")
    if hail is not None and not isinstance(hail, dict):
        bad.append("hail: an object, {\"roads\": [...]}")
    elif isinstance(hail, dict) and "roads" in hail and not isinstance(hail["roads"], list):
        bad.append("hail.roads: a list of road names (a row that only narrows: hail reads a bare name as that road, any other shape as no road)")
    if not isinstance(data.get("ask", {}).get("parked"), bool):
        bad.append("ask.parked: true or false")
    return bad + validate_ladders(data.get("notify") or {})


def file_problems(path=None):
    """Problems with the file as written, as lines: what load() smooths over (a file that does not parse,
    a seam that is no object, which load() reads as its defaults) and validate(load()). wharf-runs' hail
    reads its own row from the same file and takes no road where this names its seam or the file, so
    `ask backends` prints these: what helm shows and what hail takes must not differ unsaid."""
    p = Path(path) if path else FILE
    try:
        text = p.read_text()
    except UnicodeDecodeError as e:   # a ValueError, not an OSError: hail reads it as no road too
        return ["%s is not UTF-8 (%s): helm reads its defaults, and hail takes no road" % (p, e.reason)]
    except OSError as e:
        if isinstance(e, FileNotFoundError) and not os.path.lexists(p):
            return []   # no file: the defaults, for helm and hail alike
        return ["%s cannot be read (%s): helm reads its defaults, and hail takes no road" % (p, e.strerror or e)]
    try:
        data = json.loads(text)
    except ValueError:
        return ["%s does not parse: helm reads its defaults, and hail takes no road" % p]
    if not isinstance(data, dict):
        return ["%s is no object: helm reads its defaults, and hail takes no road" % p]
    bad = ["%s: an object (read as its defaults%s)" % (seam, "; hail takes no road" if seam == "hail" else "")
           for seam in list(DEFAULTS) + list(OLD_SEAMS) if seam in data and not isinstance(data[seam], dict)]
    return bad + [b for b in validate(load(p)) if b not in bad]


def problems(path=None):
    """Every problem `ask backends` and `helm backends` print, one list: why the stall road holds its phone
    rungs (notify_unreadable), then file_problems(), each once (charterer S3)."""
    why = notify_unreadable(path)
    bad = file_problems(path)
    return ([why + " — the stall road holds every phone rung"] if why else []) + [b for b in bad if b != why]

def set_row(assign, path=None):
    """`relay=file` or `ask.relay=talk,file` or `helm.live=redeploy`: writes the file, returns the new value.
    A bare key is looked up in ask, then helm, then notify, then hail; `plan.<key>` is written as `helm.<key>`."""
    p = Path(path) if path else FILE
    key, _, val = assign.partition("=")
    if not val:
        raise ValueError("--set wants key=value")
    # a file that will not read is refused, never rewritten as {}: that would drop notify.quiet, notify.cap
    # and every ladder, narrowings a writer must carry over (AGENTS.md, the narrowing trap). Only a file that
    # is truly absent starts empty; a link to a missing file is unreadable, not absent
    try:
        raw = p.read_text()
        data = json.loads(raw) if raw.strip() else {}   # an empty file holds nothing to carry over: as no file
    except FileNotFoundError:
        if os.path.lexists(p):
            raise ValueError("%s is a link to nothing: fix it by hand first" % p)
        data = {}   # no file: the one row starts it
    except (OSError, ValueError) as e:
        # never write over what did not read: it may hold a narrowing row (hail.roads) the rewrite would drop
        raise ValueError("%s does not read (%s): fix it by hand first" % (p, getattr(e, "strerror", None) or e))
    if not isinstance(data, dict):
        raise ValueError("%s is no object: fix it by hand first" % p)
    if "." in key:
        seam, k = key.split(".", 1)
        seam = OLD_SEAMS.get(seam, seam)
        if seam not in DEFAULTS:
            raise ValueError("no seam named %s (ask, helm, notify)" % seam)
    else:
        seam = next((s for s in ("ask", "helm", "notify", "hail") if key in DEFAULTS[s]), None)
        k = key
        if not seam:
            raise ValueError("no row named %s" % key)
    if seam in data and not isinstance(data[seam], dict):
        raise ValueError("%s's %s is no object: fix it by hand first" % (p, seam))
    if seam == "notify" and k in LADDER_KEYS:
        raise ValueError("notify.%s is JSON (a ladder, quiet hours or a cap): edit the file, then `ask backends` checks it" % k)
    cur = load(p)[seam].get(k)
    if isinstance(cur, list) or seam == "notify":   # a host row is a list, as ladder() reads it (a string one from an older --set too)
        new = [x for x in val.split(",") if x]
    elif isinstance(cur, bool) or isinstance(DEFAULTS[seam].get(k), bool):
        new = val.lower() in ("1", "true", "yes", "on")
    else:
        new = val
    if not isinstance(data.get(seam), dict):
        data[seam] = {}   # an empty seam (null, []) reads as the defaults: written as an object
    data[seam][k] = new
    before = set(validate(load(p)))
    probe = load(p)
    probe[seam][k] = new
    # a problem the file had before is no refusal (--set past old problems), unless it is the key written
    bad = [b for b in validate(probe) if b not in before or b.startswith("%s.%s:" % (seam, k))]
    if bad:
        raise ValueError("; ".join(bad))
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    return new


def describe(path=None):
    data = load(path)
    lines = []
    for seam in ("ask", "helm", "notify", "hail"):
        for k, v in data[seam].items():
            flat = isinstance(v, list) and all(isinstance(x, str) for x in v)
            lines.append("%-20s %s" % ("%s.%s" % (seam, k), ", ".join(v) if flat else json.dumps(v)))
    return "\n".join(lines)
