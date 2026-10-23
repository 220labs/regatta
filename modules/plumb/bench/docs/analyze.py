#!/usr/bin/env python3
"""Aggregates over docs.csv / items.csv / tindex.json / corpus.jsonl / review-gate.jsonl -> tables.md (and stdout).
Python 3.9, stdlib only.  Run after docs.py."""
import collections, csv, datetime as dt, json, os, re, statistics, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import _regatta  # noqa: E402  the core: the projects folder, the log dir

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.environ.get("BENCH") or _regatta.data("docs")  # data outside git, like bench/decisions
os.makedirs(DATA, exist_ok=True)
UD = str(_regatta.common().LOG_DIR)  # the core's log dir: the benches' data and review-gate.jsonl
D = list(csv.DictReader(open(os.path.join(DATA, 'docs.csv'))))
I = list(csv.DictReader(open(os.path.join(DATA, 'items.csv'))))
for r in D:
    for k in ('words', 'd_items', 'fam_legend', 'fam_defined', 'items_answered', 'memo_answered', 'architect', 'legend',
              'do_now', 'one_para', 'replies', 'has_built', 'squashed', 'n_commits', 'kept', 'overruled', 'stood_items'):
        r[k] = int(r[k])
    r['age'] = float(r['age_days']) if r['age_days'] else 0.0
    r['hrs'] = float(r['hrs_to_answer']) if r['hrs_to_answer'] != '' else None
    r['bd'] = float(r['built_days']) if r['built_days'] != '' else None
    r['week'] = r['handover'][:10]
    d0 = dt.date.fromisoformat(r['handover'][:10])
    y, w, _ = d0.isocalendar()
    r['wk'] = '%d-W%02d' % (y, w)
    r['fam'] = r['fam_legend'] if r['legend'] else None
by = {r['key']: r for r in D}
for r in I:
    for k in ('pos', 'n', 'last', 'body_len', 'has_rev', 'has_opts', 'n_opts', 'new_shape', 'answered', 'memo_ans', 'stood', 'yolo', 'stood_touched'):
        r[k] = int(r[k])
    r['age'] = float(r['age_days']) if r['age_days'] else 0.0

out = []


def P(s=''):
    out.append(s)
    print(s)


def pct(a, b):
    return '%d%%' % round(100.0 * a / b) if b else '-'


def cell(n_never, n):
    return '%d/%d (%s)%s' % (n_never, n, pct(n_never, n), ' †' if n < 10 else '')


def table(title, rows, keyfn, order, pred, label='never answered', extra=None):
    P('| %s | n | %s | share |' % (title, label))
    P('| --- | --- | --- | --- |')
    g = collections.defaultdict(list)
    for r in rows:
        g[keyfn(r)].append(r)
    for k in order if order else sorted(g):
        v = g.get(k, [])
        if not v:
            continue
        a = sum(1 for r in v if pred(r))
        P('| %s | %d%s | %d | %s |' % (k, len(v), ' †' if len(v) < 10 else '', a, pct(a, len(v))))
    P()


def bucket(x, edges, labels):
    for e, l in zip(edges, labels):
        if x < e:
            return l
    return labels[-1]


old = [r for r in D if r['age'] > 3]
never = lambda r: r['items_answered'] == 0
never_memo = lambda r: r['memo_answered'] == 0
P('## A. Docs and ages')
P('docs %d; older than 3 days %d; never answered (strict) %d of %d old; never answered (memo.answered, parent measure) %d of %d old'
  % (len(D), len(old), sum(map(never, old)), len(old), sum(map(never_memo, old)), len(old)))
P('strict = the owner-box text on a new-shape item, a settling reply or an the owner note; old-shape answer text equal to the first commit is a pre-fill.')
P('new-shape docs (items with a Recommended line): %d of %d; old-shape: %d' % (
    sum(1 for r in D if int(r['new_shape']) > 0), len(D), sum(1 for r in D if int(r['new_shape']) == 0)))
P('hand-over source: %s' % dict(collections.Counter(r['ho_src'] for r in D)))
P('answer-time source: %s' % dict(collections.Counter(r['ans_src'] for r in D)))
P()

