#!/usr/bin/env python3
"""Per-doc and per-item facts for every doc `memo list` knows (Python 3.9, stdlib only).

Run order: `python3 tindex.py` (transcript index, ~1 min), `python3 docs.py`, `python3 analyze.py`.
Reads list.json (`memo list --limit 400 --json`, refreshed here), git history of each doc, the doc text at
every commit that touched it, tindex.json. Writes docs.csv and items.csv beside this file.

Definitions (all approximate; the report repeats them):
 - hand-over: first transcript assistant message that names the doc AND carries a link marker (127.0.0.1,
   github.com, spacesheep, 'memo line'); else the first commit when the doc has >= 2 commits; else the date in
   the file name; else the only commit.  `ho_src` says which.
 - squashed: a doc with one commit, or whose first commit already carries an answer.  /finish folds the doc and
   the owner's answers into one commit, so git cannot time them; transcripts are the fallback (`ans_src`).
 - item answered (by the owner): answer box non-empty (not a yolo pick), or a settling reply (> **Done./Applied./
   Superseded./Revised./Checked.**, not 'Applied. Stood'), or an `**the owner, <date>:**` / `> the owner (<date>)` note
   under it.  An old-shape answer that equals the first commit's text is a pre-fill, not an answer.
 - kept / overruled: new-shape items compare the first word or letter of answer and Recommended; 'other' is free
   text that matches neither.  Old-shape items have no Recommended line: na.
"""
import csv, datetime as dt, importlib.machinery, importlib.util, json, os, re, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import _regatta  # noqa: E402  keel through the core's tool() (G37)
DATA = os.environ.get("BENCH") or _regatta.data("docs")  # data outside git, like bench/decisions
os.makedirs(DATA, exist_ok=True)
MEMO = _regatta.need('keel')
ldr = importlib.machinery.SourceFileLoader('memo', MEMO)
spec = importlib.util.spec_from_loader('memo', ldr)
memo = importlib.util.module_from_spec(spec)
ldr.exec_module(memo)
# keel's scrub renamed the owner's reply pattern OWNER_REPLY_RE; a keel from before it has the old,
# owner-named attribute, found by its suffix so either landing order works.
OWNER_REPLY_RE = getattr(memo, 'OWNER_REPLY_RE', None) or next(
    getattr(memo, n) for n in dir(memo)
    if n.endswith('_REPLY_RE') and n.split('_')[0] not in ('SETTLE', 'STOOD', 'OWNER'))
TODAY = dt.datetime(2026, 10, 14, 23, 59, tzinfo=dt.timezone(dt.timedelta(hours=-7)))


def run(*a):
    return subprocess.run(list(a), capture_output=True, text=True).stdout


# refresh the list
lst = json.loads(run('python3', MEMO, 'list', '--limit', '400', '--json'))
json.dump(lst, open(os.path.join(DATA, 'list.json'), 'w'))
tix = json.load(open(os.path.join(DATA, 'tindex.json')))
MENT, TURNS = tix['mentions'], tix['turns']


def pt(s):
    if not s:
        return None
    s = s.replace('Z', '+00:00')
    try:
        d = dt.datetime.fromisoformat(s)
    except ValueError:
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=dt.timezone.utc)
    return d


REPLY_KIND_RE = re.compile(r'^\s*>\s*\*\*(Done|Applied|Built|Recorded|Superseded|Revised|Checked|Accepted)\b')
BUILT_RE = re.compile(r'\*\*Built\b')
LETTER_RE = re.compile(r'^[*_`(]*([A-Z])\b')
WORD_RE = re.compile(r'^[*_`(~]*([A-Za-z]+)')
YES = {'yes', 'ok', 'okay', 'agree', 'agreed', 'accept', 'accepted', 'approved', 'approve', 'go', 'recommended', 'as', 'confirmed', 'fine', 'sure', 'yep', 'yeah'}
FAM_RE = re.compile(r'(?<![\w<])([A-Z])\s?(?:<n>|\d)')


def legend_of(lines):
    for i, l in enumerate(lines[:120]):
        m = re.match(r'^\s*(?:#{1,6}\s+)?\**legend\b', l, re.I)
        if m:
            # the legend line plus what follows: stop at a heading or rule; a blank line ends it once ids were seen
            buf = [l]
            started = bool(FAM_RE.search(l))
            for k in range(i + 1, min(i + 15, len(lines))):
                s = lines[k]
                if s.startswith('#') or s.strip() == '---':
                    break
                if not s.strip():
                    if started:
                        break
                    continue
                buf.append(s)
                started = started or bool(FAM_RE.search(s))
            return '\n'.join(buf)
    return None


