"""run_vendor's offline integration cases. Called through test_vendor.sh only."""
import importlib.machinery
import fcntl
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

B, T = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
sys.path.insert(0, str(B))
sys.argv = [sys.argv[0]]
for k in list(os.environ):
    if k.startswith(("CLAUDE", "DISPATCH_")) or k == "REGATTA_UNATTENDED":
        os.environ.pop(k, None)
import vendorlib as v

STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys, time
a=sys.argv[1:]
if a == ['login','status']:
    gate=os.environ.get('PREFLIGHT_GATE')
    if gate:
        path=pathlib.Path(gate)
        n=int(path.read_text())+1 if path.exists() else 1
        path.write_text(str(n))
        if n==2:
            path.with_suffix('.ready').touch()
            deadline=time.monotonic()+60
            while not path.with_suffix('.release').exists():
                assert time.monotonic()<deadline, 'preflight was never released'
                time.sleep(.05)
    sys.exit(0)
if a == ['debug','models','--bundled']:
    print(json.dumps({'models':[{'slug':'gpt-6.1-sol','supported_reasoning_levels':[{'effort':'high'},{'effort':'xhigh'}]}]})); sys.exit(0)
assert a.pop(0)=='exec', a
flags={}; conf=[]; disabled=[]
while a and a[0].startswith('-') and a[0]!='-':
    x=a.pop(0)
    if x in ('--json','--approve-for-me','--dangerously-bypass-hook-trust'): flags[x]=True
    elif x in ('-c','-C','-m','--disable','--enable'):
        val=a.pop(0)
        if x=='-c': conf.append(val)
        elif x=='--disable': disabled.append(val)
        elif x=='--enable': assert val=='hooks'; flags[x]=val
        else: flags[x]=val
    else: raise AssertionError('unknown real CLI flag '+x)
assert flags.get('--json') and flags.get('--approve-for-me')
assert flags.get('-m')=='gpt-6.1-sol'
assert 'default_permissions="regatta-fence"' in conf
assert any(x.startswith('permissions.regatta-fence.filesystem=') for x in conf)
assert 'mcp_servers={}' in conf and 'apps' in disabled and 'plugins' in disabled
assert not os.environ.get('CLAUDE_CODE_SESSION_ID') and not os.environ.get('CLAUDECODE')
assert os.environ.get('REGATTA_WORKTREE')==flags['-C']
assert os.environ.get('PLAN_HARNESS')=='codex'
assert not any(k.startswith('DISPATCH_') and k not in ('DISPATCH_DEPTH','DISPATCH_MAX_DEPTH') for k in os.environ)
assert os.environ.get('DISPATCH_DEPTH','').isdigit() and int(os.environ['DISPATCH_DEPTH'])>=1
mode='build'
review_sub=bool(a) and a[0]=='review'   # the real CLI's review mode: it answers in its own shape (probed, 0.166.0)
if review_sub: a.pop(0)
elif a and a[0]=='resume': mode='resume'; a.pop(0); assert a.pop(0)=='builder-thread'
assert a==['-'], a
prompt=sys.stdin.read(); assert len(prompt.encode())<=65536
fs=[x for x in conf if x.startswith('permissions.regatta-fence.filesystem=')][0]
own=json.dumps(os.path.realpath(flags['-C']))
if 'perform that review' in prompt or 'fresh verifier' in prompt or 'You reformat a review' in prompt:
    mode='review'
    assert own+'="read"' in fs and own+'="write"' not in fs, fs
    assert 'permissions.regatta-fence.extends=":read-only"' in conf, conf
else:
    assert 'permissions.regatta-fence.extends=":workspace"' in conf, conf
wt=pathlib.Path(flags['-C']); f=wt/'f.py'
with open(os.environ['AUDIT'],'a') as out: out.write(json.dumps({'mode':mode,'prompt':prompt})+'\n')
if os.environ.get('WRITE_ENDING'):
    rec=pathlib.Path(os.environ['WRITE_ENDING']); d=json.loads(rec.read_text())
    d['ending']='requeued by the fixture'; rec.write_text(json.dumps(d))
    print(json.dumps({'type':'thread.started','thread_id':'builder-thread'}))
    print(json.dumps({'type':'turn.failed','error':{'message':'stopped'}}))
    sys.exit(1)
if os.environ.get('FAIL_EXIT_QUIET'):
    sys.stderr.write(os.environ.get('STDERR_TEXT','')+'\n'); sys.exit(1)
if os.environ.get('FAIL_BEFORE_COMMIT'):
    print(json.dumps({'type':'thread.started','thread_id':'builder-thread'}))
    print(json.dumps({'type':'turn.failed','error':{'message':'fixture failure before commit'}}))
    sys.exit(1)
if mode=='review':
    thread='review-'+str(len(open(os.environ['AUDIT']).readlines()))
    if 'You reformat a review' in prompt: text=os.environ.get('REFORMATTED','NO_FINDINGS')
    elif 'name: code-reviewer' in prompt:
        assert 'answer NO_FINDINGS' not in prompt, 'the code reviewer is asked for a JSON list only'
        text=os.environ.get('CODE_REVIEW_TEXT','[]')
    elif 'fresh verifier' in prompt: text='f.py:1 — [S2] bad result\nverdict: WRONG\nevidence: bad input produces bad output\nfix: write fixed'
    elif os.environ.get('CLEAN_REVIEWS'): text=os.environ.get('CLEAN_TEXT','NO_FINDINGS')
    elif f.read_text().strip()=='bad' or os.environ.get('ALWAYS_FIND'): text='f.py:1 — [S2] bad result\nverdict: WRONG\nevidence: bad input produces bad output\nfix: write fixed'
    else: text='NO_FINDINGS'
else:
    thread='builder-thread'
    if os.environ.get('DIRTY_TURN'):
        (wt/'decision.md').write_text('D1\n')
    elif not os.environ.get('NO_COMMIT'):
        f.write_text('bad\n' if mode=='build' else 'fixed\n')
        subprocess.run(['git','add','f.py'],cwd=wt,check=True)
        subprocess.run(['git','commit','--allow-empty','-qm','fixture: '+mode],cwd=wt,check=True)
    if os.environ.get('EDIT_BRIEF') and mode=='build':
        own=wt/'docs/handoff/2026-11-04-build.md'
        own.write_text(own.read_text()+'Status: built.\n')
        subprocess.run(['git','add',str(own)],cwd=wt,check=True)
        subprocess.run(['git','commit','-qm','fixture: own brief edited'],cwd=wt,check=True)
    if os.environ.get('NEXT_BRIEF'):
        brief=wt/'docs/handoff/2099-01-01-build.md'
        brief.write_text('The next step.\n')
        subprocess.run(['git','add',str(brief)],cwd=wt,check=True)
        subprocess.run(['git','commit','-qm','fixture: next brief'],cwd=wt,check=True)
    text=os.environ.get('BUILD_ANSWER','built') if mode=='build' else 'fixed'
