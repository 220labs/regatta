// Regatta in VS Code: helm's board (what waits on whom, the ships) and the navigator's meetings
// (the one running, the next one), read from the `regatta` CLI and the board file helm's poll
// writes. Pure: never imports `vscode`, so `node --test` covers the parsing and the layout.
// Moved from Sheepfold's src/regatta.ts on 2026-11-02, when the views split into this extension.

import { MoreRow, expandHome, relativeTime } from './util';

// ---------------------------------------------------------------------------------------------
// Finding the CLI: what the core itself honours (`regatta_root`). Regatta keeps itself off PATH
// by design, so `$REGATTA_HOME` and the config dir's `home` file are how an install is found.

/**
 * The `regatta` programs to try, first that runs wins: the setting when set; else `regatta` on
 * PATH, the clone in `$REGATTA_HOME`, then the clone the config dir's `home` file names.
 */
export function regattaCandidates(setting: string, env: { REGATTA_HOME?: string }, homeFile: string | null): string[] {
  const set = setting.trim();
  if (set) return [set];
  const out = ['regatta'];
  // The home file's first non-blank line, as the core's config_line reads it.
  const fromFile = homeFile?.split(/\r?\n/).find((l) => l.trim() !== '');
  for (const root of [env.REGATTA_HOME, fromFile]) {
    const r = (root ?? '').trim().replace(/[\\/]+$/, '');
    if (r) out.push(`${r}/modules/regatta/bin/regatta`);
  }
  return [...new Set(out)];
}

/** Where helm's poll leaves the board (helm_render's `cache_root()/overview/state.json`). */
export function boardFileCandidates(setting: string, env: { PLAN_CACHE_DIR?: string }, home: string): string[] {
  const set = setting.trim();
  if (set) return [expandHome(set, home)];
  const base = env.PLAN_CACHE_DIR || `${home}/Library/Caches/plan`;
  return [`${base}/overview/state.json`];
}

/**
 * The cache dir `helm board` must write for it to land at the board file the setting names:
 * null when the setting is empty (helm's own default is that file), the dir when the setting ends
 * in `overview/state.json` (helm writes `$PLAN_CACHE_DIR/overview/state.json`), and false for any
 * other file, which helm cannot write: then only helm's poll (or the owner) fills it.
 */
export function boardCacheDir(setting: string, home: string): string | null | false {
  const set = setting.trim();
  if (!set) return null;
  const file = expandHome(set, home);
  const m = /^(.+?)[\\/]+overview[\\/]+state\.json$/.exec(file);
  return m ? m[1] : false;
}

/**
 * A board file older than this says its age above the tree. The CLI is not asked on its own for a
 * fresher one: `helm board` reads every repo's pull requests from GitHub (over a minute), and every
 * VS Code window would ask. Only the refresh button asks, or the lack of any board file.
 */
export const BOARD_FILE_FRESH_MS = 15 * 60_000;
/** With no board file at all, the CLI is asked at most this often. */
export const BOARD_CLI_EVERY_MS = 30 * 60_000;

// ---------------------------------------------------------------------------------------------
// The board: `regatta helm board --json`.

// `permission`: a session stopped at a permission prompt; `run`: an unattended run's own card;
// `road`: an escalation helm sent by the stall road.
export type CardKind =
  | 'ask'
  | 'stall'
  | 'waiting'
  | 'permission'
  | 'pr'
  | 'done'
  | 'lookout'
  | 'memo'
  | 'human'
  | 'task'
  | 'held'
  | 'run'
  | 'road'
  | 'intake'
  | 'other';

const KINDS: readonly CardKind[] = ['ask', 'stall', 'waiting', 'permission', 'pr', 'done', 'lookout', 'memo', 'human', 'task', 'held', 'run', 'road', 'intake'];

export interface Card {
  kind: CardKind;
  column: string;
  title: string;
  repo: string | null;
  branch: string | null;
  /** A PR, a WIP PR, a `vscode://` session link. */
  url: string | null;
  /** The doc's page on spacesheep, where its D-items are answered. */
  course: string | null;
  github: string | null;
  /** `docs/x-2026-10-24.md#D2` for an ask; a branch for a lookout. */
  ref: string | null;
  recommended: string | null;
  /** 'yes' | 'no' as the doc says; null when it does not. */
  reversible: string | null;
  session: string | null;
  evidence: string | null;
  rule: string | null;
  doc: string | null;
  plan: string | null;
  planId: string | null;
  status: string | null;
  by: string | null;
  updated: number | null;
  guarded: boolean;
}

