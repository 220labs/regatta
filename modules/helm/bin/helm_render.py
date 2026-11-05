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
    artifact  a line for the skipper to act on, only where this login is known to have the tool
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
import signal
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


def snapshot(state):
    """The state as a script block's JSON: every `<` as \\u003c, so neither `</script>` nor a `<!--` then `<script` in a
    card's text can end or swallow the block (a doc title holding both left the board blank: S3's round-1 review)."""
    return json.dumps(state, ensure_ascii=False, sort_keys=True).replace("<", "\\u003c")


def page(state, title):
    """The one page: its script, its first snapshot (for an Artifact or a file:// open)."""
    snap = snapshot(state)
    return PAGE.replace("{{TITLE}}", html.escape(title)).replace("{{STATE}}", snap)


# helm-board-ux S3: the board's shell is three files beside this one (board.html, board.css, board.js), read at every
# render, with keel's foundation (tokens, art, fx: helm-ui S10) inlined at {{FOUNDATION}}, so the page stays one file
# for the local server, a spacesheep deploy and an Artifact. One pass fills every slot: a file's own text is never
# scanned again, so a `{{STATE}}` inside board.js stays text. Without keel or a file that will not read, the board
# falls back to PAGE, said on stderr at every render, never a traceback: the tick deploys the board unattended.
BOARD_FILES = ("board.html", "board.css", "board.js")
# the Engine room (engine-room S3): its rules, its adapter and its view, inlined before board.js, which calls them
ENGINE_FILES = ("engine.css", "engine_adapter.js", "engine.js")
BOARD_SLOT = re.compile(r"\{\{(TITLE|FOUNDATION|BOARD_CSS|BOARD_JS|STATE|ENGINE_CSS|ENGINE_JS|ENGINE)\}\}")


def board_page(state, title, engine=None):
    """The board: board.html with board.css, board.js, the Engine room's files, keel's foundation, the first snapshot
    and the Engine room's first document inlined (null when the caller has none: the page says unread)."""
    k = _keel()
    try:
        tpl, css, js = ((HERE / n).read_text(encoding="utf-8") for n in BOARD_FILES)
        head = k.foundation_head() if k and hasattr(k, "foundation_head") else None
    except Exception as e:   # noqa: BLE001 — keel's Stop is its own class; any miss is the old page
        print("helm: board shell unreadable (%s: %s): the plain page" % (type(e).__name__, str(e)[:120]), file=sys.stderr)
        return page(state, title)
    if not head:
        print("helm: keel's foundation not found: the plain page", file=sys.stderr)
        return page(state, title)
    try:   # the Engine room's own: without them the board stands, its ops line and Intake cards as before (board.js)
        ecss, eadapt, ejs = ((HERE / n).read_text(encoding="utf-8") for n in ENGINE_FILES)
    except Exception as e:  # noqa: BLE001 — any miss leaves the Engine room out, never the board
        print("helm: the Engine room's files unreadable (%s): the board without it" % type(e).__name__, file=sys.stderr)
        ecss = eadapt = ejs = ""
    fill = {"TITLE": html.escape(title), "FOUNDATION": head, "BOARD_CSS": css.replace("</", "<\\/"),
            "BOARD_JS": js.replace("</script", "<\\/script"),
            "ENGINE_CSS": ecss.replace("</", "<\\/"),
            "ENGINE_JS": (eadapt + "\n" + ejs).replace("</script", "<\\/script"),
            "ENGINE": snapshot(engine),
            "STATE": snapshot(state)}
    return BOARD_SLOT.sub(lambda m: fill[m.group(1)], tpl)


# ---------------------------------------------------------------------------- the plan page

def render(pid, deploy=None):
    """Write the local files; deploy per the live backend (deploy=None), now (True) or never (False).
    Returns the lines to print."""
    st = helmlib.state(pid)
    pub = dict(plan_view(st), kind="plan")
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
    """B8: the skipper's own step — only where this login is known to have the Artifact tool (B0h)."""
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


def repo_name(path):
    """A task's repo as the board names it: the folder's name, or its main checkout's when the path is a
    session's worktree, so its ask matches the poll's row (_repo_of_cwd's reading, one for both)."""
    return _repo_of_cwd(str(path or "").rstrip("/")) or ""


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
        cards.append(_card("human" if human else "task", t["title"], col, plan=plan, plan_id=st["id"], task=t.get("id"),
                           repo=repo_name(t.get("repo")), by=by or ((t.get("session") or "")[:8]),
                           status=s, eta=t.get("eta"), cost=t.get("cost"), est=t.get("est_to_go"),
                           blockers=t["blockers"], parked=t["parked"], updated=t.get("updated"),
                           overrun=t.get("overrun"), guarded=t.get("guarded")))
        for a in t["asks"]:
            if a["open"]:
                # a held dnd item and any ask in mode ask wait on the owner alone: no skipper answers them (S5)
                acol = owner_col if s == "waiting" or a.get("mode") in ("ask", "dnd") else "Parked / Relayed"
                repo = repo_name(t.get("repo"))
                course, github = ask_links(repo, t.get("branch"), a["ref"].rpartition("#")[0])
                cards.append(_card("ask", a.get("summary") or a["ref"], acol, plan=plan, plan_id=st["id"], ref=a["ref"], task=t.get("id"),
                                   repo=repo, reversible=a.get("reversible"),
                                   recommended=a.get("recommended"), updated=a.get("opened"), guarded=t.get("guarded"),
                                   mode=a.get("mode"), held="held for %s (dnd)" % helmlib.display(helmlib.people()[0]) if a.get("mode") == "dnd" else None,
                                   course=course, github=github, branch=t.get("branch")))
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


_PINS = []   # [(read at, keel's pins)]: one read per render — sheep.json is megabytes (S2's review: ~0.3 s a read)


def _pin(repo, branch, rel):
    k = _keel()
    if k is None:
        return {}
    if not _PINS or time.time() - _PINS[0][0] > 60:
        try:
            pins = k.pins()
        except Exception:
            pins = {}
        _PINS[:] = [(time.time(), pins if isinstance(pins, dict) else {})]
    pin = _PINS[0][1].get("%s@%s:%s" % (repo, branch, rel))
    return pin if isinstance(pin, dict) else {}


def ask_links(repo, branch, rel):
    """(course, github) for a doc on a branch, each None when it cannot be read."""
    if not (repo and branch and rel):
        return None, None
    k = _keel()
    course = github = None
    if k is not None:
        course = _pin(repo, branch, rel).get("url")
        slug = _github_slug(repo)
        if slug:
            try:
                github = k.urls(slug, branch, rel)[0]
            except Exception:
                github = None
    return course, github


