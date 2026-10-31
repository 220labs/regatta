#!/usr/bin/env python3
"""Shared by the user-wide hooks, bin/pr, bin/paste-paths and bin/session_status.py (pickup, bench/sessions): this machine's short host name and the weekly jobs' host rule (`weekly_host`), the GitHub
token git already holds, the repos cloned here, a thin GitHub REST client (with the CI and automerge settings bin/repos --github and bin/github-repo share), the worktree lock's reader and writer, the /move marker's reader, a repo's opt-in kept in repos.json, the fixed closing lines, the readers of autofinish's files, and the one formatter for money (`cost_text`: list and effective). Stdlib only — `gh` is not needed:
the token git already holds is enough. Where the core, its peers and the private config are found:
`tool()`, `repos_json()`, `CONFIG` (README).

Nothing here raises to a caller but write_owner: a missing token is None, a failed request is a status of 0.
Hooks must never cost a turn over GitHub being unreachable.
"""
import base64
import fnmatch
import glob
import hashlib
import json
import os
import re
import socket
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


# ---- where things are: the core, its peers, the private config (the design's C2, C3) ----------
# Public code names no host, login or person: what is private comes through the config directory,
# one file or symlink per item, written by whoever installs the modules (on the owner's Macs the
# overlay's bootstrap.sh). A file, not the environment: hooks, launchd jobs and launchers that
# whitelist their child's environment never see a variable a shell exported.
CONFIG = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
MARKETPLACE = Path(".claude-plugin") / "marketplace.json"


def config_read(name):
    """(lines, why) for `<config>/<name>`: its non-blank lines, stripped, a UTF-8 BOM dropped, and
    None; (None, None) when there is no such file (ENOENT, nothing else); (None, why) when it
    exists and cannot be read as UTF-8 text — no Full Disk Access, Drive not downloaded, a stray
    encoding. The one reader of the config dir: config_line, config_lines, bin/jev and the check
    below all go through it, so they never disagree on a file."""
    try:
        text = (CONFIG / name).read_text(encoding="utf-8-sig")
    except FileNotFoundError:
        return None, None
    except UnicodeDecodeError:
        return None, "not UTF-8"
    except OSError as e:
        return None, e.strerror or type(e).__name__
    return [l.strip() for l in text.splitlines() if l.strip()], None


def config_line(name):
    """The first non-blank line of `<config>/<name>`, or "" when there is none or it cannot be read."""
    return (config_read(name)[0] or [""])[0]


def config_lines(name):
    """`<config>/<name>`'s non-blank lines, or None when there is no such file or it cannot be
    read: a key written empty is an empty list, never the default."""
    return config_read(name)[0]


# ---- the core's private values (B2b; README, "Private values") --------------------------------
# Each is one file under <config>/regatta/, which the overlay writes; the core carries only a
# neutral default. Where the overlay is installed (the `regatta/overlay` marker), a key it
# must write and did not — or one that cannot be read — is an ImportError naming the keys: a
# guarded source sent unrefused, an Orca login let into a denied repo, every closing line and relay
# missed would each be silent. Hooks already fail closed (the deny hooks) or quiet (the rest) on an
# import error of the core, the no-core path. Without the overlay (a stranger's install) an absent
# key is its default. A path key must be absolute after `~`: relative, it would resolve against
# whatever the cwd happens to be.
OVERLAY_KEYS = ("owner", "guarded", "orca-deny", "log-dir", "projects")
PATH_KEYS = ("log-dir", "projects")


def overlay_installed():
    """An overlay is installed here: the config dir's `regatta/overlay` marker, which the overlay
    writes (since B14a, 2026-10-23). The only marker since B14b, which dropped the `legacy` file
    and `REGATTA_LEGACY` with the shims; every reader of "an overlay is installed" asks this."""
    return (CONFIG / "regatta" / "overlay").exists()


def config_problems():
    """One line per private-value key that is wrong: missing (where the overlay is installed),
    unreadable, or a relative path. [] when all is well. `regatta check` prints them."""
    overlay = overlay_installed()
    out = []
    for k in OVERLAY_KEYS:
        lines, why = config_read("regatta/" + k)
        if why:
            out.append("regatta/%s unreadable (%s)" % (k, why))
        elif lines is None:
            if overlay:
                out.append("regatta/%s missing" % k)
        elif k in PATH_KEYS and lines and not os.path.isabs(os.path.expanduser(lines[0])):
            out.append("regatta/%s is not an absolute path: %s" % (k, lines[0]))
    return out


# `regatta check` loads this module with _REGATTA_CHECK set, to report the problems instead of
# dying of them; no other caller has a way round the error, by design.
CONFIG_PROBLEMS = config_problems()
if CONFIG_PROBLEMS and not globals().get("_REGATTA_CHECK"):
    raise ImportError("regatta: config incomplete in %s: %s — run your overlay's bootstrap.sh --config"
                      % (CONFIG, "; ".join(CONFIG_PROBLEMS)))

# The owner the closing lines address and the start rules trust (`regatta/owner`, one line, as the
# owner writes it). Absent, the lines address no one and the override marker is `owner`'s. Not
# OWNER: the worktree lock's OWNER_FILE and write_owner are another owner.
OWNER_NAME = config_line("regatta/owner")


def _path_key(name, default):
    v = config_line("regatta/" + name)
    return Path(v).expanduser() if v and os.path.isabs(os.path.expanduser(v)) else default


# The projects folder repos are named under (bin/secrets, cloned_repos): `regatta/projects`, a
# leading `~` the home folder at load, else `projects` in the home folder.
PROJECTS = _path_key("projects", Path.home() / "projects")
# Where bin/jev's and bin/gate's usage logs go: `regatta/log-dir`, else .local/state/regatta.
LOG_DIR = _path_key("log-dir", Path.home() / ".local" / "state" / "regatta")


# ---- attribution: a session, or the sessions under a folder, counted to a project --------------
# Work done in one repo for another project (a session in a lean repo, because the other's context
# is heavy) belongs to the other in every reader of per-project time or cost. One file of JSON
# lines, `~/.local/state/regatta/attribution.jsonl` whatever `regatta/log-dir` says (an overlay may
# point that at usage data; `regatta/attribution` in the config dir moves the file, written empty it
# turns attribution off); append-only, never rewritten by code:
#   {"ts": ISO, "project": "<folder under projects>", "session": "<sessionId>" | "path": "<glob>", "why": "…"}
# `path` is a glob relative to the projects folder, a worktree's `.claude/worktrees/<topic>` part
# kept; it matches that folder and every folder under it. Resolution per (session, cwd): a session
# row wins, else a path row, else None (the reader's own project); among rows of one kind the
# newest `ts` wins, a row without a readable `ts` is the oldest, a later line breaks a tie.
# The key is optional and read only by reports, so it is checked here, when used, never in
# config_problems(): a bad value there would fail every hook's import. A relative or unreadable
# value turns attribution off with one line on stderr. Resolved once per process, as the rows are:
# a report asks for every prompt and cost row.
_ATTRIBUTION = {}
_ATTRIBUTION_FILE = []


def attribution_file():
    """The attribution file, or None when it is turned off."""
    if not _ATTRIBUTION_FILE:
        lines, why = config_read("regatta/attribution")
        f = Path.home() / ".local" / "state" / "regatta" / "attribution.jsonl"
        if why or (lines and not os.path.isabs(os.path.expanduser(lines[0]))):
            import sys
            print("regatta: regatta/attribution %s: attribution off"
                  % ("unreadable (%s)" % why if why else "is not an absolute path: " + lines[0]), file=sys.stderr)
            f = None
        elif lines is not None:
            f = Path(lines[0]).expanduser() if lines else None
        _ATTRIBUTION_FILE.append(f)
    return _ATTRIBUTION_FILE[0]


def under_projects(cwd, root=None):
    """`cwd` as a path under the projects folder (`root`, else PROJECTS), another home's prefix read
    as this one's (a path from the other Mac's transcripts); None outside it."""
    p = (str(cwd) if cwd else "").rstrip("/")
    root = str(Path(root).expanduser() if root else PROJECTS).rstrip("/")
    if p.startswith(root + "/"):
        return p
    rp, pp = Path(root).parts, Path(p).parts
    if len(rp) >= 3 and len(pp) > len(rp) and pp[len(rp) - 1] == rp[-1] and pp[:len(rp) - 2] == rp[:-2]:
        return root + "/" + "/".join(pp[len(rp):])
    return None


def projects_rel(cwd, root=None):
    """A folder relative to the projects folder, a worktree's part kept; None outside it."""
    p = under_projects(cwd, root)
    return p[len(str(Path(root).expanduser() if root else PROJECTS).rstrip("/")) + 1:] if p else None


def _attribution_ts(v):
    import datetime as dt
    try:
        t = dt.datetime.fromisoformat(str(v).strip().replace("Z", "+00:00"))
    except ValueError:
        return dt.datetime.min.replace(tzinfo=dt.timezone.utc)
    return t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)


def attribution_rows():
    """The rows as the reader resolves them, read once per process: {"file", "rows", "session":
    {id: row}, "path": [rows, newest first]}; each row {n, ts, project, kind, key, why}. No file, or
    attribution off, is no rows. A line that is no row (not JSON, not an object, no `project`, not
    exactly one of `session` and `path`) is skipped with one warning on stderr."""
    f = attribution_file()
    if str(f) in _ATTRIBUTION:
        return _ATTRIBUTION[str(f)]
    out = {"file": f, "rows": [], "session": {}, "path": []}
    _ATTRIBUTION[str(f)] = out
    try:
        lines = f.read_text(encoding="utf-8", errors="replace").splitlines() if f else []
    except OSError:
        lines = []
    rows = []
    for n, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            d = json.loads(line)
        except ValueError:
            d = None
        d = d if isinstance(d, dict) else {}
        kinds = [k for k in ("session", "path") if d.get(k)]
        if not (isinstance(d.get("project"), str) and d["project"].strip("/ ") and len(kinds) == 1
                and isinstance(d[kinds[0]], str)):
            import sys
            print("regatta: %s line %d is not an attribution row: skipped" % (f, n), file=sys.stderr)
            continue
        rows.append({"n": n, "ts": d.get("ts") or "", "when": _attribution_ts(d.get("ts")),
                     "project": d["project"].strip("/ "), "kind": kinds[0], "key": d[kinds[0]],
                     "why": d.get("why") if isinstance(d.get("why"), str) else ""})
    out["rows"] = rows
    for r in sorted(rows, key=lambda r: (r["when"], r["n"]), reverse=True):
        if r["kind"] == "session":
            out["session"].setdefault(r["key"], r)
        else:
            out["path"].append(r)
    return out


def attribution_match(session=None, cwd=None, root=None):
    """The row that attributes (session, cwd): a session row, else the newest path row whose glob is
    the folder or a parent of it; None when nothing does. `root` is the projects folder the globs are
    relative to (default PROJECTS)."""
    idx = attribution_rows()
    r = idx["session"].get(session) if session else None
    if r:
        return r
    rel = projects_rel(cwd, root)
    if rel is not None:
        for r in idx["path"]:
            g = r["key"].strip("/")
            if g and (fnmatch.fnmatchcase(rel, g) or fnmatch.fnmatchcase(rel, g + "/*")):
                return r
    return None


def attribution(session=None, cwd=None, root=None):
    """The project a session is attributed to, or None: the one reader of the attribution file
    (`regatta attribution`'s rows), for every report of time or cost by project."""
    r = attribution_match(session, cwd, root)
    return r["project"] if r else None


def regatta_root():
    """The regatta checkout this core belongs to: the monorepo above this file when it runs from
    one (a source shim sets `__file__` to the core's own path, so through a shim this is the
    checkout the shim found), else `$REGATTA_HOME`, else the `home` file (C2's order: a plugin
    cache on a Mac with a clone named there finds the clone); None when none of these names one."""
    for p in Path(__file__).resolve().parents:
        if (p / MARKETPLACE).is_file() and (p / "modules").is_dir():
            return p
    for v in (os.environ.get("REGATTA_HOME"), config_line("home")):
        if v and (Path(v).expanduser() / "modules").is_dir():
            return Path(v).expanduser()
    return None


def _installed_roots():
    """installPath of each `<plugin>@regatta` row Claude Code recorded: user scope, plus project
    scope where the cwd is inside the row's projectPath — the registry read back, never a cache
    path predicted."""
    f = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude").expanduser() / "plugins" / "installed_plugins.json"
    try:
        plugins = json.loads(f.read_text(encoding="utf-8")).get("plugins") or {}
    except (OSError, ValueError, AttributeError):
        return []
    try:
        cwd = os.path.realpath(os.getcwd())
    except OSError:   # the cwd was removed under us (a worktree removed after its merge): user rows only
        cwd = None
    out = []
    # A registry of the wrong shape is no registry: tool() is read at a deny hook's import, where a
    # raise is exit 1 and an allow (B5 review: a list for "plugins", a number for a path).
    if not isinstance(plugins, dict):
        return []
    for key, rows in plugins.items():
        if not isinstance(key, str) or not key.endswith("@regatta") or not isinstance(rows, list):
            continue
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get("installPath"), str) or not row["installPath"]:
                continue
            pp = row.get("projectPath")
            if row.get("scope") == "user" or (cwd and isinstance(pp, str) and pp
                                              and (cwd + os.sep).startswith(os.path.realpath(pp) + os.sep)):
                out.append((key.split("@")[0], Path(row["installPath"])))
    return out


def overlay_root():
    """The overlay's checkout, the path its `regatta/overlay` marker holds, or None. Since B14b
    (2026-10-23) no tool of a module is looked up there: it keeps only the shims a launcher names,
    its private files and its own scripts. A caller wants it for those, never for a module's tool."""
    v = config_line("regatta/overlay")
    return Path(v).expanduser() if v else None


legacy_root = overlay_root   # the old name (B1 to B14a), for a module copy older than B14b; read the marker


TOOL_DIRS = ("bin", "libexec", "hooks")   # libexec: a tool reached as `regatta <name>`, kept off PATH (C1)


def tool(name):
    """The path of a peer's executable or script, or None — the one lookup for every optional
    edge, so a missing module is a fallback its caller names, never a stack trace."""
    if not name or "/" in name or name in (".", ".."):
        return None
    root = regatta_root()
    if root:
        for d in TOOL_DIRS:
            hits = sorted(p for p in (root / "modules").glob("*/%s/%s" % (d, glob.escape(name))) if p.is_file())
            if hits:
                return hits[0]
    for _plugin, base in _installed_roots():
        for d in TOOL_DIRS:
            if (base / d / name).is_file():
                return base / d / name
    return None   # the overlay's checkout is no fallback since B14b: its shims are gone


def module_path(name):
    """Where module `name` is: `<root>/modules/<name>` or its installPath, else None (`regatta has`)."""
    root = regatta_root()
    if root and (root / "modules" / name / ".claude-plugin" / "plugin.json").is_file():
        return root / "modules" / name
    for plugin, base in _installed_roots():
        if plugin == name and base.is_dir():
            return base
    return None


def repos_json():
    """The registry of repos: `CLAUDE_REPOS_JSON`, else `<config>/wharf/repos.json` (a dangling link
    to it included: its read fails, never "no registry"), else None. The one reader every caller
    goes through (C3)."""
    v = os.environ.get("CLAUDE_REPOS_JSON")
    if v:
        return Path(v)
    p = CONFIG / "wharf" / "repos.json"
    return p if p.exists() or p.is_symlink() else None   # a dangling link is a registry gone, not none