export interface ShipBar {
  id: string;
  title: string;
  status: string;
  overrun: boolean;
  end: number | null;
}

export interface Ship {
  id: string;
  name: string;
  bars: ShipBar[];
  done: number;
  cost: number | null;
  openAsks: number;
}

export interface Board {
  /** Seconds since the epoch, as helm writes it. */
  asOf: number;
  host: string | null;
  owner: string | null;
  needsOwner: number;
  stalled: number | null;
  week: string | null;
  columns: Array<{ name: string; cards: Card[] }>;
  ships: Ship[];
}

const s = (v: unknown): string | null => (typeof v === 'string' && v !== '' ? v : null);
const n = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);

/** Statuses after which a task is over: helmlib's ENDED (done, landed, launched, failed) and the words around it. */
const ENDED = new Set(['done', 'landed', 'launched', 'failed', 'merged', 'ended', 'cancelled', 'dropped', 'superseded']);

function card(raw: Record<string, unknown>, column: string): Card {
  const kind = s(raw.kind);
  return {
    kind: kind && (KINDS as readonly string[]).includes(kind) ? (kind as CardKind) : 'other',
    column,
    title: s(raw.title) ?? '(untitled)',
    repo: s(raw.repo),
    branch: s(raw.branch),
    url: s(raw.url),
    course: s(raw.course),
    github: s(raw.github),
    ref: s(raw.ref),
    recommended: s(raw.recommended),
    reversible: s(raw.reversible),
    session: s(raw.session),
    evidence: s(raw.evidence),
    rule: s(raw.rule),
    doc: s(raw.doc),
    plan: s(raw.plan),
    planId: s(raw.plan_id),
    status: s(raw.status),
    by: s(raw.by),
    updated: n(raw.updated),
    guarded: raw.guarded === true,
  };
}

/** Parse the board. Throws a short Error on anything that is not one. */
export function parseBoard(text: string): Board {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error('the board is not JSON');
  }
  const root = data as Record<string, unknown> | null;
  if (!root || typeof root !== 'object' || !Array.isArray(root.columns)) throw new Error('the board has no columns');
  const header = (root.header && typeof root.header === 'object' ? root.header : {}) as Record<string, unknown>;
  const columns = (root.columns as unknown[])
    .filter((c): c is Record<string, unknown> => !!c && typeof c === 'object')
    .map((c) => {
      const name = s(c.name) ?? '?';
      const cards = Array.isArray(c.cards) ? c.cards.filter((x): x is Record<string, unknown> => !!x && typeof x === 'object') : [];
      return { name, cards: cards.map((x) => card(x, name)) };
    });
  const ships: Ship[] = [];
  for (const t of Array.isArray(root.timeline) ? root.timeline : []) {
    if (!t || typeof t !== 'object') continue;
    const r = t as Record<string, unknown>;
    const id = s(r.id);
    if (!id) continue;
    const bars: ShipBar[] = (Array.isArray(r.bars) ? r.bars : [])
      .filter((b): b is Record<string, unknown> => !!b && typeof b === 'object')
      .map((b) => ({
        id: s(b.id) ?? '?',
        title: s(b.title) ?? s(b.id) ?? '?',
        status: s(b.status) ?? 'planned',
        overrun: b.overrun === true,
        end: n(b.end),
      }));
    const totals = (r.totals && typeof r.totals === 'object' ? r.totals : {}) as Record<string, unknown>;
    ships.push({
      id,
      name: s(r.plan) ?? id.slice(0, 8),
      bars,
      done: bars.filter((b) => ENDED.has(b.status)).length,
      cost: n(totals.cost),
      openAsks: n(totals.open_asks) ?? 0,
    });
  }
  return {
    asOf: n(root.as_of) ?? 0,
    host: s(root.host),
    owner: s(header.owner),
    needsOwner: n(header.needs_owner) ?? (columns[0]?.cards.length ?? 0),
    stalled: n(header.stalled),
    week: s(header.week),
    columns,
    ships,
  };
}

// ---------------------------------------------------------------------------------------------
// The board as the view shows it: a short list of sections, in the order they are acted on,
// each holding rows one level deep, newest first. No column level (the view's title counts
// what waits on you) and nothing nested under a row: a doc's questions and a ship's tasks are
// in its tooltip, and a click opens the page where they are answered or followed.

export type Tone = 'owner' | 'person' | 'blocked' | 'running' | 'parked' | 'done' | 'intake';