def families(text):
    return sorted({m.group(1) for m in FAM_RE.finditer(text or '')})


def item_state(it, lines, nxt, base_ans):
    """flags for one item at one version; base_ans = the first version's answer text (or None)."""
    span = lines[it['start']:nxt]
    ans = (it['answer'] or '').strip()
    yolo = bool(memo.YOLO_ANSWER_RE.match(ans)) if ans else False
    stood = any(memo.STOOD_REPLY_RE.match(l) for l in span)
    settle = any(memo.SETTLE_REPLY_RE.match(l) and not memo.STOOD_REPLY_RE.match(l) for l in span)
    note = any(memo.NOTE_RE.match(l) or OWNER_REPLY_RE.match(l) for l in span)
    prefill = bool(ans) and base_ans is not None and ans == base_ans.strip() and it['recommended'] is None
    box = bool(ans) and not yolo and not prefill
    return dict(ans=ans, yolo=yolo, stood=stood, settle=settle, note=note, box=box,
                answered=box or settle or note,
                replies=sum(1 for l in span if REPLY_KIND_RE.match(l)))


def kept_state(it, ans):
    rec = (it['recommended'] or '').strip()
    if not rec or not ans:
        return 'na'
    if memo.ACCEPT_ALL_RE.match(ans):
        return 'kept'
    ra, aa = LETTER_RE.match(rec), LETTER_RE.match(ans)
    if ra and aa and len(ans) > 0 and (re.match(r'^[*_`(]*[A-Z](?![A-Za-z])', ans)):
        return 'kept' if ra.group(1) == aa.group(1) else 'overruled'
    rw, aw = WORD_RE.match(rec), WORD_RE.match(ans)
    if rw and aw:
        r, a = rw.group(1).lower(), aw.group(1).lower()
        if r == a:
            return 'kept'
        if r in ('yes', 'no') and a in ('yes', 'no') and r != a:
            return 'overruled'
        if r == 'no' and a in YES and a not in ('as', 'recommended'):
            return 'overruled'
        if a in YES:
            return 'kept'   # "Approved", "yes, sounds good", "as recommended" against a lettered or other pick
    return 'other'


