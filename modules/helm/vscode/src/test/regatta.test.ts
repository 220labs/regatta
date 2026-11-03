import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import {
  Board,
  boardCacheDir,
  boardFileCandidates,
  boardHeadline,
  boardLayout,
  boardMessage,
  cardLink,
  columnTone,
  dItem,
  daysAgo,
  docDay,
  docName,
  helmNotes,
  launchArgs,
  meetingNudge,
  meetingWhen,
  nextCacheStep,
  parseBoard,
  parseMeetings,
  parseNextCache,
  parseNavStatus,
  parseSkippers,
  regattaCandidates,
  stillClaimed,
} from '../regatta';

const NOW = 1_800_000_000_000;
const NOW_S = NOW / 1000;

// A synthetic board in the shape `regatta helm board --json` prints.
function boardJson(over: Record<string, unknown> = {}): string {
  return JSON.stringify({
    kind: 'overview',
    as_of: NOW_S - 60,
    host: 'laptop',
    header: { needs_owner: 5, owner: 'Ada', stalled: 1, week: 'week 40% used (pace 30%), sampled 3 min ago' },
    columns: [
      {
        name: 'Needs Ada',
        cards: [
          { kind: 'ask', column: 'Needs Ada', title: 'Which runner', ref: 'docs/ci-move-2026-01-02.md#D1', repo: 'app', reversible: 'yes', recommended: 'A', course: 'https://spacesheep.dev/@example/ci-move', updated: NOW_S - 3600 },
          { kind: 'ask', column: 'Needs Ada', title: 'Which key', ref: 'docs/ci-move-2026-01-02.md#D2', repo: 'app', reversible: 'no', recommended: 'B', course: 'https://spacesheep.dev/@example/ci-move', updated: NOW_S - 1800 },
          { kind: 'ask', column: 'Needs Ada', title: 'Keep the cache', ref: 'docs/cache.md#D1', repo: 'lib', reversible: 'yes', github: 'https://github.com/example/lib/blob/x/docs/cache.md', updated: NOW_S - 60 },
          { kind: 'stall', column: 'Needs Ada', title: 'build · S3 ended at max lifetime', repo: 'app', rule: 'max lifetime', session: 'sess-stalled', evidence: 'ended 9h', updated: NOW_S - 600 },
          { kind: 'waiting', column: 'Needs Ada', title: 'abcd1234 · waiting on Ada', repo: 'app', branch: 'main', session: 'sess-waiting', url: 'vscode://anthropic.claude-code/open?session=sess-waiting' },
          { kind: 'pr', column: 'Needs Ada', title: '#12 Ready: the parser', repo: 'app', url: 'https://github.com/example/app/pull/12' },
          { kind: 'ask', column: 'Needs Ada', title: 'guarded — open it', guarded: true, repo: 'secret' },
        ],
      },
      { name: 'Needs Sam', cards: [] },
      { name: 'Blocked', cards: [] },
      { name: 'Running', cards: [{ kind: 'pr', column: 'Running', title: '#13 WIP: the lexer', repo: 'app', url: 'https://github.com/example/app/pull/13' }] },
      { name: 'Parked / Relayed', cards: [] },
      { name: 'Done today', cards: [{ kind: 'done', column: 'Done today', title: '#11 Docs', repo: 'app', url: 'https://github.com/example/app/pull/11' }] },
    ],
    timeline: [
      {
        id: 'ship-1',
        plan: 'parser',
        totals: { cost: 1.5, open_asks: 2 },
        bars: [
          { id: 'a', title: 'tokens', status: 'done' },
          { id: 'b', title: 'tree', status: 'running', overrun: true },
          { id: 'c', title: 'docs', status: 'planned' },
        ],
      },
    ],
    ...over,
  });
}


test('regattaCandidates: the setting alone, else PATH, $REGATTA_HOME, the home file', () => {
  assert.deepEqual(regattaCandidates('~/bin/regatta', { REGATTA_HOME: '/r' }, '/h\n'), ['~/bin/regatta']);
  assert.deepEqual(regattaCandidates('', { REGATTA_HOME: '/r/' }, '/h\n'), ['regatta', '/r/modules/regatta/bin/regatta', '/h/modules/regatta/bin/regatta']);
  assert.deepEqual(regattaCandidates('', {}, null), ['regatta']);
  assert.deepEqual(regattaCandidates('', { REGATTA_HOME: '/r' }, '/r'), ['regatta', '/r/modules/regatta/bin/regatta'], 'no duplicate');
});

