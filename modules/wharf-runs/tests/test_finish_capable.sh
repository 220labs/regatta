#!/usr/bin/env bash
# Local readiness only: scratch HOME/config, real word-list reader and login walk,
# an argument-checking scheduler stand-in; no queue writes, jobs or network.
set -eu
M="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/config"
env -i PATH="$PATH" TMPDIR="$T" HOME="$T/home" REGATTA_CONFIG="$T/config" PYTHONDONTWRITEBYTECODE=1 \
  python3 -B - "$M" "$T" <<'PY'
import contextlib
import importlib.machinery
import io
import json
import os
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

module, tmp = map(Path, sys.argv[1:])
cfg, home = tmp / "config", tmp / "home"
(cfg / "wharf-runs").mkdir()
(cfg / "home").write_text(str(module.parent.parent) + "\n")
(cfg / "wharf-runs/label-prefix").write_text("\n  org.example.claude\r\n")
os.environ.update(WHARF_RUNS_OS="Linux", HELLOWORLD_WORDLIST=str(tmp / "words"),
                  ACCOUNTS_FILE=str(tmp / "accounts.json"), DISPATCH_HOST="laptop")
words = tmp / "words"
words.write_text("fixtureword\n")
primary, secondary = home / ".claude", home / ".claude-acct-a"
for d in (primary, secondary):
    (d / "skills/finish").mkdir(parents=True)
    (d / "skills/finish/SKILL.md").touch()
(tmp / "accounts.json").write_text(json.dumps({"accounts": [{"label": "acct-a", "home": str(secondary)}]}))
scheduler = tmp / "launchctl"
scheduler.write_text('''#!/bin/sh
[ "$#" = 2 ] && [ "$1" = print ] && [ "$2" = "gui/$(id -u)/${EXPECT_LABEL:-org.example.claude.autofinish}" ] || {
  echo bad-arguments >> "$PROBE_DIR/bad-arguments"; exit 64;
}
echo print >> "$PROBE_DIR/probes"
[ ! -f "$PROBE_DIR/schedule-off" ]
''')
scheduler.chmod(0o755)
os.environ["WHARF_RUNS_LAUNCHCTL"] = str(scheduler)
os.environ["PROBE_DIR"] = str(home)
m = importlib.machinery.SourceFileLoader("dq", str(module / "bin/dispatch-queue")).load_module()
af = importlib.machinery.SourceFileLoader("af", str(module / "bin/autofinish-run")).load_module()
real_load_bin = af.load_bin
af.load_bin = lambda name: m if name == "dispatch-queue" else real_load_bin(name)
af.self_host = lambda: "laptop"
native_platform = sys.platform
m.sys.platform = "linux"
m._HOST = "laptop"
m.berth_candidates = lambda repo, host: (["laptop", "buildbox"], {})
repo = tmp / "repo"
(repo / ".git").mkdir(parents=True)
entry = {"repo": str(repo), "branch": "claude/laptop/2026-11-04-ready", "kind": "finish",
         "state": "queued", "priority": "normal", "needs": ["finish-queue"], "tip": "a" * 40,
         "finish": {"by": "sweep", "rule": "A"}}
store = SimpleNamespace(name="fixture", view=lambda: ({"entry": entry}, False))
m.rows = lambda *args: ([(store, "entry", entry)], [])
m.after_said = lambda: {}
m.stores = lambda: [store]
m.records = lambda: []
m.claims_here = lambda: True
m.dark_wake = lambda: False

def check(value, message):
    assert value, message
    print("  ok   " + message)

def refused(piece):
    m.finish_readiness.cache_clear()
    why = m.claimable(entry, "laptop")
    check(why and piece in why and "\n" not in why, "claim refuses: " + piece)
    check(not af.finish_runs_here(), "launcher agrees the host cannot claim: " + piece)
    listing, claim = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(listing):
        m.cmd_list(SimpleNamespace(all=True, status=False, json=False), None)
    check("not here: " + why in listing.getvalue(), "queue row names: " + piece)
    with contextlib.redirect_stderr(claim):
        check(m._claim(SimpleNamespace()) == [], "no claim starts")
    check("not claimed fixture:entry: " + why in claim.getvalue(), "claim says: " + piece)
    report = m.finish_readiness()
    out = subprocess.run(["sh", str(module / "install.sh"), "--check"], text=True, capture_output=True)
    for key in ("schedule", "word list", "finish"):
        check(("%-12s %s" % (key + ":", report[key])) in out.stdout, "installer agrees on " + key)

check(m.builtin_met("finish-queue", "laptop"), "capable Linux host meets finish-queue without a feature line")
check(m.claimable(entry, "laptop") is None, "capable Linux finish passes claim filters")
check(af.finish_runs_here(), "launcher recognizes capable Linux host without a feature line")
check(not m.builtin_met("other", "laptop"), "no other need gains a built-in grant")
for _ in range(20):
    m.eligibility(entry, "laptop")