# The whole doc in place (helm-board-ux S2, `queue`): the Course page from its content origin,
# `https://<space>.spacesheep.app/`, the space read from keel's pin on the host that deployed it; a host
# without the pin carries none, and the card's GitHub link (keel's urls()) stands for the doc there.
# The frame case, read 2026-11-02 against a pinned Course page: anonymous, with the CLI's key as a Bearer
# header and as a cookie, the content origin answers 200 with no content-security-policy and no
# x-frame-options — a 4,354-byte shell, the same three ways, so no frame header refuses a frame. The shell
# is the catch: it renders only inside a frame (`window.parent===window` shows "Open this space at
# spacesheep.dev") and takes its sign-in ticket only from a parent at spacesheep.dev or *.spacesheep.dev
# (`trusted(o)`), then fetches /index.html with that ticket's token. The board's page runs on its own
# content origin (or 127.0.0.1), which the shell does not trust, so a private Course page framed by the
# board stays on its shell. D4 (docs/helm-board-ux-2026-10-26.md) is answered C, by surface: the local page
# renders the whole doc from the doc on disk at a click, the deployed board opens the Course page in its own
# tab, signed in there — the card's `course` URL, never `frame`, whose shell shows only "Open this space at
# spacesheep.dev" outside a frame. `frame` serves one road: the board framing the Course page while the board
# itself sits under a spacesheep.dev parent, the only parent the shell takes a sign-in from (S11).
CONTENT_ORIGIN = "https://%s.spacesheep.app/"


def ask_frame(repo, branch, rel):
    """The content-origin URL of a doc's Course page from this host's keel pin, or None."""
    space = _pin(repo, branch, rel).get("space") if repo and branch and rel else None
    return CONTENT_ORIGIN % space if space and re.match(r"^[0-9a-f-]{8,64}$", str(space)) else None


# What an ask card carries from ask poll's row for the Decide feed (S2): the item's own section, its options,
# its first line and the worktree on this host (the VS Code link), the steps that wait on it, its content hash,
# the branch's tip and time, and the doc's title and Summary (moved onto the doc's group in `queue`).
ASK_FIELDS = ("section", "options", "line", "step_waits", "hash", "worktree", "sha", "summary", "doc_title")