test('boardCacheDir: the cache dir helm board must write for the board file the setting names', () => {
  assert.equal(boardCacheDir('', '/u'), null, "empty: helm's own default");
  assert.equal(boardCacheDir('  ', '/u'), null);
  assert.equal(boardCacheDir('/c/overview/state.json', '/u'), '/c');
  assert.equal(boardCacheDir('/c//overview/state.json', '/u'), '/c');
  assert.equal(boardCacheDir('~/c/overview/state.json', '/u'), '/u/c', 'a leading ~ is expanded');
  assert.equal(boardCacheDir('/x/board.json', '/u'), false, 'a file helm cannot write');
  assert.equal(boardCacheDir('/c/overview/state.json.bak', '/u'), false);
});

test('boardFileCandidates: the setting, $PLAN_CACHE_DIR, the Mac cache', () => {
  assert.deepEqual(boardFileCandidates('/x.json', {}, '/u'), ['/x.json']);
  assert.deepEqual(boardFileCandidates('~/b.json', {}, '/u'), ['/u/b.json'], 'a leading ~ is expanded');
  assert.deepEqual(boardFileCandidates('', { PLAN_CACHE_DIR: '/c' }, '/u'), ['/c/overview/state.json']);
  assert.deepEqual(boardFileCandidates('', {}, '/u'), ['/u/Library/Caches/plan/overview/state.json']);
});

test('parseBoard reads the header, the columns and the ships', () => {
  const b = parseBoard(boardJson());
  assert.equal(b.owner, 'Ada');
  assert.equal(b.needsOwner, 5);
  assert.equal(b.columns.length, 6);
  assert.equal(b.columns[0].cards[0].kind, 'ask');
  assert.equal(b.columns[0].cards[3].session, 'sess-stalled');
  assert.equal(b.ships[0].name, 'parser');
  assert.equal(b.ships[0].done, 1);
  assert.equal(b.ships[0].openAsks, 2);
  assert.throws(() => parseBoard('nope'), /not JSON/);
  assert.throws(() => parseBoard('{}'), /no columns/);
  assert.equal(parseBoard(JSON.stringify({ columns: [{ name: 'X', cards: [{ kind: 'novel', title: 't' }] }] })).columns[0].cards[0].kind, 'other');
});

test('columnTone: the first is the owner, then by name', () => {
  assert.equal(columnTone('Needs Ada', 0), 'owner');
  assert.equal(columnTone('Needs Sam', 1), 'person');
  assert.equal(columnTone('Blocked', 2), 'blocked');
  assert.equal(columnTone('Running', 3), 'running');
  assert.equal(columnTone('Parked / Relayed', 4), 'parked');
  assert.equal(columnTone('Done today', 5), 'done');
});

test('docName and dItem', () => {
  assert.equal(docName('docs/owner-reach-2026-10-24.md#D2'), 'owner-reach');
  assert.equal(docName('docs/embark/embark-2026-10-25-followup.md'), 'embark-followup');
  assert.equal(docName('README.md'), 'README');
  assert.equal(dItem('docs/x.md#D12'), 'D12');
  assert.equal(dItem('docs/x.md#d3a'), 'D3A');
  assert.equal(dItem('docs/x.md'), null);
});

