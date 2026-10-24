#!/usr/bin/env bash
# The list's own cases, apart from the core's suite so they sit on autofinish_exclude (the autofinish-exclude
# landing review, finding 20: a case in a file off the list can be weakened by a sweep's landing):
# coverage (every live path is on autofinish_exclude), class 1 (every file a judge loads is on it) and
# class 2 (every file a leak gate loads is on autofinish_leaks). Reads the tree, git log and the caller's
# config dir's `regatta/overlay` marker; writes nothing. check.sh runs it.
#   bash modules/regatta/tests/classes.sh
set -u
M="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$M/../.." && pwd)"
fails=0
check() { if [ "$1" = "$2" ]; then echo "  ok   $3"; else echo "  FAIL $3: expected [$2] got [$1]"; fails=$((fails+1)); fi; }

# `.claude/workflow.json`'s `autofinish_exclude` is hand-kept: a path a live hook or an overlay shim runs from
# this checkout, missing from it, lands through autofinish unreviewed (the B4-fixes review, 2026-10-20: the core's
# `hooks/` since B1, plumb's and atlas's hooks and `lib/` since B8 and B10). Live = every file under
# `modules/*/hooks|lib|shell` (class 3 at least; a `libexec/` file is a job's unless a judge loads it, which
# the class-1 case below catches: sextant's `sextant-run` left the list at autofinish-exclude S2);
# a shim the overlay made with a flag (`--hook`, `--deny`: wired into the hooks);
# a `bin/<name>` the AGENTS.md autofinish paragraph names. A plain shimmed tool is not live by itself (the
# paragraph's rule: those that gate or write live state are named in it), so it is counted, not failed.
# The overlay is the `regatta/overlay` marker of the caller's config dir (check.sh passes the caller's, not its scratch ones);
# absent (CI, whose job sets its own REGATTA_CONFIG, and the public twin): the shim half is skipped.
echo "autofinish_exclude covers every live path"
out=$(python3 -I - "$ROOT" "${REGATTA_CONFIG:-}" "$HOME" <<'PY'
import json, os, re, sys
root = sys.argv[1]
wf = os.path.join(root, ".claude", "workflow.json")
if not os.path.isfile(wf):
    print("SKIP no .claude/workflow.json in this tree (the public twin has none)")
    print("RESULT none")
    sys.exit(0)
exclude = tuple(json.load(open(wf)).get("autofinish_exclude") or ())
live = {}
def rel(path): return os.path.relpath(path, root)
for d in sorted(os.listdir(os.path.join(root, "modules"))):
    for sub in ("hooks", "lib", "shell"):
        top = os.path.join(root, "modules", d, sub)
        for dp, _, ns in os.walk(top):
            for n in ns:
                live.setdefault(rel(os.path.join(dp, n)), "a hook, lib or shell file")
agents = os.path.join(root, "AGENTS.md")
if os.path.isfile(agents):
    text = open(agents).read()
    m = re.search(r"^- autofinish:.*?(?=^\S|^- |\Z)", text, re.S | re.M)
    for name in sorted(set(re.findall(r"`bin/([A-Za-z0-9_.-]+)`", m.group(0) if m else ""))):
        for d in sorted(os.listdir(os.path.join(root, "modules"))):
            f = "modules/%s/bin/%s" % (d, name)
            if os.path.isfile(os.path.join(root, f)):
                live.setdefault(f, "a tool AGENTS.md names")
config, home = sys.argv[2] or os.path.join(sys.argv[3], ".config", "regatta"), sys.argv[3]
try:
    with open(os.path.join(config, "regatta", "overlay"), encoding="utf-8-sig") as fh:
        coding = next((l.strip() for l in fh if l.strip()), "")
except OSError:
    coding = ""
if coding == "~" or coding.startswith("~/"):
    coding = home + coding[1:]
plain = []
if not os.path.isdir(coding):
    print("SKIP no overlay is named: the shim half is not checked")
else:
    pat = re.compile(r"Made by `regatta shim ((?:--[a-z-]+ )*)(\S+?)`")
    for sub in ("bin", "hooks", "shell"):
        for dp, _, ns in os.walk(os.path.join(coding, sub)):
            for n in sorted(ns):
                try:
                    head = open(os.path.join(dp, n), errors="replace").read(2000)
                except OSError:
                    continue
                m = pat.search(head)
                if not m or not os.path.isfile(os.path.join(root, m.group(2))):
                    continue
                flags, path = m.group(1).strip(), m.group(2)
                if flags:
                    live.setdefault(path, "a shim wired as a hook (%s)" % flags)
                elif path not in live:
                    plain.append(path)
bad = ["%s (%s)" % (p, why) for p, why in sorted(live.items()) if not p.startswith(exclude)]
plain = [p for p in sorted(set(plain)) if not p.startswith(exclude) and "/tests/" not in p]
if plain:
    print("NOTE %d shimmed tools land through autofinish, by the paragraph's rule: %s"
          % (len(plain), " ".join(os.path.basename(p) for p in plain)))
print("%d live paths read" % len(live))
print("RESULT " + ("; ".join(bad) or "none"))
PY
)
printf '%s\n' "$out" | grep -v '^RESULT ' | sed 's/^/    /'
check "$(printf '%s\n' "$out" | sed -n 's/^RESULT //p')" none "no live path lies outside autofinish_exclude"