def ask_key(repo, branch, rel, item):
    """The reconcile key the page keys a decision by (`queue`): repo@branch:rel#D3."""
    return "%s@%s:%s#%s" % (repo, branch, rel, item)


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
    # a guard list that may be short (helmlib.guard_unread: no `regatta/guarded`, a torn registry) keeps every
    # row's doc words home, as ask poll's scan does; the card stays as main showed it, its title and links
    unread = helmlib.guard_unread()
    for a in helmlib.newest_per_item(rows):
        course, github = ask_links(a.get("repo"), a.get("branch"), a.get("rel"))
        out.append(_card("ask", a.get("title") or a.get("item"), helmlib.columns()[0], repo=a.get("repo"), ref="%s#%s" % (a.get("rel"), a.get("item")),
                         branch=a.get("branch"), reversible=a.get("reversible"), recommended=a.get("recommended"),
                         course=course, github=github, frame=ask_frame(a.get("repo"), a.get("branch"), a.get("rel")),
                         key=ask_key(a.get("repo"), a.get("branch"), a.get("rel"), a.get("item")), rel=a.get("rel"), item=a.get("item"),
                         # an epoch, as the page's ago() reads: when the poll first saw the item, else its branch tip's time
                         updated=next((x for x in (a.get("asked"), a.get("t")) if isinstance(x, (int, float))), None),
                         # K6 at render too: a row written while the registry read may name a repo it now guards
                         guarded=helmlib.guarded(a.get("repo")) or None,
                         **{f: a.get(f) for f in ASK_FIELDS if not (unread and f in helmlib.DOC_TEXT)}))
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
# Since routed comments S3 the words are "that host's lookout acts" (the host rule names no branch's host).
OTHER_LOOKOUT_RE = re.compile(r"(?:\bits (?:own )?|\bthat host's )lookout (?:acts|starts the run)\b")


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
                         # its key names the doc and its items, so it stays one card's whatever else is listed (S2)
                         key="lookout:%s#%s" % (doc or "?", ",".join(str(i) for i in items) or r.get("id") or ""),
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
    """Orphan runs (no skipper — every autofinish run), runs the ask guard failed, and sessions at a
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
    live skipper, the owner's column for every other raise, with the evidence line and the rule that
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
    followed issue or a cleared one left open, a ladder rung that failed twice, a notify seam that holds every
    phone rung) — what GitHub never got is on the board instead. Quiet
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
        if r.get("state") == "held":
            what = "%s (`ask backends` names it)" % (r.get("why") or "?")   # the notify seam does not read (charterer S3)
        elif not closed and r.get("issue") is None:
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
            # the item's id (`- [porch-bulb] …`, wharf's /todo since 2026-10-31) is the list's handle, not the card's words
            text = re.sub(r"^\s*(?:[-*]|\d+\.)\s+(?:\[[a-z0-9-]{2,}\]\s+)?", "", tag.sub("", line)).strip()
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


def doc_decision_counts(docs):
    """(answered, all) D-items over a ship's docs, read with keel's parse (the hill's uphill, R2.13), or None
    when keel is absent or none of the docs reads here (a ship from another host, a doc moved)."""
    if not docs:
        return None
    k = _keel()
    if k is None:
        return None
    done = total = read = 0
    for d in docs:
        try:
            _, items, _ = k.parse(Path(d).read_text())
        except Exception:   # noqa: BLE001 — a doc that will not read counts nothing; keel's Stop included
            continue
        read += 1
        total += len(items)
        done += sum(1 for i in items if (i.get("answer") or "").strip())
    return (done, total) if read else None


def plan_view(st, at=None):
    """public()'s copy of a ship with its ladder (S2): the hill's decisions read from the private copy's docs."""
    pub = helmlib.public(st)
    try:
        pub["ladder"] = helmlib.ladder(pub, at, doc_decision_counts(st.get("docs")))
    except Exception as e:   # noqa: BLE001 — a hand-edited due or cost that will not read: the ship without its ladder
        print("helm: %s's ladder skipped (%s: %s)" % (st.get("id"), type(e).__name__, str(e)[:120]), file=sys.stderr)
        pub["ladder"] = None
    return pub


def timeline(states, at=None):
    """A row per ship for the ship ladder (B7; S2 adds the ladder's data): each task a bar from its start to its
    end — a built step's first DONE (`built_at`), an open one's projected end along the dependency order
    (helmlib.task_ends; `projected` says how when it is not the skipper's own ETA) — and the ship's `ladder`."""
    at = time.time() if at is None else at
    rows = []
    for st in states:
        try:   # a value plan_view's ladder tolerated (a hand-edited plan.json) never takes the board down
            ends = helmlib.task_ends(st, at)[0]
        except Exception as e:   # noqa: BLE001
            print("helm: %s timeline ends skipped (%s: %s)" % (st.get("id"), type(e).__name__, str(e)[:120]), file=sys.stderr)
            ends = {}
        bars = []
        for t in st["tasks"]:
            start = t.get("started") or st.get("created")
            end, how = ends.get(t["id"]) or (t.get("eta") or t.get("updated") or at, None)
            if t["status"] in helmlib.ENDED and t["status"] != "failed":
                end, how = t.get("built_at") or t.get("updated") or end, "built"
            bars.append({"id": t["id"], "title": t["title"], "start": start, "end": end, "status": t["status"],
                         "projected": how if how in ("projected", "pushed", "overrun") else None,
                         "kind": t.get("kind"), "deps": t["deps"], "cost": t.get("cost"), "est": t.get("est_to_go"),
                         "parked_at": t.get("parked_at"), "overrun": t.get("overrun"),
                         "flags": [a["ref"].split("#")[-1] for a in t["asks"] if a["open"]], "blockers": t["blockers"]})
        rows.append({"plan": st.get("topic") or st["id"], "id": st["id"], "bars": bars, "milestones": st["milestones"],
                     "totals": st["totals"], "ladder": st.get("ladder") if "ladder" in st else helmlib.ladder(st, at)})
    return rows


# the file each ops verb's answer needs on this host: without it no desk runs here (no subprocess then, on every poll)
OPS_FILES = {"status": "ops.jsonl", "intake": "intake-state.json"}
OPS_OFF = "off"   # ops_json's answer for a host with no desk: no file, or no lighthouse


def ops_json(verb):
    """lighthouse's `ops <verb> --json` as a dict (status exits 3 with `row` null when no sample reads, still an
    answer); OPS_OFF where lighthouse is absent or this host has no desk's file for the verb; None when the read
    failed (a crash, a timeout, JSON that will not parse) — the Engine room says unread then, never zero.
    HELM_OPS replaces the tool (the tests')."""
    stub = os.environ.get("HELM_OPS")
    try:
        path = Path(stub) if stub else helmlib.peer("ops")
        if not path or not (stub or (helmlib._common().LOG_DIR / OPS_FILES[verb]).exists()):
            return OPS_OFF
        cp = subprocess.run([sys.executable, str(path), verb, "--json"], capture_output=True, text=True,
                            timeout=10, stdin=subprocess.DEVNULL)
        d = json.loads(cp.stdout) if cp.returncode in (0, 3) else None
    except ImportError:
        return OPS_OFF
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None
    return d if isinstance(d, dict) else None


_READ = object()   # ops_row's and intake_cards' default: read the verb now


def ops_row(doc=_READ):
    """The desk's ops row (lighthouse-ops S2): lighthouse's `ops status --json`, which owns the row's format —
    its one line, its staleness and its sig (the row without its clocks and gauges, for board_sig). None when
    lighthouse is absent, no sample was taken on this host, or the read fails. `doc` is that verb's answer
    when the caller read it already (overview_state reads each verb once)."""
    d = ops_json("status") if doc is _READ else doc
    if not isinstance(d, dict) or not isinstance(d.get("line"), str):
        return None
    return {"line": d["line"], "sig": d.get("sig"), "stale": bool(d.get("stale"))}


def intake_cards(doc=_READ):
    """One card per open issue the desk's intake holds (lighthouse-ops S4): lighthouse's `ops intake --json`,
    which judges each against the registry as it reads now (a torn one gives none, a fenced scope's are
    dropped). The card carries no title of the issue — a contact is a stranger's text — only its kind and
    number, and links to GitHub; `label` is the kind, the lane the page groups it by. Its `updated` (the
    issue's creation) is a clock board_sig never reads. [] when lighthouse is absent, this host has no intake,
    or the read fails. `doc` is that verb's answer when the caller read it already."""
    d = ops_json("intake") if doc is _READ else doc
    if not isinstance(d, dict):
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


# helm-board-ux S2: the Decide feed's order and the Later shelf, carried in the board's JSON as keys into
# the owner's column (a card is written once, in its column; `queue` and `later` name it by `key`).
QUEUE_GROUPS = {"pr": "land", "held": "land", "stall": "unstick", "waiting": "unstick", "permission": "unstick",
                "road": "unstick", "lookout": "unstick", "run": "unstick", "memo": "memo"}
GUARDED_DROP = ("title", "recommended", "blockers", "by", "owner", "doc", "ref", "url", "evidence", "rule", "session", "run",
                "next_action", "orca_dispatch", "host", "course", "github", "branch", "frame", "rel", "item") + ASK_FIELDS


def card_key(c):
    """A card's reconcile key: an ask's repo@branch:rel#D3, else its kind and what names it; never its
    title's ages (AGE_RE), which move on every poll."""
    if c.get("key"):
        return c["key"]
    if c.get("plan_id"):   # a ship's card: its plan and task (a guarded task's id is public()'s salted token)
        ref = str(c.get("ref") or "")
        # an ask: its item; a guarded one's ref is public()'s "guarded", so its opening time tells its asks apart
        # (finish review: every ask of one guarded task shared a key, so a done on one hid the next)
        item = "#" + ref.rpartition("#")[2] if "#" in ref else "@%s" % c.get("updated") if c.get("updated") is not None else ""
        return "%s:%s/%s%s" % (c.get("kind"), c["plan_id"], c.get("task") or AGE_RE.sub("", str(c.get("title") or "")).strip(),
                               item if c.get("kind") == "ask" else "")
    what = c.get("url") or c.get("doc") or c.get("ref") or c.get("session") or c.get("run") or AGE_RE.sub("", str(c.get("title") or "")).strip()
    return "%s:%s%s" % (c.get("kind"), "%s/" % c["repo"] if c.get("repo") and not c.get("url") and not c.get("doc") else "", what)


def key_cards(cards):
    """Give each card its key, unique in `cards`: where two share one (a lookout card per answered item of
    one doc), each of those takes its title, ages left out, after a `|`; a tie left after that is numbered
    `~2`, `~3` in the order the board lists them. Every card is told apart, so no draft or snooze is shared."""
    base = [card_key(c) for c in cards]
    n = {}
    for k in base:
        n[k] = n.get(k, 0) + 1
    seen = {}
    for c, k in zip(cards, base):
        k = k if n[k] == 1 else "%s|%s" % (k, AGE_RE.sub("", str(c.get("title") or "")).strip())
        seen[k] = seen.get(k, 0) + 1
        c["key"] = k if seen[k] == 1 else "%s~%d" % (k, seen[k])


def guard_salt():
    """This host's salt for a guarded card's key and hash digests, kept beside board-state.json and never
    published: a reader of the board cannot check a guessed repo, branch and doc against a digest (as public()'s
    plan salt). Made once: written whole to a file of this process's own, then linked into place, which only
    the first render wins; a file that reads short (a torn write from before) is replaced the same way."""
    p = cache_root() / "guard-salt"
    for _ in range(3):
        try:
            s = p.read_text().strip()
            if len(s) >= 16:
                return s
            short = True
        except OSError:
            short = False
        s = os.urandom(16).hex()
        tmp = p.with_name("guard-salt.%d.tmp" % os.getpid())
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
            fd = os.open(str(tmp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)   # never the umask's 0644
            with os.fdopen(fd, "w") as fh:
                fh.write(s)
            if short:
                os.replace(str(tmp), str(p))   # a torn salt never served a key: replacing it loses nothing
            else:
                try:
                    os.link(str(tmp), str(p))  # create-if-absent with its content: the first render's salt is everyone's
                except FileExistsError:
                    raise
                except OSError:                # no hard links here: an exclusive create, written in place
                    fd = os.open(str(p), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                    with os.fdopen(fd, "w") as fh:
                        fh.write(s)
            return s
        except FileExistsError:
            continue                           # another render won: read its salt
        except OSError:
            return s                           # no cache dir to keep it in: this render's own
        finally:
            try:
                tmp.unlink()
            except OSError:
                pass
    return s


def strip_guarded(cards):
    """K6: another person reads the board; a guarded card keeps its column and nothing else — S2's section,
    Summary, worktree and frame included, its repo read as "guarded" (as public() names a ship's), and its key
    and hash only as salted digests, enough to reconcile by (the hash taken before the strip, so a snooze still
    sees the item change)."""
    salt = None
    for c in cards:
        if c.get("guarded"):
            salt = salt or guard_salt()
            pre = card_hash(c) + "\0" + str(c.get("key") or "")   # two asks of one guarded task differ by key alone
            for k in GUARDED_DROP:
                c.pop(k, None)
            c["title"] = "guarded — open it"
            if c.get("repo"):
                c["repo"] = "guarded"
            c["hash"] = "g" + hashlib.sha256((salt + "\0" + pre).encode()).hexdigest()[:15]
            if c.get("key"):
                c["key"] = "guarded:" + hashlib.sha256((salt + "\0" + c["key"]).encode()).hexdigest()[:12]
    return cards


def card_hash(c):
    """What a snooze "until it changes" and a done compare: an ask's item hash (S2), else a digest of what
    the card shows — its deploy-check fields and title without ages, its status, class, rule and evidence —
    so a stall that escalates or a PR whose checks turn comes back. S4's drainer writes the row with the
    hash the page showed, which is this."""
    if c.get("hash"):
        return c["hash"]
    # what moves on a card while it is held: a stall's class (`stall`), a memo's open count and keel line, a
    # review's state, a held PR's reason (finish review: `class` was read, which no card carries)
    keep = {k: c.get(k) for k in BOARD_SIG_KEYS + ("status", "stall", "rule", "evidence", "label", "open", "keel", "review", "held")}
    keep["title"] = AGE_RE.sub("", str(c.get("title") or ""))
    keep["evidence"] = AGE_RE.sub("", json.dumps(keep.get("evidence"), ensure_ascii=False, sort_keys=True, default=str))
    return "c" + hashlib.sha256(json.dumps(keep, ensure_ascii=False, sort_keys=True, default=str).encode()).hexdigest()[:15]


def board_state_file():
    return cache_root() / "board-state.json"


def read_later(now=None):
    """The owner's attention apart from the work's state (features: three states kept apart): the rows of
    this host's board-state.json, which S4's drainer writes from the page's snooze and done events —
    {"later": [{"key", "hash", "kind": "snooze" | "done", "until": "<iso>" | null, "at"}]}. A snooze's
    `until` null is "until it changes". A row that will not read is skipped; no file is no rows."""
    try:
        d = json.loads(board_state_file().read_text())
    except (OSError, ValueError):
        return []
    rows = d.get("later") if isinstance(d, dict) else None
    now = time.time() if now is None else now
    out = []
    for r in rows if isinstance(rows, list) else ():
        if not (isinstance(r, dict) and isinstance(r.get("key"), str) and r.get("kind") in ("snooze", "done")):
            continue
        until = helmlib._iso_ts(r["until"]) if r.get("until") else None
        if r["kind"] == "snooze" and r.get("until") and (until is None or until <= now):
            continue   # awake: back on the feed
        out.append(r)
    return out


def decide_queue(cards, later_rows=()):
    """(queue, later) over the owner's column. `queue`: the docs whose decisions wait — each a group with its
    items' keys in the doc's order, in the queue component's order, the reason shown (docs an S-step waits
    on, then docs holding a `Reversible: no` item, then oldest first) — and after them the other cards'
    keys by what they need: memo, land, unstick, people, tasks, other. `later`: the cards a snooze or a done
    holds off the feed while their hash is the row's (an item that changed comes back)."""
    owner = helmlib.columns()[0]
    held = {}
    for r in later_rows:
        held[r["key"]] = r
    docs, rest, later, seen = {}, {}, [], set()
    for c in cards:
        if c.get("column") != owner:
            continue
        k = c.get("key") or card_key(c)
        if k in seen:
            continue
        seen.add(k)
        r = held.get(k)
        if r and r.get("hash") == card_hash(c):
            later.append({"key": k, "kind": r["kind"], "until": r.get("until"), "at": r.get("at"), "title": c.get("title")})
            continue
        if c.get("kind") == "ask" and c.get("rel") and not c.get("guarded"):
            dk = "%s@%s:%s" % (c.get("repo"), c.get("branch"), c.get("rel"))
            g = docs.setdefault(dk, {"key": dk, "repo": c.get("repo"), "branch": c.get("branch"), "rel": c.get("rel"),
                                     "title": c.get("doc_title") or c.get("rel"), "summary": c.get("summary"),
                                     "course": c.get("course"), "github": c.get("github"), "frame": c.get("frame"),
                                     "worktree": c.get("worktree"), "items": [], "waits": [], "oneway": 0, "oldest": None})
            it = str(c.get("item") or k.rpartition("#")[2])
            num = int(it[1:]) if it[1:].isdigit() else 0
            # the doc's order: by line, a card with none (a ship's ask no poll row matched) after them, by its number
            g["items"].append((c.get("line") is None, c.get("line") or 0, num, k))
            g["waits"] += ["%s waits on %s" % (s, c.get("item") or k.rpartition("#")[2]) for s in c.get("step_waits") or ()]
            g["oneway"] += c.get("reversible") == "no"
            u = c.get("updated")   # an epoch: a poll card's branch tip, a ship's ask its opening
            u = float(u) if isinstance(u, (int, float)) else helmlib._iso_ts(u) if u else None
            if u is not None and (g["oldest"] is None or u < g["oldest"]):
                g["oldest"] = u
            continue
        # a plan task waiting on the owner stays in Decide (R2.8): `tasks`; a TODO line's @name is People's
        grp = QUEUE_GROUPS.get(c.get("kind")) or ("tasks" if c.get("kind") in ("task", "human") and c.get("plan_id")
                                                   else "people" if c.get("kind") == "human" else "other")
        rest.setdefault(grp, []).append(k)
    out = []
    for g in docs.values():
        g["items"] = [x[-1] for x in sorted(g["items"])]
        g["open"] = len(g["items"])
        g["why"] = ("↑ first: " + ", ".join(g["waits"])) if g["waits"] else (
            "holds %d irreversible" % g["oneway"]) if g["oneway"] else "oldest first"
        g["rank"] = 0 if g["waits"] else 1 if g["oneway"] else 2
        out.append({k: v for k, v in g.items() if v not in (None, "", [])})
    out.sort(key=lambda g: (g["rank"], g.get("oldest") if g.get("oldest") is not None else float("inf"), g["key"]))
    for g in out:
        g.pop("oneway", None)
        if g.get("oldest") is not None:
            g["oldest"] = helmlib.iso(g["oldest"])
    order = ("memo", "land", "unstick", "people", "tasks", "other")
    return {"docs": out, "groups": [[g, rest[g]] for g in order if rest.get(g)]}, later


def absorb_polled(cards, polled):
    """`cards` (a ship's) then `polled`, one card per decision: a ship's ask card that names the item the
    poll read takes the poll card's key, repo, branch, links and S2 fields, and that poll card is dropped.
    Matched on (repo, rel, item) — the branch too when the task recorded one; a task that names no repo
    matches only when one poll card in all repos holds that doc and item, never a guess between two."""
    by_key = {c["key"]: c for c in polled if c.get("key")}
    by_item = {}
    for c in polled:
        by_item.setdefault((c.get("repo"), c.get("rel"), c.get("item")), []).append(c)
    took = set()
    owner = helmlib.columns()[0]
    # a ship's ask relayed to its skipper (Parked / Relayed) leaves the owner's poll card in Decide, as before S2
    asks = [c for c in cards if c.get("kind") == "ask" and c.get("plan_id") and "#" in str(c.get("ref") or "")
            and c.get("column") == owner]
    for c in asks:
        rel, _, item = c["ref"].rpartition("#")
        c.setdefault("rel", rel)
        c.setdefault("item", item)

    def take(c, row):
        if row is None or id(row) in took:
            return
        took.add(id(row))
        c.update({f: row[f] for f in ASK_FIELDS + ("frame", "repo", "branch", "course", "github", "key")
                  if row.get(f) not in (None, "", [])})
        if c.get("updated") is None:   # a ship's ask keeps when it was opened; the poll's is the branch tip's time
            c["updated"] = row.get("updated")
        c["guarded"] = c.get("guarded") or row.get("guarded")
        c["_took"] = True

    for c in asks:   # first every ask on the poll's own branch, so an older branch never takes its card
        if c.get("repo") and c.get("branch"):
            take(c, by_key.get(ask_key(c["repo"], c["branch"], c["rel"], c["item"])))
    for c in asks:
        if c.pop("_took", False):
            continue
        rel, item = c["rel"], c["item"]
        got = by_item.get((c["repo"], rel, item)) if c.get("repo") else \
            [x for (_, r2, i2), xs in by_item.items() if (r2, i2) == (rel, item) for x in xs]
        # the poll keeps the newest branch's row of an item: the task's may be an older one
        take(c, got[0] if got and len(got) == 1 else None)
        c.pop("_took", None)
    return cards + [c for c in polled if id(c) not in took]


# each ops verb's answer as overview_state read it, for overview()'s Engine room document (engine_state): one read
# of each serves the board and the Engine room. A module dict, not an argument: suites stub overview_state whole
OPS_READ = {}


def overview_state():
    ops_doc, intake_doc = ops_json("status"), ops_json("intake")
    OPS_READ.clear()
    OPS_READ.update(ops=ops_doc, intake=intake_doc)
    states = []
    at = time.time()   # one clock for every ship's ladder and the timeline's bars
    for pid in helmlib.list_plans():
        try:
            st = helmlib.state(pid, at)
            if all(t["status"] in helmlib.ENDED and not _today(t.get("updated")) for t in st["tasks"]) and st["tasks"]:
                continue  # a finished plan rolls off the board the day after
        except (FileNotFoundError, ValueError):
            continue
        except Exception as e:   # noqa: BLE001 — a torn ship (an event time that is no number) costs itself, never the board
            print("helm: ship %s skipped (%s: %s)" % (pid, type(e).__name__, str(e)[:120]), file=sys.stderr)
            continue
        st = plan_view(st, at)
        states.append(st)
    cards = []
    for st in states:
        cards += plan_cards(st)
    # one read of every cloned repo's pull requests serves the stall, ask, PR and Done today cards
    prs = {} if os.environ.get("PLAN_NO_GH") else helmlib.prefetch_prs([t for ts in helmlib.repo_tops().values() for t in ts])
    polled = poll_cards(prs)
    cards = absorb_polled(cards, polled)
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
    live |= {(repo_name(t.get("repo")), t.get("branch")) for st in states for t in st["tasks"]
             if t["status"] == "running" and t.get("branch")}
    pr, wip_idle = pr_cards(prs, live)
    cards += [c for c in pr if c.get("url") not in held_urls]
    cards += done_cards(prs)
    cards += intake_cards(intake_doc)
    cards = embark_first(cards)
    owner = helmlib.columns()[0]
    key_cards([c for c in cards if c.get("column") == owner])
    strip_guarded(cards)
    for c in cards:   # the hash a snooze or done names (S4's drainer writes the one the page showed): every owner card's
        if c.get("column") == owner and not c.get("hash"):
            c["hash"] = card_hash(c)
    queue, later = decide_queue(cards, read_later())
    for c in cards:   # the doc's title and Summary ride its group in `queue`, once per doc
        c.pop("summary", None)
        c.pop("doc_title", None)
    cols = [{"name": n, "cards": [c for c in cards if c["column"] == n]} for n in board_columns()]
    today_cost = sum(t.get("cost") or 0 for st in states for t in st["tasks"] if _today(t.get("updated")))
    ops = ops_row(ops_doc)
    try:   # the board prints effective prices only ($0.07e, S3): the week's list-to-effective ratio, None when unread
        ratio = helmlib._common().cost_ratio()[0]
    except Exception:   # noqa: BLE001 — no core: the page says list prices as such
        ratio = None
    return {"kind": "overview", "as_of": time.time(), "host": helmlib.host(), "columns": cols,
            # needs_owner: a snoozed or done card (Later) needs no one now
            "header": {"needs_owner": len(cols[0]["cards"]) - len(later), "owner":helmlib.display(helmlib.people()[0]), "today_cost": round(today_cost, 4), "week": week_line(), "ratio": ratio,
                       "stalled": None if "error" in judged else len(stalled),
                       "stalls_old": (judged.get("hidden") or {}).get("old") or 0,
                       "stalls_oldest": (judged.get("hidden") or {}).get("oldest"),
                       "stalls_landed": (judged.get("hidden") or {}).get("landed") or 0,
                       "stall_days": (lambda d: int(d) if d == int(d) else d)(stall_days()),
                       "wip_idle": wip_idle,
                       "stalls_note": judged.get("error") or "; ".join(judged.get("notes") or []) or None,
                       "sheep": paused_note(), "talk": talk_note(),
                       "ops": (ops or {}).get("line"), "ops_stale": (ops or {}).get("stale"), "ops_sig": (ops or {}).get("sig")},
            "timeline": timeline(states, at), "queue": queue, "later": later}


# an age in a card's title ("gone 40h", "12 min"): it moves every poll, so the deploy check leaves it out
AGE_RE = re.compile(r"\d+(?:\.\d+)?\s*(?:s|m|min|h|d|w)\b")   # `m`: stalls' _ago ("gone 37m")
BOARD_SIG_KEYS = ("column", "kind", "repo", "ref", "url", "doc", "session", "run", "course", "github", "guarded",
                  "hash", "recommended", "reversible")   # S2: an item's text, its pick or its lock changed is a new version


def board_sig(st, eng=None):
    """What the board shows that is worth a new version: each card's identity and its title without
    ages, and the owner's column's count — never the header's week line ("sampled N min ago"), the timeline's
    `now` or `as_of`, which move on every poll (re-review of landing review 10). The ops row counts by its
    `ops_sig` alone, never its line, which carries the sample's age and the gauges (lighthouse-ops S2). `eng`, the
    Engine room's document, counts by engine_sig(): no ages, no gauges, no `history` (engine-room S3)."""
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
                                       "ops": hdr.get("ops_sig"),
                                       # the feed's order and reasons move with a step done or a Summary edited (no clock: `oldest`
                                       # is a branch tip's commit time)
                                       "queue": st.get("queue"),
                                       # a snooze or a done moves a card off the feed: a new version, as its keys say
                                       "later": sorted(str(r.get("key")) for r in st.get("later") or () if isinstance(r, dict)),
                                       "engine": engine_sig(eng)},
                                     ensure_ascii=False, sort_keys=True, default=str).encode()).hexdigest()