test('boardLayout: sections in the order they are acted on, one level of rows, newest first', () => {
  const sections = boardLayout(parseBoard(boardJson()), { nowMs: NOW, sessionLabel: (id) => (id === 'sess-waiting' ? 'Fix the login' : null) });
  assert.deepEqual(
    sections.map((s) => [s.label, s.count, s.expanded]),
    [
      ['Sessions waiting on you', 1, true],
      ['Questions', 3, true],
      ['To merge', 1, true],
      ['Stalled runs', 1, false],
      ['Running', 1, false],
      ['Ships', 1, false],
      ['Done today', 1, false],
    ],
  );
  assert.ok(sections.every((s) => s.rows.every((r) => r.kind === 'row')), 'nothing nests under a row');
  const [waiting, questions] = sections;
  assert.equal(waiting.rows[0].label, 'Fix the login', 'a waiting session takes its own row title');
  assert.equal(waiting.rows[0].session, 'sess-waiting');
  // newest first: cache.md (1m), the guarded doc (no time), ci-move (30m) — no time sorts last
  assert.deepEqual(questions.rows.map((r) => r.label), ['cache', 'ci-move', 'guarded — open it']);
  const ci = questions.rows[1];
  assert.equal(ci.description, 'app · 2 questions · 1 irreversible · 30m');
  assert.equal(ci.warn, true);
  assert.deepEqual(ci.link, { kind: 'web', url: 'https://spacesheep.dev/@example/ci-move' });
  assert.deepEqual(ci.tooltip, ['app/docs/ci-move-2026-01-02.md', '', 'D1 Which runner · recommended: A', 'D2 Which key · irreversible · recommended: B']);
  assert.equal(questions.rows[0].github, 'https://github.com/example/lib/blob/x/docs/cache.md');
  const ship = sections[5].rows[0];
  assert.equal(ship.description, '1/3 · 1 running · 2 asks');
  assert.deepEqual(ship.tooltip, ['✓ tokens', '▶ tree (overrun)', '○ docs', '', 'Cost so far (list price): $1.50']);
  assert.deepEqual(ship.link, { kind: 'ship', id: 'ship-1' });
});

test('rows sort newest first inside a section', () => {
  const cards = [
    { kind: 'pr', title: '#1 old', url: 'u1', updated: NOW_S - 20 * 86400 },
    { kind: 'pr', title: '#2 new', url: 'u2', updated: NOW_S - 600 },
    { kind: 'pr', title: '#3 mid', url: 'u3', updated: NOW_S - 86400 },
  ];
  const [merge] = boardLayout(parseBoard(boardJson({ columns: [{ name: 'Needs Ada', cards }] })), { nowMs: NOW });
  assert.deepEqual(merge.rows.map((r) => r.label), ['#2 new', '#3 mid', '#1 old']);
});

test('the fold: a long section shows its newest rows, then "N more in the fold…"; what needs you now never folds', () => {
  const prs = Array.from({ length: 8 }, (_, i) => ({ kind: 'pr', title: `#${i}`, url: `u${i}`, updated: NOW_S - i * 60 }));
  const waiting = Array.from({ length: 8 }, (_, i) => ({ kind: 'waiting', title: `w${i}`, session: `s${i}`, updated: NOW_S - i * 60 }));
  const board = parseBoard(boardJson({ columns: [{ name: 'Needs Ada', cards: [...prs, ...waiting] }], timeline: [] }));
  const [w, merge] = boardLayout(board, { nowMs: NOW });
  assert.equal(w.shown.length, 8);
  assert.equal(w.more, null);
  assert.deepEqual(merge.shown.map((r) => r.label), ['#0', '#1', '#2', '#3', '#4']);
  assert.deepEqual(merge.more, { kind: 'more', count: 3 });
  assert.equal(merge.count, 8, 'the count is the whole section');
  const [, open] = boardLayout(board, { nowMs: NOW, unfolded: new Set([merge.id]) });
  assert.equal(open.shown.length, 8);
  assert.deepEqual(open.more, { kind: 'fewer' });
  const [, two] = boardLayout(board, { nowMs: NOW, perSection: 2 });
  assert.deepEqual(two.more, { kind: 'more', count: 6 });
});

test("other people's columns are sections of their own, closed", () => {
  const columns = [
    { name: 'Needs Ada', cards: [] },
    { name: 'Needs Sam', cards: [{ kind: 'human', title: 'Sign the form', plan: 'p', status: 'planned', by: 'sam' }] },
  ];
  const sections = boardLayout(parseBoard(boardJson({ columns, timeline: [] })), { nowMs: NOW });
  assert.deepEqual(sections.map((s) => [s.label, s.expanded]), [['Waiting on Sam', false]]);
  assert.equal(sections[0].rows[0].description, 'p · planned · by sam');
});

test('a guarded card keeps its place and nothing else', () => {
  const [, questions] = boardLayout(parseBoard(boardJson()), { nowMs: NOW });
  const guarded = questions.rows.find((r) => r.label === 'guarded — open it');
  assert.ok(guarded);
  assert.equal(guarded.link, null);
  assert.deepEqual(guarded.tooltip, []);
});

