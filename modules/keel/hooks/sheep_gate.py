#!/usr/bin/env python3
"""sheep_gate — the privacy gate in front of every sessionpipe hook entry. Stdlib, Python 3.9.

    python3 <overlay>/hooks/sheep_gate.py "<sessionpipe-hook>" <harness> <Event>

`bin/sheep gate` rewrites each sessionpipe entry to this form — Claude Code's settings.json,
Codex's hooks.json, Antigravity's hooks.json (the harness is the argv's second-last word);
sessionpipe's own command is the argv after this script. The gate reads the hook's stdin JSON
and, when the event is private, exits 0 having sent nothing: sessionpipe never runs, so no
outbox line, no sink. Otherwise it runs sessionpipe's command with the same stdin bytes; its
stdout (a PermissionRequest answer) passes through, its exit code does not — a script under
hooks/ never exits non-zero (AGENTS.md), and a crashing sessionpipe must not block a tool or
erase a prompt. Antigravity 1.5.2 reads `{}` as a deny. For it the gate prints nothing
on every path and discards sessionpipe's stdout (0.5.0 only ever answers `{}` there).
Dropping a private reporting event does not deny the tool: Regatta's separate guard
handler owns tool decisions, including its decision/reason JSON on a denial.

Where a session runs, per harness: Claude Code and Codex put `cwd` in the event (Codex's
`transcript_path` is a rollout under $CODEX_HOME/sessions, which says nothing of the folder, so only
Claude Code's is read as a slug); Antigravity has no `cwd` but `workspacePaths` (file:// URIs or
paths), each judged, and this process's cwd only when it names none.

Why it exists: sessionpipe has no folder rule — its config holds sinks and per-harness switches,
its filter is per tier and event type — so the vault has to be dropped before sessionpipe ever
sees the event (docs/record/orchestration-proposal-2026-10-02.md, section 4, section 5h, E1; D1).

Private (the one definition; bin/sheep imports `private_reason` for forget-private and audit,
bin/helmlib.py's GUARDED (planlib.py before rename S5) and bin/memo's `never_mirrored` read PRIVATE_REPOS, talk_nudge.py
`private_reason`):
- a path at or under ~/projects/<repo> for each of PRIVATE_REPOS (the vault, `transcripts`,
  each `regatta/guarded` name; their worktrees included), or one with any of those names as a path part
  (helmlib's rule: a worktree's toplevel is named for its topic, not its repo), or anything
  whose real path runs through a vault's `_secrets` folder (the `lighthouse/vaults` key). Two guarded repos joined
  2026-10-16: planlib and bin/jev guarded them, this did not, and 22 of their sessions sat in the
  outbox;
- a path at or under the checkout of a repo in a confidential scope (`"confidential": true` in
  repos.json's scopes, read through the core's `confidential_roots()`; knowledge-layers D3,
  2026-10-20), its `.claude/worktrees` included — they sit inside it. A worktree made outside the
  checkout is caught only through its transcript slug (it starts with the checkout's). No
  registry file: PRIVATE_REPOS alone, as before the flag. A registry file that does not read, or
  a core that does not import beside one: every event is dropped (the fence cannot be read);
- a path that reaches those: ~/projects, ~, and every ancestor of ~ up to `/` (sessionpipe's
  own `isBroad` treats the home folder and its ancestors the same way), and any folder that holds
  one of the roots above (a scope key nests, `films/<repo>`).
Paths compare case-folded: APFS here is case-insensitive, so `~/Projects/Archive` is the same
folder. A session is private when its `cwd` (else this process's, which is what sessionpipe
falls back to), $CLAUDE_PROJECT_DIR, or the folder its transcript is filed under (Claude Code's
slug of the start directory: every non-alphanumeric character is `-`) says so. The slug is
lossy (the vault and `.personal` slug alike), which only ever drops more.

An event is also dropped when its raw text names a private path (a confidential root also in its
slug form, the folder its transcripts and memory sit under in any login dir, an Orca profile's
included) or an auto-memory file (`~/.claude/projects/<slug>/memory/…` links into
the vault/memory): a household session reading
or writing there stops reporting from its first dropped event. What this cannot reach (residual,
proposal section 5h): at tier 2 sessionpipe's worker reads the turn's text from the transcript
file at Stop, so a non-private session's own words *about* the vault content leave, redacted
for secrets only. A session that `cd`s into the vault stays blocked even after it leaves;
what it sent before stays sent — `sheep forget-private` is the deletion path.

Verified privacy drops are remembered under $XDG_STATE_HOME/regatta/sheep-gate (default: the
home folder's .local/state/regatta/sheep-gate), keyed by harness and sessionpipe's safe
session id in lower case. Case aliases share a denial on every platform, because
sessionpipe's facts filenames alias on case-insensitive filesystems.
Every later event of that session is dropped, including Stop, Interrupt and SessionEnd:
all three can read transcript text from an older `transcript_line`, and heavy events read
transcript facts. This chooses the later-Stop drop of
docs/sheep-teams-2026-11-03.md, S2,
over editing every instance's facts: a worker can overwrite an edited cursor or read it
before the gate advances it, and a new instance starts at zero. The gate's markers are
shared across SESSIONPIPE_STATE/CONFIG/SOCKET choices on Macs and Linux; no facts store
is opened and no platform-specific sessionpipe path is assumed. Empty directories are
atomic, contain no transcript text, and are never expired or reset at SessionStart (a
resumed session can still replay its history). A fresh session follows the current
scope flag; no `sheep` block is read. Keep the gate state when moving sessionpipe state.
Relative XDG_STATE_HOME values are ignored, so a cwd change cannot move the marker store.
The gate repairs its own store's owner permissions (a chmod, never a creation); a read of a
store that does not exist yet, or that a file in its path makes impossible, finds no marker and
creates nothing. An unreadable
or symlinked store, or a write that still fails, drops the current event but cannot promise a lasting
fence; neither can a hook killed before recording its decision. Events without a session
id cannot be remembered; sessionpipe's supported adapters produce no session for them.
Not closed here (residual): a fork or a transcript copied to another host gets a new id
with no marker and a cursor of 0; a Stop job sessionpipe queued before the drop reads to
the transcript's end when it runs; Codex's ungated `notify` entry never meets the gate.
Policy-unreadable drops (including a core import failure or another policy exception) leave
no marker: the next event is judged afresh (B, the owner, 2026-11-04). During that unreadable
moment sessionpipe's cursor replay is not blocked. A verified private path or text match
still fences the session for good on the roads that pass a hook: its Stop-block Session-tab
delivery and its permission requests (phone approvals). sessionpipe's daemon also reaches a
session with no hook between: its resume road (`claude -p --resume <id>` in the session's start
folder) and its waiter road (`sessionpipe wait`, which reads the answer from the transcript) post
the answer back unjudged, and its fork road is the fork residual above. Closing those needs
sessionpipe to refuse a session by id (an upstream ask). A root named only as the start of a
longer name (`know.`, `know-wt/…`, a Codex cwd `know-topic`) drops that event, as before this
branch, with no lasting marker: a later open Stop sends its turns, as main did.
Changing HOME or an absolute XDG_STATE_HOME moves the store: carry the markers with it.
Builders pin SHEEP_POLICY_HOME to the original absolute home before installing a scratch
HOME. Guarded roots, confidential roots and ~ expansion keep that policy home; delivery
and marker stores remain pinned separately. A malformed policy home drops every event.

A council arm sends nothing either (wharf's bin/council): an event whose hook runs with
REGATTA_COUNCIL_ARM set, or whose folder lies under a council run dir (its `.council-run` marker): the
arm's copy may hold a guarded home's text under /private/tmp, where no path rule here sees it (the
council's landing review, 2026-10-28; latent while sessionpipe enables claude-code alone, whose council
arm runs with every hook off).

Fails closed: stdin that is not a JSON object sends nothing, nor does any event while the
confidential scopes cannot be read, or the overlay's `regatta/guarded` cannot. Exit code always 0.
Codex activity (sessionpipe 0.5.0): a `codex exec` build is one turn, so a receiver that
counts a session's activity from its last turn.started reads it as idle while its tools run
(the brief's 38-minute case; spacesheep is a tier-2 sink, bin/sheep's SINK, so its tool events
were delivered: what the receiver makes of them is not read). Before a tool runs, send a
prompt-free UserPromptSubmit too: the adapter accepts it and emits tier-0 turn.started under the
event's own session and turn_id. At most one a minute per session (a stamp in keel's state
folder, like hook.js's beats), only with a turn_id (none would read as a new prompt), and never
on PostToolUse (its job can lose the session lock to Stop's and land a turn.started after
turn.ended). A workaround whose effect on the receiver is unverified; upstream needs a native
session.heartbeat (docs/sheep-codex-activity-upstream-2026-11-04.md). The original tool event
stays intact. No extra event is made until every privacy check has passed.
PermissionRequest is dropped for PLAN_HARNESS=codex: wharf-runs sets that marker on the Codex
runs it starts, its exec runs (codex.child_env; _argv always uses --approve-for-me, resume and
fork too) and the Orca terminal worker (orca.py's _codex_terminal, `codex --approve-for-me`).
This is telemetry only, never an approval answer (sessionpipe answers no Codex permission).
Unattended alone says nothing about who approves; every other harness and a hand-started
Codex keep theirs.
Tests: modules/keel/tests/sheep_gate.sh; the overlay's hooks/test_hooks.sh, "sheep".
"""
import functools
import hashlib
import json
import os
import stat
import re
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path