/** What a click does: a web page, a spacesheep page (the mirror's tab if it runs), a session, a file, a ship's page. */
export type Link =
  | { kind: 'web'; url: string }
  | { kind: 'session'; id: string; url: string | null }
  | { kind: 'file'; path: string }
  | { kind: 'ship'; id: string };

export interface BoardRow {
  kind: 'row';
  id: string;
  label: string;
  description: string;
  /** A codicon id. */
  icon: string;
  /** Drawn in the warning colour: an irreversible question, a stall. */
  warn: boolean;
  link: Link | null;
  tooltip: string[];
  /** The session the row is about, for its model mark. */
  session: string | null;
  /** A doc's GitHub page, for "Open on GitHub". */
  github: string | null;
  /** Seconds since the epoch; 0 when the board does not say. */
  newest: number;
  /** A ship's place: 0 moving, 1 waiting on questions, 2 the rest, 3 finished. */
  rank?: number;
}

export interface BoardSection {
  kind: 'section';
  id: string;
  label: string;
  icon: string;
  warn: boolean;
  count: number;
  expanded: boolean;
  /** Every row, newest first. */
  rows: BoardRow[];
  /** The rows above the fold: all of them when the section is unfolded or never folds. */
  shown: BoardRow[];
  /** The fold's row: "N more in the fold…", or "show fewer" once unfolded; null when all fit. */
  more: MoreRow | null;
}

/** The fold's row under a section. */
export interface BoardMore {
  kind: 'more';
  id: string;
  section: string;
  more: MoreRow;
}

export type BoardNode = BoardSection | BoardRow | BoardMore;

/** Rows a section shows above the fold, unless the setting says otherwise. */
export const BOARD_PER_SECTION = 5;

export function columnTone(name: string, index: number): Tone {
  if (index === 0) return 'owner';
  if (/^blocked/i.test(name)) return 'blocked';
  if (/^running/i.test(name)) return 'running';
  if (/^parked/i.test(name)) return 'parked';
  if (/^done/i.test(name)) return 'done';
  // The desk's open issues (helm_render's OTHER_COLUMNS since lighthouse-ops S4), never a person.
  if (/^intake/i.test(name)) return 'intake';
  return 'person';
}

/** `docs/owner-reach-2026-10-24.md#D2` → `owner-reach`; a path with no date keeps its name. */
export function docName(ref: string): string {
  const file = ref.split('#')[0].split('/').pop() ?? ref;
  return file.replace(/\.md$/i, '').replace(/-\d{4}-\d{2}-\d{2}(?=$|-)/, '') || file;
}

/** The D-item of a ref: `…#D2` → `D2`. */
export function dItem(ref: string | null): string | null {
  const m = /#(D\d+[a-z]?)$/i.exec(ref ?? '');
  return m ? m[1].toUpperCase() : null;
}

/** A doc's day from its name (`docs/x-2026-10-24.md#D1`), as seconds at its local midnight; 0 for none. */
export function docDay(ref: string): number {
  const m = /(\d{4})-(\d{2})-(\d{2})(?=[^/]*$)/.exec(ref.split('#')[0]);
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])).getTime() / 1000 : 0;
}

/** A day's age in days: `today`, `yesterday`, `3d`. */
export function daysAgo(daySeconds: number, nowMs: number): string {
  const now = new Date(nowMs);
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const n = Math.round((today - daySeconds * 1000) / 86_400_000);
  return n <= 0 ? 'today' : n === 1 ? 'yesterday' : `${n}d`;
}

function ago(updated: number, nowMs: number): string | null {
  return updated ? relativeTime(updated * 1000, nowMs) : null;
}

function join(...parts: Array<string | null | undefined | false>): string {
  return parts.filter((p): p is string => !!p).join(' · ');
}

const plural = (k: number, one: string, many: string) => `${k} ${k === 1 ? one : many}`;

function taskIcon(status: string | null): string {
  switch (status) {
    case 'running':
      return 'sync~spin';
    case 'parked':
    case 'relayed':
      return 'debug-pause';
    case 'failed':
    case 'stalled':
      return 'error';
    default:
      return status && ENDED.has(status) ? 'pass' : 'circle-large-outline';
  }
}

