"""surfaces.json — the seams of session-asks (docs/session-asks-2026-10-09.md section 2).

Shared by bin/ask and bin/helm, the way settings/models.json is read by bin/gate: which relay,
render, live and notify backend each seam takes, in order. Stdlib only, Python 3.9, nothing of
Claude's imported — the protocol is harness-neutral (R8). SURFACES_FILE points a test elsewhere.
"""
import json
import os
from pathlib import Path

# The file is the owner's (the overlay's settings/surfaces.json on the owner's Macs), linked into
# the regatta config dir as helm/surfaces.json (the design's C3); its shape is surfaces.schema.json
# beside this module's bin/, and a missing file or row reads as DEFAULTS.
CONFIG = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
FILE = Path(os.environ.get("SURFACES_FILE") or CONFIG / "helm" / "surfaces.json")
SCHEMA = Path(__file__).resolve().parent.parent / "surfaces.schema.json"

# What a missing file or row means: the design's defaults, so a fresh checkout behaves as documented.
# The `helm` seam was `plan` before rename S5 (helm-vocabulary H1): a file that still says `plan` is
# read as helm's row, `helm` winning key by key where both are set; a write goes under `helm`.
OLD_SEAMS = {"plan": "helm"}


def _laptop():
    """The host typing every cross-machine leg, as the core names it (REGATTA_LAPTOP, else the
    config dir's `regatta/laptop`, else `laptop`): read here without the core, which this file never
    loads (the deny hook imports it)."""
    if os.environ.get("REGATTA_LAPTOP"):
        return os.environ["REGATTA_LAPTOP"]
    try:
        lines = [l.strip() for l in (CONFIG / "regatta" / "laptop").read_text(encoding="utf-8-sig").splitlines()]
    except (OSError, UnicodeDecodeError):
        lines = []
    return next((l for l in lines if l), "laptop")


DEFAULTS = {
    "ask": {"relay": ["talk", "sendmessage", "file"], "listen": "talk", "parked": True},
    "helm": {"render": ["local", "sheep", "artifact"], "live": "stream", "live_fallback": "redeploy",
             "state": "state.json"},
    "notify": {_laptop(): ["banner"], "cloud": []},
}
KNOWN = {
    "ask.relay": {"talk", "sendmessage", "file"},
    "ask.listen": {"talk", "sendmessage", "none"},
    "helm.render": {"local", "sheep", "artifact"},
    "helm.live": {"stream", "redeploy", "records", "local-sse"},
    "helm.live_fallback": {"redeploy", "none"},
    "notify.*": {"banner", "telegram"},
}


def load(path=None):
    p = Path(path) if path else FILE
    try:
        data = json.loads(p.read_text())
    except (OSError, ValueError):
        data = {}
    out = {}
    for seam, rows in DEFAULTS.items():
        merged = dict(rows)
        for old, new in OLD_SEAMS.items():
            if new == seam:
                merged.update({k: v for k, v in (data.get(old) or {}).items()})
        merged.update({k: v for k, v in (data.get(seam) or {}).items()})
        out[seam] = merged
    return out


def row(name, path=None):
    """`ask.relay` → its value (`plan.state` reads `helm.state`)."""
    seam, key = name.split(".", 1)
    return load(path).get(OLD_SEAMS.get(seam, seam), {}).get(key)


def host():
    """laptop | buildbox | cloud | <other>: the notify row's key. A cloud VM has no LocalHostName."""
    if os.environ.get("SURFACES_HOST"):
        return os.environ["SURFACES_HOST"]
    if os.environ.get("CLAUDE_CODE_REMOTE") or not Path("/usr/sbin/scutil").exists():
        return "cloud"
    import subprocess
    try:
        r = subprocess.run(["/usr/sbin/scutil", "--get", "LocalHostName"], capture_output=True, text=True, timeout=5)
        return (r.stdout.strip() or "unknown").lower()
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"


def validate(data):
    """Problems with a surfaces dict, as lines; empty when it is fine."""
    bad = []
    for name, ok in KNOWN.items():
        seam, key = name.split(".", 1)
        rows = dict(data.get(seam) or {})
        for old, new in OLD_SEAMS.items():
            if new == seam:
                rows = dict(data.get(old) or {}, **rows)
        keys = rows.keys() if key == "*" else [key]
        for k in keys:
            v = rows.get(k)
            vals = v if isinstance(v, list) else [v]
            for x in vals:
                if x not in ok:
                    bad.append("%s.%s: unknown backend %r (known: %s)" % (seam, k, x, ", ".join(sorted(ok))))
    if not isinstance(data.get("ask", {}).get("parked"), bool):
        bad.append("ask.parked: true or false")
    return bad


def set_row(assign, path=None):
    """`relay=file` or `ask.relay=talk,file` or `helm.live=redeploy`: writes the file, returns the new value.
    A bare key is looked up in ask, then helm, then notify; `plan.<key>` is written as `helm.<key>`."""
    p = Path(path) if path else FILE
    key, _, val = assign.partition("=")
    if not val:
        raise ValueError("--set wants key=value")
    try:
        data = json.loads(p.read_text())
    except (OSError, ValueError):
        data = {}
    if "." in key:
        seam, k = key.split(".", 1)
        seam = OLD_SEAMS.get(seam, seam)
    else:
        seam = next((s for s in ("ask", "helm", "notify") if key in DEFAULTS[s]), None)
        k = key
        if not seam:
            raise ValueError("no row named %s" % key)
    cur = load(p)[seam].get(k)
    if isinstance(cur, list):
        new = [x for x in val.split(",") if x]
    elif isinstance(cur, bool):
        new = val.lower() in ("1", "true", "yes", "on")
    else:
        new = val
    data.setdefault(seam, {})[k] = new
    probe = load(p)
    probe[seam][k] = new
    bad = validate(probe)
    if bad:
        raise ValueError("; ".join(bad))
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    return new


def describe(path=None):
    data = load(path)
    lines = []
    for seam in ("ask", "helm", "notify"):
        for k, v in data[seam].items():
            lines.append("%-20s %s" % ("%s.%s" % (seam, k), ", ".join(v) if isinstance(v, list) else json.dumps(v)))
    return "\n".join(lines)