def policy_home_valid():
    return "SHEEP_POLICY_HOME" not in os.environ or os.path.isabs(os.environ["SHEEP_POLICY_HOME"])


def policy_home():
    """The builder's original policy home, independent of its disposable login HOME."""
    value = os.environ.get("SHEEP_POLICY_HOME")
    return Path(value) if value and os.path.isabs(value) else Path.home()


def _expanduser(path):
    value = str(path)
    if value == "~" or value.startswith("~/"):
        return str(policy_home()) + value[1:]
    return os.path.expanduser(value)



def _config_lines(name):
    """`<config>/<name>`'s non-blank lines as the core's config_read reads them, without the core;
    None when the file is absent or does not read."""
    cfg = Path(_expanduser(os.environ.get("REGATTA_CONFIG") or policy_home() / ".config" / "regatta"))
    try:
        text = (cfg / name).read_text(encoding="utf-8-sig")
    except (OSError, UnicodeDecodeError):
        return None
    return [l.strip() for l in text.splitlines() if l.strip()]


def _overlay():
    cfg = Path(_expanduser(os.environ.get("REGATTA_CONFIG") or policy_home() / ".config" / "regatta"))
    return (cfg / "regatta" / "overlay").exists()   # the overlay's marker (B14a; the only one since B14b)


