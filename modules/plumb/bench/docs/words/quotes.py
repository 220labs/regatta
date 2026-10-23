import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import _regatta  # noqa: E402  the core: the projects folder, the log dir
root = _regatta.projects()
skip = {'node_modules', '.git', 'transcripts', os.path.basename(str(_regatta.common().LOG_DIR)), 'worktrees', 'memo-archive', 'sextant', 'words'}
a = re.compile(r'the owner[^|\n]{0,60}["“][^"”]{25,}["”]')
k = re.compile(sys.argv[1], re.I)
seen = set()
for d, ds, fs in os.walk(root):
    ds[:] = [x for x in ds if x not in skip]
    for f in fs:
        if not f.endswith('.md'):
            continue
        p = os.path.join(d, f)
        try:
            lines = open(p, errors='replace').read().split('\n')
        except Exception:
            continue
        for i, l in enumerate(lines):
            if a.search(l) and k.search(l):
                key = re.sub(r'\W+', '', l)[:80]
                if key in seen:
                    continue
                seen.add(key)
                print('%s:%d: %s' % (os.path.relpath(p, root), i + 1, l.strip()[:int(sys.argv[2])]))
