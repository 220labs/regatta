import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
import _regatta  # noqa: E402  the core: the projects folder, the log dir
root = _regatta.projects()
skip = {'node_modules', '.git', 'transcripts', os.path.basename(str(_regatta.common().LOG_DIR)), 'worktrees', 'memo-archive', 'words'}
rows = []
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
            if not l.lstrip().startswith('➤ Answer'):
                continue
            ans = l.split('Answer', 1)[1].lstrip(':').strip()
            extra = []
            j = i + 1
            # only lines glued to the Answer line (no blank between) count as the answer
            while j < len(lines) and lines[j].strip() and len(extra) < 6 \
                    and not re.match(r'^\s*(#|---|- \*\*D|\*\*D|➤)', lines[j]):
                extra.append(lines[j].strip())
                j += 1
            full = re.sub(r'\s+', ' ', (ans + ' ' + ' '.join(extra)).strip())
            rec = ''
            title = ''
            for k in range(i - 1, max(0, i - 60), -1):
                if not rec and 'Recommended' in lines[k]:
                    rec = lines[k].strip()
                if re.match(r'^\s*(- )?\*\*D\d+', lines[k]) or re.match(r'^#+ .*\bD\d+', lines[k]):
                    title = lines[k].strip()
                    break
            rows.append((os.path.relpath(p, root), i + 1, title[:120], rec[:200], full[:500]))
n = 0
for r in rows:
    if not r[4]:
        continue
    n += 1
    print('%s:%d | %s\n  REC: %s\n  ANS: %s\n' % r)
print('answered', n, 'of', len(rows), file=sys.stderr)
