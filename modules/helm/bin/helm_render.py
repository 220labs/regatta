"""Helm's renderings: a ship's page and the board (docs/session-asks-2026-10-09.md section 3;
B6 the page, the board and the deploy, B7 the timeline, B8 the Artifact line).

One static page for every target: index.html carries its script and a first snapshot of its state,
and reads `state.json` beside it every 30 s (one fetch, no reload: scroll and toggles survive) —
so the local server, a spacesheep deploy and an Artifact serve the same file (the owner: "html pages
with internal storage is a good path"). The script draws everything, the timeline's SVG included:
no library, no second renderer to keep in step.

Targets (settings/surfaces.json `helm.render`, `helm.live`; the `plan` row before rename S5, read too):
    local     ~/Library/Caches/plan/<id>/ — index.html, state.json, and tails.json (the raw log
              tail, never deployed); served on 127.0.0.1 by `bin/helm open` (a stdlib static
              server of its own: memo's server is per form and shares nothing with a static root)
    sheep     the same two files (no tails) by the CLI's deploy, one space per plan, its uuid kept
              in plan.json `space` — the Talk address a run relays to (R4). Live: `stream` when a
              `spacesheep stream plans/<id>` process runs here; else `redeploy`, at most one deploy
              a minute, on each report
    artifact  a line for the manager to act on, only where this login is known to have the tool
              (B0h's fact file, ~/Library/Caches/plan/artifact-<login>.json); absent = unknown = no
              line, nothing owed

What may leave the Mac is helmlib.public() — guarded repos' text gone, no tails (K6). Stdlib only,
Python 3.9, nothing of Claude's imported. PLAN_CACHE_DIR moves the files; PLAN_NO_DEPLOY,
PLAN_NO_GH, PLAN_NO_MEMO and PLAN_NO_PEER (no ssh to a peer for the stall cards) keep a test off the network
and the disk at large.
"""
import datetime as dt
import glob
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import helmlib  # noqa: E402
import surfaces  # noqa: E402

# The two people columns come first, the owner's and everyone else's (helmlib.columns(): the config
# dir's `regatta/owner` and `helm/people`); the page skips the second while it is empty. Intake holds the
# desk's open issues (lighthouse-ops S4), grouped by kind, until S5's classifier sends each where it goes;
# it is last because the page colours a card by its column's index (.c0-.c6).
OTHER_COLUMNS = ("Blocked", "Running", "Parked / Relayed", "Done today", "Intake")


def board_columns():
    return helmlib.columns() + OTHER_COLUMNS
DEPLOY_EVERY = 60  # seconds: a burst of reports is one deploy


def cache_root():
    return Path(os.environ.get("PLAN_CACHE_DIR") or Path(os.environ.get("HOME") or Path.home()) / "Library/Caches/plan")


def _write(p, text):
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".%d.tmp" % os.getpid())
    tmp.write_text(text)
    tmp.replace(p)


def page(state, title):
    """The one page: its script, its first snapshot (for an Artifact or a file:// open)."""
    snap = json.dumps(state, ensure_ascii=False, sort_keys=True).replace("</", "<\\/")
    return PAGE.replace("{{TITLE}}", html.escape(title)).replace("{{STATE}}", snap)


# ---------------------------------------------------------------------------- the plan page

def render(pid, deploy=None):
    """Write the local files; deploy per the live backend (deploy=None), now (True) or never (False).
    Returns the lines to print."""
    st = helmlib.state(pid)
    pub = dict(helmlib.public(st), kind="plan")
    d = cache_root() / pid
    _write(d / "state.json", json.dumps(pub, ensure_ascii=False, sort_keys=True))
    _write(d / "index.html", page(pub, "Helm · %s" % (st.get("topic") or pid)))
    tails = {t["id"]: helmlib.tail_lines(t["session"]) for t in st["tasks"] if t.get("session") and not t.get("guarded")}
    _write(d / "tails.json", json.dumps(tails, ensure_ascii=False))
    out = ["local: %s" % (d / "index.html")]
    rows = surfaces.load()["helm"]
    if "sheep" in rows["render"]:
        out.append(sheep_line(pid, st, d, deploy, rows))
    if "artifact" in rows["render"]:
        a = artifact_line(d)
        if a:
            out.append(a)
    return out


def stream_running(pid):
    """A `spacesheep stream plans/<id>` process runs here and the server takes its values. The CLI
    (1.31.0's lib/stream.js, read 2026-10-24) exits 3 only on a 401 or 403; any other refusal, such
    as Streams' `plan_required` for an account without Max (its HTTP status unverified), is logged
    and the process keeps running. So a process found is checked against the plan (no Pro, no Max)
    and the server's own list: a stream absent or silent for STREAM_STALE reads as not live, and the
    page falls back to redeploy. The verdict is kept STREAM_RECHECK, so a burst of reports asks once."""
    r = subprocess.run(["pgrep", "-f", "spacesheep stream plans/%s" % pid], capture_output=True, text=True)
    if r.returncode != 0:
        return False
    return stream_taken(pid)


STREAM_STALE = 120     # s: the hint's --every is 30 s; four missed values is a refused stream
STREAM_RECHECK = 300


def stream_taken(pid):
    import asklib
    plan = asklib.sheep_plan(cached_only=True) or {}
    if plan.get("pro") is False:
        return False
    memo = cache_root() / pid / ".stream-checked"
    try:
        at, ok = memo.read_text().split()
        if time.time() - float(at) < STREAM_RECHECK:
            return ok == "1"
    except (OSError, ValueError):
        pass
    cli = asklib.sheep_cli()
    ok = True   # the list could not be read (offline, no CLI, a timeout): trust the process, as before
    if cli:
        try:
            q = subprocess.run([cli, "streams", "plans/%s" % pid, "--json"], capture_output=True, text=True,
                               env=asklib.sheep_env(cli), timeout=20)
            # the CLI's list() throws the server's `body.error`, else `HTTP <status>`, and exits 1 (3 on
            # a refused key): any of those is a stream the server does not take. Only a fetch that never
            # reached the server ("fetch failed", Node's own words) leaves the process trusted.
            if q.returncode:
                ok = bool(re.search(r"fetch failed|could not reach", q.stderr + q.stdout, re.I))
            else:
                rows = json.loads(q.stdout or "[]")
                row = next((x for x in rows if isinstance(x, dict) and x.get("path") == "plans/%s" % pid), None)
                ok = bool(row and row.get("last_at") and time.time() - float(row["last_at"]) / 1000 < STREAM_STALE)
        except (OSError, ValueError, TypeError, subprocess.TimeoutExpired):
            pass
    _write(memo, "%d %d" % (time.time(), ok))
    return ok


def sheep_line(pid, st, d, deploy, rows):
    if os.environ.get("PLAN_NO_DEPLOY"):
        return "sheep: off (PLAN_NO_DEPLOY)"
    if deploy is False:
        return "sheep: not deployed (asked not to)"
    live = rows.get("live")
    if deploy is None:
        if live == "stream" and stream_running(pid):
            return "sheep: live by stream plans/%s" % pid
        if not st.get("space"):
            hint = ""
            if live == "stream":
                hint = "; live: spacesheep stream plans/%s --every 30s -- %s/libexec/helm render %s --json" % (pid, HERE.parent, pid)
            return "sheep: not deployed yet (bin/helm render --deploy)" + hint
        if (rows.get("live_fallback") or "redeploy") != "redeploy" and live != "redeploy":
            return "sheep: no live backend runs (helm.live %s)" % live
        try:
            last = float((d / ".deployed").read_text())
        except (OSError, ValueError):
            last = 0
        if time.time() - last < DEPLOY_EVERY:
            return "sheep: deployed %ds ago — the next report deploys" % (time.time() - last)
        held = budget_hold()
        if held:
            return "sheep: " + held
    return deploy_plan(pid, st, d)


def deploy_dir(src, files, space=None, title=None, message=None, by="helm"):
    """The CLI's deploy of `files` from `src` (a folder of its own: never the tails). Returns
    (uuid, url) or raises RuntimeError with the CLI's words, a cap refusal named as such; each
    publish goes in the core's deploy log as `by`."""
    sys.path.insert(0, str(HERE))
    import asklib
    cli = asklib.sheep_cli()
    if not cli:
        raise RuntimeError("no spacesheep CLI on this Mac")
    out = src / "deploy"
    out.mkdir(parents=True, exist_ok=True)
    for f in files:
        _write(out / f, (src / f).read_text())
    cmd = [cli, "deploy", str(out), "--no-manifest", "--json"]
    cmd += ["--space", space] if space else ["--title", title or src.name]
    if message:
        cmd += ["-m", message]
    r = subprocess.run(cmd, capture_output=True, text=True, env=asklib.sheep_env(cli), timeout=120)
    try:
        res = json.loads(r.stdout)
    except ValueError:
        res = {}
    uuid = res.get("uuid") or res.get("id") or res.get("space_id")
    c = asklib._common()
    if r.returncode or not uuid:
        err = res.get("message") or res.get("error") or r.stderr.strip()[-200:] or "exit %d" % r.returncode
        if c and hasattr(c, "sheep_cap_refusal") and c.sheep_cap_refusal(err):
            # kept in the log with its retry, which pauses helm's redeploys (budget_hold) until then
            c.sheep_record(by, ok=False, what=title or space or src.name, err=err)
            err = "%s — %s" % (c.sheep_cap_line(c.sheep_budget(asklib.sheep_plan())), err)
        raise RuntimeError(err)
    if c and hasattr(c, "sheep_record"):
        c.sheep_record(by, what=title or space or src.name)
    return uuid, res.get("url")


# The publish budget (the core's sheep_budget(): this Mac's deploys in 24 h against its part of the
# account's cap). Free allows 400 a day and one active ship alone can redeploy 1,440 times, so above
# helm's share the board and the ship pages stop redeploying and leave the rest to keel's answer
# pages, which never skip. A cap refusal from the server (kept in the log with its retry) pauses them
# the same way. Crossing the line costs the board one last deploy that carries the note (its header),
# and the pause is said once in the poll's log; the page keeps updating locally (helm open).
PAUSED = "sheep-paused"