export function cardLink(c: Card): Link | null {
  if (c.guarded) return null;
  switch (c.kind) {
    case 'ask':
      return c.course ? { kind: 'web', url: c.course } : c.github ? { kind: 'web', url: c.github } : c.planId ? { kind: 'ship', id: c.planId } : null;
    case 'stall':
    case 'waiting':
    case 'permission':
      return c.session ? { kind: 'session', id: c.session, url: c.url } : c.url ? { kind: 'web', url: c.url } : null;
    case 'memo':
      return c.course ? { kind: 'web', url: c.course } : c.doc && c.doc.startsWith('/') ? { kind: 'file', path: c.doc } : null;
    case 'task':
    case 'human':
      return c.planId ? { kind: 'ship', id: c.planId } : null;
    default:
      if (c.url) return { kind: 'web', url: c.url };
      if (c.session) return { kind: 'session', id: c.session, url: null };
      return c.course ? { kind: 'web', url: c.course } : c.github ? { kind: 'web', url: c.github } : null;
  }
}

export interface BoardLayoutOptions {
  nowMs: number;
  /** Rows shown per section before the fold (BOARD_PER_SECTION when absent). */
  perSection?: number;
  /** Section ids the user unfolded; in memory only. */
  unfolded?: ReadonlySet<string>;
  /** A session's own label (Sheepfold's row title), when Sheepfold is installed and lists it. */
  sessionLabel?: (id: string) => string | null;
}

const KIND_ICON: Partial<Record<CardKind, string>> = {
  waiting: 'bell',
  permission: 'shield',
  stall: 'warning',
  run: 'run',
  road: 'megaphone',
  pr: 'git-pull-request',
  done: 'git-merge',
  held: 'lock',
  lookout: 'eye',
  intake: 'issues',
  memo: 'book',
  human: 'person',
};

function cardRow(c: Card, key: string, o: BoardLayoutOptions): BoardRow {
  const newest = c.updated ?? 0;
  const when = ago(newest, o.nowMs);
  let label = c.title;
  let description = join(c.repo, when);
  const tooltip: string[] = [];
  switch (c.kind) {
    case 'waiting':
    case 'permission':
      label = (c.session && o.sessionLabel?.(c.session)) || c.title;
      description = join(c.repo, c.branch !== 'main' && c.branch, when);
      break;
    case 'stall':
      description = join(c.repo, c.rule, when);
      if (c.evidence) tooltip.push(c.evidence);
      break;
    case 'task':
    case 'human':
      description = join(c.plan, c.status, c.kind === 'human' && c.by && `by ${c.by}`, when);
      break;
    case 'lookout':
      if (c.evidence) tooltip.push(c.evidence);
      break;
  }
  if (c.repo) tooltip.push(`Repo: ${c.repo}${c.branch ? ` (${c.branch})` : ''}`);
  if (c.guarded) {
    label = 'guarded — open it';
    description = c.repo ?? '';
    tooltip.length = 0;
  }
  return {
    kind: 'row',
    // Made unique by boardLayout's last pass: lookouts share a branch, guarded cards a title.
    id: `${key}:${c.kind}:${c.repo ?? ''}:${c.planId ?? ''}:${c.url ?? c.session ?? c.doc ?? c.ref ?? c.title}`,
    label,
    description,
    icon: c.kind === 'task' ? taskIcon(c.status) : (KIND_ICON[c.kind] ?? 'circle-small'),
    warn: c.kind === 'stall',
    link: cardLink(c),
    tooltip,
    session: c.guarded ? null : c.session,
    github: c.guarded ? null : c.github,
    newest,
  };
}

/** One row per doc: a doc's questions are answered together, on its page. */
function docRows(cards: Card[], key: string, o: BoardLayoutOptions): BoardRow[] {
  const byDoc = new Map<string, Card[]>();
  for (const c of cards) {
    const k = `${c.repo ?? ''}:${(c.ref ?? c.title).split('#')[0]}`;
    byDoc.set(k, [...(byDoc.get(k) ?? []), c]);
  }
  return [...byDoc.entries()].map(([k, cs]) => {
    const first = cs[0];
    const ref = first.ref ?? first.title;
    const hard = cs.filter((c) => c.reversible === 'no').length;
    const updated = Math.max(...cs.map((c) => c.updated ?? 0));
    // Most questions carry no time of their own; the doc's name carries its day.
    const dated = updated ? 0 : docDay(ref);
    const newest = updated || dated;
    const link = first.guarded ? null : (cs.map(cardLink).find((l) => l !== null) ?? null);
    const items = cs.map((c) => {
      const d = dItem(c.ref);
      return join(`${d ? `${d} ` : ''}${c.title}`, c.reversible === 'no' && 'irreversible', c.recommended && `recommended: ${c.recommended}`);
    });
    return {
      kind: 'row',
      id: `${key}:doc:${k}`,
      label: first.guarded ? 'guarded — open it' : docName(ref),
      description: join(
        first.repo,
        plural(cs.length, 'question', 'questions'),
        hard > 0 && `${hard} irreversible`,
        updated ? ago(updated, o.nowMs) : dated ? daysAgo(dated, o.nowMs) : null,
      ),
      icon: 'question',
      warn: hard > 0,
      link,
      tooltip: first.guarded ? [] : [`${first.repo ? `${first.repo}/` : ''}${ref.split('#')[0]}`, '', ...items],
      session: null,
      github: first.guarded ? null : (cs.find((c) => c.github)?.github ?? null),
      newest,
    };
  });
}