def guarded_repos():
    """Names of the repos whose text never leaves the Mac: the registry's top-level `guarded`
    list, never a literal in public code; () when there is none (G32: its callers move in B6)."""
    p = repos_json()
    try:
        g = json.loads(p.read_text(encoding="utf-8")).get("guarded") if p else None
    except (OSError, ValueError, AttributeError):
        return ()
    return tuple(x for x in g if isinstance(x, str)) if isinstance(g, list) else ()


# Scopes — the groups of repos in the registry's `scopes` (wharf's bin/scopes writes their
# workspace files). A scope flagged `"confidential": true` is a node nothing outside it reads
# (knowledge-layers design D3, 2026-10-20), and its `login` is the account label its runs start
# on (`account pick --repo`); its `yard` is the host that drives its ships (skipper-resilience S2).
# These are the one reader of those keys: the fence, the passes, sheep_gate, wharf and bin/scopes
# all ask here, never repos.json themselves.

def scope_registry(path=None):
    """(repos, scopes) from the registry — `path`, else repos_json(); ({}, {}) when it cannot be
    read. Never raises."""
    p = Path(path) if path else repos_json()
    try:
        d = json.loads(p.read_text(encoding="utf-8")) if p else {}
        repos, scopes = d.get("repos") or {}, d.get("scopes") or {}
        return (repos, scopes) if isinstance(repos, dict) and isinstance(scopes, dict) else ({}, {})
    except (OSError, ValueError, AttributeError):
        return {}, {}


def read_registry(path=None):
    """(registry, unreadable) from one parse — `path`, else repos_json(): the registry as a dict, or
    None; unreadable is registry_unreadable's verdict. A caller that judges the tear and then reads a
    scope passes the dict on (scope_of_repo's `reg`), so the two never read two different files
    (helm's task_mode, the follow-ups' landing review). Never raises."""
    p = Path(path) if path else repos_json()
    try:
        if not p or not (p.exists() or p.is_symlink()):
            return None, False   # a dangling link reads below and fails: unreadable (its target moved)
        d = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None, True
    ok = isinstance(d, dict) and isinstance(d.get("repos") or {}, dict) and isinstance(d.get("scopes") or {}, dict)
    return (d, False) if ok else (None, True)


def registry_unreadable(path=None):
    """True when a registry file is there but its repos or scopes cannot be read — a torn write,
    conflict markers, a non-object. scope_registry() reads that as no scopes at all, which is open;
    a fence asks this first and fails closed on it. False with no registry file. Never raises."""
    return read_registry(path)[1]


def is_glob(m):
    return any(c in m for c in "*?[")


def scope_members(scope, repos):
    """The scope's repo keys, in its order: each listed key, then each key a glob matches (sorted)."""
    out = []
    ms = scope.get("repos") if isinstance(scope, dict) else None
    for m in ms if isinstance(ms, list) else []:
        if not isinstance(m, str):
            continue
        hits = sorted(k for k in repos if fnmatch.fnmatchcase(k, m)) if is_glob(m) else [m]
        out += [k for k in hits if k not in out]
    return out


def scope_of_key(key, path=None):
    """The name of the scope holding registry key `key`, or None."""
    repos, scopes = scope_registry(path)
    return next((n for n, s in scopes.items() if key and key in scope_members(s, repos)), None)


def confidential_scopes(path=None, reg=None):
    """{name: scope} for each scope flagged `"confidential": true` (only a real true counts). REG: a
    registry read_registry() parsed already, so a gate judges the tear and the scopes from one read."""
    scopes = (reg.get("scopes") or {}) if isinstance(reg, dict) else scope_registry(path)[1]
    return {n: s for n, s in scopes.items() if isinstance(s, dict) and s.get("confidential") is True} if isinstance(scopes, dict) else {}


SCOPE_MARK = "confidential:"


def scope_marker(name):
    """What text bound for an open repo says in place of confidential scope `name` (confidential-reach
    S5: a seed's Seeded-By line and its .review's origin): `confidential:<the first 8 hex of
    sha256(name)>`. It tells a reader that the seed came out of some confidential scope and lets this
    host's registry say which (scope_of_marker); it names nothing. Unkeyed: whoever guesses the name can
    confirm the guess against it, so it hides the name, not a name already suspected."""
    return SCOPE_MARK + hashlib.sha256(name.encode("utf-8")).hexdigest()[:8]


def scope_of_marker(marker, path=None, reg=None):
    """The confidential scope whose scope_marker() is `marker`, by this host's registry (or REG, one
    read_registry() parse) — or None: no such scope, an open one, two that share the 8 hex (refused
    rather than guessed). Never raises."""
    hits = [n for n in confidential_scopes(path, reg=reg) if isinstance(marker, str) and scope_marker(n) == marker]
    return hits[0] if len(hits) == 1 else None


def scope_login(name, path=None):
    """The account label scope `name` runs on (its `login`), or None."""
    s = scope_registry(path)[1].get(name) or {}
    v = s.get("login") if isinstance(s, dict) else None
    return v if isinstance(v, str) and v else None


def scope_yard(name, path=None):
    """The host scope `name`'s ships are driven from (its `yard`: the one Mac whose tick drives them
    and where `wharf apply --yard` lays them), or None — absent and `null` alike, so a scope with no
    yard keeps today's plain apply."""
    s = scope_registry(path)[1].get(name) or {}
    v = s.get("yard") if isinstance(s, dict) else None
    return v if isinstance(v, str) and v else None


def scope_yards(path=None):
    """{name: host} for each scope with a yard (scope_yard's rule); {} when none has one."""
    scopes = scope_registry(path)[1]
    out = {n: s.get("yard") for n, s in scopes.items() if isinstance(s, dict)}
    return {n: v for n, v in out.items() if isinstance(v, str) and v}


def confidential_roots(path=None):
    """[Path] — the checkout of every repo in a confidential scope, under PROJECTS. A worktree sits
    inside its checkout, so a prefix test covers it; no git call, for hooks."""
    repos, _ = scope_registry(path)
    return [PROJECTS / k for s in confidential_scopes(path).values() for k in scope_members(s, repos) if k in repos]


def login_dirs(home=None):
    """[Path] — every Claude config dir here: the home folder's .claude and each accounts.json row's dir that
    exists (an Orca one read back, account_home); lighthouse's registry, ACCOUNTS_FILE in tests."""
    home = home or Path.home()
    out = [home / ".claude"]
    try:
        f = Path(os.environ.get("ACCOUNTS_FILE") or CONFIG / "lighthouse" / "accounts.json")
        rows = json.loads(f.read_text(encoding="utf-8")).get("accounts") or []
    except (OSError, ValueError, AttributeError):
        rows = []
    for a in account_rows(rows, home):
        if a.get("provider", "claude") == "claude":
            d = account_home(a, home)
            if d and d not in out:
                out.append(d)
    return [d for d in out if d.is_dir()]


def project_slug(path):
    """Claude Code's folder name under <config>/projects for a start directory."""
    return re.sub(r"[^A-Za-z0-9]", "-", str(path))


def scope_paths(name, path=None, home=None):
    """[Path] — what a scope's sessions leave on this Mac, the paths the fence keeps out: per repo
    of the scope (its anchor, the knowledge repo, first) its checkout and every `git worktree list`
    entry, PROJECTS/transcripts/<repo>/, and each login dir's projects/<slug>/ for each of those
    checkouts — the transcripts and the memory both (week-digest reads the .jsonl files there). A
    worktree already removed left a folder whose slug starts with its checkout's slug and a `-`:
    a reader matches that prefix, as sheep_gate's transcript test does. A copy outside a
    registered repo is not found. [] for a scope the registry lacks. Never raises."""
    repos, scopes = scope_registry(path)
    if name not in scopes:
        return []
    logins = login_dirs(home)
    out, seen = [], set()

    def add(p):   # git names a tree by its real path: one entry per folder, the first form kept
        r = os.path.realpath(p)
        if r not in seen:
            seen.add(r)
            out.append(p)
    for key in scope_members(scopes[name], repos):
        if key not in repos:
            continue
        top = PROJECTS / key
        trees = [top]
        try:
            r = subprocess.run(["git", "-C", str(top), "worktree", "list", "--porcelain"],
                               capture_output=True, text=True, timeout=10)
            trees += [Path(l[len("worktree "):]) for l in r.stdout.splitlines() if l.startswith("worktree ")] if r.returncode == 0 else []
        except (OSError, subprocess.SubprocessError):
            pass
        trees = [t for n, t in enumerate(trees) if os.path.realpath(t) not in {os.path.realpath(x) for x in trees[:n]}]
        for t in trees:
            add(t)
        add(PROJECTS / "transcripts" / key.rsplit("/", 1)[-1])
        for d in logins:
            for t in trees:
                add(d / "projects" / project_slug(t))
    return out


def scope_match(name, path=None, home=None):
    """A test path -> bool: is it one of scope `name`'s (scope_paths)? Under one of its folders by
    the path as given or its real path, or any path part that is one of its slugs or starts with one
    and a `-`, whatever folder holds it — a login dir scope_paths did not list, a worktree already
    removed, a session's scratch folder (`<tmp>/claude-<uid>/<slug>/<session>/…`, whose parent is no
    `projects/`: 11 of a scope's rows were quoted for it, trim-cross-host D2,
    2026-10-28). The prefix over-reaches (a repo `<name>-x` beside `<name>`): for a fence that is the
    safe side. Never raises."""
    ps = scope_paths(name, path, home)
    roots = {os.path.normpath(str(p)) for p in ps} | {os.path.realpath(p) for p in ps}
    slugs = {project_slug(r) for r in roots}

    def match(p):
        try:
            s = os.path.normpath(os.path.expanduser(str(p)))
            if any(c == r or c.startswith(r + os.sep) for c in {s, os.path.realpath(s)} for r in roots):
                return True
            return any(c == g or c.startswith(g + "-") for c in Path(s).parts for g in slugs)
        except (OSError, ValueError, TypeError):
            return False
    return match


def gather_fence(scope=None, path=None, home=None):
    """What a Gather reader (week-digest, interruptions, knowledge-numbers, `repos --branches`) may do
    with an item, judged by the paths it came from (knowledge-layers S4: "nothing reads down into a
    confidential node; only generalised knowledge flows upstream"). Returns fence(*paths) ->
    "quote" (print it), "fenced" (a confidential scope's: count it, never quote it) or "outside"
    (not the scope asked for: leave it out). Without `scope` an item any path of which is a
    confidential scope's is fenced, the rest quoted. With `scope` an item of that scope is quoted —
    unless a path is also another confidential scope's (fenced) — and the rest is outside. An item
    with no path is fenced, or outside under `scope`: unknown is never quoted (quoted only where no
    scope is confidential). An unreadable
    registry fences everything (a fence fails closed, regatta AGENTS.md's Traps). ValueError: a
    scope the registry lacks, or any scope asked of a registry that cannot be read."""
    if registry_unreadable(path):
        if scope:
            raise ValueError("the registry %s cannot be read, so no scope can be" % (path or repos_json()))
        return lambda *paths: "fenced"
    if scope and scope not in scope_registry(path)[1]:
        raise ValueError("no scope %r in the registry" % scope)
    others = [scope_match(n, path, home) for n in confidential_scopes(path) if n != scope]
    own = scope_match(scope, path, home) if scope else None

    def fence(*paths):
        ps = [p for p in paths if p]
        if not ps:  # unknown is never quoted — unless no scope is confidential at all
            return "outside" if scope else "fenced" if others else "quote"
        if any(m(p) for m in others for p in ps):
            return "fenced"
        if own and not any(own(p) for p in ps):
            return "outside"
        return "quote"
    return fence

def repo_key(repo):
    """REPO as a registry key: a path under PROJECTS made relative to it (a worktree's path is its
    main checkout's key), anything else as given; None for nothing."""
    if not repo:
        return None
    s = str(repo)
    if not s.startswith("/"):
        return s
    # as written first (a checkout linked into the projects folder keeps its key), then both resolved
    for p, base in ((Path(os.path.normpath(s)), PROJECTS), (Path(s).resolve(), PROJECTS.resolve())):
        wt = p.parts.index(".claude") if ".claude" in p.parts else None
        if wt is not None and p.parts[wt + 1:wt + 2] == ("worktrees",):
            p = Path(*p.parts[:wt])
        try:
            return str(p.relative_to(base))
        except ValueError:
            continue
    return s


def scope_of_repo(repo, path=None, reg=None):
    """(name, scope) of the registry's first scope whose `repos` list REPO — a key, or a path under
    PROJECTS — each entry a key or a glob, as `scopes` reads them; (None, {}) when none does or the
    registry does not read. What a scope carries beyond its repos (`mode`, `berths`: skipper-modes
    S1, S6) is data, read here once for every module. REG: a registry read_registry() parsed already."""
    import fnmatch
    key = repo_key(repo)
    p = path or repos_json()
    try:
        if reg is not None:
            scopes = reg.get("scopes") if key else None
        else:
            scopes = json.loads(Path(p).read_text(encoding="utf-8")).get("scopes") if p and key else None
    except (OSError, ValueError, AttributeError):
        return None, {}
    for name, sc in (scopes or {}).items() if isinstance(scopes, dict) else ():
        if isinstance(sc, dict) and any(isinstance(m, str) and (m == key or (any(c in m for c in "*?[") and fnmatch.fnmatchcase(key, m)))
                                        for m in sc.get("repos") or []):
            return name, sc
    return None, {}


API = "https://api.github.com"
_host = None


def account_home(a, home=None):
    """A registry row's config dir, or None when it has none here — where bin/account's
    load_registry puts a placeholder path that is no dir. A `via: orca` row's dir is Orca's, read
    back per Mac into <home>/.claude/account-orca.json (docs/orca-accounts-2026-10-16.md); a row
    with no home never reads as the cwd. `~` is `home`. Never raises."""
    home = home or Path.home()
    try:
        if a.get("via") == "orca":
            got = (json.loads(orca_file(home).read_text()).get(a.get("label")) or {}).get("home")
        else:
            got = a.get("home")
        if not isinstance(got, str) or not got:
            return None
        return (home / got[2:] if got.startswith("~/") else Path(got)).absolute()
    except Exception:
        return None


# A secondary seat's rules, as the registry's secondary rows carry them (free_below: the owner,
# 2026-10-30, "Under 70% we can run anything", set on every row). The repos it may never
# open are the overlay's (`regatta/orca-deny`, one per line); none without the key.
ORCA_ROW = {"rules": {"week_max": 70, "window_max": 50, "free_below": 70,
                      "reserve": {"last_hours": 24, "week_max": 100}},
            "repos": {"deny": config_lines("regatta/orca-deny") or []}}


def orca_file(home=None):
    """This Mac's read-back of Orca's logins (bin/account orca-sync writes it); ACCOUNT_ORCA_FILE in tests."""
    return Path(os.environ.get("ACCOUNT_ORCA_FILE") or (home or Path.home()) / ".claude" / "account-orca.json")


def orca_row(label, enabled=True, provider="claude"):
    """The row of an Orca login no registry row names: a secondary seat (ORCA_ROW). `provider` is the
    entry's own (a Codex login Orca holds is never a Claude dir)."""
    return dict(json.loads(json.dumps(ORCA_ROW)), label=label, provider=provider, via="orca", implicit=True, enabled=enabled)


