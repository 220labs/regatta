// The Board and Meetings views: regatta's helm board and navigator in Regatta's own sidebar. The
// logic is src/regatta.ts; this file runs the CLI, keeps the views fresh and acts on clicks.
// `regatta.helm` and `regatta.navigator` say which module answers and gate the views;
// `regatta.found` says the CLI answers at all, and `regatta.status` is `missing` without it, so the
// Board view's welcome can say how to add it. Moved from Sheepfold's src/regattaView.ts (2026-11-02).

import * as vscode from 'vscode';
import { execFile } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { expandHome, firstLine, moreLabel } from './util';
import {
  BOARD_CLI_EVERY_MS,
  BOARD_PER_SECTION,
  Board,
  boardCacheDir,
  BoardNode,
  HelmNote,
  LiveMeeting,
  Link,
  Meeting,
  NextCache,
  boardFileCandidates,
  boardHeadline,
  boardLayout,
  boardMessage,
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
} from './regatta';

export interface RegattaDeps {
  log(): vscode.LogOutputChannel | undefined;
  /** A spacesheep page in the mirror's tab when it runs, any other page in the browser. */
  openPage(url: string): Promise<void>;
  /** Open a session Sheepfold lists; false when it lists none with that id, or Sheepfold is absent. */
  openSession(id: string): Promise<boolean>;
  /** Sheepfold is there to go to sessions (it may still not list a given one). */
  hasSessions(): boolean;
  sessionLabel(id: string): string | null;
  sessionIcon(id: string): vscode.TreeItem['iconPath'] | undefined;
  setHelmNotes(notes: Map<string, HelmNote>): void;
}

function settings() {
  return vscode.workspace.getConfiguration('regatta');
}

/**
 * Each setting's key in Sheepfold 0.8.0, which held these views: a value set there and not here
 * still counts, so the split drops no choice the owner made (a CLI path, a board file, nudges off).
 */
const SHEEPFOLD_KEYS: Record<string, string> = {
  cli: 'regatta.cli',
  boardFile: 'regatta.boardFile',
  perSection: 'regatta.perSection',
  nudges: 'nudges',
};

function setting<T>(key: string, fallback: T): T {
  const own = settings().inspect<T>(key);
  if (own && (own.globalValue ?? own.workspaceValue ?? own.workspaceFolderValue) !== undefined) return settings().get<T>(key, fallback);
  const old = SHEEPFOLD_KEYS[key];
  return (old ? vscode.workspace.getConfiguration('sheepfold').get<T>(old) : undefined) ?? fallback;
}

/** A configuration change that touches a setting here or its Sheepfold 0.8.0 key. */
function touches(e: vscode.ConfigurationChangeEvent, key: string): boolean {
  return e.affectsConfiguration(`regatta.${key}`) || (key in SHEEPFOLD_KEYS && e.affectsConfiguration(`sheepfold.${SHEEPFOLD_KEYS[key]}`));
}

function nudgesOn(): boolean {
  return setting<boolean>('nudges', true);
}

/** What `helm` runs with: the cache dir a set board file names (boardCacheDir), so `helm board` writes that file and `helm open` reads the same cache. */
function helmEnv(): Record<string, string> | undefined {
  const dir = boardCacheDir(setting<string>('boardFile', ''), os.homedir());
  return dir ? { PLAN_CACHE_DIR: dir } : undefined;
}

/** A CLI that failed; `timedOut`: it was killed at its timeout, so its answer is unknown, not no. */
class CliError extends Error {
  constructor(
    message: string,
    readonly timedOut: boolean,
    /** The program itself is gone (a moved clone, a removed worktree): it is looked up again. */
    readonly gone = false,
  ) {
    super(message);
  }
}

const timedOut = (e: unknown) => e instanceof CliError && e.timedOut;

/**
 * Run a CLI. On Windows a `.cmd` shim runs only through a shell, the program quoted (as Sheepfold
 * runs the spacesheep CLI). `env`: variables added to this process's own.
 */
function run(program: string, args: readonly string[], timeout: number, env?: Record<string, string>): Promise<string> {
  const win = process.platform === 'win32';
  const command = win ? [`"${program.replace(/"/g, '')}"`, ...args.map((a) => `"${a.replace(/"/g, '')}"`)].join(' ') : program;
  return new Promise((resolve, reject) => {
    const opts = { timeout, maxBuffer: 32 * 1024 * 1024, windowsHide: true, shell: win, env: env ? { ...process.env, ...env } : undefined };
    execFile(command, win ? [] : [...args], opts, (err, stdout, stderr) => {
      if (err) reject(new CliError(firstLine(String(stderr)) || err.message, err.killed === true, (err as NodeJS.ErrnoException).code === 'ENOENT'));
      else resolve(String(stdout));
    });
  });
}

function readHomeFile(): string | null {
  const dir = process.env.REGATTA_CONFIG ? expandHome(process.env.REGATTA_CONFIG, os.homedir()) : path.join(os.homedir(), '.config', 'regatta');
  try {
    return fs.readFileSync(path.join(dir, 'home'), 'utf8');
  } catch {
    return null;
  }
}

/** The `regatta` CLI: found once (the first candidate whose `regatta root` answers), then reused. */
class Regatta {
  private program: string | null | undefined;
  private finding: Promise<string | null> | null = null;
  /** The last find() found nothing, but a candidate timed out: absent is not known. */
  uncertain = false;
  // Bumped by forget(): a lookup started before a settings change never caches its answer.
  private generation = 0;

  constructor(private readonly deps: RegattaDeps) {}