def budget_hold(st=None):
    """None when a redeploy may go; else the reason it may not. Only the board (`st`, its state)
    writes or clears the pause marker: its crossing deploy carries the note into the header (that one
    deploy goes, unless the server already refused one), and its resume clears it. A ship page (no
    `st`) only holds: a ship crossing first and writing the marker left the board's own crossing
    unseen, so the board never said the pause (landing review)."""
    import asklib
    c = asklib._common()
    if not c or not hasattr(c, "sheep_budget"):
        return None
    b = c.sheep_budget(asklib.sheep_plan())
    refused = float(b.get("refused_until") or 0) > time.time()
    mark = cache_root() / PAUSED
    if b["count"] < b["helm_limit"] and not refused:
        if st is not None:
            try:
                mark.unlink()
            except OSError:
                pass
            st.setdefault("header", {})["sheep"] = None   # drawn before this check cleared the pause
        return None
    note = budget_note(b, refused)
    if st is None:
        return note
    if not mark.exists():
        _write(mark, json.dumps({"at": time.time(), "count": b["count"], "limit": b["helm_limit"], "note": note}))
        st.setdefault("header", {})["sheep"] = note
        return note if refused else None   # refused: the server would refuse the note's deploy too
    return note


def paused_note():
    """The pause's note while it holds (the marker budget_hold writes), else None."""
    try:
        return json.loads((cache_root() / PAUSED).read_text()).get("note")
    except (OSError, ValueError, AttributeError):
        return None


def talk_note():
    """The relay's own line when the cached plan has no Talk (the core's sheep_talk_refusal), else None.
    Cache only: drawing the board never calls the CLI."""
    import asklib
    c = asklib._common()
    if not c or not hasattr(c, "sheep_talk_refusal"):
        return None
    return c.sheep_talk_refusal(asklib.sheep_plan(cached_only=True))


def budget_note(b, refused=False):
    import asklib
    words = asklib._common().sheep_plan_words(b["plan"])
    if refused:
        return ("redeploys paused: spacesheep refused a publish for the account's 24-hour cap (%d a day on %s), "
                "until %s — the local board is current (regatta helm board)"
                % (b["cap"], words, time.strftime("%H:%M", time.localtime(float(b["refused_until"])))))
    return ("redeploys paused: %d of this Mac's %d publishes in 24 h (spacesheep %s caps the account at %d a day, "
            "shared by %d machines; keel's answer pages keep the rest) — the local board is current (regatta helm board)"
            % (b["count"], b["helm_limit"], words, b["cap"], b["machines"]))


def deploy_plan(pid, st, d):
    try:
        uuid, url = deploy_dir(d, ("index.html", "state.json"), space=st.get("space"),
                               title="Helm · %s" % (st.get("topic") or pid), message=time.strftime("%Y-%m-%d %H:%M"), by="helm-ship")
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
        return "sheep: deploy failed — %s" % e
    _write(d / ".deployed", str(time.time()))
    if not st.get("space"):
        with helmlib.locked(pid):
            plan = helmlib.load_plan(pid)
            plan["space"] = uuid
            plan["space_url"] = url
            helmlib.save_plan(plan)
    return "sheep: %s" % (url or uuid)


def artifact_line(d):
    """B8: the manager's own step — only where this login is known to have the Artifact tool (B0h)."""
    login = Path(os.environ.get("CLAUDE_CONFIG_DIR") or "~/.claude").name
    try:
        known = json.loads((cache_root() / ("artifact-%s.json" % login)).read_text()).get("artifact")
    except (OSError, ValueError):
        return None
    if not known:
        return None
    return ("artifact: update — publish %s (its snapshot is inside) to the plan's Artifact at your next turn; "
            "a model's step, so it lags to your turns (K8)" % (d / "index.html"))


# ---------------------------------------------------------------------------- the local server

def open_page(pid=None):
    """The local page's URL on a stdlib static server rooted at the cache (started once, detached;
    it ends after two idle hours). VS Code's Simple Browser takes a 127.0.0.1 link clicked in the
    panel; nothing opens that tab from a script (read from Simple Browser's package.json, VS Code
    2026-10-03: no vscode:// handler)."""
    root = cache_root()
    pf = root / ".server.json"
    try:
        s = json.loads(pf.read_text())
        os.kill(int(s["pid"]), 0)
        port = s["port"]
    except (OSError, ValueError, KeyError, TypeError):
        import socket
        sk = socket.socket()
        sk.bind(("127.0.0.1", 0))
        port = sk.getsockname()[1]
        sk.close()
        p = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "serve", str(root), str(port)],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        _write(pf, json.dumps({"pid": p.pid, "port": port}))
    return "http://127.0.0.1:%d/%s/index.html" % (port, pid or "overview")