def account_rows(accounts, home=None):
    """The registry's rows, plus one row per Orca login orca-sync read back that no row names
    (the owner, 2026-10-16: "auto-picker gets all Orca accounts enabled by default, but there's a way to
    override during set up, or change it later at any point"). Such a row is `via: orca`, a
    secondary (ORCA_ROW's rules and deny list), placed just before the primary, and in the walk
    unless its entry in orca_file() says `"enabled": false` (`account orca off LABEL`; orca-sync
    writes it for a login it finds while `_default` is off, or with --off). `_default` is orca-sync's
    input only, so turning it off never moves a login already synced. An entry's `false` also turns
    a registry row of Orca's off on this Mac; it never turns on a row the registry parked. Copies;
    never raises."""
    rows = [dict(a) for a in accounts or [] if isinstance(a, dict)]
    try:
        synced = json.loads(orca_file(home).read_text())
        synced = synced if isinstance(synced, dict) else {}
    except Exception:
        synced = {}
    named = {a.get("label") for a in rows}
    for a in rows:
        e = synced.get(a.get("label"))
        if a.get("via") == "orca" and isinstance(e, dict) and e.get("enabled") is False:
            a["enabled"] = False
    extra = [orca_row(label, e.get("enabled") is not False, e.get("provider") if isinstance(e.get("provider"), str) else "claude")
             for label, e in synced.items() if not label.startswith("_") and label not in named and isinstance(e, dict)]
    at = next((n for n, a in enumerate(rows) if a.get("primary")), len(rows))
    return rows[:at] + extra + rows[at:]


def cloned_repos(coding=None):
    """[Path] — each repo in the registry cloned on this host, in PROJECTS/<name>
    (not coding.parent: from a worktree that is a folder inside the checkout). Shared by bin/repos --branches,
    bin/tend and weekly-run's dry run, which each enumerated it (aurora-sequence leftovers,
    2026-10-05); bin/autofinish and bin/pickup still build their own, with their suite
    overrides. The registry is `repos_json()`; `coding`, a checkout holding its own repos.json,
    is read instead while a caller still passes one (bin/repos until it moves, B6)."""
    path = Path(coding) / "repos.json" if coding else repos_json()
    projects = PROJECTS
    try:
        names = json.loads(path.read_text())["repos"]
    except (OSError, ValueError, KeyError, AttributeError):
        return []
    return [projects / name for name in names if (projects / name / ".git").exists()]


def host_name():
    """Lower-case short host name, `laptop` / `studio`. macOS's LocalHostName is the stable
    one (the DHCP-assigned name can change under a session); anything else falls back to the
    kernel's. Branch names carry it since 2026-09-22 (D7), so a reader can see where a branch
    came from without asking."""
    global _host
    if _host:
        return _host
    name = ""
    try:
        name = subprocess.run(["scutil", "--get", "LocalHostName"], capture_output=True,
                              text=True, timeout=5).stdout.strip()
    except Exception:
        pass
    name = name or socket.gethostname().split(".")[0]
    _host = re.sub(r"[^a-z0-9-]", "-", name.lower()).strip("-") or "host"
    return _host


def claude_host():
    """True when this process's responsible process — the one tccd charges a privacy request to — is
    claude-host, the launcher that holds the Drive grant (docs/orca-launcher-2026-10-24.md, S4). A reader
    a hook may run opens a Drive-backed file only then, and reads its local copy otherwise: an ungranted
    responsible process (Orca's app on the always-on Mac, 2026-10-24) blocks on a prompt nobody sees.
    Asked of the kernel through the same SPI claude-host uses (0.4 ms, probed 2026-10-25), never the
    process tree: a double fork keeps its responsible process and loses its ancestry. Off macOS, or on
    any error, False — the local copy, the safe side. REGATTA_CLAUDE_HOST=0|1 pins it for the suites,
    which may themselves run under claude-host in a dispatched session."""
    pinned = os.environ.get("REGATTA_CLAUDE_HOST")
    if pinned in ("0", "1"):
        return pinned == "1"
    try:
        import ctypes
        lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
        who = lib.responsibility_get_pid_responsible_for_pid
        who.argtypes, who.restype = [ctypes.c_int], ctypes.c_int
        pid = who(os.getpid())
        buf = ctypes.create_string_buffer(4096)
        if pid <= 0 or lib.proc_pidpath(pid, buf, 4096) <= 0:
            return False
        return os.path.basename(buf.value.decode("utf-8", "replace")) == "claude-host"
    except Exception:   # Linux (no libSystem), a sandbox refusing the SPI
        return False


def drive_backed(p):
    """True when the config key p is a link whose own text points under a cloud drive's mount: the one
    kind of file an ungranted process blocks on opening (S4). Only such a key is read from its local copy
    outside claude-host; a plain file, or a link elsewhere, reads as it always did — nothing blocks on it,
    and a copy there would freeze tenancy on every host without claude-host (Linux, a public install;
    the S4 finish review, 2026-10-25). Judged from readlink's text, never a stat into the drive. The
    mounts: REGATTA_DRIVE_ROOTS (':'-separated; the suites' stand-in drives), else macOS's own folder for
    File Provider drives, below."""
    try:
        p = os.fspath(p)
        if not os.path.islink(p):
            return False
        roots = os.environ.get("REGATTA_DRIVE_ROOTS") or os.path.expanduser("~/Library/CloudStorage")
        roots = {x for r in filter(None, roots.split(":"))
                 for x in (os.path.normpath(os.path.abspath(os.path.expanduser(r))), os.path.realpath(os.path.expanduser(r)))}
        for _ in range(8):   # a link to a link (a worktree's .env → main's → the drive): each hop by its text
            parent = os.path.realpath(os.path.dirname(os.path.abspath(p)))
            p = os.path.normpath(os.path.join(parent, os.readlink(p)))
            if any(p == root or p.startswith(root + os.sep) for root in roots):
                return True
            if not os.path.islink(p):   # a hop outside every drive: lstat only, never into a drive
                return False
    except (OSError, TypeError, ValueError):
        return True   # a link that cannot be read is taken as the drive's: its copy, the side that never hangs
    return False


# The weekly jobs' host rule (aurora's night, /sextant, a scope's pass): which host runs one. Here,
# not in a module of its own, because it is made of the readers above (config_read, host_name,
# read_registry, overlay_installed) and every caller already imports this file; until 2026-10-24 it
# was two copies, weekly-run's HOST_RULE and sextant-run's host_rule, kept in step by two suites.
# `aurora/host` names the one host (as host_name() prints it, case-blind). An allow-list, never a
# deny-list: a host that gets the overlay later (another Mac, a yard node) runs no night by default.
# Under the old deny-list (`aurora/skip-hosts`, the hosts never to run on) an unlisted host ran it,
# and two hosts each writing dreams/<date>.md in place conflict on push (gap review item 6,
# 2026-10-02). One host: a second line is refused, never read as a list (that is what skip-hosts
# was). A scope's pass runs on that scope's yard (the registry's `yard`), else where aurora/host
# says. The registry is read once (read_registry: the tear and the yard from one parse), never
# registry_unreadable() then scope_yard(): a write between the two reads as no yard, and the pass
# would run where aurora/host says on the same night its yard runs it; a torn registry is `closed`
# (its yard unknown: reading that as "no yard" would run it on the wrong host). The transition,
# until every overlay writes aurora/host: no aurora/host but an aurora/skip-hosts keeps the old
# rule, with a note saying the key is deprecated; neither, where the overlay is installed, refuses —
# a guess either way is a lost or a doubled dream; neither and no overlay runs (an install on one
# machine). Each job's skip line names its own installer's verb: sextant's --remove takes the ideas
# intake and its signed launcher with it, so its weekly job is unloaded with --unschedule.
WEEKLY_UNSCHEDULE = {"aurora": "aurora install.sh --schedule refuses here, --remove unloads a job loaded before",
                     "sextant": "sextant install.sh --schedule refuses here, --unschedule removes a job loaded before"}


def weekly_host(job, scope=None):
    """(verdict, line, notes): whether weekly job `job` runs on this host. verdict is `run` (line
    ""), `skip` (another host runs it), `refuse` (a key is empty, unreadable, many-lined or missing:
    the runner posts it) or `closed` (a scope's registry does not read: the log only); notes are
    lines said before it (the deprecation). Never raises on a key's content."""
    host = host_name()
    hint = WEEKLY_UNSCHEDULE.get(job)
    if scope:
        reg, torn = read_registry()
        if torn:
            return "closed", "refused: the registry %s cannot be read, so scope %s has no known yard (fails closed)" % (repos_json(), scope), []
        s = ((reg or {}).get("scopes") or {}).get(scope)
        yard = s.get("yard") if isinstance(s, dict) else None
        if isinstance(yard, str) and yard:
            if yard.lower() == host:
                return "run", "", []
            return "skip", "skipped: scope %s runs on its yard %s, not on %s (the registry names it)" % (scope, yard, host), []
    lines, why = config_read("aurora/host")
    if lines is None and not why and (CONFIG / "aurora" / "host").is_symlink():
        # config_read reads a dangling link as no file, and with no overlay that runs every host:
        # a link into a synced folder not mounted tonight would double the dream (the landing review)
        why = "a link whose target is missing"
    if why:
        return "refuse", "refused: aurora/host cannot be read (%s)" % why, []
    if lines is not None:
        if not lines:
            return "refuse", "refused: aurora/host is empty: it names no host to run on", []
        if len(lines) > 1:
            return "refuse", "refused: aurora/host names one host, and it has %d lines" % len(lines), []
        if lines[0].lower() == host:
            return "run", "", []
        return "skip", "skipped: %s does not run on %s (aurora/host names %s%s)" % (job, host, lines[0], "; " + hint if hint else ""), []
    skips, why = config_read("aurora/skip-hosts")
    if skips is None and why is None:
        if overlay_installed():
            return "refuse", "refused: no %s (your overlay's bootstrap.sh --config writes it)" % (CONFIG / "aurora" / "host"), []
        return "run", "", []
    notes = ["note: aurora/skip-hosts is deprecated: write aurora/host, the one host the weekly jobs run on "
             "(your overlay's bootstrap.sh --config)"]
    if why:
        return "refuse", "refused: aurora/skip-hosts cannot be read (%s)" % why, notes
    if host in [l.lower() for l in skips]:
        return "skip", "skipped: %s does not run on %s (aurora/skip-hosts%s)" % (job, host, "; " + hint if hint else ""), notes
    return "run", "", notes


def repo_slug(url):
    """`owner/name` from an origin URL, ssh or https, or None for a non-GitHub remote."""
    m = re.search(r"github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?/?$", url or "")
    return m.group(1) if m else None


REPOS_JSON = repos_json() or CONFIG / "wharf" / "repos.json"   # a Path always: a missing file reads as today
OVERLAY_MARK = "_from"  # the key that tells a written overlay from a repo's own workflow.json
UNREADABLE = "unreadable"  # workflow_overlay could not tell: keep whatever is there (review)


def workflow_overlay(repo, repos_json=None):
    """A repo's opt-in kept out of the repo: the `workflow` object of its entry in the
    registry (repos.json), or None. For a repo shared with people who don't run this workflow
    (a project shared with a friend, 2026-10-05): nothing lifecycle-shaped is committed there, and hooks/sync.py writes
    this into the clone as an untracked, git-excluded .claude/workflow.json, so every reader of
    that file works unchanged. The entry is matched by origin's GitHub slug, not the folder
    name: a clone re-pointed at another remote (a public twin, where prompt-quoting checkpoints
    must never go) drops off the workflow from its next session start.
    UNREADABLE when repos.json or the remote could not be read (a hand edit mid-save, a merge
    conflict): not the same as "not opted in", so callers keep what they had."""
    try:
        r = subprocess.run(["git", "-C", str(repo), "remote", "get-url", "origin"],
                           capture_output=True, text=True, timeout=10)
        repos = json.loads(Path(repos_json or REPOS_JSON).read_text()).get("repos")
        if r.returncode or not isinstance(repos, dict):
            return UNREADABLE
    except (OSError, ValueError, AttributeError, subprocess.SubprocessError):
        return UNREADABLE
    slug = (repo_slug(r.stdout.strip()) or "").lower()
    for entry in repos.values():
        if isinstance(entry, dict) and slug and str(entry.get("github", "")).lower() == slug:
            wf = entry.get("workflow")
            return dict(wf) if isinstance(wf, dict) and wf.get("checkpoint") is True else None
    return None


def token():
    """The token git already has, so nothing new is provisioned: GH_TOKEN/GITHUB_TOKEN, then
    the credential file git's `store` helper reads (a machine account's lives there),
    then `gh auth token` (the laptop). None when there is nothing — the caller pushes the
    branch anyway and skips the pull request."""
    for var in ("GH_TOKEN", "GITHUB_TOKEN"):
        if os.environ.get(var):
            return os.environ[var]
    try:
        for line in (Path.home() / ".git-credentials").read_text().splitlines():
            m = re.match(r"https://[^:]+:([^@]+)@github\.com", line.strip())
            if m:
                return urllib.parse.unquote(m.group(1))
    except OSError:
        pass
    try:
        r = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except Exception:
        pass
    return None


# One merge method for every repo (the owner, 2026-09-26: all PRs merge with the rebase option): a
# rebase merge keeps main linear and is what bin/pr merge asks for; delete-on-merge lets GitHub
# drop a merged PR's head, which sync.py's prune_gone follows. bin/repos --github checks it;
# bin/github-repo sets it on every repo it creates.
MERGE_POLICY = {"allow_merge_commit": False, "allow_squash_merge": False,
                "allow_rebase_merge": True, "delete_branch_on_merge": True}


def api(method, path, body=None, tok=None, timeout=15):
    """One request. Returns (status, decoded JSON or None); status 0 means it never got an
    answer (no token, offline, timeout)."""
    tok = tok or token()
    if not tok:
        return 0, None
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method, headers={
        "Authorization": f"Bearer {tok}", "Accept": "application/vnd.github+json",
        "Content-Type": "application/json", "User-Agent": "atlas-hooks"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"null")
        except Exception:
            return e.code, None
    except Exception:
        return 0, None


def find_pr(slug, branch, tok=None):
    """The open pull request for this head branch, or None."""
    owner = slug.split("/")[0]
    st, prs = api("GET", f"/repos/{slug}/pulls?state=open&per_page=5&head="
                         f"{owner}:{urllib.parse.quote(branch, safe='')}", tok=tok)
    return prs[0] if st == 200 and prs else None


def merged_pr(slug, branch, sha, tok=None):
    """The merged pull request whose head was this branch at exactly `sha`, or None: GitHub's
    word that this tip launched, whatever main has done to its files since — the proof sync.py's
    worktree pass falls back on when the files have moved on (D4, 2026-09-25)."""
    owner = slug.split("/")[0]
    st, prs = api("GET", f"/repos/{slug}/pulls?state=closed&per_page=10&head="
                         f"{owner}:{urllib.parse.quote(branch, safe='')}", tok=tok)
    if st != 200 or not isinstance(prs, list):
        return None
    return next((p for p in prs if p.get("merged_at") and (p.get("head") or {}).get("sha") == sha), None)