BOARD_DEPLOYED = ("index.html", "state.json", "engine.json")


def overview(deploy=False, as_json=False):
    OPS_READ.clear()
    hp = None if as_json else hosts_start()   # hosts' reads run beside overview_state's, inside the poll's board budget
    st = overview_state()
    if as_json:
        return json.dumps(st, ensure_ascii=False, sort_keys=True)
    try:   # a stubbed overview_state leaves OPS_READ empty: engine_state reads ops itself
        eng = engine_state(dict(OPS_READ), hosts=hp)
    except Exception as e:  # noqa: BLE001 — the unattended board never ends in a traceback: the room reads unread
        print("helm: the Engine room's document failed (%s): every source unread" % type(e).__name__, file=sys.stderr)
        hosts_collect(hp)
        eng = {"at": time.time(), "sources": {k: {"state": "unread", "at": None} for k in ENGINE_SOURCES}}
    d = cache_root() / "overview"
    _write(d / "state.json", json.dumps(st, ensure_ascii=False, sort_keys=True))
    _write(d / "engine.json", json.dumps(eng, ensure_ascii=False, sort_keys=True))
    _write(d / "index.html", board_page(st, "Helm · board", eng))
    out = ["overview: %s — %d need %s" % (d / "index.html", st["header"]["needs_owner"], st["header"]["owner"])]
    if deploy and not os.environ.get("PLAN_NO_DEPLOY"):
        pin = cache_root() / "overview-space.txt"
        # ask poll deploys every 5 min: a board whose cards are what the pinned page shows already is
        # not deployed again (landing review 10: ~288 versions a day otherwise), but at least hourly, so
        # the ages and the week line the check leaves out never go stale for long
        sig = board_sig(st, eng)
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
            _write(d / "index.html", board_page(st, "Helm · board", eng))
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
            uuid, url = deploy_dir(d, BOARD_DEPLOYED, space=space, title="Helm · board",
                                   message=time.strftime("%Y-%m-%d %H:%M"), by="helm-board")
            _write(pin, uuid)
            _write(last, sig)
            out.append("sheep: %s" % (url or uuid))
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
            out.append("sheep: deploy failed — %s" % e)
    return out


