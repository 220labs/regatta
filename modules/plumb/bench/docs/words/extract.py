import json, glob, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import _regatta  # noqa: E402  the core: the projects folder, the log dir
home = os.path.expanduser('~')
here = os.path.dirname(os.path.abspath(__file__))
files = []
for p in glob.glob(os.path.join(_regatta.projects(), 'transcripts', '*', '*.jsonl')):
    files.append((os.path.basename(os.path.dirname(p)), p))
slug = lambda p: p.replace('/', '-').replace('.', '-').replace('_', '-')  # Claude Code's folder names
for root in _regatta.common().login_dirs():  # every login dir here, from the accounts registry
    for p in glob.glob(os.path.join(str(root), 'projects', '*', '*.jsonl')):
        d = os.path.basename(os.path.dirname(p)).replace(slug(_regatta.projects()) + '-', '').replace(slug(home), '~')
        files.append((d, p))
seen = set()
out = open(os.path.join(here, 'prompts.jsonl'), 'w')
n = 0
for proj, p in files:
    try:
        for line in open(p, errors='replace'):
            if '"type":"user"' not in line[:600]:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get('type') != 'user' or r.get('isSidechain'):
                continue
            u = r.get('uuid')
            if u and u in seen:
                continue
            if u:
                seen.add(u)
            c = (r.get('message') or {}).get('content')
            if isinstance(c, list):
                c = ' '.join(b.get('text', '') for b in c if isinstance(b, dict) and b.get('type') == 'text')
            if not isinstance(c, str):
                continue
            c = c.strip()
            if not c or c.startswith('<'):
                continue
            out.write(json.dumps({'p': proj, 's': r.get('sessionId') or os.path.basename(p),
                                  't': r.get('timestamp', ''), 'x': c}) + '\n')
            n += 1
    except Exception as e:
        print(p, e, file=sys.stderr)
print(len(files), n)