/** A column's cards as rows: questions one per doc, the rest one per card. */
function rowsOf(cards: Card[], key: string, o: BoardLayoutOptions): BoardRow[] {
  return [...docRows(cards.filter((c) => c.kind === 'ask'), key, o), ...cards.filter((c) => c.kind !== 'ask').map((c) => cardRow(c, key, o))];
}

function shipRow(ship: Ship, o: BoardLayoutOptions): BoardRow {
  const running = ship.bars.filter((b) => b.status === 'running').length;
  const ended = ship.bars.length > 0 && ship.done === ship.bars.length;
  // Failed is over (helmlib's ENDED), but not done well: its own mark, and an ended ship with one is no pass.
  const failed = ship.bars.some((b) => b.status === 'failed');
  const newest = Math.max(0, ...ship.bars.map((b) => b.end ?? 0));
  const mark = (status: string) =>
    status === 'running' ? '▶' : status === 'failed' ? '✗' : ENDED.has(status) ? '✓' : status === 'parked' || status === 'relayed' ? '‖' : '○';
  return {
    kind: 'row',
    id: `ship:${ship.id}`,
    label: ship.name,
    description: join(`${ship.done}/${ship.bars.length}`, running > 0 && `${running} running`, ship.openAsks > 0 && plural(ship.openAsks, 'ask', 'asks')),
    icon: ended ? (failed ? 'error' : 'pass') : running ? 'sync~spin' : 'milestone',
    warn: ship.bars.some((b) => b.overrun),
    link: { kind: 'ship', id: ship.id },
    tooltip: [
      ...ship.bars.map((b) => `${mark(b.status)} ${b.title}${b.overrun ? ' (overrun)' : ''}`),
      '',
      ...(ship.cost ? [`Cost so far (list price): $${ship.cost.toFixed(2)}`] : []),
    ],
    session: null,
    github: null,
    newest,
    rank: running ? 0 : ended ? 3 : ship.openAsks > 0 ? 1 : 2,
  };
}

const byNewest = (a: BoardRow, b: BoardRow) => b.newest - a.newest;

// Ships: the one moving first, then one waiting on questions, then the rest, then the finished.
const byMotion = (a: BoardRow, b: BoardRow) => (a.rank ?? 2) - (b.rank ?? 2) || a.label.localeCompare(b.label);

/**
 * The Board view. Sections in the order they are acted on — sessions waiting on you, questions,
 * pull requests to merge, work by hand, blocked — open; then, closed, what is only to be watched:
 * stalled runs, the lookout, the desk's intake, other people's, running, parked, ships, done today. Empty sections
 * are left out; rows are newest first.
 */
