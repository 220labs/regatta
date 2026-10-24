"""Helm's source of truth (docs/session-asks-2026-10-09.md section 3): a directory per ship on the
skipper's Mac — plan.json, written only by the skipper through `bin/helm`, and events.jsonl,
append-only, one JSON line per report (O_APPEND: lines under 4 KB never interleave, K7).

state() merges the two into the one dict every rendering reads (state.json): the last event per
task wins for its status, ETA, progress and cost; asks stay open until answered or the task ends.
Stdlib only, Python 3.9, nothing of Claude's imported (R8).

Named planlib.py until rename S5 (docs/record/helm-vocabulary-2026-10-16.md, H1). On disk nothing
moved: the store is still plans/<id>/plan.json, and its persisted keys keep their names — the
`manager` object, `eta_by: "manager"`, the estimate kind "manager" (printed "skipper"); a task's
doer is written `by` and read as `by` or the older `owner` (D3-A).
"""
import contextlib
import datetime as dt
import fcntl
import importlib.util
import json
import os
import re
import socket
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _common():
    """The regatta core's common.py (lib/find_core.py: the checkout this module sits in, else the
    config dir's `home`, else the core plugin's installPath; never a copy). Loaded on first use, not
    at import: wharf's session_status loads this file for GUARDED alone, and a missing core must not
    end that caller (find_core exits). No core is an ImportError the callers' own guards take."""
    import sys
    if "common" in sys.modules:
        return sys.modules["common"]
    lib = str(HERE.parent / "lib")
    if lib not in sys.path:
        sys.path.insert(0, lib)
    import find_core
    try:
        hooks = find_core.hooks()
    except SystemExit:
        raise ImportError("helm: the regatta core is missing")
    if hooks not in sys.path:
        sys.path.insert(0, hooks)
    import common
    return common


def peer(name):
    """A peer module's file through the core's tool() (the design's C2): keel's keel, sheep and
    sheep_gate.py, wharf-runs' dispatch, dispatch-rc, autofinish, harness, wharf and blueprintlib.py,
    plumb's usage-report — wherever each lives: a module here, or a plugin install's.
    None when it is not installed (or there is no core): each caller names what it skips."""
    try:
        return _common().tool(name)
    except ImportError:
        return None


def yard_hosts():
    """(hosts, torn): the hosts some scope's `yard` names (the core's scope_yards(), skipper-resilience
    S2), and whether that could not be told. torn is True, and hosts empty, when the registry is there
    and does not read (the core's registry_unreadable(): a torn write, conflict markers) or there is no
    core: a gate that lets a host act because it is a yard fails closed on it (the fence trap), while
    one that only stops acting for a yard reads no yard. No registry file is no yard, never torn."""
    try:
        common = _common()
        if common.registry_unreadable():
            return set(), True
        return set(common.scope_yards().values()), False
    except Exception:   # noqa: BLE001 — no core, or one too old to know yards: nothing can be told
        return set(), True


def brake_refusal():
    """Why the studio brake holds this Mac, or None: wharf-runs' own brake_refusal() (S1), so the tick
    and wharf read one rule — the brake file, or the job the brake stops, in state T. wharf is a script
    with a dash-free name and no CLI for this, so it is loaded as a module. None when wharf-runs is
    not installed or does not load: an unreadable brake is no brake, as it is to wharf's own starts."""
    exe = peer("wharf")
    if not exe:
        return None
    import sys
    path = list(sys.path)   # wharf puts its own folders first on import; the tick's later imports must not see them
    try:
        from importlib.machinery import SourceFileLoader
        from importlib.util import module_from_spec, spec_from_loader
        loader = SourceFileLoader("wharf_for_brake", str(exe))
        mod = module_from_spec(spec_from_loader(loader.name, loader))
        loader.exec_module(mod)
        return mod.brake_refusal()
    except (Exception, SystemExit):   # noqa: BLE001 — wharf exits at import when it cannot find its peers
        return None
    finally:
        sys.path[:] = path


# ---------------------------------------------------------------------------- the brake's windows (S13a)
# The studio brake freezes a skipper's whole tree (claude and its lease sidecar), but not the wall clock:
# the lease's `until` stops being renewed and a hailed question's minutes keep counting, so the first pass
# after the brake let go would hand over, as lapsed or deaf, a skipper that was only frozen. The tick
# records when the brake held (brake-windows.json beside its other state, note_brake_pass) and the two
# clocks subtract that time (braked_within): leaselib.lapsed for every lease reader (wharf's, helm send's,
# the tick's), skipperlib.deaf for the deaf rule, and the skipper pass's two start clocks (a take within
# TAKE_WITHIN, a yard-held ship its sidecar should have taken) and the stall road's unanswered-relay
# clock beside them. Chosen over pushing each lease's `until` on at every
# braked pass because one record serves both clocks; the deaf rule's start is a hail time in the plan's
# `relayed` list and the ask's events, which would otherwise need rewriting too.
# The brake carries no time of its own, so a window is bounded by the tick's passes: it opens at the last
# pass before the first that saw the brake (no earlier than BRAKE_LEAD before that one) and closes at the
# first pass that does not see it (no later than BRAKE_LEAD after the last that did). Both ends err
# towards keeping a skipper: at worst a deaf or lapsed one is handed over one pass period later. A window
# still open — the brake holding, or the tick gone quiet under it — credits time only up to BRAKE_LEAD
# past its last braked pass, so a tick that dies under the brake does not keep every lease alive forever.
# No file is no brake ever seen: both clocks run as before S13a (every host with no lease writes none).

BRAKE_LEAD = 10 * 60          # two of ask poll's 5-minute passes
BRAKE_KEEP = 7 * 24 * 3600    # a closed window older than this is dropped (the daily hand-over ends any lease long before)
BRAKE_MAX = 200               # windows kept at most


def tick_state_dir():
    """The tick's state dir (stalls_tick.state_dir's one rule: STALLS_STATE_DIR, else .local/state/stalls under HOME)."""
    return Path(os.environ.get("STALLS_STATE_DIR") or Path(os.environ.get("HOME") or Path.home()) / ".local/state/stalls")


def brake_windows_path():
    return tick_state_dir() / "brake-windows.json"


def _brake_state():
    """{"windows": [[start, end], …], "since": the open window's start or None, "seen": its last braked
    pass or None, "pass": the last pass}; an empty record when the file is absent or does not read."""
    try:
        d = json.loads(brake_windows_path().read_text())
    except (OSError, ValueError):
        d = None
    if not isinstance(d, dict):
        d = {}
    ws = [w for w in d.get("windows") or [] if isinstance(w, list) and len(w) == 2
          and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in w) and w[0] <= w[1]]
    num = lambda x: float(x) if isinstance(x, (int, float)) and not isinstance(x, bool) else None
    return {"windows": ws, "since": num(d.get("since")), "seen": num(d.get("seen")), "pass": num(d.get("pass"))}