if review_sub: text='Review comment:\n\n- [P1] Restore it — f.py:1-1\n  The real shape, which no parser here reads.'
if os.environ.get('STDERR_TEXT'): sys.stderr.write(os.environ['STDERR_TEXT']+'\n')
print(json.dumps({'type':'thread.started','thread_id':thread}))
if os.environ.get('RETRY_BLIP'): print(json.dumps({'type':'error','message':'Reconnecting... 1/2'}))
print(json.dumps({'type':'item.completed','item':{'type':'agent_message','text':text}}))
print(json.dumps({'type':'turn.completed','usage':{'input_tokens':10,'output_tokens':5}}))
if os.environ.get('FAIL_EXEC'): print(json.dumps({'type':'turn.failed','error':{'message':'fixture failure'}}))
'''


def cmd(*a, **kw):
    return subprocess.run(list(map(str, a)), capture_output=True, text=True, **kw)


def _hold_re():
    src = (B / "run-vendor").read_text()
    line = next(l for l in src.splitlines() if l.startswith("HOLD_RE = "))
    scope = {"re": __import__("re")}
    exec(line, scope)
    return scope["HOLD_RE"]


HOLD_RE = _hold_re()


class VendorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (T / "bin").mkdir(exist_ok=True)
        cli = T / "bin/codex"
        cli.write_text(STUB); cli.chmod(0o755)
        claude = T / "bin/claude"
        claude.write_text('#!/bin/sh\necho called >> "$CLAUDE_AUDIT"\nexit 91\n'); claude.chmod(0o755)
        screen = T / "bin/screen"
        screen.write_text('#!/bin/sh\nexit 95\n'); screen.chmod(0o755)
        check = T / "bin/check"
        check.write_text('#!/bin/sh\n[ "$2" = --builder ] || exit 98\n'
                         '[ "$CLAUDE_UNATTENDED" = vendor-build ] || exit 97\n'
                         '[ "$REGATTA_UNATTENDED" = vendor-build ] || exit 97\n'
                         '[ "$3" = --out ] || exit 98\n'
                         'if [ -n "$CHECK_SUMMARY" ]; then mkdir -p "$4"; printf "$CHECK_SUMMARY" > "$4/summary"; printf "the log tail\\n" > "$4/01-suite.log"; fi\n'
                         'if [ -n "$CHECK_RC" ]; then exit "$CHECK_RC"; fi\n'
                         'if [ -n "$CHECK_FAIL_BAD" ]; then [ "$(cat "$1/f.py")" = fixed ]; else exit 0; fi\n')
        check.chmod(0o755)
        ps = T / "bin/ps"
        ps.write_text('#!/bin/sh\ncase "$*" in "-o lstart= -p "*) echo "Thu Jan  1 00:00:00 2026";; *) exit 2;; esac\n'); ps.chmod(0o755)
        cfg = Path(os.environ["REGATTA_CONFIG"])
        (cfg / "home").write_text(str(B.parents[2]) + "\n")
        (cfg / "wharf-runs/only").write_text("codex\n")
        (cfg / "wharf-runs/features").write_text("laptop:codex\n")
        (cfg / "wharf-runs/build-review-rounds").write_text("2\n")
        (T / "gitconfig").write_text('[user]\nname = test\nemail = test@example.invalid\n[init]\ndefaultBranch = main\n')
        os.environ.update(PATH=str(T / "bin") + ":" + os.environ["PATH"], GIT_CONFIG_GLOBAL=str(T / "gitconfig"),
                          HARNESS_CODEX=str(cli), VENDOR_CHECK=str(check), CLAUDE_AUDIT=str(T / "claude.calls"),
                          HARNESS_AGY=str(T / "no-agy"), GEMINI_CLI_HOME=str(T / "no-gemini"),
                          DISPATCH_CLAUDE=str(claude),
                          CLAUDE_REPOS_JSON=str(T / "registry.json"), ACCOUNTS_FILE=str(T / "no-accounts"),
                          BUILD_REVIEW_LOG=str(T / "build-review.jsonl"), REVIEW_GATE_LOG=str(T / "review-gate.jsonl"),
                          DISPATCH_HOST="laptop")
        vh=importlib.machinery.SourceFileLoader("fixture_vendor_hooks",str(v.common.tool("vendor-hooks"))).load_module()
        home=Path(os.environ["CODEX_HOME"]); home.mkdir(parents=True, exist_ok=True)
        (home / "hooks.json").write_text(json.dumps({"hooks":{"PreToolUse":[{"matcher":"","hooks":[vh.handler("codex")]}]}}))

    def setUp(self):
        self.root = T / (type(self).__name__ + "-" + self._testMethodName)
        self.root.mkdir()
        self.repo = self.root / "repo"
        self.assertEqual(cmd("git", "init", "--bare", self.root / "origin.git").returncode, 0)
        self.assertEqual(cmd("git", "init", "-b", "main", self.repo).returncode, 0)
        def git(*args):
            r=cmd("git", "-C", self.repo, *args)
            self.assertEqual(r.returncode, 0, r.stderr)
            return r.stdout.strip()
        self.git=git
        (self.repo / "AGENTS.md").write_text("- physical: none\n")
        (self.repo / "f.py").write_text("start\n")
        git("add", "."); git("commit", "-qm", "init")
        git("remote", "add", "origin", self.root / "origin.git")
        git("push", "-q", "origin", "main")
        self.wt=self.repo / ".claude/worktrees/build"
        git("worktree", "add", "-b", "claude/laptop/build", self.wt)
        self.brief=self.wt / "docs/handoff/2026-11-04-build.md"
        self.brief.parent.mkdir(parents=True)
        self.brief.write_text("Build it.\n")
        self.assertEqual(cmd("git", "-C", self.wt, "add", "docs").returncode,0)
        self.assertEqual(cmd("git", "-C", self.wt, "commit", "-qm", "seed").returncode,0)
        Path(os.environ["CLAUDE_REPOS_JSON"]).write_text(json.dumps({"repos":{},"scopes":{"open":{"repos":["*"]}}}))
        self.record=self.root / "run.json"
        arm=v.buildercoin.arm_of("gpt-big:3:2099-01-01:0")
        self.record.write_text(json.dumps({"session":self._testMethodName, "repo":str(self.repo), "topic":"build", "arm":arm}))
        self.audit=self.root / "audit.jsonl"
        os.environ["AUDIT"]=str(self.audit)

    def launch(self, *flags, **env):
        return cmd(sys.executable, B / "run-vendor", self.wt, "--cli", "codex", "--record", self.record,
                   "--brief", self.brief, "--effort", "xhigh", *flags, env=dict(os.environ, **env))

    def test_build_review_fix_clean(self):
        r=self.launch(); self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        state=json.loads(self.record.read_text())
        self.assertEqual((state["outcome"],state["turns"],state["rounds"]),("clean",2,2))
        self.assertIsInstance(state["pid"],int); self.assertIsNone(state["turn_pid"])
        self.assertEqual(state["conversation"],"builder-thread")
        self.assertEqual(state["cost"]["openai"],{"input_tokens":70,"output_tokens":35})
        self.assertEqual(state["cost"]["anthropic"],{"input_tokens":0,"output_tokens":0})
        calls=[json.loads(l) for l in self.audit.read_text().splitlines()]
        self.assertEqual([x["mode"] for x in calls],["build","review","review","review","resume","review","review"])
        self.assertFalse(Path(os.environ["CLAUDE_AUDIT"]).exists(),"Claude must never start")
        self.assertEqual((self.wt / "f.py").read_text(),"fixed\n")
        rows=[json.loads(l) for l in (Path.home() / "Library/Logs/claude-weekly/builder-rotation.jsonl").read_text().splitlines()]
        row=next(r for r in rows if r["session"]==self._testMethodName)
        self.assertEqual((row["agent"],row["conversation"],row["outcome"],row["turns"],row["rounds"]),
                         ("codex","builder-thread","clean",2,2))
        self.assertEqual(row["cost"],state["cost"])

    def calls(self):
        return [json.loads(l) for l in self.audit.read_text().splitlines()]

    def state(self):
        return json.loads(self.record.read_text())

    def test_a_review_is_a_plain_exec_and_its_trailer_passes(self):
        # never `codex exec review`, whose own shape the stub gives as the real CLI does; and the reviewer template's
        # trailer after the word is a clean report
        r=self.launch(CLEAN_REVIEWS="1",CLEAN_TEXT="NO_FINDINGS\n\nChecked: 7 files read")
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual(self.state()["outcome"],"clean",r.stdout+r.stderr)

    def test_a_red_check_hands_the_fix_turn_its_failure(self):
        r=self.launch(CLEAN_REVIEWS="1",CHECK_RC="1",CHECK_SUMMARY="10:00 rc=1 3s bash t.sh\\nDONE 0/1\\n")
        self.assertEqual(self.state()["outcome"],"cap",r.stdout+r.stderr)
        fix=[c["prompt"] for c in self.calls() if c["mode"]=="resume"][0]
        self.assertIn("rc=1 3s bash t.sh",fix); self.assertIn("the log tail",fix)
        self.assertNotIn("Read the check logs",fix)

    def test_an_unrun_command_is_green_and_noted(self):
        r=self.launch(CLEAN_REVIEWS="1",CHECK_RC="3",CHECK_SUMMARY="UNRUN echo added\\nDONE 1/1\\n")
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual(self.state()["outcome"],"clean",r.stdout+r.stderr)
        self.assertEqual([c["mode"] for c in self.calls()],["build","review","review"])

    def test_a_refused_check_holds_before_any_review(self):
        r=self.launch(CHECK_RC="2",CHECK_SUMMARY="REFUSED no check line\\n")
        self.assertNotEqual(r.returncode,0,r.stdout+r.stderr)
        s=self.state(); self.assertEqual(s["outcome"],"held",r.stdout+r.stderr)
        self.assertIn("REFUSED no check line",s["end_reason"]); self.assertFalse(s["retry_claude"])
        self.assertEqual([c["mode"] for c in self.calls()],["build"])

    def test_a_refused_clean_end_exits_non_zero(self):
        # the refusal inside the process: run-vendor names build-review by its own folder
        driver=self.root/"driver.py"
        driver.write_text("""import importlib.machinery, subprocess, sys
sys.path.insert(0, sys.argv[1])
m = importlib.machinery.SourceFileLoader("rv", sys.argv[1] + "/run-vendor").load_module()
real = subprocess.run
def run(a, *k, **kw):
    if a[2:3] == ["end"] and "clean" in a:
        return subprocess.CompletedProcess(a, 1, "", "refused by the case")
    return real(a, *k, **kw)
subprocess.run = run
sys.argv = ["run-vendor"] + sys.argv[2:]
sys.exit(m.main())
""")
        r=cmd(sys.executable,driver,B,self.wt,"--cli","codex","--record",self.record,"--brief",self.brief,"--effort","xhigh",
              env=dict(os.environ,CLEAN_REVIEWS="1"))
        self.assertEqual(self.state()["outcome"],"failed",r.stdout+r.stderr)
        self.assertEqual((r.returncode,self.state()["exit"]),(1,1),r.stdout+r.stderr)

    def test_a_note_reaches_the_first_turn(self):
        d=self.state(); d["note"]="NOTE-FOR-THE-BUILD"; self.record.write_text(json.dumps(d))
        r=self.launch(CLEAN_REVIEWS="1"); self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertIn("NOTE-FOR-THE-BUILD",self.calls()[0]["prompt"])

    def test_a_blip_before_any_turn_writes_no_row(self):
        self.git("remote","set-url","origin",self.root/"gone.git")
        r=self.launch(); self.assertEqual(r.returncode,4,r.stdout+r.stderr)
        rows=(Path.home()/"Library/Logs/claude-weekly/builder-rotation.jsonl")
        self.assertNotIn(self._testMethodName,rows.read_text() if rows.exists() else "")

    def test_a_failed_turn_keeps_the_vendors_words(self):
        r=self.launch(FAIL_BEFORE_COMMIT="1")
        self.assertIn("fixture failure before commit",self.state()["end_reason"],r.stdout+r.stderr)

    def test_a_failed_exit_keeps_stderr(self):
        r=self.launch(FAIL_EXIT_QUIET="1",STDERR_TEXT="usage limit reached")
        self.assertIn("usage limit reached",self.state()["end_reason"],r.stdout+r.stderr)

    def test_the_class_not_the_text_decides_a_hold(self):
        # git's rejection names the branch: a word in it must not make a failure a hold
        self.assertEqual(cmd("git","-C",self.wt,"branch","-m","claude/laptop/vendor-fence-held-fix").returncode,0)
        hook=self.root/"origin.git/hooks/pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n"); hook.chmod(0o755)
        r=self.launch()
        self.assertEqual(self.state()["outcome"],"failed",r.stdout+r.stderr)
        self.assertIsInstance(v.Held("x"),v.Refused)

    def test_a_scope_name_in_a_verdict_is_a_hold(self):
        Path(os.environ["CLAUDE_REPOS_JSON"]).write_text(json.dumps({"repos":{},"scopes":{"open":{"repos":["*"]},
            "wall":{"confidential":True,"repos":["elsewhere"]}}}))
        with self.assertRaises(v.Held):
            v.fence(self.wt,"codex","","names the wall here")

    def test_a_scope_name_matches_at_a_token_start_only(self):
        Path(os.environ["CLAUDE_REPOS_JSON"]).write_text(json.dumps({"repos":{},"scopes":{"open":{"repos":["*"]},
            "ops":{"confidential":True,"repos":["elsewhere"]}}}))
        v.fence(self.wt,"codex","","the check stops; the operator reads it")   # "stops" holds no scope name
        for text in ("ops", "see opsdesk", "the ops-site page", "v2ops.md", "see 2ops"):   # a short name: at a token's start, a digit before it included
            with self.assertRaises(v.Held):
                v.fence(self.wt,"codex","",text)

    def test_a_long_scope_name_holds_inside_a_word(self):
        Path(os.environ["CLAUDE_REPOS_JSON"]).write_text(json.dumps({"repos":{},"scopes":{"open":{"repos":["*"]},
            "acmecorp":{"confidential":True,"repos":["elsewhere"]}}}))
        with self.assertRaises(v.Held):
            v.fence(self.wt,"codex","","see loadAcmecorp()")   # the publish gate's rule: 5+ characters anywhere

    def test_the_main_is_the_main_checkouts(self):
        self.assertEqual(v.main_name(self.wt),"main")
        wf=self.wt/".claude"/"workflow.json"; wf.parent.mkdir(exist_ok=True); wf.write_text('{"main": "elsewhere"}')
        self.addCleanup(wf.unlink)
        self.assertEqual(v.main_name(self.wt),"main", "a branch's own workflow.json never decides")

    def test_the_house_waiting_line_holds_in_every_form(self):
        rv=importlib.machinery.SourceFileLoader("vendor_fixture_rv_hold",str(B/"run-vendor")).load_module()
        for line in ("WAITING FOR you: D1", "\U0001f6d1 THIS SESSION IS WAITING FOR YOU \u2014 D1",
                     "\U0001f6d1 MARY ANN, THIS SESSION IS WAITING FOR YOU \u2014 D1",
                     "\U0001f6d1 JOS\u00c9, THIS SESSION IS WAITING FOR YOU \u2014 D1"):
            self.assertTrue(rv.HOLD_RE.match(line), line)
        for line in ("Done, WAITING FOR review", "I noted that WAITING FOR x",
                     "\u2705 OWNER, THIS SESSION IS WAITING FOR NOTHING \u2014 built"):
            self.assertFalse(rv.HOLD_RE.match(line), line)

    def test_codex_takes_no_if_room(self):
        self.assertIn('codex_refuse "--harness codex takes no --if-room', (B/"dispatch").read_text())

    def test_a_codex_folder_in_the_checkout_holds(self):
        d=self.wt/".codex"; d.mkdir(); (d/"hooks.json").write_text("{}")
        self.addCleanup(lambda: (d/"hooks.json").unlink() or d.rmdir())
        with self.assertRaises(v.Held):
            v.fence(self.wt,"codex","","a prompt")

    def test_a_second_hook_event_is_no_guard(self):
        p=Path(os.environ["CODEX_HOME"]) / "hooks.json"
        text=p.read_text(); cfg=json.loads(text)
        cfg["hooks"]["SessionStart"]=[{"matcher":"","hooks":[{"type":"command","command":"true"}]}]
        p.write_text(json.dumps(cfg)); self.addCleanup(lambda: p.write_text(text))
        self.assertIn("guards alone", v.codex_guards())

    def test_finish_only_brief_runs_the_check_alone(self):
        self.brief.write_text("Build it.\n\nReview: finish only\n")
        self.assertEqual(cmd("git","-C",self.wt,"commit","-qam","finish only").returncode,0)
        r=self.launch(); self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual(self.state()["outcome"],"clean",r.stdout+r.stderr)
        self.assertEqual([c["mode"] for c in self.calls()],["build"])

    def test_finish_only_red_check_gets_a_fix_turn(self):
        self.brief.write_text("Review: finish only\n")
        self.assertEqual(cmd("git","-C",self.wt,"commit","-qam","finish only").returncode,0)
        r=self.launch(CHECK_FAIL_BAD="1"); self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual([c["mode"] for c in self.calls()],["build","resume"])

    def test_status_reads_a_live_vendor_run(self):
        logs=self.root/"h"
        runs=logs/"Library/Logs/claude-weekly/run-seed-runs"; runs.mkdir(parents=True)
        (runs/"build.json").write_text(json.dumps({"mode":"vendor","topic":"build","repo":str(self.repo),"session":"s",
            "pid":os.getpid(),"proc_start":"Thu Jan  1 00:00:00 2026","started":1,"cli":"codex","conversation":"th","turns":2,"log":"l"}))
        r=cmd(sys.executable,B/"dispatch-rc","status",env=dict(os.environ,HOME=str(logs)))
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertNotIn("vscode://",r.stdout)

    def test_gpt_size_reads_past_the_odds(self):
        (Path(os.environ["REGATTA_CONFIG"])/v.buildercoin.ODDS_KEY).unlink(missing_ok=True)
        self.assertIsNone(v.buildercoin.gpt_class("Tier: sr-worker\n"))
        self.assertEqual(v.buildercoin.gpt_size("Tier: sr-worker\n"),"gpt-big")
        self.assertEqual(v.buildercoin.gpt_size("Tier: worker\n"),"gpt-mid")
        self.assertIsNone(v.buildercoin.gpt_size("Tier: principal-worker\n"))

    def test_a_clean_report_in_prose_is_asked_again(self):
        r=self.launch(CLEAN_REVIEWS="1",CLEAN_TEXT="No findings in the assigned diff.")
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual(self.state()["outcome"],"clean",r.stdout+r.stderr)
        self.assertEqual([c["mode"] for c in self.calls()],["build","review","review","review"])

    def test_a_code_review_that_answers_no_findings_is_clean(self):
        r=self.launch(CLEAN_REVIEWS="1",CODE_REVIEW_TEXT="NO_FINDINGS")
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual(self.state()["outcome"],"clean",r.stdout+r.stderr)

    def test_a_code_review_in_prose_is_refused(self):
        r=self.launch(CLEAN_REVIEWS="1",CODE_REVIEW_TEXT="Looks fine to me.")
        s=self.state(); self.assertEqual(s["outcome"],"failed",r.stdout+r.stderr)
        self.assertIn("not a findings list",s["end_reason"])

    def test_a_prose_report_that_stays_prose_is_refused(self):
        r=self.launch(CLEAN_REVIEWS="1",CLEAN_TEXT="No findings.",REFORMATTED="Still prose.")
        s=self.state(); self.assertEqual(s["outcome"],"failed",r.stdout+r.stderr)
        self.assertIn("no verdict or NO_FINDINGS",s["end_reason"])

    def test_a_retried_blip_is_no_failed_turn(self):
        r=self.launch(CLEAN_REVIEWS="1",RETRY_BLIP="1"); self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual(self.state()["outcome"],"clean",r.stdout+r.stderr)

    def test_a_mention_of_waiting_for_holds_nothing(self):
        for answer in ('Changed the "WAITING FOR" closing line check; tests pass.',
                       "built\n\n\u2705 OWNER, THIS SESSION IS WAITING FOR NOTHING \u2014 built",
                       "\u23f3 OWNER, THIS SESSION IS WAITING FOR SOMETHING \u2014 the check"):
            self.assertIsNone(HOLD_RE.match(answer.splitlines()[-1]),answer)
        r=self.launch(CLEAN_REVIEWS="1",BUILD_ANSWER='built\n\nWAITING FOR NOTHING')
        self.assertEqual(self.state()["outcome"],"clean",r.stdout+r.stderr)

    def test_a_hold_on_an_uncommitted_d_item_is_a_hold(self):
        r=self.launch(DIRTY_TURN="1",BUILD_ANSWER="D1 written.\nWAITING FOR the owner on D1")
        s=self.state(); self.assertEqual(s["outcome"],"held",r.stdout+r.stderr)
        self.assertFalse(s["retry_claude"])

    def test_a_turn_that_commits_nothing_is_a_failure(self):
        r=self.launch(NO_COMMIT="1",BUILD_ANSWER="I cannot do this.")
        s=self.state(); self.assertEqual(s["outcome"],"failed",r.stdout+r.stderr)
        self.assertIn("committed nothing",s["end_reason"]); self.assertTrue(s["retry_claude"])
        self.assertEqual([c["mode"] for c in self.calls()],["build"])

    def test_a_size_refusal_is_a_failure(self):
        d=self.state(); d["note"]="x"*70000; self.record.write_text(json.dumps(d))
        r=self.launch(); self.assertEqual(self.state()["outcome"],"failed",r.stdout+r.stderr)

    def test_a_merge_blip_is_a_wait(self):
        (self.repo/"new.py").write_text("main\n"); self.git("add","new.py"); self.git("commit","-qm","main gains new.py")
        self.git("push","-q","origin","main")
        (self.wt/"new.py").write_text("untracked here\n")
        r=self.launch(); self.assertEqual(r.returncode,4,r.stdout+r.stderr)
        self.assertFalse(self.audit.exists())

    def test_a_hold_before_any_turn_writes_no_row(self):
        (self.repo/"f.py").write_text("main\n"); self.git("commit","-qam","main"); self.git("push","-q","origin","main")
        (self.wt/"f.py").write_text("branch\n")
        self.assertEqual(cmd("git","-C",self.wt,"commit","-qam","branch").returncode,0)
        r=self.launch(); self.assertEqual(self.state()["outcome"],"held",r.stdout+r.stderr)
        self.assertIn("f.py",self.state()["end_reason"])
        rows=Path.home()/"Library/Logs/claude-weekly/builder-rotation.jsonl"
        self.assertNotIn(self._testMethodName,rows.read_text() if rows.exists() else "")

    def test_a_lost_row_keeps_the_end_handling(self):
        rows=Path.home()/"Library/Logs/claude-weekly/builder-rotation.jsonl"
        keep=rows.with_suffix(".kept")
        if rows.exists(): rows.rename(keep)
        rows.mkdir(parents=True)
        def back():
            rows.rmdir()
            if keep.exists(): keep.rename(rows)
        self.addCleanup(back)
        r=self.launch(CLEAN_REVIEWS="1"); self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        owner=json.loads((Path(v.git(self.wt,"rev-parse","--absolute-git-dir"))/"claude/owner.json").read_text())
        self.assertTrue(owner.get("handover"),r.stdout)

    def test_finish_only_last_fix_is_checked(self):
        self.brief.write_text("Review: finish only\n")
        self.assertEqual(cmd("git","-C",self.wt,"commit","-qam","finish only").returncode,0)
        (Path(os.environ["REGATTA_CONFIG"])/"wharf-runs/build-review-rounds").write_text("1\n")
        self.addCleanup(lambda: (Path(os.environ["REGATTA_CONFIG"])/"wharf-runs/build-review-rounds").write_text("2\n"))
        r=self.launch(CHECK_FAIL_BAD="1"); self.assertEqual(self.state()["outcome"],"clean",r.stdout+r.stderr)

    def test_finish_only_is_dispatchs_line_test(self):
        self.brief.write_text("Review:\nfinish only the docs change is wanted\n")
        self.assertEqual(cmd("git","-C",self.wt,"commit","-qam","two lines").returncode,0)
        r=self.launch(CLEAN_REVIEWS="1"); self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertIn("review",[c["mode"] for c in self.calls()])

    def test_a_fallback_preserves_hard_pins(self):
        q=importlib.machinery.SourceFileLoader("fixture_queue_pin",str(B/"dispatch-queue")).load_module()
        for pin in ({"pin_kind": "typed"}, {"pin_kind": "login"},
                    {"pinned_why": "unpublished worktree"}, {}):
            with self.subTest(pin=pin):
                e = dict(pin, host="buildbox", state="claimed", running_on="buildbox", claimed_by="buildbox",
                         job="vendor-job", args=["--harness", "codex", "--needs", "codex,mac"],
                         needs=["codex", "mac"], arm_need="codex", env={})
                fallback = dict(e, **q.vendor_fallback_fields(e))
                for key in ("host", "pin_kind", "pinned_why"):
                    self.assertEqual(fallback.get(key), e.get(key))
                self.assertEqual(fallback["state"], "queued")
                self.assertFalse(fallback["running_on"] or fallback["claimed_by"] or fallback["job"])
                self.assertEqual(fallback["needs"], ["mac"])
                self.assertIsNone(q.bad_args(fallback))
                self.assertEqual(q.eligibility(fallback, "laptop"), "pinned to buildbox")
                # The pinned builder has no Claude login: its own claim filter holds the fallback.
                self.assertIn("only entries that need codex", q.only_refusal(fallback))

    def test_dispatch_hands_the_chain_to_a_vendor_run(self):
        # the record of what run-vendor's own environment held, read by the stand-in check
        probe=self.root/"env.txt"
        check=self.root/"check-env"
        check.write_text('#!/bin/sh\nenv | grep -E "^DISPATCH_(MODE|TASK)=" > "%s"\nexit 0\n' % probe); check.chmod(0o755)
        env=self.fire_env(VENDOR_CHECK=str(check),CLEAN_REVIEWS="1")
        r=cmd(B/"dispatch","claude/laptop/build","--repo",self.repo,"--harness","codex",env=env,timeout=90)
        self.assertEqual(r.returncode,0,self.log.read_text() if self.log.exists() else r.stderr)
        self.assertIn("DISPATCH_MODE=default",probe.read_text())   # DISPATCH_TASK rides the same chain, with a skipper

    def test_round_cap(self):
        r=self.launch(ALWAYS_FIND="1"); self.assertNotEqual(r.returncode,0,r.stdout+r.stderr)
        state=json.loads(self.record.read_text()); self.assertEqual(state["outcome"],"cap",r.stdout+r.stderr)
        self.assertFalse(Path(os.environ["CLAUDE_AUDIT"]).exists())

    def test_lowered_live_cap_stops_before_the_next_round(self):
        launcher = importlib.machinery.SourceFileLoader("vendor_fixture_live_cap", str(B / "run-vendor")).load_module()
        cap = Path(os.environ["REGATTA_CONFIG"]) / "wharf-runs/build-review-rounds"
        cap.write_text("3\n")
        self.addCleanup(lambda: cap.write_text("2\n"))
        real_run = subprocess.run
        rounds = []

        def run(argv, **kw):
            result = real_run(argv, **kw)
            if argv[1:3] == [str(B / "build-review"), "round"] and result.returncode == 0:
                rounds.append(argv)
                cap.write_text("1\n")
            return result

        args = SimpleNamespace(worktree=self.wt, cli="codex", model=v.MODEL, effort="xhigh", origin="",
                               record=self.record, brief=self.brief, preflight=False, next=False, timeout=90)
        with patch.dict(os.environ, ALWAYS_FIND="1"), patch.object(launcher.subprocess, "run", side_effect=run):
            self.assertEqual(launcher.run(args), 1)
        state = self.state()
        self.assertEqual((state["outcome"], state["rounds"], state["turns"]), ("cap", 1, 2))
        self.assertEqual(state["end_reason"], "build-review round cap")
        self.assertEqual(len(rounds), 1)
        self.assertEqual([c["mode"] for c in self.calls()], ["build", "review", "review", "review", "resume"])

    def test_expired_owner_allows_a_new_run(self):
        gd = Path(v.git(self.wt, "rev-parse", "--absolute-git-dir")) / "claude"
        gd.mkdir()
        (gd / "owner.json").write_text(json.dumps({"session": "abandoned", "seen": time.time() - v.common.OWNER_TTL - 1}))
        r = self.launch(CLEAN_REVIEWS="1")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(v.common.read_owner(gd)["session"], self._testMethodName)

    def test_recent_owner_refuses_a_new_run(self):
        gd = Path(v.git(self.wt, "rev-parse", "--absolute-git-dir")) / "claude"
        v.common.write_owner(gd, "other-session", "claude/laptop/build")
        r = self.launch()
        self.assertEqual(r.returncode, 4, r.stdout + r.stderr)
        self.assertIn("refused for now: another session holds", r.stderr)
        self.assertFalse(self.audit.exists())
        self.assertEqual(v.common.read_owner(gd)["session"], "other-session")

    def test_launcher_lock_refuses_even_with_an_expired_owner(self):
        gd = Path(v.git(self.wt, "rev-parse", "--absolute-git-dir")) / "claude"
        gd.mkdir()
        (gd / "owner.json").write_text(json.dumps({"session": "abandoned", "seen": 0}))
        with (gd / "vendor.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            r = self.launch()
        self.assertEqual(r.returncode, 4, r.stdout + r.stderr)
        self.assertIn("refused for now: another vendor launcher holds", r.stderr)
        self.assertFalse(self.audit.exists())

    def test_failure_after_start_is_vendor_failure(self):
        r=self.launch(FAIL_EXEC="1"); self.assertEqual(r.returncode,1,r.stdout+r.stderr)
        state=json.loads(self.record.read_text())
        self.assertEqual((state["agent"],state["outcome"],state["turns"]),("codex","failed",1))
        self.assertEqual(state["cost"]["openai"]["input_tokens"],10)
        self.assertFalse(Path(os.environ["CLAUDE_AUDIT"]).exists())

    def test_fetch_failure_before_any_turn_is_a_wait(self):
        # the launcher's fetch fails (origin gone): no vendor ran, so exit 4 hands the entry back; no Claude retry
        self.git("remote", "set-url", "origin", self.root / "gone.git")
        r = self.launch()
        self.assertEqual(r.returncode, 4, r.stdout + r.stderr)
        state = json.loads(self.record.read_text())
        self.assertEqual(state["turns"], 0)
        self.assertFalse(state["retry_claude"])
        self.assertIn("before any vendor turn", state["end_reason"])
        self.assertFalse(self.audit.exists())

    def test_sibling_topic_brief_is_no_next_brief(self):
        launcher = importlib.machinery.SourceFileLoader("vendor_fixture_launcher_sib", str(B / "run-vendor")).load_module()
        sib = self.wt / "docs/handoff/2099-01-01-other-build.md"
        sib.write_text("A sibling topic's brief.\n")
        v.git(self.wt, "add", str(sib)); v.git(self.wt, "commit", "-qm", "sibling brief")
        calls = []
        original_run = subprocess.run

        def fake_run(argv, **kw):
            if str(argv[0]) == str(B / "dispatch"):
                calls.append(argv)
                return subprocess.CompletedProcess(argv, 0)
            return original_run(argv, **kw)
        args = SimpleNamespace(worktree=self.wt, cli="codex", model=v.MODEL, effort="xhigh", origin="", coin=False,
                               record=self.record, brief=self.brief, preflight=False, next=False, timeout=90)
        with patch.dict(os.environ, {"CLEAN_REVIEWS": "1"}), patch.object(launcher.subprocess, "run", fake_run):
            self.assertEqual(launcher.run(args), 0)
        self.assertEqual(calls, [], "a later brief of a topic that ends in this one's name schedules no --next")

    def test_failed_end_frees_the_worktree(self):
        gd = Path(v.git(self.wt, "rev-parse", "--absolute-git-dir")) / "claude"
        r = self.launch(FAIL_EXEC="1"); self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIsNone(v.common.read_owner(gd), "an ended run's lock must not refuse the next fire")
        self.record.write_text(json.dumps({"session": "second", "repo": str(self.repo), "topic": "build"}))
        r = self.launch(CLEAN_REVIEWS="1")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_conflicting_main_merge_is_aborted_and_held(self):
        (self.wt / "f.py").write_text("branch side\n")
        v.git(self.wt, "commit", "-qam", "branch edit")
        (self.repo / "f.py").write_text("main side\n")
        self.git("commit", "-qam", "main edit"); self.git("push", "-q", "origin", "main")
        r = self.launch(); self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        state = json.loads(self.record.read_text())
        self.assertEqual(state["outcome"], "held", r.stdout + r.stderr)
        self.assertIn("does not merge cleanly", state["end_reason"])
        self.assertEqual(v.git(self.wt, "status", "--porcelain"), "")
        self.assertNotEqual(cmd("git", "-C", self.wt, "rev-parse", "-q", "--verify", "MERGE_HEAD").returncode, 0)
        self.assertFalse(self.audit.exists(), "no vendor turn on a tree main does not merge into")

    def test_protected_path_from_main_holds_before_any_vendor_turn(self):
        (self.repo / ".env.local").write_text("fixture=1\n")
        self.git("add", ".env.local"); self.git("commit", "-qm", "main gains a protected path")
        self.git("push", "-q", "origin", "main")
        r = self.launch()
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        state = self.state()
        self.assertEqual((state["outcome"], state["turns"]), ("held", 0), r.stdout + r.stderr)
        self.assertIn("checkout holds a protected path", state["end_reason"])
        self.assertFalse(state["retry_claude"])
        self.assertTrue((self.wt / ".env.local").is_file(), "the merge introduced the protected path")
        self.assertFalse(self.audit.exists(), "no vendor turn on the merged protected tree")

    def test_stopped_run_requests_no_retry_and_keeps_its_reason(self):
        r = self.launch(WRITE_ENDING=str(self.record)); self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        state = json.loads(self.record.read_text())
        self.assertEqual(state["outcome"], "failed")
        self.assertFalse(state["retry_claude"], "a stop is no failure to retry")
        self.assertEqual((state["ending"], state["end_reason"]), ("requeued by the fixture",) * 2)

    def test_torn_registry_is_refused_for_now(self):
        Path(os.environ["CLAUDE_REPOS_JSON"]).write_text("{not json")
        r = self.launch("--preflight")
        self.assertEqual(r.returncode, 4, r.stdout + r.stderr)
        self.assertIn("refused for now", r.stderr)

    def test_registry_that_does_not_walk_is_refused_for_now(self):
        Path(os.environ["CLAUDE_REPOS_JSON"]).write_text(json.dumps({"repos": {}, "scopes": {"open": {"repos": 7}}}))
        r = self.launch("--preflight")
        self.assertEqual(r.returncode, 4, r.stdout + r.stderr)
        self.assertIn("refused for now", r.stderr)
        self.assertIn("does not walk", r.stderr)

    def test_preflight_refuses_a_live_owner_or_launcher_for_now(self):
        gd = Path(v.git(self.wt, "rev-parse", "--absolute-git-dir")) / "claude"
        v.common.write_owner(gd, "other-session", "claude/laptop/build")
        r = self.launch("--preflight")
        self.assertEqual(r.returncode, 4, r.stdout + r.stderr)
        self.assertIn("refused for now: another session holds", r.stderr)
        (gd / "owner.json").unlink()
        with (gd / "vendor.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            r = self.launch("--preflight")
        self.assertEqual(r.returncode, 4, r.stdout + r.stderr)
        self.assertIn("refused for now: another vendor launcher holds", r.stderr)
        r = self.launch("--preflight")
        self.assertEqual(r.returncode, 0, "a released lock and no owner pass: " + r.stderr)
        v.common.write_owner(gd, "pickup", "claude/laptop/build", handover=True)
        r = self.launch("--preflight")
        self.assertEqual(r.returncode, 0, "a handed-over owner holds nobody out: " + r.stderr)
        self.assertFalse(self.audit.exists())

    def test_own_brief_edit_schedules_no_next(self):
        launcher = importlib.machinery.SourceFileLoader("vendor_fixture_launcher2", str(B / "run-vendor")).load_module()
        original_run = subprocess.run
        calls = []

        def run(argv, **kw):
            if str(argv[0]) == str(B / "dispatch"):
                calls.append(argv); return subprocess.CompletedProcess(argv, 0)
            return original_run(argv, **kw)

        args = SimpleNamespace(worktree=self.wt, cli="codex", model=v.MODEL, effort="xhigh", origin="",
                               record=self.record, brief=self.brief, preflight=False, next=False, timeout=90)
        with patch.dict(os.environ, dict(EDIT_BRIEF="1", CLEAN_REVIEWS="1")), \
                patch.object(launcher.subprocess, "run", side_effect=run):
            self.assertEqual(launcher.run(args), 0)
        self.assertIn("Status: built.", self.brief.read_text())
        self.assertEqual(calls, [], "an edit of the builder's own brief is no next brief")

    def test_failure_before_commit_requests_a_separate_fleet_retry(self):
        r=self.launch(FAIL_BEFORE_COMMIT="1"); self.assertEqual(r.returncode,1,r.stdout+r.stderr)
        state=json.loads(self.record.read_text())
        self.assertEqual(state["outcome"],"failed")
        self.assertTrue(state["retry_claude"])
        self.assertFalse(Path(os.environ["CLAUDE_AUDIT"]).exists())

    def test_failure_after_launcher_merge_still_requests_retry(self):
        (self.repo / "from-main").write_text("main advanced\n")
        self.git("add", "from-main"); self.git("commit", "-qm", "advance main")
        main_tip = self.git("rev-parse", "HEAD")
        self.git("push", "-q", "origin", "main")
        before = v.git(self.wt, "rev-parse", "HEAD")
        r = self.launch(FAIL_BEFORE_COMMIT="1")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        state = json.loads(self.record.read_text())
        self.assertNotEqual(state["tip"], before)
        self.assertEqual(v.git(self.wt, "rev-parse", "HEAD^2"), main_tip)
        self.assertTrue(state["retry_claude"])

    def test_check_only_fix_gets_a_fresh_review(self):
        r = self.launch(CLEAN_REVIEWS="1", CHECK_FAIL_BAD="1")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        state = json.loads(self.record.read_text())
        self.assertEqual((state["outcome"], state["rounds"]), ("clean", 2))
        calls = [json.loads(line)["mode"] for line in self.audit.read_text().splitlines()]
        self.assertEqual(calls, ["build", "review", "review", "resume", "review", "review"])

    def test_check_only_fix_at_cap_cannot_end_clean(self):
        cap = Path(os.environ["REGATTA_CONFIG"]) / "wharf-runs/build-review-rounds"
        with patch.dict(os.environ, CLEAN_REVIEWS="1", CHECK_FAIL_BAD="1"):
            cap.write_text("1\n")
            try:
                r = self.launch()
            finally:
                cap.write_text("2\n")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertEqual(json.loads(self.record.read_text())["outcome"], "cap")

    def test_next_brief_passes_branch_and_releases_owner_through_dispatch(self):
        launcher = importlib.machinery.SourceFileLoader("vendor_fixture_launcher", str(B / "run-vendor")).load_module()
        original_run = subprocess.run
        calls = []
        routing = {"DISPATCH_SKIPPER": "owner-session", "DISPATCH_SHIP": "ship-1",
                   "DISPATCH_SKIPPER_ACCOUNT": "acct-a", "DISPATCH_PLAN_SPACE": "sp-1",
                   "DISPATCH_SKIPPER_HOST": "buildbox", "DISPATCH_TASK": "build"}

        def run(argv, **kw):
            if str(argv[0]) != str(B / "dispatch"):
                return original_run(argv, **kw)
            calls.append(argv)
            self.assertEqual(argv[1:], ["claude/laptop/build", "--next", "--repo", str(self.repo)])
            gd = Path(v.git(self.wt, "rev-parse", "--absolute-git-dir")) / "claude"
            owner = v.common.read_owner(gd)
            self.assertEqual(owner["session"], self._testMethodName)
            self.assertFalse(owner.get("handover"), "dispatch must see this session as mine, not handed")
            self.assertEqual(kw["env"]["CLAUDE_CODE_SESSION_ID"], owner["session"])
            self.assertEqual(kw["env"]["CLAUDE_UNATTENDED"], "vendor-build")
            # the launcher lock is free for the next step's own pre-flight probe
            with (gd / "vendor.lock").open("a") as probe:
                fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.flock(probe, fcntl.LOCK_UN)
            self.assertEqual({key: kw["env"].get(key) for key in routing}, routing)
            self.assertNotIn("DISPATCH_LABEL", kw["env"])
            self.assertNotIn("DISPATCH_ARM", kw["env"])
            (gd / "owner.json").unlink()  # dispatch's same-session release
            return subprocess.CompletedProcess(argv, 0)

        args = SimpleNamespace(worktree=self.wt, cli="codex", model=v.MODEL, effort="xhigh", origin="",
                               record=self.record, brief=self.brief, preflight=False, next=False, timeout=90)
        with patch.dict(os.environ, dict(routing, NEXT_BRIEF="1", CLEAN_REVIEWS="1",
                                        DISPATCH_LABEL="old-job", DISPATCH_ARM="old-arm")), \
                patch.object(launcher.subprocess, "run", side_effect=run):
            self.assertEqual(launcher.run(args), 0)
        self.assertEqual(len(calls), 1)
        gd = Path(v.git(self.wt, "rev-parse", "--absolute-git-dir")) / "claude"
        self.assertFalse((gd / "owner.json").exists(), "launcher must not retake the next step's lock")

    def test_missing_guards_refuse_before_vendor_start(self):
        p=Path(os.environ["CODEX_HOME"]) / "hooks.json"
        text=p.read_text(); p.unlink()
        try:
            r=self.launch("--preflight"); self.assertEqual(r.returncode,3)
            self.assertFalse(self.audit.exists())
        finally:
            p.write_text(text)

    def test_principal_refused_before_vendor_start(self):
        self.brief.write_text("Tier: principal-worker\n")
        r=self.launch(); self.assertEqual(r.returncode,2)
        self.assertFalse(self.audit.exists())

    def test_launcher_liveness_without_a_claude_registry(self):
        rc=importlib.machinery.SourceFileLoader("vendor_fixture_rc",str(B / "dispatch-rc")).load_module()
        state={"pid":os.getpid(),"mode":"vendor","session":"vendor-thread"}
        self.assertTrue(rc.same(state))
        self.assertFalse(rc.parked(state))

    def test_declared_cross_vendor_review_needs_a_ready_login(self):
        p=Path(os.environ["REGATTA_CONFIG"]) / "wharf-runs/features"
        text=p.read_text(); p.write_text("laptop:codex,agy\n")
        try:
            r=self.launch(); self.assertEqual(r.returncode,1,r.stdout+r.stderr)
            state=json.loads(self.record.read_text())
            self.assertEqual(state["outcome"],"held")
            self.assertIn("agy",state["end_reason"])
            self.assertFalse(Path(os.environ["CLAUDE_AUDIT"]).exists())
        finally:
            p.write_text(text)

    def test_reviewer_features_accept_spaces_and_bootstrap_lines(self):
        p = Path(os.environ["REGATTA_CONFIG"]) / "wharf-runs/features"
        text = p.read_text()
        try:
            for row in ("laptop:codex, agy\n", "laptop:codex,\nagy\n",
                        "buildbox:codex,agy\nlaptop:codex\n",
                        "laptop:codex\nbuildbox:agy\n"):
                with self.subTest(row=row):
                    p.write_text(row)
                    expected = "antigravity" if row.startswith("laptop:codex,") else "codex"
                    self.assertEqual(v.reviewer_cli("codex"), expected)
        finally:
            p.write_text(text)

    def test_confidential_refused(self):
        Path(os.environ["CLAUDE_REPOS_JSON"]).write_text(json.dumps({"repos":{},"scopes":{"vault":{"repos":["*"],"confidential":True}}}))
        r=self.launch("--preflight"); self.assertEqual(r.returncode,2); self.assertIn("vendor fence",r.stderr)
        # the real call after a pre-flight that passed: a race, a wait the next pre-flight settles
        r=self.launch(); self.assertEqual(r.returncode,4,r.stderr); self.assertIn("refused for now: the vendor fence changed",r.stderr)
        self.assertFalse(self.audit.exists())

    def test_origin_refused(self):
        r=self.launch("--preflight","--origin","confidential:marker"); self.assertEqual(r.returncode,2)
        r=self.launch("--origin","confidential:marker"); self.assertEqual(r.returncode,4,r.stderr)
        self.assertFalse(self.audit.exists())

    def test_coin_fence_preflight_falls_back_without_a_vendor_turn(self):
        registry = Path(os.environ["CLAUDE_REPOS_JSON"])
        public = Path(os.environ["REGATTA_CONFIG"]) / "wharf-runs/public-repos"
        for reason in ("rotation", "confidential", "public", "origin"):
            with self.subTest(reason=reason):
                scope = {"repos": ["*"]}
                if reason == "rotation":
                    scope["rotation"] = False
                if reason == "confidential":
                    scope["confidential"] = True
                registry.write_text(json.dumps({"repos": {}, "scopes": {"open": scope}}))
                public.write_text("repo\n" if reason == "public" else "")
                flags = ["--origin", "confidential:marker"] if reason == "origin" else []
                try:
                    typed = self.launch("--preflight", *flags)
                    self.assertEqual(typed.returncode, 2, typed.stdout + typed.stderr)
                    coin = self.launch("--preflight", "--coin", *flags)
                    self.assertEqual(coin.returncode, 3, coin.stdout + coin.stderr)
                    self.assertIn("vendor pre-flight fallback:", coin.stderr)
                    self.assertFalse(self.audit.exists())
                    self.assertNotIn("started", json.loads(self.record.read_text()))
                    self.assertFalse(Path(os.environ["CLAUDE_AUDIT"]).exists())
                finally:
                    public.unlink()

    def test_origin_review_is_scoped_to_the_current_topic(self):
        for filename in ("2026-11-01-old.review", "old.review", "nested/build.review"):
            p = self.brief.parent / filename
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("another task's review\n")
        v.git(self.wt, "add", "docs")
        v.git(self.wt, "commit", "-qm", "unrelated reviews")
        v.fence(self.wt, "codex")
        for filename in ("2026-11-04-build.review", "build.review"):
            with self.subTest(filename=filename):
                p = self.brief.parent / filename
                p.write_text("this topic's origin marker\n")
                v.git(self.wt, "add", str(p))
                with self.assertRaisesRegex(v.Refused, "origin marker"):
                    v.fence(self.wt, "codex")
                v.git(self.wt, "reset", "--", str(p))
                p.unlink()
        self.assertFalse(self.audit.exists())

    def test_size_and_verdict_fences(self):
        with self.assertRaisesRegex(v.Refused,"64 KB"):
            v.turn("codex",self.wt,"x"*65537)
        with self.assertRaisesRegex(v.Refused,"credential"):
            v.fence(self.wt,"codex",text="-----BEGIN " + "PRIVATE KEY-----")
        self.assertFalse(self.audit.exists())

    def test_five_arms_and_zero_weights(self):
        c=v.buildercoin
        self.assertEqual([c.coin_of(n) for n in range(7)],[0,1,1,2,2,3,4])
        self.assertEqual(c.arm_of("gpt-mid:4:2099-01-01:0")["effort"],"high")
        self.assertEqual(c.arm_of("gpt-big:3:2099-01-01:0")["effort"],"xhigh")
        self.assertEqual(c.need_of("gpt-mid:4:2099-01-01:0"),"codex")
        for n in range(40):
            self.assertIn(c.coin_of(n%2,(0,0,0,1,1)),(3,4))
        with patch.object(c,"read_odds",return_value=((0,0,0,1,1),"test")):
            for prefix in ("Tier:", "- Tier:", "* Tier:", "- **Tier:**", "**Tier:**"):
                with self.subTest(prefix=prefix):
                    self.assertEqual(c.rotates(prefix + " sr-worker (Opus high)"),"gpt-big")
                    self.assertEqual(c.rotates(prefix + " worker"),"gpt-mid")
                    self.assertIsNone(c.rotates(prefix + " principal-worker"))
            # a tier word decides alone; model words only for a line with none
            for line, want in (("Tier: sr-architect (Opus, high)", None), ("Tier: architect, Opus 5.5 high", None),
                               ("Tier: main (Opus)", None), ("Tier: worker, not Opus", "gpt-mid"),
                               ("Tier: Opus 5.5 high", "gpt-big"), ("Tier: Sonnet 5.5 high", "gpt-mid")):
                with self.subTest(line=line):
                    self.assertEqual(c.gpt_class(line), want)
        with patch.object(c,"read_odds",return_value=((1,0,0,1,1),"test")):
            self.assertIsNone(c.rotates("Tier: sr-worker"))

    def test_preflight_fallback(self):
        Path(os.environ["REGATTA_CONFIG"],"wharf-runs/only").write_text("agy\n")
        try:
            r=self.launch("--preflight"); self.assertEqual(r.returncode,3)
            self.assertFalse(self.audit.exists())
        finally:
            Path(os.environ["REGATTA_CONFIG"],"wharf-runs/only").write_text("codex\n")

    def test_builder_check_omits_only_landing_commands(self):
        (self.wt / "AGENTS.md").write_text("- check: `claude plugin validate --strict . && bash okay.sh && python3 modules/helloworld/bin/helloworld check . --ref HEAD`\n")
        (self.wt / "okay.sh").write_text("exit 0\n")
        r=cmd(B / "check",self.wt,"--builder","--full","--out",self.root / "check",
              env=dict(os.environ,CHECK_SLOT_DIR=str(self.root / "slots"),CHECK_HOST="laptop",CHECK_PASS_TTL="0"))
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertIn("DONE 1/1",r.stdout)
        self.assertEqual(r.stdout.count("vendor builder: landing runs this command"),2)
        self.assertFalse(Path(os.environ["CLAUDE_AUDIT"]).exists())

    def test_unattended_builder_check_reads_main_contract(self):
        (self.repo / "AGENTS.md").write_text("- check: `bash required.sh`\n")
        (self.repo / "required.sh").write_text("echo required-suite-ran\nexit 1\n")
        self.git("add", "."); self.git("commit", "-qm", "require suite")
        self.git("push", "-q", "origin", "main")
        v.git(self.wt, "fetch", "origin")
        v.git(self.wt, "merge", "--no-edit", "origin/main")
        (self.wt / "AGENTS.md").write_text("- check: `true`\n")
        r = cmd(B / "check", self.wt, "--builder", "--full", "--out", self.root / "check",
                env=dict(os.environ, CLAUDE_UNATTENDED="vendor-build", REGATTA_UNATTENDED="vendor-build",
                         CHECK_SLOT_DIR=str(self.root / "slots"), CHECK_HOST="laptop", CHECK_PASS_TTL="0"))
        self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("the check line from origin/main", r.stdout)
        self.assertIn("required-suite-ran", "".join(p.read_text() for p in (self.root / "check").glob("*.log")))

    def test_trim_arm_and_fallback_stream(self):
        sys.path.insert(0,str(B.parents[1] / "plumb/lib"))
        import trimlib
        self.assertEqual(trimlib.arm_of("gpt-6.1-sol","xhigh"),"gpt-6.1-sol:xhigh")
        row={"unit":"landing","arm":"opus:high","arm_source":"fallback"}
        self.assertEqual(trimlib.stream([row],"builder"),[])

    def test_dispatch_codex_fire(self):
        self.assertEqual(cmd("git", "-C", self.wt, "push", "-q", "origin", "HEAD:refs/heads/claude/laptop/build").returncode,0)
        lc=self.root / "launchctl"
        lc.write_text('#!/bin/sh\nexit 0\n'); lc.chmod(0o755)
        log=self.root / "dispatch.log"
        env=dict(os.environ, DISPATCH_LABEL="org.example.claude.dispatch.repo.build.202611040000",
                 DISPATCH_LOG=str(log), DISPATCH_LAUNCHCTL=str(lc), DISPATCH_DEFAULT_ON="",
                 HEADROOM_SAMPLE="60 0 0", DISPATCH_HOST="laptop")
        r=cmd(B / "dispatch","claude/laptop/build","--repo",self.repo,"--harness","codex",env=env,timeout=90)
        text=log.read_text() if log.exists() else r.stdout+r.stderr
        self.assertEqual(r.returncode,0,text)
        self.assertIn("vendor end: clean",text)
        self.assertFalse(Path(os.environ["CLAUDE_AUDIT"]).exists())

    def rotation_on(self, tier):
        cfg=Path(os.environ["REGATTA_CONFIG"])/"wharf-runs"
        (cfg/"builder-rotation").write_text("until 2099-01-01\n")
        self.addCleanup(lambda: (cfg/"builder-rotation").unlink(missing_ok=True))
        self.brief.write_text("Tier: %s\nBuild it.\n" % tier)
        self.assertEqual(cmd("git","-C",self.wt,"commit","-qam","tier").returncode,0)

    def test_dispatch_keeps_a_drawn_gpt_word_on_a_row_without_the_odds(self):
        # a builder row fires what it never drew: default odds here must not send a sized build back to Claude
        self.rotation_on("sr-worker")
        self.assertIsNone(v.buildercoin.rotates("Tier: sr-worker\n"))
        env=self.fire_env(DISPATCH_ARM="gpt-big:3:2099-01-01:0",CLEAN_REVIEWS="1")
        r=cmd(B/"dispatch","claude/laptop/build","--repo",self.repo,env=env,timeout=90)
        text=self.log.read_text() if self.log.exists() else r.stdout+r.stderr
        self.assertIn("vendor end: clean",text); self.assertNotIn("dropped",text)
        self.assertFalse(Path(os.environ["CLAUDE_AUDIT"]).exists())

    def test_dispatch_reads_a_crashed_preflight_as_a_wait(self):
        # exit 1 is any uncaught error (the Traps): never a final refusal, so a coin arm keeps its road
        site=self.root/"site"; site.mkdir()
        (site/"sitecustomize.py").write_text("import os, sys\n"
            "if sys.argv[0].endswith('run-vendor') and '--preflight' in sys.argv:\n"
            "    sys.stderr.write('Traceback: a crash\\n'); sys.stderr.flush(); os._exit(1)\n")
        self.rotation_on("worker")
        env=self.fire_env(DISPATCH_ARM="gpt-mid:4:2099-01-01:0",PYTHONPATH=str(site))
        r=cmd(B/"dispatch","claude/laptop/build","--repo",self.repo,env=env,timeout=90)
        text=self.log.read_text() if self.log.exists() else r.stdout+r.stderr
        self.assertEqual(r.returncode,1,text)
        self.assertIn("could not tell (exit 1)",text); self.assertIn("the next step waits for a run to end",text)
        self.assertFalse(self.audit.exists()); self.assertFalse(Path(os.environ["CLAUDE_AUDIT"]).exists())

    def test_a_catalog_of_the_wrong_shape_is_a_fallback(self):
        cache=Path(os.environ["CODEX_HOME"])/"models_cache.json"
        cache.write_text("[]"); self.addCleanup(lambda: cache.unlink(missing_ok=True))
        r=self.launch("--preflight","--coin"); self.assertEqual(r.returncode,3,r.stdout+r.stderr)

    def test_the_fire_time_principal_refusal_is_for_good(self):
        self.assertIn('"FAILED: refused for good, principal tiers run Claude; no vendor build"',(B/"dispatch").read_text())

    def test_vendor_queue_fallback_fields(self):
        q=importlib.machinery.SourceFileLoader("vendor_fixture_queue",str(B / "dispatch-queue")).load_module()
        e={"env":{"DISPATCH_ARM":"gpt-mid:4:2099-01-01:0"},"needs":["codex","mac"],"arm_need":"codex",
           "args":["--needs","codex,mac","--harness","codex"]}
        f=q.vendor_fallback_fields(e)
        self.assertEqual(f["env"]["DISPATCH_ARM"],"opus-high:4:2099-01-01:0")
        self.assertEqual(f["needs"],["mac"])
        self.assertEqual(f["args"],["--needs","mac"])
        self.assertIsNone(q.bad_args(dict(e,**f)))
        self.assertEqual(f["state"],"queued")
        # A typed vendor need (codex or agy) goes too: only a builder row has it, and that row has no Claude login.
        e["arm_need"] = ""
        f = q.vendor_fallback_fields(e)
        self.assertEqual(f["needs"], ["mac"])
        self.assertEqual(f["args"], ["--needs", "mac"])
        self.assertIsNone(q.bad_args(dict(e, **f)))
        e_agy = {"env": {}, "needs": ["agy", "mac"], "arm_need": "", "args": ["--needs", "agy,mac", "--harness", "agy"]}
        f_agy = q.vendor_fallback_fields(e_agy)
        self.assertEqual(f_agy["needs"], ["mac"])
        self.assertEqual(f_agy["args"], ["--needs", "mac", "--model", "claude-opus-5-5", "--effort", "high"])
        self.assertIsNone(q.bad_args(dict(e_agy, **f_agy)))
        with patch.object(q, "berth_candidates", return_value=(["laptop"], {})), \
                patch.object(q, "builtin_met", return_value=False):
            self.assertIsNone(q.eligibility(dict(e, **f), "laptop", {"laptop": {"mac"}}))

    def fire_env(self, **extra):
        self.assertEqual(cmd("git", "-C", self.wt, "push", "-q", "origin", "HEAD:refs/heads/claude/laptop/build").returncode, 0)
        lc = self.root / "launchctl"
        lc.write_text('#!/bin/sh\nexit 0\n'); lc.chmod(0o755)
        self.log = self.root / "dispatch.log"
        base = dict(os.environ)
        base.update(DISPATCH_LABEL="org.example.claude.dispatch.repo.build.202611040000",
                    DISPATCH_LOG=str(self.log), DISPATCH_LAUNCHCTL=str(lc), DISPATCH_DEFAULT_ON="",
                    HEADROOM_SAMPLE="60 0 0", DISPATCH_HOST="laptop")
        base.update(extra)
        return base

    def test_dispatch_typed_refusal_is_one_failed_line(self):
        # harness warns on stderr (no wharf-runs/public-repos here) before the fence's verdict: the FAILED
        # line helm reads alone must be the verdict, "refused for good", not the warning
        Path(os.environ["CLAUDE_REPOS_JSON"]).write_text(json.dumps({"repos": {}, "scopes": {"open": {"repos": ["*"], "rotation": False}}}))
        env = self.fire_env()
        r = cmd(B / "dispatch", "claude/laptop/build", "--repo", self.repo, "--harness", "codex", env=env, timeout=90)
        text = self.log.read_text() if self.log.exists() else r.stdout + r.stderr
        self.assertEqual(r.returncode, 2, text)
        failed = [l for l in text.splitlines() if l.startswith("FAILED")]
        self.assertEqual(len(failed), 1, text)
        self.assertTrue(failed[0].startswith("FAILED: run_vendor: refused for good: "), text)
        self.assertIn("does not rotate", failed[0])
        self.assertFalse(self.audit.exists())

    def test_dispatch_retry_carries_the_runs_context(self):
        # a skippered vendor build that fails before its first commit: its Claude retry keeps the skipper and
        # the note, and drops only the harness and its own codex need
        qhome = self.root / "queue.git"
        self.assertEqual(cmd("git", "init", "-q", "--bare", qhome).returncode, 0)
        queue_repo = Path(os.environ["REGATTA_CONFIG"]) / "wharf-runs/queue-repo"
        queue_repo.write_text(str(qhome) + "\n")
        env = self.fire_env(FAIL_BEFORE_COMMIT="1", DISPATCH_SKIPPER="skipper-fixture")
        try:
            r = cmd(B / "dispatch", "claude/laptop/build", "--repo", self.repo, "--harness", "codex",
                    "--note", "fixture note", env=env, timeout=120)
            text = self.log.read_text() if self.log.exists() else r.stdout + r.stderr
            # the put claimed it here and wrote its own job (the stub launchctl never starts it): fire that job
            import plistlib
            la = Path(os.environ["HOME"]) / "Library/LaunchAgents"
            jobs = [j for j in sorted(la.glob("*.plist")) if "--from-queue" in plistlib.loads(j.read_bytes())["ProgramArguments"]]
            self.assertTrue(jobs, text)
            job = plistlib.loads(jobs[-1].read_bytes())
            jenv = dict(env); jenv.update(job.get("EnvironmentVariables") or {})
            jenv.update(DISPATCH_LAUNCHCTL=env["DISPATCH_LAUNCHCTL"])
            # the job names the dispatch its writer resolves (the primary checkout's); this tree's is the one tested
            argv = [str(B / "dispatch") if a.endswith("/bin/dispatch") else a for a in job["ProgramArguments"]]
            r = cmd(*argv, env=jenv, timeout=120)
            jlog = Path(jenv.get("DISPATCH_LOG") or job.get("StandardOutPath") or self.log)
            text = r.stdout + r.stderr + (jlog.read_text() if jlog.exists() else "")
            for j in jobs:
                j.unlink(missing_ok=True)
            ls = cmd("git", "--git-dir", qhome, "ls-tree", "-r", "--name-only", "refs/regatta/queue")
            entries = []
            for name in ls.stdout.split():
                if name.startswith("queue/"):
                    e = json.loads(cmd("git", "--git-dir", qhome, "show", "refs/regatta/queue:" + name).stdout)
                    if e.get("branch") == "claude/laptop/build" and e.get("state") in ("queued", "claimed"):
                        entries.append(e)
            self.assertEqual(len(entries), 1, text + "\n" + ls.stdout + ls.stderr)
            e = entries[0]
            self.assertEqual(e["env"].get("DISPATCH_SKIPPER"), "skipper-fixture", json.dumps(e))
            self.assertNotIn("--harness", e["args"], json.dumps(e))
            self.assertIn("claude-opus-5-5", " ".join(e["args"]), json.dumps(e))
            self.assertIn("fixture note", " ".join(e["args"]), json.dumps(e))
            self.assertNotIn("codex", e.get("needs") or [], json.dumps(e))
            self.assertFalse(Path(os.environ["CLAUDE_AUDIT"]).exists())
        finally:
            queue_repo.unlink()

    def queued_entries(self, qhome):
        ls = cmd("git", "--git-dir", qhome, "ls-tree", "-r", "--name-only", "refs/regatta/queue")
        out = []
        for name in ls.stdout.split():
            if name.startswith("queue/"):
                e = json.loads(cmd("git", "--git-dir", qhome, "show", "refs/regatta/queue:" + name).stdout)
                if e.get("branch") == "claude/laptop/build":
                    out.append(e)
        return out

    def test_dispatch_real_call_wait_hands_the_entry_back(self):
        # the pre-flight passes; a session takes the worktree before the real call's lock: the entry is
        # handed back queued, never ended and removed by the sweep
        import plistlib, threading
        qhome = self.root / "queue.git"
        self.assertEqual(cmd("git", "init", "-q", "--bare", qhome).returncode, 0)
        queue_repo = Path(os.environ["REGATTA_CONFIG"]) / "wharf-runs/queue-repo"
        queue_repo.write_text(str(qhome) + "\n")
        gate = self.root / "preflight"
        env = self.fire_env()
        try:
            r = cmd(B / "dispatch", "claude/laptop/build", "--repo", self.repo, "--harness", "codex", env=env, timeout=120)
            la = Path(os.environ["HOME"]) / "Library/LaunchAgents"
            jobs = [j for j in sorted(la.glob("*.plist")) if "--from-queue" in plistlib.loads(j.read_bytes())["ProgramArguments"]]
            self.assertTrue(jobs, r.stdout + r.stderr)
            job = plistlib.loads(jobs[-1].read_bytes())
            jenv = dict(env); jenv.update(job.get("EnvironmentVariables") or {})
            jenv.update(DISPATCH_LAUNCHCTL=env["DISPATCH_LAUNCHCTL"], PREFLIGHT_GATE=str(gate))
            argv = [str(B / "dispatch") if a.endswith("/bin/dispatch") else a for a in job["ProgramArguments"]]
            gd = Path(v.git(self.wt, "rev-parse", "--absolute-git-dir")) / "claude"

            def take():
                deadline = time.monotonic() + 90
                while not gate.with_suffix(".ready").exists() and time.monotonic() < deadline:
                    time.sleep(.05)
                v.common.write_owner(gd, "other-session", "claude/laptop/build")
                gate.with_suffix(".release").touch()
            t = threading.Thread(target=take); t.start()
            r = cmd(*argv, env=jenv, timeout=120)
            t.join()
            jlog = Path(jenv.get("DISPATCH_LOG") or self.log)
            text = r.stdout + r.stderr + (jlog.read_text() if jlog.exists() else "")
            self.assertIn("queued again: vendor build waits: run_vendor refused this worktree for now", text)
            self.assertNotIn("FAILED", text)
            entries = self.queued_entries(qhome)
            self.assertEqual([e["state"] for e in entries], ["queued"], text)
            self.assertFalse(self.audit.exists(), "no vendor turn past the refusal")
        finally:
            queue_repo.unlink()
            for j in (Path(os.environ["HOME"]) / "Library/LaunchAgents").glob("*.plist"):
                j.unlink(missing_ok=True)

    def test_codex_parse_refusal_removes_a_fired_jobs_plist(self):
        env = self.fire_env()
        la = Path(os.environ["HOME"]) / "Library/LaunchAgents"
        la.mkdir(parents=True, exist_ok=True)
        plist = la / (env["DISPATCH_LABEL"] + ".plist")
        plist.write_text("<plist/>\n")
        r = cmd(B / "dispatch", "claude/laptop/build", "--repo", self.repo, "--harness", "codex",
                "--account", "acct-x", env=env, timeout=60)
        self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
        self.assertIn("codex uses the builder user login", r.stderr)
        self.assertFalse(plist.exists(), "a fired job its own arguments refuse removes its plist")

    def test_entry_of_record_rebuilds_a_typed_vendor_run(self):
        q = importlib.machinery.SourceFileLoader("vendor_fixture_queue_rec", str(B / "dispatch-queue")).load_module()
        st = {"repo": str(self.repo), "branch": "claude/laptop/build", "topic": "build", "mode": "vendor",
              "cli": "codex", "agent": "codex", "model": "gpt-6.1-sol", "effort": "xhigh", "task_mode": "yolo"}
        e = q.entry_of_record(st, "laptop", 0)
        self.assertEqual(e["needs"], ["codex"])
        self.assertEqual(e.get("arm_need"), "codex")
        self.assertIn("--harness", e["args"]); self.assertEqual(e["args"][e["args"].index("--harness") + 1], "codex")
        self.assertNotIn("DISPATCH_MODE", e["env"], "a vendor build takes no landing mode")
        self.assertIsNone(q.bad_args(e))
        agy_rec = q.entry_of_record(dict(st, cli="agy", agent="antigravity", model="gemini-4-argon-high"), "laptop", 0)
        self.assertEqual(agy_rec["needs"], ["agy"])
        self.assertEqual(agy_rec.get("arm_need"), "agy")
        self.assertIn("--harness", agy_rec["args"]); self.assertEqual(agy_rec["args"][agy_rec["args"].index("--harness") + 1], "agy")
        self.assertNotIn("DISPATCH_MODE", agy_rec["env"])
        self.assertIsNone(q.bad_args(agy_rec))
        claude = q.entry_of_record(dict(st, mode="headless", cli="", agent="claude", model="claude-opus-5-5"), "laptop", 0)
        self.assertEqual(claude["needs"], [])

    def test_started_vendor_retry_is_never_redrawn(self):
        q=importlib.machinery.SourceFileLoader('vendor_retry_queue',str(B/'dispatch-queue')).load_module()
        for arm in ('argon-high:2:2099-01-01:0','gpt-mid:4:2099-01-01:0'):
            need=v.buildercoin.need_of(arm)
            old={'id':'old','state':'ended','session':'started-session','started':100,'branch':'claude/laptop/build',
                 'repo':'repo','env':{'DISPATCH_ARM':arm}}
            new=dict(old,id='new',state='queued',session='',started=None,put_at=1,queued_at=1,
                     needs=[need],arm_need=need,by='')
            entries={'key':old}
            q.apply_op(entries,{'op':'put','key':'key','entry':new})
            self.assertTrue(entries['key']['vendor_started'])
            self.assertIsNone(q.redraw_op('fleet:key','key',entries['key'],10**9))
            replay=q.redraw_op('fleet:key','key',new,10**9)
            self.assertIsNotNone(replay)
            self.assertFalse(q.apply_op(entries,replay)[0],'an outbox replay cannot redraw a started retry')
            q.apply_op(entries,{'op':'put','key':'key','entry':dict(new,id='another-retry')})
            self.assertTrue(entries['key']['vendor_started'],'a repeated stall retry keeps the marker')
            # The old run's own next step gets a fresh chance at the vendor.
            entries={'key':old}
            q.apply_op(entries,{'op':'put','key':'key','entry':dict(new,by='started-session')})
            self.assertFalse(entries['key'].get('vendor_started'))

    def test_dispatch_reserves_slot_during_launcher_preflight(self):
        v.git(self.wt, "push", "-q", "origin", "HEAD:refs/heads/claude/laptop/build")
        # A different topic can only be stopped by the shared host cap.
        v.git(self.wt, "branch", "claude/laptop/other")
        v.git(self.wt, "push", "-q", "origin", "claude/laptop/other")
        lc = self.root / "launchctl"
        lc.write_text('#!/bin/sh\nexit 0\n'); lc.chmod(0o755)
        gate = self.root / "preflight"
        log = self.root / "dispatch.log"
        env = dict(os.environ, DISPATCH_LABEL="org.example.claude.dispatch.repo.build.202611040000",
                   DISPATCH_LOG=str(log), DISPATCH_LAUNCHCTL=str(lc), DISPATCH_DEFAULT_ON="",
                   DISPATCH_MAX_RUNS="1", HEADROOM_SAMPLE="60 0 0", PREFLIGHT_GATE=str(gate))
        first = subprocess.Popen([str(B / "dispatch"), "claude/laptop/build", "--repo", str(self.repo),
                                  "--harness", "codex"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 60
            while not gate.with_suffix(".ready").exists():
                self.assertIsNone(first.poll(), log.read_text() if log.exists() else "no log")
                self.assertLess(time.monotonic(), deadline, "launcher did not reach second preflight")
                time.sleep(.05)
            r = cmd(sys.executable, B / "dispatch-rc", "live", "--no-reap", self.repo, "other", env=env)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(r.stdout.strip(), "1", r.stderr)
            # Fire the other topic with its own brief on its own branch.
            other = self.repo / ".claude/worktrees/other"
            self.git("worktree", "add", other, "claude/laptop/other")
            p = other / "docs/handoff/2026-11-04-other.md"
            p.write_text("Build the other task.\n")
            v.git(other, "add", str(p)); v.git(other, "commit", "-qm", "other seed")
            v.git(other, "push", "-q", "origin", "claude/laptop/other")
            other_log = self.root / "other.log"
            r = cmd(B / "dispatch", "claude/laptop/other", "--repo", self.repo, "--harness", "codex",
                    env=dict(env, DISPATCH_LABEL="org.example.claude.dispatch.repo.other.202611040000",
                             DISPATCH_LOG=str(other_log)), timeout=45)
            self.assertNotEqual(r.returncode, 0, other_log.read_text())
            self.assertIn("vendor build waits", other_log.read_text())
            self.assertFalse(self.audit.exists(), "neither vendor may start while preflight is held")
        finally:
            gate.with_suffix(".release").touch()
            try:
                first.wait(timeout=60)
            except subprocess.TimeoutExpired:
                first.kill(); first.wait()
        self.assertEqual(first.returncode, 0, log.read_text())


AGY_STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys, time
a=sys.argv[1:]
if a==['--help']:
    print('--sandbox --dangerously-skip-permissions --print-timeout'); sys.exit(0)
if len(a)==3 and a[0]=='--log-file' and a[2]=='models':
    pathlib.Path(a[1]).write_text('OAuth: authenticated successfully as '+os.environ.get('NATIVE_EMAIL','test@example.invalid')+'\n')
    print('gemini-4-argon-high' if not os.environ.get('MISSING_MODEL') else 'gemini-other'); sys.exit(0)
flags={}; i=0
while i<len(a):
    f=a[i]; assert f not in flags, a
    if f in ('--sandbox','--dangerously-skip-permissions','-p='): flags[f]=True; i+=1
    elif f in ('--input-format','--output-format','--model','--effort','--conversation','--log-file','--print-timeout','--add-dir'):
        flags[f]=a[i+1]; i+=2
    else: raise AssertionError('unknown real agy flag '+f)
assert flags['--input-format']==flags['--output-format']=='stream-json'
assert flags['--model']=='gemini-4-argon-high' and flags['--effort'] in ('high','xhigh')
assert flags['--sandbox'] and flags['--dangerously-skip-permissions'] and flags['--print-timeout']=='0'
assert a[-1]=='-p='
assert not any(k.startswith('DISPATCH_') and k not in ('DISPATCH_DEPTH','DISPATCH_MAX_DEPTH') for k in os.environ)
assert os.environ.get('DISPATCH_DEPTH','').isdigit() and int(os.environ['DISPATCH_DEPTH'])>=1
assert not os.environ.get('CLAUDE_CODE_SESSION_ID') and not os.environ.get('CLAUDE_CONFIG_DIR')
assert os.environ['PLAN_HARNESS']=='agy' and os.environ['CLAUDE_UNATTENDED']=='vendor-build'
home=pathlib.Path(os.environ['HOME']); gemini=pathlib.Path(os.environ['GEMINI_CLI_HOME'])
assert gemini==home/'.gemini'
assert set(json.loads((gemini/'config/hooks.json').read_text()))=={'regatta'}
assert (home/'Library/Keychains/login.keychain-db').is_file()
pathlib.Path(flags['--log-file']).write_text('OAuth: authenticated successfully as '+os.environ.get('TURN_EMAIL','test@example.invalid')+'\n')
conv=flags.get('--conversation') or 'conv-'+str(time.time_ns())
state=gemini/'antigravity-cli/conversations'; state.mkdir(exist_ok=True)
if '--conversation' in flags: assert (state/conv).is_file(), 'lost builder conversation'
(state/conv).touch()
def out(x): print(json.dumps(x),flush=True)
if os.environ.get('NO_INIT'): time.sleep(30); sys.exit(0)
out({'event':'init','conversation_id':conv})
line=sys.stdin.readline()
if not line: sys.exit(1)
assert len(line.encode())<=65536, 'serialized message exceeded the byte guard'
event=json.loads(line)
assert event['event']=='user' and event['message']['role']=='user'
prompt=event['message']['content']; assert len(prompt.encode())<=65536
review='name: reviewer' in prompt or 'name: code-reviewer' in prompt or 'You reformat a review' in prompt
mode='review' if review else ('resume' if '--conversation' in flags else 'build')
# a reviewer gets no git dir to write; the builder's commits in a linked worktree need the common dir
assert ('--add-dir' not in flags) if review else pathlib.Path(flags['--add-dir']).is_dir(), (mode, flags)
wt=pathlib.Path(os.getcwd()); f=wt/'f.py'
with open(os.environ['AUDIT'],'a') as audit: audit.write(json.dumps({'mode':mode,'prompt':prompt,'conversation':conv,'home':str(home)})+'\n')
if review and os.environ.get('REVIEW_WRITES'): f.write_text('reviewer wrote\n')
if mode=='build' and os.environ.get('PLANT_HOOK'):
    gd=subprocess.run(['git','rev-parse','--path-format=absolute','--git-common-dir'],capture_output=True,text=True).stdout.strip()
    hook=pathlib.Path(gd)/'hooks/pre-push'; hook.parent.mkdir(exist_ok=True); hook.write_text('#!/bin/sh\nexit 0\n')
if review:
    if 'name: code-reviewer' in prompt: text='[]'
    elif 'You reformat a review' in prompt: text='NO_FINDINGS'
    elif 'fresh verifier' in prompt or f.read_text().strip()=='bad' or os.environ.get('ALWAYS_FIND'):
        text='f.py:1 — [S2] bad result\nverdict: WRONG\nevidence: bad input produces bad output\nfix: write fixed'
    else: text='NO_FINDINGS'
else:
    f.write_text('bad\n' if mode=='build' else 'fixed\n')
    subprocess.run(['git','add','f.py'],check=True)
    subprocess.run(['git','commit','--allow-empty','-qm','fixture: '+mode],check=True)
    text='built' if mode=='build' else 'fixed'
if os.environ.get('HOLD_STDOUT'):
    # a tool outside agy's process group keeps stdout open after the turn (the landing review's case)
    subprocess.Popen(['sleep','20'],start_new_session=True,stdin=subprocess.DEVNULL)
if os.environ.get('FENCE_AFTER_BUILD') and mode=='build':
    pathlib.Path(os.environ['CLAUDE_REPOS_JSON']).write_text(json.dumps({'repos':{},'scopes':{'open':{'repos':['*'],'rotation':False}}}))
out({'event':'result','result':{'status':'ERROR' if os.environ.get('FAIL_EXEC') else 'SUCCESS',
     'response':text,'usage':{'input_tokens':10,'output_tokens':5},'num_turns':1}})
'''


class AntigravityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        VendorTests.setUpClass()

    def setUp(self):
        VendorTests.setUp(self)
        self.cli = self.root / 'agy'
        self.cli.write_text(AGY_STUB); self.cli.chmod(0o755)
        account = self.root / 'account'
        account.write_text('#!/usr/bin/env python3\nimport json,sys\n'
                          'a=sys.argv[1:]; assert a[:3]==["pick","--provider","antigravity"]\n'
                          'assert a[3]=="--repo" and a[5:]==["--json"]\n'
                          'print(json.dumps({"account":"agy-x","provider":"antigravity","primary":False,"env":{},"reason":"fixture"}))\n')
        account.chmod(0o755)
        security = self.root / 'security'
        security.write_text('#!/usr/bin/python3\nimport os,pathlib,shlex,sys\n'
                            'a=sys.argv[1:]\n'
                            'if a==["-i"]: a=shlex.split(sys.stdin.read())\n'
                            'assert a[0] in ("find-generic-password","unlock-keychain","create-keychain","set-keychain-settings","add-generic-password","delete-keychain"),a\n'
                            'if a[0]=="find-generic-password": print("fixture")\n'
                            'if a[0]=="create-keychain": pathlib.Path(a[-1]).touch()\n'
                            'if a[0]=="delete-keychain": pathlib.Path(a[-1]).unlink()\n')
        security.chmod(0o755)
        self.security = security
        self.f = v.codex._fence(); self.f.SECURITY = str(security)
        kc = Path.home() / self.f.BUILDER_KC
        kc.parent.mkdir(parents=True, exist_ok=True); kc.touch()
        pw = Path.home() / self.f.BUILDER_PW; pw.write_text('a'*32)
        cfg = Path(os.environ['REGATTA_CONFIG'])
        (cfg / 'wharf-runs/only').write_text('agy,codex\n')
        (cfg / 'wharf-runs/features').write_text('laptop:agy\n')
        (cfg / 'wharf-runs/agy-domain').write_text('example.invalid\n')
        gemini = self.root / 'gemini'
        (gemini / 'config').mkdir(parents=True)
        vh=importlib.machinery.SourceFileLoader('agy_fixture_vh',str(v.common.tool('vendor-hooks'))).load_module()
        (gemini / 'config/hooks.json').write_text(json.dumps(vh.plan_ag({})[0]))
        self.env = patch.dict(os.environ, HARNESS_AGY=str(self.cli), HARNESS_ACCOUNT=str(account), GEMINI_CLI_HOME=str(gemini))
        self.env.start(); self.addCleanup(self.env.stop)
        self.fence_patch = patch.object(v.codex, '_fence', return_value=self.f)
        self.fence_patch.start(); self.addCleanup(self.fence_patch.stop)
        self.record.write_text(json.dumps({'session':'agy-'+self._testMethodName,'repo':str(self.repo),'topic':'build',
                                          'arm':v.buildercoin.arm_of('argon-high:2:2099-01-01:0')}))

    def launch(self, *flags, **env):
        launcher=importlib.machinery.SourceFileLoader('agy_fixture_launcher',str(B/'run-vendor')).load_module()
        out, err = io.StringIO(), io.StringIO()
        args=['run-vendor',str(self.wt),'--cli','antigravity','--record',str(self.record),'--brief',str(self.brief),*flags]
        old_handler = __import__('signal').getsignal(__import__('signal').SIGTERM)
        try:
            with patch.dict(os.environ, env), patch.object(sys,'argv',args), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                rc=launcher.main()
        finally:
            __import__('signal').signal(__import__('signal').SIGTERM,old_handler)
        return subprocess.CompletedProcess(args,rc,out.getvalue(),err.getvalue())

    def test_build_review_fix_clean(self):
        r=self.launch(); self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        state=json.loads(self.record.read_text())
        self.assertEqual((state['agent'],state['cli'],state['outcome'],state['turns'],state['rounds']),
                         ('antigravity','agy','clean',2,2))
        calls=[json.loads(l) for l in self.audit.read_text().splitlines()]
        self.assertEqual([x['mode'] for x in calls],['build','review','review','review','resume','review','review'])
        self.assertEqual(calls[0]['conversation'],calls[4]['conversation'])
        self.assertEqual(calls[0]['home'],calls[4]['home'])
        self.assertEqual(len({x['conversation'] for x in calls if x['mode']=='review'}),5)
        self.assertEqual(state['pid'],os.getpid()); self.assertIsNone(state['turn_pid'])
        self.assertEqual(state['cost']['google'],{'input_tokens':70,'output_tokens':35})
        self.assertEqual(state['cost']['anthropic'],{'input_tokens':0,'output_tokens':0})
        self.assertTrue(all(not Path(x['home']).exists() for x in calls),'per-run keychains cleaned up')
        self.assertEqual(v.git(self.wt,'rev-parse','HEAD'),self.git('rev-parse','refs/remotes/origin/claude/laptop/build'))
        self.assertFalse(Path(os.environ['CLAUDE_AUDIT']).exists())
        rows=[json.loads(l) for l in (Path.home()/'Library/Logs/claude-weekly/builder-rotation.jsonl').read_text().splitlines()]
        row=next(r for r in reversed(rows) if r['session']=='agy-'+self._testMethodName)
        self.assertEqual((row['agent'],row['outcome'],row['cost']),('antigravity','clean',state['cost']))

    test_round_cap = VendorTests.test_round_cap
    test_confidential_refused = VendorTests.test_confidential_refused
    test_origin_refused = VendorTests.test_origin_refused
    test_coin_fence_preflight_falls_back_without_a_vendor_turn = VendorTests.test_coin_fence_preflight_falls_back_without_a_vendor_turn
    test_recent_owner_refuses_a_new_run = VendorTests.test_recent_owner_refuses_a_new_run

    def test_cross_vendor_in_both_directions(self):
        cfg=Path(os.environ['REGATTA_CONFIG'])/'wharf-runs/features'
        cfg.write_text('laptop:agy,codex\n')
        (cfg.parent/'only').write_text('agy\n')
        r=self.launch(); self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        state=json.loads(self.record.read_text())
        self.assertEqual(state['cost']['google']['input_tokens'],20)
        self.assertEqual(state['cost']['openai']['input_tokens'],50)
        self.audit.unlink()
        import vendorreview
        # Codex builder's declared other vendor is agy, also from a fresh conversation.
        self.assertEqual(v.reviewer_cli('codex'),'antigravity')
        report=vendorreview.review(self.wt,'antigravity',self.root/'cross-review')
        self.assertEqual(report['found'],0)
        self.assertEqual(report['cost']['google']['input_tokens'],20)

    def test_preflight_failures_send_no_build(self):
        for env in ({'NATIVE_EMAIL':'acct-b@other.invalid'},{'MISSING_MODEL':'1'}):
            with self.subTest(env=env):
                r=self.launch('--preflight',**env)
                self.assertEqual(r.returncode,3,r.stdout+r.stderr)
                self.assertFalse(self.audit.exists())
        (Path(os.environ['REGATTA_CONFIG'])/'wharf-runs/agy-domain').write_text('other.invalid\n')
        self.assertEqual(self.launch('--preflight').returncode,3)
        self.assertFalse(self.audit.exists())

    def test_open_repo_needs_no_accounts_registry(self):
        # a builder host keeps no lighthouse/accounts.json: the real pick exits 4 with no stdout
        nopick=self.root/'account-none'
        nopick.write_text('#!/bin/sh\necho "account: no registry" >&2\nexit 4\n'); nopick.chmod(0o755)
        r=self.launch('--preflight',HARNESS_ACCOUNT=str(nopick))
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertFalse(self.audit.exists())

    def test_a_tool_holding_stdout_does_not_hang_the_turn(self):
        start=time.monotonic()
        with patch.object(v.agybuild,'RESULT_GRACE',2), patch.dict(os.environ,HOLD_STDOUT='1'):
            result=v.turn('antigravity',self.wt,'name: code-reviewer\nhello',review=True,timeout=40)
        self.assertEqual(result['last_answer'],'[]')
        self.assertLess(time.monotonic()-start,25,'the turn ends at its grace, not at the holder\'s exit')

    def test_reviewer_write_is_held(self):
        r=self.launch(REVIEW_WRITES='1'); self.assertEqual(r.returncode,1,r.stdout+r.stderr)
        state=json.loads(self.record.read_text())
        self.assertEqual(state['outcome'],'held',r.stdout+r.stderr)
        self.assertIn('reviewer changed the worktree',state['end_reason'])
        self.assertFalse(Path(os.environ['CLAUDE_AUDIT']).exists())

    def test_planted_git_hook_is_held_before_the_launcher_pushes(self):
        r=self.launch(PLANT_HOOK='1'); self.assertEqual(r.returncode,1,r.stdout+r.stderr)
        state=json.loads(self.record.read_text())
        self.assertEqual(state['outcome'],'held',r.stdout+r.stderr)
        self.assertIn('config or hooks',state['end_reason'])
        self.assertEqual([json.loads(l)['mode'] for l in self.audit.read_text().splitlines()],['build'])
        pushed=subprocess.run(['git','-C',str(self.wt),'rev-parse','--verify','-q','refs/remotes/origin/claude/laptop/build'],
                              capture_output=True,text=True).stdout.strip()
        self.assertNotEqual(pushed,v.git(self.wt,'rev-parse','HEAD'),'nothing pushed after the held turn')

    def test_unreadable_features_file_waits(self):
        real=v.common.config_read
        def read(key):
            return (None,'fixture: Drive not downloaded') if key=='wharf-runs/features' else real(key)
        with patch.object(v.common,'config_read',side_effect=read):
            r=self.launch('--preflight')
        self.assertEqual(r.returncode,4,r.stdout+r.stderr)
        self.assertFalse(self.audit.exists())

    def test_runtime_failure_belongs_to_antigravity(self):
        r=self.launch(FAIL_EXEC='1'); self.assertEqual(r.returncode,1,r.stdout+r.stderr)
        state=json.loads(self.record.read_text())
        self.assertEqual((state['agent'],state['outcome']),('antigravity','failed'))
        self.assertEqual(state['cost']['google']['input_tokens'],10)
        self.assertFalse(state['retry_claude'])
        self.assertFalse(Path(os.environ['CLAUDE_AUDIT']).exists())

    def test_fence_rechecked_before_review(self):
        r=self.launch(FENCE_AFTER_BUILD='1'); self.assertEqual(r.returncode,1,r.stdout+r.stderr)
        self.assertEqual(json.loads(self.record.read_text())['outcome'],'held')
        self.assertEqual(len(self.audit.read_text().splitlines()),1)

    def test_size_verdict_and_native_identity_before_input(self):
        with self.assertRaisesRegex(v.Refused,'64 KB'):
            v.turn('antigravity',self.wt,'x'*65537)
        with self.assertRaisesRegex(v.Refused,'credential'):
            v.fence(self.wt,'antigravity',text='-----BEGIN '+'PRIVATE KEY-----')
        dot=self.wt/'.gemini/config'; dot.mkdir(parents=True); (dot/'hooks.json').write_text('{}')
        try:
            with self.assertRaisesRegex(v.Held,r'\.gemini/'):
                v.fence(self.wt,'antigravity')
        finally:
            __import__('shutil').rmtree(self.wt/'.gemini')
        with patch.dict(os.environ,TURN_EMAIL='acct-b@other.invalid'):
            with self.assertRaisesRegex(v.Refused,'nothing sent'):
                v.turn('antigravity',self.wt,'hello')
        self.assertFalse(self.audit.exists())

    def test_per_run_guards_are_rechecked_before_each_turn(self):
        with v.vendor_home('antigravity',self.wt) as home:
            (Path(home['GEMINI_CLI_HOME'])/'config/hooks.json').write_text('{}')
            with self.assertRaisesRegex(v.Refused,'per-run guards changed'):
                v.turn('antigravity',self.wt,'hello',home=home)
        self.assertFalse(self.audit.exists())

    def test_unicode_message_stays_below_the_serialized_byte_guard(self):
        result=v.turn('antigravity',self.wt,'name: code-reviewer\n'+'é'*32700,review=True)
        self.assertEqual(result['last_answer'],'[]')

    def test_json_escaping_cannot_bypass_the_byte_guard(self):
        pids=[]
        with self.assertRaisesRegex(v.Refused,'64 KB'):
            v.turn('antigravity',self.wt,'"'*40000,on_pid=pids.append)
        self.assertEqual(pids,[],'guard the encoded stdin message before starting a CLI')
        self.assertFalse(self.audit.exists())

    def test_review_verb_uses_antigravity_without_a_claude_process(self):
        br=importlib.machinery.SourceFileLoader('agy_review_verb',str(B/'build-review')).load_module()
        out=io.StringIO()
        with contextlib.redirect_stdout(out):
            rc=br.main(['review',str(self.wt),'--cli','antigravity','--out',str(self.root/'verb-review')])
        self.assertEqual(rc,0,out.getvalue())
        result=json.loads(out.getvalue())
        self.assertEqual((result['cli'],result['found']),('antigravity',0))
        self.assertEqual(result['cost']['google']['input_tokens'],20)
        self.assertFalse(Path(os.environ['CLAUDE_AUDIT']).exists())

    def test_dispatch_typed_harness_model_and_coin_use_the_vendor_fence(self):
        # Copy the shell entrypoint; every peer is real except the keychain
        # command, patched in its Python child. No live state or network.
        module=self.root/'module'; bins=module/'bin'; bins.mkdir(parents=True)
        (module/'lib').symlink_to(B.parent/'lib',target_is_directory=True)
        for peer in B.iterdir():
            if peer.name not in ('dispatch','run-vendor','__pycache__'):
                (bins/peer.name).symlink_to(peer,target_is_directory=peer.is_dir())
        dispatch=bins/'dispatch'; dispatch.write_text((B/'dispatch').read_text()); dispatch.chmod(0o755)
        wrapper=bins/'run-vendor'
        wrapper.write_text('import os,sys,runpy\nsys.path.insert(0,%r)\nimport vendorlib as v\n'
                           'f=v.codex._fence(); f.SECURITY=%r\nv.codex._fence=lambda:f\n'
                           'original=v.common.vendor_refusal\n'
                           'def refusal(repo,cli):\n'
                           '    open(os.environ["FIRE_FENCE"],"a").write(cli+"\\n")\n'
                           '    return original(repo,cli)\n'
                           'v.common.vendor_refusal=refusal\n'
                           'runpy.run_path(%r,run_name="__main__")\n' % (str(B),str(self.security),str(B/'run-vendor')))
        self.brief.write_text('Tier: worker\nBuild it.\n')
        v.git(self.wt,'commit','-qam','fixture: a coin-eligible brief')
        v.git(self.wt,'push','-q','origin','HEAD:refs/heads/claude/laptop/build')
        lc=self.root/'launchctl'; lc.write_text('#!/bin/sh\nexit 0\n'); lc.chmod(0o755)
        cfg=Path(os.environ['REGATTA_CONFIG'])/'wharf-runs'
        (cfg/'builder-rotation').write_text('until 2099-01-01\n')
        (cfg/'builder-odds').write_text('opus-high=1,sonnet-high=2,argon-high=2,gpt-big=1,gpt-mid=1\n')
        for selection in ('harness','model','coin'):
            with self.subTest(selection=selection):
                # Restore the seed so each fire builds independently.
                fence_log=self.root/(selection+'.fence')
                log=self.root/(selection+'.log')
                env=dict(os.environ,DISPATCH_LOG=str(log),DISPATCH_LAUNCHCTL=str(lc),DISPATCH_DEFAULT_ON='',
                         DISPATCH_LABEL='org.example.claude.dispatch.repo.build.202611040000',FIRE_FENCE=str(fence_log))
                flags=['--harness','agy'] if selection=='harness' else ['--model','gemini-4-argon-high'] if selection=='model' else []
                if selection=='coin': env['DISPATCH_ARM']='argon-high:2:2099-01-01:0'
                r=cmd(dispatch,'claude/laptop/build','--repo',self.repo,*flags,env=env,timeout=90)
                text=log.read_text() if log.exists() else r.stdout+r.stderr
                self.assertEqual(r.returncode,0,text)
                self.assertIn('vendor end: clean',text)
                self.assertEqual(set(fence_log.read_text().splitlines()),{'antigravity'})
                gd=Path(v.git(self.wt,'rev-parse','--absolute-git-dir'))/'claude'
                (gd/'owner.json').unlink(missing_ok=True)
        self.assertFalse(Path(os.environ['CLAUDE_AUDIT']).exists())

    def test_no_init_is_bounded_and_reaps_the_cli(self):
        pids=[]
        with patch.dict(os.environ,NO_INIT='1'):
            with self.assertRaisesRegex(v.Refused,'nothing sent'):
                v.turn('antigravity',self.wt,'hello',timeout=.2,on_pid=pids.append)
        self.assertTrue(pids)
        with self.assertRaises(ProcessLookupError): os.kill(pids[0],0)
        self.assertFalse(self.audit.exists())


unittest.main(verbosity=2)