def serve(root, port, idle=2 * 3600):
    import functools
    import http.server
    last = [time.time()]

    class H(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def end_headers(self):
            self.send_header("Cache-Control", "no-store")
            super().end_headers()

        def do_GET(self):
            last[0] = time.time()
            return super().do_GET()

    srv = http.server.ThreadingHTTPServer(("127.0.0.1", int(port)), functools.partial(H, directory=str(root)))
    srv.timeout = 60
    while time.time() - last[0] < idle:
        srv.handle_request()


# ---------------------------------------------------------------------------- the overview

def _today(t):
    return bool(t) and dt.date.fromtimestamp(float(t)) == dt.date.today()


def _card(kind, title, column, **kw):
    c = {"kind": kind, "title": title, "column": column}
    c.update({k: v for k, v in kw.items() if v not in (None, "", [])})
    return c


def plan_cards(st):
    cards = []
    plan = st.get("topic") or st["id"]
    owner_col = helmlib.columns()[0]
    for t in st["tasks"]:
        human = t.get("kind") == "human"
        by = helmlib.doer(t) or ""
        s = t["status"]
        if human and s not in helmlib.ENDED:
            col = (helmlib.column_for(by) if by.lower() in helmlib.people()
                   else "Running" if s == "running" else "Blocked")
            if t["blockers"] and col.startswith("Needs"):
                col = "Blocked"
        elif s in helmlib.DONE:
            col = "Done today" if _today(t.get("updated")) else None
        elif s in ("relayed", "parked"):
            col = "Parked / Relayed"
        elif s == "waiting":
            col = owner_col
        elif s in ("blocked", "failed") or (s == "planned" and t["blockers"]):
            col = "Blocked"
        elif s == "running":
            col = "Running"
        else:
            col = None
        if not col:
            continue
        cards.append(_card("human" if human else "task", t["title"], col, plan=plan, plan_id=st["id"],
                           repo=Path(str(t.get("repo") or "")).name, by=by or ((t.get("session") or "")[:8]),
                           status=s, eta=t.get("eta"), cost=t.get("cost"), est=t.get("est_to_go"),
                           blockers=t["blockers"], parked=t["parked"], updated=t.get("updated"),
                           overrun=t.get("overrun"), guarded=t.get("guarded")))
        for a in t["asks"]:
            if a["open"]:
                # a held dnd item and any ask in mode ask wait on the owner alone: no skipper answers them (S5)
                acol = owner_col if s == "waiting" or a.get("mode") in ("ask", "dnd") else "Parked / Relayed"
                repo = Path(str(t.get("repo") or "")).name
                course, github = ask_links(repo, t.get("branch"), a["ref"].rpartition("#")[0])
                cards.append(_card("ask", a.get("summary") or a["ref"], acol, plan=plan, plan_id=st["id"], ref=a["ref"],
                                   repo=repo, reversible=a.get("reversible"),
                                   recommended=a.get("recommended"), updated=a.get("opened"), guarded=t.get("guarded"),
                                   mode=a.get("mode"), held="held for %s (dnd)" % helmlib.display(helmlib.people()[0]) if a.get("mode") == "dnd" else None,
                                   course=course, github=github))
    return cards


# skipper-modes S5: every ask card carries `keel line`'s two links that cost no deploy — the doc's
# course page as its pin already holds it (keel's sheep pins: `keel line` deploys, the board never
# does) and GitHub's read view of the doc on its branch (keel's urls(), the repo's `github` in the
# registry). One that cannot be read is left out, never guessed.
_KEEL = []


def _keel():
    if not _KEEL:
        p = helmlib.peer("keel")
        try:
            from importlib.machinery import SourceFileLoader
            _KEEL.append(SourceFileLoader("keel_board", str(p)).load_module() if p else None)
        except Exception:
            _KEEL.append(None)
    return _KEEL[0]


def _github_slug(repo):
    try:
        p = helmlib._common().repos_json()
        r = (json.loads(p.read_text()).get("repos") or {}).get(repo) if p else None
    except (OSError, ValueError, AttributeError):
        return None
    return r.get("github") if isinstance(r, dict) else None


def ask_links(repo, branch, rel):
    """(course, github) for a doc on a branch, each None when it cannot be read."""
    if not (repo and branch and rel):
        return None, None
    k = _keel()
    course = github = None
    if k is not None:
        try:
            course = (k.pins().get("%s@%s:%s" % (repo, branch, rel)) or {}).get("url")
        except Exception:
            course = None
        slug = _github_slug(repo)
        if slug:
            try:
                github = k.urls(slug, branch, rel)[0]
            except Exception:
                github = None
    return course, github


def poll_cards(states=None):
    """One card per open ask in ask poll's cache, as the board shows them (board-cleanup S1): a template's
    or a test's D-items are none, nor a branch whose PR is merged or closed (the cache may hold rows the
    poll's own filter did not see: carried rows, an older poll's), and one doc item on two branches is one
    card, the newest branch's. The cache keeps every row: keel's lookout watches it per branch."""
    p = Path(os.environ.get("ASK_CACHE_DIR") or Path(os.environ.get("HOME") or Path.home()) / "Library/Caches/ask") / "asks.json"
    try:
        d = json.loads(p.read_text())
    except (OSError, ValueError):
        return []
    rows = [a for a in d.get("asks") or [] if isinstance(a, dict) and not helmlib.not_an_ask(a.get("rel"))
            and not helmlib.branch_ended(states or {}, a.get("repo"), a.get("branch"), a.get("sha"), a.get("t"))]
    out = []
    for a in helmlib.newest_per_item(rows):
        course, github = ask_links(a.get("repo"), a.get("branch"), a.get("rel"))
        out.append(_card("ask", a.get("title") or a.get("item"), helmlib.columns()[0], repo=a.get("repo"), ref="%s#%s" % (a.get("rel"), a.get("item")),
                         branch=a.get("branch"), reversible=a.get("reversible"), recommended=a.get("recommended"),
                         course=course, github=github))
    return out


def memo_cards(skip_docs):
    if os.environ.get("PLAN_NO_MEMO"):
        return []
    try:
        keel = helmlib.peer("keel")   # keel's: the docs' cards; none without it
        if not keel:
            return []
        r = subprocess.run([sys.executable, str(keel), "list", "--root", str(Path.home() / "projects"), "--json"],
                           capture_output=True, text=True, timeout=120)
        rows = json.loads(r.stdout or "[]")
    except (subprocess.TimeoutExpired, ValueError, OSError):
        return []
    out = []
    for r in memo_rows(rows):
        if not r.get("open") or Path(r["path"]).name in skip_docs:
            continue
        out.append(_card("memo", r.get("title") or Path(r["path"]).name, helmlib.columns()[0], repo=(r.get("repo") or "").split("@")[0],
                         doc=r["path"], open=r["open"], review=r.get("review"), keel=keel_text(r.get("keel"), r.get("files")),
                         guarded=helmlib.guarded((r.get("repo") or "").split("/")[0].split("@")[0])))
    return out


# The week's /embark sitting (the owner, 2026-10-24: "presented on helm dashboard as its course doc"):
# aurora's weekly-run writes docs/embark/embark-<date>.md in regatta after the sextant, and the newest
# open one leads the owner's column, labelled Embark — a memo card (this Mac's `keel list`) or a
# lookout card (`repo@branch:docs/embark/…`), this Mac's or a peer's: the Mac that runs the sextant
# writes it on its own branch, and the other Mac's board shows it once a lookout card exists for it
# (an answer event); until then only the writing Mac's board does.
EMBARK_RE = re.compile(r"(?:^|[/:])docs/embark/embark-(\d{4}-\d\d-\d\d)\.md$")


def embark_first(cards):
    """`cards` with the newest embark memo's card first, titled and labelled Embark; unchanged when
    the owner's column holds none. Equal dates keep the first found: a memo card, read before the
    lookout's."""
    owner, best = helmlib.columns()[0], None
    for c in cards:
        m = EMBARK_RE.search(str(c.get("doc") or "")) if c.get("column") == owner and c.get("kind") in ("memo", "lookout") else None
        if m and (best is None or m.group(1) > best[0]):
            best = (m.group(1), c)
    if best is None:
        return cards
    c = best[1]
    c["label"] = "Embark"
    if not (c.get("course") or c.get("github")):
        doc = str(c.get("doc") or "")
        repo = branch = rel = None
        if "@" in doc and ":" in doc:   # a lookout card's repo@branch:path
            head, rel = doc.split(":", 1)
            repo, branch = head.split("@", 1)
        else:                           # a memo card's absolute path: the branch is its checkout's
            try:
                m = EMBARK_RE.search(doc)
                rel = "docs/embark/" + doc.rsplit("/", 1)[-1] if m else None
                branch = subprocess.run(["git", "-C", str(Path(doc).parent), "rev-parse", "--abbrev-ref", "HEAD"],
                                        capture_output=True, text=True, timeout=10).stdout.strip() or None
                repo = c.get("repo")
            except (OSError, subprocess.TimeoutExpired):
                pass
        course, github = ask_links(repo, branch, rel)
        if course:
            c["course"] = course
        if github:
            c["github"] = github
    if not str(c.get("title") or "").startswith("Embark"):
        c["title"] = "Embark %s — %s" % (best[0], c.get("title") or "")
    return [c] + [x for x in cards if x is not c]


# Run on a peer over ssh (`python3 -`): find its core as lib/find_core.py does (its source is sent,
# as stalls sends its probe), then print that host's `keel lookout --status --json`. Exit 2 without
# a core, 3 without keel; either is no cards from it.
PEER_LOOKOUT_MAIN = """
sys.path.insert(0, hooks())
import common, subprocess
k = common.tool("keel")
if not k:
    sys.exit(3)
r = subprocess.run([sys.executable, str(k), "lookout", "--status", "--json"], capture_output=True, text=True, timeout=50)
sys.stdout.write(r.stdout)
sys.exit(r.returncode)
"""
# a lookout's card that only says another host's own lookout acts: once that host's cards are read,
# the board shows its card instead (S6 landing review, 19). Keel's wording, matched loosely; a
# rewording shows both cards again, never hides one.
OTHER_LOOKOUT_RE = re.compile(r"\bits (own )?lookout (acts|starts the run)\b")


def peer_lookout_rows():
    """{host: {"cards": [card rows], "armed": bool}} of each peer's lookout (S6 landing review, 19):
    the build Mac's cards sit in its own lookout.jsonl. Read as stall_cards reads the peer — stalls.peers()
    (STALLS_PEERS), over STALLS_SSH, one ssh each, BatchMode — and only a host that answered is in the
    result. `armed` is the peer's own word: a disarmed lookout answers with no cards and acts on
    nothing (S11b finish review). PLAN_NO_PEER keeps a test off ssh."""
    if os.environ.get("PLAN_NO_PEER"):
        return {}
    try:
        import stalls
        hosts = stalls.peers()
        src = "__file__ = '/peer/probe/lib/find_core.py'\n" + (Path(__file__).resolve().parent.parent / "lib" / "find_core.py").read_text() + PEER_LOOKOUT_MAIN
    except Exception:
        return {}
    ssh = os.environ.get("STALLS_SSH") or "ssh"
    out = {}
    for h, alias in sorted(hosts.items()):
        try:
            r = subprocess.run([ssh, "-o", "BatchMode=yes", "-o", "ConnectTimeout=%d" % stalls.SSH_TIMEOUT, alias, "python3 -"],
                               input=src, capture_output=True, text=True, timeout=60)
            st = json.loads(r.stdout or "{}") if r.returncode == 0 else None
            rows = st.get("cards") if st is not None else None
        except (subprocess.TimeoutExpired, ValueError, OSError, AttributeError):
            continue
        if isinstance(rows, list):
            out[h] = {"cards": rows, "armed": st.get("armed") is True}
    return out


def branch_host(doc):
    """The host a lookout card's `repo@claude/<host>/…:path` doc names, or None."""
    parts = str(doc or "").partition("@")[2].partition(":")[0].split("/")
    return parts[1] if len(parts) > 2 and parts[0] == "claude" else None


def lookout_cards(states=None):
    """The lookout's open cards (crosstalk S6): a doc it could not hail or start a run for, a branch on
    another host — `keel lookout --status --json`, one card each in the owner's column (the lookout
    names no other). Its doc is `repo@branch:path`; the card text is the why. Each peer's cards too,
    read over ssh (S6 landing review, 19), their why led by the host; a peer read drops this Mac's
    cards that only say that host's own lookout acts. PLAN_KEEL is a test's stand-in; PLAN_NO_MEMO
    keeps a test off the real state. No keel, an old keel without the flag, a keel that fails, a peer
    that does not answer: no cards from it, never the board's failure. A card on a branch whose PR is
    merged or closed is no card (board-cleanup S1: 23 of 31 on one Mac, 2026-10-26); the lookout's own
    state keeps it."""
    rows = []
    try:
        keel = os.environ.get("PLAN_KEEL") or (None if os.environ.get("PLAN_NO_MEMO") else helmlib.peer("keel"))
        if keel:
            r = subprocess.run([sys.executable, str(keel), "lookout", "--status", "--json"],
                               capture_output=True, text=True, timeout=60)
            rows = json.loads(r.stdout or "{}").get("cards") or []
    except (subprocess.TimeoutExpired, ValueError, OSError, AttributeError):
        rows = []
    rows = [(None, r) for r in (rows if isinstance(rows, list) else [])]
    peers = peer_lookout_rows()
    # a local "its own lookout acts" card gives way only to the lookout of the host its branch names
    # (claude/<host>/…), and only when that host answered armed: a disarmed peer acts on nothing, so its
    # empty answer replaces no card (S11b finish review). A peer's own such card is about another
    # host's branch — this Mac's, whose cards are already here — and is never shown.
    armed = {h for h, st in peers.items() if st["armed"]}
    rows = [(h, r) for h, r in rows if not (isinstance(r, dict) and OTHER_LOOKOUT_RE.search(str(r.get("card") or ""))
                                            and branch_host(r.get("doc")) in armed)]
    rows += [(h, r) for h, st in peers.items() for r in st["cards"]
             if not (isinstance(r, dict) and OTHER_LOOKOUT_RE.search(str(r.get("card") or "")))]
    out = []
    for h, r in rows:
        if not isinstance(r, dict) or not r.get("card"):
            continue
        doc = str(r.get("doc") or "")
        repo, _, rest = doc.partition("@")
        branch, _, rel = rest.partition(":")
        # the branch's tip, so a branch that moved on past its merged PR keeps its card (as stall_gone)
        tip = next((t for t in (_tip(top, branch) for top in helmlib.repo_tops().get(Path(repo).name, [])) if t[0]),
                   (None, None)) if rest else (None, None)
        if rest and helmlib.branch_ended(states or {}, Path(repo).name, branch, *tip):
            continue
        items = r.get("items") if isinstance(r.get("items"), list) else []
        # the guard fails closed: a doc not in repo@branch:path form is judged by its whole string
        # by: the owner, lower-case, as the human cards' doer field and lane (helmlib D3-A)
        out.append(_card("lookout", " ".join([rel or doc or "?"] + [str(i) for i in items]),
                         helmlib.columns()[0], repo=repo if rest else None, by=helmlib.people()[0], ref=branch, doc=r.get("doc"),
                         evidence=("%s: " % h if h else "") + str(r["card"]), updated=r.get("ts"), host=h,
                         guarded=helmlib.guarded(repo if rest else doc)))
    return out


def memo_rows(rows):
    """`keel list --json`'s rows with a nested set folded into its entry's row (shape section 3: one
    card per entry): the entry's `open` becomes the set's, and `files` its file count. A component
    whose entry is not in the rows stays a card of its own."""
    entries = {str(Path(r["path"]).resolve()): r for r in rows if not r.get("set")}
    out = []
    for r in rows:
        e = entries.get(r.get("set") or "")
        if r.get("set") and e is not None:
            e["open"] = (e.get("open") or 0) + (r.get("open") or 0)
            e["files"] = (e.get("files") or 1) + 1
            continue
        out.append(r)
    return out


def keel_text(k, files=None):
    """`building · 8 of 15 steps` (and `· 4 files` for a set): the Keel word and the plan's count."""
    if not k:
        return None
    s = k.get("word") or ""
    if k.get("steps"):
        s += " · %d of %d steps" % tuple(k["steps"])
    return s + (" · %d files" % files if files and files > 1 else "")


def _dispatch_rc():
    """wharf-runs' dispatch-rc as a module, for typed(): a run record's numbers may be strings on
    disk (B0). ImportError when it is not installed: the callers' own guards take it."""
    from importlib.machinery import SourceFileLoader
    from importlib.util import module_from_spec, spec_from_loader
    path = helmlib.peer("dispatch-rc")
    if not path:
        raise ImportError("dispatch-rc not installed (wharf-runs)")
    loader = SourceFileLoader("dispatch_rc", str(path))
    mod = module_from_spec(spec_from_loader("dispatch_rc", loader))
    loader.exec_module(mod)
    return mod


def _alive(same, st):
    """dispatch-rc's same(), where a record it cannot read (a pid past 2**31, a session file that is
    no object) is a run that is not running, never a traceback that takes the board down."""
    try:
        return same(st)
    except Exception:
        return False


def run_cards():
    """Orphan runs (no manager — every autofinish run), runs the ask guard failed, and sessions at a
    permission prompt (`waitingFor` in the registry): the same unwatched ask by another door."""
    out = []
    runs = Path(os.environ.get("HOME") or Path.home()) / "Library/Logs/claude-weekly/run-seed-runs"
    cutoff = time.time() - 86400
    try:
        rc = _dispatch_rc()
        typed, same = rc.typed, rc.same
    except Exception:   # a broken dispatch-rc must not take the board with it: string starts drop off instead
        typed, same = (lambda st: st), (lambda st: True)
    for f in glob.glob(str(runs / "*.json")):
        try:
            st = typed(json.loads(Path(f).read_text()))
        except (OSError, ValueError):
            continue
        # no record, no start, or one that is no number even after typed(): not a run of the last day
        if not isinstance(st, dict) or not isinstance(st.get("started"), (int, float)) or isinstance(st["started"], bool) \
                or st["started"] < cutoff:
            continue
        repo = Path(st.get("repo") or "").name
        if st.get("ask_guard"):
            out.append(_card("run", "%s: %s" % (st.get("topic"), st["ask_guard"]), "Blocked", repo=repo, updated=st.get("ended"),
                             session=st.get("session"), guarded=helmlib.guarded(repo)))
        # no end recorded is not proof of a run: a crash or a reboot ends one without writing it
        elif not st.get("ended") and not st.get("manager") and _alive(same, st):
            out.append(_card("run", "%s (no skipper)" % st.get("topic"), "Running", repo=repo, by="dispatch",
                             updated=st.get("started"), guarded=helmlib.guarded(repo)))
    sys.path.insert(0, str(HERE))
    import asklib
    for f in glob.glob(str(asklib.sessions_dir() / "*.json")):
        try:
            d = json.loads(Path(f).read_text())
        except (OSError, ValueError):
            continue
        if d.get("status") == "waiting" and asklib.pid_alive(d.get("pid")):
            out.append(_card("permission", "%s waits: %s" % (d.get("name") or d.get("sessionId", "")[:8], d.get("waitingFor") or "input"),
                             helmlib.columns()[0], repo=Path(d.get("cwd") or "").name.split("/")[-1], updated=(d.get("updatedAt") or 0) / 1000,
                             session=d.get("sessionId"),
                             guarded=helmlib.guarded(d.get("cwd") or "")))
    return out


VSCODE_OPEN = "vscode://anthropic.claude-code/open?session=%s"   # pickup's reopen link (its SCHEME)


def waiting_cards(judged, here=None):
    """skipper-modes S5: one card per session on either Mac whose last reply ends on the WAITING line
    — the repo, "waiting on <owner>" and a link, never free text (session-asks K6: the board has other
    readers). The link opens a session of this Mac in VS Code; a peer's opens its branch on GitHub,
    since the laptop's VS Code cannot open a peer's session. And a peer's sessions at a permission
    prompt, which this Mac's registry read (run_cards) cannot see."""
    here = here or helmlib.host()
    out = []
    for w in judged.get("waiting") or []:
        repo = _repo_of_cwd(w.get("cwd"))
        if w.get("host") == here:
            url = VSCODE_OPEN % w.get("session_id")
        else:
            slug = _github_slug(repo)
            url = "https://github.com/%s/tree/%s" % (slug, w["branch"]) if slug and w.get("branch") else None
        out.append(_card("waiting", "%s · waiting on %s" % (session_topic(w), helmlib.display(helmlib.people()[0])), helmlib.columns()[0],
                         repo=repo, by=w.get("host"), url=url, branch=w.get("branch"),
                         session=w.get("session_id"), updated=w.get("since"), guarded=helmlib.guarded(w.get("cwd") or "")))
    for x in judged.get("prompts") or []:
        out.append(_card("permission", "waits at a prompt", helmlib.columns()[0], repo=_repo_of_cwd(x.get("cwd")), by=x.get("host"),
                         session=x.get("session_id"), updated=x.get("updated"), guarded=helmlib.guarded(x.get("cwd") or "")))
    return out


DATE_PREFIX = re.compile(r"^\d{4}-\d\d-\d\d-")


def session_topic(w):
    """What a waiting card names (board-cleanup S1: "waiting on <owner>" alone said nothing): the
    branch's topic (`claude/<host>/<date>-<topic>` → `<topic>`), else the worktree's folder, else the
    session's first 8 characters."""
    b = str(w.get("branch") or "")
    if b and b not in ("main", "master", "HEAD"):
        return DATE_PREFIX.sub("", b.rsplit("/", 1)[-1]) or b
    parts = Path(str(w.get("cwd") or "")).parts
    if "worktrees" in parts and parts.index("worktrees") + 1 < len(parts):
        return parts[parts.index("worktrees") + 1]
    return (w.get("session_id") or "?")[:8]


def _repo_of_cwd(cwd):
    """A session's repo as the board names one: its main checkout's folder, a worktree's too."""
    if not cwd:
        return None
    parts = Path(cwd).parts
    if ".claude" in parts and parts[parts.index(".claude") + 1:parts.index(".claude") + 2] == ("worktrees",):
        parts = parts[:parts.index(".claude")]
    return parts[-1] if parts else None


STALL_DAYS = 7   # a stall older than this is a header count with its age, no card (board-cleanup S1); HELM_STALL_DAYS overrides


def stall_days():
    try:
        return float(os.environ.get("HELM_STALL_DAYS") or STALL_DAYS)
    except ValueError:
        return STALL_DAYS


_BRANCHES = []


def _branches():
    """wharf's hooks/branches.py, for prove(); None without wharf: a stall with no PR then keeps its card."""
    if not _BRANCHES:
        try:
            from importlib.machinery import SourceFileLoader
            p = helmlib.peer("branches.py")
            _BRANCHES.append(SourceFileLoader("wharf_branches", str(p)).load_module() if p else None)
        except Exception:   # noqa: BLE001 — a broken peer costs the content check, never the board
            _BRANCHES.append(None)
    return _BRANCHES[0]


def _tip(top, branch):
    """(sha, commit time) of `branch` in a checkout, its local ref else origin's; (None, None)."""
    for ref in ("refs/heads/" + branch, "refs/remotes/origin/" + branch):
        try:
            r = subprocess.run(["git", "-C", str(top), "log", "-1", "--format=%H %ct", ref, "--"], capture_output=True, text=True, timeout=15)
        except (OSError, subprocess.TimeoutExpired):
            return None, None
        sha, _, t = r.stdout.strip().partition(" ")
        if r.returncode == 0 and sha:
            return sha, float(t or 0)
    return None, None


def landed_on_main(top, branch):
    """wharf's branches.prove() of `branch` against origin's main, or None. Only "every changed file
    identical on main" counts: "no net change" is a branch with nothing to land, and "merged" (its tip on
    main) is also what a branch reset onto main reads (AGENTS.md, the vacuous proofs); a branch merged as
    it stood has a merged PR, which the caller reads first."""
    br = _branches()
    if br is None:
        return None
    try:
        b = br.Branch(branch)
        for side, ref in (("local", "refs/heads/"), ("remote", "refs/remotes/origin/")):
            setattr(b, side, br.out(top, "rev-parse", "-q", "--verify", ref + branch) or None)
        tgt = br.target(top, br.main_branch(top))
        proof = br.prove(top, b, tgt) if b.tips and tgt else None
    except Exception:   # noqa: BLE001
        return None
    return proof if proof and set(proof.split(" / ")) == {"every changed file identical on main"} else None


def stall_gone(s, states):
    """Why a stall is no card: its `(repo, branch)`'s PR is merged or closed, or the branch's content is
    on main though it has no PR (work landed through another branch); None while it may matter."""
    repo, branch = s.get("repo"), s.get("branch")
    if not (repo and branch) or branch in ("main", "master"):
        return None
    tops = helmlib.repo_tops().get(repo, [])
    tip = (None, None)
    for top in tops:
        tip = _tip(top, branch)
        if tip[0]:
            break
    ended = helmlib.branch_ended(states, repo, branch, *tip)
    if ended:
        return "PR " + ended
    if any(helmlib.pr_state(states.get(str(t)), branch)[1] for t in tops):
        return None   # an open PR, or one the branch moved past: live work's claim
    for top in tops:
        proof = landed_on_main(top, branch)
        if proof:
            return proof
    return None


def stall_cards(states=None):
    """(cards, judged): one card per stall bin/stalls.py finds on both Macs (chain-manager E1) —
    titled `<topic> · S1 gone 40h`, Blocked for a class the tick acts on (A1/A2) or a raise to a
    live manager, the owner's column for every other raise, with the evidence line and the rule that
    decided. A classifier that fails costs its cards, never the board: judged carries the error.
    The board's view only (board-cleanup S1): a stall whose work landed is no card, and one older than
    STALL_DAYS is counted in judged["hidden"] with the oldest's start; stalls.py --json and the tick
    still see every record."""
    try:
        import stalls
        res = stalls.judge(peer=not os.environ.get("PLAN_NO_PEER"), orca_held=helmlib.brake_refusal())
    except Exception as e:
        return [], {"error": "stalls: %s: %s" % (e.__class__.__name__, str(e)[:200])}
    cards, now, days = [], time.time(), stall_days()
    hidden = {"landed": 0, "old": 0, "oldest": None}
    for s in res["stalls"]:
        if stall_gone(s, states or {}):
            hidden["landed"] += 1
            continue
        since = s.get("since")
        if isinstance(since, (int, float)) and now - since > days * 86400:
            hidden["old"] += 1
            hidden["oldest"] = since if hidden["oldest"] is None else min(hidden["oldest"], since)
            continue
        cards.append(_card("stall", s["title"], s["column"], repo=s.get("repo"), by=s.get("host"),
                           updated=s.get("since"), evidence=stalls.evidence_line(s), stall=s["class"],
                           action=s["action"], rule=s["rule"], session=s.get("session"), run=s.get("run"),
                           orca_dispatch=s.get("orca_dispatch"), next_action=s.get("next_action"),
                           branch=s.get("branch"), guarded=s.get("guarded")))
    res["hidden"] = hidden
    return cards, res


def tag_re():
    """`@<person>` in a TODO line, for each of helmlib.people()."""
    return re.compile(r"@(%s)\b" % "|".join(re.escape(p) for p in helmlib.people()), re.I)


def road_cards():
    """skipper-resilience S8: one card in the owner's column per escalation the stall road could not
    deliver or settle (stalls_tick.road_faults: an issue that never opened after its one retry, a
    followed issue or a cleared one left open) — what GitHub never got is on the board instead. Quiet
    with no escalations.jsonl (every host that is no yard)."""
    try:
        import stalls_tick
        faults = stalls_tick.road_faults()
    except Exception:   # noqa: BLE001 — the road's reader costs its cards, never the board
        return []
    out = []
    for r in faults:
        closed = r.get("state") == "closed"
        left = [n for n in ((r.get("close_failed_issues") or [r.get("issue")]) if closed else stalls_tick.followed(r)) if n]
        if not closed and r.get("issue") is None:
            # its new issue never opened: that is the fault; the one it follows stays the stall's
            what = "not opened: %s%s" % (r.get("why") or "?", " (#%s still open)" % ", #".join(map(str, left)) if left else "")
        else:
            what = ("#%s left open" % ", #".join(map(str, left))) if left else "not opened: %s" % (r.get("why") or "?")
        out.append(_card("road", "stall road: %s — %s" % (r.get("title") or r.get("class") or "?", what), helmlib.columns()[0],
                         by=r.get("yard"), updated=r.get("t"), rule=r.get("class"), guarded=r.get("guarded")))
    return out


def todo_cards():
    out = []
    tag = tag_re()
    root = Path(os.environ.get("PLAN_PROJECTS_ROOT") or Path(os.environ.get("HOME") or Path.home()) / "projects")
    for f in glob.glob(str(root / "*" / "TODO.md")):
        repo = Path(f).parent.name
        try:
            lines = Path(f).read_text().splitlines()
        except OSError:
            continue
        for line in lines:
            m = tag.search(line)
            if not m or not re.match(r"^\s*(?:[-*]|\d+\.)\s", line):
                continue
            who = m.group(1).lower()
            text = re.sub(r"^\s*(?:[-*]|\d+\.)\s+", "", tag.sub("", line)).strip()
            out.append(_card("human", text[:140], helmlib.column_for(who), repo=repo, by=who,
                             guarded=helmlib.guarded(repo)))
    return out


def pr_cards(states, live=()):
    """(cards, idle): every open PR of every repo this Mac has cloned (board-cleanup S1: no cap — the
    board showed 10 of one repo's 102), from prefetch_prs()'s one read per repo. A ready PR waits on the
    owner; a WIP one (draft, or `WIP:`) is Running while a live session holds its `(repo, branch)`, and
    otherwise only counted: `idle`."""
    out, idle = [], 0
    live = set(live)
    for name, tops in sorted(helmlib.repo_tops().items()):
        if helmlib.guarded(name):
            continue
        for top in tops:
            for p in states.get(str(top)) or []:
                if str(p.get("state") or "").upper() != "OPEN":
                    continue
                wip = p.get("isDraft") or (p.get("title") or "").startswith("WIP:")
                if wip and (name, p.get("headRefName")) not in live:
                    idle += 1
                    continue
                out.append(_card("pr", "#%s %s" % (p["number"], p.get("title")), "Running" if wip else helmlib.columns()[0],
                                 repo=name, url=p.get("url"), branch=p.get("headRefName"), updated=helmlib._iso_ts(p.get("updatedAt"))))
    return out, idle


def done_cards(states, root=None):
    """Done today (board-cleanup S1: the column was always empty): each PR merged today in a repo this
    Mac has cloned, and each `launched` line dated today in a repo's autofinished log whose PR is not
    carded already. A guarded repo's are left out, as held_cards leaves them."""
    out, seen, still_open = [], set(), set()
    for name, tops in sorted(helmlib.repo_tops().items()):
        if helmlib.guarded(name):
            continue
        for top in tops:
            for p in states.get(str(top)) or []:
                if str(p.get("state") or "").upper() == "OPEN":
                    still_open.add((name, str(p["number"])))
                t = helmlib._iso_ts(p.get("mergedAt")) if str(p.get("state") or "").upper() == "MERGED" else None
                if t and _today(t):
                    seen.add((name, str(p["number"])))
                    out.append(_card("done", "#%s %s" % (p["number"], p.get("title")), "Done today", repo=name,
                                     url=p.get("url"), branch=p.get("headRefName"), updated=t))
    root = Path(root or Path.home() / "projects")
    for f in sorted(list(root.glob("*/.git/claude/autofinished")) + list(root.glob("*/*/.git/claude/autofinished"))):
        name = str(f.parent.parent.parent.relative_to(root))
        short = Path(name).name
        if helmlib.guarded(name):
            continue
        for e in helmlib._common().autofinished(f.parent.parent):
            if e["outcome"] not in ("launched", "landed"):
                continue
            try:
                ts = dt.datetime.fromisoformat(e["ts"]).timestamp()
            except ValueError:
                continue
            pr = re.search(r"#(\d+)\b", e["detail"] or "")
            # a PR readied for the owner's tap (the other Mac's launch) is not done while it is open
            if not _today(ts) or (pr and ((short, pr.group(1)) in seen or (short, pr.group(1)) in still_open)):
                continue
            if pr:
                seen.add((short, pr.group(1)))
            out.append(_card("done", helmlib._common().autofinished_phrase(e), "Done today", repo=short,
                             branch=e["branch"], updated=ts))
    return out


HELD_RE = re.compile(r"^held held \((?P<why>.*?)\): ?(?P<rest>.*)$")
HELD_DAYS = 14   # a held PR older than this left the board's reach: the PR list still shows it


def held_cards(root=None):
    """skipper-modes S3b: one card per branch whose last autofinish run held its landing at a ready PR —
    autofinish-run's `stopped <branch> held held (<why>): …` line in <repo>/.git/claude/autofinished,
    under ~/projects (one level of nesting, as a folder of repos) — naming the class, with the PR's link
    when the line names it. A branch merged by the owner's tap is gone locally after the next session
    start (sync.py prunes it), and its card with it; a later run on the branch replaces the line."""
    root = Path(root or Path.home() / "projects")
    out, now = [], time.time()
    for f in sorted(list(root.glob("*/.git/claude/autofinished")) + list(root.glob("*/*/.git/claude/autofinished"))):
        top = f.parent.parent.parent
        name = str(top.relative_to(root))
        if helmlib.guarded(name):
            continue
        last = {}
        for e in helmlib._common().autofinished(f.parent.parent):
            last[e["branch"]] = e
        for branch, e in sorted(last.items()):
            m = HELD_RE.match(e["detail"]) if e["outcome"] == "stopped" else None
            if not m:
                continue
            try:
                ts = dt.datetime.fromisoformat(e["ts"]).timestamp()
            except ValueError:
                continue
            if now - ts > HELD_DAYS * 86400:
                continue
            if subprocess.run(["git", "-C", str(top), "rev-parse", "-q", "--verify", "refs/heads/" + branch],
                              capture_output=True).returncode:
                continue
            pr = re.search(r"#(\d+)\b", m.group("rest"))
            slug = _github_slug(name)
            out.append(_card("held", "held at a ready PR — %s" % branch, helmlib.columns()[0], repo=name, held=m.group("why"),
                             updated=ts, url=("https://github.com/%s/pull/%s" % (slug, pr.group(1))) if pr and slug else None))
    return out


def week_line():
    """The week's plan usage as the tier check shows it: tier_check.weekly() takes the parsed
    .claude.json of this login ($CLAUDE_CONFIG_DIR's, else ~/.claude.json — CLAUDE_JSON, as its own
    report() passes it) and returns (percent, sampled_ms, resets_at or None). None when unread."""
    try:
        tc = helmlib.peer("tier_check.py")   # plumb's (G26): absent → no week line
        if not tc:
            return None
        if str(tc.parent) not in sys.path:
            sys.path.insert(0, str(tc.parent))
        import tier_check
        w = tier_check.weekly(tier_check.load(tier_check.CLAUDE_JSON))
        if not w:
            return None
        pct, sampled, resets = w
        s = "week %s%% used" % pct
        if resets:
            s += " (pace %s%%)" % tier_check.week_pace(resets)
        return s + ", sampled %s" % tier_check.age(sampled)
    except Exception:
        return None


def timeline(states):
    rows = []
    for st in states:
        bars = []
        for t in st["tasks"]:
            start = t.get("started") or st.get("created")
            end = t.get("eta") or t.get("updated") or time.time()
            if t["status"] in helmlib.ENDED:
                end = t.get("updated") or end
            bars.append({"id": t["id"], "title": t["title"], "start": start, "end": end, "status": t["status"],
                         "kind": t.get("kind"), "deps": t["deps"], "cost": t.get("cost"), "est": t.get("est_to_go"),
                         "parked_at": t.get("parked_at"), "overrun": t.get("overrun"),
                         "flags": [a["ref"].split("#")[-1] for a in t["asks"] if a["open"]], "blockers": t["blockers"]})
        rows.append({"plan": st.get("topic") or st["id"], "id": st["id"], "bars": bars, "milestones": st["milestones"],
                     "totals": st["totals"]})
    return rows


def ops_row():
    """The desk's ops row (lighthouse-ops S2): lighthouse's `ops status --json`, which owns the row's format —
    its one line, its staleness and its sig (the row without its clocks and gauges, for board_sig). None when
    lighthouse is absent, no sample was taken on this host (no subprocess then, on every poll), or the read
    fails. HELM_OPS replaces the tool (the tests')."""
    stub = os.environ.get("HELM_OPS")
    try:
        path = Path(stub) if stub else helmlib.peer("ops")
        if not path or not (stub or (helmlib._common().LOG_DIR / "ops.jsonl").exists()):
            return None
        cp = subprocess.run([sys.executable, str(path), "status", "--json"], capture_output=True, text=True,
                            timeout=10, stdin=subprocess.DEVNULL)
        d = json.loads(cp.stdout) if cp.returncode == 0 else None
    except (ImportError, OSError, ValueError, subprocess.TimeoutExpired):
        return None
    if not isinstance(d, dict) or not isinstance(d.get("line"), str):
        return None
    return {"line": d["line"], "sig": d.get("sig"), "stale": bool(d.get("stale"))}


def intake_cards():
    """One card per open issue the desk's intake holds (lighthouse-ops S4): lighthouse's `ops intake --json`,
    which judges each against the registry as it reads now (a torn one gives none, a fenced scope's are
    dropped). The card carries no title of the issue — a contact is a stranger's text — only its kind and
    number, and links to GitHub; `label` is the kind, the lane the page groups it by. Its `updated` (the
    issue's creation) is a clock board_sig never reads. [] when lighthouse is absent, this host has no intake,
    or the read fails. HELM_OPS replaces the tool (the tests')."""
    stub = os.environ.get("HELM_OPS")
    try:
        path = Path(stub) if stub else helmlib.peer("ops")
        if not path or not (stub or (helmlib._common().LOG_DIR / "intake-state.json").exists()):
            return []
        cp = subprocess.run([sys.executable, str(path), "intake", "--json"], capture_output=True, text=True,
                            timeout=10, stdin=subprocess.DEVNULL)
        d = json.loads(cp.stdout) if cp.returncode == 0 else None
    except (ImportError, OSError, ValueError, subprocess.TimeoutExpired):
        return []
    try:
        # on a confidential scope's own yard ops keeps its issues; the shared page guards them, as skipperlib does
        conf = set(helmlib._common().confidential_scopes())
        conf_unread = False
    except Exception:  # noqa: BLE001 — scopes that do not read guard every card
        conf, conf_unread = set(), True
    out = []
    for c in (d.get("open") if isinstance(d, dict) and isinstance(d.get("open"), list) else []):
        if not isinstance(c, dict) or not c.get("repo") or c.get("number") is None:
            continue
        kind = str(c.get("kind") or "other")
        out.append(_card("intake", "%s #%s" % (kind, c["number"]), "Intake", repo=c["repo"], label=kind,
                         ref="%s#%s" % (c.get("slug") or c["repo"], c["number"]), url=c.get("url"),
                         by=c.get("author"), updated=c.get("created"),
                         guarded=conf_unread or c.get("scope") in conf or helmlib.guarded(c["repo"])))
    return out


def overview_state():
    states = []
    for pid in helmlib.list_plans():
        try:
            st = helmlib.public(helmlib.state(pid))
        except (FileNotFoundError, ValueError):
            continue
        if all(t["status"] in helmlib.ENDED and not _today(t.get("updated")) for t in st["tasks"]) and st["tasks"]:
            continue  # a finished plan rolls off the board the day after
        states.append(st)
    cards = []
    for st in states:
        cards += plan_cards(st)
    # one read of every cloned repo's pull requests serves the stall, ask, PR and Done today cards
    prs = {} if os.environ.get("PLAN_NO_GH") else helmlib.prefetch_prs([t for ts in helmlib.repo_tops().values() for t in ts])
    polled = poll_cards(prs)
    cards += polled
    cards += memo_cards({Path((c.get("ref") or "").split("#")[0]).name for c in polled})
    cards += lookout_cards(prs)
    stalled, judged = stall_cards(prs)
    # a stall replaces the run's own card (an ask guard's, a permission prompt's): one card per run —
    # every stall's, a landed or old one's too, whose run must not come back as a card of its own
    covered = {s.get("session") for s in judged.get("stalls") or [] if s.get("session")}
    cards += [c for c in run_cards() if not (c.get("session") and c["session"] in covered)]
    cards += stalled
    # a WAITING session a stall already cards (a run's S6) keeps the stall's card alone
    cards += [c for c in waiting_cards(judged) if not (c.get("session") and c["session"] in covered)]
    cards += road_cards()
    cards += todo_cards()
    held = held_cards()
    cards += held
    # a held PR's card names its class; the plain PR card for the same link would only repeat it
    held_urls = {c["url"] for c in held if c.get("url")}
    # a session at work on a branch, either Mac's, or a running task's: its WIP PR is a Running card
    live = {(_repo_of_cwd(x.get("cwd")), x.get("branch")) for x in judged.get("live") or [] if x.get("branch")}
    live |= {(Path(str(t.get("repo") or "")).name, t.get("branch")) for st in states for t in st["tasks"]
             if t["status"] == "running" and t.get("branch")}
    pr, wip_idle = pr_cards(prs, live)
    cards += [c for c in pr if c.get("url") not in held_urls]
    cards += done_cards(prs)
    cards += intake_cards()
    cards = embark_first(cards)
    for c in cards:  # K6: another person reads the board; a guarded card keeps its column and nothing else
        if c.get("guarded"):
            for k in ("title", "recommended", "blockers", "by", "owner", "doc", "ref", "url", "evidence", "rule", "session", "run",
                      "next_action", "orca_dispatch", "host", "course", "github", "branch"):
                c.pop(k, None)
            c["title"] = "guarded — open it"
    cols = [{"name": n, "cards": [c for c in cards if c["column"] == n]} for n in board_columns()]
    today_cost = sum(t.get("cost") or 0 for st in states for t in st["tasks"] if _today(t.get("updated")))
    ops = ops_row()
    return {"kind": "overview", "as_of": time.time(), "host": helmlib.host(), "columns": cols,
            "header": {"needs_owner": len(cols[0]["cards"]), "owner": helmlib.display(helmlib.people()[0]), "today_cost": round(today_cost, 4), "week": week_line(),
                       "stalled": None if "error" in judged else len(stalled),
                       "stalls_old": (judged.get("hidden") or {}).get("old") or 0,
                       "stalls_oldest": (judged.get("hidden") or {}).get("oldest"),
                       "stalls_landed": (judged.get("hidden") or {}).get("landed") or 0,
                       "stall_days": (lambda d: int(d) if d == int(d) else d)(stall_days()),
                       "wip_idle": wip_idle,
                       "stalls_note": judged.get("error") or "; ".join(judged.get("notes") or []) or None,
                       "sheep": paused_note(), "talk": talk_note(),
                       "ops": (ops or {}).get("line"), "ops_stale": (ops or {}).get("stale"), "ops_sig": (ops or {}).get("sig")},
            "timeline": timeline(states)}


# an age in a card's title ("gone 40h", "12 min"): it moves every poll, so the deploy check leaves it out
AGE_RE = re.compile(r"\d+(?:\.\d+)?\s*(?:s|min|h|d|w)\b")
BOARD_SIG_KEYS = ("column", "kind", "repo", "ref", "url", "doc", "session", "run", "course", "github", "guarded")


def board_sig(st):
    """What the board shows that is worth a new version: each card's identity and its title without
    ages, and the owner's column's count — never the header's week line ("sampled N min ago"), the timeline's
    `now` or `as_of`, which move on every poll (re-review of landing review 10). The ops row counts by its
    `ops_sig` alone, never its line, which carries the sample's age and the gauges (lighthouse-ops S2)."""
    def card(c):
        if not isinstance(c, dict):
            return c
        keep = {k: c.get(k) for k in BOARD_SIG_KEYS}
        keep["title"] = AGE_RE.sub("", str(c.get("title") or ""))
        return keep
    cols = [{"name": col.get("name"), "cards": [card(c) for c in col.get("cards") or []]} if isinstance(col, dict) else col
            for col in st.get("columns") or []]
    hdr = st.get("header") or {}
    return hashlib.sha256(json.dumps({"columns": cols, "needs_owner": hdr.get("needs_owner"), "stalled": hdr.get("stalled"),
                                       "stalls_old": hdr.get("stalls_old"), "wip_idle": hdr.get("wip_idle"),
                                       "ops": hdr.get("ops_sig")},
                                     ensure_ascii=False, sort_keys=True, default=str).encode()).hexdigest()


def overview(deploy=False, as_json=False):
    st = overview_state()
    if as_json:
        return json.dumps(st, ensure_ascii=False, sort_keys=True)
    d = cache_root() / "overview"
    _write(d / "state.json", json.dumps(st, ensure_ascii=False, sort_keys=True))
    _write(d / "index.html", page(st, "Helm · board"))
    out = ["overview: %s — %d need %s" % (d / "index.html", st["header"]["needs_owner"], st["header"]["owner"])]
    if deploy and not os.environ.get("PLAN_NO_DEPLOY"):
        pin = cache_root() / "overview-space.txt"
        # ask poll deploys every 5 min: a board whose cards are what the pinned page shows already is
        # not deployed again (landing review 10: ~288 versions a day otherwise), but at least hourly, so
        # the ages and the week line the check leaves out never go stale for long
        sig = board_sig(st)
        last = cache_root() / "overview-deployed.sha"
        try:
            space = pin.read_text().strip() or None
        except OSError:
            space = None
        try:
            same = space and last.read_text().strip() == sig and time.time() - last.stat().st_mtime < 3600
        except OSError:
            same = False
        # the hold before the unchanged check: a resume must redeploy the page that still says
        # "paused" though no card moved (landing review: up to an hour of a stale note otherwise)
        before = st.get("header", {}).get("sheep")
        held = budget_hold(st) if space else None   # a board never deployed has no pin yet: it goes once
        now = st.get("header", {}).get("sheep")
        if now != before:   # the crossing (the deployed page says it, the log once) or the resume
            _write(d / "state.json", json.dumps(st, ensure_ascii=False, sort_keys=True))
            _write(d / "index.html", page(st, "Helm · board"))
        if held:
            # the poll's log says the pause once, at the crossing; a hand-run says why nothing deployed
            if now != before or not os.environ.get("HELM_BOARD_POLL"):
                out.append("sheep: " + held)
            return out
        if same and now == before:
            out.append("sheep: unchanged since the last deploy (%s)" % space)
            return out
        if now and now != before:
            out.append("sheep: " + now + " (after this deploy)")
        try:
            uuid, url = deploy_dir(d, ("index.html", "state.json"), space=space, title="Helm · board",
                                   message=time.strftime("%Y-%m-%d %H:%M"), by="helm-board")
            _write(pin, uuid)
            _write(last, sig)
            out.append("sheep: %s" % (url or uuid))
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
            out.append("sheep: deploy failed — %s" % e)
    return out


# ---------------------------------------------------------------------------- the page

PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{TITLE}}</title>
<meta name="ss-streams" content="plans/*">
<style>
:root{--bg:#fbfaf7;--fg:#1d1d1b;--mute:#6b6a65;--line:#e4e1d8;--card:#fff;--owner:#c2410c;--peer:#7c3aed;--block:#b91c1c;--run:#1d4ed8;--park:#a16207;--done:#15803d;--amber:#d97706}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#161614;--fg:#ecebe6;--mute:#9b9a94;--line:#2c2b28;--card:#1f1e1c}}
:root[data-theme="dark"]{--bg:#161614;--fg:#ecebe6;--mute:#9b9a94;--line:#2c2b28;--card:#1f1e1c}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
header{padding:14px 16px;border-bottom:1px solid var(--line);display:flex;flex-wrap:wrap;gap:8px 18px;align-items:baseline}
h1{font-size:17px;margin:0;font-weight:600}.mute{color:var(--mute)}.pill{border:1px solid var(--line);border-radius:999px;padding:2px 10px;background:var(--card);cursor:pointer;font:inherit;color:inherit}
.pill[data-on=true]{background:var(--fg);color:var(--bg)}main{padding:12px 16px}
.board{display:grid;grid-template-columns:repeat(6,minmax(180px,1fr));gap:10px;overflow-x:auto}
@media (max-width:760px){.board{grid-template-columns:1fr}}
.col h2{font-size:12px;text-transform:uppercase;letter-spacing:.06em;margin:0 0 6px;color:var(--mute)}
.lane{font-size:11px;color:var(--mute);margin:8px 0 4px;border-top:1px dashed var(--line);padding-top:4px}
.card{background:var(--card);border:1px solid var(--line);border-left:3px solid var(--mute);border-radius:6px;padding:7px 9px;margin:0 0 7px}
.card .t{font-weight:550}.card .m{font-size:12px;color:var(--mute)}
.c0{border-left-color:var(--owner)}.c1{border-left-color:var(--peer)}.c2{border-left-color:var(--block)}.c3{border-left-color:var(--run)}.c4{border-left-color:var(--park)}.c5{border-left-color:var(--done)}.c6{border-left-color:var(--amber)}
.tl{overflow-x:auto}.tl svg{display:block}.tasks{display:grid;gap:8px}
table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid var(--line);padding:5px 6px;text-align:left;font-size:13px;vertical-align:top}
.hidden{display:none}.more{font-size:12px;margin:0 0 7px}
#ops{padding:5px 16px;border-bottom:1px solid var(--line);font-size:12px;color:var(--mute)}#ops.stale{color:var(--amber)}
</style></head><body>
<header><h1 id="title"></h1><span id="head" class="mute"></span>
<span><button class="pill" data-view="board">Board</button> <button class="pill" data-view="timeline">Timeline</button></span>
<span id="lanes"><button class="pill" data-lane="plan">by plan</button> <button class="pill" data-lane="repo">by repo</button> <button class="pill" data-lane="by">by whom</button></span></header>
<div id="ops" class="hidden"></div>
<main><div id="app"></div><p class="mute" id="foot"></p></main>
<script type="application/json" id="snapshot">{{STATE}}</script>
<script>
(function(){
var S=JSON.parse(document.getElementById('snapshot').textContent);
function get(k,d){try{return localStorage.getItem('plan.'+k)||d}catch(e){return d}}
function put(k,v){try{localStorage.setItem('plan.'+k,v)}catch(e){}}
var view=get('view','board'),lane=get('lane','plan');if(lane==='owner')lane='by';
function by(c){return c.by||c.owner}
function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
function money(x){return x==null?'':'$'+(x>=10?Math.round(x):x>=0.1?x.toFixed(2):x.toPrecision(2))}
function ago(t){if(!t)return'';var s=Date.now()/1000-t;return s<5400?Math.round(s/60)+'m':s<172800?Math.round(s/3600)+'h':Math.round(s/86400)+'d'}
function when(t){if(!t)return'—';var d=new Date(t*1000);return d.toLocaleString([], {month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'})}
function card(c,i){var m=[];if(c.plan)m.push(esc(c.plan));if(c.repo)m.push(esc(c.repo));if(by(c))m.push(esc(by(c)));
 if(c.updated)m.push(ago(c.updated)+' ago');var x=[];
 if(c.ref)x.push(esc(c.ref));if(c.reversible)x.push('Reversible: '+esc(c.reversible));if(c.recommended)x.push('Recommended: '+esc(c.recommended));
 if(c.eta)x.push('ETA '+when(c.eta)+(c.overrun?' (overrun)':''));if(c.cost!=null)x.push(money(c.cost)+(c.est?' → '+money(c.est):''));
 if(c.blockers&&c.blockers.length)x.push('blocked: '+esc(c.blockers.join('; ')));if(c.parked&&c.parked.length)x.push('parked: '+esc(c.parked.join(', ')));
 if(c.open)x.push(c.open+' open');if(c.keel)x.push(esc(c.keel));if(c.review)x.push(esc(c.review));if(c.evidence)x.push(esc(c.evidence));
 if(c.rule)x.push(esc(c.rule)+(c.action?' → '+esc(c.action):''));
 if(c.held)x.push(esc(c.held));
 var link=(c.course?' <a href="'+esc(c.course)+'">course</a>':'')+(c.github?' <a href="'+esc(c.github)+'">github</a>':'')+(c.url?' <a href="'+esc(c.url)+'">open</a>':'');
 return '<div class="card c'+i+'"><div class="t">'+esc(c.kind==='ask'?'? ':c.kind==='human'?'◯ ':c.kind==='pr'?'⇡ ':c.kind==='permission'?'! ':c.kind==='stall'?'⚠ ':c.kind==='waiting'?'… ':c.kind==='held'?'⏸ ':c.kind==='done'?'✓ ':'')+esc(c.title)+link+'</div><div class="m">'+m.join(' · ')+'</div>'+(x.length?'<div class="m">'+x.join(' · ')+'</div>':'')+'</div>'}
// the owner's column groups by kind (board-cleanup S1: 130 cards in one list), five each, "+N more" to open
var KINDS=[['asks',['ask']],['stalls',['stall','road']],['sessions waiting',['waiting','permission','task']],['PRs',['pr','held']],['memos',['memo','lookout']]],SHOW=5,more={};
// Intake's lanes in ops' order (deadman first); any other label ranks after them, alphabetically
var IKINDS=['deadman','stall','contact','bug','other'];
function kindOf(c){for(var j=0;j<KINDS.length;j++)if(KINDS[j][1].indexOf(c.kind)>=0)return j;return KINDS.length}
function lanes(col,i){var groups={},rank={};col.cards.forEach(function(c){var k,r;
  if(c.label){k=c.label;var j=IKINDS.indexOf(k);r=j<0?-1:j-IKINDS.length}else if(i===0){r=kindOf(c);k=r<KINDS.length?KINDS[r][0]:'other'}else{k=(lane==='by'?by(c):c[lane])||'—';r=0}
  (groups[k]=groups[k]||[]).push(c);rank[k]=r});
 return Object.keys(groups).sort(function(a,b){return rank[a]-rank[b]||(a<b?-1:a>b?1:0)}).map(function(k){return [k,groups[k]]})}
function board(cols){var h='<div class="board">';cols.forEach(function(col,i){if(i===1&&!col.cards.length)return;
 h+='<section class="col"><h2>'+esc(col.name)+' · '+col.cards.length+'</h2>';
 lanes(col,i).forEach(function(g){var key=i+'/'+g[0],cs=g[1],open=more[key];
  h+='<div class="lane">'+esc(g[0])+' · '+cs.length+'</div>'+(open?cs:cs.slice(0,SHOW)).map(function(c){return card(c,i)}).join('');
  if(cs.length>SHOW)h+='<button class="pill more" data-more="'+esc(key)+'">'+(open?'fewer':'+'+(cs.length-SHOW)+' more')+'</button>'});
 h+='</section>'});return h+'</div>'}
var FILL={running:'var(--run)',relayed:'var(--park)',parked:'var(--park)',waiting:'var(--owner)',blocked:'var(--block)',failed:'var(--block)',done:'var(--done)',landed:'var(--done)',launched:'var(--done)',planned:'var(--mute)'};
function timeline(rows){if(!rows||!rows.length)return '<p class="mute">No ships with tasks.</p>';
 var now=Date.now()/1000,lo=now,hi=now;rows.forEach(function(r){r.bars.forEach(function(b){lo=Math.min(lo,b.start||now);hi=Math.max(hi,b.end||now)});(r.milestones||[]).forEach(function(m){hi=Math.max(hi,m.on)})});
 hi=Math.max(hi,lo+3600);var W=Math.max(640,Math.min(1600,window.innerWidth-40)),L=160,R=90,rowH=22,y=24,x=function(t){return L+(W-L-R)*(t-lo)/(hi-lo)};
 var parts=[],pos={};
 rows.forEach(function(r){parts.push('<text x="4" y="'+(y+14)+'" font-weight="600" fill="currentColor">'+esc(r.plan)+'</text>');
  parts.push('<text x="'+(W-R+6)+'" y="'+(y+14)+'" font-size="11" fill="currentColor">'+money(r.totals.cost)+(r.totals.est_to_go?' → '+money(r.totals.est_to_go):'')+(r.totals.open_asks?' · '+r.totals.open_asks+'?':'')+'</text>');y+=rowH;
  (r.milestones||[]).forEach(function(m){var mx=x(m.on);parts.push('<path d="M'+mx+' '+(y-16)+' l6 6 l-6 6 l-6 -6z" fill="currentColor"><title>'+esc(m.name)+'</title></path><text x="'+(mx+8)+'" y="'+(y-6)+'" font-size="11" fill="currentColor">'+esc(m.name)+' ('+m.open+')</text>')});
  r.bars.forEach(function(b){var x0=b.status==='blocked'||(b.blockers&&b.blockers.length&&b.status==='planned')?x(now):x(b.start||now),x1=Math.max(x0+4,x(b.end||now));pos[r.id+'/'+b.id]={x0:x0,x1:x1,y:y+8};
   var fill=FILL[b.status]||'var(--mute)',human=b.kind==='human',hollow=human||b.status==='blocked';
   parts.push('<text x="12" y="'+(y+12)+'" font-size="12" fill="currentColor">'+esc(b.title).slice(0,22)+'</text>');
   parts.push('<rect x="'+x0+'" y="'+(y+2)+'" width="'+(x1-x0)+'" height="13" rx="3" fill="'+(hollow?'none':fill)+'" stroke="'+(b.overrun?'var(--amber)':fill)+'" stroke-width="'+(b.overrun?2:1)+'"><title>'+esc(b.title+' — '+b.status+(b.blockers&&b.blockers.length?' — '+b.blockers.join('; '):''))+'</title></rect>');
   if(b.parked_at){var px=Math.max(x0,x(b.parked_at));parts.push('<rect x="'+px+'" y="'+(y+2)+'" width="'+Math.max(2,x1-px)+'" height="13" fill="url(#hatch)"/>')}
   if(b.cost!=null)parts.push('<text x="'+(x1+4)+'" y="'+(y+13)+'" font-size="10" fill="currentColor">'+money(b.cost)+(b.est?' → '+money(b.est):'')+'</text>');
   (b.flags||[]).forEach(function(f,k){parts.push('<text x="'+(x0+4+k*24)+'" y="'+(y)+'" font-size="10" fill="var(--owner)">⚑'+esc(f)+'</text>')});
   y+=rowH});
  r.bars.forEach(function(b){(b.deps||[]).forEach(function(d){var a=pos[r.id+'/'+d],c=pos[r.id+'/'+b.id];if(!a||!c)return;var bad=c.x0<a.x1-1;
   parts.push('<path d="M'+a.x1+' '+a.y+' C'+(a.x1+20)+' '+a.y+' '+(c.x0-20)+' '+c.y+' '+c.x0+' '+c.y+'" fill="none" stroke="'+(bad?'var(--block)':'var(--mute)')+'" stroke-width="1"/>')})});y+=8});
 var nx=x(now);parts.push('<line x1="'+nx+'" y1="10" x2="'+nx+'" y2="'+y+'" stroke="var(--owner)" stroke-dasharray="3 3"/><text x="'+(nx+3)+'" y="12" font-size="10" fill="var(--owner)">now</text>');
 return '<p class="mute">ETAs are guesses; a bar past its ETA turns amber.</p><div class="tl"><svg width="'+W+'" height="'+(y+10)+'" viewBox="0 0 '+W+' '+(y+10)+'" role="img"><title>timeline</title><defs><pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="6" stroke="var(--park)" stroke-width="2"/></pattern></defs>'+parts.join('')+'</svg></div>'}
function planView(s){var h='<div class="tasks"><table><tr><th>Task</th><th>Status</th><th>By</th><th>Updated</th><th>ETA</th><th>Cost</th><th>Blockers · asks</th></tr>';
 s.tasks.forEach(function(t){h+='<tr><td>'+esc(t.title)+(t.progress?'<div class="mute">'+esc(t.progress)+'</div>':'')+'</td><td>'+esc(t.status)+'</td><td>'+esc(by(t)||(t.session||'').slice(0,8))+'</td><td>'+ago(t.updated)+'</td><td>'+when(t.eta)+(t.overrun?' ⚠':'')+'</td><td>'+money(t.cost)+(t.est_to_go?' → '+money(t.est_to_go)+' '+(t.est_kind==='manager'?'skipper':(t.est_kind||'')):'')+'</td><td>'+esc((t.blockers||[]).join('; '))+'</td></tr>'});
 return h+'</table></div>'}
function draw(){document.documentElement.dataset.view=view;var o=S.kind==='overview';
 document.getElementById('title').textContent=o?'Helm · board':'Helm · '+(S.topic||S.id);
 var hd=o?[S.header.needs_owner+' need '+(S.header.owner||'the owner'),S.header.stalled?S.header.stalled+' stalled':'',S.header.stalls_old?S.header.stalls_old+' stalls over '+(S.header.stall_days||7)+'d (oldest '+ago(S.header.stalls_oldest)+')':'',S.header.wip_idle?S.header.wip_idle+' WIP PRs idle':'',S.header.today_cost?'today '+money(S.header.today_cost):'',S.header.week||'',S.header.talk||'',S.header.sheep||'']:['started '+(S.started?when(S.started):'none'),'due '+(S.due?when(S.due):'none'),S.cost!=null?money(S.totals.cost)+' of '+money(S.cost)+' est.':money(S.totals.cost)+' so far',S.totals.est_to_go?money(S.totals.est_to_go)+' to go':'',S.totals.open_asks+' open asks'];
 document.getElementById('head').textContent=hd.filter(Boolean).join(' · ');
 var op=document.getElementById('ops');if(o&&S.header.ops){op.textContent=S.header.ops;op.className=S.header.ops_stale?'stale':''}else op.className='hidden';
 document.getElementById('lanes').className=o&&view==='board'?'':'hidden';
 var rows=o?S.timeline:[{plan:S.topic||S.id,id:S.id,bars:S.tasks.map(function(t){return{id:t.id,title:t.title,start:t.started||S.created,end:t.eta||t.updated,status:t.status,kind:t.kind,deps:t.deps,cost:t.cost,est:t.est_to_go,parked_at:t.parked_at,overrun:t.overrun,flags:(t.asks||[]).filter(function(a){return a.open}).map(function(a){return a.ref.split('#').pop()}),blockers:t.blockers}}),milestones:S.milestones,totals:S.totals}];
 document.getElementById('app').innerHTML=view==='timeline'?timeline(rows):(o?board(S.columns):planView(S));
 document.querySelectorAll('[data-view]').forEach(function(b){b.setAttribute('data-on',b.dataset.view===view)});
 document.querySelectorAll('[data-lane]').forEach(function(b){b.setAttribute('data-on',b.dataset.lane===lane)});
 document.getElementById('foot').textContent='as of '+when(S.as_of)+' on '+(S.host||'?');}
document.addEventListener('click',function(e){var b=e.target.closest('[data-view],[data-lane],[data-more]');if(!b)return;if(b.dataset.more){more[b.dataset.more]=!more[b.dataset.more];draw();return}if(b.dataset.view){view=b.dataset.view;put('view',view)}else{lane=b.dataset.lane;put('lane',lane)}draw()});
function poll(){fetch('state.json',{cache:'no-store'}).then(function(r){return r.ok?r.json():null}).then(function(j){if(j&&j.as_of!==S.as_of){S=j;draw()}}).catch(function(){})}
draw();setInterval(poll,30000);
})();
</script></body></html>
"""


if __name__ == "__main__" and len(sys.argv) == 4 and sys.argv[1] == "serve":
    serve(sys.argv[2], sys.argv[3])
