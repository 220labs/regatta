#!/usr/bin/env python3
"""Sections F (answers typed in chat) and G (review-gate findings by branch, design doc before it or not).
Reads tindex.json, docs.csv, review-gate.jsonl.  Writes tables2.md.  Python 3.9, stdlib only."""
import collections, csv, datetime as dt, json, os, re, statistics, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _regatta  # noqa: E402  the core: the projects folder, the log dir

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.environ.get("BENCH") or _regatta.data("docs")  # data outside git, like bench/decisions
os.makedirs(DATA, exist_ok=True)
UD = str(_regatta.common().LOG_DIR)  # the core's log dir: the benches' data and review-gate.jsonl
T = json.load(open(os.path.join(DATA, 'tindex.json')))
D = list(csv.DictReader(open(os.path.join(DATA, 'docs.csv'))))
out = []


def P(s=''):
    out.append(s)
    print(s)


def wk(ts):
    d = dt.datetime.fromisoformat(ts.replace('Z', '+00:00'))
    y, w, _ = d.isocalendar()
    return '%d-W%02d' % (y, w)


P('## F. Answers typed in chat')
# The owner-typed turns: tindex keeps every one; continued sessions (/pickup, --continue) copy earlier turns with the same
# timestamp into a new transcript file, so the same turn must be counted once.  Also drop messages another session
# sent (cross-session notes) and skill bodies, which arrive in user records but are not the owner's words.
NOT_OWNER = ('Another Claude session', 'Base directory for this skill', '[Cross-session', '<cross-session')
seen = set()
AT = []
for t in T['all_turns']:
    if t[3].startswith(NOT_OWNER) or (t[0], t[3]) in seen:
        continue
    seen.add((t[0], t[3]))
    AT.append(t)
P('the owner-typed turns in the transcript archive: %d raw records -> %d after dropping cross-session messages, skill bodies and exact duplicates (continued sessions copy their history); dispatched (unattended) sessions are excluded; sub-agent transcripts are not read.' % (len(T['all_turns']), len(AT)))
PATS = [
    ('D-letter', re.compile(r'^\s*\**D\d+\**\s*[:—–.)=\- ]+\s*\**[A-Da-d]\b')),
    ('D-anywhere', re.compile(r'\bD\d+\s*[-–:=]?\s*\(?[A-D]\b(?![a-z])')),
    ('in-doc', re.compile(r'(answered|answers?|saved|filled)[^.]{0,30}\b(in|into) (the )?(doc|memo|form)\b|\bsaved the form\b', re.I)),
    ('go', re.compile(r'^\s*(go|go ahead|go for it|go with (all )?(the )?recommend\w*|proceed|ship it)\s*[.!]*\s*$', re.I)),
    ('accept-all', re.compile(r'\b(accept all|accepted all|all recommended|all recommendations|approve all|approved all|all approved|take all (the )?recommend\w*|go with (all )?(your )?recommend\w*|yes to all|agree with all|i agree with everything)\b', re.I)),
    ('responded', re.compile(r'^\s*(responded|i responded|answered|i answered|done|answers? (are )?in)\b|\banswered in the (doc|memo|form)\b|\bresponded\b', re.I)),
]
kinds = ('D-letter', 'D-anywhere', 'accept-all', 'go', 'responded', 'in-doc')
P('Patterns (first match wins, turns <= 600 chars): D-letter = turn starts "D<n> <letter>"; D-anywhere = "D<n>-<letter>" anywhere; accept-all = "all approved", "go with recommendations", ...; go = a bare "go"/"ship it";')
P('responded = "responded"/"answered"/"done" (the word that tells the doc_answers hook the answers are in the doc, not in chat); in-doc = "answered in the doc".')
by = collections.defaultdict(collections.Counter)
wt = collections.Counter()
for t in AT:
    w = wk(t[0])
    wt[w] += 1
    x = t[3]
    if len(x) > 600:
        continue
    for pn, pr in PATS:
        if pr.search(x):
            by[w][pn] += 1
            break