test('cardLink: course, then GitHub; sessions; ships; files', () => {
  const b = parseBoard(boardJson());
  const [a1, , a3, stall, waiting, pr] = b.columns[0].cards;
  assert.deepEqual(cardLink(a1), { kind: 'web', url: 'https://spacesheep.dev/@example/ci-move' });
  assert.deepEqual(cardLink(a3), { kind: 'web', url: 'https://github.com/example/lib/blob/x/docs/cache.md' });
  assert.deepEqual(cardLink(stall), { kind: 'session', id: 'sess-stalled', url: null });
  assert.equal(cardLink(waiting)?.kind, 'session');
  assert.deepEqual(cardLink(pr), { kind: 'web', url: 'https://github.com/example/app/pull/12' });
  const memo = parseBoard(JSON.stringify({ columns: [{ name: 'N', cards: [{ kind: 'memo', title: 'm', doc: '/abs/docs/m.md' }, { kind: 'task', title: 't', plan_id: 'p1' }] }] })).columns[0].cards;
  assert.deepEqual(cardLink(memo[0]), { kind: 'file', path: '/abs/docs/m.md' });
  assert.deepEqual(cardLink(memo[1]), { kind: 'ship', id: 'p1' });
});

test('boardHeadline and boardMessage', () => {
  const b = parseBoard(boardJson());
  assert.equal(boardHeadline(b), '5 for Ada · 1 stalled · 1 running');
  assert.equal(boardMessage(b, NOW), 'week 40% used (pace 30%)');
  const old: Board = { ...b, asOf: NOW_S - 3 * 3600 };
  assert.equal(boardMessage(old, NOW, 'reading a fresh board…'), 'reading a fresh board… — week 40% used (pace 30%) — board from 3h ago: refresh reads a fresh one');
  assert.equal(boardMessage({ ...b, week: null, asOf: NOW_S - 30 * 3600 }, NOW), 'board from yesterday: refresh reads a fresh one', 'never "yesterday ago"');
  assert.equal(boardHeadline({ ...b, needsOwner: 0, stalled: 0, columns: [] }), null);
});

test('helmNotes: stalls and waits from the board, skippers from their status', () => {
  const notes = helmNotes(parseBoard(boardJson()), new Map([['sess-skip', 'app']]));
  assert.equal(notes.get('sess-stalled')?.word, 'stalled');
  assert.match(notes.get('sess-stalled')?.line ?? '', /max lifetime \(ended 9h\)/);
  assert.equal(notes.get('sess-waiting')?.kind, 'waiting');
  assert.equal(notes.get('sess-skip')?.line, 'Helm: the skipper of app');
  assert.equal(helmNotes(null, new Map()).size, 0);
});

test('parseSkippers: the record and the live holders', () => {
  const text = JSON.stringify({
    scopes: [
      { scope: 'app', record: { session: 's-rec' }, holders: [{ session: 's-live', alive: true }, { session: 's-gone', alive: false }] },
      { scope: 'lib', record: null, holders: [] },
    ],
  });
  assert.deepEqual([...parseSkippers(text)], [['s-rec', 'app'], ['s-live', 'app']]);
  assert.equal(parseSkippers('no ship here holds a lease').size, 0);
});

test('parseNavStatus: live, left over, none', () => {
  const text = [
    'standup-0105  listening  http://127.0.0.1:8123/',
    'retro-0104  recogniser still recording, no server — navigate stop retro-0104',
    'old-0101  not running',
  ].join('\n');
  const ms = parseNavStatus(text);
  assert.deepEqual(ms[0], { id: 'standup-0105', alive: true, status: 'listening', url: 'http://127.0.0.1:8123/', note: null });
  assert.equal(ms[1].alive, false);
  assert.match(ms[1].note ?? '', /navigate stop retro-0104/);
  assert.equal(ms[2].note, 'not running');
  assert.deepEqual(parseNavStatus('no meetings\n'), []);
});

const meetingJson = (over: Record<string, unknown> = {}) => ({
  event: 'evt1',
  name: 'Design review',
  start: { dateTime: new Date(NOW + 25 * 60_000).toISOString() },
  end: { dateTime: new Date(NOW + 55 * 60_000).toISOString() },
  all_day: false,
  org: 'example',
  ask: false,
  network: null,
  lang: 'en',
  brief: '/briefs/design-review/short.md',
  ...over,
});