  forget(): void {
    this.generation++;
    this.program = undefined;
    this.finding = null;
  }

  find(): Promise<string | null> {
    if (this.program !== undefined) return Promise.resolve(this.program);
    const gen = this.generation;
    const keep = (p: string | null) => {
      if (gen === this.generation) this.program = p;
      return p;
    };
    this.finding ??= (async () => {
      const tried: string[] = [];
      let slow = false;
      for (const c of regattaCandidates(setting<string>('cli', ''), process.env, readHomeFile())) {
        const program = expandHome(c, os.homedir());
        try {
          await run(program, ['root'], 15_000);
          this.deps.log()?.info(`regatta: ${program}`);
          if (gen === this.generation) this.uncertain = false;
          return keep(program);
        } catch (e) {
          slow ||= timedOut(e);
          tried.push(`${program} (${e instanceof Error ? e.message : String(e)})`);
        }
      }
      this.deps.log()?.info(`regatta: none — tried ${tried.join('; ')}`);
      if (gen === this.generation) this.uncertain = slow;
      // A timeout is not cached: the next find asks again.
      return slow ? null : keep(null);
    })().finally(() => {
      if (gen === this.generation) this.finding = null;
    });
    return this.finding;
  }

  /** True, false, or null when it could not tell (`has` timed out: a loaded Mac, not an answer). */
  async has(module: string): Promise<boolean | null> {
    const p = await this.find();
    if (!p) return this.uncertain ? null : false;
    try {
      await run(p, ['has', module], 15_000);
      return true;
    } catch (e) {
      return timedOut(e) ? null : false;
    }
  }

  async run(args: readonly string[], timeout: number, env?: Record<string, string>): Promise<string> {
    const p = await this.find();
    if (!p) throw new CliError(this.missingWhy(), this.uncertain);
    try {
      return await run(p, args, timeout, env);
    } catch (e) {
      if (e instanceof CliError && e.gone) this.forget();
      throw e;
    }
  }

  /** Why there is no CLI to run: not found, or found too slow to answer (a loaded machine). */
  missingWhy(): string {
    return this.uncertain ? 'regatta did not answer `regatta root` within 15 s (a loaded machine?)' : 'regatta not found';
  }

  /** A terminal running one regatta command, for what may prompt or take a while. */
  async terminal(name: string, args: readonly string[]): Promise<void> {
    const p = await this.find();
    if (!p) {
      void vscode.window.showWarningMessage(
        this.uncertain
          ? `${name}: nothing started — ${this.missingWhy()}. Try again in a moment.`
          : `${name}: the regatta CLI was not found, so nothing started. Set regatta.cli to its full path.`,
      );
      return;
    }
    const t = vscode.window.createTerminal({ name, shellPath: p, shellArgs: [...args], iconPath: new vscode.ThemeIcon('compass') });
    t.show();
  }
}

// ---------------------------------------------------------------------------------------------
// The Board view.

const ICON_COLOR: Record<string, string> = {
  warning: 'list.warningForeground',
  error: 'list.errorForeground',
  pass: 'testing.iconPassed',
  'git-merge': 'charts.purple',
  'git-pull-request': 'charts.green',
};

function themeIcon(id: string, color?: string): vscode.ThemeIcon {
  const c = color ?? ICON_COLOR[id.replace(/~.*$/, '')];
  return new vscode.ThemeIcon(id, c ? new vscode.ThemeColor(c) : undefined);
}

function tooltipOf(title: string, lines: readonly string[], hint?: string): vscode.MarkdownString {
  const md = new vscode.MarkdownString(undefined, false);
  md.appendText(title);
  md.appendMarkdown('\n\n');
  for (const l of lines) {
    md.appendText(l);
    md.appendMarkdown('  \n');
  }
  if (hint) {
    md.appendMarkdown('\n');
    md.appendText(hint);
  }
  return md;
}

function linkHint(link: Link | null): string | undefined {
  if (!link) return undefined;
  switch (link.kind) {
    case 'web':
      return /github\.com/.test(link.url) ? 'Click: open on GitHub' : 'Click: open its page';
    case 'session':
      return 'Click: go to the session';
    case 'file':
      return 'Click: open the doc';
    case 'ship':
      return "Click: the ship's page";
  }
}

class BoardProvider implements vscode.TreeDataProvider<BoardNode> {
  private readonly changed = new vscode.EventEmitter<BoardNode | undefined>();
  readonly onDidChangeTreeData = this.changed.event;

  board: Board | null = null;
  private nodes: BoardNode[] = [];
  error: string | null = null;
  /** A fresh board is being asked of the CLI (it reads every repo's pull requests: a minute or so). */
  reading = false;
  private lastCliRun = 0;
  private skippers = new Map<string, string>();
  private lastSkippers = 0;
  // Sections whose fold the user opened; in memory only, as in Sheepfold's sessions view.
  private readonly unfolded = new Set<string>();

  constructor(
    private readonly regatta: Regatta,
    private readonly deps: RegattaDeps,
  ) {}

  get status(): 'loading' | 'error' | 'empty' | 'ok' {
    if (this.board) return this.nodes.length ? 'ok' : 'empty';
    if (this.error) return 'error';
    return 'loading';
  }

  relayout(): void {
    if (this.board) {
      this.nodes = boardLayout(this.board, {
        nowMs: Date.now(),
        sessionLabel: (id) => this.deps.sessionLabel(id),
        perSection: setting<number>('perSection', BOARD_PER_SECTION),
        unfolded: this.unfolded,
      });
    }
    this.changed.fire(undefined);
  }

