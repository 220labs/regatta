"""helm yard-on HOST SCOPE... [--dry-run] [--within H] — name HOST the yard of each SCOPE, once its tick drives.

A scope's `yard` turns wharf's fence on at once on every host: a plain `wharf apply` of a blueprint
ship in that scope is refused (wharf-runs' bin/wharf, `yard_fence`), and the yard host's tick drives
its ships. So the value waits for that tick, and for the blueprint ships laid here to finish
(skipper-resilience S3 and S13). It refuses (exit 1), naming which check failed, unless both hold:

  * `helm tick --status` on HOST, over ssh (sendlib's road: `wharf-runs/ssh`'s alias, the yard's own
    core), reads `armed`, or `dry` (armed, inside its first 3 h). Disarmed, no answer or an unreadable
    one is a refusal: a yard value with nothing driving is the state this guards against.
  * No blueprint ship of those scopes is in flight on this host: a task laid by `wharf apply` (its
    `blueprint` is set) running or relayed at any age, or not yet over and updated within --within hours
    (12). Those are the ships the fence would strand. A ship with no blueprint task (a typed session's,
    a skipper's own) is not one: the fence never refuses it, and counting it refused every arming while
    any session on this host was at work (the laptop, 2026-11-01; TODO.md [arm-yard] (b)). A task whose repo's
    scope cannot be told (no core, a path outside the projects folder, a torn registry) counts, as the fence
    fails closed; a repo the registry reads and puts in no scope does not, as the fence refuses nothing there.
    A repo is looked up by its registry key as the fence does (blueprintlib's repo_key: nested keys such
    as `<org>/<repo>` included), never by its folder's name alone.

Then `scopes set <scope> --yard HOST` for each scope in order, on the registry `scopes` itself
resolves, and the value read back through the core: a scope that does not read HOST is a failure
(exit 3) naming it. Run on HOST itself it refuses: the check reads this host's ships, the ones the
fence would strand elsewhere. Under an unattended caller it refuses to write (exit 2); --dry-run is
open to anyone and runs both checks. Exit: 0 written and read back (or a dry run that would
proceed); 1 refused; 2 usage or unattended; 3 a write or read-back failed.

Moved from the overlay's `bootstrap.sh --yard-on` (2026-11-02): the hosts and scopes are arguments,
never names in this file (AGENTS.md: public code never names a host).
"""
import os
import subprocess
import time
from pathlib import Path

import helmlib
import sendlib

LIVE = ("running", "relayed")                       # a worker is on it right now
OVER = ("done", "landed", "launched", "failed")     # nothing more will happen to the task


def tick_mode(host):
    """(mode, said): HOST's tick as `helm tick --status` there reads; mode None when it cannot be told, "node"
    for a node's peer this Mac has no alias for (yard-on reaches no node yet)."""
    alias = sendlib.alias_of(host)
    if not alias and host.lower().endswith("-agent"):   # every node's peer (orca-host's NODE_ROLE)
        return "node", ("%s is a node's peer: yard-on reaches no node yet (TODO.md [node-road-left] (g)); read "
                      "`helm tick --status` on it and write the yard with `scopes set`, never a wharf-runs/ssh row "
                      "for it" % host)
    if not alias:
        return None, "no ssh alias for %s (the config dir's wharf-runs/ssh) — cannot reach it" % host
    rc, out, err = sendlib.remote(alias, "helm", ["tick", "--status"], timeout=60)
    first = out.splitlines()[0] if (out or "").strip() else ""
    if rc != 0 or not first.startswith("helm tick: "):
        return None, "ssh %s `helm tick --status` gave rc=%s, %r" % (alias, rc, (first or (err or "").strip())[:120])
    return first[len("helm tick: "):].split(" ", 1)[0], first


UNKNOWN = object()   # the scope cannot be told: counts against every arming, as the fence fails closed


def repo_key(repo, common):
    """The registry key of a task's repo, by blueprintlib.repo_key's rule: a key as given, an absolute
    path's place under the projects folder; None outside it. wharf writes the task's repo as a path."""
    repo = str(repo)
    if not repo.startswith("/"):
        return repo
    try:
        return Path(os.path.realpath(repo)).relative_to(os.path.realpath(str(common.PROJECTS))).as_posix()
    except ValueError:
        return None


def scope_of(repo):
    """The scope of a task's repo (a path or a registry key); None for a repo in no scope; UNKNOWN when
    it cannot be told."""
    if not repo:
        return UNKNOWN
    try:
        common = helmlib._common()
        if common.registry_unreadable():
            return UNKNOWN
        key = repo_key(repo, common)
        return common.scope_of_key(key) if key else UNKNOWN
    except Exception:   # noqa: BLE001 — no core: cannot be told, which counts
        return UNKNOWN


