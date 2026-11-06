#!/usr/bin/env python3
"""Shared by the user-wide hooks, bin/pr, bin/paste-paths and bin/session_status.py (pickup, bench/sessions): this machine's short host name and the weekly jobs' host rule (`weekly_host`), the GitHub
token git already holds, the repos cloned here, a thin GitHub REST client (with the CI and automerge settings bin/repos --github and bin/github-repo share), the worktree lock's reader and writer, the /move marker's reader, a repo's opt-in kept in repos.json, the fixed closing lines, the readers of autofinish's files, and the one formatter for money (`cost_text`: list and effective). Stdlib only — `gh` is not needed:
the token git already holds is enough. Where the core, its peers and the private config are found:
`tool()`, `repos_json()`, `CONFIG` (README).

Nothing here raises to a caller but write_owner: a missing token is None, a failed request is a status of 0.
Hooks must never cost a turn over GitHub being unreachable.
"""
import base64
import collections
import errno
import fnmatch
import glob
import hashlib
import json
import os
import re
import socket
import stat
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

# ---- the council's marker, one home ---------------------------------------------------------------
# Read by wharf's council and (the marker) keel's sheep_gate: a copy in each made a rename four edits, and a
# missed one reopened a fence with no case to see it (the council's third landing review, finding 24). Who is
# unattended is unattended_caller(), below, beside the vendor-neutral marker it extends.
COUNCIL_MARKER = ".council-run"   # in every council run dir (council's fence_root); a box sits two folders under


def _config_file(path):
    """(lines, why) for one file, as config_read describes them."""
    try:
        text = path.read_text(encoding="utf-8-sig")
    except FileNotFoundError:
        return None, None
    except UnicodeDecodeError:
        return None, "not UTF-8"
    except OSError as e:
        return None, e.strerror or type(e).__name__
    return [l.strip() for l in text.splitlines() if l.strip()], None


# The live layer (live-limits, 2026-11-01): `<config>/live/<name>`, which `regatta limit` writes and
# nothing else does, so the overlay's `--config` never overwrites it and a value changes on its next
# read, with no build and no landing. A layer line `<word>:<value>` (a host, a login, `*`) stands in
# front of the base file's lines, so a reader taking the first line for that word reads the layer's,
# and the base's entry for the same word, on whatever line, is dropped; a layer line with no `<word>:`
# replaces every base line with none (load-max's plain value). An unreadable layer is no layer: the base as ever.
LIVE = "live"
_WORD_RE = re.compile(r"^([^\s:#(]+):")


def live_merge(layer, base):
    """The lines a reader sees: `layer` over `base` (both lists of stripped lines, None for none)."""
    if not layer:
        return base
    words = {m.group(1).lower() for m in map(_WORD_RE.match, layer) if m}
    plain = any(not _WORD_RE.match(l) for l in layer)
    kept, owner = [], None
    for l in base or []:
        # an entry runs on across lines (the overlay writes one word per line: `buildbox:` then `5`), as
        # config_entries and dispatch's parse read it; a plain layer judges each line alone (round 5)
        k, owner = _merge_line(l, words, plain, None if plain else owner)
        if k:
            kept.append(k)
    return list(layer) + kept


def _split_note(l):
    """(tokens before a note, the note's tokens): a note starts at a token opening with `#` or `(`, as dispatch's
    run-cap parse reads it."""
    toks = l.split()
    cut = next((i for i, t in enumerate(toks) if t.startswith(("#", "("))), len(toks))
    return toks[:cut], toks[cut:]


def _merge_line(l, words, plain, owner=None):
    """One config line with the layer's words taken out, entry by entry: a word token and the value tokens after it
    up to the next word (a hand-written `a: 5 b: 6`, or `a:avail=10, rate=40`, which the readers accept). Kept: the
    other words' entries; a value no word stands before unless the layer is plain; the note only beside something
    kept (alone, headroom would read it as a line without `<host>:`; rounds 3 and 4 of the live-limits review).
    OWNER is the entry the line before ended in ("drop", "keep" or None); returned with the line, for the next."""
    head, note = _split_note(l)
    out = []
    for t in head:
        m = _WORD_RE.match(t)
        if m:
            owner = "drop" if m.group(1).lower() in words else "keep"
        if owner == "keep" or (owner is None and not plain):
            out.append(t)
    if out:
        out += note
    # a dropped entry runs on past a note: the overlay splits a note one word per line too (`host-a:`, `5`, `#`,
    # `was`, `4`), and config_entries reads the words after the `#` line as the entry's value (the landing review)
    return " ".join(out), (owner if owner == "drop" or not note else None)


def config_entries(lines):
    """[(word or None, value)] in the lines' order: `host:5`, `host: 5` and `host:avail=10, rate=40` each one entry;
    a value no word stands before is (None, value); notes dropped. What a reader of `<word>:<value>` keys takes."""
    out = []
    for l in lines or []:
        head, _ = _split_note(l)
        for t in head:
            m = _WORD_RE.match(t)
            if m:
                out.append([m.group(1).lower(), t[m.end():]])
            elif out and out[-1][0] is not None:
                out[-1][1] = (out[-1][1] + " " + t).strip()
            else:
                out.append([None, t])
    return [(w, v.strip()) for w, v in out]


def config_read(name):
    """(lines, why) for `<config>/<name>`: its non-blank lines, stripped, a UTF-8 BOM dropped, and
    None; (None, None) when there is no such file (ENOENT, nothing else); (None, why) when it
    exists and cannot be read as UTF-8 text — no Full Disk Access, Drive not downloaded, a stray
    encoding. The one reader of the config dir: config_line, config_lines, bin/jev and the check
    below all go through it, so they never disagree on a file. The live layer (above) is merged
    in front: a key with a layer and an unreadable base reads as the layer's lines with the base's why, so a reader
    that refuses an unreadable file still does, and one that reads on takes the layer."""
    lines, why = _config_file(CONFIG / name)
    # a stat first: the declared keys are read only for a key that has a layer file; never `home`, which
    # live_keys' own root lookup reads
    try:
        has_layer = "/" in name and (CONFIG / LIVE / name).is_file()
    except OSError:   # a folder on the way it may not search: no layer, never a raise at the core's import
        has_layer = False
    if has_layer and name in live_keys():
        layer, lwhy = _config_file(CONFIG / LIVE / name)
        if layer and not lwhy:
            # the base's own trouble stays said (a Drive link not downloaded): a reader that raises on it still does
            return live_merge(layer, lines), why
    return lines, why


_LIVE_KEYS = None


def live_keys():
    """The keys the live layer may stand over: those a module's `limits` file declares (regatta limit's table),
    read once per process once live/ exists. Any other key ignores a file under live/, so a stray file there never replaces what
    the overlay owns (a deny list, a guarded set; the live-limits review). The live/ folder absent: none, one stat."""
    global _LIVE_KEYS
    if _LIVE_KEYS is None:
        try:
            there = (CONFIG / LIVE).is_dir()
        except OSError:
            there = False
        if not there:
            return frozenset()   # not kept: a layer written later in a long process is still seen
        keys, whole = set(), True
        # the modules beside this core first: it is read at import (config_problems), before regatta_root and
        # _installed_roots are defined, so those join only once they are, and a set read without them is not kept
        bases = list(Path(__file__).resolve().parent.parent.parent.glob("*"))
        try:
            bases += [p for p in ((regatta_root() or Path("/nonexistent")) / "modules").glob("*")]
            bases += [b for _, b in _installed_roots()]
        except NameError:
            whole = False
        except Exception:
            pass
        for b in bases:
            try:
                text = (b / "limits").read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            # never the core's own private values (regatta/*: the deny lists, the guarded set), whatever a file declares
            keys |= {l.split()[0] for l in text.splitlines()
                     if l.strip() and not l.lstrip().startswith("#") and not l.split()[0].startswith("regatta/")}
        if not whole:
            return keys
        _LIVE_KEYS = keys
    return _LIVE_KEYS


def config_line(name):
    """The first non-blank line of `<config>/<name>`, or "" when there is none or it cannot be read."""
    return (config_read(name)[0] or [""])[0]


def config_lines(name):
    """`<config>/<name>`'s non-blank lines, or None when there is no such file or it cannot be
    read: a key written empty is an empty list, never the default."""
    return config_read(name)[0]


def launchd_domain(uid=None):
    """The launchd domain this user's jobs load into: `gui/<uid>`, a login's (every host but a builder's), or
    `user/<uid>` where DISPATCH_LAUNCHD_DOMAIN (else `wharf-runs/launchd-domain`) says `user`: a builder user
    has no login session and so no gui domain (the Argon arm's S2, docs/argon-builder-arm-2026-11-03.md,
    "launchd"). Any other word reads as `gui`, today's, so a typo never moves a login's jobs. The one seam
    dispatch, dispatch-queue, dispatch-rc and kicklib build a target from; systemd-launchctl takes both."""
    uid = os.getuid() if uid is None else uid
    word = (os.environ.get("DISPATCH_LAUNCHD_DOMAIN") or config_line("wharf-runs/launchd-domain") or "gui").strip()
    return "%s/%d" % ("user" if word == "user" else "gui", uid)


