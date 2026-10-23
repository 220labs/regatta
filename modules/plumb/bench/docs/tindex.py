#!/usr/bin/env python3
"""One pass over <projects>/transcripts/*/*.jsonl, the transcript archive (Python 3.9, stdlib only).

Writes metrics/tindex.json:
  mentions[basename] -> [[ts, session, kind]]   kind: link (assistant text with the doc name + a hand-over
                         marker: 127.0.0.1, github.com, spacesheep, 'memo line'), write (a Write/Edit tool_use on
                         the file), amention (any other assistant mention), umention (the owner-typed mention)
  turns[session]     -> [[ts, text[:400]]]  the owner-typed turns, only for sessions that mention a doc
  chat               -> [[ts, project, session, pattern, text[:240], after_dlist]]  answer-like the owner turns
  weekly_turns       -> {iso-week: n the owner-typed turns}  (denominator)
The owner-typed = user record, not sidechain, no tool_result, text not starting '<' / hook/system boilerplate, and the
session's first user text does not start 'You are an unattended session' (a dispatched run: nobody typing).
"""
import glob, json, os, re, sys, datetime as dt
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _regatta  # noqa: E402  the core: the projects folder, the log dir

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.environ.get("BENCH") or _regatta.data("docs")  # data outside git, like bench/decisions
os.makedirs(DATA, exist_ok=True)
docs = json.load(open(os.path.join(DATA, 'list.json')))
names = sorted({os.path.basename(d['path']) for d in docs})
name_re = re.compile('|'.join(re.escape(n) for n in names))
LINK_RE = re.compile(r'127\.0\.0\.1|github\.com/[^\s)]+/(?:blob|edit)/|spacesheep\.dev')
SKIP_START = ('<', 'Stop hook', 'Caveat:', '[Request interrupted', 'This session is being continued',
              'You are an unattended session', 'Picked up with', 'PreToolUse', 'UserPromptSubmit')
PATS = [
    ('D-letter', re.compile(r'^\s*\**D\d+\**\s*[:—–.)=\- ]+\s*\**[A-Da-d]\b')),
    ('D-anywhere', re.compile(r'\bD\d+\s*[-\u2013:=]?\s*\(?[A-D]\b(?![a-z])')),
    ('in-doc', re.compile(r'(answered|answers?|saved|filled)[^.]{0,30}\b(in|into) (the )?(doc|memo|form)\b|\bsaved the form\b', re.I)),
    ('go', re.compile(r'^\s*(go|go ahead|go for it|go with (all )?(the )?recommend\w*|proceed|ship it)\s*[.!]*\s*$', re.I)),
    ('accept-all', re.compile(r'\b(accept all|accepted all|all recommended|all recommendations|approve all|approved all|take all (the )?recommend\w*|go with (all )?(your )?recommend\w*|yes to all|agree with all)\b', re.I)),
    ('responded', re.compile(r'^\s*(responded|i responded|answered|i answered|done|answers? (are )?in)\b|\banswered in the (doc|memo|form)\b|\bresponded\b', re.I)),
]


def utext(o):
    c = o.get('message', {}).get('content')
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        parts = []
        for b in c:
            if isinstance(b, dict) and b.get('type') == 'text':
                parts.append(b.get('text', ''))
        return '\n'.join(parts)
    return ''


def wk(ts):
    try:
        d = dt.datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except Exception:
        return None
    y, w, _ = d.isocalendar()
    return '%d-W%02d' % (y, w)


mentions = {}
allturns = []
turns = {}
chat = []
weekly = {}
files = sorted(glob.glob(os.path.join(_regatta.projects(), 'transcripts', '*', '*.jsonl')))
for f in files:
    project = f.split('/')[-2]
    sess = os.path.basename(f)[:-6]
    first_user = True
    dispatched = False
    after_dlist = False
    after_link = False
    mine = []   # this session's the owner turns
    hit = False
    for line in open(f, errors='replace'):
        is_user = '"type":"user"' in line[:1500]
        is_asst = (not is_user) and '"type":"assistant"' in line
        if is_asst:
            after_dlist = ('Recommended' in line and 'D1' in line)
            after_link = bool(LINK_RE.search(line)) and ('.md' in line)
            if name_re.search(line):
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                ts = o.get('timestamp')
                c = o.get('message', {}).get('content')
                if not isinstance(c, list):
                    continue
                for b in c:
                    if not isinstance(b, dict):
                        continue
                    if b.get('type') == 'text':
                        t = b.get('text', '')
                        for n in set(name_re.findall(t)):
                            kind = 'link' if LINK_RE.search(t) else 'amention'
                            mentions.setdefault(n, []).append([ts, sess, kind])
                            hit = True
                    elif b.get('type') == 'tool_use' and b.get('name') in ('Write', 'Edit', 'MultiEdit'):
                        fp = (b.get('input') or {}).get('file_path', '')
                        n = os.path.basename(fp)
                        if n in names:
                            mentions.setdefault(n, []).append([ts, sess, 'write'])
                            hit = True
            continue
        if not is_user or '"tool_result"' in line:
            continue
        try:
            o = json.loads(line)
        except Exception:
            continue
        if o.get('isSidechain'):
            continue
        t = utext(o).strip()
        if first_user:
            first_user = False
            dispatched = t.startswith('You are an unattended session')
        if dispatched or not t or t.startswith(SKIP_START):
            continue
        ts = o.get('timestamp')
        w = wk(ts)
        if w:
            weekly[w] = weekly.get(w, 0) + 1
        mine.append([ts, t[:400]])
        allturns.append([ts, project, sess, t[:300], after_link, after_dlist])
        for n in set(name_re.findall(t)):
            mentions.setdefault(n, []).append([ts, sess, 'umention'])
            hit = True
        for pn, pr in PATS:
            if len(t) <= 600 and pr.search(t):
                chat.append([ts, project, sess, pn, t[:240], after_dlist, after_link])
                break
    if hit:
        turns[sess] = mine
json.dump({'mentions': mentions, 'turns': turns, 'chat': chat, 'weekly_turns': weekly, 'all_turns': allturns},
          open(os.path.join(DATA, 'tindex.json'), 'w'))
print(len(files), 'files;', sum(len(v) for v in mentions.values()), 'mentions;', len(chat), 'chat hits;',
      sum(weekly.values()), 'the owner turns')
