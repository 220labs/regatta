#!/usr/bin/env bash
# check --ci: strict peer stubs, disposable git repos and HOME; no network or real push.
# Optional case names: bash tests/test_check_ci.sh CheckCI.test_green
set -eu
export CHECK_CI_BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
python3 - "$@" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

B = Path(os.environ['CHECK_CI_BIN'])

STUB = r'''
import json, os, subprocess, sys
from pathlib import Path
a = sys.argv[1:]
state = Path(os.environ['CI_STATE'])
d = json.loads(state.read_text())
kind = Path(sys.argv[0]).name
if kind == 'ps':
    # The local fallback needs its own start time. This suite tests no live slot holders;
    # a sandbox may refuse real ps, which test_check.sh covers with its process cases.
    if a[:2] != ['-o', 'lstart='] or a[2:3] != ['-p'] or len(a) != 4: sys.exit(2)
    print('Mon Jan 1 00:00:00 2024'); sys.exit(0)
with open(os.environ['CI_CALLS'], 'a') as f:
    f.write(json.dumps([kind] + a) + '\n')
def save(): state.write_text(json.dumps(d))
def emit(v): print(json.dumps(v))
def invalid():
    with open(os.environ['CI_INVALID'], 'a') as f: f.write(repr([kind] + a) + '\n')
    sys.exit(2)
if kind == 'git':
    if a and a[0] == 'fetch':
        if a != ['fetch', '--no-tags', 'origin', '+refs/heads/main:refs/remotes/origin/main']: invalid()
        sys.exit(1 if d.get('offline') else 0)
    if a and a[0] == 'push':
        if a != ['push', 'origin', 'HEAD:refs/heads/claude/test/check-ci']: invalid()
        if d.get('push_refused'):
            print('remote with ' + os.environ.get('GH_TOKEN', ''), file=sys.stderr)
            sys.exit(1)
        d['pushed'] = True; save(); sys.exit(0)
    os.execv(os.environ['CI_REAL_GIT'], [os.environ['CI_REAL_GIT']] + a)
if kind != 'gh': invalid()
if len(a) < 2 or a[-2:] != ['--repo', 'example/checks']: invalid()
a = a[:-2]
branch = 'claude/test/check-ci'
head = subprocess.check_output([os.environ['CI_REAL_GIT'], 'rev-parse', 'HEAD'], text=True).strip()
fields = 'number,isDraft,headRefOid,body,baseRefName,isCrossRepository,labels'
if a == ['pr', 'list', '--head', branch, '--state', 'open', '--json', fields]:
    if d.get('offline'): sys.exit(1)
    body = d.get('body', 'curated by `/finish`' if d.get('ready') else '<!-- wharf-runs check --ci -->')
    emit([dict(number=17, isDraft=d.get('draft', False), headRefOid=head, body=body,
               baseRefName='main', isCrossRepository=False, labels=d.get('labels', []))] if d.get('pr') else [])
elif a == ['pr', 'list', '--head', branch, '--state', 'merged', '--base', 'main', '--json', 'number']:
    emit([dict(number=5)] if d.get('landed') else [])
elif a == ['label', 'create', 'hold', '--color', 'B60205', '--description', 'automerge stays off while set']:
    sys.exit(1)  # an existing label, as the real gh returns
elif a[:5] == ['pr', 'edit', '17', '--add-label', 'hold']:
    if len(a) != 5:
        if len(a) != 7 or a[5] != '--body-file' or not Path(a[6]).is_file(): invalid()
        if d.get('body_refused'): sys.exit(1)
    if d.get('label_refused'): sys.exit(1)
    if len(a) == 7: d['body'] = Path(a[6]).read_text().strip()
    d.update(held=True, labels=[dict(name='hold')]); save()
elif a == ['pr', 'ready', '17']:
    if not d.get('held') or '<!-- wharf-runs check --ci -->' not in d.get('body', ''): invalid()
    d['draft'] = False; save()
elif a[:2] == ['pr', 'create']:
    expected = ['pr', 'create', '--draft', '--head', branch, '--base', 'main', '--label', 'hold',
                '--title', 'WIP: check ci', '--body-file']
    if a[:-1] != expected or not Path(a[-1]).is_file(): invalid()
    body = Path(a[-1]).read_text()
    if '<!-- wharf-runs check --ci -->' not in body: invalid()
    if d.get('no_pr'): sys.exit(1)
    if not d.get('pushed'): invalid()
    if d.get('create_label_refused'):
        # gh made the PR, then its label call failed: a draft, unlabelled, and gh exits 1
        d.update(pr=True, draft=True, held=False, body=body, labels=[]); save(); sys.exit(1)
    d.update(pr=True, draft=True, held=True, body=body, labels=[dict(name='hold')]); save()
elif a == ['pr', 'view', '17', '--json', 'headRefOid,state']:
    d['views'] = d.get('views', 0) + 1; save()
    moved = d.get('moved') or (d.get('moved_after') and d['views'] >= 2)
    emit(dict(headRefOid='other-head' if moved else head, state='OPEN'))
elif a == ['pr', 'checks', '17', '--json', 'name,bucket,link']:
    d['polls'] = d.get('polls', 0) + 1; save()
    if d.get('slow'):
        import time; time.sleep(60)
    names = json.loads(Path('.github/main-protection.json').read_text())['required_status_checks']['checks']
    rows = [dict(name=n['context'], bucket='pass', link='') for n in names]
    if d.get('no_checks_first') and d['polls'] == 1:
        # gh's answer for a head with no context yet (cli/cli pkg/cmd/pr/checks/checks.go): no stdout
        print("no checks reported on the '%s' branch" % branch, file=sys.stderr); sys.exit(1)
    if d.get('pending_once') and d['polls'] == 1:
        # under --json gh exits 0 with pending rows (its exporter returns before the pending error)
        rows[0]['bucket'] = 'pending'; emit(rows); sys.exit(0)
    if d.get('red'):
        rows[0].update(bucket='fail', link='https://github.com/example/checks/actions/runs/10/job/20')
        rows.append(dict(name='suite (broken)', bucket='fail', link='https://github.com/example/checks/actions/runs/10/job/21'))
        if d.get('other_pending'): rows[1]['bucket'] = 'pending'
        if d.get('other_missing'): rows.pop(1)
        emit(rows); sys.exit(1)
    if d.get('missing'): rows.pop()
    if d.get('skipped'): rows[0]['bucket'] = 'skipping'
    emit(rows)
elif a in (['run', 'view', '10', '--log-failed', '--job', '20'],
           ['run', 'view', '10', '--log-failed', '--job', '21']):
    print('job\tstep\tFAIL expected [yes] got [no] ' + os.environ.get('GH_TOKEN', ''))
else: invalid()
'''


