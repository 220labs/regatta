// Regatta's VS Code extension: helm's board and the navigator's meetings (src/regattaView.ts), and
// the API Sheepfold reads helm's notes on its session rows from. The two extensions find each other
// at run time and neither depends on the other: without Sheepfold a board row takes its card's own
// title and a ThemeIcon, and a session card opens its page in the browser; without Regatta,
// Sheepfold's rows carry no helm notes. The contract is the same text in both repos' briefs
// (docs/blueprints/2026-11-02-regatta-vscode.md here): apiVersion 1 on each side.

import * as vscode from 'vscode';
import { HelmNote } from './regatta';
import { RegattaHandle, activateRegatta } from './regattaView';
import { apiOf, hasMembers, sameNotes } from './util';

/** What this extension exports: helm's notes on sessions, for Sheepfold's rows. */
export interface RegattaApi {
  readonly apiVersion: 1;
  helmNotes(): ReadonlyMap<string, HelmNote>;
  onDidChangeHelmNotes: vscode.Event<void>;
}

/** What Sheepfold exports, read when it is installed and speaks apiVersion 1. */
export interface SheepfoldApi {
  readonly apiVersion: 1;
  sessionLabel(id: string): string | null;
  sessionIcon(id: string): vscode.TreeItem['iconPath'] | undefined;
  openSession(id: string): Promise<boolean>;
  openPage(url: string): Promise<void>;
  onDidChangeSessions: vscode.Event<void>;
}

export const SHEEPFOLD_ID = '220labs.sheepfold';
const API_VERSION = 1;
/** What a SheepfoldApi 1 must carry, each a function (an event is one too). */
const SHEEPFOLD_MEMBERS = ['sessionLabel', 'sessionIcon', 'openSession', 'openPage', 'onDidChangeSessions'];
/** package.json's walkthrough, as `<publisher>.<name>#<id>`. */
const WALKTHROUGH = '220labs.regatta#regatta.getStarted';

let log: vscode.LogOutputChannel | undefined;

export function activate(context: vscode.ExtensionContext): RegattaApi {
  log = vscode.window.createOutputChannel('Regatta', { log: true });
  context.subscriptions.push(log);

  let notes: ReadonlyMap<string, HelmNote> = new Map();
  const notesChanged = new vscode.EventEmitter<void>();
  context.subscriptions.push(notesChanged);

  // Sheepfold, once found; its session event re-lays the board (a row takes the session's label).
  let peer: SheepfoldApi | null = null;
  let peerListener: vscode.Disposable | undefined;
  let handle: RegattaHandle | undefined;
  context.subscriptions.push({ dispose: () => peerListener?.dispose() });

  // One log line per distinct failure: a relayout asks a label for every row.
  const said = new Set<string>();
  const guarded = <T>(what: string, f: () => T, fallback: T): T => {
    try {
      return f();
    } catch (e) {
      const line = `sheepfold ${what}: ${e instanceof Error ? e.message : String(e)}`;
      if (!said.has(line)) {
        said.add(line);
        log?.warn(line);
      }
      return fallback;
    }
  };
  // A peer's own throw (a label read while it deactivates) is logged, never let out of an event.
  const relayout = () => {
    try {
      handle?.sessionsChanged();
    } catch (e) {
      log?.warn(`board relayout: ${e instanceof Error ? e.message : String(e)}`);
    }
  };
  const setPeer = (next: SheepfoldApi | null) => {
    if (next === peer) return;
    peerListener?.dispose();
    peerListener = next ? guarded('onDidChangeSessions', () => next.onDidChangeSessions(relayout), undefined) : undefined;
    peer = next;
    log?.info(next ? 'sheepfold: found, apiVersion 1' : 'sheepfold: none');
    relayout();
  };

  // Never awaited inside activate(): Sheepfold looks for this extension the same way, and two
  // activations each awaiting the other's would wait for ever. A generation keeps a slow lookup
  // started before a later one from overwriting its answer.
  let lookups = 0;
  const lookForSheepfold = async () => {
    const mine = ++lookups;
    const ext = vscode.extensions.getExtension(SHEEPFOLD_ID);
    let found: SheepfoldApi | null = null;
    if (ext) {
      try {
        found = apiOf<SheepfoldApi>(ext.isActive ? ext.exports : await ext.activate(), API_VERSION);
        if (!found) log?.info('sheepfold: installed, but not apiVersion 1; used as absent');
        else if (!hasMembers(found, SHEEPFOLD_MEMBERS)) {
          log?.warn('sheepfold: says apiVersion 1 but lacks part of it; used as absent');
          found = null;
        }
      } catch (e) {
        log?.warn(`sheepfold: did not activate: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
    if (mine === lookups) setPeer(found);
  };

  handle = activateRegatta(context, {
    log: () => log,
    // A spacesheep page in Sheepfold's mirror tab when Sheepfold is there; the browser otherwise.
    openPage: async (url) => {
      try {
        if (peer) return await peer.openPage(url);
      } catch (e) {
        log?.warn(`sheepfold openPage: ${e instanceof Error ? e.message : String(e)}; the browser instead`);
      }
      await vscode.env.openExternal(vscode.Uri.parse(url));
    },
    // A peer that throws is a session it cannot open: the card's own page is the fallback.
    openSession: async (id) => {
      try {
        return peer ? await peer.openSession(id) : false;
      } catch (e) {
        log?.warn(`sheepfold openSession: ${e instanceof Error ? e.message : String(e)}`);
        return false;
      }
    },
    hasSessions: () => peer !== null,
    // A peer's throw (a read while it deactivates) is a missing label or mark, never a broken view.
    sessionLabel: (id) => guarded('sessionLabel', () => peer?.sessionLabel(id) ?? null, null),
    sessionIcon: (id) => guarded('sessionIcon', () => peer?.sessionIcon(id), undefined),
    setHelmNotes: (next) => {
      if (sameNotes(next, notes)) return;
      notes = next;
      notesChanged.fire();
    },
  });

  context.subscriptions.push(
    vscode.extensions.onDidChange(() => void lookForSheepfold()),
    // VS Code joins the two itself: the step it selects is `<category>#<step>`.
    vscode.commands.registerCommand('regatta.add', () =>
      vscode.commands.executeCommand('workbench.action.openWalkthrough', { category: WALKTHROUGH, step: 'regatta' }),
    ),
  );
  void lookForSheepfold();

  return {
    apiVersion: 1,
    helmNotes: () => notes,
    onDidChangeHelmNotes: notesChanged.event,
  };
}

export function deactivate(): void {}
