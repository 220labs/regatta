"""Where atlas's two knowledge repos are, and the core when a script needs it. Stdlib, Python 3.9.

The **vault** holds the records written in place: the bulletin, auto-memory, inbox notes, dreams,
`log.md`. The **layer** holds what every session loads: rules, lessons, skills. Each is one value
file in the regatta config dir, `atlas/vault` and `atlas/layer`: the name callers pass to
`knowledge-commit` on its first line, the primary checkout's path on its second (a leading `~` is
the home folder), and optionally on a third the name of an environment variable that overrides
that path, for a test suite or one shell — an installer whose scripts already use one keeps it.
`ATLAS_VAULT` and `ATLAS_LAYER` override them always. An installer writes the files (on the
owner's Macs, the overlay's `bootstrap.sh --config`).

Where the overlay is installed (a `legacy` file in the config dir) a missing key is None, never a
guess: a bulletin posted to a default folder while the real one sits elsewhere would be lost
without a word. Without the overlay (a stranger's install) the vault defaults to `atlas` in the XDG
data folder, a plain folder the bulletin can use; the layer has no default.

The config dir is read here directly, not through the core: the bulletin runs at every session
start and must not cost one over a core that cannot load. `core()` is for the optional edges
(G19, G20): the core's `common`, or None.
"""
import os
import sys
from pathlib import Path

CONFIG = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
ENV = {"vault": "ATLAS_VAULT", "layer": "ATLAS_LAYER"}
LIB = Path(__file__).resolve().parent


def _lines(role):
    try:
        return [l.strip() for l in (CONFIG / "atlas" / role).read_text(encoding="utf-8-sig").splitlines() if l.strip()]
    except (OSError, UnicodeDecodeError):
        return []


def key(role):
    """(name, path) from `<config>/atlas/<role>`, or None when it is absent, unreadable or short."""
    lines = _lines(role)
    if len(lines) < 2 or not os.path.isabs(os.path.expanduser(lines[1])):
        return None
    return lines[0], Path(lines[1]).expanduser()


def env_name(role):
    """The installer's own override variable for the role (the key's third line), else ATLAS_<ROLE>."""
    lines = _lines(role)
    return lines[2] if len(lines) > 2 and lines[2].isidentifier() else ENV[role]


def overlay():   # the core's overlay_installed(): B14a's marker, or legacy until B14b drops it
    return (CONFIG / "regatta" / "overlay").exists() or (CONFIG / "legacy").exists()


def repo(role):
    """The role's checkout: its environment override, else the config key, else (no overlay) the
    vault's default; None when the overlay is installed and did not write the key."""
    env = os.environ.get(ENV[role]) or os.environ.get(env_name(role))
    if env:
        return Path(env).expanduser()
    k = key(role)
    if k:
        return k[1]
    if role == "vault" and not overlay():
        return Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share").expanduser() / "atlas"
    return None


def missing(role):
    """The one line said when repo(role) is None."""
    return ("atlas: no %s configured — %s holds no name and path (your overlay's bootstrap.sh --config, "
            "or %s for this shell)" % (role, CONFIG / "atlas" / role, env_name(role)))


def core():
    """The regatta core's `common` module, or None. Never raises and never exits: every caller
    here is an optional edge, and a hook must not lose its session over one."""
    try:
        if "common" in sys.modules:
            return sys.modules["common"]
        if str(LIB) not in sys.path:
            sys.path.insert(0, str(LIB))
        import find_core
        for c in find_core.candidates():
            if (c / "common.py").is_file():
                sys.path.insert(0, str(c))
                import common
                return common
    except BaseException:
        return None
    return None


def tool(name):
    """A peer's path through the core's one lookup (`common.tool`), or None: the core or the peer
    missing reads the same to a caller, which names its own fallback."""
    c = core()
    try:
        return c.tool(name) if c else None
    except Exception:
        return None