export function boardLayout(b: Board, o: BoardLayoutOptions): BoardSection[] {
  const owner: Card[] = [];
  const running: Card[] = [];
  const parked: Card[] = [];
  const blocked: Card[] = [];
  const done: Card[] = [];
  const intake: Card[] = [];
  const people: Array<{ name: string; cards: Card[] }> = [];
  b.columns.forEach((col, i) => {
    switch (columnTone(col.name, i)) {
      case 'owner':
        owner.push(...col.cards);
        break;
      case 'running':
        running.push(...col.cards);
        break;
      case 'parked':
        parked.push(...col.cards);
        break;
      case 'blocked':
        blocked.push(...col.cards);
        break;
      case 'done':
        done.push(...col.cards);
        break;
      case 'intake':
        intake.push(...col.cards);
        break;
      case 'person':
        if (col.cards.length) people.push({ name: col.name.replace(/^needs\s+/i, ''), cards: col.cards });
        break;
    }
  });
  const ofKind = (cards: Card[], ...kinds: CardKind[]) => cards.filter((c) => kinds.includes(c.kind));
  const cap = Math.max(0, o.perSection ?? BOARD_PER_SECTION);
  // `folds`: false for what needs you now (sessions waiting, blocked), which always shows whole.
  const section = (key: string, label: string, icon: string, rows: BoardRow[], expanded: boolean, warn = false, order = byNewest, folds = true): BoardSection => {
    const id = `section:${key}`;
    const sorted = [...rows].sort(order);
    const fits = !folds || sorted.length <= cap;
    const open = o.unfolded?.has(id) ?? false;
    return {
      kind: 'section',
      id,
      label,
      icon,
      warn,
      count: sorted.length,
      expanded,
      rows: sorted,
      shown: fits || open ? sorted : sorted.slice(0, cap),
      more: fits ? null : open ? { kind: 'fewer' } : { kind: 'more', count: sorted.length - cap },
    };
  };
  const handKinds: CardKind[] = ['human', 'memo', 'task', 'run', 'road', 'other'];
  const sections = [
    section('waiting', 'Sessions waiting on you', 'bell', ofKind(owner, 'waiting', 'permission').map((c) => cardRow(c, 'waiting', o)), true, true, byNewest, false),
    section('questions', 'Questions', 'question', docRows(ofKind(owner, 'ask'), 'questions', o), true),
    section('merge', 'To merge', 'git-pull-request', ofKind(owner, 'pr', 'held').map((c) => cardRow(c, 'merge', o)), true),
    section('hand', 'By hand', 'person', ofKind(owner, ...handKinds).map((c) => cardRow(c, 'hand', o)), true),
    section('blocked', 'Blocked', 'circle-slash', rowsOf(blocked, 'blocked', o), true, true, byNewest, false),
    section('stalled', 'Stalled runs', 'warning', ofKind(owner, 'stall').map((c) => cardRow(c, 'stalled', o)), false),
    section('lookout', 'Lookout', 'eye', ofKind(owner, 'lookout').map((c) => cardRow(c, 'lookout', o)), false),
    section('intake', 'Intake', 'inbox', rowsOf(intake, 'intake', o), false),
    ...people.map((p) => section(`person:${p.name}`, `Waiting on ${p.name}`, 'person', rowsOf(p.cards, `person:${p.name}`, o), false)),
    section('running', 'Running', 'play-circle', rowsOf(running, 'running', o), false),
    section('parked', 'Parked or relayed', 'debug-pause', rowsOf(parked, 'parked', o), false),
    section('ships', 'Ships', 'milestone', b.ships.map((s) => shipRow(s, o)), false, false, byMotion),
    section('done', 'Done today', 'pass', rowsOf(done, 'done', o), false),
  ];
  const kept = sections.filter((s) => s.count > 0);
  // Tree ids must be unique across the view: a repeat gets `#2`, `#3`.
  const seen = new Map<string, number>();
  for (const sec of kept) {
    for (const r of sec.rows) {
      const k = (seen.get(r.id) ?? 0) + 1;
      seen.set(r.id, k);
      if (k > 1) r.id = `${r.id}#${k}`;
    }
  }
  return kept;
}

/** The view's description: `3 for Ada · 1 stalled`, or null for an empty board. */
export function boardHeadline(b: Board): string | null {
  const parts: string[] = [];
  if (b.needsOwner > 0) parts.push(`${b.needsOwner} for ${b.owner ?? 'you'}`);
  if (b.stalled) parts.push(`${b.stalled} stalled`);
  const running = b.columns.find((c, i) => columnTone(c.name, i) === 'running')?.cards.length ?? 0;
  if (running) parts.push(`${running} running`);
  return parts.length ? parts.join(' · ') : null;
}

/** `5m ago`, `3h ago`, `yesterday`, `3d ago`: relativeTime as a phrase. */
export function agoPhrase(at: number, nowMs: number): string {
  const r = relativeTime(at, nowMs);
  return r === 'yesterday' ? r : `${r} ago`;
}

/** The line above the tree: the week, and the board's age once it is old enough to matter. */
export function boardMessage(b: Board, nowMs: number, note?: string | null): string | null {
  const parts: string[] = [];
  if (note) parts.push(note);
  if (b.week) parts.push(b.week.replace(/,? sampled .*$/, ''));
  const old = nowMs - b.asOf * 1000;
  if (b.asOf && old > BOARD_FILE_FRESH_MS) parts.push(`board from ${agoPhrase(b.asOf * 1000, nowMs)}: refresh reads a fresh one`);
  return parts.length ? parts.join(' — ') : null;
}