def launchd_session_keys(domain=None):
    """Extra plist keys for jobs without a GUI login session."""
    return {"LimitLoadToSessionType": "Background"} if (domain or launchd_domain()).startswith("user/") else {}


# ---- the core's private values (B2b; README, "Private values") --------------------------------
# Each is one file under <config>/regatta/, which the overlay writes; the core carries only a
# neutral default. Where the overlay is installed (the `regatta/overlay` marker), a key it
# must write and did not — or one that cannot be read — is an ImportError naming the keys: a
# guarded source sent unrefused, every closing line and relay missed would each be silent.
# `regatta/orca-deny` left the list with deny-drift (2026-11-03): read by nothing, as ORCA_ROW has no deny
# list; an overlay that still writes it is harmless, and `regatta check` notes it. Hooks already fail closed (the deny hooks) or quiet (the rest) on an
# import error of the core, the no-core path. Without the overlay (a stranger's install) an absent
# key is its default. A path key must be absolute after `~`: relative, it would resolve against
# whatever the cwd happens to be.
OVERLAY_KEYS = ("owner", "guarded", "log-dir", "projects")
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
    # a confidential scope whose `repos` is no list reads as no members, which is open: torn, here, so every
    # fence that asks registry_unreadable() fails closed on it, not only S6's gates (the fifth landing review)
    return (d, False) if ok and not registry_malformed(d) else (None, True)