def landed_pr(slug, branch, tok=None, base=None, timeout=5):
    """The merged pull request from this head branch, at any sha, while none from it is open; else
    None, and None on any GitHub failure. merged_pr's sibling for a branch that may have moved on
    since: checkpoint.py's publish() asks it before pushing, because a session in a spent worktree
    pushed a landed branch's checkpoint history back and opened a stale WIP PR (regatta#171 after
    #169, 2026-10-25). An open PR wins: a branch someone reopened work on is live again. Only PRs
    whose head.ref is this branch count (as read_merged_pr checks), and with `base` only those
    into it: a PR merged into another claude/* branch never reached main. The short timeout keeps
    the Stop and SessionEnd hooks inside their budgets."""
    owner = slug.split("/")[0]
    st, prs = api("GET", f"/repos/{slug}/pulls?state=all&per_page=10&head="
                         f"{owner}:{urllib.parse.quote(branch, safe='')}", tok=tok, timeout=timeout)
    if st != 200 or not isinstance(prs, list):
        return None
    prs = [p for p in prs if isinstance(p, dict) and (p.get("head") or {}).get("ref") == branch]
    if any(p.get("state") == "open" for p in prs):
        return None
    return next((p for p in prs if p.get("merged_at")
                 and (base is None or (p.get("base") or {}).get("ref") == base)), None)


# The line open_pr puts in the body of a PR it had to open as a non-draft, and ready_pr's cue
# that the `hold` beside it is open_pr's own and not the owner's brake. Its "land" stays through
# the rename (the overlay's wharf-rename design): open PRs on GitHub carry this text and ready_pr
# and the overlay's `pr` find it as exact text inside the body, so a new word needs a reader of both first.
HOLD_NOTE = ("GitHub refused this pull request as a draft (HTTP 422), so it was opened ready and "
             "labelled `hold` instead: automerge must not land a branch nobody curated. "
             "`bin/pr ready` takes the label off.")


def open_pr(slug, branch, base, title, body, tok=None):
    """Open a pull request, as a draft where the plan allows it (it does on this one: the
    first hook-opened PR, on 2026-09-22, came back `draft: true`), falling back to
    a plain one on 422; the caller's `WIP:` title carries the meaning either way. Returns
    the PR dict or None.

    A non-draft PR from a `claude/*` branch is what automerge.yml arms in a repo that has it
    (docs/ci-automerge-rollout-2026-10-06.md), so the fallback labels it `hold`, says so in its
    body (HOLD_NOTE) and marks the dict `_held`: such a PR never launches itself, and ready_pr —
    the curation step — takes the label off again. The label is made first (POST
    /repos/{slug}/labels; 422 is "already exists"), not left to the issues endpoint. Best
    effort: a label that could not be added leaves the PR as GitHub made it. And it arrives a
    moment after `opened`, so the workflow may arm first and disarm on `labeled` — safe only
    while main requires a check, which holds the armed PR until that run has disarmed it."""
    for draft in (True, False):
        if not draft:
            api("POST", f"/repos/{slug}/labels", HOLD, tok=tok)  # 201 made, 422 already there
        st, pr = api("POST", f"/repos/{slug}/pulls", {"title": title, "head": branch, "base": base,
                                                     "body": body if draft else f"{body}\n\n{HOLD_NOTE}",
                                                     "draft": draft}, tok=tok)
        if st == 201:
            if not draft and isinstance(pr, dict) and pr.get("number"):
                lst, _ = api("POST", f"/repos/{slug}/issues/{pr['number']}/labels",
                             {"labels": [HOLD["name"]]}, tok=tok)
                pr["_held"] = lst == 200
            return pr
        if st != 422:
            return None
    return None


def ready_pr(pr, tok=None):
    """Take a draft PR out of draft. REST has no field for it; this is the one GraphQL call.
    Returns True when the PR is no longer a draft. A PR open_pr had to open ready and hold (its
    `_held` mark, or HOLD_NOTE in its body) loses that `hold` here, best effort: ready is the
    curated signal the draft would have given, and automerge arms on `unlabeled`. The mark is
    one-shot: HOLD_NOTE leaves the body with the label, so a later ready — after the owner labelled
    the PR `hold` themselves — finds no mark and leaves their brake on."""
    slug = ((pr.get("base") or {}).get("repo") or {}).get("full_name")
    body = pr.get("body") or ""
    if slug and (pr.get("_held") or HOLD_NOTE in body):
        st, _ = api("DELETE", f"/repos/{slug}/issues/{pr['number']}/labels/{HOLD['name']}", tok=tok)
        if st in (200, 404) and HOLD_NOTE in body:  # 404: the label never stuck; the mark is spent
            edited = edit_pr(slug, pr["number"], tok, body=body.replace(f"\n\n{HOLD_NOTE}", "").replace(HOLD_NOTE, ""))
            if edited:
                pr["body"] = edited.get("body")
        if st in (200, 404):  # a failed DELETE keeps the mark: the PR stays held, which is safe
            pr["_held"] = False
    if not pr.get("draft"):
        return True
    st, res = api("POST", "/graphql", {
        "query": "mutation($id: ID!) { markPullRequestReadyForReview(input: {pullRequestId: $id})"
                 " { pullRequest { isDraft } } }",
        "variables": {"id": pr["node_id"]}}, tok=tok)
    try:
        return st == 200 and res["data"]["markPullRequestReadyForReview"]["pullRequest"]["isDraft"] is False
    except (KeyError, TypeError):
        return False


def edit_pr(slug, number, tok=None, **fields):
    st, pr = api("PATCH", f"/repos/{slug}/pulls/{number}", fields, tok=tok)
    return pr if st == 200 else None


def merge_pr(slug, number, tok=None):
    """Rebase-merge, the one method the repos allow (D9). Returns (ok, message)."""
    st, res = api("PUT", f"/repos/{slug}/pulls/{number}/merge", {"merge_method": "rebase"}, tok=tok)
    return st == 200, (res or {}).get("message", f"HTTP {st}")


AUTOMERGE_WAIT = 180  # s: a `check` takes about a minute; three is a slow runner, not a stuck one
AUTOMERGE_GRACE = 60  # s: PR readied → automerge.yml's run has armed it (it starts in seconds)


def required_contexts(slug, base, tok=None):
    """The status contexts the base's protection requires (["check"] on a workflow repo); [] when none
    or unreadable (no protection, or a token the rule is hidden from)."""
    st, body = api("GET", f"/repos/{slug}/branches/{base}/protection/required_status_checks", tok=tok)
    if st != 200 or not isinstance(body, dict):
        return []
    return [c for c in body.get("contexts") or [] if isinstance(c, str)]


def check_state(slug, sha, contexts, tok=None):
    """("success" | "failure" | "pending", why) for the newest non-skipped check run of each required
    context on sha. A skipped run is a draft's (check.yml skips drafts, and GitHub counts it as passed:
    automerge.yml's comment); it answers nothing. No run yet is pending: it starts seconds after a push.
    A context with no check run is read from the commit's statuses: CircleCI reports `ci/circleci: <job>`
    through the Statuses API, never as a check run (the CI split, 2026-10-27). The name is URL-encoded:
    the space in it made the request invalid, and an unreadable answer reads as pending forever."""
    for ctx in contexts:
        q = urllib.parse.quote(ctx, safe="")
        st, body = api("GET", f"/repos/{slug}/commits/{sha}/check-runs?check_name={q}&per_page=20", tok=tok)
        runs = (body.get("check_runs") if st == 200 and isinstance(body, dict) else None) or []
        run = next((r for r in runs if isinstance(r, dict) and r.get("conclusion") != "skipped"), None)
        if run is None:
            state = commit_status(slug, sha, ctx, tok)
            if state == "success":
                continue
            if state in ("failure", "error"):
                return "failure", f"the required check `{ctx}` ended {state} on {sha[:8]}"
            return "pending", f"the required check `{ctx}` is still running on {sha[:8]}"
        if run.get("status") != "completed":
            return "pending", f"the required check `{ctx}` is still running on {sha[:8]}"
        if run.get("conclusion") not in ("success", "neutral"):
            return "failure", f"the required check `{ctx}` ended {run.get('conclusion')} on {sha[:8]}"
    return "success", ""


def commit_status(slug, sha, ctx, tok=None):
    """The newest state ("success" | "failure" | "error" | "pending") of status context `ctx` on sha, or
    None when it has reported nothing (or the answer is unreadable). The combined status lists the
    newest status per context."""
    st, body = api("GET", f"/repos/{slug}/commits/{sha}/status?per_page=100", tok=tok)
    statuses = (body.get("statuses") if st == 200 and isinstance(body, dict) else None) or []
    return next((s.get("state") for s in statuses if isinstance(s, dict) and s.get("context") == ctx), None)


def merge_pr_waiting(slug, number, tok=None, automerge=False, wait=AUTOMERGE_WAIT, poll=10, sleep=None,
                     head=None, contexts=None):
    """merge_pr, with a refusal read back before it counts — bin/pr merge's and sparks'.

    With `head` (the PR's head sha) and `contexts` (required_contexts of the base), nothing is merged
    until every required check has passed on that head: an admin's token (the laptop's) is not refused
    by the protection, so without this the merge landed before CI ran (two PRs on 2026-10-23; the
    check-scope landing review). A failed check refuses at once; a pending one is polled every `poll`
    s up to `wait` s, a merge automerge made meanwhile counted, and then refused with "still running":
    the caller reports that automerge lands it when the check passes (the check takes 40–90 min on a
    loaded runner, past what a session's one call may wait).

    A repo with automerge.yml and a required `check`: a token that is no admin (a machine account's) is
    refused while the check runs, and automerge launches the PR when it passes, about a minute
    later (docs/ci-automerge-rollout-2026-10-06.md). So on a refusal this polls the PR every
    `poll` s, up to `wait` s, while GitHub says auto-merge is armed, and a merge it finds is the
    answer. With `automerge` (the caller read automerge.yml on the base) it also waits up to
    AUTOMERGE_GRACE for the arming itself: the caller has just readied the PR, and the
    workflow's run takes some seconds to start. A PR that is not armed first gets one retry
    after 5 s — GitHub computes mergeability lazily (sparks' old retry: verify, then retry
    once). A PR that is not armed and cannot be — a draft, `mergeable` False or
    `mergeable_state` "dirty" (a conflict), or labelled `hold` — ends the wait at the first
    read, retry and grace skipped; a `hold` that disarms an armed PR ends it too. Returns
    (ok, message), the message on a failure being the first refusal's."""
    sleep = sleep or time.sleep
    waited = 0
    if head and contexts:
        while True:
            state, why = check_state(slug, head, contexts, tok)
            if state == "success":
                break
            if state == "failure":
                return False, why
            st, cur = api("GET", f"/repos/{slug}/pulls/{number}", tok=tok)
            cur = cur if st == 200 and isinstance(cur, dict) else {}
            if cur.get("merged_at"):
                return True, "merged by automerge once its check passed"
            if waited >= wait:
                armed = "armed" if cur.get("auto_merge") else "not armed"
                return False, f"{why} after {waited} s; automerge ({armed}) lands it when the check passes"
            sleep(poll)
            waited += poll
    ok, msg = merge_pr(slug, number, tok)
    if ok:
        return ok, msg
    first, waited, retried, armed = msg, 0, False, False
    while True:
        st, cur = api("GET", f"/repos/{slug}/pulls/{number}", tok=tok)
        cur = cur if st == 200 and isinstance(cur, dict) else {}
        if cur.get("merged_at"):
            how = "by automerge once its check passed" if armed or cur.get("auto_merge") else "(read back)"
            return True, f"merged {how} (first refused: {first})"
        if cur.get("state") == "closed" or waited >= wait:
            break
        if cur.get("auto_merge"):
            armed = True
        else:
            # Nothing will arm or merge it: a draft, a conflict (mergeable is null while GitHub
            # still computes it, False once it knows), or a `hold` — stop now, not after the grace
            labels = {(l or {}).get("name") for l in cur.get("labels") or []}
            if cur.get("draft") or cur.get("mergeable") is False or cur.get("mergeable_state") == "dirty" \
                    or HOLD["name"] in labels:
                break
            if not retried:
                sleep(5)
                waited, retried = waited + 5, True
                ok, msg = merge_pr(slug, number, tok)
                if ok:
                    return ok, msg
                continue
            if armed or not automerge or waited >= AUTOMERGE_GRACE:
                break  # disarmed (a `hold`), or never armed: nothing is coming
        sleep(poll)
        waited += poll
    return False, first


# ---- CI and automerge settings on GitHub (docs/ci-automerge-rollout-2026-10-06.md, D4) --------------
#
# A repo carrying templates/code/.github on its main needs three things only the owner's token
# sets: allow_auto_merge (with the merge policy: .github/repo-settings.json), main protected with
# the `check` context required (.github/main-protection.json), and a `hold` label, automerge's
# brake. One helper, so bin/repos --github and bin/github-repo cannot drift apart.
CHECK_YML = ".github/workflows/check.yml"
AUTOMERGE_YML = ".github/workflows/automerge.yml"
CIRCLECI_CONFIG = ".circleci/config.yml"
CIRCLECI_PREFIX = "ci/circleci: "
REPO_SETTINGS = ".github/repo-settings.json"
MAIN_PROTECTION = ".github/main-protection.json"
HOLD = {"name": "hold", "color": "B60205", "description": "automerge stays off while set"}


def contents_reader(slug, ref, tok=None):
    """read(path) -> the file's text on `ref` as GitHub has it, or None (absent or unreadable)."""
    def read(path):
        st, res = api("GET", f"/repos/{slug}/contents/{urllib.parse.quote(path)}"
                             f"?ref={urllib.parse.quote(ref, safe='')}", tok=tok)
        if st != 200 or not isinstance(res, dict) or res.get("encoding") != "base64":
            return None
        try:
            return base64.b64decode(res.get("content") or "").decode()
        except (ValueError, UnicodeDecodeError):
            return None
    return read


def _json_file(read, path):
    try:
        v = json.loads(read(path) or "null")
    except ValueError:
        return None
    return v if isinstance(v, dict) else None


def _contexts(prot):
    rsc = (prot or {}).get("required_status_checks") or {}
    names = list(rsc.get("contexts") or []) or [c.get("context") for c in rsc.get("checks") or []]
    return sorted(n for n in names if n)