# ---------------------------------------------------------------------------- the Engine room's document

# docs/engine-room-2026-11-02.md S3: the poll's five reads for the Engine room — lighthouse's `hosts --json`, `ops
# status --json` and `ops intake --json` (the last two the board's own reads, once each), the config dir's
# lighthouse/ci-budgets.json and the log dir's ci-budget-alarms.json — each through the page's own field allowlist
# (ENGINE_ALLOW, not helmlib.public(), which filters a ship's plan only), written as engine.json beside state.json.
# The page's adapter (engine_adapter.js) maps it onto what the view draws. Each source carries its own read state and
# `at` under `sources`: `ok`, `off` (no desk, no file on this host) or `unread` (the read failed), so the page says
# unread where a source did not read, never zero (the design's reviews.md, finding 10).
# What the allowlist keeps: names, numbers and the tools' own fixed words (a pin's `by` as a session's first 8, as
# S4's hosts cuts it). It drops a login's home, env, email and same_as; a run's session; a guarded repo's runs and
# entries (engine_guard: counted, never listed); an entry's args, env, note and caller (hosts drops those first); a budget's user, org and
# org_slug and every `why` the desk prints (a path under the home folder: reviews.md, finding 4); an intake card's url,
# slug, label and scope. Every string that passes is cut of anything that reads as a path or an address.
_V = True    # a scalar (a string, a number, a bool, null) or a list of scalars
_HIST = "history"   # a list of samples, each a list of numbers
ENGINE_ALLOW = {
    "hosts": {
        "at": _V, "here": _V,
        "hosts": {"*": {
            "host": _V, "os": _V, "role": _V, "at": _V, "no_sample": _V, "source": _V,
            "load": {"per_core_5m": _V}, "mem": {"avail": _V, "swap_gb": _V, "swap_total_gb": _V, "rate": _V},
            "headroom": {"room": _V, "reason": _V, "near": _V},
            "limits": {"cap": _V, "avail": _V, "swap": _V, "rate": _V, "load_max": _V},
            "slots": {"cap": _V, "busy": _V, "reserved": _V},
            "fence": {"confined": _V, "unreadable": _V, "runs_unread": _V},
            "runs": [{"topic": _V, "repo": _V, "login": _V, "state": _V, "prio": _V, "started": _V}],
            "records": {"stale": _V, "oldest_days": _V},
            "checks": {"busy": _V, "cap": _V, "waiting": _V}, "features": _V,   # S4's: absent until it lands
            "history": _HIST}},
        "queue": {"entries": [{"qid": _V, "topic": _V, "repo": _V, "state": _V, "priority": _V, "kind": _V, "host": _V,
                               "prefer": _V, "prefer_off": _V, "running_on": _V, "queued_at": _V, "claimed_at": _V,
                               "claimed_by": _V, "attempts": _V, "needs": _V, "last_refusal": _V,
                               "refused_by": {"*": _V}, "after": _V,
                               "pin_kind": _V, "pinned_why": _V, "by": _V, "pin_login": _V}],   # the last four S4's
                  "dropped": _V, "fence_unreadable": _V, "unreadable": _V, "guard_unread": _V},
        "logins": [{"label": _V, "eligible": _V, "primary": _V, "parked": _V, "why": _V, "sampled": _V,
                    "limits": {"plan": _V, "five_hour": _V, "five_hour_resets": _V, "seven_day": _V,
                               "seven_day_resets": _V, "fable_week": _V}}],
        "records": {"stale": _V, "oldest_days": _V},
        "ref": {"unreadable": _V, "offline": _V}},
    "ops": {"row": {"host": _V, "as_of": _V, "partial": _V, "check": {"slots_busy": _V, "waiting": _V},
                    "budget": {"*": {"state": _V, "used": _V, "week_used": _V, "unit": _V, "net_amount": _V,
                                     "cap": _V, "share": _V}}},
            "age_s": _V, "stale": _V},
    "budgets": {"reserve": _V, "accounts": {"*": {"provider": _V, "reserve": _V, "month_credits": _V,
                                                  "month_minutes": _V, "margin": _V, "week_share": _V}}},
    "alarms": {"*": {"level": _V, "issue": _V, "since": _V}},
    "intake": {"open": [{"repo": _V, "number": _V, "kind": _V, "created": _V, "author": _V}], "guarded": {"*": _V}},
}
# lighthouse's bin/hosts' scrub, in its order (URLISH, PATHISH, ADDRISH; PATHISH is dispatch-queue's, the gate's), and a
# path after any other punctuation: a second layer over what hosts cut already, never weaker than it
ENGINE_URLISH = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*://\S+|git@\S+")
ENGINE_PATHISH = re.compile(r"(?:^|(?<=[\s(\[\"'=,:`<|;>{}]))(?:~/|/[A-Za-z])[^\s,;)\]\"'`>|]*")
ENGINE_ADDRISH = re.compile(r"[^\s@()<>\"',;]+@[^\s@()<>\"',;]+")