P('## B. Never-answered share, docs older than 3 days (strict | memo measure)')
for name, keyf, order in [
    ('words', lambda r: bucket(r['words'], (2000, 5001), ('<2,000', '2,000-5,000', '>5,000')), ('<2,000', '2,000-5,000', '>5,000')),
    ('D-items', lambda r: bucket(r['d_items'], (4, 8), ('<=3', '4-7', '>=8')), ('<=3', '4-7', '>=8')),
    ('architect "Written by"', lambda r: 'architect' if r['architect'] else 'not', ('architect', 'not')),
    ('has "Do this now"', lambda r: 'yes' if r['do_now'] else 'no', ('yes', 'no')),
    ('has "decision in one paragraph"', lambda r: 'yes' if r['one_para'] else 'no', ('yes', 'no')),
    ('has legend', lambda r: 'yes' if r['legend'] else 'no', ('yes', 'no')),
    ('id families in legend (docs with legend)', lambda r: 'no legend' if not r['legend'] else bucket(r['fam_legend'], (2, 4, 6), ('1', '2-3', '4-5', '6+')), ('no legend', '1', '2-3', '4-5', '6+')),
    ('id families defined in body', lambda r: bucket(r['fam_defined'], (2, 3, 4, 6), ('<=1', '2', '3', '4-5', '6+')), ('<=1', '2', '3', '4-5', '6+')),
    ('new-shape (Recommended lines)', lambda r: 'new' if int(r['new_shape']) > 0 else 'old', ('new', 'old')),
]:
    P('**%s**' % name)
    P('| %s | n all | never, new-shape docs only | never, all docs (strict) | never, all docs (memo) |' % name)
    P('| --- | --- | --- | --- | --- |')
    g = collections.defaultdict(list)
    for r in old:
        g[keyf(r)].append(r)
    for k in order:
        v = g.get(k, [])
        if v:
            nv = [r for r in v if int(r['new_shape']) > 0]
            P('| %s | %d%s | %s | %s | %s |' % (k, len(v), ' †' if len(v) < 10 else '', cell(sum(map(never, nv)), len(nv)), cell(sum(map(never, v)), len(v)), cell(sum(map(never_memo, v)), len(v))))
    P()
# repo
repo_n = collections.Counter(r['repo'] for r in old)
P('**repo** (repos with fewer than 5 old docs pooled as "other")')
P('| repo | n all | never, new-shape docs only | never, all docs (strict) | never, all docs (memo) |')
P('| --- | --- | --- | --- | --- |')
g = collections.defaultdict(list)
for r in old:
    g[r['repo'] if repo_n[r['repo']] >= 5 else 'other'].append(r)
for k, v in sorted(g.items(), key=lambda kv: -len(kv[1])):
    nv = [r for r in v if int(r['new_shape']) > 0]
    P('| %s | %d%s | %s | %s | %s |' % (k, len(v), ' †' if len(v) < 10 else '', cell(sum(map(never, nv)), len(nv)), cell(sum(map(never, v)), len(v)), cell(sum(map(never_memo, v)), len(v))))
P()
P('**week of hand-over** (all docs, not only old: is the backlog growing?)')
P('| ISO week | docs | D-items | never (strict) | never (memo) | items answered, strict | of which new-shape docs | new-shape: none answered | new-shape: fully answered |')
P('| --- | --- | --- | --- | --- | --- | --- | --- | --- |')
g = collections.defaultdict(list)
for r in D:
    g[r['wk']].append(r)
for k in sorted(g):
    v = g[k]
    ni = sum(r['d_items'] for r in v)
    na = sum(r['items_answered'] for r in v)
    nv = [r for r in v if int(r['new_shape']) > 0]
    P('| %s | %d%s | %d | %s | %s | %s | %d | %d | %d |' % (k, len(v), ' †' if len(v) < 10 else '', ni, cell(sum(map(never, v)), len(v)), cell(sum(map(never_memo, v)), len(v)), pct(na, ni), len(nv), sum(1 for r in nv if r['items_answered'] == 0), sum(1 for r in nv if r['items_answered'] == r['d_items'])))
P()