class CheckCI(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='check-ci-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.wt = self.root / 'repo'
        self.wt.mkdir()
        home = self.root / 'home'
        home.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.state = self.root / 'state.json'
        self.calls = self.root / 'calls.jsonl'
        self.invalid = self.root / 'invalid'
        self.out = self.root / 'out'
        self.registry = self.root / 'repos.json'
        self.registry.write_text('{}')
        self.env = dict(os.environ, HOME=str(home), REGATTA_CONFIG=str(self.root / 'config'),
                        CLAUDE_REPOS_JSON=str(self.registry), GIT_CONFIG_GLOBAL=str(self.root / 'gitconfig'),
                        GIT_CONFIG_SYSTEM=os.devnull, PYTHONDONTWRITEBYTECODE='1', TMPDIR=str(self.root),
                        CHECK_LOGS=str(self.root / 'logs'), CHECK_SLOT_DIR=str(self.root / 'slots'),
                        CHECK_SLOTS='1', CHECK_PASS_TTL='0', CI_STATE=str(self.state), CI_CALLS=str(self.calls),
                        CI_INVALID=str(self.invalid), CI_REAL_GIT=shutil.which('git'),
                        LOCAL_MARK=str(self.root / 'local'), GH_TOKEN='fakekey')
        for k in list(self.env):
            if k.startswith(('CLAUDE_', 'DISPATCH_', 'REGATTA_UNATTENDED', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_',
                             'GIT_CONFIG_VALUE_', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE')):
                self.env.pop(k, None)
        self.env['CLAUDE_REPOS_JSON'] = str(self.registry)
        self.env['GIT_AUTHOR_NAME'] = self.env['GIT_COMMITTER_NAME'] = 'Test'
        self.env['GIT_AUTHOR_EMAIL'] = self.env['GIT_COMMITTER_EMAIL'] = 'test@example.invalid'
        self.g('init', '-q', '-b', 'main')
        self.g('config', 'core.hooksPath', '/dev/null')
        (self.wt / '.github').mkdir()
        self.protection = self.wt / '.github/main-protection.json'
        self.protection.write_text(json.dumps({'required_status_checks': {'checks': [
            {'context': 'mac-tests'}, {'context': 'linux-tests'}]}}))
        (self.wt / 'AGENTS.md').write_text('- check: `bash local.sh`\n')
        # the CI's own line, as regatta's .github/ci/share.sh prints it
        (self.wt / '.github/ci').mkdir()
        (self.wt / '.github/ci/share.sh').write_text('[ "$1" = line ] && echo "{ [ ! -f x ] || bash local.sh; }"\n')
        (self.wt / 'local.sh').write_text('echo ran >> "$LOCAL_MARK"\n')
        (self.wt / 'shared').write_text('base\n')
        self.g('add', '.'); self.g('commit', '-qm', 'base')
        self.g('update-ref', 'refs/remotes/origin/main', 'HEAD')
        self.g('remote', 'add', 'origin', 'https://github.com/example/checks.git')
        self.g('checkout', '-qb', 'claude/test/check-ci')
        (self.wt / 'branch').write_text('branch\n')
        self.g('add', '.'); self.g('commit', '-qm', 'branch change')
        self.set_state(pr=True)
        for name in ('git', 'gh', 'ps'):
            p = self.bin / name
            p.write_text('#!' + sys.executable + '\n' + STUB)
            p.chmod(0o755)
        self.env['PATH'] = str(self.bin) + os.pathsep + self.env['PATH']

    def tearDown(self):
        self.assertFalse(self.invalid.exists(), self.invalid.read_text() if self.invalid.exists() else '')

    def g(self, *args):
        return subprocess.check_output([self.env['CI_REAL_GIT'], *args], cwd=self.wt,
                                       env=self.env, text=True, stderr=subprocess.STDOUT).strip()

    def set_state(self, **kw):
        self.state.write_text(json.dumps(kw))

    def events(self):
        return [json.loads(s) for s in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def run_check(self, *args):
        # Several Python/git startups per call: allow loaded runners room, while bounding a hang.
        p = subprocess.run(['bash', str(B / 'check'), str(self.wt), '--ci', '--out', str(self.out), *args],
                           env=self.env, text=True, capture_output=True, timeout=120)
        self.assertNotIn('fakekey', p.stdout + p.stderr)
        return p

    def local(self, *args):
        p = self.run_check(*args)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(p.stdout.count('falling back to local check'), 1, p.stdout)
        self.assertTrue((self.root / 'local').exists(), p.stdout)
        self.assertTrue((self.out / 'summary').read_text().endswith('DONE 1/1\n'))
        return p

    def advance_main(self, conflict=False):
        if conflict:
            (self.wt / 'shared').write_text('branch edit\n')
            self.g('add', '.'); self.g('commit', '-qm', 'branch change')
        self.g('checkout', '-q', 'main')
        (self.wt / ('shared' if conflict else 'main-file')).write_text('main edit\n')
        self.g('add', '.'); self.g('commit', '-qm', 'main change')
        self.g('update-ref', 'refs/remotes/origin/main', 'HEAD')
        self.g('checkout', '-q', 'claude/test/check-ci')

    def test_green(self):
        p = self.run_check()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIn('DONE 2/2', p.stdout)
        self.assertFalse((self.root / 'slots').exists())
        self.assertFalse((self.root / 'logs/passed').exists())
        self.assertFalse((self.root / 'local').exists())
        self.assertIn(['git', 'push', 'origin', 'HEAD:refs/heads/claude/test/check-ci'], self.events())

    def test_new_pr(self):
        self.set_state(pr=False)
        p = self.run_check()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        ev = self.events()
        created = next(i for i, e in enumerate(ev) if e[:3] == ['gh', 'pr', 'create'])
        ready = next(i for i, e in enumerate(ev) if e[:3] == ['gh', 'pr', 'ready'])
        self.assertLess(created, ready)
        self.assertTrue(json.loads(self.state.read_text())['held'])

    def test_ci_hold_ownership(self):
        for new in (False, True):
            with self.subTest(new=new):
                self.set_state(pr=not new)
                p = self.run_check()
                self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
                state = json.loads(self.state.read_text())
                self.assertTrue(state['held'])
                self.assertIn('Build CI labelled this pull request `hold`', state['body'])
                p = self.run_check()
                self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
                self.assertEqual(json.loads(self.state.read_text())['body'], state['body'])

    def test_manual_hold_not_claimed(self):
        for draft in (False, True):
            with self.subTest(draft=draft):
                self.set_state(pr=True, draft=draft, labels=[dict(name='hold')], body='Owner hold.')
                p = self.run_check()
                self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
                body = json.loads(self.state.read_text())['body']
                self.assertTrue(body.startswith('Owner hold.'))
                self.assertNotIn('Build CI labelled', body)
                self.assertEqual('<!-- wharf-runs check --ci -->' in body, draft)

    def test_red_with_failing_lines(self):
        self.set_state(pr=True, red=True)
        p = self.run_check()
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        summary = (self.out / 'summary').read_text()
        self.assertIn('CI suite (broken) — job\tstep\tFAIL expected [yes] got [no] ***', summary)
        self.assertTrue(summary.splitlines()[-1].startswith('FAILED'))
        self.assertIn('FAIL expected', (self.out / 'ci-02.log').read_text())
        self.assertFalse((self.root / 'local').exists())

    def test_merge_main(self):
        self.advance_main()
        p = self.run_check()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(self.g('merge-base', 'HEAD', 'origin/main'), self.g('rev-parse', 'origin/main'))

    def test_merge_conflict_aborted(self):
        self.advance_main(conflict=True)
        before = self.g('rev-parse', 'HEAD')
        p = self.run_check()
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        self.assertIn('FAILED merge of origin/main conflicted: shared', p.stdout)
        self.assertEqual(self.g('rev-parse', 'HEAD'), before)
        self.assertEqual(self.g('status', '--porcelain'), '')
        self.assertFalse(any(e[:2] == ['git', 'push'] for e in self.events()))

    def test_draft_held_before_readied_and_pushed(self):
        self.set_state(pr=True, draft=True)
        p = self.run_check()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        ev = self.events()
        held = next(i for i, e in enumerate(ev) if e[:3] == ['gh', 'pr', 'edit'])
        pushed = next(i for i, e in enumerate(ev) if e[:2] == ['git', 'push'])
        ready = next(i for i, e in enumerate(ev) if e[:3] == ['gh', 'pr', 'ready'])
        self.assertLess(held, pushed)
        self.assertLess(held, ready)

    def test_checkpoint_draft_marked_before_ready_and_checked_again(self):
        self.set_state(pr=True, draft=True, body='Checkpoint draft.')
        p = self.run_check()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        body = json.loads(self.state.read_text())['body']
        self.assertTrue(body.startswith('Checkpoint draft.'))
        self.assertIn('<!-- wharf-runs check --ci -->', body)
        ev = self.events()
        marked = next(i for i, e in enumerate(ev) if e[:3] == ['gh', 'pr', 'edit'] and '--body-file' in e)
        ready = next(i for i, e in enumerate(ev) if e[:3] == ['gh', 'pr', 'ready'])
        self.assertLess(marked, ready)
        self.advance_main()
        p = self.run_check()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(self.g('merge-base', 'HEAD', 'origin/main'), self.g('rev-parse', 'origin/main'))
        self.assertEqual(sum(e[:3] == ['gh', 'pr', 'ready'] for e in self.events()), 1)

    def test_unwritten_draft_marker_cannot_ready(self):
        self.set_state(pr=True, draft=True, body='Checkpoint draft.', body_refused=True,
                       labels=[dict(name='hold')])
        self.local()
        self.assertFalse(any(e[:3] == ['gh', 'pr', 'ready'] or e[:2] == ['git', 'push'] for e in self.events()))

    def test_readied_pr_needs_explicit_merge(self):
        # no fix clears a moved main under a /finish-readied PR: no red, the local line answers
        self.advance_main()
        self.set_state(pr=True, ready=True)
        p = self.local()
        self.assertIn('PR readied by /finish and main moved', p.stdout)
        self.assertNotIn('--ci-merge-main', p.stdout)
        self.assertFalse(any(e[:2] in (['git', 'push'], ['git', 'merge']) for e in self.events()))
        (self.root / 'local').unlink()
        for marker in ('CLAUDE_UNATTENDED', 'REGATTA_UNATTENDED'):
            with self.subTest(marker=marker):
                env = self.env
                self.env = dict(env, **{marker: '1'})
                p = self.run_check('--ci-merge-main')
                self.env = env
                self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
                self.assertIn("never an unattended run's", p.stderr)
        p = self.run_check('--ci-merge-main')
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)

    def test_unrun_contract_commands(self):
        # what the contract runs and CI's line never does (the publish gate) is said after a green, exit 3
        (self.wt / 'AGENTS.md').write_text('- check: `bash local.sh && bash gate.sh --ref HEAD`\n')
        self.g('add', '.'); self.g('commit', '-qm', 'gate')
        p = self.run_check()
        self.assertEqual(p.returncode, 3, p.stdout + p.stderr)
        lines = (self.out / 'summary').read_text().splitlines()
        self.assertEqual(lines[-2:], ['UNRUN bash gate.sh --ref HEAD', 'DONE 2/2'])
        self.assertNotIn('UNRUN bash local.sh', lines)

    def test_no_ci_line_uses_local(self):
        (self.wt / '.github/ci/share.sh').unlink()
        self.g('add', '-A'); self.g('commit', '-qm', 'no share')
        p = self.local()
        self.assertIn('no .github/ci/share.sh line', p.stdout)
        self.assertFalse(any(e[0] == 'gh' for e in self.events()))

    def test_no_checks_yet_waits(self):
        self.set_state(pr=True, no_checks_first=True)
        import importlib.util
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location('check_ci', B / 'check_ci.py')
        m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
        self.out.mkdir()
        with patch.dict(os.environ, self.env, clear=True):
            ci = m.CI(self.wt, self.out, 1, False)
            ci.slug = 'example/checks'
            tick = [0]
            real_sleep = time.sleep
            def sleep(seconds):
                if seconds >= 1: tick[0] += seconds
                else: real_sleep(seconds)
            with patch.object(m.time, 'monotonic', lambda: tick[0]), patch.object(m.time, 'sleep', sleep):
                self.assertEqual(ci.wait(17, self.g('rev-parse', 'HEAD'), ['mac-tests', 'linux-tests']), 0)
        self.assertEqual(json.loads(self.state.read_text())['polls'], 2)

    def test_new_pr_label_refused_stays_draft(self):
        # gh's label call failing after the PR exists leaves a draft, which automerge never arms
        self.set_state(pr=False, create_label_refused=True)
        self.local()
        self.assertTrue(json.loads(self.state.read_text())['draft'])
        self.assertFalse(any(e[:3] == ['gh', 'pr', 'ready'] for e in self.events()))

    def test_landed_branch_never_pushed(self):
        self.set_state(pr=False, landed=True)
        p = self.local()
        self.assertIn('branch already landed', p.stdout)
        self.assertFalse(any(e[:2] == ['git', 'push'] or e[:3] == ['gh', 'pr', 'create'] for e in self.events()))

    def test_required_contexts_from_origin_main(self):
        # a branch that narrows its own protection file does not narrow what its green means
        import importlib.util
        spec = importlib.util.spec_from_file_location('check_ci', B / 'check_ci.py')
        m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
        self.protection.write_text(json.dumps({'required_status_checks': {'checks': [{'context': 'mac-tests'}]}}))
        self.g('add', '.'); self.g('commit', '-qm', 'narrow')
        self.out.mkdir()
        ci = m.CI(self.wt, self.out, 1, False)
        self.assertEqual(ci.required(), ['mac-tests', 'linux-tests'])

    def test_signal_ends_helper(self):
        import signal, time
        self.set_state(pr=True, slow=True)
        p = subprocess.Popen(['bash', str(B / 'check'), str(self.wt), '--ci', '--out', str(self.out)],
                             env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for _ in range(600):
            if any(e[:3] == ['gh', 'pr', 'checks'] for e in self.events()): break
            time.sleep(0.1)
        p.send_signal(signal.SIGTERM)
        out, err = p.communicate(timeout=60)
        self.assertEqual(p.returncode, 143, out + err)
        self.assertTrue((self.out / 'summary').read_text().endswith('INTERRUPTED 0/0 by SIGTERM\n'))
        time.sleep(1)
        ps = subprocess.run(['pgrep', '-f', 'check_ci.py ' + str(self.wt)], capture_output=True, text=True)
        self.assertEqual(ps.stdout.strip(), '', 'the helper outlived its check')

    def test_guarded_repo_uses_local(self):
        self.registry.write_text(json.dumps({'guarded': [self.wt.name]}))
        p = self.local()
        self.assertIn('confidential scope', p.stdout)
        self.assertFalse(any(e[0] == 'gh' for e in self.events()))

    def test_moved_head(self):
        for key in ('moved', 'moved_after'):
            with self.subTest(key=key):
                self.set_state(pr=True, **{key: True})
                p = self.run_check()
                self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
                self.assertIn('FAILED CI head moved', p.stdout)
                self.assertNotIn('DONE', p.stdout)
                self.assertFalse((self.root / 'local').exists())

    def test_timeout_falls_back(self):
        self.local('--ci-wait', '0')

    def test_no_gh_falls_back(self):
        # A PATH of the local road's actual tools only, so even a runner with /usr/bin/gh
        # cannot accidentally answer the no-gh case. No mock gh or git reaches the network.
        tools = self.root / 'local-bin'
        tools.mkdir()
        for name in ('bash', 'dirname', 'basename', 'mkdir', 'pwd', 'date', 'sed', 'head', 'tr', 'grep', 'echo',
                     'find', 'xargs', 'seq', 'cat', 'ls', 'sort', 'perl', 'awk', 'rm', 'rmdir',
                     'cut', 'sleep', 'python3', 'cp', 'mv'):
            (tools / name).symlink_to(shutil.which(name))
        (tools / 'git').symlink_to(self.bin / 'git')
        (tools / 'ps').symlink_to(self.bin / 'ps')
        self.env['PATH'] = str(tools)
        p = self.local()
        self.assertIn('(no gh)', p.stdout)
        self.assertFalse(any(e[0] == 'gh' for e in self.events()))

    def test_unavailable_falls_back(self):
        for reason in ('offline', 'push_refused', 'no_pr', 'label_refused'):
            with self.subTest(reason=reason):
                self.set_state(pr=(reason != 'no_pr'), **{reason: True})
                self.local()

    def test_confidential_all_scopes_and_absolute_path(self):
        for entry in (str(self.wt), str(self.wt.parent / '*')):
            with self.subTest(entry=entry):
                self.registry.write_text(json.dumps({'scopes': {
                    'umbrella': {'repos': ['*']}, 'closed': {'repos': [entry], 'confidential': True}}}))
                p = self.local()
                self.assertIn('confidential scope', p.stdout)
                self.assertFalse(any(e[0] == 'gh' or e[:2] == ['git', 'fetch'] for e in self.events()))

    def test_confidential_external_worktree(self):
        primary = self.wt
        self.wt = self.root / 'external-worktree'
        self.g_at(primary, 'worktree', 'add', '-q', str(self.wt), '-b', 'claude/test/external', 'HEAD')
        self.registry.write_text(json.dumps({'scopes': {'closed': {'repos': [str(primary)], 'confidential': True}}}))
        self.local()
        self.assertFalse(any(e[0] == 'gh' for e in self.events()))

    def g_at(self, cwd, *args):
        return subprocess.check_output([self.env['CI_REAL_GIT'], *args], cwd=cwd, env=self.env, stderr=subprocess.STDOUT)

    def test_torn_registry_falls_back(self):
        for text in ('{', '{"scopes":{"closed":{"repos":"*","confidential":true}}}'):
            self.registry.write_text(text)
            self.local()
        self.registry.unlink()
        self.registry.symlink_to(self.root / 'missing-registry')
        self.local()
        self.assertFalse(any(e[0] == 'gh' for e in self.events()))

    def test_dirty_tree_uses_local(self):
        (self.wt / 'shared').write_text('uncommitted\n')
        self.local()
        self.assertFalse(any(e[0] == 'gh' for e in self.events()))

    def test_ci_wait_usage(self):
        p = self.run_check('--ci-wait', '-1')
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)

    def test_skipped_required_is_red(self):
        self.set_state(pr=True, skipped=True)
        p = self.run_check()
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)

    def test_pending_and_missing_contexts_wait(self):
        # Drive the poller's clock in process: pending exit 8 must be accepted and an absent
        # required context cannot turn green. No real 15-second sleeps or two-hour timeout.
        import importlib.util
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location('check_ci', B / 'check_ci.py')
        m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
        self.out.mkdir()
        for missing in (False, True):
            self.set_state(pr=True, pending_once=not missing, missing=missing)
            with patch.dict(os.environ, self.env, clear=True):
                ci = m.CI(self.wt, self.out, 1, False)
                ci.slug = 'example/checks'
                tick = [0]
                real_sleep = time.sleep
                # the patch reaches the shared time module, so subprocess's own wait loop (sleeps
                # of 0.05 s or less) would move the fake clock too, more the more loaded the box
                def sleep(seconds):
                    if seconds >= 1: tick[0] += seconds
                    else: real_sleep(seconds)
                with patch.object(m.time, 'monotonic', lambda: tick[0]), patch.object(m.time, 'sleep', sleep):
                    if missing:
                        with self.assertRaises(m.Unavailable): ci.wait(17, self.g('rev-parse', 'HEAD'), ['mac-tests', 'linux-tests'])
                    else:
                        self.assertEqual(ci.wait(17, self.g('rev-parse', 'HEAD'), ['mac-tests', 'linux-tests']), 0)
                        self.assertEqual(json.loads(self.state.read_text())['polls'], 2)

    def test_required_failure_never_falls_back(self):
        import importlib.util
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location('check_ci', B / 'check_ci.py')
        m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
        self.out.mkdir()
        for other in ('other_pending', 'other_missing'):
            with self.subTest(other=other):
                self.set_state(pr=True, red=True, **{other: True})
                tick = [0]
                real_sleep = time.sleep
                # the patch reaches the shared time module, so subprocess's own wait loop (sleeps
                # of 0.05 s or less) would move the fake clock too, more the more loaded the box
                def sleep(seconds):
                    if seconds >= 1: tick[0] += seconds
                    else: real_sleep(seconds)
                argv = ['check_ci.py', str(self.wt), str(self.out), '1', '0']
                with patch.dict(os.environ, self.env, clear=True), patch.object(sys, 'argv', argv), \
                     patch.object(m.time, 'monotonic', lambda: tick[0]), patch.object(m.time, 'sleep', sleep):
                    self.assertEqual(m.main(), 1)
                summary = (self.out / 'summary').read_text()
                self.assertIn('FAIL expected [yes] got [no] ***', summary)
                self.assertTrue(summary.endswith('FAILED 0/2 CI checks passed\n'), summary)
                self.assertEqual(json.loads(self.state.read_text())['polls'], 1)
                self.assertFalse((self.root / 'local').exists())


suite = (unittest.defaultTestLoader.loadTestsFromNames(sys.argv[1:], module=sys.modules[__name__])
         if len(sys.argv) > 1 else unittest.defaultTestLoader.loadTestsFromTestCase(CheckCI))
result = unittest.TextTestRunner(verbosity=2).run(suite)
if result.wasSuccessful():
    print('check --ci: all %d cases passed' % result.testsRun)
sys.exit(not result.wasSuccessful())
PY