def _scalar(v):
    if isinstance(v, str):
        return ENGINE_ADDRISH.sub("<address>", ENGINE_PATHISH.sub("<path>", ENGINE_URLISH.sub("<url>", v)))[:240]
    return v if v is None or isinstance(v, (bool, int, float)) else None


def engine_pick(v, spec):
    """`v` kept to what `spec` names (ENGINE_ALLOW's shape): a dict keeps its listed keys (`*` stands for every key,
    a host's name or a budget's), a list each item by the one spec, a scalar as itself, cut of paths. A value of the
    wrong shape is dropped (None in a list, absent in a dict), never passed through."""
    if spec is _V:
        if isinstance(v, list):
            return [x for x in (_scalar(y) for y in v) if x is not None]
        return _scalar(v)
    if spec == _HIST:
        return [[x if isinstance(x, (int, float)) and not isinstance(x, bool) else None for x in p]
                for p in v if isinstance(p, list)][-48:] if isinstance(v, list) else None
    if isinstance(spec, list):
        return [engine_pick(x, spec[0]) for x in v if isinstance(x, dict)] if isinstance(v, list) else None
    if not isinstance(v, dict):
        return None
    out = {}
    for k, x in v.items():
        sub = spec.get(k, spec.get("*")) if isinstance(k, str) else None
        if sub is None:
            continue
        kept = engine_pick(x, sub)
        if kept is not None or x is None:
            out[_scalar(k) if "*" in spec and k not in spec else k] = kept
    return out