def ci_settings(slug, read, tok=None, apply=False, knowledge=False, repo=None):
    """The three settings against the files on the repo's main; with `apply`, set what differs.
    `read(path)` gives a file on that main (contents_reader, or git on a just-pushed main);
    `repo` is GET /repos/{slug} when the caller has it. Returns (bad, text): how many things are
    off or failed, and one phrase for the caller's line ("" for a repo with no automerge.yml).
    A 403 or 404 is reported in the text, never raised.

    Refusals, whatever `apply` says:
      - a knowledge repo is never given automerge (D2: check only — its reviewed PR path keeps
        the review as the gate); one with automerge.yml or allow_auto_merge is reported;
      - no protection without check.yml on main, nor one naming a context no job in check.yml
        has (job key or `name:`): a required check nothing reports holds every PR forever;
      - no protection from a main-protection.json that is unreadable or requires no check, and
        no allow_auto_merge then: automerge with no required check launches a ready PR at once,
        unchecked (gh's isImmediatelyMergeable). The `hold` label, the brake, is still made;
      - allow_auto_merge only once protection reads back right;
      - main requiring no check while automerge.yml is there is its own HAZARD in the text, and
        `apply` turns allow_auto_merge off then (2026-10-07)."""
    if repo is None:
        st, repo = api("GET", f"/repos/{slug}", tok=tok)
        if st != 200 or not isinstance(repo, dict):
            return 1, f"ci settings unreadable (HTTP {st})"
    has_am = read(AUTOMERGE_YML) is not None
    if knowledge:
        found = [w for w, on in (("automerge.yml on main", has_am),
                                 ("allow_auto_merge on", repo.get("allow_auto_merge"))) if on]
        return (1, "ci: " + ", ".join(found) + " — knowledge repo, D2: check only; not applied") if found else (0, "")
    if not has_am:
        return 0, ""
    want_repo = _json_file(read, REPO_SETTINGS)
    want_prot = _json_file(read, MAIN_PROTECTION)
    has_check = read(CHECK_YML) is not None
    branch = repo.get("default_branch") or "main"
    prot_path = f"/repos/{slug}/branches/{urllib.parse.quote(branch, safe='')}/protection"
    off, failed, done = [], [], []
    if want_repo is None:
        failed.append(f"no readable {Path(REPO_SETTINGS).name} on main")

    st, _ = api("GET", f"/repos/{slug}/labels/{HOLD['name']}", tok=tok)
    if st == 404 and apply:
        st, _ = api("POST", f"/repos/{slug}/labels", HOLD, tok=tok)
        (done if st == 201 else failed).append("hold label" + ("" if st == 201 else f" (HTTP {st})"))
    elif st != 200:
        off.append("no hold label" if st == 404 else f"labels unreadable (HTTP {st})")

    pst, cur = api("GET", prot_path, tok=tok)
    have_ctx = _contexts(cur) if pst == 200 else None  # None: not known (unreadable)
    if pst == 404:
        have_ctx = []
    want_ctx = _contexts(want_prot)
    jobs = _job_names(read(CHECK_YML)) if has_check else set()
    # CircleCI reports a job as `ci/circleci: <job>` (the CI split's check-linux, 2026-10-27)
    circle = {f"{CIRCLECI_PREFIX}{j}" for j in _job_names(read(CIRCLECI_CONFIG))}
    unknown = [c for c in want_ctx if not _is_job(c, jobs) and c not in circle]
    prot_ok = bool(want_ctx) and have_ctx == want_ctx
    repo_off = {k: v for k, v in (want_repo or {}).items() if repo.get(k) != v}
    # Anything that makes the protection in the file unsafe to apply. Each would leave main
    # requiring a check nothing reports (every PR held forever) or requiring none (automerge
    # launches a ready PR unchecked), so neither protection nor allow_auto_merge goes on.
    block = ("no check.yml on main" if not has_check else
             f"no readable {Path(MAIN_PROTECTION).name}" if want_prot is None else
             f"{Path(MAIN_PROTECTION).name} requires no check" if not want_ctx else
             f"{Path(MAIN_PROTECTION).name} requires {unknown}, a name no job in check.yml has" if unknown else None)

    if block:
        failed.append(f"{block}: protection and allow_auto_merge not "
                      + ("applied" if apply else "applicable"))
        prot_ok = False  # even protection matching the file is no ground for allow_auto_merge
    elif not prot_ok:
        why = (f"{branch} unprotected" if pst == 404 else f"{branch} requires {have_ctx or 'no check'}"
               if pst == 200 else f"protection unreadable (HTTP {pst})")
        if apply and pst in (200, 404):
            st, res = api("PUT", prot_path, want_prot, tok=tok)
            if st == 200 and _contexts(res) == want_ctx:
                done.append(f"{branch} requires {want_ctx}")
                prot_ok, have_ctx = True, want_ctx
            else:
                failed.append(f"protection (HTTP {st})")
        else:
            (failed if apply else off).append(why)

    # The live hazard: automerge.yml on main and no required check — a ready claude/* PR launches at
    # once, unchecked. allow_auto_merge off narrows it (no armed auto-merge), but gh merges a
    # PR it finds already mergeable directly, so the real brakes are protection and `hold`.
    hazard = []
    if have_ctx == [] and not prot_ok:
        if repo.get("allow_auto_merge") and apply:
            st, res = api("PATCH", f"/repos/{slug}", {"allow_auto_merge": False}, tok=tok)
            if st == 200 and (res or {}).get("allow_auto_merge") is False:
                done.append("allow_auto_merge turned off (main requires no check)")
                repo = dict(repo, allow_auto_merge=False)
            else:
                failed.append(f"allow_auto_merge left on (HTTP {st})")
        hazard.append(f"{branch} requires no check while automerge.yml is on main"
                      + (" and allow_auto_merge is on" if repo.get("allow_auto_merge") else "")
                      + " — a ready claude/* PR launches unchecked; label open ones `hold`")
        repo_off = {k: v for k, v in (want_repo or {}).items() if repo.get(k) != v}
    if repo_off and apply and prot_ok and want_repo is not None:
        st, res = api("PATCH", f"/repos/{slug}", want_repo, tok=tok)
        still = [k for k, v in want_repo.items() if st != 200 or (res or {}).get(k) != v]
        if still:
            failed.append(f"settings (HTTP {st}): " + ", ".join(still))
        else:
            done.append(", ".join(f"{k}={v}" for k, v in repo_off.items()))
    elif repo_off and apply:
        failed.append("settings left off until protection holds: " + ", ".join(repo_off))
    elif repo_off:
        off.append(", ".join(f"{k}={repo.get(k)}" for k in repo_off))
    return len(hazard) + len(off) + len(failed), _ci_text(off, failed, done, hazard)


def _job_names(text):
    """The job keys and job `name:` values in a workflow's text — what a required context can
    be. Stdlib only, so not a YAML parser: jobs at two spaces under a top-level `jobs:`, their
    `name:` at four, as templates/code/.github/workflows/check.yml and every copy writes them."""
    # A job with a literal `name:` reports under that name only, so its key is not a context then.
    jobs, in_jobs, key = {}, False, None
    for line in (text or "").splitlines():
        if line.lstrip().startswith("#"):
            continue  # a comment, even at column 0, neither opens nor closes a block
        if re.match(r"\S", line):
            in_jobs = line.split("#")[0].strip() == "jobs:"
            continue
        if not in_jobs:
            continue
        m = re.match(r"^  ([A-Za-z0-9_.-]+):\s*(#.*)?$", line)
        if m:
            key = m.group(1)
            jobs[key] = key
            continue
        m = re.match(r"""^    name:\s*(['"]?)(.+?)\1\s*(#.*)?$""", line)
        if m and key:
            jobs[key] = m.group(2)
    return {n for n in jobs.values() if "${{" not in n} | {k for k, n in jobs.items() if "${{" in n}


def _is_job(context, jobs):
    """A context GitHub reports for one of these jobs: its name, or a matrix leg `<name> (<value>)`."""
    return context in jobs or any(context.startswith(f"{j} (") for j in jobs)


def _ci_text(off, failed, done, hazard=()):
    lead = ["HAZARD: " + "; ".join(hazard)] if hazard else []
    if not off and not failed and not hazard:
        return ("ci settings set: " + ", ".join(done)) if done else "ci settings ok"
    parts = lead + (["set: " + ", ".join(done)] if done else []) + \
        (["NOT set: " + "; ".join(failed)] if failed else []) + \
        (["DIFFER: " + ", ".join(off) + " — repos --github --apply"] if off else [])
    return "ci settings " + " · ".join(parts)


# ---- the one-writer lock (rules/git-workflow.md, "One writer per worktree") ------------------------
#
# <git dir>/claude/owner.json, written here only, so its fields cannot drift between
# checkpoint.py (claim) and bin/pickup (next, open's take-over). Fields: session, branch, seen
# (epoch), and `handover` (epoch) once `pickup next` handed the worktree to a fresh tab.
# branches.py reads OWNER_TTL from here; sync.py keeps a copy (it imports this module lazily).
OWNER_FILE = "owner.json"
OWNER_TTL = 2 * 3600  # an owner idle this long has gone; the next writer takes over


def read_owner(state):
    """The lock in this state dir as a dict, or None (no lock, or unreadable)."""
    try:
        lock = json.loads((Path(state) / OWNER_FILE).read_text())
    except (OSError, ValueError):
        return None
    return lock if isinstance(lock, dict) else None


def write_owner(state, session, branch, handover=None):
    """Take the lock for `session`, seen now; `handover` keeps or sets the hand-over mark.
    Through a temp file and a rename, so a reader never sees a half-written lock (read as none,
    that would let claim() overwrite it). The one helper here that raises: a lock that could not
    be written must not pass for taken."""
    import time
    lock = {"session": session, "branch": branch, "seen": time.time()}
    if handover:
        lock["handover"] = handover
    Path(state).mkdir(parents=True, exist_ok=True)
    tmp = Path(state) / f".{OWNER_FILE}.{os.getpid()}"
    tmp.write_text(json.dumps(lock))
    os.replace(tmp, Path(state) / OWNER_FILE)
    return lock


# ---- the /move marker (docs/record/teleport-design-2026-10-02.md, E4) ----------------------------
#
# `teleported.json` in a worktree's state dir (.git/worktrees/<name>/claude/, beside the
# lock): this branch's conversation went on somewhere else, so the session left here must not
# keep writing. A file and not a record in the old transcript: appending to a running
# session's own transcript is what the auto-mode classifier refused on 2026-09-29. Written by
# `pickup move` (E2/E3); read by checkpoint.py (denies writes, never commits or pushes),
# sync.py (never commits or pushes what is left) and pickup list/show. Fields: to, session,
# from_session, at (epoch), branch, pending (true: committed and pushed for a move the target
# has not made yet).
MOVED_FILE = "teleported.json"


def moved(state):
    """The marker in this state dir as a dict, or None (no marker, or unreadable)."""
    try:
        m = json.loads((Path(state) / MOVED_FILE).read_text())
    except (OSError, ValueError):
        return None
    return m if isinstance(m, dict) else None


def _clock(at):
    """03:45 today, 2026-10-01 03:45 otherwise; '?' without a time."""
    import time
    try:
        t = time.localtime(float(at))
    except (TypeError, ValueError, OverflowError, OSError):  # OSError: an epoch in ns, say
        return "?"
    return time.strftime("%H:%M" if t[:3] == time.localtime()[:3] else "%Y-%m-%d %H:%M", t)


def moved_line(m, when=None):
    """`moved to studio (session 65046969, at 03:45)` / `waiting for laptop (prepared at
    03:45)` — `when` replaces the `at …` part (pickup passes its own `2 h ago`)."""
    to = m.get("to") or "?"
    when = when or f"at {_clock(m.get('at'))}"
    if m.get("pending"):
        return f"waiting for {to} (prepared {when})"
    sid = str(m.get("session") or "")[:8]
    return f"moved to {to} (" + (f"session {sid}, " if sid else "") + f"{when})"


# ssh runs laptop → the other Mac only (design D2): the laptop types every leg. Its host name is
# config (`REGATTA_LAPTOP`, else `<config>/regatta/laptop`), never a literal here.
LAPTOP = os.environ.get("REGATTA_LAPTOP") or config_line("regatta/laptop") or "laptop"


def moved_reason(m, branch=None):
    """The one line a marked worktree answers every write and every prompt with. It names the
    way back (R7 of the design), typed where it can run: the laptop starts both directions
    between the Macs (D2), the cloud is pulled from wherever this is."""
    to = m.get("to") or "?"
    topic = re.sub(r"^claude/(?:[^/]+/)?(?:\d{4}-\d{2}-\d{2}-)?", "",
                   branch or str(m.get("branch") or "")) or "<topic>"
    when = _clock(m.get("at"))
    sid = str(m.get("session") or "")[:8]
    here = host_name()
    if m.get("pending"):
        step = (f"On {to}: /move --from-{here} '{topic}'" if to == LAPTOP else
                f"Once {to} answers: /move --to-{to} here")
        return f"⇢ this branch is waiting to move to {to}: committed and pushed at {when}. {step}. Writes here are refused."
    back = (f"or /move --from-{to} '{topic}' to bring it back" if to == "cloud" or here == LAPTOP else
            f"or on {LAPTOP}: /move --to-home sends it back")
    return (f"⇢ this branch moved to {to} at {when}" + (f" (session {sid})" if sid else "")
            + f". Work there, {back}. Writes here are refused.")


# ---- a session's successful hand-off to another machine (the owner, 2026-10-08) ----------------
#
# One file per session that handed its work to another machine and saw it take: `pickup move --to
# HOST` once the session there is proved running, `dispatch --on HOST` once HOST scheduled the run.
# Keyed by the session left behind, which has nothing more to do — "they just sit around doing
# nothing. As long as it succeeded, I don't need to see it." dispatch-rc tidy closes its Terminal
# window, and a run's watcher ends it, once it has gone idle after the hand-off. Unlike the /move
# marker it is per session, not per worktree: a move from main writes no marker, and a dispatch
# --on hands off a run, not the branch. Fields: to, what (move|dispatch), target, at (epoch).
HANDOFFS = os.path.join(os.path.expanduser("~"), "Library", "Caches", "run-seed", "handoffs")


def handed_off(sid, to, what, target=""):
    """Record that session SID handed its work to TO. Never raises: a hand-off that succeeded is
    not undone by a cache it could not write — the window just stays, as before."""
    if not sid:
        return
    try:
        os.makedirs(HANDOFFS, exist_ok=True)
        tmp = os.path.join(HANDOFFS, f".{sid}.{os.getpid()}")
        with open(tmp, "w") as f:
            json.dump({"to": to, "what": what, "target": target, "at": int(time.time())}, f)
        os.replace(tmp, os.path.join(HANDOFFS, f"{sid}.json"))
        # a record older than a day can never match again (dispatch-rc HANDOFF_TURN is minutes): drop it
        for name in os.listdir(HANDOFFS):
            p = os.path.join(HANDOFFS, name)
            if time.time() - os.path.getmtime(p) > 86400:
                os.remove(p)
    except OSError:
        pass


def handoff(sid):
    """SID's hand-off record, or None — None too when its `at` is not a number."""
    try:
        with open(os.path.join(HANDOFFS, f"{sid}.json")) as f:
            h = json.load(f)
        if isinstance(h, dict):
            h["at"] = float(h.get("at") or 0)
            return h
    except (OSError, ValueError, TypeError):
        pass
    return None


# ---- closing lines (orchestration proposal A1/A2, 2026-10-04) --------------------------
# The fixed upper-case last lines that tell the owner — and code (bin/session_status.py for pickup and bench/sessions, the
# board) — how a session ended without anyone reading the reply. Each skill states its own
# line; this table is what `bin/paste-paths --stop-hook` holds a reply to (`ending`), so a new
# line goes here and in its skill in the same change. `done`: the session's job is over. `waiting`: only the owner can move
# it on, and the line says what (the house rules, "How to talk"). `pending`: the session waits on
# something it started or watches itself — a reviewer, the check, a PR it polls — and carries on
# by itself; the owner has nothing to do (the owner, 2026-10-20: the WAITING line said "nothing to do
# yet; the reviewers are running" and still read as an ask). An ask under it is blocked
# (keel's bin/paste-paths, two_waits_findings). `idle`: nothing goes on and nothing is owed — a plain
# answer, a look that changed nothing; the owner may close it or ask more (the owner, 2026-10-29, the
# second closing-line correction that day: an answer ended WAITING FOR YOU with nothing owed). Work
# that landed ends on its skill's done line instead.
# Each line opens by addressing the owner (OWNER_NAME upper-cased, then ", "), or on its first word
# with no owner configured; a skill states its line in the addressed form, so every pattern
# below starts with _TO.
# Before the address, one mark per state, so a panel of sessions reads at a glance (the owner,
# 2026-10-29): ✅ closeable — a done line or WAITING FOR NOTHING; ⏳ work goes on without the owner —
# WAITING FOR SOMETHING, the hand-over, RELAYED; 🛑 the owner owes the next move — WAITING FOR YOU.
# The constants and CLOSING stay unmarked: bare() drops a leading mark, so every reader compares as
# before, and keel's Stop lint (mark_findings) holds a reply to the mark its kind names. A producer
# that prints a line for a session to end on prints `marked(kind, line)`.
MARKS = {"done": "✅", "idle": "✅", "pending": "⏳", "handed": "⏳", "relayed": "⏳", "waiting": "🛑"}
# Any leading pictograph run, and the space after it — not only MARKS, so a wrong mark is read as one, and
# a missing space still strips (the lint names it): without it the line read as no closing line at all.
_MARK_RE = re.compile("^([\u2190-\u2bff\U0001F000-\U0001FAFF\ufe0f\u200d]+)([*_`]*[ \t]*)")   # "**🛑** " too


