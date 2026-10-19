"""Where the regatta core's hooks/ folder is, for this module's scripts, before `import common`.

In order: the checkout this file sits in (modules/regatta beside this module; through a
source shim `__file__` is the module file's own path, so this holds there too), else
$REGATTA_HOME, else the config dir's `home` file, else the core's installPath as Claude Code
recorded it in installed_plugins.json — read back, never predicted (the design's C2). None found:
one line and exit 2, never a fallback copy of the core. Stdlib, Python 3.9.
"""
import json
import os
import sys
from pathlib import Path


def candidates():
    out = [Path(__file__).resolve().parents[2] / "regatta" / "hooks"]
    cfg = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
    try:
        home = (cfg / "home").read_text(encoding="utf-8").split("\n")[0].strip()
    except (OSError, UnicodeDecodeError):
        home = ""
    out += [Path(h).expanduser() / "modules" / "regatta" / "hooks" for h in (os.environ.get("REGATTA_HOME"), home) if h]
    reg = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude").expanduser() / "plugins" / "installed_plugins.json"
    try:
        rows = json.loads(reg.read_text(encoding="utf-8")).get("plugins", {}).get("regatta@regatta") or []
        out += [Path(r["installPath"]) / "hooks" for r in rows if isinstance(r, dict) and r.get("installPath")]
    except (OSError, ValueError, AttributeError, TypeError):
        pass
    return out


def hooks():
    for c in candidates():
        if (c / "common.py").is_file():
            return str(c)
    print(f"{Path(sys.argv[0]).name}: the regatta core is missing — install the `regatta` plugin, or name a "
          "clone in the regatta config dir's `home` file (its install.sh writes it)", file=sys.stderr)
    sys.exit(2)
