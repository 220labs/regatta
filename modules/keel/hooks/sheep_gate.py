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
erase a prompt. Antigravity reads a hook's stdout as its answer and takes anything but JSON as a
deny (sessionpipe's adapters/antigravity.ts), so for it the gate prints `{}` before anything
else, on every path, and discards sessionpipe's stdout (0.5.0 only ever answers `{}` there).

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
or writing there still reports, but not those tool events. What this cannot reach (residual,
proposal section 5h): at tier 2 sessionpipe's worker reads the turn's text from the transcript
file at Stop, so a non-private session's own words *about* the vault content leave, redacted
for secrets only. A session that `cd`s into the vault stops reporting from that event on;
what it sent before stays sent — `sheep forget-private` is the deletion path.

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
Tests: tests/sheep_gate.sh; the overlay's hooks/test_hooks.sh, "sheep".
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



def _config_lines(name):
    """`<config>/<name>`'s non-blank lines as the core's config_read reads them, without the core;
    None when the file is absent or does not read."""
    cfg = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
    try:
        text = (cfg / name).read_text(encoding="utf-8-sig")
    except (OSError, UnicodeDecodeError):
        return None
    return [l.strip() for l in text.splitlines() if l.strip()]


def _overlay():
    cfg = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
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
    cfg = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
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
        return tuple(common.confidential_roots())
    except Exception:
        return None if _registry_file() else ()


def _roots():
    home = Path.home()
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
    for part in Path(os.path.expanduser(str(path))).parts:
        if part.casefold() in names:
            return names[part.casefold()]
    return None


def slug(path):
    """Claude Code's folder name under ~/.claude/projects for a start directory."""
    return re.sub(r"[^A-Za-z0-9]", "-", str(path))


def _real(p):
    try:
        return Path(os.path.realpath(os.path.expanduser(str(p))))
    except Exception:
        return Path(str(p))


def _path_reason(p):
    if not p or not isinstance(p, str):
        return None
    home, subtree, projects = _roots()
    for cand in {Path(os.path.abspath(os.path.expanduser(p))), _real(p)}:
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
            if _fold(root) in low:
                return f"the event names {root}"
        if home in r.parents and ("~/" + _fold(r.relative_to(home))) in low:
            return f"the event names {r}"
    for r in confidential_roots() or ():
        if _fold(slug(r)) in low:   # its transcripts and memory, under any login dir's projects/
            return f"the event names {r}'s transcript folder"
    if any(_fold(seg) in low for seg in SECRETS_SEGMENTS):
        return "the event names Drive's _secrets"
    if MEMORY.search(text):
        return "the event names an auto-memory file (it lives in the vault)"
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
    state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
    stamp = state / "keel" / "sheep-beats" / hashlib.sha256(sid.encode("utf-8")).hexdigest()[:32]
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
    if confidential_roots() is None or PRIVATE_UNREAD:
        return
    name = harness(argv)
    transcript = event.get("transcript_path") if name == "claude-code" else None
    if council_arm(places(name, event)):
        return
    if any(private_reason(p) for p in places(name, event)) \
            or private_reason(None, transcript, os.environ.get("CLAUDE_PROJECT_DIR")) \
            or _text_reason(data):
        return
    if name == "codex" and argv[-1] == "PermissionRequest" and os.environ.get("PLAN_HARNESS") == "codex":
        return   # the run's own approver answers; no owner attention, no approval decision here
    # communicate() feeds stdin without the 64 KB pipe-buffer deadlock. Claude Code and Codex:
    # stdout and stderr are inherited (a PermissionRequest answer goes straight back).
    # Antigravity: the answer was written before anything else, and sessionpipe 0.5.0's own is `{}`
    # on every path (antigravity.ts fromHook), so its stdout goes nowhere: a second answer is noise.
    out = subprocess.DEVNULL if name == "antigravity" else None
    subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=out).communicate(data)
    if name == "codex" and argv[-1] == "PreToolUse":
        activity = codex_activity(event)
        if activity is not None:
            subprocess.Popen([*argv[:-1], "UserPromptSubmit"], stdin=subprocess.PIPE,
                             stdout=subprocess.DEVNULL).communicate(activity)


if __name__ == "__main__":
    # Antigravity: `{}` first, as sessionpipe's own hook.js does, so a crash or Antigravity's 5 s
    # timeout killing this process still leaves it an answer (module docstring).
    if harness(sys.argv[1:]) == "antigravity":
        try:
            os.write(1, b"{}\n")
        except BaseException:
            pass
    try:
        main(sys.argv[1:], sys.stdin.buffer.read())
    except BaseException:  # SystemExit included: this hook's only exit code is 0
        pass
    os._exit(0)