check((home / "probes").read_text().splitlines() == ["print"], "many entries use one readiness probe")
(home / "schedule-off").touch()
check(m.builtin_met("finish-queue", "laptop"), "the current pass retains its snapshot")
# The sweep wrapper refreshes even when the module is reused; its inner claim shares that snapshot.
m._sweep = lambda a, ctx: [m.builtin_met("finish-queue", "laptop") for _ in range(3)]
m.words_tend = lambda: None
check(m.cmd_sweep(None, None) == [False] * 3, "next sweep refreshes readiness once")
check(len((home / "probes").read_text().splitlines()) == 2, "one probe for the whole next sweep")
refused("autofinish schedule not loaded")
(home / "schedule-off").unlink()
words.unlink()
refused("word list: MISSING")
words.write_text("")
refused("word list: REFUSED")
words.write_text("bad#comment\n")
refused("word list: REFUSED")
words.write_text("fixtureword\n")
accounts = tmp / "accounts.json"
registry = json.loads(accounts.read_text())
disabled = home / ".claude-acct-off"
disabled.mkdir()
registry["accounts"].append({"label": "acct-off", "home": str(disabled), "enabled": False})
accounts.write_text(json.dumps(registry))
m.finish_readiness.cache_clear()
check(m.builtin_met("finish-queue", "laptop"), "a disabled registry login without finish never blocks readiness")
check(disabled in m.common.login_dirs(), "disabled dirs remain visible to transcript and fence discovery")
registry["accounts"][-1]["enabled"] = True
accounts.write_text(json.dumps(registry))
refused("/finish missing in " + str(disabled))
registry["accounts"][-1]["enabled"] = False
# An explicitly disabled default login is not a possible pick either.
registry["accounts"].append({"label": "acct-main", "home": str(primary), "enabled": False})
accounts.write_text(json.dumps(registry))
(primary / "skills/finish/SKILL.md").unlink()
m.finish_readiness.cache_clear()
check(m.builtin_met("finish-queue", "laptop"), "an explicitly disabled default login is skipped too")
registry["accounts"].append({"label": "acct-main-alias", "home": str(primary)})
accounts.write_text(json.dumps(registry))
refused("/finish missing in " + str(primary))
(primary / "skills/finish/SKILL.md").touch()
registry["accounts"] = registry["accounts"][:1]
accounts.write_text(json.dumps(registry))
orca_dir = home / ".claude-acct-orca"
orca_dir.mkdir()
orca_file = primary / "account-orca.json"
orca_file.write_text(json.dumps({"acct-orca": {"home": str(orca_dir), "enabled": False}}))
m.finish_readiness.cache_clear()
check(m.builtin_met("finish-queue", "laptop"), "a disabled implicit Orca login without finish never blocks readiness")
orca_file.write_text(json.dumps({"acct-orca": {"home": str(orca_dir)}}))
refused("/finish missing in " + str(orca_dir))
registry["accounts"].append({"label": "acct-orca", "via": "orca"})
accounts.write_text(json.dumps(registry))
orca_file.write_text(json.dumps({"acct-orca": {"home": str(orca_dir), "enabled": False}}))
m.finish_readiness.cache_clear()
check(m.builtin_met("finish-queue", "laptop"), "Orca's disabled switch excludes an explicit registry row too")
orca_file.unlink()
registry["accounts"] = registry["accounts"][:1]
accounts.write_text("{")
refused("/finish login dirs: unreadable")
accounts.write_text(json.dumps(registry))
(secondary / "skills/finish/SKILL.md").unlink()
refused("/finish missing in " + str(secondary))
# A wharf plugin is install --check's other supported form.
(secondary / "plugins").mkdir()
(secondary / "plugins/installed_plugins.json").write_text('{"plugins":{"wharf@regatta":[{"scope":"user"}]}}')
m.finish_readiness.cache_clear()
check(m.builtin_met("finish-queue", "laptop"), "a secondary login with the wharf plugin is ready")
(secondary / "plugins/installed_plugins.json").write_text('{"plugins":["wharf@regatta"]}')
refused("/finish missing in " + str(secondary))
primary.rename(tmp / "primary-away")
secondary.rename(tmp / "secondary-away")
m.finish_readiness.cache_clear()
check("no login dir" in m.finish_readiness()["reason"], "no login dirs is not vacuous readiness")
(tmp / "primary-away").rename(primary)
(tmp / "secondary-away").rename(secondary)
check(m.builtin_met("finish-queue", "buildbox"), "remote readiness is left to that host")
m.sys.platform = "darwin"
check(m.builtin_met("finish-queue", "laptop"), "Darwin retains its grant with missing prerequisites")
check(af.finish_runs_here(), "launcher recognizes Darwin with missing prerequisites")
features = cfg / "wharf-runs/features"
features.write_text("laptop:-finish-queue\n")
check("disabled" in m.claimable(entry, "laptop"), "negation overrides Darwin too")
check(not af.finish_runs_here(), "launcher honors Darwin negation before choosing a ladder pin")
# The sampler consumes the real CLI, then the queue validates its resulting row.
hosts = importlib.machinery.SourceFileLoader("hosts", str(module.parent / "lighthouse/bin/hosts")).load_module()
features.write_text("laptop:feat-a,finish-queue,-finish-queue\n")
advertised = hosts.host_features("laptop", {})
check(advertised == ["feat-a"], "sampler advertises grants only, with disabled finish removed")
row = dict.fromkeys(m.ROW_REQUIRED)
row.update(host="laptop", at=1, runs=[], features=advertised)
check(m.row_refusal(row, "laptop") is None, "a disabled finish still permits host-row updates")
features.write_bytes(b"laptop:-finish-queue\n\xff\n")
why = m.claimable(entry, "laptop")
check(why and "wharf-runs/features" in why and "unreadable" in why,
      "invalid UTF-8 never bypasses a Darwin finish disable")