# The repos whose sessions, rows and pages never leave the Mac — the one list (module docstring):
# the core's `regatta/guarded` (bin/jev's list) and the transcript archive. Compared case-folded, as
# a path part (private_part): APFS is case-insensitive. Where the overlay is installed and that key
# does not read, PRIVATE_UNREAD, and main() drops every event, as for an unreadable registry.
_GUARDED = _config_lines("regatta/guarded")
PRIVATE_REPOS = tuple(_GUARDED or ()) + ("transcripts",)
PRIVATE_UNREAD = _GUARDED is None and _overlay()
# The vaults whose `_secrets` never leaves: `lighthouse/vaults` (the vault folders, by name); without
# that key, a `_secrets` folder in any path — a wider net, never a narrower.
_VAULTS = _config_lines("lighthouse/vaults")
SECRETS_SEGMENTS = tuple("/%s/_secrets" % v for v in _VAULTS) if _VAULTS else ("/_secrets",)
# An auto-memory path: every project's memory folder links into the vault/memory/<project>.
MEMORY = re.compile(r"/\.claude[^/\"]*/projects/[^/\"]+/memory(?:/|\")")


def _fold(p):
    return str(p).casefold()


def _registry_file():
    """Whether a registry file is there, without the core: the core's repos_json() order."""
    v = os.environ.get("CLAUDE_REPOS_JSON")
    cfg = Path(_expanduser(os.environ.get("REGATTA_CONFIG") or policy_home() / ".config" / "regatta"))
    p = Path(v) if v else cfg / "wharf" / "repos.json"
    return p.exists() or p.is_symlink()   # a dangling link is a registry gone, not none (the core's rule)