def brake_windows(t=None):
    """[(start, end)] of every time the brake held here: the closed windows, and an open one ending at
    min(t, its last braked pass + BRAKE_LEAD)."""
    t = now() if t is None else t
    d = _brake_state()
    out = [tuple(w) for w in d["windows"]]
    if d["since"] is not None:
        out.append((d["since"], min(t, (d["seen"] or d["since"]) + BRAKE_LEAD)))
    return out


def braked_within(a, b):
    """Seconds of [a, b] the brake held here (brake_windows); 0 with no record. Never raises: a record that
    does not read credits nothing, and the clocks run as they did before S13a."""
    try:
        a, b = float(a), float(b)
        if b <= a:
            return 0.0
        return float(sum(max(0.0, min(b, e) - max(a, s)) for s, e in brake_windows(b)))
    except Exception:   # noqa: BLE001
        return 0.0


def note_brake_pass(braked, t=None):
    """One tick pass seen, braked or not (the tick's, before its skipper pass): a braked pass opens a
    window or moves its last-seen on; the first unbraked one closes it. Written by an atomic replace;
    returns the record."""
    t = now() if t is None else t
    d = _brake_state()
    if braked:
        if d["since"] is not None and d["seen"] is not None and t - d["seen"] > BRAKE_LEAD:
            # the tick was quiet under the brake: what the header promises — the gap past BRAKE_LEAD is
            # no braked time — closes the window there and opens a new one BRAKE_LEAD back (the landing review)
            d["windows"].append([d["since"], d["seen"] + BRAKE_LEAD])
            d["since"] = t - BRAKE_LEAD
        elif d["since"] is None:   # no pass seen before this one (a first tick, a record lost): BRAKE_LEAD back
            d["since"] = max(d["pass"], t - BRAKE_LEAD) if d["pass"] is not None else t - BRAKE_LEAD
        d["seen"] = t
    elif d["since"] is not None:
        d["windows"].append([d["since"], max(d["since"], min(t, (d["seen"] or d["since"]) + BRAKE_LEAD))])
        d["since"] = d["seen"] = None
    d["pass"] = t
    d["windows"] = [w for w in d["windows"] if w[1] >= t - BRAKE_KEEP][-BRAKE_MAX:]
    p = brake_windows_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(".%s.%d" % (p.name, os.getpid()))
    tmp.write_text(json.dumps(d, sort_keys=True))
    tmp.replace(p)
    return d


def harness_adapter(name):
    """wharf-runs' harness adapter `name` (claude_code.py, orca.py): it sits in harness_adapters/
    beside bin/harness, which loads it so; tool() takes no path, so the adapter is found by its
    harness. None when the harness or the adapter is not here."""
    h = peer("harness")
    p = h.parent / "harness_adapters" / name if h else None
    return p if p and p.is_file() else None
# The run's environment (rename S5, H1): a ship's id and its skipper's road, each written under its
# new name and its old one until S8, and read under either forever — a launchd plist written before
# S5 exports only the old names, and a run started before it carries them.
ENV_NAMES = {"ship": ("DISPATCH_SHIP", "DISPATCH_PLAN"), "skipper": ("DISPATCH_SKIPPER", "DISPATCH_MANAGER"),
             "skipper_account": ("DISPATCH_SKIPPER_ACCOUNT", "DISPATCH_MANAGER_ACCOUNT"),
             "skipper_host": ("DISPATCH_SKIPPER_HOST", "DISPATCH_MANAGER_HOST")}


def env(key, environ=None):
    """The value of ENV_NAMES[key] under its new name, else its old one; None when neither is set."""
    environ = os.environ if environ is None else environ
    for name in ENV_NAMES[key]:
        if environ.get(name):
            return environ[name]
    return None


def env_pairs(key, value):
    """[(NEW, value), (OLD, value)]: what a writer exports, both names until rename S8."""
    return [(name, value) for name in ENV_NAMES[key]]


def people():
    """Who a human task may wait on, lower-case, the owner first: the config dir's `helm/people`
    (one name per line), else the core's owner (`regatta/owner`), else `owner`."""
    try:
        c = _common()
        names = c.config_lines("helm/people") or [c.OWNER_NAME or "owner"]
    except Exception:
        names = ["owner"]
    return tuple(dict.fromkeys(n.strip().lower() for n in names if n.strip()))


def display(name):
    """A person's name as the config dir writes it (`Sam`), for a column or a line."""
    try:
        c = _common()
        for n in (c.config_lines("helm/people") or []) + [c.OWNER_NAME]:
            if n and n.strip().lower() == (name or "").lower():
                return n.strip()
    except Exception:
        pass
    return name


def doer(t):
    """A task's or event's doer: `by` (rename S5, D3-A), else the older `owner`."""
    return (t or {}).get("by") or (t or {}).get("owner")


SKIPPER = "skipper"   # what the page and `helm show` print for the persisted "manager" keys
# `launched` is rename S5's word for `landed` (docs/wharf-rename-2026-10-16.md, M11): an old plan.json
# keeps `landed` forever, so both are listed, both end a task and both satisfy a dependency (DONE)
STATUSES = ("planned", "running", "relayed", "parked", "waiting", "blocked", "done", "failed", "landed", "launched")
DONE = ("done", "landed", "launched")
ENDED = DONE + ("failed",)
# Repos whose rows never leave the Mac with text in them (K6): hooks/sheep_gate.py's PRIVATE_REPOS,
# the one list (two repos were missing from the gate while this file had them, 2026-10-16).
# Loaded by path, not imported: the gate is keel's (hooks/sheep_gate.py), found through the core's
# tool(), and stdlib like this file. A gate that will not load (keel not installed, a syntax error
# mid-edit) must not take helm, ask and stalls down with it, nor guard less: then the core's own
# lists stand in — the registry's `guarded` and the config dir's `regatta/guarded`, together.


def _fallback_repos():
    try:
        c = _common()
    except Exception:  # no core, or its config incomplete: nothing named, nothing to guard by name
        return ()
    return tuple(dict.fromkeys(tuple(c.guarded_repos()) + tuple(c.config_lines("regatta/guarded") or ())))


def _load_gate(path):
    if not path:
        return None
    try:
        spec = importlib.util.spec_from_file_location("sheep_gate", str(path))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        tuple(mod.PRIVATE_REPOS), mod.private_part  # noqa: B018 — both must exist
        return mod
    except Exception:
        return None