# ------------------------------------------------------------------ item cuts
P('## C. Per-item cuts (items in docs older than 3 days; answered = strict item-level)')
oi = [r for r in I if r['age'] > 3 and r['new_shape']]
P('new-shape items (a Recommended line; an empty box means unanswered) in docs older than 3 days: %d in %d docs. Old-shape items are excluded: their box is pre-filled, so answered cannot be read from it.' % (len(oi), len({r['key'] for r in oi})))
P()
cuts = [
    ('position', lambda r: 'D1 (first)' if r['pos'] == 1 else ('last' if r['last'] else ('2nd' if r['pos'] == 2 else 'middle')), ('D1 (first)', '2nd', 'middle', 'last')),
    ('position 1..8+', lambda r: str(min(r['pos'], 8)) if r['pos'] < 8 else '8+', ('1', '2', '3', '4', '5', '6', '7', '8+')),
    ('body length (chars)', lambda r: bucket(r['body_len'], (400, 800, 1200), ('<400', '400-800', '800-1200', '>1200')), ('<400', '400-800', '800-1200', '>1200')),
    ('Reversible line', lambda r: 'yes' if r['has_rev'] else 'no', ('yes', 'no')),
    ('lettered options', lambda r: 'yes' if r['has_opts'] else 'no', ('yes', 'no')),
    ('options count', lambda r: bucket(r['n_opts'], (1, 3, 4), ('0', '2', '3', '4+')), ('0', '2', '3', '4+')),
    ('shape', lambda r: 'new (Recommended line)' if r['new_shape'] else 'old', ('new (Recommended line)', 'old')),
]
for name, kf, order in cuts:
    P('**%s**' % name)
    P('| %s | items | answered (strict) | answered (memo) | overruled of kept+overruled |' % name)
    P('| --- | --- | --- | --- | --- |')
    g = collections.defaultdict(list)
    for r in oi:
        g[kf(r)].append(r)
    for k in order:
        v = g.get(k, [])
        if not v:
            continue
        a = sum(r['answered'] for r in v)
        m = sum(r['memo_ans'] for r in v)
        ko = sum(1 for r in v if r['kept'] == 'kept')
        ov = sum(1 for r in v if r['kept'] == 'overruled')
        P('| %s | %d%s | %s | %s | %d/%d (%s)%s |' % (k, len(v), ' †' if len(v) < 10 else '', pct(a, len(v)), pct(m, len(v)), ov, ko + ov, pct(ov, ko + ov), ' †' if ko + ov < 10 else ''))
    P()
P('within-doc: among docs with >= 1 answer and >= 4 items, share where the answered items are a prefix of the list (answered D1..Dk, none after)')
pre = tot = 0
for key in {r['key'] for r in oi}:
    its = sorted([r for r in oi if r['key'] == key], key=lambda r: r['pos'])
    a = [r['answered'] for r in its]
    if len(its) >= 4 and sum(a) >= 1 and sum(a) < len(a):
        tot += 1
        k = sum(a)
        pre += int(all(a[:k]))
P('partially answered docs with >= 4 items: %d; answered items form a prefix: %d' % (tot, pre))
P()
# corpus
corp = [json.loads(l) for l in open(os.path.join(UD, 'bench/decisions/corpus.jsonl'))]
P('### Corpus (2026-10-02, %d items; %d known) - kind counts' % (len(corp), sum(c['known'] for c in corp)))
P(str(dict(collections.Counter(c['kind'] for c in corp))))
kn = [c for c in corp if c['known']]
for name, kf, order in [
    ('body length', lambda c: bucket(len(c['body'] or ''), (400, 800, 1200), ('<400', '400-800', '800-1200', '>1200')), ('<400', '400-800', '800-1200', '>1200')),
    ('has_options', lambda c: 'yes' if c['has_options'] else 'no', ('yes', 'no')),
    ('repo', lambda c: c['repo'], None),
    ('item id n', lambda c: 'D1' if c['id'] == 'D1' else 'later', ('D1', 'later')),
]:
    g = collections.defaultdict(list)
    for c in kn:
        g[kf(c)].append(c)
    P('| %s | known items | touched (y_touched) | overruled (y_override) |' % name)
    P('| --- | --- | --- | --- |')
    for k in (order or sorted(g)):
        v = g.get(k, [])
        if v:
            P('| %s | %d%s | %s | %d (%s) |' % (k, len(v), ' †' if len(v) < 10 else '', pct(sum(c['y_touched'] for c in v), len(v)), sum(c['y_override'] for c in v), pct(sum(c['y_override'] for c in v), len(v))))
    P()