@functools.lru_cache(maxsize=None)
def confidential_roots():
    """The checkouts of the confidential scopes' repos, from the core (keel's lib/find_core.py
    order); () with no registry file; None when one is there and cannot be read — no core, a
    core that does not import, a file that does not parse — so the gate fails closed (the /finish
    review of S1, 2026-10-22: a torn read was the open door). Never raises."""
    try:
        lib = str(Path(__file__).resolve().parent.parent / "lib")
        if lib not in sys.path:
            sys.path.insert(0, lib)
        import find_core
        hooks = next((str(c) for c in find_core.candidates() if (c / "common.py").is_file()), None)
        if not hooks:
            return None if _registry_file() else ()
        if hooks not in sys.path:
            sys.path.insert(0, hooks)
        import common
        if not hasattr(common, "confidential_roots"):   # a core from before the flag: as before it
            return ()
        if getattr(common, "registry_unreadable", lambda: False)():
            return None
        roots = tuple(common.confidential_roots())
        if policy_home() != Path.home():
            # The core's default PROJECTS was loaded under the scratch HOME too.
            configured = common.config_line("regatta/projects")
            value = _expanduser(configured) if configured else ""
            projects = Path(value) if os.path.isabs(value) else policy_home() / "projects"
            rebased = []
            for root in roots:
                try:
                    root = projects / root.relative_to(common.PROJECTS)
                except ValueError:   # an absolute registry key outside PROJECTS stays absolute
                    pass
                rebased.append(root)
            roots = tuple(rebased)
        return roots
    except Exception:
        return None if _registry_file() else ()


def _roots():
    home = policy_home()
    projects = home / "projects"
    return home, [projects / r for r in PRIVATE_REPOS] + list(confidential_roots() or ()), projects



def private_part(path):
    """The PRIVATE_REPOS name `path` runs through as a path part, case-folded, else None. A bare
    repo name is a one-part path, so `private_part("archive")` is "archive" too (with archive guarded). A confidential
    scope's repo counts by its folder name as well, so keel's never_mirrored and helm's guarded(),
    which ask here, keep it in too (the /finish review of S1, 2026-10-22). An unreadable registry
    adds no name here — this also feeds forget-private; the gate's main() drops every event then."""
    if not path or not isinstance(path, (str, Path)):
        return None
    names = {r.name.casefold(): r.name for r in confidential_roots() or ()}
    names.update({r.casefold(): r for r in PRIVATE_REPOS})
    for part in Path(_expanduser(path)).parts:
        if part.casefold() in names:
            return names[part.casefold()]
    return None


def slug(path):
    """Claude Code's folder name under ~/.claude/projects for a start directory."""
    return re.sub(r"[^A-Za-z0-9]", "-", str(path))


def _real(p):
    try:
        return Path(os.path.realpath(_expanduser(p)))
    except Exception:
        return Path(str(p))


def _path_reason(p):
    if not p or not isinstance(p, str):
        return None
    home, subtree, projects = _roots()
    for cand in {Path(os.path.abspath(_expanduser(p))), _real(p)}:
        c = _fold(cand)
        if any(_fold(seg) + "/" in c + "/" for seg in SECRETS_SEGMENTS):
            return f"{cand} is in Drive's _secrets"
        for r in subtree:
            for root in {r, _real(r)}:
                ro = _fold(root)
                if c == ro or c.startswith(ro.rstrip("/") + "/"):
                    return f"{cand} is under {root}"
                if ro.startswith(c.rstrip("/") + "/"):   # ~/projects/films holds films/<a confidential repo>
                    return f"{cand} holds {root}"
        for broad in {home, _real(home), projects, _real(projects)}:
            b = _fold(broad)
            if c == b or b.startswith(c.rstrip("/") + "/"):
                return f"{cand} reaches {broad}, and with it every repo"
        name = private_part(cand)
        if name:
            return f"{cand} runs through a folder named {name}"
    return None


