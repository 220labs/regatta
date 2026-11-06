"""Local /finish prerequisites, shared by install --check and the queue's claim.

Read only: never load a schedule or repair a login. The caller caches one result
per queue pass, so every entry in that pass gets the same judgement.
"""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys


def has_finish(d):
    # A linked skill, or wharf installed as a plugin of this login (install's rule).
    if (d / "skills" / "finish" / "SKILL.md").is_file():
        return True
    try:
        rows = json.loads((d / "plugins" / "installed_plugins.json").read_text(encoding="utf-8")).get("plugins") or {}
    except (OSError, ValueError, AttributeError):
        return False
    return isinstance(rows, dict) and any(str(k).split("@")[0] == "wharf" for k in rows)


def enabled_login_dirs(common):
    """The account walk's enabled Claude dirs, plus an unregistered default dir.

    Use the core's account rows and home resolver so Orca's switches apply too.
    common.login_dirs() also serves transcript/fence readers, which need disabled dirs.
    """
    home = Path.home()
    registry = Path(os.environ.get("ACCOUNTS_FILE") or common.CONFIG / "lighthouse/accounts.json")
    try:
        rows = json.loads(registry.read_text(encoding="utf-8")).get("accounts") or []
    except FileNotFoundError:
        rows = []
    if not isinstance(rows, list):
        raise ValueError("accounts must be a list")
    known, enabled = set(), []
    for a in common.account_rows(rows, home):
        if a.get("provider", "claude") != "claude":
            continue
        d = common.account_home(a, home)
        if d:
            known.add(d)
            if a.get("enabled", True):
                enabled.append(d)
    default = home / ".claude"
    dirs = ([default] if default not in known or default in enabled else []) + enabled
    return [d for d in dict.fromkeys(dirs) if d.is_dir()]


def capability(common, launchctl=None, label=None, plist=None):
    """Report lines and a one-line refusal (None when all three prerequisites hold).

    The installer's explicit schedule paths also work here. Defaults match its
    --schedule: a non-Mac uses the configured prefix and systemd-launchctl.
    """
    here = Path(__file__).resolve().parent.parent
    darwin = os.environ.get("WHARF_RUNS_OS", "Darwin" if sys.platform == "darwin" else "Linux") == "Darwin"
    prefix = ""
    if not darwin:
        # install.sh drops all whitespace from the first nonblank prefix line.
        cfg = Path(os.environ.get("REGATTA_CONFIG", str(Path.home() / ".config/regatta")))
        try:
            prefix = next(("".join(x.split()) for x in (cfg / "wharf-runs/label-prefix").read_text().splitlines() if x.strip()), "")
        except OSError:
            pass
    label = label or os.environ.get("WHARF_RUNS_LABEL") or (prefix or "dev.regatta") + ".autofinish"
    launchctl = launchctl or os.environ.get("WHARF_RUNS_LAUNCHCTL") or ("launchctl" if darwin else str(here / "bin/systemd-launchctl"))
    plist = Path(plist) if plist else Path(os.environ.get("WHARF_RUNS_LAUNCH_DIR", str(Path.home() / "Library/LaunchAgents"))) / (label + ".plist")
    reasons = []
    try:
        loaded = subprocess.run([launchctl, "print", "gui/%s/%s" % (os.getuid(), label)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        loaded = False
    if loaded:
        schedule = "loaded (%s, every 10 min)" % label
    else:
        schedule = "plist written but not loaded (%s)" % plist if plist.is_file() else "off (sh %s/install.sh --schedule)" % here
        reasons.append("autofinish schedule not loaded (%s)" % label)

    hw = common.tool("helloworld")
    words_ok = False
    if not hw:
        words = "unknown (no helloworld module)"
    else:
        try:
            loader = importlib.machinery.SourceFileLoader("helloworld", str(hw))
            h = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
            loader.exec_module(h)
            wl = h.wordlist_path()
            try:
                h.wordlist()  # The gate's own read: missing, empty and malformed lists refuse.
                words, words_ok = str(wl), True
            except h.Refused as e:
                words = "%s (%s) — the publish gate refuses here, so a /finish of a repo with a public twin stops at its check" % (
                    "MISSING" if not wl.is_file() else "REFUSED", e if wl.is_file() else wl)
        except (Exception, SystemExit) as e:
            words = "unreadable (%s: %s)" % (type(e).__name__, e)
    if not words_ok:
        reasons.append("word list: " + words)

    have, lack = [], []
    try:
        for d in enabled_login_dirs(common):
            (have if has_finish(d) else lack).append(str(d))
        finish = "; ".join((["in " + ", ".join(have)] if have else []) +
                           (["MISSING in " + ", ".join(lack) + " — a landing on that login reads 'Unknown command: /finish'"] if lack else [])) or "no login dir here"
        if lack or not have:
            reasons.append("/finish missing in " + ", ".join(lack) if lack else "/finish: no login dir here")
    except (OSError, ValueError, AttributeError) as e:
        finish = "unreadable (%s)" % e
        reasons.append("/finish login dirs: " + finish)
    return {"schedule": schedule, "word list": words, "finish": finish,
            "reason": " ".join("; ".join(reasons).splitlines()) if reasons else None}
