"""Message-only host discovery for hail and helm; no placement reader imports this file.

The fleet ref avoids a second host list to maintain. Read only its local cache: the sampler's
`hosts put` refreshes it, and a Stop hook or an explicit hail must never fetch under its lock.
Importing this module reads no config and starts no process; callers supply the core.
"""
import json
import math
import re
import subprocess
import sys
import time

# Fleet rows are common.host_name() output, not arbitrary DNS names or ssh options.
HOST_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,62}")
MAX_AGE_S = 24 * 3600   # hail's MAIL_SEEN_H: a retired host stops being an automatic peer
SKEW_S = 300            # a sampler's clock this far ahead of the reader's still reads fresh
_ROWS = {}


def configured(core):
    """Aliases in precedence order: placement's explicit aliases, kick aliases, named nodes."""
    return configured_from(core)[0]


def configured_from(core):
    """(aliases, folder names): configured()'s aliases, and the names a node folder here gives, which the
    core's nodes_here judges; a kick alias alone is judged only by its fleet row."""
    out, folders = {}, set()
    for key in ("wharf-runs/ssh", "wharf-runs/kick-ssh"):
        for host, alias in pairs(core.config_lines(key) or []):
            out.setdefault(host, alias)
    role = getattr(core, "NODE_ROLE", "agent")
    for path in sorted((core.CONFIG / "wharf-runs" / "nodes").glob("*/ssh")):
        name = path.parent.name
        if name.startswith("."):   # the core's nodes_here skips these: the fence and this reader walk one set
            continue
        host = core.config_line("wharf-runs/nodes/%s/name" % name) or name
        alias = core.config_line("wharf-runs/nodes/%s/ssh" % name)
        if alias:
            peer = "%s-%s" % (host.lower(), role)
            out.setdefault(peer, alias)
            folders.add(peer)
    return out, folders


def pairs(lines):
    """[(host, alias)] by kicklib's `_pairs` rule (inlined: kicklib loads the core at import): a note
    after `#` or `(` is cut, and a bare `host:` takes the next line as its alias (a value the overlay
    wrote one word per line). The alias is its first word: an ssh destination is one word."""
    out, pending = [], None
    for raw in lines:
        ln = re.split(r"[#(]", str(raw), maxsplit=1)[0].strip()
        if not ln:
            continue
        if pending is not None and ":" not in ln:
            out.append((pending, ln.split()[0]))
            pending = None
            continue
        host, sep, alias = ln.partition(":")
        host, alias = host.strip().lower(), (alias.strip().split() or [""])[0]
        if sep and host and alias:
            out.append((host, alias))
        pending = host if sep and host and not alias else None
    return out


def rows(core):
    """The fleet ref's rows by host, {} where no queue is set, None where the ref did not read (no
    dispatch-queue, its timeout, a non-zero exit, output that is no rows): then no row vouches for a name."""
    home = core.config_line("wharf-runs/queue-repo")
    if not home or home.lower() == "off":
        return {}
    if home not in _ROWS:
        got = None
        try:
            queue = core.tool("dispatch-queue")
            if queue:
                res = subprocess.run([sys.executable, str(queue), "hosts", "get", "--cached"],
                                     capture_output=True, text=True, timeout=5)
                got = json.loads(res.stdout) if res.returncode == 0 else None
        except (OSError, ValueError, subprocess.TimeoutExpired):
            pass
        got = got.get("rows") if isinstance(got, dict) else None
        _ROWS[home] = got if isinstance(got, dict) else None
    return _ROWS[home]


def fresh_at(at, now):
    """A sample within MAX_AGE_S, or up to SKEW_S ahead: the stamp is the sampler's own clock."""
    try:   # a bad row costs its own host alone: an int too large for a float raises
        return (not isinstance(at, bool) and isinstance(at, (int, float)) and math.isfinite(float(at))
                and -SKEW_S <= now - at <= MAX_AGE_S)
    except (OverflowError, ValueError):
        return False