def registry_unreadable(path=None):
    """True when a registry file is there but its repos or scopes cannot be read — a torn write,
    conflict markers, a non-object, a confidential scope whose `repos` is no list. scope_registry() reads that as no scopes at all, which is open;
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


# The spawn (confidential-reach S6): the one write out of a confidential scope is a seed whose brief
# `pickup seed --from` reviewed, with docs/handoff/<date>-<topic>.review beside it (S5). dispatch asks
# spawn_gate() before it writes anything, and again on the tree it launches; the queue asks it again at
# claim, on whichever host claims (docs/dispatch-queue-confidential-2026-10-26.md, item 3). Its refusals
# never use the cap's waiting words (ASK_EXEMPT_RE, helm's CAP_RE): a missing review is not fixed by
# waiting, and those words read as "queued" to stalls and to autofinish.
#
# Whose brief needs the review (the skipper's settlement of the landing review, 2026-10-28): what leaves
# a confidential scope is what a confidential session writes, and pickup's confined_refusal already
# refuses a plain `seed` or `brief` from one, so a spawned branch's later briefs come from open sessions
# (its own --next, a re-dispatch, the lander). So a caller inside a confidential scope needs the brief
# dispatch will hand the run reviewed — the newest, at the tree judged — and may send no --note or
# --start prompt with it (neither is reviewed); an open caller on a branch whose seed carries a review
# needs the seed's own brief reviewed: the blob the seed commit brought, judged against its .review,
# never the tip's file of that path (the spawned run's next brief overwrites it the same day).
#
# Which `.review` counts (the fourth landing review): its run's own — docs/handoff/<date>-<topic>.review,
# the topic its branch names (branch_topic) — for spawn_gate, the queue's has_review and pickup's
# branch_origin alike. A seed made beside a spawn (`pickup seed --beside`) carries its source's review under
# the source's topic: that review vouches for the source's brief, already in the open repo, while the new
# seed's own brief is its maker's, an open session (pickup refuses a plain seed from inside a node), so its
# run is an open run. Any topic would split the readers (the gate refused what the queue routed as a
# spawn), and a `.review` that reached main would make every branch of the repo a spawn.
#
# The `.review` is unsigned JSON: a guard against accidents, not intent — whoever can commit to the open
# branch can write one (the review left this for the owner, 2026-10-30; a signature by config agents
# cannot touch is S6b's, later).

REVIEW_DIR = "docs/handoff/"
BLUEPRINT_DIR = "docs/blueprints/"


def branch_topic(branch):
    """A run's topic from its branch name: the last part, its date dropped (dispatch's topic, the queue's
    topic_of), or None."""
    t = re.sub(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}-", "", str(branch or "").rsplit("/", 1)[-1])
    return t or None


def _git_out(repo, *a, binary=False):
    """git's stdout in REPO (bytes with BINARY, else stripped text), or None on any failure. Never raises."""
    try:
        r = subprocess.run(["git", "-C", str(repo), *a], capture_output=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode:
        return None
    return r.stdout if binary else r.stdout.decode("utf-8", "replace").strip()


def _handoff_re(topic, ext):
    """A handoff file's name pattern: <date>-<TOPIC>.<EXT> (the date optional for a review, as the queue's
    has_review reads it), or any <name>.<EXT> directly in REVIEW_DIR without TOPIC."""
    if not topic:
        return re.compile(r"%s[^/]+\.%s" % (re.escape(REVIEW_DIR), ext))
    date = r"[0-9]{4}-[0-9]{2}-[0-9]{2}-"
    return re.compile(r"%s%s%s\.%s" % (re.escape(REVIEW_DIR), date if ext == "md" else "(?:%s)?" % date, re.escape(topic), ext))


def spawn_reviews(repo, commit, topic=None):
    """[path] of each REVIEW_DIR/*.review in COMMIT's tree (directly in it, as pickup writes them; TOPIC's
    alone when given), or None when COMMIT does not read as a commit in REPO."""
    sha = _git_out(repo, "rev-parse", "--verify", "--quiet", "%s^{commit}" % commit) if commit else None
    if not sha:
        return None
    pat = _handoff_re(topic, "review")
    names = _git_out(repo, "ls-tree", "--name-only", sha, "--", REVIEW_DIR) or ""
    return [n for n in names.splitlines() if pat.fullmatch(n)]


def newest_brief(repo, commit, topic=None):
    """The brief dispatch hands a run of COMMIT: the last by name of REVIEW_DIR/<date>-<TOPIC>.md in its
    tree (dispatch's brief_re, `sort | tail -1`), or None."""
    pat = _handoff_re(topic, "md") if topic else re.compile(r"%s[0-9]{4}-[0-9]{2}-[0-9]{2}-[^/]+\.md" % re.escape(REVIEW_DIR))
    names = _git_out(repo, "ls-tree", "--name-only", commit, "--", REVIEW_DIR) or ""
    hits = sorted(n for n in names.splitlines() if pat.fullmatch(n))
    return hits[-1] if hits else None


def seed_commit(repo, commit, topic=None):
    """The commit that brought the oldest of COMMIT's reviews (TOPIC's), by path and with no rename read as
    a carry: the seed whose brief was reviewed on its way out. None when COMMIT carries no review."""
    revs = spawn_reviews(repo, commit, topic)
    if not revs:
        return None
    out = _git_out(repo, "log", "--no-renames", "--diff-filter=A", "--format=%H", "--reverse", commit, "--", *revs)
    return (out or "").split("\n")[0] or None


def primary_branch(repo):
    """The repo's primary branch: its `.claude/workflow.json` "main" in its git checkout, as checkpoint and sync.py
    read it, else origin's HEAD, else `main`. Never raises."""
    try:
        top = git_checkout(repo) or str(repo)
        v = json.loads((Path(top) / ".claude" / "workflow.json").read_text(encoding="utf-8")).get("main")
        if isinstance(v, str) and re.fullmatch(r"[A-Za-z0-9._/-]+", v):
            return v
    except (OSError, ValueError, AttributeError, TypeError):
        pass
    h = _git_out(repo, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")   # origin's default, else main
    return h.split("/", 1)[1] if h and "/" in h else "main"


def unpushed_beyond(repo, commit, topic, also=()):
    """The paths COMMIT brings that origin has not got (every commit of it no `origin/*` ref holds) other
    than its topic's own seed files — REVIEW_DIR/<date>-<TOPIC>.md and .review, BLUEPRINT_DIR/<date>-<TOPIC>.md,
    what `pickup seed --from` commits — sorted; None when git cannot say (no origin refs, a bad commit). A
    caller inside a node pushes its local branch with `--next`: anything else on it no review read (the
    fourth landing review, item 4). Never raises."""
    if not _git_out(repo, "for-each-ref", "--count=1", "--format=%(refname)", "refs/remotes/origin/"):
        return None
    # --cc: a merge lists only the paths that differ from every parent, so dispatch's after_merge of origin/main
    # (a local merge commit) brings nothing main already has, and an evil merge's own text is still listed
    # (the fifth landing review, item 11); every other unpushed commit lists its paths as before
    out = _git_out(repo, "log", "--format=", "--name-only", "--no-renames", "--cc", commit, "--not", "--remotes=origin", *also)
    if out is None:
        return None
    own = [_handoff_re(topic, "md"), _handoff_re(topic, "review"),
           re.compile(r"%s[0-9]{4}-[0-9]{2}-[0-9]{2}-%s\.md" % (re.escape(BLUEPRINT_DIR), re.escape(topic or "")))]
    return sorted({p for p in out.splitlines() if p and not (topic and any(r.fullmatch(p) for r in own))})


def _review_verdict(repo, sha, revs, origin, reg, here_only=False):
    """(ok, why, marker, final) for reviews REVS in commit SHA: each beside its brief (<same name>.md) with
    that brief's sha256, `scan` and `judge` clean, one confidential `origin` marker for all, equal to ORIGIN
    when given, read back by REG. FINAL: no wait fixes it — every refusal but a marker this host's registry
    does not know (another host's may), which is final too with HERE_ONLY: a host-local queue's entry no
    other host can claim (the fourth landing review)."""
    marks = set()
    for rp in revs:
        try:
            rec = json.loads((_git_out(repo, "cat-file", "blob", "%s:%s" % (sha, rp), binary=True) or b"null").decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            rec = None
        if not isinstance(rec, dict):
            return False, "%s does not read as a review" % rp, None, True
        brief = rp[:-len(".review")] + ".md"
        body = _git_out(repo, "cat-file", "blob", "%s:%s" % (sha, brief), binary=True)
        if body is None:
            return False, "%s vouches for %s, which the seed does not carry" % (rp, brief), None, True
        if rec.get("sha256") != hashlib.sha256(body).hexdigest():
            return False, "%s is not the text %s reviewed (its sha256 differs)" % (brief, rp), None, True
        if rec.get("scan") != "clean" or rec.get("judge") != "clean":
            return False, "%s does not say clean by both the scan and the judge" % rp, None, True
        m = rec.get("origin")
        if not (isinstance(m, str) and m.startswith(SCOPE_MARK)):
            return False, "%s names no confidential origin" % rp, None, True
        marks.add(m)
    if len(marks) != 1:
        return False, "its reviews name more than one origin", None, True
    m = marks.pop()
    if origin and origin != m:
        return False, "its review's origin %s is not the origin given (%s)" % (m, origin), None, True
    if not scope_of_marker(m, reg=reg):
        return False, "its origin %s names no confidential scope in this host's registry" % m, None, bool(here_only)
    return True, "", m, False


def spawn_review_ok(seed_commit, repo=".", origin=None, path=None, reg=None, topic=None):
    """(ok, why, marker): does SEED_COMMIT in REPO carry a review that vouches for the brief it carries?
    Every docs/handoff/*.review in its tree (TOPIC's alone when given) must: sit beside a brief (<same
    name>.md) whose sha256 is its `sha256`, say `scan` and `judge` clean, and name an `origin` marker; one
    marker for all of them, equal to ORIGIN when given, which this host's registry reads back to a
    confidential scope. WHY says what failed (never a scope's name: a refusal is pushed with a fleet
    entry); MARKER is the origin on ok. The registry is read once (REG: a read_registry() parse already
    made); a torn one refuses. Never raises."""
    if reg is None:
        reg, torn = read_registry(path)
        if torn:
            return False, "the scope registry cannot be read here, so no origin can be read back (fails closed)", None
    revs = spawn_reviews(repo, seed_commit, topic)
    if revs is None:
        return False, "no seed commit to judge here (%s)" % (seed_commit or "none named"), None
    if not revs:
        return False, "its seed carries no %s*.review of its own topic: the brief was never reviewed on its way out" % REVIEW_DIR, None
    return _review_verdict(repo, _git_out(repo, "rev-parse", "%s^{commit}" % seed_commit), revs, origin, reg)[:3]


def entry_takes(entry, key):
    """True when a scope's `repos` entry ENTRY — a key, or a glob — takes repo key KEY: the one rule of
    scope_members' globs, scope_of_repo and scope_resolver. An absolute entry takes the key by its real path
    too: a symlinked spelling is the same repo (the fourth landing review)."""
    if not (isinstance(entry, str) and bool(key)):
        return False
    if entry == key or (is_glob(entry) and fnmatch.fnmatchcase(key, entry)):
        return True
    if not entry.startswith("/"):
        return False
    if key.startswith("/"):
        return os.path.realpath(entry) == os.path.realpath(key)
    # an absolute entry under the projects folder names the repo whose key is relative (repo_key makes every path
    # there relative): without this a scope listing its repo by path read its own checkout as split from its
    # folder, and every run of it was refused for good (the sixth landing review)
    if is_glob(entry):
        return fnmatch.fnmatchcase(str(PROJECTS / key), entry) or fnmatch.fnmatchcase(str(PROJECTS.resolve() / key), entry)
    return repo_key(entry) == key


def registry_malformed(reg):
    """True when a confidential scope's `repos` in REG is there but not a list of strings: read as no
    entries it would fail open, so a gate reads it as torn (the fourth landing review: `"repos": 5`
    crashed the claim after its CAS). Never raises."""
    for sc in confidential_scopes(reg=reg if isinstance(reg, dict) else {}).values():
        ms = sc.get("repos")
        if ms is not None and not (isinstance(ms, list) and all(isinstance(m, str) for m in ms)):
            return True
    return False


def git_checkout(p):
    """The main checkout git names for path P — its common dir's folder: a worktree's is its repo's, a
    clone's its own — or None outside git or in a bare repo. Never raises."""
    g = _git_out(p, "rev-parse", "--path-format=absolute", "--git-common-dir")
    return str(Path(g).parent) if g and g.endswith("/.git") else None


def scope_resolver(reg, home=None):
    """p -> the confidential scope a path is in, by REG (one read_registry() parse), or None — the one
    resolver of spawn_gate and dispatch-queue's route() (S6's landing review). `scopes(p)` gives every
    such scope (a repo may be in two); `target(p)` judges a run's repo, by its git checkout.

    A caller's directory (the resolver, `scopes`) reaches far, the safe side: by the fence's paths
    (scope_match: the scope's registered checkouts and worktrees, a slug in any path part), by the path's
    repo key and by its git checkout's, as given and resolved, against every confidential scope's entries
    and globs — a repo the registry does not list that a confidential glob takes is in that scope. A run's
    repo is what its git names: `target(p)` is (scopes, why), the scopes of its checkout's key alone, and
    WHY when its folder places it in other scopes — a worktree or a clone of an open repo inside a
    confidential folder reads as the node's by its path while it pushes to the open repo (the third
    landing review), and the reverse; spawn_gate refuses that target. Every confidential scope is walked,
    so a scope listed before (an umbrella `*`) hides none (the fence trap). Never raises."""
    scopes = confidential_scopes(reg=reg)
    if not scopes:
        resolve = lambda p: None
        resolve.scopes, resolve.target = (lambda p: frozenset()), (lambda p: (frozenset(), None))
        return resolve
    matchers = [(n, scope_match(n, home=home, reg=reg)) for n in scopes]

    def norm(p):
        try:
            return os.path.normpath(os.path.expanduser(str(p))) if p else None
        except (TypeError, ValueError):
            return None

    def by_keys(*ps):
        ks = {repo_key(y) for x in ps if x for y in (x, os.path.realpath(x))} - {None}
        return frozenset(n for n, sc in scopes.items() for e in (sc.get("repos") if isinstance(sc.get("repos"), list) else [])
                         if any(entry_takes(e, k) for k in ks))

    def by_path(p):
        return frozenset(n for n, m in matchers if m(p)) | by_keys(p)

    def every(p):
        p = norm(p)
        return by_path(p) | by_keys(git_checkout(p)) if p else frozenset()

    def target(p):
        p = norm(p)
        top = git_checkout(p) if p else None
        if not top:
            return (by_path(p) if p else frozenset()), None   # no git here: the run's own fetch refuses it
        mine, here = by_keys(top), by_path(p)
        # split when the folder names a scope the checkout is not in (an open repo's worktree or clone inside a
        # node's folder). A checkout in more scopes than its folder shows (a glob's member the registry does not
        # list, its worktree outside the projects folder) is its checkout's: its scopes judge it, the stricter
        # side, and refusing it for good refused a scope's own Orca run (the sixth review, second pass)
        if here - mine:
            return mine, ("its folder and its git checkout are not in the same confidential scopes (a worktree or a "
                          "clone of one repo inside another's folder), so which repo the run pushes to cannot be told "
                          "by its path")
        return mine, None

    def resolve(p):
        s = every(p)
        return next((n for n in scopes if n in s), None)
    resolve.scopes, resolve.target = every, target
    return resolve


def _same_repo(cwd, repo):
    """True when CWD is no caller's directory (none, or launchd's `/`) or one of REPO's own checkouts (its
    git common dir). Never raises."""
    if not cwd or os.path.realpath(str(cwd)) == "/":
        return True
    a, b = git_checkout(cwd), git_checkout(repo)   # one rule of which checkout a path is (the fifth review)
    # both must be checkouts: realpath("") is the process's cwd, so a repo with none read as the caller's own
    # when the caller stood at its checkout's root (the sixth landing review)
    return bool(a) and bool(b) and os.path.realpath(a) == os.path.realpath(b)


def session_dirs(home=None):
    """Every sessions/ folder a Claude Code session's record may sit in, each once by its real path: each
    login dir's (login_dirs), then every Orca profile's own (a session registry is not one folder: AGENTS.md's
    trap). Never raises."""
    home = Path(home or Path.home())
    own = os.environ.get("CLAUDE_CONFIG_DIR")
    cands = [Path(own) / "sessions"] if own else []   # the caller's own login first, listed in accounts or not
    try:
        cands += [d / "sessions" for d in login_dirs(home)]
    except Exception:  # noqa: BLE001 — a broken accounts file costs only those dirs
        cands += [home / ".claude" / "sessions"]
    cands += [Path(p) for p in sorted(glob.glob(str(home / "Library" / "Application Support" / "orca" / "claude-profiles" / "*" / "home" / "sessions")))]
    out, seen = [], set()
    for d in cands:
        r = os.path.realpath(d)
        if r not in seen and d.is_dir():
            seen.add(r)
            out.append(d)
    return out


def session_dir(sid, home=None):
    """The folder session SID runs in by its newest record (`cwd`; `updatedAt`, as asklib.registry and
    rc-hosts pick: a session picked up again keeps its old record beside the new one) in any sessions/
    folder here, or None when no record names it — a headless run may keep none. Never raises."""
    if not sid:
        return None
    best, key = None, None
    for d in session_dirs(home):
        for f in sorted(d.glob("*.json")):
            try:
                rec = json.loads(f.read_text(encoding="utf-8"))
                k = (float(rec.get("updatedAt") or 0), f.stat().st_mtime)
            except (OSError, ValueError, TypeError, AttributeError):
                continue
            if isinstance(rec, dict) and rec.get("sessionId") == sid and isinstance(rec.get("cwd"), str) and rec["cwd"] \
                    and (key is None or k > key):
                best, key = rec["cwd"], k
    return best


def session_start_dirs(sid, home=None):
    """[dir] the folders session SID started in: each transcript of it — <login>/projects/<slug>/<SID>.jsonl,
    beside each sessions/ folder here (session_dirs), one per folder a resume began it in — read for its first
    entry's `cwd`, a real path. A `cd` does not move it: Claude Code writes a moved cwd into later entries (probed
    on a typed session, the sixth landing review) and may into the session's record. The slug folder itself is
    never judged: scope_match's slug prefix read an open `<name>-x` as confidential `<name>` (its first review
    pass). Never raises."""
    if not sid or "/" in str(sid):
        return []
    out = []
    for d in session_dirs(home):
        try:
            hits = sorted(glob.glob(str(d.parent / "projects" / "*" / ("%s.jsonl" % glob.escape(str(sid))))))
        except (OSError, ValueError, TypeError):
            continue
        for h in hits:
            try:
                with open(h, encoding="utf-8", errors="replace") as f:
                    for n, line in enumerate(f):
                        if n >= 200:
                            break
                        try:
                            c = json.loads(line).get("cwd")
                        except (ValueError, AttributeError):
                            continue
                        if isinstance(c, str) and c.startswith("/"):
                            if c not in out:
                                out.append(c)
                            break
            except OSError:
                continue
    return out


def caller_dirs(here, sid=None, home=None):
    """[dir] a caller asks from: HERE (its shell's), its session SID's own folder by record (session_dir), and
    the folder it started in by its transcript (session_start_dirs), each when it differs — a
    session inside a node that runs `cd <open repo> && …`, or that moved its cwd for good, is still inside it.
    One list for dispatch, pickup and harness (the fourth landing review, item 7). Never raises."""
    out = [here]
    for extra in (([session_dir(sid, home)] + session_start_dirs(sid, home)) if sid else ()):
        try:
            if extra and all(os.path.realpath(extra) != os.path.realpath(str(x)) for x in out if x):
                out.append(extra)
        except (TypeError, ValueError):
            continue
    return out


def caller_and_target(at, cwds, repo):
    """(cs, inside, rs, split) by resolver AT (scope_resolver): the confidential scopes the caller's
    directories CWDS are in, the first of them inside one, REPO's scopes by its git checkout, and why its
    folder and checkout disagree (or None). A caller in a scope REPO is not in sends a spawn: spawn_gate
    judges it, pickup's confined_refusal refuses its plain seed or brief — one rule (item 7). Never raises."""
    per = [(c, at.scopes(c)) for c in cwds if c]
    cs = frozenset().union(*(x for _, x in per)) if per else frozenset()
    inside = next((c for c, x in per if x), None)
    rs, split = at.target(repo)
    return cs, inside, rs, split


Spawn = collections.namedtuple("Spawn", "why mark scope final caller", defaults=(None, None, None, False, None))
Spawn.__doc__ = """spawn_gate's verdict: (why, mark, scope, final, caller). WHY None lets the run start; MARK is the
origin it carries (None for an open run), SCOPE that origin's name by this host's registry (local state, never
pushed); FINAL says no wait fixes the refusal, so a queue drops the entry rather than retry it; CALLER, on a
start, the first caller's directory inside a confidential scope (None: an open caller), for the queue's route."""


def spawn_gate(repo, commit, cwd, origin=None, path=None, topic=None, node=None, note=False, start=False, here_only=False):
    """Spawn(why, mark, scope, final): why a run of COMMIT in REPO, asked from CWD (the caller's directory,
    or several: a shell's and its session's start folder, any one inside a scope placing the caller there)
    or from the queue of confidential scope NODE (its folder's name), may not start — or None — and the
    origin it carries. A run is a spawn when ORIGIN (a marker) is given, when its tree carries a review
    (TOPIC's, the run's: the one rule of which review counts, above), or when its caller is in a
    confidential scope that REPO is not in: a spawn starts only in an open repo. REPO is judged by its git
    checkout (scope_resolver's target), and refused when its folder says other scopes. A caller inside a
    confidential scope needs the newest brief at COMMIT reviewed, out of that scope, nothing else on COMMIT
    that origin lacks (unpushed_beyond: its --next pushes it), and may send no NOTE or START prompt (neither
    was reviewed); an open caller needs the seed's own brief reviewed (seed_commit), and the newest brief
    the seed carries to be that one, whatever later briefs say. A confidential scope's own run (its caller
    in a scope REPO is in, no review, no origin) is no spawn. A target in a confidential scope refuses
    every spawn (no bridge waives it: S8's was removed). One read_registry() judges everything.
    A torn one — or a confidential scope whose `repos` is no list (registry_malformed) — refuses whatever
    may be a spawn: an ORIGIN, a review, a NODE, a CWD outside REPO's own checkouts; and lets a run asked
    from inside its own repo (or with no caller's directory: launchd's `/`) go on, as the mode's torn read
    does (dispatch's mode_unread). HERE_ONLY: the entry is a host-local queue's, so a marker this host does
    not know is final. Never raises."""
    cwds = [c for c in ((cwd,) if cwd is None or isinstance(cwd, (str, os.PathLike)) else cwd)
            if c and os.path.realpath(str(c)) != "/"]
    reg, torn = read_registry(path)   # torn includes a confidential scope whose `repos` is no list
    reg = reg or {}   # no registry file: judged as no scopes from this one read, never re-read (the fourth review)
    revs = spawn_reviews(repo, commit, topic) if commit else None
    if torn:
        if origin or revs or node or not all(_same_repo(c, repo) for c in cwds):
            return Spawn("the scope registry cannot be read here, so whether this run leaves a confidential scope "
                         "cannot be told (fails closed)")
        return Spawn()
    scopes = confidential_scopes(reg=reg)
    if not scopes and not origin and not revs and not node:
        return Spawn()   # nothing confidential here, nothing claimed: an open run (a node queue's entry is judged below)
    at = scope_resolver(reg)
    cs, inside, rs, split = caller_and_target(at, cwds, repo)
    if not cs and node:
        cs = frozenset(n for n in scopes if re.sub(r"[^A-Za-z0-9._-]", "_", n) == node)
        if not cs:
            # a node queue's entry was asked from inside that scope; one this host's registry no longer names as
            # confidential (renamed, opened) cannot say which scope it left, and judged as an open caller it went
            # out unjudged. Its queue is this host's alone, so no wait fixes it (the sixth landing review)
            return Spawn("its node queue names no confidential scope in this host's registry (renamed or opened "
                         "since it was queued), so what it carries out cannot be judged", final=True)
    if split:   # judged for every run here, as the queue's route() judges it: an open run in such a folder too
        return Spawn(split, final=True)
    if not (origin or revs or (cs and not cs <= rs)):
        # an open run, or a scope's own: every scope its caller is in takes its repo. A caller in two scopes
        # (a repo they share, or a shell in one and its session folder in another) asking for a repo of only
        # one is a spawn out of the other, refused below as main's confined_refusal refused it (the fifth
        # landing review, item 2; AGENTS.md's narrowed-guard trap)
        return Spawn(caller=inside)
    sha = _git_out(repo, "rev-parse", "--verify", "--quiet", "%s^{commit}" % commit) if commit else None
    if rs:
        return Spawn("its repo is in a confidential scope: a spawn out of one goes to an open repo, and no bridge "
                     "waives that", final=True)
    if cs:
        # the caller is inside a node (rs is empty here): what it hands the run must all be reviewed
        if start:
            return Spawn("a --start from inside a confidential scope hands the run a prompt no review read", final=True)
        if note:
            return Spawn("a --note from inside a confidential scope rides with the run, and no review read it", final=True)
        here = spawn_reviews(repo, sha, topic) if sha else None
        if here is None:   # a branch this host has not fetched yet: waited out, never final
            return Spawn("no seed commit to judge here (%s)" % (commit or "none named"))
        if not here:
            return Spawn("its seed carries no %s*.review of its own topic: the brief was never reviewed on its way out" % REVIEW_DIR, final=True)
        brief = newest_brief(repo, sha, topic)
        if not brief:
            return Spawn("no brief of its own beside its review, for the review to vouch for", final=True)
        rev = brief[:-len(".md")] + ".review"
        if rev not in here:
            return Spawn("its newest brief %s carries no %s beside it: a brief written after the seed's review "
                         "was never reviewed on its way out" % (brief, rev.rsplit("/", 1)[-1]), final=True)
        ok, why, mark, final = _review_verdict(repo, sha, [rev], origin, reg, here_only)
        if ok and {scope_of_marker(mark, reg=reg)} != set(cs):
            # a brief reviewed out of another scope: the run would record that scope as its origin. And a caller in
            # two scopes (a repo they share, a shell in one and its session folder in another) with a review out of
            # one: what it hands the run may hold the other's text, which no review read (the sixth landing review)
            return Spawn("its review names another confidential scope as its origin than the one it is asked from, "
                         "or the caller is in more than one confidential scope and the review vouches for one",
                         final=True)
        if ok and (inside or node):
            # what a push would send beyond the seed's own files: no review read it (item 4). A node queue's
            # claim too (the fifth landing review, item 5): its entry was asked from inside the node, and the
            # fired run reuses this host's local branch, which its checkpoint hook then pushes
            extra = unpushed_beyond(repo, sha, topic or branch_topic(brief[:-len(".md")]))
            if extra is None:
                return Spawn("what its branch would push to origin cannot be told here (no origin refs to judge against)")
            if extra:
                # all of it the repo's own local main, ahead of origin (sync.py leaves such a main alone; `pickup seed
                # --from` bases the seed on it): the refusal says so and what fixes it (the sixth review's first pass).
                # Final still: a main whose commits landed on origin under other shas (a rebase-merge) never matches,
                # so a refusal for now was handed back each hour for ever (its third pass); the card names the fix
                prim = "refs/heads/%s" % primary_branch(repo)
                mine = unpushed_beyond(repo, sha, topic or branch_topic(brief[:-len(".md")]), also=(prim,)) \
                    if _git_out(repo, "rev-parse", "--verify", "--quiet", prim) else extra
                mine = extra if mine is None else mine   # git could not say: never read as "all of it main's"
                return Spawn("its branch holds %d path(s) origin has not got beyond its seed's brief and review (%s): "
                             "a push from inside a confidential scope would carry them, and no review read them%s"
                             % (len(extra), ", ".join(extra[:3]) + (", …" if len(extra) > 3 else ""),
                                "" if mine else "; they are all this repo's local %s, ahead of origin: the owner pushes it, or resets it to "
                                "origin's, then dispatches it again" % prim[len("refs/heads/"):]), final=True)
    else:
        seed = seed_commit(repo, sha, topic) if sha else None
        if not seed and sha and revs:
            # the tip carries the topic's review, yet no commit adds it by path (a merge brought it, which a
            # plain log does not show as an add): the tip is the seed, judged with the newest-brief rule
            # below, never the plain spawn_review_ok that skips it (the fifth landing review, item 8)
            seed = sha
        if not seed:
            # no review of its topic on it (or no commit here): spawn_review_ok says which, and never passes
            ok, why, mark = spawn_review_ok(commit, repo, origin=origin, reg=reg, topic=topic)
            final = bool(sha)
        else:
            sha = _git_out(repo, "rev-parse", "%s^{commit}" % seed)
            here = spawn_reviews(repo, sha, topic)
            ok, why, mark, final = _review_verdict(repo, sha, here, origin, reg, here_only)
            # the brief dispatch hands a run is the newest: the seed's must be the reviewed one (item 3)
            brief = newest_brief(repo, sha, topic) if ok else None
            if brief and brief[:-len(".md")] + ".review" not in here:
                return Spawn("its seed carries %s, newer than the brief its review vouches for, which no review read: "
                             "dispatch would hand the run that one" % brief, final=True)
    if not ok:
        return Spawn(why, final=final)
    return Spawn(None, mark, scope_of_marker(mark, reg=reg), caller=inside)


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


# A confidential scope's yard may be its own node (scopes-node-yard, 2026-11-03): a yard check asks
# scope_yard_hosts(), never `lighthouse/hosts` alone. The overlay may list a node there too (it listed the
# first named node on 2026-11-04), so a host that a node here is told as passes only as its own scope's node:
# a listed host is no licence to another scope's node, nor an open scope's. Where the node is told from, on this host:
#  * a named node's folder, `<config>/wharf-runs/nodes/<folder>/` (yard-node's `--node`, orca-host's
#    node_peers, helm send's yard_alias), whose `scope` key names the scope — yard-node's own binding: a
#    folder with no `scope` is a shared node, no scope's own — and whose `ssh` names the alias this host
#    reaches it by (helm send refuses a node yard without one). The yard is the node's peer,
#    `<name>-agent` (`name` defaulting to the folder), the name the node's own host_name() gives, which
#    the yard rules compare with (weekly_host's, helm's yard_here, send's node match, case-blind).
#  * this host itself, when it is a named node: its payload's `wharf-runs/node/scope` names the scope it
#    serves (empty on a shared node). A node rendered before that key (the first named node, 2026-10-28) has only its
#    `wharf-runs/node/clones`, the registry keys it cloned; yard-node clones no confidential scope's repo
#    but its own, so the confidential scope holding a cloned key is its scope — judged on the registry's
#    own flags (never the flag a write is about to set: a shared node's carry would become any scope's it
#    flags) and only where this host's name is `<scope>-agent`, the name such a node's folder gives.
# The shared node a Mac drives (`wharf-runs/node/name`, its guest `<name>-agent`) is told too, as no
# scope's. Either road holds only for a confidential scope (an open scope's yard is a Mac, as before), and
# a scope never gets another scope's node. Anything that will not read — the registry, a node folder, a
# key — tells no node, with its reason: the check fails closed, as send's node_peers does.
NODES_DIR, NODE_ROLE = "wharf-runs/nodes", "agent"   # orca-host's names: a node's peer is `<name>-agent`
NODE_KEY = "wharf-runs/node/"   # the shared node's keys on a Mac; a named node's payload on the node itself


def _node_key(key):
    """(lines, why) of a node config key, a link whose target moved unreadable (orca-host's rule)."""
    path = CONFIG / key
    if os.path.islink(path) and not os.path.exists(path):
        return None, "is a link whose target moved"
    return config_read(key)


def nodes_here(reg, confidential=None, me=None):
    """({peer: scope or None}, why, held): every node this host can tell, its peer lower-cased, each with the
    confidential scope it is the own node of — None for a shared node, an open scope's, or a folder with no
    `ssh`, which helm send cannot reach (that confidential scope's reason goes in HELD, {scope: why}).
    Told by the rules above: the node folders, the shared node's `name`, and this host's own name (ME, else
    host_name()) on a named node. REG: a registry read_registry() parsed (never torn); CONFIDENTIAL:
    {scope: True|False} for a flag a write is about to change (never on the clones road). WHY: None, or
    why the nodes here cannot be told — then nothing is told (fails closed: a folder or key that will not
    read could be any scope's). Never raises."""
    flagged = dict(confidential_scopes(reg=reg or {}))   # the registry's own flags
    conf = dict(flagged)
    for name, flag in (confidential or {}).items():
        sc = ((reg or {}).get("scopes") or {}).get(name)
        if flag is True and isinstance(sc, dict):
            conf[name] = sc
        elif flag is False:
            conf.pop(name, None)
    out, whys, held = {}, [], {}

    def tell(peer, owner):
        peer = peer.lower()
        if peer in out and out[peer] != owner:
            whys.append("two nodes here give the peer %s, of %s and %s" % (peer, out[peer] or "no scope", owner or "no scope"))
        out[peer] = owner

    root = CONFIG / NODES_DIR
    try:
        names = sorted(p.name for p in root.iterdir() if not p.name.startswith(".")) if os.path.lexists(root) else []
    except OSError as e:
        return {}, "%s does not read (%s)" % (root, e.strerror or type(e).__name__), {}
    for name in names:
        try:   # os.stat, never Path.is_dir: from Python 3.13 that swallows EACCES and reads as "not a folder"
            folder = stat.S_ISDIR(os.stat(root / name).st_mode)
        except (FileNotFoundError, NotADirectoryError):
            folder = False
        except OSError as e:   # a folder it may list but not search; a link loop
            if e.errno == errno.ELOOP:
                folder = False
            else:
                return {}, "%s does not read (%s)" % (root / name, e.strerror or type(e).__name__), {}
        if not folder:
            whys.append("%s is not a folder (a link whose target moved?)" % (root / name))
            continue
        got = {}
        for k in ("scope", "name", "ssh"):
            got[k], why = _node_key("%s/%s/%s" % (NODES_DIR, name, k))
            if why:
                whys.append("%s %s" % (root / name / k, why))
                break
        else:
            owner = (got["scope"] or [None])[0]
            owner = owner if owner in conf else None
            if owner and not (got["ssh"] or [""])[0]:
                held[owner] = "%s names scope %s and no ssh (the Host alias this host reaches it by)" % (root / name, owner)
                owner = None
            tell("%s-%s" % ((got["name"] or [name])[0], NODE_ROLE), owner)
    keys = {}
    for k in ("name", "scope", "clones"):
        keys[k], why = _node_key(NODE_KEY + k)
        if why:
            return {}, "%s %s" % (CONFIG / (NODE_KEY + k), why), {}
    if keys["name"]:   # the shared node this Mac drives: no scope's (yard-node's fence)
        tell("%s-%s" % (keys["name"][0], NODE_ROLE), None)
    me = (me or host_name()).lower()
    if keys["scope"] is not None:   # a named node, by its payload's own word: empty is a shared one
        owner = (keys["scope"] or [None])[0]
        tell(me, owner if owner in conf else None)
    elif keys["clones"]:   # a named node rendered before the key: its clones, on the registry's own flags
        owners = set()
        for line in keys["clones"]:
            key = line.split()[0]
            for n, s in flagged.items():
                try:
                    if scope_of_repo(key, reg={"scopes": {n: s}})[0]:
                        owners.add(n)
                except TypeError:   # a confidential scope whose repos is no list: nothing is told
                    return {}, "scope %s's repos is no list" % n, {}
        if len(owners) > 1:
            return {}, "this node's %s clones repos of several confidential scopes (%s): no one scope's node" % (
                CONFIG / (NODE_KEY + "clones"), ", ".join(sorted(owners))), {}
        owner = next(iter(owners), None)
        tell(me, owner if owner in conf and me == ("%s-%s" % (owner, NODE_ROLE)).lower() else None)
    if whys:
        return {}, "; ".join(whys), {}
    return out, None, held


def scope_yard_hosts(scope, reg=None, confidential=None, me=None):
    """(hosts, nodes, why): the hosts SCOPE may name as its yard on this host. HOSTS: `lighthouse/hosts`'
    lines, less any a node here is told as that is not SCOPE's own node. NODES: SCOPE's own node, by the rules above (nodes_here's peers, lower-cased, whose
    scope is SCOPE); [] for an open scope. WHY: None, or why no node could be told here (nodes_here's, or
    SCOPE's held folder). REG: a registry read_registry() parsed already (None reads repos_json() once);
    CONFIDENTIAL: the flag a write is about to leave on SCOPE (scopes set --confidential/--open), else the
    registry's; ME: this host's name, else host_name(). Never raises."""
    hosts = config_lines("lighthouse/hosts") or []
    if reg is None:
        reg, torn = read_registry()
        if torn:
            return hosts, [], "the registry %s does not read, so no scope's node can be told" % repos_json()
    flag = {} if confidential is None else {scope: confidential}
    peers, why, held = nodes_here(reg or {}, confidential=flag, me=me)
    nodes = [p for p, s in peers.items() if s == scope]
    hosts = [h for h in hosts if peers.get(h.lower(), scope) == scope]   # a listed node: its own scope's only
    return hosts, nodes, why or (None if nodes else held.get(scope))


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


def scope_paths(name, path=None, home=None, reg=None):
    """[Path] — what a scope's sessions leave on this Mac, the paths the fence keeps out: per repo
    of the scope (its anchor, the knowledge repo, first) its checkout and every `git worktree list`
    entry, PROJECTS/transcripts/<repo>/, and each login dir's projects/<slug>/ for each of those
    checkouts — the transcripts and the memory both (week-digest reads the .jsonl files there). A
    worktree already removed left a folder whose slug starts with its checkout's slug and a `-`:
    a reader matches that prefix, as sheep_gate's transcript test does. A copy outside a
    registered repo is not found. [] for a scope the registry lacks. REG: one read_registry() parse, so a
    caller judging several scopes reads one file (the "a fence walks every scope" trap; S6's scope_resolver).
    Never raises."""
    repos, scopes = scope_registry(path) if reg is None else (reg.get("repos") or {}, reg.get("scopes") or {})
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
        if key.startswith("/"):
            # a member named by its absolute path, as `repos` entries may be (entry_takes): its checkout as given,
            # when it is there, with its worktrees — without them a sibling worktree of such a repo read as split
            # from its checkout, and S6's gate refused the scope's own run (S6's fifth round, main's vendor fence)
            top = Path(key)
            if not top.is_dir():
                continue
        elif key not in repos:
            continue
        else:
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


def scope_match(name, path=None, home=None, reg=None):
    """A test path -> bool: is it one of scope `name`'s (scope_paths)? Under one of its folders by
    the path as given or its real path, or any path part that is one of its slugs or starts with one
    and a `-`, whatever folder holds it — a login dir scope_paths did not list, a worktree already
    removed, a session's scratch folder (`<tmp>/claude-<uid>/<slug>/<session>/…`, whose parent is no
    `projects/`: 11 of a scope's rows were quoted for it, trim-cross-host D2,
    2026-10-28). The prefix over-reaches (a repo `<name>-x` beside `<name>`): for a fence that is the
    safe side. Never raises."""
    ps = scope_paths(name, path, home, reg)
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
    given = None
    for p, base in ((Path(os.path.normpath(s)), PROJECTS), (Path(s).resolve(), PROJECTS.resolve())):
        wt = p.parts.index(".claude") if ".claude" in p.parts else None
        if wt is not None and p.parts[wt + 1:wt + 2] == ("worktrees",):
            p = Path(*p.parts[:wt])
            given = given or p
        try:
            return str(p.relative_to(base))
        except ValueError:
            continue
    # outside the projects folder: as given, a worktree as its checkout — a scope that lists a repo by its
    # absolute path holds that repo's worktrees too (S6's fifth round: the launch judged one as split)
    return str(given) if given else s


def scope_of_repo(repo, path=None, reg=None):
    """(name, scope) of the registry's first scope whose `repos` list REPO — a key, or a path under
    PROJECTS — each entry a key or a glob, as `scopes` reads them; (None, {}) when none does or the
    registry does not read; a TypeError on a confidential scope whose `repos` is there but no list in a REG handed in
    (read from the file here, as an open scope's always, it is no member: a fence asks read_registry first). What a scope carries beyond its repos (`mode`, `berths`: skipper-modes
    S1, S6) is data, read here once for every module. REG: a registry read_registry() parsed already."""
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
        ms = sc.get("repos") if isinstance(sc, dict) else None
        if ms is not None and not isinstance(ms, list):
            if reg is not None and isinstance(sc, dict) and sc.get("confidential") is True:
                # a string would iterate as characters and read as no member, which is open: raise, so a fence
                # that relies on the raise (autofinish-run's rotation fence) fails closed. Only with a REG handed in:
                # read from the file here, it is no member, as on main — read_registry calls such a file torn, and
                # a reader that read it so and passed reg=None (crew-report) crashed (the sixth review, second pass)
                raise TypeError("scope %r: `repos` is %s, not a list" % (name, type(ms).__name__))
            # an open scope's odd value is no member, as on main: raising crashed every reader that walks the
            # scopes (berth, usage-report, crew-report, ops) on a scope no fence depends on (the sixth landing review)
            continue
        if any(entry_takes(m, key) for m in ms or []):
            return name, sc
    return None, {}


def rotation_problem(name, sc):
    """What is wrong with scope NAME's `rotation` key, or None: absent, true and false read; anything else is a
    narrowing key that does not read, which fences (scope_rotates) and `regatta check` names (AGENTS.md's Traps)."""
    if not isinstance(sc, dict) or "rotation" not in sc or isinstance(sc["rotation"], bool):
        return None
    return "scope %s's rotation is %r, not true or false" % (name, sc["rotation"])


def scope_rotates(primary, reg):
    """(rotates, why, fields) for a build or a landing of PRIMARY on the coins (the builder rotation, the finisher's):
    one rule, which buildercoin.py's and autofinish-run's rotation_fence both ask. REG is read_registry()'s dict,
    the caller having judged the tear on the same parse (None: no registry, which fences). A repo rotates when
    some scope lists it and every scope that lists it — each walked and judged alone, by scope_of_repo with that
    scope only, so neither the first-listed nor an umbrella hides one — has no `rotation` key or `rotation: true`.
    `rotation: false` fences, and so does a key that is not a bool (rotation_problem). `confidential` alone no
    longer fences (the owner, 2026-11-04: one confidential scope opts out, the others draw). A scope whose
    `repos` is there but no list is a registry this cannot walk: fenced. FIELDS, when it rotates: {"scope": the first confidential scope that lists it, else the first scope, "confidential": bool},
    which each row carries so a reader can tell. Never raises."""
    if not isinstance(reg, dict):
        return False, "no scope registry", {}
    try:
        scopes = reg.get("scopes") or {}
        if not isinstance(scopes, dict):
            raise TypeError("`scopes` is no object")
        for n, sc in scopes.items():
            if isinstance(sc, dict) and sc.get("repos") is not None and not isinstance(sc.get("repos"), list):
                raise TypeError("scope %r: `repos` is no list" % n)
        mine = [(n, sc) for n, sc in scopes.items()
                if isinstance(sc, dict) and scope_of_repo(primary, reg={"scopes": {n: sc}})[0]]
    except Exception as e:  # noqa: BLE001 — a registry it cannot walk is never known open
        return False, "the scope registry does not walk (%s)" % type(e).__name__, {}
    if not mine:
        return False, "%s is in no scope" % os.path.basename(str(primary).rstrip("/")), {}
    for n, sc in mine:
        bad = rotation_problem(n, sc)
        if bad:
            return False, bad, {}
        if sc.get("rotation") is False:
            return False, "scope %s does not rotate (rotation: false)" % n, {}
    conf = [n for n, sc in mine if sc.get("confidential") is True]
    return True, "rotates", {"scope": (conf or [mine[0][0]])[0], "confidential": bool(conf)}


# ---- the unattended marker and the vendor fence (vendor-fence, docs/codex-agy-gaps-2026-10-29.md) ----
# One marker for every CLI's unattended run (the owner on that doc: "let's rename this to vendor-neutral"),
# staged: every launcher sets both names (unattended_env), every reader asks unattended(), which takes
# either, and the checkpoint's shed guard denies dropping either. Stage 2 (the doc's list of the readers
# left) drops the old name once the overlay and both Macs read only this helper.
UNATTENDED_NAMES = ("REGATTA_UNATTENDED", "CLAUDE_UNATTENDED")


def unattended(env=None):
    """The unattended marker's value — REGATTA_UNATTENDED, else the old CLAUDE_UNATTENDED — or None."""
    env = os.environ if env is None else env
    return next((env[n] for n in UNATTENDED_NAMES if env.get(n)), None)


def unattended_label(env=None):
    """`NAME=value` of the marker that is set (what a refusal quotes), or None."""
    env = os.environ if env is None else env
    return next(("%s=%s" % (n, env[n]) for n in UNATTENDED_NAMES if env.get(n)), None)


def unattended_caller(env=None):
    """`NAME=value` of what makes the caller an unattended run, or None: the marker (unattended_label), else
    AUTOFINISH_CALLER_UNATTENDED, which peer-start sets in a peer's job, whose environment holds only what its
    plist names, so an unattended caller on the sending Mac stays one there. A flag that stands for a person's
    yes refuses such a caller (AGENTS.md's trap); council, harness and autofinish-run read this one rule (the
    council's fourth landing review, finding 5: a second unattended() here, merged with no conflict, shadowed
    the marker's and dropped REGATTA_UNATTENDED)."""
    env = os.environ if env is None else env
    return unattended_label(env) or (
        "AUTOFINISH_CALLER_UNATTENDED=%s" % env["AUTOFINISH_CALLER_UNATTENDED"]
        if env.get("AUTOFINISH_CALLER_UNATTENDED") else None)


def unattended_env(value):
    """{name: VALUE} for both of the marker's names: what a launcher puts in its child's environment."""
    return {n: value for n in UNATTENDED_NAMES}


def _checkout_of(path):
    """The main checkout of the git tree at PATH (a worktree's, wherever it lies), or None: repo_key knows a
    worktree only in the folder the workflow makes them in, and a Codex thread's cwd can be any worktree.
    Wider than git_checkout on purpose: any common dir's parent, a bare layout's (`<repo>/.bare`) included,
    for the vendor fence names more forms, the safe side; the spawn gate's target needs a checkout git names
    exactly (the sixth review's first pass: one rule here dropped a bare-layout repo's checkout from the fence)."""
    try:
        r = subprocess.run(["git", "-C", str(path), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return os.path.dirname(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None


def fenced_scopes(repo, reg):
    """[name] of what fences REPO from a vendor its tenant holds no login of: every confidential scope that
    lists it — every scope walked, never scope_of_repo's first (AGENTS.md's fence trap) — and `guarded` when
    the registry's `guarded` list, the config dir's `regatta/guarded` or the transcript archive names it. REPO and, for a git tree, its main checkout are both judged.
    REG: one read_registry() parse."""
    main = _checkout_of(repo) if repo and os.path.isdir(str(repo)) else None
    forms = [repo] + ([main] if main and os.path.realpath(main) != os.path.realpath(str(repo)) else [])
    keys = {k for k in (repo_key(f) for f in forms) if k}
    out = []
    for n, sc in sorted(((reg or {}).get("scopes") or {}).items()):
        if isinstance(sc, dict) and sc.get("confidential") is True and any(
                scope_of_repo(f, reg={"scopes": {n: sc}})[0] for f in forms):
            out.append(n)
    # the guarded names every other guard reads (sheep_gate's PRIVATE_REPOS, helmlib's fallback): the
    # registry's list, the config dir's `regatta/guarded` and the transcript archive, case-folded (APFS)
    g = (reg or {}).get("guarded")
    names = [x for x in (g if isinstance(g, list) else []) if isinstance(x, str)]
    names += list(config_lines("regatta/guarded") or []) + ["transcripts"]
    folded = {x.strip().casefold() for x in names if x.strip()}
    if any(k.casefold() in folded or os.path.basename(k).casefold() in folded for k in keys):
        out.append("guarded")
    return out


VENDORS_UNFENCED = ("claude",)   # the providers whose runs this check leaves to their own rules


def vendor_refusal(repo, provider, account=None, timeout=120):
    """Why a run of PROVIDER's CLI may not open REPO, or None: the start check every vendor's road asks
    (docs/codex-agy-gaps-2026-10-29.md, D2-A and "Differences that stay" 1). A confidential or guarded repo's
    text goes only to a login its tenant owns. `gate` states it as "every vendor but Anthropic", because the
    tenants hold a Claude seat and no other; stated per login it is one rule, and a tenant that adds its own
    login of another vendor gets that vendor. A Claude run's rule is unchanged: None here, as before.
    bin/account's `pick --provider P --repo R --json --cached` names the login the run would take and says
    whether it `owns` the repo (its scope's login, or a login of the tenant whose repos
    cover it). Fails closed: a torn registry refuses first, then a pick that does not read, names no
    login, or names one the repo's tenant does not own. ACCOUNT: bin/account's path (a suite's stand-in)."""
    if not provider or provider in VENDORS_UNFENCED:
        return None
    reg, torn = read_registry()
    if torn:
        return "the scope registry does not read: no %s run opens a repo until it does" % provider
    try:
        fenced = fenced_scopes(repo, reg or {})
    except Exception as e:  # noqa: BLE001 — a registry it cannot walk is never known open
        return "the scope registry does not walk (%s): no %s run opens a repo until it does" % (type(e).__name__, provider)
    if not fenced:
        return None
    where = "%s is %s" % (repo_key(repo), " and ".join("guarded" if n == "guarded" else "in confidential scope " + n
                                                        for n in fenced))
    exe = account or os.environ.get("REGATTA_ACCOUNT") or tool("account")
    if not exe:
        return "%s, and bin/account is not here to name a %s login its tenant owns" % (where, provider)
    try:
        r = subprocess.run([str(exe), "pick", "--provider", provider, "--repo", str(repo), "--json", "--cached"],
                           capture_output=True, text=True, timeout=timeout)
        d = json.loads(r.stdout) if r.stdout.strip() else None
    except (OSError, ValueError, subprocess.TimeoutExpired) as e:
        return "%s, and account pick did not answer (%s)" % (where, type(e).__name__)
    if not isinstance(d, dict) or not d.get("account"):
        skipped = "; ".join("%s: %s" % tuple(x[:2]) for x in (d or {}).get("skipped") or [] if isinstance(x, list) and len(x) >= 2) \
            if isinstance(d, dict) else ""
        return "%s, and no %s login may run it (%s)" % (where, provider, skipped or (r.stderr or "").strip()[:200]
                                                         or "account pick exit %d" % r.returncode)
    if d.get("owns") is not True:
        return ("%s: its text goes only to a login its tenant owns, and the %s login account pick names, %s, is not "
                "one (a tenant gets %s by adding its own login: account tenant set)" % (where, provider, d["account"], provider))
    return None


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
# 2026-10-30, "Under 70% we can run anything", set on every row; week_max 90: the owner,
# 2026-10-31, "bump the ceiling for not taking work to 90% for all accounts"), with no reserve that
# lifts it to 100 (the owner, 2026-11-04: every login's bar at 90% or lower; past it a job starts only
# by lighthouse's `account pick --overdraw`). No deny list since deny-drift (2026-11-03; the owner: "rely
# on confidential scopes only"): such a login is no tenant's, so lighthouse's tenancy keeps every tenant's
# repos off it, the vault's tenant's included, and a scope's `login` routes a confidential repo's runs to
# their own seat. `regatta/orca-deny` is read by nothing. `repos.deny` stays, always empty and read by
# nothing, while the overlay's suite still prints it from this checkout (AGENTS.md, the alias trap): drop
# it once that read is gone.
ORCA_ROW = {"rules": {"week_max": 90, "window_max": 50, "free_below": 70},
            "repos": {"deny": []}}


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
    secondary (ORCA_ROW's rules), placed just before the primary, and in the walk
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
    # a builder host's row (`<host>-<vendor>`, the Argon arm's S2): its config dir's `wharf-runs/host`, which
    # builder-host make writes, so a launchd job's run names the row its sweep claimed as. No key, the Mac's name.
    key = re.sub(r"[^a-z0-9-]", "-", (config_line("wharf-runs/host") or "").strip().lower()).strip("-")
    if key:
        _host = key
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
CI_HOLD_NOTE = ("Build CI labelled this pull request `hold` to keep automerge off. "
                "`bin/pr ready` takes this label off after curation.")
HOLD_NOTES = (HOLD_NOTE, CI_HOLD_NOTE)


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
    Returns True when the PR is no longer a draft. A PR held by open_pr or build CI (its
    `_held` mark, or a HOLD_NOTES entry in its body) loses that `hold` here, best effort: ready is the
    curated signal the draft would have given, and automerge arms on `unlabeled`. The mark is
    one-shot: the note leaves the body with the label, so a later ready — after the owner labelled
    the PR `hold` themselves — finds no mark and leaves their brake on."""
    slug = ((pr.get("base") or {}).get("repo") or {}).get("full_name")
    body = pr.get("body") or ""
    notes = [note for note in HOLD_NOTES if note in body]
    if slug and (pr.get("_held") or notes):
        st, _ = api("DELETE", f"/repos/{slug}/issues/{pr['number']}/labels/{HOLD['name']}", tok=tok)
        if st in (200, 404) and notes:  # 404: the label never stuck; the mark is spent
            for note in notes:
                body = body.replace(f"\n\n{note}", "").replace(note, "")
            edited = edit_pr(slug, pr["number"], tok, body=body)
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
# `handed`: a dispatched yolo or dnd run, or a `default` one started with the landing switch on (task-shape S3), hands its landing to dispatch's launch (wharf-runs' yolo_launch,
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


# session-asks R2 (docs/session-asks-2026-10-09.md): what a skippered run hands the owner past its
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
    """What a reply hands the owner that a skippered run must relay instead: 'the WAITING line' when it
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


def autofinish_landings():
    """{"by", "ts"} when this Mac's done `default` builds hand their landing to dispatch (the landing
    switch, `autofinish arm --landings`; task-shape S3), else None (off: the default). Apart from
    `armed`: the sweep's switch, which yolo and dnd launches still need."""
    return _json_object(autofinish_state_dir() / "landings")


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
    """The runner's name: the record's, else the session name dispatch gives it, `finish-<topic>`."""
    if rec.get("window"):
        return rec["window"]
    topic = re.sub(r"^claude/(?:[^/]+/)?(?:\d{4}-\d{2}-\d{2}-)?", "", branch or "") or "?"
    # the very call dispatch makes of autofinish-run's NAME, so a topic `finish-x` reads finish-x here too
    return session_name("work", f"finish · {topic}", lead=True)


# ---- session names (the owner, 2026-11-01: "easy to follow") ----------------------------------
# A session a launcher starts is named `<verb>-<topic>`: the verb says which agent runs it or what it
# is for, the topic what it works on, so a list of runs reads as a list of jobs. Until then every
# dispatched run was `run-<topic>`, and every landing `run-finish` (dispatch cut "finish · <topic>"
# at its first ` · `), twelve alike in one repo's last sixty sessions. Fitted to `session_name_max()`, a
# soft target: whole words go from the end first, so the verb and the topic's head survive. A session the
# owner typed keeps `<repo>: <topic>` whole (checkpoint's Stop title, pickup): dispatch-rc's window_session
# ties a pickup window to its session by that name, so it must stay unique in its repo (landing review).
SESSION_VERBS = {
    "build": "a build step from a handoff brief: worker, sr-worker, principal-worker, main or no tier",
    "design": "a brief at an architect tier (architect, sr-architect, principal-architect): a design doc",
    "finish": "a landing: /finish of the branch its topic names",
    "steer": "a skipper keeping a scope's ships moving (helm)",
    "work": "a task sent with a prompt (harness run, helm send) whose name leads with no verb here",
    "probe": "dispatch --probe: a start that only proves a session can run",
    "see": "a read-only look: a review, a watch, an audit",
    "sound": "a sounding: an idea weighed before anything is built",
    "evolve": "the Evolve loop's pass over the owner's answers",
}
# len("Regatta: arm yard remaining"), the owner's yardstick: about what a phone's session list and VS
# Code's panel show without cutting. <config>/regatta/session-name-max overrides it.
SESSION_NAME_MAX = 27
SESSION_NAME_MIN = 12  # below this a name is a verb and a stub; a smaller key reads as unset


def session_name_max():
    """The soft cap on a session name: `regatta/session-name-max` when it reads as a whole number of
    at least SESSION_NAME_MIN, else SESSION_NAME_MAX. Optional: a bad value is one stderr line and the
    default, never an error (Traps: an optional key in config_problems() fails every hook)."""
    raw = config_line("regatta/session-name-max")
    if not raw:
        return SESSION_NAME_MAX
    try:
        n = int(raw)
    except ValueError:
        n = 0
    if n < SESSION_NAME_MIN:
        import sys
        print(f"regatta/session-name-max: {raw!r} is no whole number of at least {SESSION_NAME_MIN}; "
              f"using {SESSION_NAME_MAX}", file=sys.stderr)
        return SESSION_NAME_MAX
    return n


def _name_words(text):
    """A topic's words: a branch's `claude/<host>/<date>-` and any date dropped, split on what a
    topic, a slug or a window name separates words with."""
    text = re.sub(r"^claude/(?:[^/]+/)?", "", str(text or "").strip())
    text = re.sub(r"^\d{4}-\d{2}-\d{2}-?", "", text)
    return [w for w in re.split(r"[\s\-_/·:]+", text.lower()) if w]


def _fit(verb, words, cap):
    """`<verb>-<words>`, whole words dropped from the end until it fits `cap`. The verb and the first word
    always stay whole, past the cap if need be: the cap is soft, and a cut word names nothing."""
    words = list(words) or ["?"]
    while len(words) > 1 and len(verb + "-" + "-".join(words)) > cap:
        words.pop()
    return verb + "-" + "-".join(words)


def session_name(verb, topic, lead=False, cap=None):
    """The name a launcher gives a session: `<verb>-<topic>` (`build-queue-rank`, `finish-vendor-hooks`).
    With `lead`, a NAME of the form `<verb> · <topic>` whose verb is known keeps it (dispatch --start's
    NAME, "finish · <topic>"); `verb` is the fallback. Only that form: a slug that merely starts with a
    verb's word (`build-review`, `see-also-links`) is a topic. Fitted to `cap`, else session_name_max()."""
    cap = cap or session_name_max()
    m = re.match(r"\s*(\w+)\s+·\s", str(topic or "")) if lead else None
    words = _name_words(topic[m.end():] if m and m.group(1).lower() in SESSION_VERBS else topic)
    if m and m.group(1).lower() in SESSION_VERBS:
        verb = m.group(1).lower()
        # "finish · finish-stale-tip": a topic that repeats the verb says it once
        while words and words[0] == verb:
            words = words[1:]
    return _fit(verb, words, cap)


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
