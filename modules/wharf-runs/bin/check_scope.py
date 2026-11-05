#!/usr/bin/env python3
"""check_scope — which of the check line's commands a branch's change reaches.

    CHECK_CMDS="<one command a line>" check_scope.py <checkout> <base> "<changed paths, one a line>"

Prints a `SCOPE<tab><said>` line, then one `RUN<tab><why>` or `SKIP<tab><why>` per command, in order.
The rules are `check`'s header (lines 8-30): a module's suite runs when the module changed, or one it
uses (its plugin.json dependencies, followed through, or a module its files name by path, one hop);
a change outside modules/ (bar docs/ and .github/, though .github/ci/ counts: the shares' scripts and list,
which wharf's and wharf-runs' suites test; free CI's S2, 2026-11-04) runs the whole line; check.yml and
check-linux.yml run wharf's suite, which reads them. Moved out of `check`'s heredoc
(2026-10-30) so the Linux PR trigger (.github/workflows/check-linux.yml) asks the same question.
"""
import json, os, re, sys
wt, base, changed = sys.argv[1], sys.argv[2], [p for p in sys.argv[3].split("\n") if p]
cmds = [l for l in os.environ.get("CHECK_CMDS", "").split("\n") if l.strip()]   # in the environment: argv holds the paths
mods = sorted(d for d in os.listdir(os.path.join(wt, "modules")) if os.path.isdir(os.path.join(wt, "modules", d)))
def declared(m):
    """m's plugin.json dependencies, every name (a module since removed still counts)"""
    try:
        return list(json.load(open(os.path.join(wt, "modules", m, ".claude-plugin/plugin.json"))).get("dependencies") or [])
    except Exception:
        return []
def suite_of(c):
    for w in c.split():
        m = re.match(r"modules/([^/]+)/tests/", w)
        if m and m.group(1) in mods: return m.group(1)
    return None
def say(line, verdicts):
    print("SCOPE\t" + line)
    for v in verdicts: print(v)
if not changed:
    say("the whole line: nothing changed since %s" % base, ["RUN\tnothing changed since %s" % base] * len(cmds)); sys.exit(0)
# own: modules whose own suite runs; deep: changes other modules' suites follow (code, not a suite or prose)
own, deep, roots, why_all = set(), set(), False, None
for p in changed:
    m = re.match(r"modules/([^/]+)/(.*)", p)
    if m:
        name, rest = m.group(1), m.group(2)
        own.add(name)
        # a suite or prose is the module's own; a skill or an agent is behaviour another suite may read
        if name not in mods or not (rest.startswith("tests/") or (rest.endswith(".md") and not rest.startswith(("skills/", "agents/")))): deep.add(name)
        continue
    m = re.match(r"\.([^/]+)/", p)
    if m and m.group(1) in mods: own.add(m.group(1))
    # the two check workflows are wharf's suite's input (its roads and trigger cases read them, free CI's S2)
    elif p in (".github/workflows/check.yml", ".github/workflows/check-linux.yml") and "wharf" in mods: own.add("wharf")
    # .github/ci/ holds share.sh and its list (.circleci/ until S2, where it ran the whole line): still does
    elif p.startswith("docs/") or (p.startswith(".github/") and not p.startswith(".github/ci/")): pass
    elif "/" not in p and p.endswith(".md"): roots = True
    else: why_all = why_all or p
if why_all:
    say("the whole line: %s changed, outside modules/" % why_all, ["RUN\t%s changed, outside modules/" % why_all] * len(cmds)); sys.exit(0)
names = sorted(set(mods) | own)
def mentions(m):
    """the modules m's files (not Markdown) name by path"""
    out = set()
    # a suite names a peer as `modules/<peer>` or `$D/../<peer>/` (sextant's principal.sh runs wharf's council
    # that way): both read as a use, which errs only towards RUN (free-ci S3's finish review)
    pat = re.compile(r"(?:modules|\.\.)/(%s)(?![\w-])" % "|".join(re.escape(x) for x in names if x != m))
    for root, dirs, files in os.walk(os.path.join(wt, "modules", m)):
        dirs[:] = [d for d in dirs if not d.startswith(".") or d == ".claude-plugin"]
        for f in files:
            if f.endswith(".md"): continue
            p = os.path.join(root, f)
            try:
                if os.path.getsize(p) > 2_000_000: continue
                with open(p, "rb") as fh: out |= set(pat.findall(fh.read().decode("utf-8", "replace")))
            except OSError:
                pass
    out.discard(m); return out
def reach(m):
    """what m's suite may see change: its declared dependencies, followed through, and what its own
    files name by path (one hop: a loose mention followed through would reach everything)"""
    seen, todo = set(), [m]
    while todo:
        x = todo.pop()
        for d in declared(x) if x in mods else []:
            if d not in seen and d != m: seen.add(d); todo.append(d)
    seen |= mentions(m); seen.discard(m); return seen
universal = [m for m in mods if all(m in declared(x) for x in mods if x != m)]   # the core: every other module declares it
run_why = {}
for m in mods:
    if m in own: run_why[m] = "modules/%s changed" % m; continue
    hit = sorted(reach(m) & deep)
    if hit: run_why[m] = "uses modules/%s, changed" % hit[0]
    elif m in universal and (own or deep): run_why[m] = "modules/%s checks every module" % m
    elif roots and not declared(m): run_why[m] = "a root Markdown file changed, which modules/%s checks" % m
out = []
for c in cmds:
    s = suite_of(c)
    if s is None: out.append("RUN\tnot a module's suite: runs every time")
    elif s in run_why: out.append("RUN\t" + run_why[s])
    else: out.append("SKIP\tno change under modules/%s or what it uses since %s" % (s, base))
n = sum(1 for v in out if v.startswith("RUN"))
say("%d of %d script(s): %s changed since %s" % (n, len(cmds), ", ".join(["modules/" + m for m in sorted(own)] + (["a root Markdown file"] if roots else [])), base), out)