def mark_for(line):
    """The mark a closing line opens with: its kind's, or 🛑 for a done line that leaves the owner a step."""
    kind = closing_kind(line)
    return MARKS["waiting"] if kind == "done" and _OWNER_STEP_RE.match(bare(line)) else MARKS.get(kind)


def marked(kind, line):
    """`line` with its kind's mark in front."""
    return f"{MARKS[kind]} {line}" if kind in MARKS else line
ADDRESS = OWNER_NAME.replace("’", "'").upper() + ", " if OWNER_NAME else ""   # straight apostrophes, as bare() reads a line
_TO = re.escape(ADDRESS)
FINISH_LINES = (ADDRESS + "IT'S FINE — THIS SESSION IS REALLY DONE. YOU HAVEN'T FORGOTTEN ANYTHING.",
                ADDRESS + "THIS SESSION IS DONE — BUT READ THE NOTE ABOVE BEFORE YOU CLOSE IT.")
WAITING_PREFIX = ADDRESS + "THIS SESSION IS WAITING FOR YOU — "
PENDING_PREFIX = ADDRESS + "THIS SESSION IS WAITING FOR SOMETHING — "
IDLE_PREFIX = ADDRESS + "THIS SESSION IS WAITING FOR NOTHING — "
# `handed`: a dispatched yolo or dnd run hands its landing to dispatch's launch (wharf-runs' yolo_launch,
# autofinish-run) — a WAITING FOR SOMETHING line, since the work goes on without the owner, but its own
# kind, so that dispatch launches on it, dispatch-rc ends the run at once, and helm raises a launch that
# never started instead of retrying the build (yolo-launch review D1-B, 2026-10-25). Before it, two runs on
# 2026-10-24 (b14b-shrink, hookwatch-date) waited on dispatch while dispatch read them as waiting on their
# own work. HANDOVER_LINE is what dispatch's prompt names; HANDED_WHAT also takes the two free forms those
# runs wrote, anchored at the what's start, so a line waiting on something else first ("the reviewers,
# then dispatch's launch") stays pending.
HANDOVER_LINE = PENDING_PREFIX + "dispatch's launch (autofinish-run)"
HANDED_WHAT = (r"(?:[Dd]ispatch's (?:(?:yolo|dnd) )?launch\b|[Dd]ispatch to start the (?:(?:yolo|dnd) )?launch\b"
               r"|autofinish-run\b).*")
# /autofinish (autofinish design E6, D7): the session is done and the launcher takes the branch.
# Allowed only when the session's own dry run says `start` — checkpoint.py's Stop checks it
# (autofinish_at_stop) and blocks the reply once otherwise; bin/autofinish lets it skip rule C's
# 40 idle minutes.
# The rename (the overlay's wharf-rename design, M3): the line /autofinish says since its writer step
# (S4), first, beside the one it said before. Every reader takes both until the aliases are dropped
# — a session started before the switch still ends on the old line — and compares with
# `in DECLARED_LINES`, never `== DECLARED_LINE`. Both literals on one line: the rename's map script
# keeps a line holding both words, so a later map run cannot make it (new, new).
DECLARED_LINES = (ADDRESS + "THIS SESSION IS DONE — IT LAUNCHES BY ITSELF.", ADDRESS + "THIS SESSION IS DONE — IT LANDS BY ITSELF.")
DECLARED_LINE = DECLARED_LINES[0]   # the line the overlay's /autofinish skill states, and the fallback quote
CLOSING = (
    ("done", "|".join(re.escape(x) for x in FINISH_LINES)),                       # /finish, /evacuate
    ("done", "|".join(re.escape(x) for x in DECLARED_LINES)),                     # /autofinish
    ("done", _TO + r"THIS WAS ONLY THE PICKUP — CLOSE THIS SESSION\. THE WORK CONTINUES "
             r"(IN THE NEW TAB|IN TERMINAL|IN ITS RUNNING SESSION|IN \S+'S WINDOW)\."),  # /pickup
    ("done", _TO + r"THIS WAS ONLY THE MOVE — CLOSE THIS SESSION\. THE WORK CONTINUES "
             r"(IN THE NEW TAB|IN TERMINAL)\."),                                   # /move --from
    ("done", _TO + r"THIS SESSION MOVED TO \S+ — CLOSE THIS TAB\. THE WORK CONTINUES THERE"
             r"(\.| ONCE YOU START IT: .+)"),                                       # /move --to
    ("done", _TO + r"THIS SESSION IS READY TO MOVE TO \S+ — CLOSE THIS TAB\. .+"),  # /move --prepare
    ("done", _TO + r"THIS SESSION GOES TO THE CLOUD FROM THE NEW TERMINAL WINDOW — .+"),
    ("waiting", _TO + r"THIS SESSION WAITS TO MOVE TO \S+ — .+"),                   # /move, peer away
    ("waiting", re.escape(WAITING_PREFIX) + r"\S.*"),                               # A1: any ask
    ("handed", re.escape(PENDING_PREFIX) + HANDED_WHAT),                            # before pending: its landing is dispatch's
    ("pending", re.escape(PENDING_PREFIX) + r"\S.*"),                               # no ask: it carries on by itself
    ("idle", re.escape(IDLE_PREFIX) + r"\S.*"),                                     # no ask, nothing going on: a plain answer
    # session-asks R4: a dispatched run that relayed its ask waits on its skipper, not on the owner
    ("relayed", r"RELAYED TO \S.* — \S.*"),
)
_CLOSING_RE = [(kind, re.compile(f"(?:{rx})$")) for kind, rx in CLOSING]
# A done line that still names a step for the owner elsewhere (a move not proved running, one prepared
# for the laptop, a teleport to answer) takes 🛑: closing the tab is safe, the work still waits on them
# (the landing review, 2026-10-29).
_OWNER_STEP_RE = re.compile(_TO + r"(?:THIS SESSION MOVED TO \S+ — CLOSE THIS TAB\. THE WORK CONTINUES THERE ONCE YOU START IT: "
                            r"|THIS SESSION IS READY TO MOVE TO |THIS SESSION GOES TO THE CLOUD FROM THE NEW TERMINAL WINDOW — )")
# Bold or backticks around the whole line only: one in a bullet or mid-sentence is *quoted*.
_MARKUP_RE = re.compile(r"^[\s*_`]+|[\s*_`]+$")
# What reads as an attempt at one — not any line that addresses the owner (a previewed
# notification is copy).
_OPENER_RE = re.compile(_TO + r"(?:THIS SESSION|THIS WAS|IT'S FINE)\b")
# Fenced code blocks — the one rule for checkpoint.py, branches.py, bin/keel and ending() below
# (memo-lint-fixes, 2026-10-05: three copies closed a ```` fence at an inner ```, and one closed
# a ``` fence at a ~~~). CommonMark's: an opener is three or more backticks or tildes (a backtick
# fence's info string holds no backtick); a closer is the same character, at least as many, and
# nothing after it but spaces, indented at most three spaces deeper than its opener. An opener
# may sit at any indent, unlike CommonMark's three spaces: the docs here nest fences inside list
# items. The closer's limit is relative for the same reason — and it is what keeps an example's
# own "    ```" inside a column-0 ```` ```markdown ```` block from closing it (aurora's dream.md,
# pipeline's generalize skill; review, 2026-10-05).
_FENCE_OPEN_RE = re.compile(r"^(\s*)(`{3,}(?=[^`]*$)|~{3,})")
_FENCE_CLOSE_RE = re.compile(r"^(\s*)(`{3,}|~{3,})\s*$")


def fence_opener(line):
    """The fence string (e.g. "````") when the line could open a fenced block, else None."""
    m = _FENCE_OPEN_RE.match(line)
    return m.group(2) if m else None


def fence_indent(line):
    return len(line) - len(line.lstrip())


def fence_closes(line, opener, indent=0):
    """Does this line close the block `opener` opened at `indent`?"""
    m = _FENCE_CLOSE_RE.match(line)
    return bool(m and m.group(2)[0] == opener[0] and len(m.group(2)) >= len(opener)
                and len(m.group(1)) <= indent + 3)


def fenced(lines):
    """For each line: inside a fenced block, its own fence lines included. A block left open
    runs to the end, as CommonMark has it."""
    out, opener, indent = [], None, 0
    for l in lines:
        if opener is None:
            opener, indent = fence_opener(l), fence_indent(l)
            out.append(opener is not None)
        else:
            out.append(True)
            if fence_closes(l, opener, indent):
                opener = None
    return out


# A closing line may be followed by links only: a reply asking about a doc ends with its edit
# link (the house rules, bin/keel), and that rule came first.
_LINK_RE = re.compile(r"https?://|\]\(")


def bare(line):
    """The line without the markup around it or its leading mark, its typographic apostrophes straight."""
    line = _MARKUP_RE.sub("", (line or "").replace("’", "'"))
    return _MARKUP_RE.sub("", _MARK_RE.sub("", line))


def mark_of(line):
    """The pictograph run that opens a line (markup around it skipped), without U+FE0F; "" for none.
    A run with no space after it comes back with a trailing "|", so it never equals a mark."""
    m = _MARK_RE.match(_MARKUP_RE.sub("", (line or "")))
    return (m.group(1).replace("\ufe0f", "") + ("" if m.group(2).strip("*_`") or m.group(2)[-1:].isspace() else "|")) if m else ""


def closing_kind(line):
    """'done', 'waiting', 'handed', 'pending', 'idle', 'relayed' or None for one line of a reply. Markup around it doesn't change what
    it says, so it doesn't change the answer."""
    line = bare(line)
    for kind, rx in _CLOSING_RE:
        if rx.match(line):
            return kind
    return None


def ending(text):
    """How one message ends: (kind, line, problem). `kind` is a CLOSING kind or None for the
    closing line it ends on (link lines after it allowed), `line` that line, bare. `problem` is
    None, ('after', line) — something other than links follows a closing line, a code block
    included — or ('unknown', line): the last line reads as a closing line but is not one."""
    raws = (text or "").splitlines()
    lines = [(raw.strip(), inside) for raw, inside in zip(raws, fenced(raws)) if raw.strip()]
    at = [i for i, (l, inside) in enumerate(lines) if not inside and closing_kind(l)]
    if not at:
        last, inside = lines[-1] if lines else ("", True)
        if not inside and _OPENER_RE.match(bare(last)):
            return None, None, ("unknown", last)
        return None, None, None
    line = lines[at[-1]][0]
    if all(not inside and _LINK_RE.search(l) for l, inside in lines[at[-1] + 1:]):
        return closing_kind(line), bare(line), None
    return None, None, ("after", line)


def ending_mark(text):
    """(want, mark) for the closing line `text` ends on, as ending() reads it: the mark it should open with
    (mark_for) and the one it does (mark_of); (None, "") for none."""
    raws = (text or "").splitlines()
    lines = [raw.strip() for raw, inside in zip(raws, fenced(raws)) if raw.strip() and not inside]
    kind, line, problem = ending(text)
    if not kind:
        return None, ""
    raw = next((l for l in reversed(lines) if closing_kind(l) and bare(l) == line), "")
    return mark_for(line), mark_of(raw)


# session-asks R2 (docs/session-asks-2026-10-09.md): what a managed run hands the owner past its
# skipper. Every WAITING line counts, bar dispatch's own refusals, which tell a run to end on one
# (bin/dispatch: the chain's depth, the run cap, an account with no room) and say a fact for the
# board, not an ask — and "nothing to do", which asks nothing. A first cut (finding 7 of the
# launch review) counted only lines naming a D-item or a manual step: against 1,015 real WAITING
# lines it caught 374 and let through "the worktree switch needs your approval", "pick option A
# or B", "say go to start the four fixes" (second review, 2026-10-11). So the default flipped;
# the regexes below stay as signals that beat an exemption ("nothing to do but approve D1").
ASK_EXEMPT_RE = re.compile(
    r"the next step waits for (?:a run to end|%s to start it)|weekly reset|\bnothing to do\b"
    % re.escape(OWNER_NAME or "the owner"), re.I)
ASK_DITEM_RE = re.compile(r"\bD\d+\b")
ASK_MANUAL_RE = re.compile(
    r"\b(?:do this now|paste|log(?:s|ged)? ?in(?:to)?|sign(?:s|ed)? ?in|press(?:es)? (?:enter|return)"
    r"|approv\w*|click|tap|run (?:this|these|the (?:line|command)s?)\b|in (?:a|your) terminal"
    r"|(?:to|in) the vault|type (?:in|`))", re.I)
# The heading form only — a line that is the heading, # or ** around it allowed — never a mention
# ("no Do-this-now block is owed") in prose.
DO_THIS_NOW_HEAD_RE = re.compile(r"^[ \t]*(?:#{1,6}[ \t]+|\*\*|__)?do this now\b[^\n]*$", re.I | re.M)


def do_this_now_block(text):
    """True when `text` holds a Do-this-now heading followed by a fenced block before the next
    heading: the paste block a run would hand the owner."""
    lines = (text or "").splitlines()
    inside = fenced(lines)
    for i, l in enumerate(lines):
        if inside[i] or not DO_THIS_NOW_HEAD_RE.match(l):
            continue
        for j in range(i + 1, len(lines)):
            if inside[j] and fence_opener(lines[j]):
                return True
            if not inside[j] and re.match(r"^[ \t]*#{1,6}[ \t]", lines[j]):
                break
    return False


def unrelayed_ask(reply, last=None):
    """What a reply hands the owner that a managed run must relay instead: 'the WAITING line' when it
    ends on one — unless the line is one of dispatch's refusals or "nothing to do" and names no
    D-item or manual step; 'a Do-this-now step' for a Do-this-now heading with a fenced block
    under it; else None."""
    kind, line, _ = ending(reply if last is None else last)
    if kind == "waiting" and line:
        signal = ASK_DITEM_RE.search(line) or ASK_MANUAL_RE.search(line)
        if signal or not ASK_EXEMPT_RE.search(line):
            return "the WAITING line"
    if do_this_now_block(reply):
        return "a Do-this-now step"
    return None


# Does a reply ask the owner to answer D-items? (the owner, 2026-10-04: "hand me the docs EVERY SINGLE TIME
# you remind me of Dx answers"; 2026-10-07: the hand-over line "should apply to every single
# message that asks for Dx to be answered".) Asking = `➤ Answer:` in the prose (outside fences
# and code spans), or a WAITING closing line that names a D-item outside parentheses — "(D6,
# 2026-10-04)" cites a decided one, the house convention. A reminder in plain prose without a
# WAITING line is left out on purpose: prose cites D-numbers all the time. bin/paste-paths and
# checkpoint.py's answer_link_block both read it: the first owns a reply that asks, the second
# only a turn that wrote D-items without asking, so one Stop never blocks twice for one line.
_NAMES_D_RE = re.compile(r"\bD\d+\b")