def _slug_reason(folder):
    if not folder:
        return None
    f = folder.casefold()
    home, subtree, projects = _roots()
    if any(_fold(slug(seg)) in f for seg in SECRETS_SEGMENTS):
        return f"transcript folder {folder} is Drive's _secrets"
    for root in subtree:
        s = _fold(slug(root))
        if f == s or f.startswith(s + "-"):
            return f"transcript folder {folder} is {root}"
    h = _fold(slug(projects))
    if f == h or h.startswith(f + "-") or f in ("-", ""):
        return f"transcript folder {folder} reaches {projects}"
    return None


def _text_reason(raw):
    """A private path or an auto-memory file named anywhere in the event's raw text."""
    text = raw.decode("utf-8", "replace") if isinstance(raw, bytes) else str(raw)
    low = text.casefold()
    home, subtree, _ = _roots()
    for r in subtree:
        for root in {r, _real(r)}:
            if re.search(re.escape(_fold(root)) + r"(?![\w.-])", low):
                return f"the event names {root}"
        if home in r.parents and re.search(re.escape("~/" + _fold(r.relative_to(home))) + r"(?![\w.-])", low):
            return f"the event names {r}"
    for r in confidential_roots() or ():
        if _fold(slug(r)) in low:   # its transcripts and memory, under any login dir's projects/
            return f"the event names {r}'s transcript folder"
    if any(_fold(seg) in low for seg in SECRETS_SEGMENTS):
        return "the event names Drive's _secrets"
    if MEMORY.search(text):
        return "the event names an auto-memory file (it lives in the vault)"
    return None


def _text_prefix(raw):
    """A private root named only as the start of a longer name (`know.`, `know-wt/…`, a Codex cwd
    `know-topic`): main's plain substring rule, kept so no denial main had is lost. Such an event is
    dropped, as on main, but leaves no lasting marker: `knowledge-base` matches it too, and a session
    that only names a sibling must not go dark for good. A Claude Code session started in the
    sibling is still fenced by its transcript slug's substring (`_text_reason`), as main dropped it."""
    low = (raw.decode("utf-8", "replace") if isinstance(raw, bytes) else str(raw)).casefold()
    home, subtree, _ = _roots()
    for r in subtree:
        for root in {r, _real(r)}:
            if _fold(root) in low:
                return f"the event names a path starting {root}"
        if home in r.parents and ("~/" + _fold(r.relative_to(home))) in low:
            return f"the event names a path starting {r}"
    return None


def private_reason(cwd=None, transcript_path=None, project_dir=None):
    """Why this session must not leave the machine, or None."""
    for p in (cwd, project_dir):
        why = _path_reason(p)
        if why:
            return why
    if transcript_path:
        return _slug_reason(Path(str(transcript_path)).parent.name)
    return None


def harness(argv):
    """The harness sessionpipe's command names: its second-last word (`<hook> <harness> <Event>`,
    or `node <hook.js> <harness> <Event>`); claude-code for a command too short to say."""
    return argv[-2] if len(argv) >= 3 else "claude-code"


def workspace_paths(value):
    """Antigravity's workspacePaths as absolute local paths, as sessionpipe's agWorkspaces reads
    them: a file:// URI decoded, a plain absolute path kept, a remote URI or a relative path left
    out (the raw-text scan still sees its words)."""
    out = []
    for p in value if isinstance(value, list) else []:
        if not isinstance(p, str) or not p:
            continue
        if p[:5].lower() == "file:":
            p = urllib.parse.unquote(urllib.parse.urlparse(p).path)
        elif re.match(r"^[a-z][a-z0-9+.-]*://", p, re.I):
            continue
        if os.path.isabs(p) and p not in out:
            out.append(p)
    return out


def places(name, event):
    """The folders the session runs in, per harness (module docstring)."""
    if name == "antigravity":
        return workspace_paths(event.get("workspacePaths")) or [os.getcwd()]
    return [event["cwd"] if isinstance(event.get("cwd"), str) else os.getcwd()]


COUNCIL_MARKER = ".council-run"   # only where no core is found: the core's common.COUNCIL_MARKER is the name