def in_flight(scopes, within_h, now=None):
    """[line] for each blueprint ship of SCOPES in flight here, or (None, why) when the store will not read."""
    now = now or time.time()
    out = []
    for pid in helmlib.list_plans():
        try:
            st = helmlib.state(pid)
        except (OSError, ValueError, FileNotFoundError) as e:
            return None, "`helm state %s` was not readable: %s" % (pid, e)
        laid = [t for t in st.get("tasks") or [] if t.get("blueprint")]
        mine = [t for t in laid if (lambda sc: sc is UNKNOWN or sc in scopes)(scope_of(t.get("repo")))]
        if not mine:
            continue
        live = any(t.get("status") in LIVE for t in mine)
        updated = float(st.get("updated") or 0)
        recent = now - updated < within_h * 3600 and any(t.get("status") not in OVER for t in mine)
        if live or recent:
            out.append("%s (%s, %s)" % (st.get("topic") or pid, pid[:8], "a task running or relayed" if live
                                        else "updated %dm ago" % ((now - updated) // 60)))
    return out, ""


def unattended():
    """The core's marker names (common.UNATTENDED_NAMES), so a new name reaches this refusal too; the
    two known today when the core will not load."""
    try:
        names = helmlib._common().UNATTENDED_NAMES
    except Exception:   # noqa: BLE001
        names = ("REGATTA_UNATTENDED", "CLAUDE_UNATTENDED")
    return next((n for n in names if os.environ.get(n)), None)


def run(host, scopes, dry=False, within=12.0, say=print, err=None):
    err = err or (lambda m: say(m))
    scopes_tool = helmlib.peer("scopes")
    if not scopes_tool:
        err("helm yard-on: wharf's `scopes` is not installed here")
        return 2
    cmds = [[str(scopes_tool), "set", s, "--yard", host] for s in scopes]
    if dry:
        say("helm yard-on --dry-run: would run:")
        for c in cmds:
            say("  " + " ".join(c))
    elif unattended():
        err("helm yard-on: refused under %s — a yard is named by the person there" % unattended())
        return 2
    if sendlib.machine() == host:
        err("helm yard-on: %s this host is %s — run it where the scopes' ships were laid"
            % ("would refuse:" if dry else "refused:", host))
        return 1
    why = []
    mode, said = tick_mode(host)
    if mode in ("armed", "dry"):
        say("  ok      %s's tick reads %s (%s)" % (host, mode, said))
    elif mode == "node":   # its tick cannot be read from here: said as that, never as a tick not armed
        why.append(said)
    else:
        why.append("%s's tick is not armed — %s. Arm it there first: `helm tick --arm`" % (host, said))
    busy, bwhy = in_flight(scopes, within)
    if busy is None:
        why.append("cannot tell what is in flight here — %s" % bwhy)
    elif busy:
        why.append("blueprint ships of these scopes in flight here: %s — let them land, or pass --within with fewer "
                   "hours if they are parked (a running or relayed task counts at any age: settle it in helm)" % "; ".join(busy))
    else:
        say("  ok      no blueprint ship of %s in flight here (nothing running, none updated within %gh and unfinished)"
            % (", ".join(scopes), within))
    if why:
        for w in why:
            err("helm yard-on: %s %s" % ("would refuse:" if dry else "refused:", w))
        return 1
    if dry:
        say("helm yard-on --dry-run: both checks pass; nothing written")
        return 0
    for s, c in zip(scopes, cmds):
        r = subprocess.run(c, capture_output=True, text=True)
        if r.returncode != 0:
            err("helm yard-on: `%s` failed (rc=%d): %s\nhelm yard-on: stopped at %s; the scopes before it are written"
                % (" ".join(c), r.returncode, (r.stderr or r.stdout).strip(), s))
            return 3
        say(r.stdout.strip().splitlines()[0] if r.stdout.strip() else "  %s: scopes said nothing" % s)
    common = helmlib._common()
    if common.registry_unreadable():
        err("helm yard-on: the registry %s does not read back" % common.repos_json())
        return 3
    bad = [s for s in scopes if common.scope_yard(s) != host]
    for s in scopes:
        say("  read back: %s yard = %r" % (s, common.scope_yard(s)))
    if bad:
        err("helm yard-on: not %s after the write: %s" % (host, ", ".join(bad)))
        return 3
    say("helm yard-on: %d scope(s) read back as yard %s in %s — commit the registry" % (len(scopes), host, common.repos_json()))
    return 0