test('parseMeetings reads next --json', () => {
  const [m] = parseMeetings(JSON.stringify([meetingJson(), { name: '' }]));
  assert.equal(m.name, 'Design review');
  assert.equal(m.start, NOW + 25 * 60_000);
  assert.equal(m.refused, false);
  assert.equal(parseMeetings(JSON.stringify([meetingJson({ network: 'no recording' })]))[0].refused, true);
  assert.equal(parseMeetings(JSON.stringify([meetingJson({ start: { date: '2027-01-15' }, all_day: true })]))[0].allDay, true);
  assert.throws(() => parseMeetings('{}'), /no list/);
});

test('meetingWhen', () => {
  const [m] = parseMeetings(JSON.stringify([meetingJson()]));
  assert.equal(meetingWhen(m, NOW), 'in 25m');
  assert.equal(meetingWhen(m, NOW + 25 * 60_000 - 30_000), 'in under a minute');
  assert.equal(meetingWhen(m, NOW + 25 * 60_000 + 30_000), 'now');
  assert.equal(meetingWhen(m, NOW + 35 * 60_000), 'started 10m ago');
  assert.equal(meetingWhen(m, NOW + 60 * 60_000), 'over');
  assert.equal(meetingWhen(m, NOW - 2 * 3_600_000 + 25 * 60_000), 'in 2h');
  assert.equal(meetingWhen(m, NOW + 25 * 60_000 - (59 * 60_000 + 40_000)), 'in 59m', 'minutes floor, never "in 60m"');
  assert.equal(meetingWhen(m, NOW + 25 * 60_000 - (119 * 60_000 + 40_000)), 'in 1h 59m', 'never "in 1h 60m"');
  const [open] = parseMeetings(JSON.stringify([meetingJson({ end: null })]));
  assert.equal(meetingWhen(open, NOW + 25 * 60_000 + 30 * 3_600_000), 'started yesterday', 'never "yesterday ago"');
});

test('launchArgs', () => {
  const [m] = parseMeetings(JSON.stringify([meetingJson()]));
  assert.deepEqual(launchArgs(m), ['navigate', 'launch', '--name', 'Design review', '--event', 'evt1', '--lang', 'en']);
  const [auto] = parseMeetings(JSON.stringify([meetingJson({ lang: 'auto', event: null })]));
  assert.deepEqual(launchArgs(auto), ['navigate', 'launch', '--name', 'Design review']);
});

test('meetingNudge: five minutes before to ten after, unless listening or refused', () => {
  const ms = parseMeetings(JSON.stringify([meetingJson()]));
  const start = NOW + 25 * 60_000;
  assert.equal(meetingNudge(ms, [], start - 6 * 60_000), null);
  assert.equal(meetingNudge(ms, [], start - 4 * 60_000)?.name, 'Design review');
  assert.equal(meetingNudge(ms, [], start + 9 * 60_000)?.name, 'Design review');
  assert.equal(meetingNudge(ms, [], start + 11 * 60_000), null);
  assert.equal(meetingNudge(ms, [{ id: 'x', alive: true, status: null, url: null, note: null }], start), null);
  assert.equal(meetingNudge(parseMeetings(JSON.stringify([meetingJson({ network: 'x' })])), [], start), null);
});

test('questions with no time of their own sort and age by the day in their doc name', () => {
  const now = new Date(NOW);
  const day = (d: number) => new Date(now.getFullYear(), now.getMonth(), now.getDate() - d);
  const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  const cards = [
    { kind: 'ask', title: 'a', ref: `docs/old-${iso(day(5))}.md#D1`, repo: 'app' },
    { kind: 'ask', title: 'b', ref: `docs/new-${iso(day(0))}.md#D1`, repo: 'app' },
    { kind: 'ask', title: 'c', ref: 'docs/undated.md#D1', repo: 'app' },
    { kind: 'ask', title: 'd', ref: `docs/mid-${iso(day(1))}.md#D1`, repo: 'app' },
  ];
  const [questions] = boardLayout(parseBoard(boardJson({ columns: [{ name: 'Needs Ada', cards }], timeline: [] })), { nowMs: NOW });
  assert.deepEqual(
    questions.rows.map((r) => [r.label, r.description]),
    [
      ['new', 'app · 1 question · today'],
      ['mid', 'app · 1 question · yesterday'],
      ['old', 'app · 1 question · 5d'],
      ['undated', 'app · 1 question'],
    ],
  );
  assert.equal(docDay('docs/x.md'), 0);
  assert.equal(daysAgo(day(3).getTime() / 1000, NOW), '3d');
});