@functools.lru_cache(maxsize=None)
def council_marker():
    """The council's run-dir marker: the core's common.COUNCIL_MARKER (one home, the council's third landing
    review's finding 24), else COUNCIL_MARKER when this keel has no core beside it. keel.sh checks the two agree."""
    try:
        lib = str(Path(__file__).resolve().parent.parent / "lib")
        if lib not in sys.path:
            sys.path.insert(0, lib)
        import find_core
        hooks = next((str(c) for c in find_core.candidates() if (c / "common.py").is_file()), None)
        if hooks:
            if hooks not in sys.path:
                sys.path.insert(0, hooks)
            import common
            return getattr(common, "COUNCIL_MARKER", COUNCIL_MARKER)
    except Exception:   # noqa: BLE001 — a core that does not import: the name it has always had
        pass
    return COUNCIL_MARKER


def council_arm(folders):
    """True for an event of a council arm: the variable bin/council's arm_env sets, or a folder at or under
    a dir holding its marker (council_marker(); the module docstring) that is a run dir as council makes one:
    this account's, closed to others (0700), the marker its own too — as the core's fence.box_why judges it. A
    stray marker elsewhere (another account's, a world-writable scratch root) silences nothing (round 6)."""
    if os.environ.get("REGATTA_COUNCIL_ARM"):
        return True
    marker = council_marker()
    uid = os.getuid()
    for f in folders:
        d = os.path.realpath(f) if isinstance(f, str) and f else None
        while d:
            m = os.path.join(d, marker)
            try:
                st, sm = os.stat(d), os.lstat(m)
            except OSError:
                st = sm = None
            if st is not None and stat.S_ISREG(sm.st_mode) and st.st_uid == uid and sm.st_uid == uid \
                    and not st.st_mode & 0o077:
                return True
            up = os.path.dirname(d)
            d = None if up == d else up
    return False


def _state_root():
    xdg = os.environ.get("XDG_STATE_HOME", "")
    return Path(xdg) if os.path.isabs(xdg) else Path.home() / ".local" / "state"


def session_dropped(name, event, dropped):
    """Read a lasting denial, or record a verified privacy drop, across sender instances.

    Match the supported adapters' id precedence (sessionpipe 0.5.0 fromHook) and
    facts' safeId spelling, including case aliases on case-insensitive filesystems,
    so two ids sharing facts cannot bypass a marker. Do not use the cwd or transcript
    path: both can change during a session.
    """
    keys = {"antigravity": ("conversationId", "session_id", "sessionId"),
            "claude-code": ("session_id", "sessionId")}.get(name, ("session_id",))
    sid = next((event[k] for k in keys if event.get(k) is not None), None)
    if sid is None:
        return dropped   # no session for the adapter to send
    if not isinstance(sid, str):
        return True      # no supported hook needs a non-string id (and {} is truthy in JS)
    if not sid:
        return dropped   # empty string is falsy in JS too
    # JS's non-Unicode regexp replaces each UTF-16 unit, then slice truncates to 160.
    safe = lambda s: re.sub(r"[^A-Za-z0-9_.-]", lambda m: "__" if ord(m[0]) > 0xffff else "_", s)[:160]
    # safeId is ASCII; fold its case before hashing, even on case-sensitive hosts,
    # so moving the store between platforms cannot separate these aliases.
    key = hashlib.sha256((safe(name) + "/" + safe(sid).lower()).encode()).hexdigest()
    root = _state_root() / "regatta" / "sheep-gate"
    try:
        if not dropped:
            # A read: a store that does not exist holds no marker, so this session is not fenced;
            # creating it here would let a store that cannot be made silence every session.
            try:
                st = root.lstat()
            except (FileNotFoundError, NotADirectoryError):
                return False   # no store, or one that a file in its path makes impossible
            if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
                return True   # something else sits where the store goes: fail closed
            if not os.access(root, os.X_OK):
                root.chmod(stat.S_IMODE(st.st_mode) | 0o700)   # the owner's own store: repair, create nothing
            if not os.access(root, os.X_OK):
                return True   # it exists and cannot be searched: it may hold this session's denial
            try:
                (root / key).lstat()   # any entry, even a broken link, is a denial
                return True
            except FileNotFoundError:
                return False
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        st = root.lstat()
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
            return True
        if not os.access(root, os.W_OK | os.X_OK):
            root.chmod(stat.S_IMODE(st.st_mode) | 0o700)
            if not os.access(root, os.W_OK | os.X_OK):
                return True
        marker = root / key
        try:
            marker.lstat()   # any entry, even a broken link, is a denial
            return True
        except FileNotFoundError:
            pass
        try:
            marker.mkdir(mode=0o700)
        except FileExistsError:
            pass        # another event already marked this session
        return True
    except OSError:
        return True