  private missingSaid = false;

  /**
   * Forget the board: helm no longer answers (so the view's welcome says why, not a frozen board),
   * or the board file setting changed (a board from the old file must not outrank the new one).
   * A read already running (a `helm board` of a minute or more, a skipper status) belongs to the
   * generation before: its result is dropped, never put back over the reset.
   */
  reset(): void {
    this.generation++;
    this.board = null;
    this.nodes = [];
    this.error = null;
    this.errorAt = 0;
    this.readWhy = null;
    this.missingSaid = false;
    this.lastCliRun = 0;
    this.reading = false;
    this.skippers = new Map();
    this.lastSkippers = 0;
    this.changed.fire(undefined);
  }

  private generation = 0;

  private boardFile(): string {
    return boardFileCandidates(setting<string>('boardFile', ''), process.env, os.homedir())[0];
  }

  /** Why the board file did not read last: null after a good read; `missing` for no file at all. */
  private readWhy: { missing: boolean; why: string } | null = null;
  /** When a `helm board` read failed: its error stands until a board newer than that is read. */
  private errorAt = 0;

  /** The board file, when it reads; logs why not (a missing file only when the setting names it). */
  private readFile(): boolean {
    const file = this.boardFile();
    try {
      const board = parseBoard(fs.readFileSync(file, 'utf8'));
      if (!this.board || board.asOf >= this.board.asOf) this.board = board;
      this.readWhy = null;
      // The same old file read again says nothing about a refresh that failed since.
      if (!this.errorAt || board.asOf * 1000 > this.errorAt) {
        this.error = null;
        this.errorAt = 0;
      }
      return true;
    } catch (e) {
      const missing = (e as NodeJS.ErrnoException).code === 'ENOENT';
      this.readWhy = { missing, why: e instanceof Error ? e.message : String(e) };
      if (!missing || (setting<string>('boardFile', '').trim() && !this.missingSaid)) {
        this.missingSaid = this.missingSaid || missing;
        this.deps.log()?.warn(`board file ${file}: ${e instanceof Error ? e.message : String(e)}`);
      }
      return false;
    }
  }

  /**
   * The board file helm's poll writes, whatever its age (the message says it). The CLI only when
   * asked (the refresh button), or, while the view shows, when there is no board file, at most
   * every 30 minutes.
   */
  async refresh(force = false, visible = true): Promise<void> {
    const gen = this.generation;
    const found = this.readFile();
    // A board file helm cannot write (boardCacheDir false) is never asked of the CLI on the timer:
    // each run would read every repo and still leave the file missing. The view says so instead of
    // "Reading the board…".
    const writable = boardCacheDir(setting<string>('boardFile', ''), os.homedir()) !== false;
    if (!found && !writable && !this.board) {
      this.error =
        this.readWhy && !this.readWhy.missing
          ? `the board file at ${this.boardFile()} does not read: ${this.readWhy.why}`
          : `no board file at ${this.boardFile()}; helm board writes only <dir>/overview/state.json, so only what writes this file can fill it`;
    }
    if (force || (!found && writable && visible && Date.now() - this.lastCliRun > BOARD_CLI_EVERY_MS)) void this.readFromCli();
    const skippersDue = Date.now() - this.lastSkippers > 5 * 60_000;
    if (skippersDue) {
      // The file's board shows at once; the skipper notes (a CLI call of up to 30 s) follow.
      if (found) {
        this.deps.setHelmNotes(helmNotes(this.board, this.skippers));
        this.relayout();
      }
      this.lastSkippers = Date.now();
      let skippers = new Map<string, string>();
      try {
        skippers = parseSkippers(await this.regatta.run(['helm', 'skipper', '--status', '--json'], 30_000));
      } catch (e) {
        // a timeout is no answer: the skippers known stand; any other failure: none known
        if (timedOut(e)) skippers = this.skippers;
      }
      if (gen !== this.generation) return;
      this.skippers = skippers;
    }
    this.deps.setHelmNotes(helmNotes(this.board, this.skippers));
    this.relayout();
  }

  private async readFromCli(): Promise<void> {
    if (this.reading) return;
    const gen = this.generation;
    this.reading = true;
    this.lastCliRun = Date.now();
    this.changed.fire(undefined);
    let error: string | null = null;
    try {
      // Without --json, helm writes the board file (and deploys nothing), so this one read serves
      // every window; with --json it would print it and write nothing. A board file the setting
      // names is helm's own once its cache dir is passed; any other file helm cannot write.
      const dir = boardCacheDir(setting<string>('boardFile', ''), os.homedir());
      if (dir === false) throw new Error(`helm board writes <cache dir>/overview/state.json, never ${this.boardFile()}: point regatta.boardFile at such a file, or leave it empty`);
      await this.regatta.run(['helm', 'board'], 240_000, helmEnv());
      if (gen !== this.generation) return;
      if (!this.readFile()) throw new Error(`helm board wrote no board at ${this.boardFile()}`);
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      if (gen === this.generation) this.reading = false;
    }
    if (gen !== this.generation) return;
    if (error) {
      this.error = error;
      this.errorAt = Date.now();
      this.deps.log()?.warn(`board: ${error}`);
    }
    this.deps.setHelmNotes(helmNotes(this.board, this.skippers));
    this.relayout();
  }

  toggleFold(section: string): void {
    if (!this.unfolded.delete(section)) this.unfolded.add(section);
    this.relayout();
  }

  getChildren(node?: BoardNode): BoardNode[] {
    if (!node) return this.nodes;
    if (node.kind !== 'section') return [];
    return node.more ? [...node.shown, { kind: 'more', id: `${node.id}:more`, section: node.id, more: node.more }] : node.shown;
  }