P()

# ------------------------------------------------------------------ time
P('## D. Time to first answer')
tm = [r for r in D if r['hrs'] is not None and r['ans_src'] in ('git', 'tr')]
P('docs with a timed first answer (source git or transcript): %d; sources %s' % (len(tm), dict(collections.Counter(r['ans_src'] for r in tm))))
hs = sorted(r['hrs'] for r in tm)


def q(xs, p):
    if not xs:
        return None
    k = (len(xs) - 1) * p
    f = int(k)
    return xs[f] + (xs[min(f + 1, len(xs) - 1)] - xs[f]) * (k - f)


if hs:
    P('hours to first answer: p10 %.1f | p25 %.1f | median %.1f | p75 %.1f | p90 %.1f | max %.1f' % (q(hs, .1), q(hs, .25), q(hs, .5), q(hs, .75), q(hs, .9), hs[-1]))
    P('within 1 h %d | within 24 h %d | 24 h - 3 d %d | > 3 d %d  (of %d timed)' % (
        sum(h <= 1 for h in hs), sum(h <= 24 for h in hs), sum(24 < h <= 72 for h in hs), sum(h > 72 for h in hs), len(hs)))
P('all docs by outcome: timed answer %d | answered but untimable (squashed/untracked) %d | never answered, older than 3 d %d | never answered, <= 3 d %d' % (
    len(tm), sum(1 for r in D if r['items_answered'] > 0 and not (r['hrs'] is not None and r['ans_src'] in ('git', 'tr'))),
    sum(1 for r in D if r['items_answered'] == 0 and r['age'] > 3), sum(1 for r in D if r['items_answered'] == 0 and r['age'] <= 3)))
P()
# stand counterfactual: docs whose hand-over is > 24 h ago with no answer in the first 24 h
stand = [r for r in D if (r['items_answered'] == 0 and r['age'] > 1) or (r['hrs'] is not None and r['ans_src'] in ('git', 'tr') and r['hrs'] > 24)]
P('24 h stand counterfactual: docs that had no the owner answer 24 h after hand-over (timed late answers + never answered, hand-over > 24 h ago): %d' % len(stand))
late = [r for r in stand if r['items_answered'] > 0]
P('  of these, answered later: %d docs, %d items answered later, of which overruled (new-shape letter/word differs): %d, kept: %d' % (
    len(late), sum(r['items_answered'] for r in late), sum(r['overruled'] for r in late), sum(r['kept'] for r in late)))
P('  never answered: %d docs (%d D-items)' % (sum(1 for r in stand if r['items_answered'] == 0), sum(r['d_items'] for r in stand if r['items_answered'] == 0)))
P('  `memo stand --apply` actually run: see stood.py (1 doc, 220-claudia agentic-build, 9 items, 2026-10-14)')
P()

# ------------------------------------------------------------------ build
P('## E. Build marker')
ans_docs = [r for r in D if r['items_answered'] > 0]
bl = [r for r in ans_docs if r['has_built']]
P('docs with >= 1 answer %d; with a `**Built` marker %d (%s)' % (len(ans_docs), len(bl), pct(len(bl), len(ans_docs))))
bd = sorted(r['bd'] for r in bl if r['bd'] is not None)
P('days to first Built marker (docs whose history shows it, n=%d): median %s, p25 %s, p75 %s' % (len(bd), '%.1f' % statistics.median(bd) if bd else '-', '%.1f' % q(bd, .25) if bd else '-', '%.1f' % q(bd, .75) if bd else '-'))
P('answered docs older than 7 days: %d, with Built %d (%s); %s' % (
    sum(1 for r in ans_docs if r['age'] > 7), sum(1 for r in ans_docs if r['age'] > 7 and r['has_built']),
    pct(sum(1 for r in ans_docs if r['age'] > 7 and r['has_built']), sum(1 for r in ans_docs if r['age'] > 7)),
    'Built marker is the exception, not the rule: most builds are recorded elsewhere (TODO, commit messages)'))