ENGINE_SOURCES = ("hosts", "ops", "budgets", "alarms", "intake")
HOSTS_TIMEOUT = 60   # s; started before overview_state, so the board's own reads overlap it


def hosts_start():
    """lighthouse's `hosts --json` (S2), started: a Popen in its own process group, OPS_OFF where lighthouse is absent
    or PLAN_NO_HOSTS keeps a suite off it (it fetches the queue home) — off, never a failed read — None when it will not
    start. HELM_HOSTS replaces the tool (the tests')."""
    if os.environ.get("PLAN_NO_HOSTS"):
        return OPS_OFF
    stub = os.environ.get("HELM_HOSTS")
    try:
        path = Path(stub) if stub else helmlib.peer("hosts")
        if not path:
            return OPS_OFF
        return subprocess.Popen([sys.executable, str(path), "--json"], stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, text=True, start_new_session=True)
    except (ImportError, OSError):
        return None


def hosts_collect(p):
    """hosts_start()'s answer read: every host's row, the fleet queue, the logins and this host's records, fenced by
    `hosts` itself; OPS_OFF passed on; None when the read fails or outlasts HOSTS_TIMEOUT, whose whole group is
    killed then (its fetch included: an orphan every poll otherwise)."""
    if p is None or p == OPS_OFF:
        return p
    try:
        out, _ = p.communicate(timeout=HOSTS_TIMEOUT)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        p.communicate()
        return None
    try:
        d = json.loads(out) if p.returncode == 0 else None
    except ValueError:
        return None
    return d if isinstance(d, dict) else None


def hosts_json():
    return hosts_collect(hosts_start())


def _engine_file(path):
    """(doc, state, at) for one of the desk's JSON files: `off` when it is absent, `unread` when it will not read."""
    try:
        at = path.stat().st_mtime
        d = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError:
        return None, "off", None
    except (OSError, ValueError, UnicodeDecodeError):
        return None, "unread", None
    return (d, "ok", at) if isinstance(d, dict) else (None, "unread", at)


def engine_intake(d):
    """The intake's answer as the page may see it: the cards the board's own intake_cards() would list, never the desk's
    `why`. A confidential scope's or a guarded repo's card is counted by its kind under `guarded` (a fixed word: the page
    counts an alarm among the alarms), never listed, as the board keeps it as a guarded card; when the scopes do not
    read, every card is counted so and `torn` says it (the source then reads unread, never "no alarms")."""
    try:
        # one parse judges the tear and names the scopes (AGENTS.md: scope_registry() reads a torn file as no scopes)
        common = helmlib._common()
        reg, torn = common.read_registry()
        conf = common.confidential_scopes(reg=reg) if reg is not None else {}
    except Exception:  # noqa: BLE001 — scopes that do not read guard every card
        common, conf, torn = None, {}, True
    try:
        blind = bool(helmlib.guard_unread())   # guarded() cannot be trusted: every card counted, as engine_guard does
    except Exception:  # noqa: BLE001
        blind = True

    def confidential(c):
        if c.get("scope") in conf:
            return True
        for n, sc in conf.items():   # every scope that lists the repo, not ops' first (an umbrella "*" hides one)
            try:
                if common.scope_of_repo(c["repo"], reg={"scopes": {n: sc}})[0]:
                    return True
            except Exception:  # noqa: BLE001 — a scope that will not judge guards the card
                return True
        return False
    keep, hid = [], {}
    for c in d.get("open") if isinstance(d.get("open"), list) else []:
        if not isinstance(c, dict) or not c.get("repo") or c.get("number") is None:
            continue
        if torn or blind or not isinstance(c.get("scope"), (str, type(None))) or confidential(c) or helmlib.guarded(c["repo"]):
            k = re.sub(r"[^a-z]", "", str(c.get("kind") or "other").lower())[:16] or "other"
            hid[k] = hid.get(k, 0) + 1
        else:
            keep.append(c)
    return {"open": keep, "guarded": hid, "torn": torn}