P()
P('| ISO week | the owner turns | ' + ' | '.join(kinds) + ' | chat answer-like (first four) | answers-in-doc signal (last two) |')
P('| --- | --- | ' + ' | '.join('---' for _ in kinds) + ' | --- | --- |')
tot = collections.Counter()
for w in sorted(wt):
    tot.update(by[w])
    P('| %s | %d | %s | %d | %d |' % (w, wt[w], ' | '.join(str(by[w][k]) for k in kinds), sum(by[w][k] for k in kinds[:4]), sum(by[w][k] for k in kinds[4:])))
P('| total | %d | %s | %d | %d |' % (sum(wt.values()), ' | '.join(str(tot[k]) for k in kinds), sum(tot[k] for k in kinds[:4]), sum(tot[k] for k in kinds[4:])))
P()
P('AskUserQuestion answers are tool results, not typed turns: they are not in this table (`bin/interruptions` counts them: 344 asks, 58 % took the recommendation).')
P()
APPROVE = re.compile(r'\b(approved?|agree[ds]?|yes|yep|accept\w*|go|ok|okay|sounds good|recommend\w*|proceed|ship it|do it|lgtm)\b', re.I)
RESP = re.compile(r'\b(responded|answered|answers? (are )?in|saved)\b', re.I)
alt = [t for t in AT if t[4]]
P('the owner turns right after an assistant message carrying a hand-over link to a .md file: %d (of %d typed turns)' % (len(alt), len(AT)))
kc = collections.Counter()
for t in alt:
    x = t[3]
    if RESP.search(x) and len(x) < 200:
        kc['says responded/answered (answers are in the doc)'] += 1
    elif re.search(r'\bD\d+\b', x):
        kc['names D-ids in the message'] += 1
    elif len(x) < 120 and APPROVE.search(x):
        kc['short approval in chat (<120 chars)'] += 1
    elif len(x) >= 120:
        kc['long message (discussion or instruction)'] += 1
    else:
        kc['other short'] += 1
for k, v in kc.most_common():
    P('  - %s: %d (%s)' % (k, v, '%d%%' % round(100.0 * v / len(alt))))
dmen = [t for t in AT if re.search(r'\bD\d+\b', t[3])]
dw = collections.Counter(wk(t[0]) for t in dmen)
P('the owner turns that name a D-id (any context): %d; per week %s' % (len(dmen), dict(sorted(dw.items()))))
byp = collections.Counter(t[1] for t in alt)
P('post-link turns by project: %s' % dict(byp.most_common(8)))
P()
# docs: how many docs have a chat answer? (the owner turn in the same session shortly after link, answer-like) -> from docs.csv ans_src
P('docs whose first answer time came from a transcript turn (ans_src=tr): %d; from git: %d; git-squashed (no usable time): %d; none: %d' % tuple(
    sum(1 for r in D if r['ans_src'] == k) for k in ('tr', 'git', 'git-squashed', 'none')))