# Class 1 (docs/autofinish-exclude-2026-10-23.md S1): the judges — the tools that decide what lands,
# what runs unattended and on which login — and every file they import or exec, transitively. A wrong
# one fails unseen, so each must sit on autofinish_exclude: a judge that loads a file off the list
# lands that file unwatched and with it the judgement. The walk over-approximates (a name matched in
# any module counts) and fails closed: a judge that is gone is a finding, never a shorter walk.
# Edges: common.tool("x") / peer("x") / tool("x"), BIN / "x", HERE, "x", HERE / "x", SourceFileLoader's
# path, `import x` / `from x import` of a module file, a shell's "$VAR/bin|libexec|hooks|lib/x" and `$(tool x)` / `$(peer x)`.
# It also prints G1's count: the landings of the last 7 days on HEAD that touched the list (a
# session trailer is one landing, else one committer second), the number S2 and S7 move.
echo "class 1: the judges and what they load are all on autofinish_exclude"
out=$(python3 -I - "$ROOT" <<'PY'
import json, os, re, subprocess, sys, time
from pathlib import Path
root = Path(sys.argv[1])
wf = root / ".claude" / "workflow.json"
if not wf.is_file():
    print("SKIP no .claude/workflow.json in this tree (the public twin has none)")
    print("RESULT none")
    sys.exit(0)
exclude = tuple(json.loads(wf.read_text()).get("autofinish_exclude") or ())
JUDGES = ("modules/wharf-runs/bin/autofinish", "modules/wharf-runs/bin/autofinish-run", "modules/wharf-runs/bin/dispatch",
          "modules/wharf/libexec/pr", "modules/wharf/bin/review-gate", "modules/wharf-runs/bin/check",
          "modules/wharf-runs/bin/wharf", "modules/keel/bin/keel", "modules/lighthouse/bin/account",
          "modules/aurora/bin/weekly-run", "modules/helm/libexec/skipper-run")
by_name, every = {}, set()
for m in sorted((root / "modules").iterdir()):
    for sub in ("bin", "hooks", "lib", "libexec"):
        for f in sorted((m / sub).rglob("*")) if (m / sub).is_dir() else ():
            if f.is_file() and "__pycache__" not in f.parts:
                r = f.relative_to(root).as_posix()
                by_name.setdefault(f.name, []).append(r)
                every.add(r)
REF = re.compile(r'(?:common\.tool|peer|tool)\("([^"]+)"|BIN / "([^"]+)"|HERE, "([^"]+)"|HERE / "([^"]+)"'
                 r'|SourceFileLoader\("[^"]+",\s*(?:str\()?[^,)]*?"([^"]+)"|^\s*import ([A-Za-z_]+)\b'
                 r'|^\s*from ([A-Za-z_]+) import', re.M)
SH = re.compile(r'\$\{?[A-Za-z_]+\}?/((?:bin|libexec|hooks|lib)/[A-Za-z0-9_.-]+)')
# a shell's own lookup, `$(tool x)` / `$(peer x)`: weekly-run runs tend this way (landing review, finding 2)
SHTOOL = re.compile(r'\$\((?:tool|peer) ([A-Za-z0-9_.-]+)')
# a path joined from the module's own parts: `HERE.parent / "libexec" / "helm"` (stalls_tick.py, ask)
JOIN = re.compile(r'"(bin|libexec|hooks|lib)"\s*[/,]\s*"([A-Za-z0-9_.-]+)"')
QUOTED = re.compile(r'"([A-Za-z_][A-Za-z0-9_.-]*)"')   # a sibling folder named in a string is loaded whole (harness's adapters)
missing = [j for j in JUDGES if j not in every]
def edges(p, imports=False):
    """Every module file `p` imports or execs, by the patterns above (over-approximated); `imports`:
    only what it imports or loads into its own process (`import`, `from … import`, SourceFileLoader)."""
    text = (root / p).read_text(errors="replace")
    here, mod = Path(p).parent, "/".join(p.split("/")[:2])
    found = []
    for m in REF.finditer(text):
        if imports and not any(m.groups()[4:]):
            continue
        name = next(g for g in m.groups() if g)
        n = name if "." in name or name in by_name else name + ".py"
        sib = (here / n).as_posix()   # a sibling first, then any module's file of that name
        found += [sib] if sib in every else by_name.get(n, [])
    if imports:
        return set(found) - {p}
    for m in SH.finditer(text):   # a shell's path: this module's file first, then any module's
        own = "%s/%s" % (mod, m.group(1))
        found += [own] if own in every else [r for r in every if r.endswith("/" + m.group(1))]
    for m in SHTOOL.finditer(text):
        found += by_name.get(m.group(1), [])
    for m in JOIN.finditer(text):
        found += [r for r in ["%s/%s/%s" % (mod, m.group(1), m.group(2))] if r in every]
    for name in set(QUOTED.findall(text)):
        d = (here / name).as_posix() + "/"
        found += [r for r in every if r.startswith(d)]
    return set(found) - {p}
seen, queue = set(), [j for j in JUDGES if j in every]
while queue:
    p = queue.pop(0)
    if p not in seen:
        seen.add(p)
        queue += [c for c in edges(p) if c not in seen]
off = sorted(p for p in seen if not p.startswith(exclude))
# Class 2 (finding 3): the leak gates take their fence from the core and its loaders, so a file a leak gate
# imports, off autofinish_leaks, lets a yes at the brief loosen the fence unattended. Walked from every file
# on the key; an import off it is a finding, and is not followed further. A tool a gate only runs is printed,
# not failed: most name a path in a message or count slots; one whose answer is the gate's verdict is listed
# by hand (account_guard runs `account allowed`, so `account` is on the key).
leaks = tuple(p for p in json.loads(wf.read_text()).get("autofinish_leaks") or () if isinstance(p, str) and p)
lseen, lqueue, loff = set(), sorted(r for r in every if r.startswith(leaks)), set()
if not leaks:
    loff.add("no autofinish_leaks in .claude/workflow.json")
while lqueue:
    p = lqueue.pop(0)
    if p in lseen:
        continue
    lseen.add(p)
    for c in edges(p, imports=True):
        if not c.startswith(leaks):
            loff.add("%s (imported by %s)" % (c, p))
        elif c not in lseen:
            lqueue.append(c)
ran = sorted({os.path.basename(c) for p in lseen for c in edges(p) - edges(p, imports=True) if not c.startswith(leaks)})
print("%d files in class 2 from autofinish_leaks; run, not imported, off it: %s" % (len(lseen), " ".join(ran) or "none"))
print("LEAKS " + ("; ".join(sorted(loff)) or "none"))
print("%d files in class 1 from %d judges" % (len(seen), len(JUDGES) - len(missing)))
try:   # G1: what the list holds for the owner's tap this week
    log = subprocess.run(["git", "-C", str(root), "log", "--first-parent", "HEAD", "--since=%d" % (time.time() - 7 * 86400),
                          "--format=%x00%ct%x01%(trailers:key=Claude-Session,valueonly,separator=)%x02",
                          "--name-only", "--no-renames"], capture_output=True, text=True, timeout=60).stdout
    landings = {}
    for chunk in log.split("\x00")[1:]:
        head, _, names = chunk.partition("\x02")
        ct, _, sid = head.partition("\x01")
        landings.setdefault(sid.strip() or "t" + ct, set()).update(n for n in names.split("\n") if n.strip())
    held = sum(1 for v in landings.values() if any(n.startswith(exclude) for n in v))
    print("G1: %d of %d landings on HEAD in the last 7 days touched autofinish_exclude" % (held, len(landings)))
except (OSError, subprocess.SubprocessError) as e:
    print("G1: not counted (%s)" % type(e).__name__)
print("RESULT " + ("; ".join(["judge gone: " + j for j in missing] + off) or "none"))
PY
)
printf '%s\n' "$out" | grep -v '^RESULT \|^LEAKS ' | sed 's/^/    /'
check "$(printf '%s\n' "$out" | sed -n 's/^RESULT //p')" none "every file a judge loads lies on autofinish_exclude"
leaks=$(printf '%s\n' "$out" | sed -n 's/^LEAKS //p')
check "${leaks:-none}" none "every file a leak gate loads lies on autofinish_leaks"

[ "$fails" -eq 0 ] && echo "classes: all ok" || echo "classes: $fails failed"
[ "$fails" -eq 0 ]