/** What helm says about Sheepfold's session rows: stalls and waits on the board, and skippers. */
export interface HelmNote {
  kind: 'stall' | 'waiting' | 'skipper';
  /** A word for the row's description. */
  word: string;
  /** A line for the row's tooltip. */
  line: string;
}

export function helmNotes(b: Board | null, skippers: ReadonlyMap<string, string>): Map<string, HelmNote> {
  const out = new Map<string, HelmNote>();
  for (const [id, scope] of skippers) {
    out.set(id, { kind: 'skipper', word: 'skipper', line: `Helm: the skipper of ${scope}` });
  }
  for (const col of b?.columns ?? []) {
    for (const c of col.cards) {
      // A guarded card shows nothing beyond its column on the board, and nothing here either.
      if (!c.session || c.guarded) continue;
      if (c.kind === 'stall') out.set(c.session, { kind: 'stall', word: 'stalled', line: `Helm: stalled — ${c.rule ?? c.title}${c.evidence ? ` (${c.evidence})` : ''}` });
      else if ((c.kind === 'waiting' || c.kind === 'permission') && !out.has(c.session)) out.set(c.session, { kind: 'waiting', word: '', line: `Helm: waiting on ${b?.owner ?? 'you'}` });
    }
  }
  return out;
}

/** Skipper sessions from `regatta helm skipper --status --json`: session id → scope. */
export function parseSkippers(text: string): Map<string, string> {
  const out = new Map<string, string>();
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    return out;
  }
  const scopes = (data as { scopes?: unknown } | null)?.scopes;
  for (const sc of Array.isArray(scopes) ? scopes : []) {
    const scope = s((sc as Record<string, unknown>)?.scope) ?? '?';
    const record = (sc as Record<string, unknown>)?.record as Record<string, unknown> | null;
    const ids = [s(record?.session)];
    for (const h of Array.isArray((sc as Record<string, unknown>)?.holders) ? ((sc as Record<string, unknown>).holders as unknown[]) : []) {
      const r = h as Record<string, unknown>;
      if (r && r.alive !== false) ids.push(s(r.session));
    }
    for (const id of ids) if (id) out.set(id, scope);
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// The navigator: `regatta navigate status` and `regatta navigate next --json`.

export interface LiveMeeting {
  id: string;
  /** The server answers and the page is up. */
  alive: boolean;
  status: string | null;
  url: string | null;
  /** For a meeting left over: what the navigator says to do. */
  note: string | null;
}

/**
 * `navigate status` prints one line per meeting folder: `<id>  <status>  <url>` while its server
 * runs, else `<id>  <why> — navigate stop <id>` or `<id>  not running`; `no meetings` for none.
 */
export function parseNavStatus(text: string): LiveMeeting[] {
  const out: LiveMeeting[] = [];
  for (const line of text.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || /^no meetings$/i.test(t)) continue;
    const [id, ...rest] = t.split(/\s{2,}/);
    if (!id || /\s/.test(id)) continue;
    const tail = rest.join('  ');
    const url = /(https?:\/\/\S+)\s*$/.exec(tail)?.[1] ?? null;
    if (url) {
      out.push({ id, alive: true, status: tail.replace(url, '').trim() || null, url, note: null });
    } else {
      out.push({ id, alive: false, status: null, url: null, note: tail || 'not running' });
    }
  }
  return out;
}

export interface Meeting {
  event: string;
  name: string;
  /** Milliseconds since the epoch; null for an all-day one. */
  start: number | null;
  end: number | null;
  allDay: boolean;
  org: string | null;
  /** Two organizations claim it: the start asks which. */
  ask: boolean;
  /** Marked `network:` — the navigator refuses to listen. */
  refused: boolean;
  lang: string;
  /** The prepared brief's path, when there is one. */
  brief: string | null;
}

function when(v: unknown): number | null {
  const r = v as { dateTime?: unknown; date?: unknown } | null;
  const t = s(r?.dateTime) ?? s(r?.date);
  if (!t) return null;
  const ms = Date.parse(t);
  return Number.isFinite(ms) ? ms : null;
}