P('| arch | n answered docs | with Built |')
P('| --- | --- | --- |')
for k, v in (('architect', [r for r in ans_docs if r['architect']]), ('not', [r for r in ans_docs if not r['architect']])):
    P('| %s | %d | %s |' % (k, len(v), cell(sum(r['has_built'] for r in v), len(v)).replace(' (', ' (', 1)))
P()
full = sorted([r for r in D if r['d_items'] > 0 and r['items_answered'] == r['d_items']], key=lambda r: -r['d_items'])[:5]
P('five docs with the most D-items, fully answered (strict):')
for r in full:
    P('  - %s %s: %d D, %d words, %s' % (r['key'], r['handover'][:10], r['d_items'], r['words'], r['review']))
nev = sorted([r for r in old if r['items_answered'] == 0], key=lambda r: -r['d_items'])[:8]
P('never-answered docs older than 3 days, most D-items first (top 8; the report names five):')
for r in nev:
    P('  - %s %s: %d D, %d words, age %.0f d, arch=%d, %s' % (r['key'], r['handover'][:10], r['d_items'], r['words'], r['age'], r['architect'], r['review']))
P()

# ------------------------------------------------------------------ extras on the clean population
P('## H. New-shape docs older than 3 days (the clean population: an empty box means unanswered)')
nw = [r for r in D if int(r['new_shape']) > 0 and r['age'] > 3]
full = [r for r in nw if r['items_answered'] == r['d_items']]
part = [r for r in nw if 0 < r['items_answered'] < r['d_items']]
none = [r for r in nw if r['items_answered'] == 0]
P('docs %d: fully answered %d (%s) | partly %d (%s) | none %d (%s)' % (len(nw), len(full), pct(len(full), len(nw)), len(part), pct(len(part), len(nw)), len(none), pct(len(none), len(nw))))
P('items in docs: fully answered docs %d items; partly %d docs hold %d items of which %d answered' % (sum(r['d_items'] for r in full), len(part), sum(r['d_items'] for r in part), sum(r['items_answered'] for r in part)))
P('| age of doc | docs | none answered | fully | partly |')
P('| --- | --- | --- | --- | --- |')
for lab, lo, hi in (('3-7 d', 3, 7), ('7-14 d', 7, 14), ('14+ d', 14, 999)):
    v = [r for r in nw if lo < r['age'] <= hi]
    P('| %s | %d%s | %s | %s | %s |' % (lab, len(v), ' †' if len(v) < 10 else '', cell(sum(1 for r in v if r['items_answered'] == 0), len(v)),
                                     pct(sum(1 for r in v if r['items_answered'] == r['d_items']), len(v)), pct(sum(1 for r in v if 0 < r['items_answered'] < r['d_items']), len(v))))
P()
P('review status word, all docs: %s' % dict(collections.Counter(r['review'].split()[0].rstrip(',') for r in D)))
P('review status word, new-shape docs: %s' % dict(collections.Counter(r['review'].split()[0].rstrip(',') for r in D if int(r['new_shape']) > 0)))
P()
P('### Timing by source (hours from hand-over to first answer)')
for src in ('git', 'tr'):
    hs_ = sorted(r['hrs'] for r in D if r['ans_src'] == src and r['hrs'] is not None)
    z = sum(1 for r in D if r['ans_src'] == src and r['hrs'] == 0.0)
    if hs_:
        P('%s: n=%d | p25 %.1f | median %.1f | p75 %.1f | p90 %.1f | max %.1f | clamped to 0 (answer stamped before the link) %d | within 24 h %d | 24 h-3 d %d | > 3 d %d' % (
            src, len(hs_), q(hs_, .25), q(hs_, .5), q(hs_, .75), q(hs_, .9), hs_[-1], z, sum(h <= 24 for h in hs_), sum(24 < h <= 72 for h in hs_), sum(h > 72 for h in hs_)))