def asks_answers(text):
    raws = (text or "").splitlines()
    prose = "\n".join(re.sub(r"`[^`]*`", "", r) for r, inside in zip(raws, fenced(raws)) if not inside)
    if "➤ Answer:" in prose:
        return True
    kind, line, problem = ending(text)
    if problem and problem[0] == "after" and closing_kind(problem[1]) == "waiting":
        kind, line = "waiting", bare(problem[1])  # not last: paste-paths' closing check says so too
    return kind == "waiting" and bool(_NAMES_D_RE.search(re.sub(r"\([^()]*\)", "", line or "")))


# ---- autofinish's files (docs/autofinish-design-2026-10-02.md; the contract: bin/autofinish's header) --
#
# The readers live here because three places say what they hold — checkpoint.py (the prompt
# note, the refused write), sync.py (the session-start line) and bin/repos (the groups) — and
# bin/autofinish writes the ones it owns through the same names. E1's runner writes the run
# record and the log line; nothing here writes either.
AUTOFINISH_RUN = "autofinish.json"   # per worktree, <git dir>/claude/: the run, written by E1
AUTOFINISH_OVERRIDE = "autofinish"   # per worktree, <git dir>/claude/: /autofinish's marker (rule C)
AUTOFINISHED = "autofinished"        # per repo, <common git dir>/claude/: one line per ended run


def autofinish_state_dir():
    """Where this Mac keeps autofinish's own state: `armed`, the tried tips, the sweep lock."""
    return Path(os.environ.get("AUTOFINISH_STATE_DIR") or Path.home() / ".local/state/autofinish")


def _json_object(path):
    try:
        d = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None
    return d if isinstance(d, dict) else None


def autofinish_armed():
    """{"by", "ts"} when this Mac's launcher may start runners, else None (disarmed: the default)."""
    return _json_object(autofinish_state_dir() / "armed")


# bin/autofinish-run's end line, one per ended run in the dated autofinish log, and the reader
# bin/autofinish's launch door counts with: one home for both, so neither re-parses the other's
# prose (widen review, 2026-10-07). Fields: iso, repo, branch, outcome, " gate=<g>" or "",
# " pr=#<n>" or "", session, tip, rule, by, the first line kept, "; <notes>" or "".
RUN_END = "%s run %s %s %s%s%s session=%s tip=%s rule=%s by=%s account=%s — %s%s"
# account= since the account pool (2026-10-08): optional, so the lines before it still count.
# `launched` since the overlay's launcher switched (rename S4), `landed` before; both forever: the
# launch door counts the week's old lines beside the new (the wharf-rename design, M8, risk R2).
RUN_LAUNCHED = re.compile(r"^(\S+) run (\S+) (\S+) (?:landed|launched)(?: gate=\S+)?(?: pr=#\S+)? session=(\S+) tip=\S+ rule=\S+ by=(\S+)(?: account=\S+)? —")
# The old name, for an overlay whose callers still say RUN_LANDED (not RUN_LAUNCHED): the core
# launches first (the overlay's main imports it before its reader step says RUN_LAUNCHED). It goes
# once no overlay caller says RUN_LANDED instead of RUN_LAUNCHED (S8).
RUN_LANDED = RUN_LAUNCHED
# An ended run's outcome that merged its branch (autofinish.json's `outcome`, the `autofinished`
# lines, RUN_END's): `launched` once the overlay's writers switch (S4), `landed` before; every reader
# takes both forever (M7).
LAUNCHED_OUTCOMES = ("launched", "landed")
# The runner's gate for a start refused before any session: nothing ran. `not-launched` until the
# start word changed (2026-10-17); read both forever — old run records and dated logs keep the old
# word. One home for the launcher, its runner and the stall reader.
REFUSED = "refused"
NOT_LAUNCHED = "not-launched"
REFUSED_GATES = (REFUSED, NOT_LAUNCHED)


# Rule L (the owner, 2026-10-13: "If the code is deployed already, it should be landed ASAP"): a commit
# whose `Deployed:` line says something went live. The line is free text (`yes`, `no`, `<what>`),
# so the values that say nothing is live yet are read as not deployed — no, none, n/a, a dash, and
# the future ones (`on merge`, `after the merge`, `once …`, `when …`, `later`): those were all in
# the repos' history when L was built, and each would have started a launch (review at /finish).
# One home for bin/autofinish and checkpoint.py's Stop, so the two never disagree.
DEPLOYED_LINE = re.compile(r"^Deployed:[ \t]*(.*)$", re.M)
NOT_DEPLOYED = re.compile(r"^[`'\"*_( ]*(?:no|none|nothing|n/?a|not|never|pending|later|tbd|on merge|"
                          r"at merge|after|once|when|will|until)\b|^[`'\"*_ \-—–.]*$", re.I)
L_SINCE = 1791961200  # 2026-10-14 00:00 PDT: rule L launches deploys committed from here on


def deployed(message):
    """The first `Deployed:` value in a commit message that says something went live, or None."""
    for m in DEPLOYED_LINE.finditer(message or ""):
        value = m.group(1).strip()
        if value and not NOT_DEPLOYED.match(value):
            return value
    return None


# The `by` the owner's /autofinish writes into its marker: OWNER_NAME lower-cased, `owner` without one.
OVERRIDE_BY = (OWNER_NAME or "owner").lower()


def autofinish_override(state):
    """Rule C's marker, or None. Anything but a JSON object the owner's /autofinish wrote is no
    override: a stray file must not lift the start rules."""
    m = _json_object(Path(state) / AUTOFINISH_OVERRIDE)
    return m if m and m.get("by") == OVERRIDE_BY else None


def autofinish_run(state):
    """This worktree's run record (bin/autofinish's contract), or None."""
    return _json_object(Path(state) / AUTOFINISH_RUN)


def autofinish_running(state, owner):
    """The run record while its runner still holds this worktree's lock, else None. A record
    whose lock is gone without an `ended` is a runner that died: it is not said to be running."""
    rec = autofinish_run(state)
    if not rec or rec.get("ended") or not owner or not rec.get("session"):
        return None
    return rec if owner.get("session") == rec.get("session") else None


def autofinish_window(rec, branch=None):
    """The runner's window name: the record's, else `finish · <topic>`."""
    if rec.get("window"):
        return rec["window"]
    topic = re.sub(r"^claude/(?:[^/]+/)?(?:\d{4}-\d{2}-\d{2}-)?", "", branch or "") or "?"
    return f"finish · {topic}"


def iso_clock(iso):
    """`03:45` today, `2026-10-01 03:45` otherwise, from an ISO time; '?' when unreadable."""
    import datetime
    try:
        t = datetime.datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
    except ValueError:
        return "?"
    return _clock(t.timestamp())


def autofinish_outcome(rec):
    """What an ended run came to, in the words the prompt note uses, or None while it runs."""
    outcome = rec.get("outcome")
    if outcome in LAUNCHED_OUTCOMES:
        return f"this branch launched as #{rec.get('pr') or '?'}"
    if outcome == "stopped":
        return f"autofinish stopped here at {rec.get('gate') or '?'}"
    if outcome == "never-started":
        return "autofinish stopped here: its runner never started (bin/dispatch --status has the screen's last lines)"
    if outcome == "died":
        return ("autofinish's runner died here before an outcome (the Mac lost power or the process was "
                "killed; nothing merged) — the sweep judges the branch once more")
    return None


def autofinished(common_dir):
    """The repo's ended runs, oldest first: {"ts", "outcome", "branch", "detail", "raw"} per
    line of <common git dir>/claude/autofinished (`<iso> <outcome> <branch> <detail>`)."""
    try:
        text = (Path(common_dir) / "claude" / AUTOFINISHED).read_text(encoding="utf-8")
    except OSError:
        return []
    out = []
    for raw in text.splitlines():
        parts = raw.split(" ", 3)
        if len(parts) >= 3 and parts[1] in LAUNCHED_OUTCOMES + ("stopped", "never-started", "died"):
            out.append({"ts": parts[0], "outcome": parts[1], "branch": parts[2],
                        "detail": parts[3] if len(parts) > 3 else "", "raw": raw})
    return out


def autofinished_phrase(e):
    """One ended run as a line for the owner: `claude/x launched as #12` / `claude/y stopped at G4: …` /
    `claude/z died before an outcome at 1a2b3c4: …`."""
    if e["outcome"] in LAUNCHED_OUTCOMES:
        return f"{e['branch']} launched as {e['detail'] or '#?'}"
    if e["outcome"] == "stopped":
        return f"{e['branch']} stopped at {e['detail'] or '?'}"
    if e["outcome"] == "died":  # detail: `<tip7> <its dispatch log's last line>`
        tip, _, last = (e["detail"] or "?").partition(" ")
        return f"{e['branch']} died before an outcome at {tip}" + (f": {last}" if last else "")
    return f"{e['branch']} never started" + (f": {e['detail']}" if e["detail"] else "")


# ----------------------------------------------------------------------------- cost: list and effective

# The owner, 2026-10-05: never an API list price alone — "$1.33 ($0.03 effective)", list first. Effective is
# what the money really costs: the plan's price over the list-price spend it buys in an average week
# (the owner's method, 2026-10-04: $200 ÷ days-in-month × 7, over a week's list spend). `bin/usage-report
# ratio` recomputes it every week and commits it to the owner's private records (spend is personal; this
# repo goes public). A provider the file does not name is pay-per-use: effective = list.
# Resolved: usage-report commits it with git, which needs the real file inside its repo, not the
# config dir's link to it (the gate's `set` does the same for its table).
COST_RATIO = Path(os.environ.get("COST_RATIO") or CONFIG / "regatta" / "cost-ratio.json").resolve()


_PROVIDER_ALIASES = {"claude": "anthropic"}
_ratio_cache = {}


def _ratio_file():
    """The ratio file's providers, read once per version of the file (a report formats dozens of
    amounts; a write mid-render is a new version). {} when missing or of any other shape."""
    try:
        key = (str(COST_RATIO), COST_RATIO.stat().st_mtime_ns)
    except OSError:
        return {}
    if key not in _ratio_cache:
        try:
            p = json.loads(COST_RATIO.read_text(encoding="utf-8"))["providers"]
            _ratio_cache[key] = p if isinstance(p, dict) else {}
        except Exception:
            _ratio_cache[key] = {}
    return _ratio_cache[key]


def cost_ratio(provider="anthropic"):
    """(ratio, entry) for a provider: entry is its record in the ratio file (None when the provider
    is pay-per-use, ratio 1.0). (None, None) when the file has no usable entry for a provider that
    should have one, so a caller never shows a made-up effective number. Never raises: a hook
    calling this must not lose its turn over a file edited by hand."""
    provider = _PROVIDER_ALIASES.get(provider.lower(), provider.lower())
    try:
        entry = _ratio_file()[provider]
        if float(entry["ratio"]) > 0:
            return float(entry["ratio"]), entry
    except Exception:
        pass
    return (None, None) if provider == "anthropic" else (1.0, None)


def ratio_note():
    """The ratio in use, in one phrase: "Anthropic list × 0.0177, week ending 2026-10-04"."""
    r, e = cost_ratio()
    return (f"Anthropic list × {r:.4f}, week ending {e.get('week_ending', '?')}" if r
            else f"no usable ratio in {COST_RATIO}")


def usd(x):
    """$2,442 · $1.33 · $0.046 · $0.00067: whole dollars from $10, cents from 10¢, two significant
    digits below — an effective cost is often a fraction of a cent and "$0.00" says nothing."""
    sign, x = ("-", -x) if x < 0 else ("", x)
    if round(x) >= 10:
        return f"{sign}${x:,.0f}"
    if round(x, 2) >= 0.1 or x == 0:
        return f"{sign}${x:,.2f}"
    digits = 1
    while round(x * 10 ** digits, 1) < 10 and digits < 8:
        digits += 1
    return f"{sign}${x:.{digits}f}"


def cost_text(list_usd, provider="anthropic"):
    """The one way any script shows money spent on a model: "$1.33 ($0.03 effective)"."""
    ratio, _ = cost_ratio(provider)
    if ratio is None:
        return f"{usd(list_usd)} (effective unknown: no ratio)"
    return f"{usd(list_usd)} ({usd(list_usd * ratio)} effective)"


def extra_usage(xu):
    """A usage answer's `extra_usage` object (paid overage past the plan's windows) → the fields a
    reader keeps: {"enabled", "user_disabled", "spend_limit_reached", "used_credits", "monthly_limit",
    "utilization"}, each None when absent; None when xu is no dict (a reading without the field). One
    parse for both shapes that carry it, the /usage cache in .claude.json (`utilization.extra_usage`,
    plumb's usage-report) and the get_usage control answer (`rate_limits.extra_usage`, lighthouse's
    account; probed 2026-10-24, the same keys bar `user_disabled` and
    `spend_limit_reached`, which the control answer lacks: None there) — costs S8, docs/host-power-costs-2026-10-24.md."""
    if not isinstance(xu, dict):
        return None
    return {"enabled": xu.get("is_enabled"), "user_disabled": xu.get("user_disabled"),
            "spend_limit_reached": xu.get("spend_limit_reached"), "used_credits": xu.get("used_credits"),
            "monthly_limit": xu.get("monthly_limit"), "utilization": xu.get("utilization")}


# A zero amount ($0, $0.00) needs no effective figure: zero times any ratio is zero (the owner, 2026-10-18).
_DOLLAR_RE = re.compile(r"(?<![\w$])\$(?!0+(?:\.0+)?(?!\d)(?!\.\d))\d")
_AMT = r"\$\d[\d,]*(?:\.\d+)?\s*[kKmM]?"
# "$1.33 ($0.02 effective)", "$4 ($0.07 eff.)", "$0.07 effective": the dollars these cover are fine
_PAIRED_RE = re.compile(_AMT + r"[^$()]{0,40}?\(\s*" + _AMT + r"\s+eff(?:ective|\.)?\b[^)]*\)|" + _AMT + r"\s+effective\b", re.I)
_EFFECTIVE_RE = re.compile(r"\beffective\b|\beff\b", re.I)
_LIST_ONLY_RE = re.compile(r"list[- ]only", re.I)
_INLINE_CODE_RE = re.compile(r"`[^`]*`")


def bare_costs(text):
    """(line number, line) for each dollar amount in a Markdown doc shown without its effective
    cost: no "effective" on the line, nor in the header of the table it sits in. Fenced code is
    skipped. A line that is list on purpose (a vendor's invoice, a domain price) says `list-only`;
    a zero amount ($0, $0.00) needs no effective figure.
    The owner, 2026-10-05: every analysis or benchmark doc and deck shows effective costs and prices."""
    lines = text.splitlines()
    code = fenced(lines)
    out, header = [], None
    for i, raw in enumerate(lines):
        if code[i]:
            header = None
            continue
        l = raw.strip()
        s = l.lstrip("> ").strip() if l.startswith(">") else l  # a quoted table keeps its header
        if s.startswith("|"):
            if header is None:
                header = s
            if _EFFECTIVE_RE.search(header):
                continue
        else:
            header = None
        if _LIST_ONLY_RE.search(l):
            continue
        # A hard-wrapped "$1.33 ($0.02" + "effective)" pairs across the break: read on into the next line.
        nxt = lines[i + 1].strip() if i + 1 < len(lines) and not code[i + 1] else ""
        joined = l + " " + nxt
        masked = _INLINE_CODE_RE.sub(lambda m: " " * len(m.group()), joined)  # `$1` in a shell snippet is not money
        covered = [m.span() for m in _PAIRED_RE.finditer(joined)]
        if any(m.start() < len(l) and not any(a <= m.start() < b for a, b in covered)
               for m in _DOLLAR_RE.finditer(masked)):
            out.append((i + 1, l))
    return out