/** `navigate next --json`: a list of meetings, soonest first. Throws a short Error on bad JSON. */
export function parseMeetings(text: string): Meeting[] {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error('the navigator did not return JSON');
  }
  if (!Array.isArray(data)) throw new Error('the navigator returned no list of meetings');
  return data
    .filter((m): m is Record<string, unknown> => !!m && typeof m === 'object' && !!s((m as Record<string, unknown>).name))
    .map((m) => ({
      event: s(m.event) ?? '',
      name: s(m.name) as string,
      start: when(m.start),
      end: when(m.end),
      allDay: m.all_day === true,
      org: s(m.org),
      ask: m.ask === true,
      refused: !!m.network,
      lang: s(m.lang) ?? 'auto',
      brief: s(m.brief),
    }));
}

/** `in 25m`, `in 2h`, `now`, `started 5m ago`, `tomorrow 09:30`. */
export function meetingWhen(m: Meeting, nowMs: number): string {
  if (m.allDay || m.start === null) return 'all day';
  const d = m.start - nowMs;
  if (d <= 0) return m.end !== null && m.end < nowMs ? 'over' : d > -60_000 ? 'now' : `started ${agoPhrase(m.start, nowMs)}`;
  if (d < 60_000) return 'in under a minute';
  // Whole minutes, floored: rounding up shows `in 60m` and `in 1h 60m`.
  const mins = Math.floor(d / 60_000);
  if (mins < 60) return `in ${mins}m`;
  if (d < 12 * 60 * 60_000) {
    const h = Math.floor(mins / 60);
    const min = mins % 60;
    return min ? `in ${h}h ${min}m` : `in ${h}h`;
  }
  const at = new Date(m.start);
  const hhmm = `${String(at.getHours()).padStart(2, '0')}:${String(at.getMinutes()).padStart(2, '0')}`;
  const day = new Date(nowMs);
  const tomorrow = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
  const same = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  if (same(at, tomorrow)) return `tomorrow ${hhmm}`;
  return `${at.toLocaleDateString(undefined, { weekday: 'short' })} ${hhmm}`;
}

/** The arguments that start a meeting's navigator, or bring its window back when it runs. */
export function launchArgs(m: Meeting): string[] {
  const args = ['navigate', 'launch', '--name', m.name];
  if (m.event) args.push('--event', m.event);
  if (m.lang && m.lang !== 'auto') args.push('--lang', m.lang);
  return args;
}

/** Nudge from five minutes before a meeting to ten after its start, unless one is listening. */
export const MEETING_NUDGE_BEFORE_MS = 5 * 60_000;
export const MEETING_NUDGE_AFTER_MS = 10 * 60_000;

export function meetingNudge(meetings: readonly Meeting[], live: readonly LiveMeeting[], nowMs: number): Meeting | null {
  if (live.some((l) => l.alive)) return null;
  return (
    meetings.find(
      (m) =>
        !m.allDay &&
        !m.refused &&
        m.start !== null &&
        m.start - nowMs <= MEETING_NUDGE_BEFORE_MS &&
        nowMs - m.start <= MEETING_NUDGE_AFTER_MS,
    ) ?? null
  );
}

// ---------------------------------------------------------------------------------------------
// The navigator's shared answer: one `navigate next` per profile, kept in a file every window of
// it reads (regattaView's readNext does the I/O; the decisions are here, where tests reach them).

export interface NextCache {
  /** Milliseconds: when the answer was written, or the read claimed. */
  at: number;
  /** The last good answer, kept through a failed read. */
  text: string | null;
  /** The last read's failure; null after a good one. */
  error: string | null;
}

/** The cache file's content as a NextCache, or null when it is not one. */
export function parseNextCache(raw: string): NextCache | null {
  try {
    const d = JSON.parse(raw) as Record<string, unknown> | null;
    if (!d || typeof d !== 'object' || typeof d.at !== 'number') return null;
    return { at: d.at, text: typeof d.text === 'string' ? d.text : null, error: typeof d.error === 'string' ? d.error : null };
  } catch {
    return null;
  }
}

/**
 * What a window does with the cache: `take` a fresh answer (its text and error); wait while a
 * fresh claim has none yet (`pending`: another window's read is running, or the profile's first);
 * else `ask` the navigator itself, claiming the cache first.
 */
export function nextCacheStep(c: NextCache | null, nowMs: number, everyMs: number, force: boolean): 'take' | 'pending' | 'ask' {
  if (force || !c || nowMs - c.at >= everyMs) return 'ask';
  return c.text === null && c.error === null ? 'pending' : 'take';
}

/** A read's result is written back only while the cache still holds its own claim: a later claim's answer is newer. */
export function stillClaimed(c: NextCache | null, claimAt: number): boolean {
  return c?.at === claimAt;
}