  getTreeItem(node: BoardNode): vscode.TreeItem {
    const C = vscode.TreeItemCollapsibleState;
    const warn = 'list.warningForeground';
    if (node.kind === 'section') {
      const item = new vscode.TreeItem(node.label, node.expanded ? C.Expanded : C.Collapsed);
      item.id = node.id;
      item.description = String(node.count);
      item.iconPath = themeIcon(node.icon, node.warn ? warn : undefined);
      item.contextValue = 'boardSection';
      return item;
    }
    if (node.kind === 'more') {
      const item = new vscode.TreeItem(moreLabel(node.more), C.None);
      item.id = node.id;
      item.iconPath = new vscode.ThemeIcon(node.more.kind === 'more' ? 'ellipsis' : 'fold-up');
      item.contextValue = 'more';
      item.command = { command: 'regatta.board.toggleFold', title: 'Toggle', arguments: [node] };
      return item;
    }
    const item = new vscode.TreeItem(node.label, C.None);
    item.id = node.id;
    item.description = node.description;
    // A session's row wears its model's mark, as in Sheepfold's sessions view.
    item.iconPath = (node.session ? this.deps.sessionIcon(node.session) : undefined) ?? themeIcon(node.icon, node.warn ? warn : undefined);
    item.tooltip = tooltipOf(node.label, node.tooltip, linkHint(node.link));
    item.contextValue = ['boardRow', node.link ? 'hasLink' : '', node.github ? 'hasGitHub' : ''].filter(Boolean).join(' ');
    if (node.link) item.command = { command: 'regatta.board.open', title: 'Open', arguments: [node] };
    return item;
  }
}

// ---------------------------------------------------------------------------------------------
// The Meetings view.

// `id`: the tree id, made unique in getChildren (one event can come from two calendars).
type MeetingNode = { kind: 'live'; live: LiveMeeting } | { kind: 'next'; meeting: Meeting; id: string };

class MeetingsProvider implements vscode.TreeDataProvider<MeetingNode> {
  private readonly changed = new vscode.EventEmitter<MeetingNode | undefined>();
  readonly onDidChangeTreeData = this.changed.event;

  live: LiveMeeting[] = [];
  next: Meeting[] = [];
  // Kept apart: a good `status` must not hide a calendar read that failed.
  statusError: string | null = null;
  nextError: string | null = null;
  loaded = false;

  /** `cache`: a file every window of this profile shares, so the calendar is read once, not per window. */
  constructor(
    private readonly regatta: Regatta,
    private readonly cache: string,
  ) {}

  get error(): string | null {
    return this.nextError ?? this.statusError;
  }

  get status(): 'loading' | 'error' | 'empty' | 'ok' {
    if (!this.loaded) return 'loading';
    if (this.live.length || this.upcoming().length) return 'ok';
    return this.error ? 'error' : 'empty';
  }

  /** The coming meetings worth a row: not all-day, not over, at most three. */
  upcoming(now = Date.now()): Meeting[] {
    return this.next.filter((m) => !m.allDay && (m.end ?? m.start ?? 0) > now).slice(0, 3);
  }

  /** Forget everything: the navigator no longer answers. A read still running is dropped. */
  reset(): void {
    this.resetGen++;
    this.statusSeq++;
    this.readSeq++;
    this.live = [];
    this.next = [];
    this.statusError = null;
    this.nextError = null;
    this.loaded = false;
    this.changed.fire(undefined);
  }

  private statusSeq = 0;
  private resetGen = 0;

  /**
   * `status` every time (local and quick); `next`, a calendar read, every 5 minutes while the view
   * shows and every 15 while it is hidden (the meeting nudge needs it), or when forced.
   */
  async refresh(force = false, visible = true, nudges = true): Promise<void> {
    const gen = this.resetGen;
    // Only the newest `navigate status` is kept: an older one landing late (a slow Mac, 20 s) would
    // put back "not running" over the live row a start just brought. The rest of a superseded
    // refresh still runs: a forced calendar read is the click's whole point.
    const mine = ++this.statusSeq;
    try {
      const live = parseNavStatus(await this.regatta.run(['navigate', 'status'], 20_000));
      if (mine === this.statusSeq) {
        this.live = live;
        this.statusError = null;
      }
    } catch (e) {
      // The last answer stands (a timeout on a loaded Mac is no meeting ended): emptied, a meeting
      // being recorded would lose its Stop row and the nudge would ask to start it. The message says it.
      if (mine === this.statusSeq) this.statusError = e instanceof Error ? e.message : String(e);
    }
    if (gen !== this.resetGen) return;
    // Hidden with nudges off, nothing needs the next meetings. While another window's read is
    // pending, a view never loaded stays on loading rather than saying "No meetings".
    const answered = force || visible || nudges ? await this.readNext(force, (visible ? 5 : 15) * 60_000) : true;
    if (gen !== this.resetGen) return;
    if (answered || this.live.length) this.loaded = true;
    this.changed.fire(undefined);
  }

  /**
   * `navigate next` refreshes a Google token and reads the calendars: once per profile, not per
   * window. The answer is kept in the shared cache file with its time; a window takes it while it
   * is younger than `everyMs`, and the first to find it older asks again (claimed at once, so two
   * windows rarely ask together). A failed read is kept there too (`error`, beside the last good
   * `text`), so every window says it until the next ask; a fresh claim with no answer yet is
   * `pending`, neither an answer nor a reason to ask (nextCacheStep). A read writes its result back
   * only while the cache still holds its own claim, and this window keeps only its newest read's
   * result: an older read ending late never overwrites a newer one. Returns false while pending.
   */
  private readSeq = 0;