def engine_guard(h):
    """The hosts document without a guarded repo's runs and entries (helmlib.guarded(), the board's K6: strip_guarded
    turns such cards into "guarded"): `hosts` fences confidential scopes only. Each dropped run counts in its row's
    fence.confined and each entry in the queue's `dropped`, so the page counts them and never lists them; every run and
    entry is dropped when guarded() cannot be trusted (guard_unread)."""
    if not isinstance(h, dict):
        return h
    try:
        torn = helmlib.guard_unread()
    except Exception:  # noqa: BLE001 — a guard that does not read guards everything
        torn = True
    hid = (lambda repo: True) if torn else (lambda repo: helmlib.guarded(repo))
    for r in (h.get("hosts") or {}).values():
        if isinstance(r, dict) and isinstance(r.get("runs"), list):
            keep = [x for x in r["runs"] if isinstance(x, dict) and not hid(x.get("repo"))]
            gone = len(r["runs"]) - len(keep)
            if gone:
                r["runs"] = keep
                if not isinstance(r.get("fence"), dict):
                    r["fence"] = {}
                fn = r["fence"]
                fn["confined"] = (fn.get("confined") if isinstance(fn.get("confined"), int) else 0) + gone
    q = h.get("queue")
    if torn and isinstance(q, dict):
        q["guard_unread"] = True   # every entry hidden: the page says the queue is unknown, never empty
    if isinstance(q, dict) and isinstance(q.get("entries"), list):
        keep = [e for e in q["entries"] if isinstance(e, dict) and not hid(e.get("repo"))]
        gone = len(q["entries"]) - len(keep)
        if gone:
            q["entries"] = keep
            q["dropped"] = (q.get("dropped") if isinstance(q.get("dropped"), int) else 0) + gone
    return h


def engine_state(raw=None, at=None, hosts=_READ):
    """The Engine room's document (engine.json): the five sources through ENGINE_ALLOW, each with its state and `at`.
    `raw` holds overview_state's ops answers (`ops`, `intake`); without it they are read here."""
    raw = raw if isinstance(raw, dict) else {}
    at = time.time() if at is None else at
    srcs, out = {}, {"at": at}
    h = hosts_json() if hosts is _READ else hosts_collect(hosts)
    hoff = h == OPS_OFF
    h = None if hoff else h
    out["hosts"] = engine_guard(engine_pick(h, ENGINE_ALLOW["hosts"])) if h else None
    srcs["hosts"] = {"state": "ok" if h else "off" if hoff else "unread", "at": h.get("at") if h and isinstance(h.get("at"), (int, float)) else (at if h else None)}
    o = raw["ops"] if "ops" in raw else ops_json("status")
    if o == OPS_OFF:
        out["ops"], srcs["ops"] = None, {"state": "off", "at": None}
    elif isinstance(o, dict):
        row = o.get("row") if isinstance(o.get("row"), dict) else None
        out["ops"] = engine_pick(o, ENGINE_ALLOW["ops"])
        # ops_json answered OPS_OFF where no desk's file is: a file there with no row that reads is a failed read
        srcs["ops"] = {"state": "ok" if row else "unread", "at": row.get("as_of") if row else None}
    else:
        out["ops"], srcs["ops"] = None, {"state": "unread", "at": None}
    try:
        common = helmlib._common()
        files = {"budgets": common.CONFIG / "lighthouse" / "ci-budgets.json", "alarms": common.LOG_DIR / "ci-budget-alarms.json"}
    except ImportError:
        files = {}
    for k in ("budgets", "alarms"):
        d, st, t = _engine_file(files[k]) if k in files else (None, "unread", None)
        out[k] = engine_pick(d, ENGINE_ALLOW[k]) if d is not None else None
        srcs[k] = {"state": st, "at": t}
    i = raw["intake"] if "intake" in raw else ops_json("intake")
    if i == OPS_OFF:
        out["intake"], srcs["intake"] = None, {"state": "off", "at": None}
    elif isinstance(i, dict):
        try:
            t = (helmlib._common().LOG_DIR / OPS_FILES["intake"]).stat().st_mtime
        except (ImportError, OSError):
            t = None
        # ops_json answered OPS_OFF where no intake file is: a `why` here is a read that failed (a torn registry, a file
        # that will not read), which ops answers with no cards; unread then, never "no alarms"
        ei = engine_intake(i)
        bad = (bool(i.get("why")) and not i.get("open")) or ei["torn"]
        out["intake"] = None if bad else engine_pick(ei, ENGINE_ALLOW["intake"])
        srcs["intake"] = {"state": "unread" if bad else "ok", "at": None if bad else t}
    else:
        out["intake"], srcs["intake"] = None, {"state": "unread", "at": None}
    for e in ((out.get("hosts") or {}).get("queue") or {}).get("entries") or []:
        if isinstance(e.get("by"), str):   # a session's first 8, as S4's hosts cuts it: never a whole id
            e["by"] = e["by"][:8]
    out["sources"] = srcs
    return out


# what moves on every sample of an unchanged fleet: clocks, gauges and the history, never worth a new version
ENGINE_SIG_DROP = {"at", "as_of", "age_s", "sampled", "created", "queued_at", "claimed_at", "started", "since",
                   "five_hour_resets", "seven_day_resets", "history", "load", "mem", "five_hour", "seven_day",
                   "fable_week", "used", "week_used", "share", "net_amount", "oldest_days", "near"}
ENGINE_SIG_TEXT = {"reason", "why", "last_refusal", "no_sample"}   # a judge's line carries the gauges in digits
ENGINE_STALE_S = 30 * 60   # a row this old reads unread on the page: crossing it is a change


def engine_sig(eng, now=None):
    """What the Engine room shows that is worth a new version: its document without ENGINE_SIG_DROP's clocks, gauges
    and `history`, its judges' lines without their digits, a released preference as a flag, and each host row only
    as fresh or past the page's 30 minutes (AGENTS.md: a change check over a rendered state never fires when it holds
    clocks)."""
    if not isinstance(eng, dict):
        return None
    hat = ((eng.get("sources") or {}).get("hosts") or {}).get("at")
    # the page's own time for a row (engine_adapter's docAt): the hosts source's at, else the document's
    now = hat if now is None and isinstance(hat, (int, float)) else eng.get("at") if now is None and isinstance(eng.get("at"), (int, float)) else (now or time.time())

    def walk(v, k=None):
        if isinstance(v, dict):
            o = {}
            for kk, x in v.items():
                if kk in ENGINE_SIG_DROP:
                    continue
                if kk == "refused_by" and isinstance(x, dict):
                    o[kk] = sorted(x)   # the page names the refusing hosts; their stamps are clocks
                elif kk in ("check", "checks") and isinstance(x, dict):
                    o[kk] = {c: bool(n) for c, n in x.items()}   # a check starts and ends all day: only "any" shows
                else:
                    o[kk] = bool(x) if kk == "prefer_off" else walk(x, kk)
            return o
        if isinstance(v, list):
            return [walk(x) for x in v]
        if k in ENGINE_SIG_TEXT and isinstance(v, str):
            return re.sub(r"\d+(?:[.,]\d+)?", "#", v)
        return v
    d = walk(eng)
    rows = ((eng.get("hosts") or {}).get("hosts") or {}) if isinstance(eng.get("hosts"), dict) else {}
    for name, r in rows.items():
        if isinstance(r, dict) and isinstance(d["hosts"]["hosts"].get(name), dict):
            t = r.get("at")
            d["hosts"]["hosts"][name]["_old"] = not isinstance(t, (int, float)) or now - t > ENGINE_STALE_S
    d.pop("sources", None)
    d["states"] = {k: (v or {}).get("state") for k, v in (eng.get("sources") or {}).items()}
    return hashlib.sha256(json.dumps(d, ensure_ascii=False, sort_keys=True, default=str).encode()).hexdigest()


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
var IKINDS=['deadman','stall','budget','contact','bug','other'];
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
