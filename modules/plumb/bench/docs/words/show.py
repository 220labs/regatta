import json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
rows = [json.loads(l) for l in open(os.path.join(here, 'human.jsonl'))]
rows.sort(key=lambda r: r['t'])
for a in sys.argv[1:]:
    i = int(a)
    r = rows[i]
    print('[%d] %s %s %s\n%s\n' % (i, r['t'][:16], r['p'], r['s'][:8], r['x'][:2500]))
