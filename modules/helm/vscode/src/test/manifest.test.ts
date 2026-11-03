// The manifest against the sources: every module packaged, every id renamed, every command
// registered and contributed. Reads files only; no VS Code needed.
import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';

const ROOT = path.join(__dirname, '..', '..');
const read = (p: string) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const pkg = JSON.parse(read('package.json'));
const sources = fs.readdirSync(path.join(ROOT, 'src')).filter((f) => f.endsWith('.ts'));
const code = sources.map((f) => read(`src/${f}`)).join('\n');

test('every src module is packaged: .vscodeignore lists its out/*.js', () => {
  // Without the line the package builds green and the installed extension fails on activation
  // with "Cannot find module" (Sheepfold's AGENTS.md).
  const lines = new Set(read('.vscodeignore').split(/\r?\n/).map((l) => l.trim()));
  for (const f of sources) assert.ok(lines.has(`!out/${f.replace(/\.ts$/, '.js')}`), `${f} has no line in .vscodeignore`);
});

test('the contract: id, version, kind, container', () => {
  assert.equal(`${pkg.publisher}.${pkg.name}`, '220labs.regatta');
  assert.equal(pkg.displayName, 'regatta');
  assert.equal(pkg.version, '0.1.0');
  assert.deepEqual(pkg.extensionKind, ['workspace']);
  assert.deepEqual(
    pkg.contributes.viewsContainers.activitybar.map((c: { id: string }) => c.id),
    ['regatta'],
  );
  assert.deepEqual(
    pkg.contributes.views.regatta.map((v: { id: string }) => v.id),
    ['regatta.board', 'regatta.meetings'],
  );
  assert.equal(pkg.extensionDependencies, undefined, 'Sheepfold is found at run time, never a dependency');
  assert.deepEqual(pkg.dependencies, undefined, 'no runtime dependencies');
});

test('nothing in the manifest still says sheepfold', () => {
  const text = read('package.json').replace(/github\.com\/220labs\/sheepfold/g, '');
  assert.equal(/sheepfold\./i.test(text), false, 'a sheepfold.* id, setting or context key');
});

test('every setting is regatta.*, and the old switch is gone', () => {
  const keys = Object.keys(pkg.contributes.configuration.properties);
  assert.deepEqual(keys.sort(), ['regatta.boardFile', 'regatta.cli', 'regatta.nudges', 'regatta.perSection']);
});

test('every command is contributed and registered, under regatta.*', () => {
  const contributed = new Set<string>(pkg.contributes.commands.map((c: { command: string }) => c.command));
  const registered = new Set([...code.matchAll(/registerCommand\('([^']+)'/g)].map((m) => m[1]));
  for (const c of contributed) assert.match(c, /^regatta\./);
  assert.deepEqual([...registered].sort(), [...contributed].sort());
  // A command a tree item or a welcome runs is one of them.
  for (const m of code.matchAll(/command: '([^']+)'/g)) assert.ok(contributed.has(m[1]), `${m[1]} is not contributed`);
  for (const m of JSON.stringify(pkg.contributes.viewsWelcome).matchAll(/command:(regatta\.[\w.]+)/g)) {
    assert.ok(contributed.has(m[1]), `${m[1]} in a welcome is not contributed`);
  }
});

test('every context key the code sets is regatta.*, and every one the manifest reads is set', () => {
  const set = new Set([...code.matchAll(/ctx\('([^']+)'/g)].map((m) => m[1]));
  for (const k of set) assert.match(k, /^regatta\./);
  const manifest = JSON.stringify(pkg.contributes);
  const read_ = new Set([...manifest.matchAll(/\b(regatta\.(?:helm|navigator|found|status|boardStatus|meetingsStatus))\b/g)].map((m) => m[1]));
  for (const k of read_) assert.ok(set.has(k), `${k} is read in package.json but never set`);
});

test('the walkthrough the Add command opens exists', () => {
  const m = /WALKTHROUGH = '([^']+)'/.exec(code);
  assert.ok(m);
  const [ext, id] = m![1].split('#');
  assert.equal(ext, `${pkg.publisher}.${pkg.name}`);
  assert.ok(pkg.contributes.walkthroughs.some((w: { id: string }) => w.id === id));
});
