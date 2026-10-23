import json, os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
rows = [json.loads(l) for l in open(os.path.join(here, 'human.jsonl'))]
rows.sort(key=lambda r: r['t'])
pat = re.compile(sys.argv[1], re.I)
lo = int(sys.argv[2]) if len(sys.argv) > 2 else 0
hi = int(sys.argv[3]) if len(sys.argv) > 3 else 10**9
mx = int(sys.argv[4]) if len(sys.argv) > 4 else 700
for i, r in enumerate(rows):
    if i < lo or i >= hi:
        continue
    if pat.search(r['x']):
        print('[%d] %s %s %s\n%s\n' % (i, r['t'][:10], r['p'][:14], r['s'][:6], r['x'][:mx]))