P('git = first commit in the doc\'s own history that adds an answer, hand-over = first link in a transcript or the first commit: reliable when the history survives (57 docs have >= 2 commits).')
P('tr = first answer-like the owner turn in the session that showed the link: an upper bound on speed (the turn may answer something else), and a lower bound on slowness (a form answer saved later is missed).')
P()
P('### 24 h stand counterfactual, new-shape docs only (the only docs `stand` can act on)')
nw_all = [r for r in D if int(r['new_shape']) > 0 and r['age'] > 1]
timed_ok = [r for r in nw_all if r['hrs'] is not None and r['ans_src'] in ('git', 'tr') and r['hrs'] <= 24]
timed_late = [r for r in nw_all if r['hrs'] is not None and r['ans_src'] in ('git', 'tr') and r['hrs'] > 24]
untimed = [r for r in nw_all if r['items_answered'] > 0 and (r['hrs'] is None or r['ans_src'] not in ('git', 'tr')) ]
nonev = [r for r in nw_all if r['items_answered'] == 0]
P('new-shape docs handed over > 24 h ago: %d | first answer <= 24 h (timed): %d | first answer later (timed): %d | answered, time unknown: %d | never answered: %d (%d D-items)' % (
    len(nw_all), len(timed_ok), len(timed_late), len(untimed), len(nonev), sum(r['d_items'] for r in nonev)))
P('`stand` would have applied to the %d late + %d never docs = %d docs, %d D-items (of %d)' % (len(timed_late), len(nonev), len(timed_late) + len(nonev), sum(r['d_items'] for r in timed_late + nonev), sum(r['d_items'] for r in nw_all)))
P('  the late docs, once answered: %d items answered, kept %d, overruled %d (letter/word comparison) -> overruled share %s' % (
    sum(r['items_answered'] for r in timed_late), sum(r['kept'] for r in timed_late), sum(r['overruled'] for r in timed_late), pct(sum(r['overruled'] for r in timed_late), sum(r['kept'] + r['overruled'] for r in timed_late))))
P('  all new-shape answered docs for comparison: kept %d, overruled %d -> %s' % (sum(r['kept'] for r in nw_all), sum(r['overruled'] for r in nw_all), pct(sum(r['overruled'] for r in nw_all), sum(r['kept'] + r['overruled'] for r in nw_all))))
P()
P('### Build proxy: commits in the repo (any branch) naming the doc file, not touching it, subject not "Docs/Memo"')
for lab, v in (('new-shape, >= 1 item answered', [r for r in nw if r['items_answered'] > 0]), ('new-shape, none answered', none),
               ('old-shape, memo-answered', [r for r in D if int(r['new_shape']) == 0 and r['age'] > 3 and r['memo_answered'] > 0])):
    b = [r for r in v if int(r['refs_nondoc']) > 0]
    b2 = [r for r in v if int(r['refs_2h']) > 0]
    b24 = [r for r in v if int(r['refs_24h']) > 0]
    P('%s: %d docs%s | any such commit %d (%s) | one > 2 h after hand-over %d (%s) | one > 24 h after hand-over %d (%s)' % (
        lab, len(v), ' †' if len(v) < 10 else '', len(b), pct(len(b), len(v)), len(b2), pct(len(b2), len(v)), len(b24), pct(len(b24), len(v))))
P()
none_new = sorted([r for r in none if r['memo_answered'] == 0], key=lambda r: -r['d_items'])
P('never-answered new-shape docs older than 3 days (no memo.answered either): %d; five largest by D-items:' % len(none_new))
for r in none_new[:5]:
    P('  - %s %s: %d D, %d words, age %.0f d, arch=%d, %s, build-refs %s' % (r['key'], r['handover'][:10], r['d_items'], r['words'], r['age'], r['architect'], r['review'], r['refs_nondoc']))
P()
P('### Hypotheses from reading the ten heads: what opens the doc (new-shape docs older than 3 days; heuristics, regex on the first 14 / 40 lines)')
P('| cut | n | none answered | fully answered |')
P('| --- | --- | --- | --- |')
for lab, f in (('opens with the owner\'s own words / ask / "from a chat"', lambda r: r['owner_ask'] == '1'),
               ('does not', lambda r: r['owner_ask'] != '1'),
               ('a clock in the first 40 lines (today, before 10:00, premiere ...)', lambda r: r['clock'] == '1'),
               ('no clock', lambda r: r['clock'] != '1'),
               ('"Do this now" longer than 6 lines', lambda r: int(r['do_now_lines']) > 6),
               ('"Do this now" 1-6 lines', lambda r: 0 < int(r['do_now_lines']) <= 6),
               ('no "Do this now"', lambda r: int(r['do_now_lines']) == 0)):
    v = [r for r in nw if f(r)]
    P('| %s | %d%s | %s | %s |' % (lab, len(v), ' †' if len(v) < 10 else '', cell(sum(1 for r in v if r['items_answered'] == 0), len(v)),
                                 pct(sum(1 for r in v if r['items_answered'] == r['d_items']), len(v))))