  private readCache(): NextCache | null {
    try {
      return parseNextCache(fs.readFileSync(this.cache, 'utf8'));
    } catch {
      return null;
    }
  }

  /** Through a temporary file and a rename, so another window never reads half a write. */
  private writeCache(c: NextCache): void {
    try {
      fs.mkdirSync(path.dirname(this.cache), { recursive: true });
      const tmp = `${this.cache}.${process.pid}.tmp`;
      fs.writeFileSync(tmp, JSON.stringify(c));
      fs.renameSync(tmp, this.cache);
    } catch {
      // no shared cache: this window still has its answer
    }
  }

  private async readNext(force: boolean, everyMs: number): Promise<boolean> {
    const cached = this.readCache();
    const step = nextCacheStep(cached, Date.now(), everyMs, force);
    if (step === 'pending') return false;
    if (step === 'take' && cached) {
      try {
        if (cached.text !== null) this.next = parseMeetings(cached.text);
        this.nextError = cached.error;
        return true;
      } catch {
        // a bad cache is asked again below
      }
    }
    const mine = ++this.readSeq;
    const claim: NextCache = { at: Date.now(), text: cached?.text ?? null, error: cached?.error ?? null };
    this.writeCache(claim);
    let text: string | null = null;
    let error: string | null = null;
    try {
      text = await this.regatta.run(['navigate', 'next', '--all', '--days', '2', '--json'], 60_000);
      this.next = mine === this.readSeq ? parseMeetings(text) : this.next;
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
      text = null;
    }
    if (mine === this.readSeq) this.nextError = error;
    if (stillClaimed(this.readCache(), claim.at)) {
      this.writeCache({ at: Date.now(), text: text ?? claim.text, error });
    }
    return true;
  }

  getChildren(node?: MeetingNode): MeetingNode[] {
    if (node) return [];
    const up = this.upcoming();
    const seen = new Map<string, number>();
    const unique = (m: Meeting) => {
      const id = `meeting:${m.event || m.name}:${m.start ?? ''}`;
      const k = (seen.get(id) ?? 0) + 1;
      seen.set(id, k);
      return k > 1 ? `${id}#${k}` : id;
    };
    return [
      ...this.live.map((live): MeetingNode => ({ kind: 'live', live })),
      ...up.map((meeting): MeetingNode => ({ kind: 'next', meeting, id: unique(meeting) })),
    ];
  }

  getTreeItem(node: MeetingNode): vscode.TreeItem {
    if (node.kind === 'live') {
      const l = node.live;
      const item = new vscode.TreeItem(l.id, vscode.TreeItemCollapsibleState.None);
      item.id = `live:${l.id}`;
      if (l.alive) {
        item.description = [l.status, 'listening'].filter(Boolean).join(' · ');
        item.iconPath = themeIcon('record', 'testing.iconFailed');
        item.tooltip = tooltipOf(l.id, [`Live page: ${l.url}`], 'Click: the live page · Stop: stop listening and archive');
        item.command = { command: 'regatta.meetings.openLive', title: 'Open', arguments: [node] };
        item.contextValue = 'liveMeeting';
      } else {
        item.description = l.note ?? 'not running';
        item.iconPath = themeIcon('warning');
        item.tooltip = tooltipOf(l.id, [l.note ?? 'Not running.'], 'Stop: archive what it left');
        item.contextValue = 'leftoverMeeting';
      }
      return item;
    }
    const m = node.meeting;
    const item = new vscode.TreeItem(m.name, vscode.TreeItemCollapsibleState.None);
    item.id = node.id;
    const soon = m.start !== null && m.start - Date.now() < 10 * 60_000;
    item.description = [meetingWhen(m, Date.now()), m.refused ? 'not recorded' : m.org ?? (m.ask ? 'which org?' : null), m.lang !== 'auto' ? m.lang : null, m.brief ? 'brief ✓' : null]
      .filter(Boolean)
      .join(' · ');
    item.iconPath = m.refused ? themeIcon('circle-slash') : themeIcon(soon ? 'bell' : 'calendar', soon ? 'list.warningForeground' : undefined);
    const lines = [
      m.start ? `Starts: ${new Date(m.start).toLocaleString()}` : 'All day',
      m.org ? `Organization: ${m.org}` : m.ask ? 'Two organizations: the start asks which' : 'Your own',
      `Language: ${m.lang}`,
      m.brief ? `Brief: ${m.brief}` : 'No brief yet',
    ];
    if (m.refused) lines.push('Marked network: the navigator does not listen to it.');
    item.tooltip = tooltipOf(m.name, lines, m.refused ? undefined : m.brief ? 'Click: the brief · ▶: start the navigator' : m.event ? '▶: start the navigator · Prepare Brief: in the context menu' : '▶: start the navigator');
    // hasEvent: a brief is prepared by the event's id; `navigate brief --next` would brief another meeting.
    item.contextValue = ['meeting', m.refused ? 'refused' : 'startable', m.brief ? 'hasBrief' : '', m.event ? 'hasEvent' : ''].filter(Boolean).join(' ');
    if (m.brief) item.command = { command: 'regatta.meetings.openBrief', title: 'Open Brief', arguments: [node] };
    return item;
  }
}

// ---------------------------------------------------------------------------------------------

/** What extension.ts tells the Board when Sheepfold's sessions change: its rows take labels and marks from them. */
export interface RegattaHandle {
  sessionsChanged(): void;
}

