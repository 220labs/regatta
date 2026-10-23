import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import _regatta  # noqa: E402  the core: the projects folder, the log dir
root = _regatta.projects()
skip = {'node_modules', '.git', 'transcripts', os.path.basename(str(_regatta.common().LOG_DIR)), 'worktrees', 'memo-archive'}
hdr = re.compile(r'^#+ .*(feedback from the owner|feedback from \w+|open feedback)', re.I)
out = []
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
            if hdr.match(l):
                body = []
                for m in lines[i + 1:]:
                    if re.match(r'^## ', m) and body:
                        break
                    body.append(m)
                txt = '\n'.join(body).strip()
                txt = re.sub(r'\(anything that does not fit[^\n]*\)', '', txt).strip()
                txt = re.sub(r'^.*(Write here|the owner writes|free text)[^\n]*\n', '', txt, flags=re.I).strip()
                if len(txt) > 15:
                    out.append('### %s:%d\n%s\n' % (os.path.relpath(p, root), i + 1, txt[:1800]))
print('\n'.join(out))