def message_peers(core, here, aliases=None, target=None):
    """Automatic peers are main's configured placement aliases (BASE), unfiltered, plus the names this
    reader adds (kick aliases, node folders, fleet rows), less every confidential scope's yard and own
    node and every host whose fleet row is torn or marked with no open scope's marker, fresh or not. A
    kick alias alone is added only while a fresh, unmarked row vouches for it; a node folder is the
    core's to judge. Only an explicit hail target may reach a blocked name. A registry, a yard or a node
    folder that does not read drops every added name: BASE alone, what main reached. Aliases win before
    any discovery, including on an explicit target's fast path."""
    base = dict(aliases or {})
    base.pop(here, None)
    if not core:
        return base
    known, folders = configured_from(core)
    known.update(base)
    known.pop(here, None)
    if target and target in known:
        return {target: known[target]}
    now = time.time()
    got = rows(core)
    fleet = {}
    for host, row in (got or {}).items():
        # a builder user's row (lighthouse's sampler marks it) names no ssh host: reached by a configured alias only
        if (isinstance(host, str) and HOST_RE.fullmatch(host) and isinstance(row, dict)
                and fresh_at(row.get("at"), now) and (row.get("builder") is not True or host in known)):
            fleet[host] = known.get(host, host)
    if target:   # the owner's explicit exception: a fresh row is a road, whatever it is marked
        return {target: fleet[target]} if target in fleet else {}
    reg, unreadable = core.read_registry()   # one snapshot for every scope, never first-match
    if unreadable or reg is None:
        return base
    blocked = blocked_hosts(core, reg)
    if blocked is None:
        return base
    open_marks = open_scope_marks(core, reg)
    for host, row in (got or {}).items():
        if not isinstance(host, str):
            continue
        # A torn row, or a scope node's row whose marker (lighthouse's sampler) is no open scope here,
        # confidential or unknown, blocks its host whatever it is named and however old the row is. A marker
        # that is no string (a list, an object: unhashable) blocks its own host alone, never the walk.
        mark = row.get("scope") if isinstance(row, dict) else None
        if not isinstance(row, dict) or ("scope" in row and (open_marks is None or not isinstance(mark, str)
                                                            or mark not in open_marks)):
            blocked = blocked | {host.lower()}
    for host, alias in known.items():
        if host in base or host in folders or host in fleet:
            fleet[host] = alias
    fleet.pop(here, None)
    # main reached every configured placement alias, a Mac yard included: never narrow BASE
    return {host: alias for host, alias in fleet.items() if host in base or host not in blocked}


def open_scope_marks(core, reg):
    """The scope markers (the core's scope_marker) of this registry's open scopes, or None when the core
    cannot make them: every marked row then reads as no open scope's."""
    mark = getattr(core, "scope_marker", None)
    if not callable(mark):
        return None
    scopes = (reg.get("scopes") if isinstance(reg, dict) else None) or {}
    try:
        return {mark(n) for n, sc in scopes.items()
                if isinstance(n, str) and isinstance(sc, dict) and sc.get("confidential", False) is False}
    except Exception:
        return None


def blocked_hosts(core, reg):
    """Every confidential scope's yard and own node (the core's nodes_here, and `<scope>-agent` where no
    folder here tells it), lower-cased, or None when one will not read: a yard that is not a string, a
    node folder the core cannot tell or holds (a scope and no ssh), a core too old to tell nodes. A narrowing that does not read narrows to nothing added, never to nothing blocked."""
    out = set()
    for sc in ((reg.get("scopes") if isinstance(reg, dict) else None) or {}).values():
        if not isinstance(sc, dict) or "confidential" not in sc or sc.get("confidential") is False:
            continue
        if sc.get("confidential") is not True:   # a flag that is no bool narrows to nothing added
            return None
        yard = sc.get("yard")
        if isinstance(yard, str) and yard:
            out.add(yard.lower())
        elif yard is not None and yard != "":
            return None
    tell = getattr(core, "nodes_here", None)
    if not callable(tell):
        return None
    try:
        told, why, held = tell(reg)
    except Exception:
        return None
    # A held folder names a confidential scope but no ssh: told as no scope's, never as open.
    if why or held or not isinstance(told, dict):
        return None
    out |= {peer.lower() for peer, scope in told.items() if scope}
    # A node folder whose `scope` names no open scope here (one this registry lacks, not yet synced) is no shared
    # node: the core tells it as None, which would read as open. Its own folder says it is a scope's node.
    opened = {n for n, sc in ((reg.get("scopes") if isinstance(reg, dict) else None) or {}).items()
              if isinstance(n, str) and isinstance(sc, dict) and sc.get("confidential", False) is False}
    try:
        for path in sorted((core.CONFIG / "wharf-runs" / "nodes").glob("*/ssh")):
            name = path.parent.name
            if name.startswith("."):
                continue
            scope = (core.config_line("wharf-runs/nodes/%s/scope" % name) or "").strip()
            if scope and scope not in opened:
                host = core.config_line("wharf-runs/nodes/%s/name" % name) or name
                out.add(("%s-%s" % (host, getattr(core, "NODE_ROLE", "agent"))).lower())
    except Exception:
        return None
    # A scope's node with no folder on this host is still `<scope>-agent` (the core's naming rule).
    role = getattr(core, "NODE_ROLE", "agent")
    out |= {("%s-%s" % (name, role)).lower() for name, sc in ((reg.get("scopes") or {}).items())
            if isinstance(name, str) and isinstance(sc, dict) and sc.get("confidential")}
    return out