export function activateRegatta(context: vscode.ExtensionContext, deps: RegattaDeps): RegattaHandle {
  const regatta = new Regatta(deps);
  const board = new BoardProvider(regatta, deps);
  const meetings = new MeetingsProvider(regatta, path.join(context.globalStorageUri.fsPath, 'navigator-next.json'));
  const boardView = vscode.window.createTreeView('regatta.board', { treeDataProvider: board, showCollapseAll: true });
  const meetingsView = vscode.window.createTreeView('regatta.meetings', { treeDataProvider: meetings });
  const ctx = (key: string, value: unknown) => void vscode.commands.executeCommand('setContext', key, value);

  let hasHelm = false;
  let hasNavigator = false;
  // What the Board view's welcome says before helm answers: `looking`, `missing` (no CLI),
  // `noModules` (a CLI with neither helm nor the navigator), then `helm`, or `navigator` alone.
  let found: 'looking' | 'missing' | 'noModules' | 'helm' | 'navigator' = 'looking';
  const publishFound = () => {
    ctx('regatta.status', found);
    // A CLI without either module is not Regatta added: the walkthrough step stays open.
    ctx('regatta.found', found === 'helm' || found === 'navigator');
    ctx('regatta.helm', hasHelm);
    ctx('regatta.navigator', hasNavigator);
  };
  publishFound();
  /**
   * Which modules answer. A full look (activation, a setting) may drop one; a look on focus only
   * adds what is missing, never asking again about a module that answered. A `root` or `has` that
   * timed out (a loaded Mac) is no answer: what was known stands.
   */
  // A look that could not tell (a timeout) looks again on its own, focus or not: in 30 s, then
  // doubling to 10 minutes while the CLI keeps timing out; a clear answer starts it over. A retry
  // after a full look is full too (a module known before is asked again, not taken as known).
  let retryTimer: NodeJS.Timeout | undefined;
  let retryDelay = 30_000;
  let disposed = false;
  const retrySoon = (full: boolean) => {
    clearTimeout(retryTimer);
    if (disposed) return;
    retryTimer = setTimeout(() => void start(full), retryDelay);
    retryDelay = Math.min(retryDelay * 2, 10 * 60_000);
  };
  const detect = async (full: boolean) => {
    if (full || found === 'missing' || found === 'looking') regatta.forget();
    const program = await regatta.find();
    if (!program) {
      if (regatta.uncertain) {
        // Not an answer: at the first look the welcome stays on "Looking…", later what was known stands.
        deps.log()?.warn(`regatta: ${regatta.missingWhy()}; looking again in ${Math.round(retryDelay / 1000)} s`);
        retrySoon(full);
        return;
      }
      clearTimeout(retryTimer);
      retryDelay = 30_000;
      hasHelm = hasNavigator = false;
      found = 'missing';
    } else {
      let unsure = false;
      const ask = async (module: string, had: boolean) => {
        if (!full && had) return true;
        const answer = await regatta.has(module);
        unsure ||= answer === null;
        return answer ?? had;
      };
      [hasHelm, hasNavigator] = await Promise.all([ask('helm', hasHelm), ask('navigator', hasNavigator)]);
      // a clear answer also drops a retry an earlier timeout armed (finish review)
      if (unsure) retrySoon(full);
      else { clearTimeout(retryTimer); retryDelay = 30_000; }
      // Unsure of both, after nothing was found: still looking, never "neither is installed".
      found = hasHelm ? 'helm' : hasNavigator ? 'navigator' : unsure && (found === 'looking' || found === 'missing') ? 'looking' : 'noModules';
    }
    publishFound();
    if (!hasHelm) {
      clearTimeout(boardTimer);
      deps.setHelmNotes(new Map());
      board.reset();
    }
    if (!hasNavigator) {
      clearTimeout(meetingsTimer);
      meetings.reset();
      updateMeetingItem();
    }
  };

  const publishBoard = () => {
    // `off` without helm, so only the welcome that says why (regatta.status) shows.
    ctx('regatta.boardStatus', hasHelm ? board.status : 'off');
    boardView.description = board.board ? (boardHeadline(board.board) ?? undefined) : undefined;
    const msg = board.board
      ? boardMessage(board.board, Date.now(), board.reading ? 'reading a fresh board…' : board.error ? `the last read failed: ${board.error}` : null)
      : board.reading
        ? 'Reading the board: it looks at every repo, so about a minute.'
        : board.error;
    boardView.message = msg ?? undefined;
  };
  const publishMeetings = () => {
    ctx('regatta.meetingsStatus', meetings.status);
    const live = meetings.live.filter((l) => l.alive).length;
    meetingsView.description = live ? `${live} listening` : undefined;
    // A failed read is said over a list it left standing, which may be stale.
    meetingsView.message =
      meetings.status === 'error'
        ? (meetings.error ?? undefined)
        : [meetings.nextError && `the calendar read failed: ${meetings.nextError}`, meetings.statusError && `navigate status failed: ${meetings.statusError}`]
            .filter(Boolean)
            .join(' — ') || undefined;
    meetingsView.badge = live ? { value: live, tooltip: `${live} meeting${live === 1 ? '' : 's'} listening` } : undefined;
  };
  board.onDidChangeTreeData(publishBoard);
  meetings.onDidChangeTreeData(publishMeetings);

  // The meeting nudge: from five minutes before the next meeting until ten after its start, while
  // nothing listens, a status-bar item that starts the navigator.
  const meetingItem = vscode.window.createStatusBarItem('regatta.meeting', vscode.StatusBarAlignment.Left, 49);
  meetingItem.name = 'Regatta meeting';
  const updateMeetingItem = () => {
    const m = hasNavigator && nudgesOn() ? meetingNudge(meetings.upcoming(), meetings.live, Date.now()) : null;
    if (!m) {
      meetingItem.hide();
      return;
    }
    meetingItem.text = `$(record) ${m.name} ${meetingWhen(m, Date.now())}`;
    meetingItem.tooltip = 'Click to start the navigator for it';
    meetingItem.command = { command: 'regatta.meetings.start', title: 'Start', arguments: [{ kind: 'next', meeting: m, id: 'nudge' }] };
    meetingItem.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
    meetingItem.show();
  };

  // One timer per view, rescheduled after each run so slow reads never overlap, and whatever the run
  // threw (a peer's sessionLabel, a file read): a throw once stopped the loop until a reload.
  const logged = (what: string) => (e: unknown) => deps.log()?.warn(`${what}: ${e instanceof Error ? e.message : String(e)}`);
  let boardTimer: NodeJS.Timeout | undefined;
  let meetingsTimer: NodeJS.Timeout | undefined;
  const scheduleBoard = () => {
    clearTimeout(boardTimer);
    if (!hasHelm || disposed) return;
    boardTimer = setTimeout(async () => {
      // helm may have gone since this was set (detect clears it too)
      if (!hasHelm) return;
      try {
        await board.refresh(false, boardView.visible);
      } catch (e) {
        logged('board')(e);
      } finally {
        scheduleBoard();
      }
    }, (boardView.visible ? 60 : 300) * 1000);
  };
  const scheduleMeetings = () => {
    clearTimeout(meetingsTimer);
    if (!hasNavigator || disposed) return;
    meetingsTimer = setTimeout(async () => {
      // the navigator may have gone since this was set (detect clears it too)
      if (!hasNavigator) return;
      try {
        await meetings.refresh(false, meetingsView.visible, nudgesOn());
        updateMeetingItem();
      } catch (e) {
        logged('meetings')(e);
      } finally {
        scheduleMeetings();
      }
    }, (meetingsView.visible ? 30 : 120) * 1000);
  };
  // One start at a time: a focus or a setting change while one runs asks for one more after it,
  // never a second in parallel (each would run `regatta root`, the board and the calendar again).
  let starting: Promise<void> | null = null;
  let again: 'full' | 'focus' | null = null;
  const startOnce = async (full: boolean) => {
    try {
      await detect(full);
      publishBoard();
      // The two views read different things: neither waits for the other.
      // allSettled: one view's throw never cuts the other's read short (it would overlap the next).
      const done = await Promise.allSettled([
        hasHelm ? board.refresh(false, boardView.visible) : Promise.resolve(),
        hasNavigator ? meetings.refresh(false, meetingsView.visible, nudgesOn()).then(updateMeetingItem) : Promise.resolve(),
      ]);
      for (const d of done) if (d.status === 'rejected') logged('start')(d.reason);
    } finally {
      scheduleBoard();
      scheduleMeetings();
    }
  };
  const start = (full = true): Promise<void> => {
    if (starting) {
      again = full || again === 'full' ? 'full' : 'focus';
      return starting;
    }
    let next: 'full' | 'focus' | null = full ? 'full' : 'focus';
    starting = (async () => {
      try {
        while (next) {
          again = null;
          await startOnce(next === 'full').catch(logged('start'));
          next = again;
        }
      } finally {
        starting = null;
      }
    })();
    return starting;
  };
  let lastFocusLook = Date.now();
  const ticker = setInterval(updateMeetingItem, 30_000);

  const meetingOf = (arg: unknown): Meeting | undefined => {
    const n = arg as MeetingNode | undefined;
    return n?.kind === 'next' ? n.meeting : undefined;
  };
  const liveOf = (arg: unknown): LiveMeeting | undefined => {
    const n = arg as MeetingNode | undefined;
    return n?.kind === 'live' ? n.live : undefined;
  };

  // A page regatta serves on 127.0.0.1, in a tab. In a Remote-SSH window regatta runs on the
  // remote host: its port is forwarded first.
  const openLocalPage = async (url: string) => {
    const external = await vscode.env.asExternalUri(vscode.Uri.parse(url));
    await vscode.commands.executeCommand('simpleBrowser.show', external.toString(true));
  };

  const openLink = async (link: Link) => {
    switch (link.kind) {
      case 'web':
        await deps.openPage(link.url);
        return;
      case 'session':
        if (await deps.openSession(link.id)) return;
        // Without Sheepfold (or a session it does not list), the card's own page, in the browser.
        if (link.url) await vscode.env.openExternal(vscode.Uri.parse(link.url));
        else
          void vscode.window.showInformationMessage(
            deps.hasSessions()
              ? `Session ${link.id.slice(0, 8)} is not in Sheepfold's recent sessions.`
              : `Session ${link.id.slice(0, 8)}: the board gives no page for it, and Sheepfold, which goes to sessions, is not installed.`,
          );
        return;
      case 'file':
        await vscode.commands.executeCommand('markdown.showPreview', vscode.Uri.file(link.path));
        return;
      case 'ship': {
        // helm serves the ship's page on 127.0.0.1 and prints its URL.
        try {
          const out = await regatta.run(['helm', 'open', link.id], 60_000, helmEnv());
          const url = /(https?:\/\/\S+)\s*$/.exec(out.trim())?.[1];
          if (url) await openLocalPage(url);
          else void vscode.window.showWarningMessage(`helm open said: ${firstLine(out) || 'nothing'}`);
        } catch (e) {
          void vscode.window.showWarningMessage(`Could not open the ship's page: ${e instanceof Error ? e.message : String(e)}`);
        }
        return;
      }
    }
  };

  context.subscriptions.push(
    boardView,
    meetingsView,
    meetingItem,
    { dispose: () => clearTimeout(boardTimer) },
    { dispose: () => clearTimeout(meetingsTimer) },
    // A start still running when the extension goes would re-arm the timers it schedules.
    { dispose: () => (disposed = true) },
    { dispose: () => clearTimeout(retryTimer) },
    { dispose: () => clearInterval(ticker) },
    boardView.onDidChangeVisibility(async (e) => {
      try {
        if (e.visible && hasHelm) await board.refresh();
      } catch (err) {
        logged('board')(err);
      } finally {
        scheduleBoard();
      }
    }),
    meetingsView.onDidChangeVisibility(async (e) => {
      try {
        if (e.visible && hasNavigator) await meetings.refresh();
      } catch (err) {
        logged('meetings')(err);
      } finally {
        scheduleMeetings();
      }
    }),
    // Regatta (or one of its two modules) installed after activation, or a `root` or `has` that
    // timed out on a loaded Mac: look again on a focus or activity change while either is missing,
    // asking only about what is missing (start(false)). `regatta root` and `has` are cheap, never
    // `helm board`; still, at most every 30 s with neither and every 10 minutes with one (today's
    // usual: helm without the navigator), so alt-tabbing runs no three processes each time.
    vscode.window.onDidChangeWindowState((w) => {
      if (!w.focused || (hasHelm && hasNavigator)) return;
      const every = hasHelm || hasNavigator ? 10 * 60_000 : 30_000;
      if (Date.now() - lastFocusLook < every) return;
      lastFocusLook = Date.now();
      void start(false);
    }),
    vscode.workspace.onDidChangeConfiguration((e) => {
      // Each setting does only what it needs: the fold relays out, the nudges re-judge the
      // meeting item, and the rest (the CLI, the board file) finds regatta again.
      if (touches(e, 'perSection')) board.relayout();
      if (touches(e, 'nudges')) updateMeetingItem();
      if (touches(e, 'boardFile')) board.reset();
      if (touches(e, 'cli') || touches(e, 'boardFile')) void start();
    }),
    vscode.commands.registerCommand('regatta.board.refresh', async () => {
      if (!hasHelm) return;
      await board.refresh(true);
      scheduleBoard();
    }),
    vscode.commands.registerCommand('regatta.board.open', async (arg: unknown) => {
      const node = arg as BoardNode | undefined;
      if (node?.kind === 'row' && node.link) await openLink(node.link);
    }),
    vscode.commands.registerCommand('regatta.board.toggleFold', (arg: unknown) => {
      const node = arg as BoardNode | undefined;
      if (node?.kind === 'more') board.toggleFold(node.section);
    }),
    vscode.commands.registerCommand('regatta.board.openOnGitHub', async (arg: unknown) => {
      const node = arg as BoardNode | undefined;
      if (node?.kind === 'row' && node.github) await vscode.env.openExternal(vscode.Uri.parse(node.github));
    }),
    vscode.commands.registerCommand('regatta.meetings.refresh', async () => {
      if (!hasNavigator) return;
      await meetings.refresh(true);
      updateMeetingItem();
      scheduleMeetings();
    }),
    vscode.commands.registerCommand('regatta.meetings.start', async (arg: unknown) => {
      const m = meetingOf(arg) ?? meetings.upcoming().find((x) => !x.refused);
      if (!hasNavigator || !m || m.refused) return;
      meetingItem.hide();
      await regatta.terminal(`Navigator · ${m.name}`, launchArgs(m));
      // The server takes a few seconds to come up; look again then.
      setTimeout(() => void meetings.refresh().then(updateMeetingItem), 8_000);
    }),
    vscode.commands.registerCommand('regatta.meetings.openLive', async (arg: unknown) => {
      const l = liveOf(arg);
      if (l?.url) await openLocalPage(l.url);
    }),
    vscode.commands.registerCommand('regatta.meetings.stop', async (arg: unknown) => {
      const l = liveOf(arg);
      if (!l) return;
      const pick = await vscode.window.showWarningMessage(
        l.alive ? `Stop listening to ${l.id}? The navigator archives what it heard.` : `Archive what ${l.id} left behind?`,
        { modal: true },
        l.alive ? 'Stop' : 'Archive',
      );
      if (!pick) return;
      await regatta.terminal(`Navigator · stop ${l.id}`, ['navigate', 'stop', l.id]);
      setTimeout(() => void meetings.refresh().then(updateMeetingItem), 5_000);
    }),
    vscode.commands.registerCommand('regatta.meetings.openBrief', async (arg: unknown) => {
      const m = meetingOf(arg);
      if (m?.brief) await vscode.commands.executeCommand('markdown.showPreview', vscode.Uri.file(m.brief));
    }),
    vscode.commands.registerCommand('regatta.meetings.prepareBrief', async (arg: unknown) => {
      const m = meetingOf(arg);
      if (!m) return;
      if (!m.event) {
        void vscode.window.showInformationMessage(`${m.name} carries no calendar event id, so no brief can be prepared for it from here.`);
        return;
      }
      await regatta.terminal(`Navigator · brief ${m.name}`, ['navigate', 'brief', '--event', m.event]);
    }),
  );

  void start();
  return {
    sessionsChanged: () => {
      if (board.board) board.relayout();
    },
  };
}