P()
# examples: prefer after_link and D patterns
ex = [t for t in alt if (re.search(r'\bD\d+\b', t[3]) or (len(t[3]) < 120 and APPROVE.search(t[3]))) and not t[3].startswith(NOT_OWNER)]
ex.sort(key=lambda t: t[0])
P('Examples (the owner\'s words right after a hand-over link, decision-related only; %d candidates, 10 spread evenly):' % len(ex))
step = max(1, len(ex) // 10)
for t in ex[::step][:10]:
    P('  - %s (%s): "%s"' % (t[0][:10], t[1], re.sub(r'\s+', ' ', t[3])[:150]))
P()

# ------------------------------------------------------------------ G
P('## G. Code quality per launched branch (review-gate.jsonl)')
rows = [json.loads(l) for l in open(os.path.join(UD, 'review-gate.jsonl'))]
rg = [r for r in rows if r.get('findings') is not None and r.get('diff')]
P('runs %d; with findings/diff fields %d (older runs lack them); distinct branches %d' % (len(rows), len(rg), len({r['branch'] for r in rg})))
# one row per branch: the last run (the one that gated the launch)
lastrun = {}
for r in sorted(rg, key=lambda r: r['ts']):
    lastrun[r['branch']] = r
br = list(lastrun.values())
P('per-branch rows (last run per branch): %d' % len(br))


def sev(r):
    f = r['findings']
    return f['S1'] + f['S2'] + f['S3']


def wrong(r):
    w = r['wrong']
    return w['S1'] + w['S2'] + w['S3']


docs_by_proj = collections.defaultdict(list)
for r in D:
    proj = r['repo'].split('/')[-1]
    docs_by_proj[proj].append(r)


def bdate(b):
    m = re.search(r'/(\d{4}-\d{2}-\d{2})-(.+)$', b)
    return (dt.date.fromisoformat(m.group(1)), m.group(2)) if m else (None, '')


STOP = {'the', 'and', 'for', 'with', 'from', 'doc', 'docs', 'fix', 'design'}


def toks(s):
    return {t for t in re.split(r'[^a-z0-9]+', s.lower()) if len(t) > 3 and not t.isdigit() and t not in STOP}


for r in br:
    bd, topic = bdate(r['branch'])
    r['bd'] = bd
    ds = docs_by_proj.get(r['project'], [])
    win = [x for x in ds if bd and bd - dt.timedelta(days=7) <= dt.date.fromisoformat(x['handover'][:10]) <= bd]
    r['after_window'] = bool(win)
    tt = toks(topic)
    r['after_topic'] = any(tt & toks(re.sub(r'\d{4}-\d{2}-\d{2}', '', x['file'][:-3])) for x in ds if bd and dt.date.fromisoformat(x['handover'][:10]) <= bd + dt.timedelta(days=1))
    r['after_arch'] = any(tt & toks(re.sub(r'\d{4}-\d{2}-\d{2}', '', x['file'][:-3])) for x in ds if int(x['architect']) and bd and dt.date.fromisoformat(x['handover'][:10]) <= bd + dt.timedelta(days=1))
    r['after_title'] = any(tt & toks(x['title']) for x in ds if bd and dt.date.fromisoformat(x['handover'][:10]) <= bd + dt.timedelta(days=1))
    r['sev'] = sev(r)
    r['wrong_n'] = wrong(r)
    r['added'] = r['diff']['added']


def agg(label, rs):
    a = sum(r['added'] for r in rs)
    f = sum(r['sev'] for r in rs)
    s12 = sum(r['findings']['S1'] + r['findings']['S2'] for r in rs)
    w = sum(r['wrong_n'] for r in rs)
    rates = sorted(100.0 * r['sev'] / r['added'] for r in rs if r['added'] > 0)
    med = statistics.median(rates) if rates else float('nan')
    P('| %s | %d%s | %d | %d | %.1f | %.1f | %.1f | %d (%s) |' % (label, len(rs), ' †' if len(rs) < 10 else '', a, f, 100.0 * f / a if a else 0, 100.0 * s12 / a if a else 0, med, w, ('%d%%' % round(100.0 * w / f)) if f else '-'))


P('| group | branches | added lines | findings S1+S2+S3 | per 100 added (pooled) | S1+S2 per 100 | median branch per 100 | wrong (share of findings) |')
P('| --- | --- | --- | --- | --- | --- | --- | --- |')
agg('all', br)
agg('doc in same project <=7 d before (window match)', [r for r in br if r['after_window']])
agg('no such doc', [r for r in br if not r['after_window']])
agg('branch topic names a doc of the project (topic match)', [r for r in br if r['after_topic']])
agg('no topic match', [r for r in br if not r['after_topic']])
agg('topic names an architect-written doc', [r for r in br if r['after_arch']])
agg('topic in the file name or title of any doc', [r for r in br if r['after_topic'] or r['after_title']])
agg('no match in file name or title', [r for r in br if not (r['after_topic'] or r['after_title'])])
agg('branch built by Opus only (models.main, no Sonnet)', [r for r in br if 'claude-sonnet' not in json.dumps(r.get('models'))])
agg('branch with a Sonnet main or agent', [r for r in br if 'claude-sonnet' in json.dumps(r.get('models'))])
for p in sorted({r['project'] for r in br}):
    agg('project ' + p, [r for r in br if r['project'] == p])
P()
P('Window match: the branch date (from its name) falls 0-7 days after the hand-over date of any doc in the same project folder name; topic match: a word >3 letters of the branch topic appears in a doc file name of the project handed over on or before the branch date +1. Both approximate; the branch\'s first commit date is not read.')
P('Branch-level correlation sizes: window-matched %d of %d branches; topic-matched %d.' % (sum(r['after_window'] for r in br), len(br), sum(r['after_topic'] for r in br)))
open(os.path.join(DATA, 'tables2.md'), 'w').write('\n'.join(out))
