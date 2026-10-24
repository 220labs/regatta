"""The two knowledge repos as wharf's hooks and tools read them: atlas's `atlas/layer` (what every
session loads: rules, lessons, skills) and `atlas/vault` (the records written in place on main).
Each is one value file in the regatta config dir, as atlas's README describes it: the name callers
pass to knowledge-commit on its first line, the primary checkout's path on its second (a leading
`~` is the home folder), and optionally on a third the name of an environment variable that
overrides that path for a test suite or one shell. `ATLAS_LAYER` / `ATLAS_VAULT` override it
always, as in atlas's own lib. On the owner's Macs the overlay's `bootstrap.sh --config` writes
both.

A missing key is no knowledge repo, never a guessed folder: checkpoint then judges that checkout
like any other repo, sync.py fast-forwards only the session's own, and `missing()` names what an
overlay was meant to write so the caller can say so in one line. Stdlib only, no core: sync.py
reads this at import, before it knows whether the core loads (C4).
"""
import os
from pathlib import Path

ROLES = ("layer", "vault")
ENV = {"layer": "ATLAS_LAYER", "vault": "ATLAS_VAULT"}


def _config():
    return Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()


def _lines(role):
    try:
        text = (_config() / "atlas" / role).read_text(encoding="utf-8-sig")
    except (OSError, UnicodeDecodeError):
        return []
    return [l.strip() for l in text.splitlines() if l.strip()]


def repo(role):
    """(name, path) of the layer or the vault, or (None, None) when its key is absent or empty."""
    lines = _lines(role)
    if not lines:
        return None, None
    name = lines[0]
    raw = os.environ.get(ENV[role]) or (len(lines) > 2 and os.environ.get(lines[2])) or (lines[1] if len(lines) > 1 else "")
    return name, (Path(raw).expanduser() if raw else None)


def names():
    """The knowledge repos' names, layer first: the folder names knowledge-commit takes."""
    return tuple(n for n, _ in (repo(r) for r in ROLES) if n)


def paths():
    """The knowledge repos' primary checkouts, layer first; a role without a path is left out."""
    return [p for _, p in (repo(r) for r in ROLES) if p]


def missing():
    """The `atlas/<role>` keys an overlay should have written and did not (its `regatta/overlay`
    marker in the config dir says one is installed); empty without an overlay, where no key is owed."""
    if not (_config() / "regatta" / "overlay").is_file():   # the overlay's marker (the only one since B14b)
        return []
    return [f"atlas/{r}" for r in ROLES if not _lines(r)]