check(not af.finish_runs_here(), "launcher also refuses unreadable feature config")
check(m.eligibility(dict(entry, needs=[]), "laptop") is None, "unreadable features do not change a build with no needs")
check(hosts.host_features("laptop", {}) is None, "sampler marks unreadable features unknown")
features.unlink()
features.mkdir()
check("unreadable" in m.claimable(entry, "laptop"), "an unreadable feature path holds finishes too")
features.rmdir()
features.symlink_to(cfg / "wharf-runs/missing-features")
check("unreadable" in m.claimable(entry, "laptop"), "a dangling feature link holds finishes too")
features.unlink()
features.write_text("laptop:-finish-queue\n")
# Exercise the real handed enqueue up to its dry output: no git, queue write or job.
tree = SimpleNamespace(warm_ended=True, path=str(repo), primary=str(repo), tip=entry["tip"],
                       branch=entry["branch"], ladder=(None, None, False, None))
args = SimpleNamespace(on=None, by="handed", rule="C", dry=True, merge=False, digest=None,
                       hold=False, priority=None, session=None)
af.read_origin = lambda t: t.tip
output = io.StringIO()
with contextlib.redirect_stdout(output):
    result = af.enqueue(tree, args, "handed", "")
check(result == 0 and "--prefer laptop" in output.getvalue() and "--pin laptop" not in output.getvalue(),
      "disabled Darwin handed finish goes to peers without an unclaimable pin")
check(m.eligibility(entry, "buildbox") is None, "a peer can claim the unpinned finish")
args.on = "here"
output = io.StringIO()
with contextlib.redirect_stdout(output):
    result = af.enqueue(tree, args, "handed", "")
check(result == 0 and "--pin laptop" in output.getvalue(), "explicit --on here stays pinned on a disabled host")
args.on = None
m.sys.platform = "linux"
features.write_text("laptop:finish-queue\n")
check(m.claimable(entry, "laptop") is None, "explicit grant works with missing prerequisites")
check(af.finish_runs_here(), "launcher honors explicit grant with missing prerequisites")
(secondary / "skills/finish/SKILL.md").touch()
m.finish_readiness.cache_clear()
check(m.builtin_met("finish-queue", "laptop"), "Linux host restored to capable")
features.write_text("laptop:finish-queue,\n-finish-queue\n")
check("disabled" in m.claimable(entry, "laptop"), "split-line negation overrides capable host and explicit grant")
check(not af.finish_runs_here(), "launcher honors split-line negation over both grants")
features.write_bytes(b"laptop:-finish-queue\n\xff\n")
check("unreadable" in m.claimable(entry, "laptop"), "invalid UTF-8 holds a capable Linux host too")
features.write_text("laptop:-other\n")
check("-other" not in m.features()["laptop"], "no negation syntax added for other needs")
features.unlink()
output = io.StringIO()
with contextlib.redirect_stdout(output):
    result = af.enqueue(tree, args, "handed", "")
check(result == 0 and "--pin laptop" in output.getvalue(), "capable Linux handed finish stays pinned without a feature line")
os.environ.update(WHARF_RUNS_LABEL="org.example.custom", EXPECT_LABEL="org.example.custom")
m.finish_readiness.cache_clear()
check(m.builtin_met("finish-queue", "laptop"), "schedule label override uses the real print argument shape")
check(not (home / "bad-arguments").exists(), "every scheduler call validates verb, arity, uid and label")
m.sys.platform = native_platform
print("all finish capability tests passed")
PY