_sheep_gate = _load_gate(peer("sheep_gate.py"))
GUARDED = tuple(_sheep_gate.PRIVATE_REPOS) if _sheep_gate else _fallback_repos()
# O_APPEND keeps whole lines apart below PIPE_BUF; a longer report has its free text shrunk (append_event)
MAX_LINE = 4000
MIN_BURN = 600  # seconds of a task's history before its burn rate is extrapolated
# A task `helm send` handed to a scope's skipper (skipper-resilience S7, bin/sendlib.py): who sent it and
# when, from the yard's `helm send --mark`, and when its scope's skipper first took the ship (leaselib.take).
# state() derives `send` from them — "sent" until the pickup, then "picked up" — and leaves `status`
# alone: wharf drives the block's status whoever holds the lease, and a `sent` there would read as a
# stage of the block (the page's colours, the S7 stall's `planned`) rather than of the hand-over.
SENT_FIELDS = ("sent_by", "sent_at", "sent_from", "picked_up_at", "picked_up_by")
SEND_ONLY = set(SENT_FIELDS) | {"task", "t", "lease_gen", "plan"}   # every key a mark or a pickup event has
# The free-text fields append_event may shrink, longest first, to fit a line under MAX_LINE bytes
SHRINK = ("progress", "summary", "recommended", "title", "waiting_for", "by", "owner", "branch", "pr", "check")
# What a line keeps when shrinking the free text was not enough (long lists of owned paths, say)
ESSENTIAL = ("task", "status", "t", "session", "host", "harness", "ask", "answered", "from", "plan", "repo",
             "eta", "cost", "parked", "via") + SENT_FIELDS


def plans_root():
    return Path(os.environ.get("PLANS_DIR") or Path(os.environ.get("HOME") or Path.home()) / "Library/Logs/claude-weekly/plans")


def plan_dir(pid):
    if not re.match(r"^[A-Za-z0-9._-]+$", pid or ""):
        raise ValueError("a plan id is letters, digits, dot, dash and underscore: %r" % pid)
    return plans_root() / pid


def now():
    return time.time()


def iso(t):
    return dt.datetime.fromtimestamp(t).astimezone().isoformat(timespec="seconds") if t else None


def host():
    h = os.environ.get("PLAN_HOST") or os.environ.get("DISPATCH_HOST")
    if h:
        return h
    try:
        import subprocess
        r = subprocess.run(["/usr/sbin/scutil", "--get", "LocalHostName"], capture_output=True, text=True, timeout=5)
        if r.stdout.strip():
            return r.stdout.strip().lower()
    except (OSError, Exception):
        pass
    return socket.gethostname().split(".")[0].lower()


def harness():
    if os.environ.get("PLAN_HARNESS"):
        return os.environ["PLAN_HARNESS"]
    if os.environ.get("CLAUDE_CODE_SESSION_ID") or os.environ.get("CLAUDECODE"):
        return "claude-code"
    if os.environ.get("CODEX_HOME") or os.environ.get("CODEX_SESSION_ID"):
        return "codex"
    return "other"