P()
P('medians, new-shape docs older than 3 days: words fully answered %d (n=%d) | partly %d (n=%d) | none %d (n=%d); D-items %.0f | %.0f | %.0f' % (
    statistics.median([r['words'] for r in full]), len(full), statistics.median([r['words'] for r in part]), len(part),
    statistics.median([r['words'] for r in none]), len(none),
    statistics.median([r['d_items'] for r in full]), statistics.median([r['d_items'] for r in part]), statistics.median([r['d_items'] for r in none])))
ni_ = [r for r in I if r['new_shape'] and r['answered']]
kc_ = collections.Counter(r['kept'] for r in ni_)
P('new-shape items answered (all ages): %d -> kept %d (%s), overruled %d (%s), free text matching neither (other) %d (%s), box empty but settled by a reply/note (na) %d' % (
    len(ni_), kc_['kept'], pct(kc_['kept'], len(ni_)), kc_['overruled'], pct(kc_['overruled'], len(ni_)), kc_['other'], pct(kc_['other'], len(ni_)), kc_['na']))
P('| new-shape docs > 3 d by D-items | n | none | partly | fully | answered items / items |')
P('| --- | --- | --- | --- | --- | --- |')
for lab, lo, hi in (('<=3', 0, 4), ('4-7', 4, 8), ('>=8', 8, 99)):
    v = [r for r in nw if lo <= r['d_items'] < hi]
    P('| %s | %d%s | %d | %d | %d | %s |' % (lab, len(v), ' †' if len(v) < 10 else '', sum(1 for r in v if r['items_answered'] == 0), sum(1 for r in v if 0 < r['items_answered'] < r['d_items']),
                                          sum(1 for r in v if r['items_answered'] == r['d_items']), pct(sum(r['items_answered'] for r in v), sum(r['d_items'] for r in v))))
P('| new-shape docs > 3 d by words | n | none | partly | fully | answered items / items |')
P('| --- | --- | --- | --- | --- | --- |')
for lab, lo, hi in (('<2,000', 0, 2000), ('2,000-5,000', 2000, 5001), ('>5,000', 5001, 10 ** 9)):
    v = [r for r in nw if lo <= r['words'] < hi]
    P('| %s | %d%s | %d | %d | %d | %s |' % (lab, len(v), ' †' if len(v) < 10 else '', sum(1 for r in v if r['items_answered'] == 0), sum(1 for r in v if 0 < r['items_answered'] < r['d_items']),
                                          sum(1 for r in v if r['items_answered'] == r['d_items']), pct(sum(r['items_answered'] for r in v), sum(r['d_items'] for r in v))))
P('hours to first answer (timed docs, git+transcript) by words:')
for lab, lo, hi in (('<2,000', 0, 2000), ('2,000-5,000', 2000, 5001), ('>5,000', 5001, 10 ** 9)):
    v = sorted(r['hrs'] for r in D if r['hrs'] is not None and r['ans_src'] in ('git', 'tr') and lo <= r['words'] < hi)
    P('  %s: n=%d%s median %s p75 %s' % (lab, len(v), ' †' if len(v) < 10 else '', '%.1f' % q(v, .5) if v else '-', '%.1f' % q(v, .75) if v else '-'))
P('hours to first answer by D-items:')
for lab, lo, hi in (('<=3', 0, 4), ('4-7', 4, 8), ('>=8', 8, 99)):
    v = sorted(r['hrs'] for r in D if r['hrs'] is not None and r['ans_src'] in ('git', 'tr') and lo <= r['d_items'] < hi)
    P('  %s: n=%d%s median %s p75 %s' % (lab, len(v), ' †' if len(v) < 10 else '', '%.1f' % q(v, .5) if v else '-', '%.1f' % q(v, .75) if v else '-'))
open(os.path.join(DATA, 'tables.md'), 'w').write('\n'.join(out))