rows, irows = [], []
for x in lst:
    p = x['path']
    dn, fn = os.path.dirname(p), os.path.basename(p)
    try:
        text = open(p).read()
    except OSError:
        continue
    try:
        lines, items, fb = memo.parse(text)
    except Exception as e:
        print('parse fail', p, e, file=sys.stderr)
        continue
    # ---- history
    out = run('git', '-C', dn, 'log', '--follow', '--format=\x01%H\t%aI', '--name-only', '--', fn)
    commits = []
    for rec in out.split('\x01')[1:]:
        hd, *rest = rec.strip().split('\n')
        sha, ad = hd.split('\t')
        path_at = next((r for r in rest if r.strip()), fn)
        commits.append((sha, pt(ad), path_at))
    commits.reverse()  # oldest first
    # parse each version
    versions = []
    for sha, ad, pa in commits:
        t = run('git', '-C', dn, 'show', '%s:%s' % (sha, pa))
        try:
            vl, vi, _ = memo.parse(t)
        except Exception:
            versions.append((ad, None, None, t)); continue
        versions.append((ad, vl, vi, t))
    base = {}
    if versions and versions[0][2] is not None:
        base = {it['id']: (it['answer'] or '') for it in versions[0][2]}
    first_ans_dt, first_ans_idx, built_dt = None, None, None
    per_version = []
    for vi_idx, (ad, vl, vit, t) in enumerate(versions):
        if vit is None:
            per_version.append(0); continue
        n_ans = 0
        for k, it in enumerate(vit):
            nxt = vit[k + 1]['start'] if k + 1 < len(vit) else len(vl)
            st = item_state(it, vl, nxt, base.get(it['id']) if vi_idx > 0 else None)
            # first version: baseline is itself; only replies/notes/new-shape boxes count
            if vi_idx == 0:
                st['answered'] = (bool(st['ans']) and it['recommended'] is not None and not st['yolo']) or st['settle'] or st['note']
            n_ans += st['answered']
        per_version.append(n_ans)
        if n_ans and first_ans_idx is None:
            first_ans_idx, first_ans_dt = vi_idx, ad
        if built_dt is None and BUILT_RE.search(t or ''):
            built_dt = (vi_idx, ad)
    n_commits = len(commits)
    first_commit_dt = commits[0][1] if commits else None
    last_commit_dt = commits[-1][1] if commits else None
    # ---- head items
    ids = [it['id'] for it in items]
    states = []
    for k, it in enumerate(items):
        nxt = items[k + 1]['start'] if k + 1 < len(items) else len(lines)
        st = item_state(it, lines, nxt, base.get(it['id']) if n_commits > 1 else None)
        if n_commits <= 1 or (versions and versions[0][2] is not None and first_ans_idx == 0):
            # squashed: an old-shape answer box alone cannot be told from a pre-fill -> only count evidence
            if it['recommended'] is None:
                st['answered'] = st['settle'] or st['note']
        st['kept'] = kept_state(it, st['ans']) if st['answered'] and st['box'] else ('na' if not st['answered'] else 'na')
        states.append(st)
    n_items = len(items)
    n_ans = sum(s['answered'] for s in states)
    kept = sum(1 for s in states if s['kept'] == 'kept')
    over = sum(1 for s in states if s['kept'] == 'overruled')
    n_stood = sum(s['stood'] for s in states)
    memo_ans = sum(1 for it in items if memo.answered(it, lines))
    n_new = sum(1 for it in items if it['recommended'] is not None)
    # ---- shape
    by = memo.written_by(lines)
    leg = legend_of(lines)
    fam_leg = families(leg) if leg else []
    defined = sorted({m.group(1)[0] for l in lines for m in [memo.DEF_RE.match(l)] if m})
    words = len(text.split())
    head14 = '\n'.join(lines[:14])
    head40 = '\n'.join(lines[:40])
    owner_ask = int(bool(re.search(r"the owner's (ask|spark|request|words)|the owner,? \d{4}-\d{2}-\d{2}|Asked in chat|From a chat|the owner (asked|wrote|said)|the owner, \d", head14)))
    clock = int(bool(re.search(r"\b(before \d{1,2}[:.]?\d{0,2}|today|tonight|this (morning|evening)|by (tomorrow|monday|tuesday|wednesday|thursday|friday|sunday)|premiere|deadline)\b", head40, re.I)))
    n_do_now_lines = 0
    mdn = re.search(r'^#{1,6}\s*(?:\d+\.?\s*)?Do this now.*?(?=^#{1,6}\s|\Z)', text, re.M | re.S | re.I)
    if mdn:
        n_do_now_lines = len([l for l in mdn.group(0).split('\n') if l.strip()]) - 1
    replies = sum(1 for l in lines if REPLY_KIND_RE.match(l))
    owner_notes = sum(1 for l in lines if memo.NOTE_RE.match(l) or OWNER_REPLY_RE.match(l))
    # ---- hand-over and first answer
    m_ = MENT.get(fn, [])
    # a mention belongs to this doc when its time is after the file's first commit minus 30 days; the name
    # is the key, so same-named docs in two repos could collide (rare; dated names are unique)
    links = sorted(pt(a[0]) for a in m_ if a[2] == 'link' and pt(a[0]))
    writes = sorted(pt(a[0]) for a in m_ if a[2] == 'write' and pt(a[0]))
    name_date = None
    mm = re.search(r'(\d{4}-\d{2}-\d{2})\.md$', fn)
    if mm:
        name_date = dt.datetime.fromisoformat(mm.group(1)).replace(tzinfo=dt.timezone(dt.timedelta(hours=-7)), hour=12)
    if links:
        ho, ho_src = links[0], 'link'
    elif n_commits >= 2:
        ho, ho_src = first_commit_dt, 'git'
    elif name_date:
        ho, ho_src = name_date, 'name'
    else:
        ho, ho_src = first_commit_dt, 'git1'
    squashed = n_commits <= 1 or first_ans_idx == 0
    ans_dt, ans_src = None, 'none'
    if first_ans_idx is not None and not squashed:
        ans_dt, ans_src = first_ans_dt, 'git'
    elif n_ans:
        # transcripts: first the owner turn after the link in the session that showed it, answer-like
        cand = [a for a in m_ if a[2] == 'link' and pt(a[0])]
        cand.sort(key=lambda a: pt(a[0]))
        for a in cand[:3]:
            t0 = pt(a[0])
            for ts, txt in TURNS.get(a[1], []):
                d = pt(ts)
                if txt.startswith(('Another Claude session', 'Base directory for this skill', '[Cross-session', '<cross-session')):
                    continue   # another session's note or a skill body, not the owner's words
                if d and d > t0 and re.search(r'\bD\d+\b|\brespond|^\W*(go|yes|ok|okay|accept\w*|approved?|agree\w*|all approved|answered|done)\b|\brecommend', txt, re.I) \
                        and not re.search(r"can't answer|cannot answer|not answer", txt, re.I):
                    ans_dt, ans_src = d, 'tr'
                    break
            if ans_dt:
                break
        if not ans_dt and first_ans_dt and first_ans_idx is not None:
            ans_dt, ans_src = first_ans_dt, 'git-squashed'
    hrs = None
    if ans_dt and ho:
        hrs = round((ans_dt - ho).total_seconds() / 3600.0, 1)
        if hrs < 0 and ans_src != 'git-squashed':
            hrs = 0.0
    age_days = round((TODAY - ho).total_seconds() / 86400.0, 1) if ho else None
    built_days = None
    if built_dt and not squashed and ho:
        built_days = round((built_dt[1] - ho).total_seconds() / 86400.0, 1)
    # ---- build proxy: commits anywhere in the repo whose message names this file, not touching it
    own = {c[0] for c in commits}
    refs = []
    for l in run('git', '-C', dn, 'log', '--all', '--format=%H\t%aI\t%s', '-F', '--grep=' + fn).splitlines():
        parts = l.split('\t', 2)
        if len(parts) == 3 and parts[0] not in own and pt(parts[1]):
            refs.append((pt(parts[1]), parts[2]))
    refs.sort()
    nondocs = [r_ for r_ in refs if not re.match(r'(Docs?|Memo|Doc)\b', r_[1], re.I)]
    ref_days = ''
    refs_2h = refs_24h = 0
    if nondocs and ho:
        ref_days = round((nondocs[0][0] - ho).total_seconds() / 86400.0, 1)
        refs_2h = sum(1 for r_ in nondocs if (r_[0] - ho).total_seconds() > 2 * 3600)
        refs_24h = sum(1 for r_ in nondocs if (r_[0] - ho).total_seconds() > 24 * 3600)
    nrepo = re.sub(r'@.*', '', x['repo'])
    key = '%s:%s' % (nrepo, fn)
    rows.append(dict(
        key=key, repo=nrepo, wt=int('@' in x['repo']), file=fn, path=p, words=words, d_items=n_items,
        opts_mean=round(sum(len(it['options']) for it in items) / n_items, 2) if n_items else 0,
        new_shape=n_new, architect=int(bool(by)),
        do_now=int(bool(re.search(r'do this now', text, re.I))),
        one_para=int(bool(re.search(r'the decision in one paragraph', text, re.I))),
        legend=int(bool(leg)), fam_legend=len(fam_leg), fam_defined=len(defined),
        families=''.join(fam_leg), n_commits=n_commits, squashed=int(squashed),
        handover=ho.isoformat() if ho else '', ho_src=ho_src, ans_src=ans_src,
        first_answer=ans_dt.isoformat() if ans_dt else '', hrs_to_answer=hrs if hrs is not None else '',
        items_answered=n_ans, memo_answered=memo_ans, frac_answered=round(n_ans / n_items, 2) if n_items else 0,
        kept=kept, overruled=over, frac_kept=round(kept / n_ans, 2) if n_ans else '',
        stood_items=n_stood, replies=replies, owner_notes=owner_notes,
        owner_ask=owner_ask, clock=clock, do_now_lines=n_do_now_lines, has_built=int(bool(BUILT_RE.search(text))), refs=len(refs), refs_nondoc=len(nondocs), refs_2h=refs_2h, refs_24h=refs_24h, ref_days=ref_days, built_days=built_days if built_days is not None else '',
        review=x['review'], age_days=age_days, modified=x['modified'], title=x['title'][:90]))
    for k, it in enumerate(items):
        st = states[k]
        span = '\n'.join(lines[it['start']:(items[k + 1]['start'] if k + 1 < n_items else len(lines))])
        irows.append(dict(
            key=key, id=it['id'], pos=k + 1, n=n_items, last=int(k == n_items - 1),
            body_len=len(it['body'] or ''), has_rev=int(bool(re.search(r'^\s*(?:[-*]\s+)?[*_]*Reversible', span, re.M | re.I))),
            has_opts=int(bool(it['options'])), n_opts=len(it['options']), new_shape=int(it['recommended'] is not None),
            answered=int(st['answered']), memo_ans=int(memo.answered(it, lines)), stood_touched=int(st['stood'] and (st['box'] or st['note'])), kept=st['kept'], stood=int(st['stood']), yolo=int(st['yolo']),
            ho_src=ho_src, squashed=int(squashed), age_days=age_days))

rows.sort(key=lambda r: r['handover'])
with open(os.path.join(DATA, 'docs.csv'), 'w', newline='') as f:
    w = csv.DictWriter(f, list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)
with open(os.path.join(DATA, 'items.csv'), 'w', newline='') as f:
    w = csv.DictWriter(f, list(irows[0].keys()))
    w.writeheader(); w.writerows(irows)
print(len(rows), 'docs;', len(irows), 'items')