ACTIVITY_EVERY = 60   # seconds; hook.js throttles a tier-0 tool beat the same


def codex_activity(event):
    """The minimal payload for the UserPromptSubmit activity signal, or None when none is due.

    No prompt, tool input/output or transcript: the synthetic event must neither disclose tool
    text at another tier nor trigger a transcript read. Only an event with a session and a turn id;
    at most one per session per ACTIVITY_EVERY, by a stamp's mtime (a stamp that will not write
    sends nothing: an unthrottled signal is the cost the stamp exists to stop).
    """
    sid, turn = event.get("session_id"), event.get("turn_id")
    if not isinstance(sid, str) or not sid or not isinstance(turn, str) or not turn:
        return None
    stamp = _state_root() / "keel" / "sheep-beats" / hashlib.sha256(sid.encode("utf-8")).hexdigest()[:32]
    try:
        if time.time() - stamp.stat().st_mtime < ACTIVITY_EVERY:
            return None
    except FileNotFoundError:
        pass
    except OSError:
        return None
    try:
        stamp.parent.mkdir(parents=True, exist_ok=True)
        stamp.touch()
    except OSError:
        return None
    return json.dumps({k: event[k] for k in ("session_id", "cwd", "turn_id", "model")
                       if isinstance(event.get(k), str)}).encode("utf-8")


def main(argv, data):
    try:
        event = json.loads(data or b"null")
    except ValueError:
        return
    if not isinstance(event, dict) or not argv:
        return
    if not policy_home_valid():
        return   # an unreadable policy home never selects the disposable HOME's roots
    name = harness(argv)
    if session_dropped(name, event, False):
        return   # a fenced session needs no policy read (which can be slow or broken)
    transcript = event.get("transcript_path") if name == "claude-code" else None
    try:
        if confidential_roots() is None or PRIVATE_UNREAD:
            return   # B: an unreadable policy drops this event only
        folders = places(name, event)
        dropped = council_arm(folders) \
            or any(private_reason(p) for p in folders) \
            or private_reason(None, transcript, os.environ.get("CLAUDE_PROJECT_DIR")) \
            or _text_reason(data)
        if not dropped and _text_prefix(data):
            return   # main's substring denial: this event only, no lasting marker
    except Exception:
        return   # B also covers a policy evaluation that raises
    # Another hook may have fenced the session while this event read its policy.
    if session_dropped(name, event, bool(dropped)):
        return
    if name == "codex" and argv[-1] == "PermissionRequest" and os.environ.get("PLAN_HARNESS") == "codex":
        return   # the run's own approver answers; no owner attention, no approval decision here
    # communicate() feeds stdin without the 64 KB pipe-buffer deadlock. Claude Code and Codex:
    # stdout and stderr are inherited (a PermissionRequest answer goes straight back).
    # Antigravity: silence allows the tool; sessionpipe 0.5.0's `{}` would deny it.
    out = subprocess.DEVNULL if name == "antigravity" else None
    subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=out).communicate(data)
    if name == "codex" and argv[-1] == "PreToolUse" and not session_dropped(name, event, False):
        activity = codex_activity(event)
        if activity is not None:
            subprocess.Popen([*argv[:-1], "UserPromptSubmit"], stdin=subprocess.PIPE,
                             stdout=subprocess.DEVNULL).communicate(activity)


if __name__ == "__main__":
    try:
        main(sys.argv[1:], sys.stdin.buffer.read())
    except BaseException:  # SystemExit included: this hook's only exit code is 0
        pass
    os._exit(0)