test('ships: the moving one first, then those waiting on questions, then the rest, the finished last', () => {
  const ship = (id: string, statuses: string[], asks = 0) => ({
    id,
    plan: id,
    totals: { open_asks: asks },
    bars: statuses.map((status, i) => ({ id: `${id}${i}`, title: 't', status })),
  });
  const timeline = [ship('done', ['done']), ship('idle', ['planned']), ship('asking', ['planned'], 2), ship('moving', ['done', 'running'])];
  const sections = boardLayout(parseBoard(boardJson({ columns: [], timeline })), { nowMs: NOW });
  assert.deepEqual(sections[0].rows.map((r) => r.label), ['moving', 'asking', 'idle', 'done']);
});

test("helm's other card kinds: a permission prompt waits on you and opens its session; run and road go by hand", () => {
  const cards = [
    { kind: 'permission', title: 'p · permission prompt', session: 's-perm', repo: 'app', updated: NOW_S - 60 },
    { kind: 'run', title: 'a run', session: 's-run', repo: 'app' },
    { kind: 'road', title: 'escalated', url: 'https://github.com/example/app/issues/1', repo: 'app' },
  ];
  const b = parseBoard(boardJson({ columns: [{ name: 'Needs Ada', cards }], timeline: [] }));
  const [waiting, hand] = boardLayout(b, { nowMs: NOW, sessionLabel: (id) => (id === 's-perm' ? 'Fix the login' : null) });
  assert.equal(waiting.label, 'Sessions waiting on you');
  assert.equal(waiting.rows[0].label, 'Fix the login');
  assert.deepEqual(waiting.rows[0].link, { kind: 'session', id: 's-perm', url: null });
  assert.equal(hand.label, 'By hand');
  assert.deepEqual(hand.rows.map((r) => r.link?.kind).sort(), ['session', 'web']);
  assert.equal(helmNotes(b, new Map()).get('s-perm')?.kind, 'waiting');
});

test('row ids are unique across the view: lookouts on one branch, guarded pairs, same-titled tasks', () => {
  const cards = [
    { kind: 'lookout', title: 'docs/a.md D1', ref: 'claude/x', repo: 'app' },
    { kind: 'lookout', title: 'docs/a.md D2', ref: 'claude/x', repo: 'app' },
    { kind: 'pr', title: 'guarded — open it', guarded: true, repo: 'secret' },
    { kind: 'pr', title: 'guarded — open it', guarded: true, repo: 'secret' },
    { kind: 'task', title: 'Land', status: 'planned' },
    { kind: 'task', title: 'Land', status: 'planned' },
  ];
  const ids = boardLayout(parseBoard(boardJson({ columns: [{ name: 'Needs Ada', cards }], timeline: [] })), { nowMs: NOW }).flatMap((s) => s.rows.map((r) => r.id));
  assert.equal(new Set(ids).size, ids.length);
  assert.equal(ids.length, 6);
});

test('launched and failed tasks are over; a question with only a ship opens the ship', () => {
  const timeline = [{ id: 'sh', plan: 'sh', bars: [{ id: 'a', title: 'a', status: 'launched' }, { id: 'b', title: 'b', status: 'done' }] }];
  const [ships] = boardLayout(parseBoard(boardJson({ columns: [], timeline })), { nowMs: NOW });
  assert.equal(ships.rows[0].description, '2/2');
  assert.equal(ships.rows[0].icon, 'pass');
  const ask = parseBoard(JSON.stringify({ columns: [{ name: 'N', cards: [{ kind: 'ask', title: 'q', plan_id: 'p1' }] }] })).columns[0].cards[0];
  assert.deepEqual(cardLink(ask), { kind: 'ship', id: 'p1' });
});

test('a guarded stall says nothing on the Sessions row', () => {
  const b = parseBoard(JSON.stringify({ columns: [{ name: 'N', cards: [{ kind: 'stall', title: 'secret run', rule: 'S3', session: 's1', guarded: true }] }] }));
  assert.equal(helmNotes(b, new Map()).size, 0);
});

