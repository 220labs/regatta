import json, os, re, collections, datetime
here = os.path.dirname(os.path.abspath(__file__))
allrows = [json.loads(l) for l in open(os.path.join(here, 'prompts.jsonl'))]
human = [json.loads(l) for l in open(os.path.join(here, 'human.jsonl'))]

def wk(t):
    d = datetime.date.fromisoformat(t[:10])
    y, w, _ = d.isocalendar()
    mon = d - datetime.timedelta(days=d.weekday())
    return str(mon)

docpat = re.compile(r'design doc|design document|\bdocs/[\w./-]*-20\d\d-\d\d-\d\d\.md|\bmemo\b|\bD\d{1,2}\b|\bthe doc\b|proposal', re.I)
chat = re.compile(r'^(D\d+[\s:.,\-–]|D\d+$|approved|all approved|go[,.! ]*$|accept all|as recommended|yes[,.! ]*$|ok[,.! ]*$|your proposal approved|i like your recommendation|good, go with recommendations|D\d.*approved|Answering your earlier question)', re.I)
dchat = re.compile(r'\bD\d{1,2}\b.*(approved|ok|yes|agree|no\b|as recommended)|approved|as recommended|accept all|Answering your earlier question|I like your recommendation|go with recommendations', re.I)
resp = re.compile(r'^(responded|i have responded|i responded|responded[,!. -]|feedback provided|good job\. responded|added my answers|answered all|I commented|responded to the doc)|\bresponded\b|answers are in|see the doc|I have responded', re.I)

# sessions
sess_all = set(r['s'] for r in allrows)
sess_doc = set(r['s'] for r in human if docpat.search(r['x']))
print('sessions with any user text', len(sess_all), 'human-typed sessions', len(set(r['s'] for r in human)))
print('sessions where the owner-typed prompt mentions design doc/memo/D-n/proposal', len(sess_doc))
sess_dd = set(r['s'] for r in human if re.search(r'design doc|design document|docs/[\w./-]*-20\d\d-\d\d-\d\d\.md', r['x'], re.I))
print('sessions mentioning a design doc (design doc phrase or dated docs/ path)', len(sess_dd))

bw = collections.defaultdict(lambda: [0, 0, 0, 0])
nchat = nresp = 0
chat_ex = []
for r in human:
    x = r['x'].strip()
    if len(x.split()) > 120:
        continue
    w = wk(r['t'])
    bw[w][3] += 1
    if resp.search(x) and len(x.split()) < 40:
        bw[w][1] += 1
        nresp += 1
    elif dchat.search(x) and len(x.split()) < 100 and re.search(r'\bD\d|approved|recommend|accept all|Answering your', x, re.I):
        bw[w][0] += 1
        nchat += 1
    if re.match(r'^(go|go!|done|resum[e]|continue|yes|ok)\W*$', x, re.I):
        bw[w][2] += 1
print('chat-typed answers', nchat, 'responded/see-doc', nresp)
print('week | chat answers | responded | bare go/done/yes | typed prompts <=120w')
for w in sorted(bw):
    print(w, bw[w])
