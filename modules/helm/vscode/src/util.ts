// Small helpers the views share, copied from Sheepfold's model.ts when the regatta and Meetings views
// moved here (2026-11-02), and the peer check both extensions make. Pure: never imports `vscode`, so
// `node --test` covers it.

/** The fold's row: "N more in the fold…", or "show fewer" once unfolded. */
export type MoreRow = { kind: 'more'; count: number } | { kind: 'fewer' };

/** Text of a "more" row. */
export function moreLabel(m: MoreRow): string {
  return m.kind === 'more' ? `${m.count} more in the fold…` : 'show fewer';
}

/** `now`, `3m`, `2h`, `yesterday`, `5d`. */
export function relativeTime(lastAt: number, now: number): string {
  const ms = Math.max(0, now - lastAt);
  const min = Math.floor(ms / 60_000);
  if (min < 1) return 'now';
  if (min < 60) return `${min}m`;
  const hours = Math.floor(min / 60);
  if (hours < 24) return `${hours}h`;
  const days = Math.floor(hours / 24);
  return days < 2 ? 'yesterday' : `${days}d`;
}

/** A leading `~` or `~/` as the home folder; any other path as it is. */
export function expandHome(path: string, home: string): string {
  if (path === '~') return home;
  if (path.startsWith('~/') || path.startsWith('~\\')) return home.replace(/[\\/]+$/, '') + path.slice(1);
  return path;
}

/** First non-empty line of a CLI's stderr, for a message. */
export function firstLine(text: string): string {
  for (const line of text.split(/\r?\n/)) {
    const t = line.trim();
    if (t) return t;
  }
  return '';
}

/**
 * A peer extension's exports when they speak the API version this one was written against, else
 * null. Regatta and Sheepfold read each other's exports this way: an older or newer peer is treated
 * as absent, never half-used.
 */
export function apiOf<T>(exports: unknown, version: number): T | null {
  if (!exports || typeof exports !== 'object') return null;
  return (exports as { apiVersion?: unknown }).apiVersion === version ? (exports as T) : null;
}

/** Every named member of a peer's exports is a function: an API that says its version but lacks part of it is not used. */
export function hasMembers(api: object, members: readonly string[]): boolean {
  return members.every((m) => typeof (api as Record<string, unknown>)[m] === 'function');
}

/** Two sets of helm's notes say the same: the same sessions, each with the same line and word. */
export function sameNotes<N extends { kind: string; word: string; line: string }>(a: ReadonlyMap<string, N>, b: ReadonlyMap<string, N>): boolean {
  if (a.size !== b.size) return false;
  for (const [id, n] of a) {
    const m = b.get(id);
    if (!m || m.kind !== n.kind || m.word !== n.word || m.line !== n.line) return false;
  }
  return true;
}