def current_repo(cwd=None):
    """The repo a report comes from (K6): $DISPATCH_REPO, which dispatch passes its run, else the
    main checkout of the cwd's repo (a worktree's toplevel is named for its topic, so the common
    dir's parent names the repo). None outside a repo."""
    if os.environ.get("DISPATCH_REPO"):
        return os.environ["DISPATCH_REPO"]
    try:
        import subprocess
        r = subprocess.run(["git", "-C", str(cwd or os.getcwd()), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=5)
    except (OSError, Exception):
        return None
    common = Path(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None
    if not common:
        return None
    return str(common.parent if common.name == ".git" else common)


def parse_eta(text, base=None):
    """`40m`, `2h`, `1h30m`, `90s`, an ISO time or `@EPOCH` → epoch seconds; None for empty."""
    if text in (None, ""):
        return None
    if isinstance(text, (int, float)):
        return float(text)
    s = str(text).strip()
    base = base or now()
    if s.startswith("@"):
        return float(s[1:])
    m = re.fullmatch(r"(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?", s)
    if m and any(m.groups()):
        d, h, mi, se = (int(x or 0) for x in m.groups())
        return base + d * 86400 + h * 3600 + mi * 60 + se
    try:
        t = dt.datetime.fromisoformat(s)
        if t.tzinfo is None:
            t = t.astimezone()
        return t.timestamp()
    except ValueError:
        raise ValueError("an ETA is 40m, 2h, 1h30m, an ISO time or @EPOCH: %r" % s)


# ---------------------------------------------------------------------------- the store

def load_plan(pid):
    try:
        return json.loads((plan_dir(pid) / "plan.json").read_text())
    except (OSError, ValueError):
        return None


@contextlib.contextmanager
def locked(pid):
    """The plan's write lock: a read-modify-write of plan.json holds it from its read to its save,
    so two writers (bin/plan, wharf's apply, wharf check --accept, the render's space) never lose
    each other's changes. Advisory, flock on plan.lock beside plan.json; no plan dir, no lock (nothing
    to lose, and a typo'd id leaves no empty plan behind). Re-entrant within a process: flock on a
    second open of the file would wait on this process's own lock (plan compile → render → deploy)."""
    d = plan_dir(pid)
    if not d.is_dir() or pid in _held:
        yield
        return
    with open(str(d / "plan.lock"), "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        _held.add(pid)
        try:
            yield
        finally:
            _held.discard(pid)


_held = set()


def save_plan(plan):
    d = plan_dir(plan["id"])
    d.mkdir(parents=True, exist_ok=True)
    plan["updated"] = now()
    plan.setdefault("salt", os.urandom(8).hex())  # public()'s guarded tokens; a plan from before it gets one
    tmp = d / ("plan.json.%d.tmp" % os.getpid())
    tmp.write_text(json.dumps(plan, indent=1, ensure_ascii=False, sort_keys=True))
    tmp.replace(d / "plan.json")


def new_plan(pid, topic, manager=None, space=None, repo=None, due=None, cost=None):
    # salt: keys the guarded tasks' tokens in public() — kept in plan.json, never in a copy that leaves.
    # `manager` keeps its key on disk (the skipper's session); `due` and `cost` are the ship's (H1),
    # `started` is set by its first `wharf apply` — all three absent on a plan from before rename S5
    plan = {"id": pid, "topic": topic, "created": now(), "manager": manager or {}, "space": space,
            "repo": repo, "tasks": {}, "milestones": [], "salt": os.urandom(8).hex()}
    if due is not None:
        plan["due"] = due
    if cost is not None:
        plan["cost"] = cost
    save_plan(plan)
    (plan_dir(pid) / "events.jsonl").touch()
    return plan


def append_event(pid, ev):
    """One line, O_APPEND — children never edit, never conflict."""
    d = plan_dir(pid)
    if not d.is_dir():
        raise FileNotFoundError("no plan %s here (%s)" % (pid, d))
    ev = dict(ev)
    ev.setdefault("t", now())
    ev, line = fit(ev)
    fd = os.open(str(d / "events.jsonl"), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    try:
        os.write(fd, (line + "\n").encode())
    finally:
        os.close(fd)
    return ev


def _dumps(ev):
    return json.dumps(ev, ensure_ascii=False, sort_keys=True)


def _enc(text):
    """The bytes a string takes inside the line: its JSON encoding, escapes included."""
    return len(json.dumps(text, ensure_ascii=False).encode())


def _cut(text, budget):
    """The longest prefix of `text`, marked with an ellipsis, whose JSON encoding fits `budget`
    bytes — bisected on characters, so a code point is never split and a text heavy in escapes
    (a control character is six bytes as \\u0001) keeps all of itself that fits (second review,
    2026-10-11: cutting by raw bytes left such a text as "…" when most of it fit)."""
    if _enc(text) <= budget:
        return text
    lo, hi = 0, len(text)
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if _enc(text[:mid] + "…") <= budget:
            lo = mid
        else:
            hi = mid - 1
    return text[:lo] + "…"


def fit(ev):
    """(event, line): the event as one JSON line under MAX_LINE bytes. The free-text fields shrink
    first, the longest each round, each measured by its own JSON-encoded length; the JSON itself is
    never cut, so every line parses (a cut string was a torn line state() skipped, losing the
    report). If the text alone cannot make room, the line keeps the ESSENTIAL keys and says it was
    truncated."""
    line = _dumps(ev)
    while len(line.encode()) > MAX_LINE:
        longs = [(_enc(ev[k]), k) for k in SHRINK if isinstance(ev.get(k), str) and len(ev[k]) > 1]
        if not longs:
            break
        n, k = max(longs)
        over = len(line.encode()) - MAX_LINE
        ev[k] = _cut(ev[k], n - over)
        line = _dumps(ev)
    if len(line.encode()) > MAX_LINE:
        ev = {k: ev[k] for k in ESSENTIAL if k in ev}
        ev["truncated"] = True
        line = _dumps(ev)
    return ev, line


def events(pid):
    try:
        lines = (plan_dir(pid) / "events.jsonl").read_text().splitlines()
    except OSError:
        return []
    out = []
    for x in lines:
        try:
            out.append(json.loads(x))
        except ValueError:
            continue  # a torn line from a crash: skipped, never fatal
    return out


def list_plans():
    root = plans_root()
    try:
        return sorted(p.name for p in root.iterdir() if (p / "plan.json").is_file())
    except OSError:
        return []


# ---------------------------------------------------------------------------- the mode (skipper-modes S1)

# A sent task's mode, read at the moment of each decision (docs/skipper-modes-2026-10-21.md, "The
# mode"): `default` — a skipper answers `Reversible: yes`, escalates the rest; `ask` — nothing
# answers but the owner; `dnd` — `keel yolo --dnd`, the held classes relayed; `yolo` — `keel yolo`, every
# bare pick. plan.json is the authority: a task's own `mode`, else the ship's (`helm mode`, `wharf
# apply` from the blueprint, `dispatch --mode`); DISPATCH_MODE (or an ask's recorded mode) only a
# hint; then the scope's `mode` in repos.json; then `default`. A session the owner types in has no mode
# (stated, was D2): run_mode says None for it, and nothing suspends or answers for it.
MODES = ("default", "ask", "dnd", "yolo")
# task_mode's `where` for a scope read while repos.json is torn: `ask` for this decision only. A writer
# that would keep the mode (dispatch's DISPATCH_MODE and run record, wharf's `mode_refused`) asks
# torn_read() first and keeps nothing, so the mode heals with the registry (the follow-ups' landing review)
TORN_WHERE = "the registry is unreadable (repos.json): read as ask"


def torn_read(pair):
    """True when a (mode, where) pair is task_mode's torn-registry `ask`, which no writer may keep."""
    return bool(pair) and pair[1] == TORN_WHERE


def task_mode(pid=None, task=None, repo=None, hint=None):
    """(mode, where it was read) for a sent task: the plan's task, the plan, the hint, the scope — `ask`
    where the scope cannot be read because the registry is torn."""
    plan = load_plan(pid) if pid else None
    if plan:
        t = (plan.get("tasks") or {}).get(task) if task else None
        if isinstance(t, dict) and t.get("mode") in MODES:
            return t["mode"], "ship %s, task %s" % (pid, task)
        if plan.get("mode") in MODES:
            return plan["mode"], "ship %s" % pid
    if hint in MODES:
        return hint, "the run's DISPATCH_MODE"
    repo = repo or (plan or {}).get("repo")
    # a torn or conflicted repos.json reads as no scopes (the core's registry_unreadable trap), so a
    # scope's `ask` would read `default` and every refusal keyed on it would fail open: read as ask,
    # the bottom of the ladder, until it reads again (follow-ups item 6). One parse judges the tear and
    # reads the scope (item 9), so the two cannot see two different files
    c, reg, torn = None, None, False
    try:
        c = _common()
        if repo and hasattr(c, "read_registry"):
            reg, torn = c.read_registry()
        elif repo:   # a core from before read_registry: two reads, as before
            torn = c.registry_unreadable()
    except Exception:  # a core without them: the reading below, as before
        torn = False
    if torn:
        return "ask", TORN_WHERE
    try:
        name, sc = (c.scope_of_repo(repo, reg=reg) if reg is not None else c.scope_of_repo(repo)) if repo else (None, {})
    except Exception:  # a core without scope_of_repo, a registry that will not read: the default
        name, sc = None, {}
    if isinstance(sc, dict) and sc.get("mode") in MODES:
        return sc["mode"], "scope %s" % name
    return "default", "the default"


def run_mode(environ=None):
    """(mode, where) for the session reading it from its own environment; (None, why) for a session
    the owner types in — no CLAUDE_UNATTENDED, no ship, no DISPATCH_MODE."""
    e = os.environ if environ is None else environ
    if not e.get("CLAUDE_UNATTENDED") and not env("ship", e) and not e.get("DISPATCH_MODE"):
        return None, "a session the owner types in has no mode"
    return task_mode(env("ship", e), e.get("DISPATCH_TASK"), e.get("DISPATCH_REPO"), e.get("DISPATCH_MODE"))


# skipper-modes S3b: the ladder's order, and who may climb it. Landing follows the mode (`ask` never
# lands by itself, `dnd` bar the held slice, `yolo` whatever the gates pass), so a raise is a merge yes:
# only the owner gives it. Every writer of a mode — `helm mode`, `dispatch --mode`/`--yolo`, `wharf apply`'s
# blueprint mode — asks raise_refusal first; an unattended caller (CLAUDE_UNATTENDED, every dispatched
# run) may keep or lower a mode, never raise it, or a run could write itself the yes to merge.
MODE_RANK = {"ask": 0, "default": 1, "dnd": 2, "yolo": 3}


def raise_refusal(old, new, environ=None):
    """None when `new` may replace `old` for this caller, else the refusal's words. A raise is any step
    up MODE_RANK (`ask` → `default` included); `old` None reads as `default`."""
    e = os.environ if environ is None else environ
    if new not in MODE_RANK or MODE_RANK[new] <= MODE_RANK.get(old or "default", 1):
        return None
    if not e.get("CLAUDE_UNATTENDED"):
        return None
    return ("mode %s over %s is a raise, and only the owner raises a mode (an unattended caller, CLAUDE_UNATTENDED=%s): "
            "landing follows the mode, so a raise is a yes to merge (skipper-modes S3b)" % (new, old or "default", e.get("CLAUDE_UNATTENDED")))


def runs_dir():
    return Path(os.environ.get("HOME") or Path.home()) / "Library/Logs/claude-weekly/run-seed-runs"   # dispatch-rc RUNS


def branch_modes_file():
    return plans_root() / "branch-modes.json"


@contextlib.contextmanager
def branch_modes_locked():
    """branch-modes.json's write lock (flock on branch-modes.lock beside it): `helm mode --branch`'s
    read-modify-write holds it, as plan.json's writers hold locked() (follow-ups item 5)."""
    f = branch_modes_file()
    f.parent.mkdir(parents=True, exist_ok=True)
    with open(str(f.with_suffix(".lock")), "w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        yield


LEGACY = " (no repo: a lowering only)"   # branch_override's `where` suffix for a key-less entry


def under_ship(over, tm):
    """A `helm mode --branch` entry (OVER) beside a sent task's mode (TM, task_mode's pair): for a task
    of a ship, the lower of the two — a ship's mode is a ceiling no branch entry outlasts, so a ship
    lowered to `ask` stays ask whatever an older `--branch B yolo` says (the follow-ups' landing
    review); for a run with no ship, the entry, the lowering verb it was made for. An entry written
    before entries named their repo (LEGACY) can only lower: it may be another repo's same-named
    branch (item 7). None: TM. The one combiner of the ladder: fire_mode and branch_mode both end here."""
    if not over:
        return tm
    lower = tm and MODE_RANK.get(tm[0], 1) < MODE_RANK.get(over[0], 1)
    if lower and (str(tm[1]).startswith("ship ") or str(over[1]).endswith(LEGACY)):
        return tm
    return over


def fire_mode(pid, task, repo, hint, branch):
    """(mode, where) dispatch's fire-time and launch reads use: the branch entry under the ship's
    mode (under_ship), one reader for both call sites."""
    return under_ship(branch_override(branch, repo), task_mode(pid, task, repo, hint))


def branch_key(branch, repo):
    """branch-modes.json's key for BRANCH of REPO: "<repo key>|<branch>" (item 7: every entry names its
    repo, branch names repeat across repos by design), None without a repo."""
    try:
        key = _common().repo_key(repo) if repo else None
    except Exception:
        key = None
    if key and key.startswith("/"):   # outside the projects folder a key is the path: one spelling per checkout
        key = str(Path(key).resolve())
    return "%s|%s" % (key, branch) if key and branch else None


def branch_override(branch, repo=None):
    """(mode, where) a `helm mode --branch` set on BRANCH of REPO, else None. dispatch's fire-time and
    launch reads ask it before task_mode (item 5). A key-less entry — written before entries named
    their repo — still counts, marked LEGACY, so under_ship lets it lower only; a reader with no repo
    reads only that one (the follow-ups' landing review, item 7)."""
    if not branch:
        return None
    bm = load_branch_modes()
    key = branch_key(branch, repo)
    e = bm.get(key) if key else None
    if isinstance(e, dict) and e.get("mode") in MODES:
        return e["mode"], "helm mode --branch %s" % branch
    e = bm.get("|%s" % branch)
    if isinstance(e, dict) and e.get("mode") in MODES:
        return e["mode"], "helm mode --branch %s%s" % (branch, LEGACY)
    return None


def yield_branch_entry(branch, repo, mode):
    """A newer `dispatch --mode MODE` on BRANCH of REPO, once its job is scheduled: an entry the branch
    has (keyed, or a key-less one from before) is replaced by MODE, keyed by REPO, under the file's lock;
    the entry it read ({"mode", "ts"}) or None, and then nothing is written. The last writer wins without
    a reader comparing clocks (item 7). Replaced, not dropped: a dropped entry let the branch's older run
    record read through until the new run fired, a higher mode than either word, and stayed dropped when
    the schedule refused afterwards (the second landing review). A key-less entry stays: it may be
    another repo's same-named branch's lowering, and the keyed one is read before it here."""
    key = branch_key(branch, repo)
    if not key or mode not in MODES:
        return None
    with branch_modes_locked():
        bm = load_branch_modes()
        was = bm.get(key) if isinstance(bm.get(key), dict) else bm.get("|%s" % branch)
        if not isinstance(was, dict):
            return None
        bm[key] = {"mode": mode, "ts": int(time.time()), "by": "dispatch --mode"}
        f = branch_modes_file()
        tmp = f.with_name("%s.%d.tmp" % (f.name, os.getpid()))
        tmp.write_text(json.dumps(bm, indent=1, sort_keys=True) + "\n")
        os.replace(tmp, f)
    return was


def load_branch_modes():
    """{"<repo key>|<branch>" or "|<branch>": {"mode", "ts"}} — `helm mode --branch`'s writes."""
    try:
        d = json.loads(branch_modes_file().read_text())
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _same_repo(a, b):
    """Two repos name one registry key — a path or a key each; either missing matches (landing review 14)."""
    if not a or not b:
        return True

    def norm(r):   # a worktree is its checkout, outside the projects folder too (repo_key keeps those as given)
        s = str(r)
        if s.startswith("/"):
            q = Path(s).resolve()
            i = q.parts.index(".claude") if ".claude" in q.parts else None
            s = str(Path(*q.parts[:i])) if i is not None and q.parts[i + 1:i + 2] == ("worktrees",) else str(q)
        try:
            return _common().repo_key(s)
        except Exception:  # a core without repo_key: the name as given
            return s
    return norm(a) == norm(b)


def branch_mode(branch, repo=None):
    """(mode, where) for the newest sent task on BRANCH, for a reader that holds only a worktree (the
    `keel stand` sweep): a `helm mode --branch` set on it (the lowering verb for a run with no ship),
    the plan task naming the branch, else the newest run record of it (its `task_mode`, dispatch's
    hint, and its ship), else (None, why) — no sent task, so no mode. With REPO, a task or record of
    another repo's same-named branch is not this one's."""
    if not branch:
        return None, "no branch"
    over = branch_override(branch, repo)
    for pid in list_plans():
        plan = load_plan(pid) or {}
        for tid, t in (plan.get("tasks") or {}).items():
            if isinstance(t, dict) and branch in (t.get("branch"), t.get("seeded_branch")) \
                    and _same_repo(repo, t.get("repo") or plan.get("repo")):
                return under_ship(over, task_mode(pid, tid, repo or t.get("repo")))
    best = None
    try:
        for f in runs_dir().glob("*.json"):
            try:
                r = json.loads(f.read_text())
            except (OSError, ValueError):
                continue
            # a record with neither `task_mode` nor `plan` is no sent task: dispatch --start (autofinish's
            # /finish launch) and probes write none, and the launch's own record must not hide the build
            # run's mode from the next judge — a retried dnd launch read `default` (skipper-modes S3b).
            # `mode_unread`: a sent task whose fire-time mode was read while repos.json was torn, kept
            # with no mode so it heals (the follow-ups' landing review)
            if not isinstance(r, dict) or r.get("branch") != branch \
                    or not (r.get("task_mode") or r.get("plan") or r.get("mode_unread")) \
                    or not _same_repo(repo, r.get("repo")):
                continue
            if best is None or (r.get("started") or 0) > (best.get("started") or 0):
                best = r
    except OSError:
        pass
    if best is None:
        # a key-less entry may be another repo's (LEGACY): with no sent task here to lower, it is no mode
        # of this branch's — returned bare, it raised a mode-less branch (the second landing review)
        if over and str(over[1]).endswith(LEGACY):
            return None, "no sent task on %s (a key-less helm mode --branch entry lowers only)" % branch
        return over or (None, "no sent task on %s" % branch)
    # the ladder's one combiner (item 8): the entry beside the record's mode, as at fire time
    return under_ship(over, task_mode(best.get("plan"), best.get("topic"), repo or best.get("repo"), best.get("task_mode")))


# ---------------------------------------------------------------------------- the merge

def guarded(repo):
    """A repo path or name in the guarded list — the one test every bin/ caller uses (bin/ask,
    helm_render, stalls, session_status). Any path part counts: a worktree's toplevel
    (…/<repo>/.claude/worktrees/x) is named for its topic, not its repo. Case-folded: APFS is
    case-insensitive, so `Notes` is notes."""
    if not repo:
        return False
    try:
        if _sheep_gate:
            return bool(_sheep_gate.private_part(str(repo)))
    except Exception:
        pass
    names = {g.casefold() for g in GUARDED}
    return any(part.casefold() in names for part in Path(os.path.expanduser(str(repo))).parts)


_guarded_repo = guarded  # the older name, kept for its callers


def guard_unread(fresh=False):
    """True when guarded() cannot be trusted to name every guarded repo: keel's gate did not load (the
    fallback list knows no confidential scope), its `regatta/guarded` key did not read where the
    overlay is installed (PRIVATE_UNREAD), or its confidential roots did not read (None: a torn
    registry, no core). What leaves the machine on guarded()'s word — the stall road's issues — fails
    closed on it. fresh: the roots read again (they are cached per process). Never raises."""
    g = _sheep_gate
    if g is None:
        return True
    try:
        if getattr(g, "PRIVATE_UNREAD", False):
            return True
        if getattr(g, "_GUARDED", ()) is None:
            return True   # no `regatta/guarded` at all, overlay or not: an empty file is "nothing guarded", a missing one is unknown

        roots = getattr(g, "confidential_roots", None)
        if roots is None:
            return False   # a gate from before confidential scopes: its list is the whole list
        if fresh and hasattr(roots, "cache_clear"):
            roots.cache_clear()
        return roots() is None
    except Exception:   # noqa: BLE001
        return True


def state(pid, at=None):
    """The merged plan: header, tasks (with blockers, asks, parked, cost, estimate), milestones."""
    plan = load_plan(pid)
    if plan is None:
        raise FileNotFoundError("no plan %s" % pid)
    at = at or now()
    evs = sorted(events(pid), key=lambda e: e.get("t", 0))
    tasks = {}
    for name, t in (plan.get("tasks") or {}).items():
        tasks[name] = {"id": name, "title": t.get("title") or name, "by": doer(t), "block": t.get("block"),
                       "kind": t.get("kind") or "session", "branch": t.get("branch"), "repo": t.get("repo") or plan.get("repo"),
                       "pr": t.get("pr"), "deps": list(t.get("deps") or []), "owns": list(t.get("owns") or []),
                       "live": list(t.get("live") or []), "status": "planned", "eta": t.get("eta"),
                       "eta_by": "manager" if t.get("eta") else None, "cost_est": t.get("cost_est"),
                       "cost": None, "progress": None, "started": None, "updated": None, "parked": [],
                       "parked_at": None, "asks": [], "session": t.get("session"), "host": None, "harness": None,
                       "check": t.get("check"), "waiting_for": None, "milestone": t.get("milestone"),
                       "blueprint": _block_fields(t), **dict.fromkeys(SENT_FIELDS)}
    asks = {}
    for e in evs:
        name = e.get("task")
        if not name:
            continue
        t = tasks.setdefault(name, {"id": name, "title": name, "by": None, "block": None, "kind": "session", "branch": None,
                                    "repo": plan.get("repo"), "pr": None, "deps": [], "owns": [], "live": [],
                                    "status": "planned", "eta": None, "eta_by": None, "cost_est": None, "cost": None,
                                    "progress": None, "started": None, "updated": None, "parked": [], "parked_at": None,
                                    "asks": [], "session": None, "host": None, "harness": None, "check": None,
                                    "waiting_for": None, "milestone": None, "blueprint": None, **dict.fromkeys(SENT_FIELDS)})
        if _guarded_repo(e.get("repo")):
            t["guarded_event"] = True  # K6: one event from a guarded repo guards the whole task
        st = e.get("status")
        if st:
            if st == "running" and not t["started"]:
                t["started"] = e.get("t")
            t["status"] = st
        for k in ("progress", "session", "host", "harness", "branch", "pr", "check", "waiting_for"):
            if e.get(k):
                t[k] = e[k]
        if e.get("sent_at") and not e.get("picked_up_at") and t.get("picked_up_at") and e["sent_at"] > t["picked_up_at"]:
            t["picked_up_at"] = t["picked_up_by"] = None   # sent again after a pickup (a hand-back, a rejoin): a new send
        for k in SENT_FIELDS:
            if e.get(k) and not (k.startswith("picked_up") and t.get(k)):   # the first pickup is the send's pickup
                t[k] = e[k]
        if doer(e):
            t["by"] = doer(e)
        if e.get("eta") is not None:
            t["eta"], t["eta_by"] = e["eta"], "child"
        if e.get("cost") is not None:
            t["cost"] = e["cost"]
        for k in ("owns", "live"):
            for x in e.get(k) or []:
                if x not in t[k]:
                    t[k].append(x)
        if "parked" in e:
            t["parked"] = list(e.get("parked") or [])
            t["parked_at"] = e.get("t") if t["parked"] else None
        if e.get("ask"):
            a = asks.setdefault(e["ask"], {"ref": e["ask"], "task": name, "opened": e.get("t"), "answered": None,
                                           "status": st, "summary": e.get("summary"), "reversible": e.get("reversible"),
                                           "recommended": e.get("recommended"), "backend": e.get("backend"),
                                           "mode": e.get("mode")})
            a["status"] = st or a["status"]
            for k in ("summary", "reversible", "recommended", "backend", "mode", "doc"):
                if e.get(k):
                    a[k] = e[k]
            # skipper-resilience S5: who the last relay went to (bin/ask relay's `to`, set or None),
            # when, and whether the skipper escalated it — read by the re-hail and the deaf rule
            if "to" in e:
                a["to"], a["relayed_at"], a["to_host"] = e.get("to"), e.get("t"), e.get("to_host")
            if e.get("escalated"):   # `helm skipper --escalate`: one ask the skipper handed the owner
                a["escalated"] = True
        if e.get("answered"):
            a = asks.get(e["answered"])
            if a:
                a["answered"] = e.get("t")
                a["answer_from"] = e.get("from")
            t["parked"] = [p for p in t["parked"] if not e["answered"].endswith("#" + p)]
        if not set(e) <= SEND_ONLY:   # a send's mark or pickup is not the task's own news (the board's ages)
            t["updated"] = e.get("t")
    for a in asks.values():
        t = tasks.get(a["task"])
        if t is None:
            continue
        a["open"] = not a["answered"] and t["status"] not in ENDED
        t["asks"].append(a)
    # blockers and the estimate
    for t in tasks.values():
        b = []
        for d in t["deps"]:
            dep = tasks.get(d)
            if not dep or dep["status"] not in DONE:
                b.append("waits on %s" % d)
        if t.get("waiting_for"):
            b.append(t["waiting_for"])
        b += ["open ask %s" % a["ref"] for a in t["asks"] if a["open"]]
        t["blockers"] = b
        t["est_to_go"], t["est_kind"] = _estimate(t, at)
        t["overrun"] = bool(t["eta"] and t["status"] not in ENDED and at > float(t["eta"]))
        t["guarded"] = _guarded_repo(t.get("repo")) or bool(t.pop("guarded_event", False))
        t["owner"] = t["by"]   # the field's old name, for a page whose script predates S5 (until S8)
        t["send"] = ("picked up" if t.get("picked_up_at") else "sent") if t.get("sent_by") else None
    totals = {"cost": sum(t["cost"] or 0 for t in tasks.values()),
              "est_to_go": sum(t["est_to_go"] or 0 for t in tasks.values()),
              "open_asks": sum(1 for t in tasks.values() for a in t["asks"] if a["open"])}
    ms = []
    for m in plan.get("milestones") or []:
        under = [t for t in tasks.values() if t.get("milestone") == m["name"]]
        ms.append(dict(m, open=sum(1 for t in under if t["status"] not in ENDED)))
    # the ship's card (H1): started at its first apply, else its first running task; due and cost as
    # `helm ship` set them; none of the three on a plan from before rename S5
    first_run = min([t["started"] for t in tasks.values() if t.get("started")] or [None], key=lambda x: x or 0)
    return {"id": plan["id"], "topic": plan.get("topic"), "manager": plan.get("manager") or {},
            "started": plan.get("started") or first_run, "due": plan.get("due"), "cost": plan.get("cost"),
            "space": plan.get("space"), "repo": plan.get("repo"), "created": plan.get("created"),
            "as_of": at, "host": host(), "updated": max([t["updated"] or 0 for t in tasks.values()] + [plan.get("updated") or 0]),
            "tasks": [tasks[k] for k in _order(plan, tasks)], "milestones": ms, "totals": totals,
            # public() keys the guarded tokens with it and drops it; a plan from before the salt
            # falls back to its id until the manager's next write adds one (save_plan)
            "guard_salt": plan.get("salt") or plan["id"]}


# A blueprint block's fields in plan.json (bin/plan task; docs/orchestration-orca-2026-10-15.md Q1): what
# the plan keeps that Orca has no slot for. Nested under "blueprint" in state(): its `host` is where the
# block runs, not the host a report came from (the task's own `host`).
BLOCK_FIELDS = ("provider", "agent", "host", "done_when", "orca_task", "orca_dispatches")


def _block_fields(t):
    got = {k: t[k] for k in BLOCK_FIELDS if t.get(k) not in (None, "", [])}
    if t.get("ship"):
        got["name"] = t["ship"]
    return got or None


def _order(plan, tasks):
    declared = list((plan.get("tasks") or {}).keys())
    return declared + [k for k in tasks if k not in declared]


def _estimate(t, at):
    """(dollars to completion, 'manager' | 'est.' | None): the manager's estimate when set, else burn
    rate × the time left to the ETA (cost so far ÷ elapsed × remaining), marked est."""
    if t["status"] in ENDED:
        return 0.0, None
    if t.get("cost_est") is not None:
        return max(0.0, float(t["cost_est"]) - float(t["cost"] or 0)), "manager"
    # a burn rate needs some history: seconds in, $0.40 extrapolated to an hour read as $720
    if t.get("cost") and t.get("started") and t.get("eta") and at - float(t["started"]) >= MIN_BURN:
        elapsed = at - float(t["started"])
        remain = max(0.0, float(t["eta"]) - at)
        return float(t["cost"]) / elapsed * remain, "est."
    return None, None


def public(st):
    """The copy that may leave the Mac (K6): guarded tasks lose their text, raw tails never ride."""
    out = json.loads(json.dumps(st))
    salt = str(out.pop("guard_salt", None) or out.get("id") or "")
    # A guarded task's id is often its topic ("tax-return"): it leaves as guarded-<hex>, a hash of
    # the id keyed by the plan's private salt. A counter (guarded-1, -2…) would renumber: plan.json
    # keeps its tasks in sorted keys, so a new task can sort before an old one. The salt keeps a
    # guessed topic from being checked against the token. Every reference to the id (a sibling's
    # deps and "waits on" blocker, the timeline's bars, which read this copy) takes the token too
    # (second review, 2026-10-11).
    import hashlib
    tokens = {t["id"]: "guarded-" + hashlib.sha256((salt + "\0" + t["id"]).encode()).hexdigest()[:8]
              for t in out["tasks"] if t.get("guarded")}
    for t in out["tasks"]:
        t["deps"] = [tokens.get(d, d) for d in t.get("deps") or []]
        t["blockers"] = ["waits on %s" % tokens[b[9:]] if b.startswith("waits on ") and b[9:] in tokens else b
                         for b in t.get("blockers") or []]
    for t in out["tasks"]:
        t.pop("tail", None)
        # a send's sender (a session id), its host and the lease holder (`skipper · <scope>`, often a
        # confidential repo's name) stay on this Mac, as an ask's `to` does; `send` and its times leave
        for k in ("sent_by", "sent_from", "picked_up_by"):
            t.pop(k, None)
        for a in t.get("asks") or []:
            # a path on this Mac, a session id and a host (S5's re-hail and deaf rule read them): no
            # reader of the copy needs them
            for k in ("doc", "to", "to_host"):
                a.pop(k, None)
        if t.get("guarded"):
            t["id"] = tokens[t["id"]]
            t["title"] = "a task in a guarded repo"
            t["progress"] = None
            t["owns"], t["live"] = [], []
            t["branch"] = t["pr"] = t["waiting_for"] = t["check"] = None
            t["blueprint"] = t["block"] = None   # a done_when names a path, a ship its topic, a block its id
            t["repo"] = "guarded"
            # a person's name says nothing of the repo; a session's name is made from its cwd
            # (`<repo>-3`), so only a person's name (people()) stays
            if (t.get("by") or "").lower() not in people():
                t["by"] = t["owner"] = None
            # a blocker quotes an ask's ref or a waiting_for text: counted, never quoted
            t["blockers"] = ["guarded"] * len(t.get("blockers") or [])
            for a in t["asks"]:
                a["summary"] = "an ask in a guarded session"
                a["ref"] = "guarded"
                a["recommended"] = a["reversible"] = None
    return out


# ---------------------------------------------------------------------------- cost

def transcript(session_id):
    """The session's transcript under ~/.claude/projects (one directory for all logins)."""
    root = Path(os.environ.get("PLAN_PROJECTS_DIR") or Path(os.environ.get("HOME") or Path.home()) / ".claude/projects")
    try:
        hits = list(root.glob("*/%s.jsonl" % session_id))
    except OSError:
        return None
    return hits[0] if hits else None


def session_cost(session_id):
    """List dollars spent so far by one session, priced with bin/usage-report's PRICES and cost_of —
    one price table. None when the transcript is not on this Mac, or usage-report is not (plumb's,
    G26: no cost, never a crash)."""
    p = transcript(session_id)
    ur_path = peer("usage-report")
    if not p or not ur_path:
        return None
    from importlib.machinery import SourceFileLoader
    try:
        ur = SourceFileLoader("usage_report", str(ur_path)).load_module()
    except Exception:
        return None
    seen = {}
    with p.open(errors="replace") as fh:
        for line in fh:
            if '"usage"' not in line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") != "assistant":
                continue
            msg = d.get("message") or {}
            u = msg.get("usage")
            if not u or msg.get("model") == "<synthetic>":
                continue
            key = d.get("requestId") or d.get("uuid")
            out = u.get("output_tokens") or 0
            if key in seen and seen[key][1]["output_tokens"] >= out:
                continue  # a streamed reply's earlier blocks
            cc = u.get("cache_creation") or {}
            w5 = cc.get("ephemeral_5m_input_tokens")
            w1 = cc.get("ephemeral_1h_input_tokens")
            if w5 is None and w1 is None:
                w5, w1 = u.get("cache_creation_input_tokens") or 0, 0
            seen[key] = (msg.get("model"), {"input": u.get("input_tokens") or 0, "output_tokens": out,
                                            "cr": u.get("cache_read_input_tokens") or 0, "w5": w5 or 0, "w1": w1 or 0})
    return sum(ur.cost_of(m, v["input"], v["output_tokens"], v["cr"], v["w5"], v["w1"]) for m, v in seen.values())


def tail_lines(session_id, n=20, cap=2048):
    """The last n assistant text lines of a session (the reader yolo_launch uses), 2 KB at most."""
    p = transcript(session_id)
    if not p:
        return []
    texts = []
    with p.open(errors="replace") as fh:
        for line in fh:
            if '"assistant"' not in line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") != "assistant":
                continue
            for c in (d.get("message") or {}).get("content") or []:
                if isinstance(c, dict) and c.get("type") == "text" and c.get("text"):
                    texts += [x for x in c["text"].splitlines() if x.strip()]
    out, size = [], 0
    for x in reversed(texts[-n:]):
        size += len(x) + 1
        if size > cap:
            break
        out.append(x)
    return list(reversed(out))


# ---------------------------------------------------------------------------- people and places

def columns():
    """The board's two people columns: the owner's (`Needs <owner>`), then everyone else's — the
    second person's name when `helm/people` names exactly two, else `Needs others`."""
    p = people()
    rest = p[1:]
    return ("Needs %s" % display(p[0]), "Needs %s" % (display(rest[0]) if len(rest) == 1 else "others"))


def column_for(person):
    """A person's board column: the owner's for the first of people(), the second for anyone else."""
    return columns()[0 if (person or "").lower() == people()[0] else 1]


def ssh_peers():
    """{host: ssh alias} of the hosts this Mac reads over ssh: the config dir's `wharf-runs/ssh`
    lines (`<host>:<alias>`, as orca-host and pickup read them); {} without the key or the core."""
    try:
        lines = _common().config_lines("wharf-runs/ssh") or []
    except Exception:
        return {}
    return dict(l.split(":", 1) for l in lines if ":" in l)