# The owner, 2026-10-18: "effective pricing should only apply to Claude prices (or other providers where
# claimed and real-life price is different)". So an effective figure on real money (cash, rent, a
# recurring bill) is wrong. The marker must touch the figure, not merely share its line: docs
# routinely put a Claude cost and a plan's monthly bill (list-only) on one line, and a line-wide match
# flagged 6 false lines of 7 across the owner's docs (review, 2026-10-18). Two shapes:
#   "$44 ($0.84 effective) a month" / "… /mo" / "… (list-only)": a cadence or list-only right after it;
#   "rent: $12 ($0.23 effective)" / "the domain is $12 (…)": rent, a subscription or a domain just before.
_FIG = _AMT + r"\s*\(\s*" + _AMT + r"\s+eff(?:ective|\.)?\b[^)]*\)"
_REAL_MONEY_RE = re.compile(
    _FIG + r"\s*(?:\(\s*)?(?:a\s+month|/mo(?:nth)?|per[- ]month|monthly|a\s+year|/yr|/year|per[- ]year"
    r"|yearly|annual(?:ly)?|a\s+user\s+a\s+month|list[- ]only)\b"
    r"|\b(?:rent|subscriptions?|domains?)\b[^$;.]{0,20}" + _FIG,
    re.I)


def real_money_effective(text):
    """(line number, line) for each line of a Markdown doc where an `($… effective)` figure is real
    money: a cadence or `list-only` right after it, or rent, a subscription or a domain just before
    (_REAL_MONEY_RE). Fenced code and inline code are skipped. One line at a time, and an Effective
    table column is not read: a figure wrapped across a break, or a table row, is not seen (a
    warning-grade check, so it errs towards quiet)."""
    lines = text.splitlines()
    code = fenced(lines)
    out = []
    for i, raw in enumerate(lines):
        if code[i]:
            continue
        l = raw.strip()
        masked = _INLINE_CODE_RE.sub(lambda m: " " * len(m.group()), l)
        if _REAL_MONEY_RE.search(masked):
            out.append((i + 1, l))
    return out


def run_group(cmd, timeout, env=None):
    """subprocess.run(capture_output, text) in its own process group; on the timeout the whole
    group is killed, not just `cmd`: bin/account's `claude -p` probe outlived a killed parent
    with no deadline of its own (review of the autofinish pool, 2026-10-08). Raises
    TimeoutExpired, as subprocess.run does."""
    import signal
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
                         start_new_session=True)
    try:
        out, err = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        p.communicate()
        raise
    return subprocess.CompletedProcess(cmd, p.returncode, out, err)


# ---- spacesheep plans: what the account has, and its 24-hour publish budget ---------------------
# Regatta runs with no spacesheep, on its free plan, or on a paid one (the owner, 2026-10-24: adapt
# to Free or none; use Pro and Max to the full when paid). Facts, spacesheep.dev/plans and the CLI
# 1.31.0's source, read 2026-10-24: Free deploys pages with comments and versions, 400 publishes per
# 24 h; Pro adds session hooks, Talk and 2,000 publishes; Max adds Streams. `spacesheep talk status`
# (the MCP's talk_settings) is the one cheap read that says anything about the plan: `pro` and
# `enabled`; `whoami --json` carries no plan, and nothing tells Pro from Max, so Max reads as Pro.
#
# The count is per Mac, the cap per account: keel's pages and helm's board and ship pages append to
# this Mac's log, and nothing here sees another Mac's deploys, or one made from a browser or another
# tool. So the shares below divide the cap by the machines that publish from the account
# (`sheep/machines` in the config dir, else the hosts `lighthouse/hosts` lists, else 1: one fleet
# list, not a second count to keep in step): helm stops redeploying at SHEEP_HELM_SHARE of a
# Mac's part, keeping a quarter of the account's cap for keel's answer pages across every Mac, and
# keel (which never skips: an answer page is the owner's) warns at SHEEP_KEEL_WARN of it.
SHEEP_CAPS = {"free": 400, "pro": 2000}
SHEEP_PLAN_TTL = 3600     # s: the poll reads the plan once an hour, not every tick
SHEEP_HELM_SHARE = 0.75
SHEEP_KEEL_WARN = 0.9
SHEEP_PLAN_URL = "spacesheep.dev/plans"
SHEEP_KEEP = 25 * 3600    # s: the deploy log keeps the 24-hour window and an hour's margin
SHEEP_REFUSED_HOLD = 3600  # s: a cap refusal that named no retry holds helm this long
# A refusal for the publish cap: the server's code is unverified (the CLI prints `deploy refused —
# <error>: <message> (retry in Ns)` for any publish guard), so a limit word counts only with
# "publish" or the 24 hours beside it: a deploy's own limits ("too many files", "file size limit
# exceeded", "storage quota exceeded") and a bare rate_limited are other refusals (landing review).
_SHEEP_LIMIT_RE = re.compile(r"rate.?limit\w*|limit\w*|\bcap\b|quota|too many|daily", re.I)
_SHEEP_CAP_NEAR_RE = re.compile(r"publish|\b24\s*-?\s*h(?:ou)?r?s?\b|\bper 24\b", re.I)
_SHEEP_RETRY_RE = re.compile(r"retry in (\d+)\s*s", re.I)


def sheep_dir():
    """This Mac's spacesheep state: $REGATTA_SHEEP_DIR, else `sheep` in the core's LOG_DIR. None
    when MEMO_SHEEP_BIN names a stand-in CLI and no REGATTA_SHEEP_DIR goes with it: a suite's stub
    deploy must never count against the account, nor its stub plan stand for the real one."""
    d = os.environ.get("REGATTA_SHEEP_DIR")
    if d:
        return Path(d)
    if "MEMO_SHEEP_BIN" in os.environ:
        return None
    return LOG_DIR / "sheep"


def _sheep_plan_from(status):
    """talk status's JSON as {"pro", "talk"}: either None when the answer did not say."""
    pro = status.get("pro") if isinstance(status.get("pro"), bool) else None
    on = status.get("enabled") if isinstance(status.get("enabled"), bool) else None
    return {"pro": pro, "talk": None if pro is None else pro and on is not False}


def sheep_plan(cli=None, env=None, refresh=False, cached_only=False):
    """What this account's plan allows, as far as this Mac can tell:
        {"cli": bool, "pro": True|False|None, "talk": True|False|None, "talk_off": bool,
         "plan": "none"|"free"|"pro"|"unknown", "cap": int, "at": epoch s, "error": str|None}
    `cli` is the caller's spacesheep CLI (None: no spacesheep here, which is a plan, not an error);
    `env` its environment (the key). Cached in sheep_dir()/plan.json for SHEEP_PLAN_TTL; a failed
    read is cached too, so a Mac offline does not call the CLI every tick, and it keeps the plan the
    last good read found (only `at` and `error` change): one failed read must not drop Pro to Free's
    cap for an hour. `cached_only` (a hook, a page draw) never runs the CLI: no cache is None, and a
    cache of any age is returned (a caller that needs a fresh one judges `at`). $REGATTA_SHEEP_PLAN
    (none, free, pro, pro-off) stands in for the read in tests. A plan never read is budgeted as
    Free: the cap that is wrong only safely."""
    fake = os.environ.get("REGATTA_SHEEP_PLAN")
    if fake:
        pro = {"free": False, "pro": True, "pro-off": True}.get(fake)
        return _sheep_plan_row(fake != "none", pro, None if pro is None else fake == "pro", None, time.time())
    if not cli and not cached_only:
        return _sheep_plan_row(False, None, None, None, time.time())
    d = sheep_dir()
    path = d / "plan.json" if d else None
    old = None
    if path:
        try:
            old = json.loads(path.read_text())
            old = old if isinstance(old, dict) else None
        except (OSError, ValueError):
            old = None
        try:
            if old and not refresh and (cached_only or time.time() - float(old.get("at") or 0) < SHEEP_PLAN_TTL):
                return old
        except (ValueError, TypeError):
            pass
    if cached_only:
        return None
    try:
        r = subprocess.run([cli, "talk", "status"], capture_output=True, text=True, env=env, timeout=20)
        i = r.stdout.find("{")
        status = json.loads(r.stdout[i:]) if i >= 0 else {}
        err = None if r.returncode == 0 and isinstance(status, dict) and status else \
            ((r.stderr or r.stdout).strip().splitlines() or ["exit %d" % r.returncode])[-1][:200]
    except (OSError, ValueError, subprocess.TimeoutExpired) as e:
        status, err = {}, str(e)[:200]
    p = _sheep_plan_from(status if isinstance(status, dict) and not err else {})
    if err and old and old.get("cli") and old.get("plan") in ("free", "pro"):
        row = dict(old, at=time.time(), error=err)   # the last good read's plan stands
    else:
        row = _sheep_plan_row(True, p["pro"], p["talk"], err, time.time())
    if path:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            tmp = path.with_name("plan.json.%d.tmp" % os.getpid())
            tmp.write_text(json.dumps(row, sort_keys=True))
            tmp.replace(path)
        except OSError:
            pass
    return row


def _sheep_plan_row(cli, pro, talk, err, at):
    plan = "none" if not cli else {True: "pro", False: "free"}.get(pro, "unknown")
    return {"cli": cli, "pro": pro, "talk": talk, "talk_off": pro is True and talk is False, "plan": plan,
            "cap": SHEEP_CAPS["pro" if pro else "free"], "at": at, "error": err}


def sheep_plan_words(plan):
    """A budget's or a plan row's `plan` as a sentence says it: "Pro", "Free", or, for a plan never
    read, "Free, as far as this Mac knows" (the cap it is budgeted at; never "Unknown")."""
    name = plan if isinstance(plan, str) else (plan or {}).get("plan")
    return {"free": "Free", "pro": "Pro", "none": "none"}.get(name, "Free, as far as this Mac knows")


def sheep_talk_refusal(plan):
    """The one line a relay says when the account cannot carry Talk, or None when it can or the
    plan is not known (then Talk is tried as before, and its own refusal is the answer)."""
    if not plan or plan.get("talk") is not False:
        return None
    if plan.get("talk_off"):
        return "Talk is off for this account (spacesheep.dev/settings/talk) — the file backend still relays on this Mac"
    return "Talk needs spacesheep Pro (%s) — the file backend still relays on this Mac" % SHEEP_PLAN_URL


def sheep_record(by, ok=True, what="", err=""):
    """Append one deploy to this Mac's log (`by`: keel, helm-board, helm-ship); `ok=False` is a
    refusal for the publish cap, kept with the `until` its `retry in Ns` names (else an hour), which
    helm's redeploys hold for. Never raises: a deploy that happened must not fail on its bookkeeping.
    Writers take `deploys.lock`, never the log itself: the prune writes a new file and renames it
    over the log, so readers (no lock) see the old file or the new one, never a half. The prune
    runs when the oldest row is past twice SHEEP_KEEP, so about once a day, not on every append."""
    d = sheep_dir()
    if not d:
        return
    path = d / "deploys.jsonl"
    now = time.time()
    row = {"ts": round(now, 1), "by": by, "ok": bool(ok), "what": what[:80]}
    if not ok:
        m = _SHEEP_RETRY_RE.search(err or "")
        row["until"] = round(now + (int(m.group(1)) if m else SHEEP_REFUSED_HOLD), 1)
    try:
        import fcntl
        d.mkdir(parents=True, exist_ok=True)
        with open(d / "deploys.lock", "a") as lk:
            fcntl.flock(lk, fcntl.LOCK_EX)
            with open(path, "a+") as f:
                f.write(json.dumps(row) + "\n")
                f.seek(0)
                first = f.readline()
            if _sheep_ts(first) < now - 2 * SHEEP_KEEP:
                keep = [l for l in path.read_text().splitlines() if _sheep_ts(l) > now - SHEEP_KEEP]
                tmp = path.with_name("deploys.jsonl.%d.tmp" % os.getpid())
                tmp.write_text("".join(l + "\n" for l in keep))
                tmp.replace(path)
    except OSError:
        pass


def _sheep_ts(line):
    try:
        return float(json.loads(line).get("ts") or 0)
    except (ValueError, TypeError, AttributeError):
        return 0.0


def _sheep_rows(hours=24):
    d = sheep_dir()
    if not d:
        return []
    since = time.time() - hours * 3600
    try:
        lines = (d / "deploys.jsonl").read_text().splitlines()
    except OSError:
        return []
    rows = []
    for l in lines:
        try:
            row = json.loads(l)
            if isinstance(row, dict) and float(row.get("ts") or 0) >= since:
                rows.append(row)
        except (ValueError, TypeError):
            continue
    return rows


def sheep_count(hours=24):
    """This Mac's published deploys in the last `hours` (refusals not counted: they cost no publish)."""
    return sum(1 for r in _sheep_rows(hours) if r.get("ok"))


def sheep_refused_until():
    """The latest `until` of a cap refusal in the log's 24 hours (epoch s), else 0."""
    out = 0.0
    for r in _sheep_rows():
        if not r.get("ok"):
            try:
                out = max(out, float(r.get("until") or 0))
            except (ValueError, TypeError):
                pass
    return out


def sheep_machines():
    """The machines that publish from the account: `sheep/machines` in the config dir, else the
    hosts `lighthouse/hosts` lists, else 1."""
    try:
        n = int(config_line("sheep/machines") or 0)
    except ValueError:
        n = 0
    return max(1, n or len(config_lines("lighthouse/hosts") or []))


def sheep_budget(plan=None):
    """{"count", "cap", "plan", "machines", "helm_limit", "keel_warn", "refused_until"}: this Mac's
    24-hour count against its part of the account's cap (the comment above the caps says why a
    part), and the hold a cap refusal from the server set."""
    plan = plan or _sheep_plan_row(True, None, None, None, time.time())
    machines = sheep_machines()
    cap = int(plan.get("cap") or SHEEP_CAPS["free"])
    return {"count": sheep_count(), "cap": cap, "plan": plan.get("plan") or "unknown", "machines": machines,
            "helm_limit": int(cap * SHEEP_HELM_SHARE / machines), "keel_warn": int(cap * SHEEP_KEEL_WARN / machines),
            "refused_until": sheep_refused_until()}


def sheep_cap_refusal(text):
    """True when a deploy's error reads as the publish cap's refusal: a limit word with "publish"
    or the 24 hours within 40 characters of it."""
    for m in _SHEEP_LIMIT_RE.finditer(text or ""):
        if _SHEEP_CAP_NEAR_RE.search(text[max(0, m.start() - 40):m.end() + 40]):
            return True
    return False


def sheep_cap_line(budget):
    """The words a cap refusal is named with."""
    return ("refused for the account's 24-hour publish cap (%d on spacesheep %s, %s; this Mac %d in 24 h)"
            % (budget["cap"], sheep_plan_words(budget["plan"]), SHEEP_PLAN_URL, budget["count"]))
