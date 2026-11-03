import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import { apiOf, expandHome, firstLine, hasMembers, moreLabel, relativeTime, sameNotes } from '../util';

const NOW = 1_800_000_000_000;
const MIN = 60_000;
const HOUR = 60 * MIN;

test('relativeTime', () => {
  assert.equal(relativeTime(NOW - 10_000, NOW), 'now');
  assert.equal(relativeTime(NOW - 3 * MIN, NOW), '3m');
  assert.equal(relativeTime(NOW - 59 * MIN, NOW), '59m');
  assert.equal(relativeTime(NOW - 2 * HOUR, NOW), '2h');
  assert.equal(relativeTime(NOW - 23 * HOUR, NOW), '23h');
  assert.equal(relativeTime(NOW - 30 * HOUR, NOW), 'yesterday');
  assert.equal(relativeTime(NOW - 72 * HOUR, NOW), '3d');
  assert.equal(relativeTime(NOW + HOUR, NOW), 'now', 'a clock skew never goes negative');
});

test('expandHome', () => {
  assert.equal(expandHome('~/projects/app', '/u'), '/u/projects/app');
  assert.equal(expandHome('~/projects/app', '/u/'), '/u/projects/app', 'a trailing slash on home is dropped');
  assert.equal(expandHome('~', '/u/'), '/u/');
  assert.equal(expandHome('/abs/path', '/u'), '/abs/path');
  assert.equal(expandHome('~other/x', '/u'), '~other/x', "another user's home is not expanded");
});

test('firstLine skips blanks', () => {
  assert.equal(firstLine('\n  \nnot signed in\nmore'), 'not signed in');
  assert.equal(firstLine(''), '');
});

test('moreLabel', () => {
  assert.equal(moreLabel({ kind: 'more', count: 2 }), '2 more in the fold…');
  assert.equal(moreLabel({ kind: 'fewer' }), 'show fewer');
});

test('apiOf takes a peer only at the version it was written against', () => {
  const v1 = { apiVersion: 1, x: 1 };
  assert.equal(apiOf(v1, 1), v1);
  assert.equal(apiOf({ apiVersion: 2 }, 1), null, 'a newer peer is absent');
  assert.equal(apiOf({ apiVersion: '1' }, 1), null, 'a string is no version');
  assert.equal(apiOf({}, 1), null);
  assert.equal(apiOf(undefined, 1), null, 'an extension that exports nothing');
  assert.equal(apiOf(null, 1), null);
  assert.equal(apiOf(1, 1), null);
});

test('sameNotes compares by session, kind, word and line', () => {
  const n = (line: string, word = 'stalled') => ({ kind: 'stall', word, line });
  const a = new Map([['s1', n('a')]]);
  assert.ok(sameNotes(a, new Map([['s1', n('a')]])));
  assert.ok(!sameNotes(a, new Map([['s1', n('b')]])), 'a new line');
  assert.ok(!sameNotes(a, new Map([['s1', n('a', '')]])), 'a new word');
  assert.ok(!sameNotes(a, new Map([['s2', n('a')]])), 'another session');
  assert.ok(!sameNotes(a, new Map()), 'one gone');
  assert.ok(sameNotes(new Map(), new Map()));
});

test('hasMembers: a peer that says its version must carry every part of it', () => {
  const f = () => undefined;
  assert.ok(hasMembers({ a: f, b: f }, ['a', 'b']));
  assert.ok(!hasMembers({ a: f }, ['a', 'b']), 'one missing');
  assert.ok(!hasMembers({ a: f, b: 1 }, ['a', 'b']), 'not a function');
});
