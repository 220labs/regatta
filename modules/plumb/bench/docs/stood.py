#!/usr/bin/env python3
"""Where did `memo stand --apply` actually run?  Looks for the Stood-By trailer and 'Applied. Stood' replies
in every repo root of the docs in docs.csv.  Prints repo, commits, docs."""
import csv, os, subprocess, re, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _regatta  # noqa: E402  the core: the projects folder, the log dir
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.environ.get("BENCH") or _regatta.data("docs")  # data outside git, like bench/decisions
os.makedirs(DATA, exist_ok=True)
R = list(csv.DictReader(open(os.path.join(DATA, 'docs.csv'))))
def common(d):
    return subprocess.run(['git', '-C', d, 'rev-parse', '--path-format=absolute', '--git-common-dir'], capture_output=True, text=True).stdout.strip()
roots = sorted({common(os.path.dirname(r['path'])) for r in R})
for root in roots:
    out = subprocess.run(['git', '-C', root, 'log', '--all', '--format=%h %aI %s', '--grep=Stood-By'], capture_output=True, text=True).stdout.strip()
    n = len(out.splitlines()) if out else 0
    out2 = subprocess.run(['git', '-C', root, 'log', '--all', '--format=%h %aI %s', '-i', '--grep=stood'], capture_output=True, text=True).stdout.strip()
    print(root, 'Stood-By commits:', n, '| "stood" in subject/body:', len(out2.splitlines()) if out2 else 0)
    for l in (out.splitlines()[:6]):
        print('   ', l[:140])
for r in R:
    t = open(r['path']).read()
    if re.search(r'Applied\.\*\*\s+Stood', t) or re.search(r'^Stands:', t, re.M):
        print('doc with stood reply / Stands line:', r['key'], r['handover'][:10])