test("the desk's Intake column is its own closed section, never a person's", () => {
  const b = parseBoard(
    JSON.stringify({
      as_of: NOW_S,
      header: { needs_owner: 0, owner: 'Ada' },
      columns: [
        { name: 'Needs Ada', cards: [] },
        { name: 'Intake', cards: [{ kind: 'intake', title: 'deadman #12', repo: 'logbook', url: 'https://github.com/example/logbook/issues/12', updated: NOW_S - 60 }] },
      ],
    }),
  );
  assert.equal(columnTone('Intake', 1), 'intake');
  const sections = boardLayout(b, { nowMs: NOW });
  assert.deepEqual(sections.map((s) => s.label), ['Intake']);
  assert.equal(sections[0].expanded, false);
  assert.equal(sections[0].rows[0].icon, 'issues');
  assert.deepEqual(sections[0].rows[0].link, { kind: 'web', url: 'https://github.com/example/logbook/issues/12' });
});

test('a ship with a failed task is over but no pass: its own mark and an error icon', () => {
  const b = parseBoard(
    JSON.stringify({
      as_of: NOW_S,
      columns: [{ name: 'Needs Ada', cards: [] }],
      timeline: [{ id: 'ship-1', plan: 'one', bars: [{ id: 'S1', title: 'a', status: 'done' }, { id: 'S2', title: 'b', status: 'failed' }] }],
    }),
  );
  const row = boardLayout(b, { nowMs: NOW }).find((s) => s.label === 'Ships')!.rows[0];
  assert.equal(row.icon, 'error');
  assert.ok(row.tooltip.includes('✗ b'));
  assert.ok(row.tooltip.includes('✓ a'));
});

test('regattaCandidates reads the home file as the core does: its first non-blank line', () => {
  assert.deepEqual(regattaCandidates('', {}, '\n  \n/h\n'), ['regatta', '/h/modules/regatta/bin/regatta']);
});

test('the board file and its cache dir expand ~ alike, a home with a trailing slash too', () => {
  assert.deepEqual(boardFileCandidates('~/c/overview/state.json', {}, '/u/'), ['/u/c/overview/state.json']);
  assert.equal(boardCacheDir('~/c/overview/state.json', '/u/'), '/u/c');
});

test("the navigator's shared answer: take a fresh one, wait on a fresh claim, else ask", () => {
  const MIN5 = 5 * 60_000;
  const c = (at: number, text: string | null, error: string | null = null) => ({ at, text, error });
  assert.equal(nextCacheStep(null, NOW, MIN5, false), 'ask', 'no cache');
  assert.equal(nextCacheStep(c(NOW - MIN5, '[]'), NOW, MIN5, false), 'ask', 'old');
  assert.equal(nextCacheStep(c(NOW - 1000, '[]'), NOW, MIN5, true), 'ask', 'forced');
  assert.equal(nextCacheStep(c(NOW - 1000, '[]'), NOW, MIN5, false), 'take');
  assert.equal(nextCacheStep(c(NOW - 1000, '[]', 'token expired'), NOW, MIN5, false), 'take', 'a failure is an answer too');
  assert.equal(nextCacheStep(c(NOW - 1000, null, 'token expired'), NOW, MIN5, false), 'take', 'a first read that failed: said, not asked every tick');
  assert.equal(nextCacheStep(c(NOW - 1000, null), NOW, MIN5, false), 'pending', "another window's first read is running");
});

test('a read writes back only over its own claim', () => {
  assert.ok(stillClaimed({ at: 5, text: null, error: null }, 5));
  assert.ok(!stillClaimed({ at: 6, text: '[]', error: null }, 5), 'a later claim (a forced read, another window) is newer');
  assert.ok(!stillClaimed(null, 5));
});

test('parseNextCache reads the file the views share, and nothing else', () => {
  assert.deepEqual(parseNextCache('{"at": 5, "text": "[]", "error": null}'), { at: 5, text: '[]', error: null });
  assert.deepEqual(parseNextCache('{"at": 5, "text": null}'), { at: 5, text: null, error: null }, "the old shape, with no error");
  assert.equal(parseNextCache('{"text": "[]"}'), null, 'no time');
  assert.equal(parseNextCache('not json'), null);
  assert.equal(parseNextCache('null'), null);
});
