"""run_vendor's offline integration cases. Called through test_vendor.sh only."""
import importlib.machinery
import fcntl
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

B, T = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
sys.path.insert(0, str(B))
sys.argv = [sys.argv[0]] + sys.argv[3:]
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
    elif os.environ.get('LEAVE_CONFLICT'):
        sub=wt/'sub'; sub.mkdir(exist_ok=True)
        (sub/'conflict.py').write_text('<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> main\n')
    elif os.environ.get('LEAVE_PROTECTED'):
        p=wt/os.environ['LEAVE_PROTECTED']; p.parent.mkdir(parents=True,exist_ok=True); p.write_text('secret\n')
    elif os.environ.get('COMMIT_PROTECTED'):
        p=wt/os.environ['COMMIT_PROTECTED']; p.parent.mkdir(parents=True,exist_ok=True); p.write_text('secret\n')
        subprocess.run(['git','add','-f',os.environ['COMMIT_PROTECTED']],cwd=wt,check=True)
        subprocess.run(['git','commit','-qm','fixture: committed protected'],cwd=wt,check=True)
    elif os.environ.get('LEAVE_UNCOMMITTED'):
        f.write_text('bad\n' if mode=='build' else 'fixed\n')
        sub=wt/'sub'; sub.mkdir(exist_ok=True); (sub/'added.txt').write_text('added\n')
        (wt/'ignored.tmp').write_text('ignored\n')
        (wt/'notes.md').write_text('Heading\n=======\nBody.\n')
        if os.environ.get('LOCK_GIT'):
            gd=subprocess.run(['git','rev-parse','--absolute-git-dir'],cwd=wt,capture_output=True,text=True,check=True).stdout.strip()
            (pathlib.Path(gd)/'index.lock').write_text('locked\n')
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
    hl=os.environ.get('HANDOVER_LINE')
    text=hl if (hl and hl in prompt) else (os.environ.get('BUILD_ANSWER','built') if mode=='build' else 'fixed')
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


class BuilderHookTests(unittest.TestCase):
    """Real sheep gate writes in a scratch home, then the real builder preflights."""
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="builder-hooks.", dir=T)
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.env = patch.dict(os.environ, HOME=str(self.root), CODEX_HOME=str(self.root / ".codex"),
                              GEMINI_CLI_HOME=str(self.root / ".gemini"),
                              REGATTA_HOME=str(B.parents[2]), SHEEP_GATE="", CLAUDE_CONFIG_DIR="",
                              ACCOUNTS_FILE=str(self.root / "no-accounts"),
                              SESSIONPIPE_CONFIG=str(self.root / "sessionpipe.json"),
                              SESSIONPIPE_STATE=str(self.root / "state"),
                              XDG_STATE_HOME=str(self.root / "xdg-state"))
        self.env.start(); self.addCleanup(self.env.stop)
        os.environ.pop("SHEEP_POLICY_HOME", None)
        for d in (".claude", ".codex", ".gemini/config"):
            (self.root / d).mkdir(parents=True)
        self.pipe = self.root / "sessionpipe-hook"
        self.pipe.write_text("#!/bin/sh\nexit 0\n"); self.pipe.chmod(0o755)
        self.seed = '"%s"' % self.pipe
        self.claude = self.root / ".claude/settings.json"
        self.claude.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [
            {"type": "command", "command": self.seed + " claude-code Stop"}]}]}}))
        self.sheep = importlib.machinery.SourceFileLoader("fixture_builder_sheep", str(v.common.tool("sheep"))).load_module()
        vh = importlib.machinery.SourceFileLoader("fixture_builder_vh", str(v.common.tool("vendor-hooks"))).load_module()
        self.paths = {"codex": self.root / ".codex/hooks.json",
                      "antigravity": self.root / ".gemini/config/hooks.json"}
        self.alone = {"codex": vh.plan_codex({})[0], "antigravity": vh.plan_ag({})[0]}
        for cli, p in self.paths.items():
            p.write_text(json.dumps(self.alone[cli]))
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(self.sheep.cmd_gate(False, no_sink=True), 0)
        self.configs = {cli: json.loads(p.read_text()) for cli, p in self.paths.items()}

    def accepted(self, cli, cfg):
        self.paths[cli].write_text(json.dumps(cfg))
        if cli == "codex":
            return v.codex_guards() is None
        try:
            self.assertEqual(v.agybuild.guards(), cfg)
            return True
        except v.agybuild.Error:
            return False

    @staticmethod
    def groups(cli, cfg):
        return cfg["hooks"] if cli == "codex" else cfg["sessionpipe"]

    def test_gate_then_preflight_accepts_both_harnesses(self):
        for cli, cfg in self.configs.items():
            with self.subTest(cli=cli):
                self.assertTrue(self.accepted(cli, cfg))
                self.assertTrue(self.accepted(cli, self.alone[cli]))
        self.assertFalse((self.root / ".codex/config.toml").exists(), "gate writes no notify")

    def test_codex_ungated_notify_refuses_after_a_refused_gate(self):
        # sheep gate refuses over sessionpipe's own notify, yet leaves its hooks.json written
        toml = self.root / ".codex/config.toml"
        toml.write_text('notify = ["%s", "codex", "notify"]\n' % self.pipe)
        self.paths["codex"].write_text(json.dumps(self.alone["codex"]))
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()), \
             self.assertRaisesRegex(self.sheep.Refused, "still ungated"):
            self.sheep.cmd_gate(False, no_sink=True)
        gated = json.loads(self.paths["codex"].read_text())
        self.assertEqual(gated, self.configs["codex"])
        for cfg in (gated, self.alone["codex"]):
            self.paths["codex"].write_text(json.dumps(cfg))
            self.assertIn("notify ungated", v.codex_guards())
        toml.write_text('model = "x"\n[profiles.x]\nnotify = ["%s", "codex", "notify"]\n' % self.pipe)
        self.assertIsNone(v.codex_guards(), "a notify inside a table is not Codex's")

    def test_reporting_that_will_not_resolve_is_a_clean_refusal(self):
        with patch.object(v.agybuild, "_sheep", side_effect=RuntimeError("Symlink loop")):
            with self.assertRaisesRegex(v.agybuild.Error, "reporting does not resolve: Symlink loop"):
                v.agybuild._reporting(self.configs["antigravity"])
            self.paths["codex"].write_text(json.dumps(self.configs["codex"]))
            self.assertIsNotNone(v.codex_guards(), "a reporting home with no keel to judge it")
            self.paths["codex"].write_text(json.dumps(self.alone["codex"]))
            self.assertIsNone(v.codex_guards())

    def test_codex_guard_group_may_follow_the_reporting_group(self):
        cfg = copy.deepcopy(self.configs["codex"])
        cfg["hooks"]["PreToolUse"].reverse()
        self.assertTrue(self.accepted("codex", cfg))

    def test_reporting_command_near_misses_refuse(self):
        for cli, cfg in self.configs.items():
            for label, change in (
                ("argument", lambda c: c + " extra"),
                ("wrapper", lambda c: "env " + c),
                ("interpreter", lambda c: c.replace("python3 ", "python ", 1)),
                ("gate path", lambda c: c.replace(str(self.sheep.GATE), str(self.root / "sheep_gate.py"))),
                ("pipe path", lambda c: c.replace(str(self.pipe), str(self.root / "other/sessionpipe-hook"))),
                ("bare hook", self.sheep.bare),
                ("shell suffix", lambda c: c + "; true"),
            ):
                with self.subTest(cli=cli, change=label):
                    bad = copy.deepcopy(cfg)
                    h = self.groups(cli, bad)["PreToolUse"][-1]["hooks"][0]
                    h["command"] = change(h["command"])
                    self.assertFalse(self.accepted(cli, bad))

    def test_extra_groups_handlers_events_and_fields_refuse(self):
        for cli, cfg in self.configs.items():
            for label in ("handler", "group", "event", "other event", "timeout", "matcher", "disabled", "guard"):
                with self.subTest(cli=cli, change=label):
                    bad = copy.deepcopy(cfg)
                    hooks = self.groups(cli, bad)
                    g = hooks["PreToolUse"][-1]
                    if label == "handler":
                        g["hooks"].append({"type": "command", "command": "true"})
                    elif label == "group":
                        hooks["PreToolUse"].append(copy.deepcopy(g))
                    elif label == "event":
                        hooks["Unexpected"] = [copy.deepcopy(g)]
                    elif label == "other event":
                        hooks["Stop"][0]["hooks" if cli == "codex" else "command"] = [] if cli == "codex" else "true"
                    elif label == "timeout":
                        g["hooks"][0]["timeout"] += 1
                    elif label == "matcher":
                        g["matcher"] = "run_command"
                    elif label == "guard":
                        if cli == "codex":
                            hooks["PreToolUse"].pop(0)
                        else:
                            bad["regatta"]["enabled"] = False
                    else:
                        g["hooks"][0]["enabled"] = False
                    self.assertFalse(self.accepted(cli, bad))

    def test_an_unreadable_seed_or_overridden_gate_never_grants_trust(self):
        for cli, cfg in self.configs.items():
            with self.subTest(cli=cli), patch.dict(os.environ, SHEEP_GATE=str(self.root / "sheep_gate.py")):
                self.assertFalse(self.accepted(cli, cfg))
        self.claude.write_text("{")
        for cli, cfg in self.configs.items():
            self.assertFalse(self.accepted(cli, cfg))
            self.assertTrue(self.accepted(cli, self.alone[cli]))

    def test_wrappers_arguments_and_shell_expansions_in_the_seed_refuse(self):
        for seed in ("env " + self.seed, self.seed + " extra", '"/tmp/$(true)/sessionpipe-hook"',
                     '"/tmp/`true`/sessionpipe-hook"', '"/tmp/$PIPE/sessionpipe-hook"'):
            self.claude.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [
                {"type": "command", "command": seed + " claude-code Stop"}]}]}}))
            for cli, cfg in self.configs.items():
                with self.subTest(cli=cli, seed=seed):
                    self.assertFalse(self.accepted(cli, cfg))

    def test_missing_keel_keeps_the_guards_only_road(self):
        tool = v.common.tool
        with patch.object(v.common, "tool", side_effect=lambda n: None if n == "sheep" else tool(n)):
            for cli, cfg in self.configs.items():
                self.assertFalse(self.accepted(cli, cfg))
                self.assertTrue(self.accepted(cli, self.alone[cli]))

    def test_agy_guard_denial_keeps_its_decision_json(self):
        # sheep_gate only drops reporting events; the separate PreToolUse guard owns tool denials.
        hook = importlib.machinery.SourceFileLoader("fixture_builder_vendor_hook",
                                                  str(v.common.tool("vendor_hook.py"))).load_module()
        self.assertEqual(hook.answer("antigravity", {}, "allow", None), "")
        self.assertEqual(json.loads(hook.answer("antigravity", {}, "deny", "fixture refusal")),
                         {"decision": "deny", "reason": "fixture refusal"})

    def scratch_fence(self):
        def scratch_home(box):
            h = Path(box) / "login"
            (h / ".gemini/config").mkdir(parents=True)
            return {"HOME": str(h)}, [], None
        fence = SimpleNamespace(BUILDER_KC="builder-keychain", _home_agy=scratch_home,
                                drop_box=shutil.rmtree, FenceError=v.agybuild.Error)
        (self.root / fence.BUILDER_KC).touch()
        return fence

    def test_agy_preflight_refuses_malformed_reporting_policy_home(self):
        for value in ("", "relative-policy"):
            with self.subTest(policy_home=value), patch.dict(os.environ, SHEEP_POLICY_HOME=value), \
                    patch.object(v.agybuild.agy, "sandbox_flag", return_value=None), \
                    patch.object(v.agybuild, "identity", return_value=(None, "example.invalid")):
                why = v.agybuild.preflight(self.root, v.agybuild.MODEL)
                self.assertEqual(why, "agy pre-flight: SHEEP_POLICY_HOME is not an absolute policy home")

    def test_agy_second_preflight_reporting_refusal_ends_reservation(self):
        launcher = importlib.machinery.SourceFileLoader("reporting_fixture_launcher", str(B / "run-vendor")).load_module()
        record = self.root / "run.json"
        args = ["run-vendor", str(self.root), "--cli", "antigravity", "--record", str(record)]
        old_handler = __import__("signal").getsignal(__import__("signal").SIGTERM)
        self.addCleanup(__import__("signal").signal, __import__("signal").SIGTERM, old_handler)
        for value in ("", "relative-policy"):
            with self.subTest(policy_home=value):
                record.write_text(json.dumps({"session": "reserved", "turn_pid": None}))
                out, err = io.StringIO(), io.StringIO()
                with patch.dict(os.environ, SHEEP_POLICY_HOME=value), \
                        patch.object(v.agybuild.agy, "sandbox_flag", return_value=None), \
                        patch.object(v.agybuild, "identity", return_value=(None, "example.invalid")), \
                        patch.object(v, "fence"), \
                        patch.object(v, "preflight", side_effect=lambda cli, model, effort, wt: v.agybuild.preflight(wt, model)), \
                        patch.object(sys, "argv", args), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    self.assertEqual(launcher.main(), 4)
                state = json.loads(record.read_text())
                self.assertTrue(state["ended"])
                self.assertEqual((state["exit"], state["outcome"], state["turn_pid"], state["retry_claude"]),
                                 (4, "held", None, False))
                self.assertEqual(state["end_reason"], "vendor start refused")
                self.assertNotIn("turns", state)
                self.assertIn("SHEEP_POLICY_HOME is not an absolute policy home", err.getvalue())

    def test_agy_scratch_home_preserves_delivery_and_privacy_stores(self):
        fence = self.scratch_fence()
        probe = '''import importlib.machinery,json,sys
s=importlib.machinery.SourceFileLoader("probe_sheep",sys.argv[1]).load_module()
print(json.dumps([str(s.config_file()),str(s.state_dir()),str(s._gate._state_root()),
                  json.loads(s.config_file().read_text())["sinks"],
                  (s.state_dir()/"outbox-kept").read_text(),
                  s._gate.session_dropped("antigravity",{"conversationId":"private-build"},False),
                  str(s._gate._real("~")),s.reporting_env()["SHEEP_POLICY_HOME"]]))
'''
        for mode in ("defaults", "absolute overrides", "xdg roots"):
            with self.subTest(mode=mode), patch.dict(os.environ):
                for key in ("SESSIONPIPE_CONFIG", "SESSIONPIPE_STATE", "XDG_CONFIG_HOME", "XDG_STATE_HOME"):
                    os.environ.pop(key, None)
                if mode == "absolute overrides":
                    os.environ.update(SESSIONPIPE_CONFIG=str(self.root / "custom/config.json"),
                                      SESSIONPIPE_STATE=str(self.root / "custom/outbox"),
                                      XDG_STATE_HOME=str(self.root / "custom/state"))
                elif mode == "xdg roots":
                    os.environ.update(XDG_CONFIG_HOME=str(self.root / "xdg-config"),
                                      XDG_STATE_HOME=str(self.root / "xdg-state"))
                # Resolve through keel before home() replaces HOME.
                config = self.sheep.config_file().resolve()
                state = self.sheep.state_dir().resolve()
                markers = self.sheep._gate._state_root().resolve()
                config.parent.mkdir(parents=True, exist_ok=True)
                config.write_text(json.dumps({"sinks": [{"url": "https://example.invalid"}]}))
                state.mkdir(parents=True, exist_ok=True)
                (state / "outbox-kept").write_text("persistent outbox")
                self.assertTrue(self.sheep._gate.session_dropped(
                    "antigravity", {"conversationId": "private-build"}, True))
                with patch.object(v.codex, "_fence", return_value=fence), v.agybuild.home(self.root) as additions:
                    child = v.agybuild.child_env(additions)
                    self.assertNotEqual(child["HOME"], str(self.root))
                    for key in ("SESSIONPIPE_CONFIG", "SESSIONPIPE_STATE", "XDG_STATE_HOME", "SHEEP_POLICY_HOME"):
                        self.assertTrue(Path(child[key]).is_absolute())
                    result = cmd(sys.executable, "-c", probe, v.common.tool("sheep"),
                                 env=child, cwd=child["HOME"])
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(json.loads(result.stdout), [str(config), str(state), str(markers),
                        [{"url": "https://example.invalid"}], "persistent outbox", True,
                        str(self.root), str(self.root)])
                self.assertFalse(Path(child["HOME"]).exists())
                self.assertTrue(config.is_file())
                self.assertEqual((state / "outbox-kept").read_text(), "persistent outbox")

    def test_agy_scratch_home_fences_fresh_private_events_and_later_stops(self):
        cfg = self.root / "config"
        (cfg / "regatta").mkdir(parents=True)
        (cfg / "regatta/guarded").write_text("vault\n")
        (cfg / "wharf").mkdir()
        registry = cfg / "wharf/repos.json"
        registry.write_text(json.dumps({"repos": {"classified": {}},
            "scopes": {"secret": {"repos": ["classified"], "confidential": True}}}))
        workspace = self.root / "projects/open"
        workspace.mkdir(parents=True)
        audit = self.root / "sent"
        self.pipe.write_text('#!/bin/sh\ncat >> "$REPORTING_AUDIT"\n')
        gate = v.common.tool("sheep_gate.py")

        def send(env, sid, event="PreToolUse", text="open turn"):
            result = cmd(sys.executable, gate, self.pipe, "antigravity", event,
                         input=json.dumps({"conversationId": sid, "workspacePaths": [str(workspace)],
                                           "toolCall": {"args": {"command": text}}}),
                         env=env, cwd=workspace)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))
        with patch.dict(os.environ, REGATTA_CONFIG=str(cfg), CLAUDE_REPOS_JSON=str(registry),
                        REPORTING_AUDIT=str(audit), CLAUDE_PROJECT_DIR="", REGATTA_COUNCIL_ARM=""), \
                patch.object(v.common, "CONFIG", cfg), \
                patch.object(v.codex, "_fence", return_value=self.scratch_fence()):
            with v.agybuild.home(workspace) as additions:
                child = v.agybuild.child_env(additions)
                self.assertEqual(child["SHEEP_POLICY_HOME"], str(self.root))
                for i, text in enumerate((str(self.root / "projects/vault/notes.md"),
                                          str(self.root / "projects/transcripts/notes.md"),
                                          "~/projects/vault/notes.md",
                                          str(self.root / "projects/classified/notes.md"))):
                    with self.subTest(private_text=text):
                        sid = "fresh-private-%d" % i
                        before = audit.read_bytes() if audit.exists() else b""
                        send(child, sid)
                        self.assertNotEqual(audit.read_bytes(), before, "open control must send")
                        before = audit.read_bytes()
                        send(child, sid, text=text)
                        send(child, sid, event="Stop")
                        self.assertEqual(audit.read_bytes(), before, "private event and later Stop must not send")
                for value in ("", "relative-policy"):
                    before = audit.read_bytes()
                    send(dict(child, SHEEP_POLICY_HOME=value), "bad-policy")
                    self.assertEqual(audit.read_bytes(), before, "malformed policy must drop reporting")
            # A new disposable home must still see the fresh denial made in the first one.
            before = audit.read_bytes()
            with v.agybuild.home(workspace) as additions:
                send(v.agybuild.child_env(additions), "fresh-private-1", event="Stop")
            self.assertEqual(audit.read_bytes(), before)


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
                          HEADROOM_SAMPLE="60 0 0", DISPATCH_HOST="laptop")
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
        (self.repo / "AGENTS.md").write_text("# Test repository\n")
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
        self.assertEqual((state["outcome"],state["turns"],state["rounds"],state["launcher_commits"]),("clean",2,2,0))
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
        for line in ("WAITING FOR you: D1", "WAITING FOR D2: which launcher to keep", "WAITING FOR the owner: D1",
                     # a D-item named after a launcher word still holds (the landing review, 2026-11-07)
                     "WAITING FOR review of D1 by the owner", "WAITING FOR CI budget decision: D1",
                     "WAITING FOR the launcher choice (D1)", "WAITING FOR ci-provider decision D2",
                     "WAITING FOR review: a D-item is open",
                     "\U0001f6d1 OWNER, THIS SESSION IS WAITING FOR review \u2014 D1",
                     # owner words, a house line, a lowercase d1 or a hyphen hold with no D-item (the second review)
                     "WAITING FOR review by the owner", "WAITING FOR CI credentials from the owner",
                     "WAITING FOR checks: owner must grant access", "WAITING FOR review of d1",
                     "WAITING FOR review of the open decision in docs/x.md", "WAITING FOR ci-provider access",
                     "WAITING FOR CIRCLECI credits: top up", "WAITING FOR reviewer",
                     "\U0001f6d1 OWNER, THIS SESSION IS WAITING FOR review \u2014 approve the schema",
                     "\U0001f6d1 THIS SESSION IS WAITING FOR CI \u2014 add the token",
                     # a bare stage word names no launcher and may be the owner's review (the third review)
                     "WAITING FOR Checks", "WAITING FOR review", "WAITING FOR review.", "WAITING FOR CI",
                     "WAITING FOR REVIEW", "WAITING FOR checks, review and CI.",
                     "\U0001f6d1 THIS SESSION IS WAITING FOR YOU \u2014 D1",
                     "\U0001f6d1 MARY ANN, THIS SESSION IS WAITING FOR YOU \u2014 D1",
                     "\U0001f6d1 JOS\u00c9, THIS SESSION IS WAITING FOR YOU \u2014 D1"):
            self.assertTrue(rv.held_by(line), line)
        for line in ("Done, WAITING FOR review", "I noted that WAITING FOR x",
                     "\u2705 OWNER, THIS SESSION IS WAITING FOR NOTHING \u2014 built",
                     # the launcher's own next stage is no hold (three Codex builds, 2026-11-06)
                     "WAITING FOR launcher checks and review.", "WAITING FOR the launcher's review rounds",
                     "WAITING FOR: launcher checks", "WAITING FOR\tlauncher checks and review",
                     "**WAITING FOR launcher checks and review**", "WAITING FOR the launcher's checks, review and CI.",
                     "WAITING FOR the launcher", "WAITING FOR the launcher's checks or reviews"):
            self.assertFalse(rv.held_by(line), line)

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
        r=self.launch(BUILD_ANSWER=v.common.WAITING_PREFIX + "D1\n[doc](https://example.invalid/doc)")
        s=self.state(); self.assertEqual((s["outcome"],s["retry_claude"]),("held",False),r.stdout+r.stderr)

    def test_a_turn_that_commits_nothing_is_a_failure(self):
        r=self.launch(NO_COMMIT="1",BUILD_ANSWER="I cannot do this.")
        s=self.state(); self.assertEqual(s["outcome"],"failed",r.stdout+r.stderr)
        self.assertIn("committed nothing",s["end_reason"]); self.assertTrue(s["retry_claude"])
        self.assertEqual(s["launcher_commits"],0)
        self.assertEqual([c["mode"] for c in self.calls()],["build"])

    def test_uncommitted_turn_is_committed_by_the_launcher(self):
        (self.wt/".gitignore").write_text("ignored.tmp\n")
        v.git(self.wt,"add",".gitignore"); v.git(self.wt,"commit","-qm","ignore tmp")
        empty_cfg=self.root/"empty-gitconfig"; empty_cfg.write_text("[init]\ndefaultBranch = main\n")
        r=self.launch(LEAVE_UNCOMMITTED="1",CLEAN_REVIEWS="1",GIT_CONFIG_GLOBAL=str(empty_cfg))
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        s=self.state()
        self.assertEqual((s["outcome"],s["launcher_commits"]),("clean",1),r.stdout+r.stderr)
        self.assertEqual(v.git(self.wt,"rev-parse","HEAD"),self.git("rev-parse","refs/remotes/origin/claude/laptop/build"))
        tracked=v.git(self.wt,"ls-tree","-r","--name-only","HEAD").splitlines()
        self.assertIn("sub/added.txt",tracked)
        self.assertIn("notes.md",tracked,"a Markdown Setext underline is no conflict marker")
        self.assertNotIn("ignored.tmp",tracked,".gitignore honoured")
        msg=v.git(self.wt,"log","-1","--format=%B","HEAD")
        vh=importlib.machinery.SourceFileLoader("vh_vendors_check",str(B.parents[1]/"lighthouse/hooks/vendor_hook.py")).load_module()
        rv=importlib.machinery.SourceFileLoader("rv_vendors_check",str(B/"run-vendor")).load_module()
        self.assertEqual(rv.VENDORS,vh.VENDORS)
        name,addr=vh.VENDORS[s["agent"]]
        self.assertTrue(msg.startswith("build: %s turn 1 \u2014 committed by the launcher\n\n" % s["agent"]),msg)
        self.assertIn("sandbox",msg); self.assertIn("git folder",msg)
        self.assertIn("Co-Authored-By: %s <%s>" % (name,addr),msg)

    def test_conflict_markers_in_touched_file_are_refused(self):
        r=self.launch(LEAVE_CONFLICT="1",CLEAN_REVIEWS="1")
        self.assertEqual(r.returncode,1,r.stdout+r.stderr)
        s=self.state()
        self.assertEqual((s["outcome"],s["launcher_commits"],s["retry_claude"]),("failed",0,True),r.stdout+r.stderr)
        self.assertIn("conflict markers",s["end_reason"])
        self.assertNotIn("sub/conflict.py",v.git(self.wt,"ls-tree","-r","--name-only","HEAD").splitlines())

    def test_failed_launcher_commit_is_refused(self):
        r=self.launch(LEAVE_UNCOMMITTED="1",LOCK_GIT="1",CLEAN_REVIEWS="1")
        self.assertEqual(r.returncode,1,r.stdout+r.stderr)
        s=self.state()
        self.assertEqual((s["outcome"],s["launcher_commits"],s["retry_claude"]),("failed",0,True),r.stdout+r.stderr)

    def test_protected_uncommitted_path_holds_and_is_never_committed(self):
        for rel in (".env.local", ".codex/hooks.json", "docs/handoff/2026-11-04-build.review"):
            with self.subTest(rel=rel):
                p=self.wt/rel
                r=self.launch(LEAVE_PROTECTED=rel,CLEAN_REVIEWS="1")
                try:
                    self.assertEqual(r.returncode,1,r.stdout+r.stderr)
                    s=self.state()
                    self.assertEqual((s["outcome"],s["launcher_commits"],s["retry_claude"]),("held",0,False),r.stdout+r.stderr)
                    self.assertNotIn(rel,v.git(self.wt,"ls-tree","-r","--name-only","HEAD").splitlines())
                finally:
                    if p.is_file(): p.unlink()
                    if (self.wt/".codex").is_dir(): (self.wt/".codex").rmdir()
                    (Path(v.git(self.wt,"rev-parse","--absolute-git-dir"))/"claude/owner.json").unlink(missing_ok=True)
                    self.record.write_text(json.dumps({"session":self._testMethodName,"repo":str(self.repo),"topic":"build"}))

    def test_committed_protected_path_holds_and_is_never_pushed(self):
        self.brief.write_text("Review: finish only\nBuild it.\n")
        v.git(self.wt,"commit","-qam","fixture: finish-only brief")
        v.git(self.wt,"push","-q","origin","HEAD:refs/heads/claude/laptop/build")
        seed_tip=v.git(self.wt,"rev-parse","HEAD")
        for rel in (".env.local", ".codex/hooks.json", ".gemini/config/hooks.json", "docs/handoff/2026-11-04-build.review"):
            with self.subTest(rel=rel):
                r=self.launch(COMMIT_PROTECTED=rel,CLEAN_REVIEWS="1")
                try:
                    self.assertEqual(r.returncode,1,r.stdout+r.stderr)
                    s=self.state()
                    self.assertEqual((s["outcome"],s["launcher_commits"],s["retry_claude"]),("held",0,False),r.stdout+r.stderr)
                    pushed=v.git(self.wt,"rev-parse","refs/remotes/origin/claude/laptop/build")
                    self.assertEqual(pushed,seed_tip,"protected commit must never be pushed to origin")
                finally:
                    v.git(self.wt,"reset","--hard",seed_tip)
                    (Path(v.git(self.wt,"rev-parse","--absolute-git-dir"))/"claude/owner.json").unlink(missing_ok=True)
                    rec={"session":self._testMethodName,"repo":str(self.repo),"topic":"build"}
                    if isinstance(self,AntigravityTests):
                        rec["arm"]=v.buildercoin.arm_of("argon-high:2:2099-01-01:0")
                    self.record.write_text(json.dumps(rec))

    def test_prompt_first_line_privacy_gate_and_step_stamp_rule(self):
        cfg=Path(os.environ["REGATTA_CONFIG"])
        (cfg/"regatta").mkdir(exist_ok=True)
        guarded=cfg/"regatta/guarded"
        guarded.write_text("vault\n")
        self.addCleanup(lambda: guarded.unlink(missing_ok=True))
        Path(os.environ["CLAUDE_REPOS_JSON"]).write_text(json.dumps({
            "repos":{"know":{}},"scopes":{"open":{"repos":["*"]},
                                          "sec":{"file":"s.code-workspace","repos":["know"],"confidential":True}}}))
        r=self.launch(CLEAN_REVIEWS="1"); self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        prompt=self.calls()[0]["prompt"]
        lines=prompt.splitlines()
        self.assertEqual(lines[0],v.common.session_name("build","build"))
        self.assertEqual(lines[1],"")
        self.assertRegex(prompt,r"python3 modules/keel/bin/keel step <doc> S<n> done --branch \S+ --stamp")
        self.assertIn("Steps:",prompt)
        self.assertIn("build S<n> of docs/<doc>.md",prompt)
        self.assertNotIn("Leave design step stamps to the landing",prompt)
        sg=importlib.machinery.SourceFileLoader("vendor_sheep_gate",str(B.parents[1]/"keel/hooks/sheep_gate.py")).load_module()
        sg.confidential_roots.cache_clear()
        self.assertIsNotNone(sg._text_reason(str(Path.home()/"projects/vault/note.md")),"fixture vault path is gated")
        self.assertIsNotNone(sg._text_reason(str(Path.home()/"projects/know/note.md")),"fixture confidential path is gated")
        self.assertIsNone(sg._text_reason(prompt))

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

    def test_record_first_reply_for_each_reader(self):
        rc=importlib.machinery.SourceFileLoader("vendor_readers_rc",str(B / "dispatch-rc")).load_module()
        q=importlib.machinery.SourceFileLoader("vendor_readers_queue",str(B / "dispatch-queue")).load_module()
        st={"session":"vendor-reader", "mode":"vendor", "started":1, "manager":"skipper",
            "wt":str(self.wt), "repo":str(self.repo), "branch":"claude/laptop/build", "topic":"build",
            "last_answer":v.common.WAITING_PREFIX + "D3 needs an answer"}
        runs=self.root / "runs"; runs.mkdir()
        (runs / "bad.json").write_text("{")
        (runs / "run.json").write_text(json.dumps(st))
        with patch.object(rc,"RUNS",str(runs)), patch.object(rc,"transcript",side_effect=AssertionError("no transcript")):
            self.assertEqual(rc.last_answer(st["session"]),st["last_answer"])
            self.assertIn("no bin/ask relay",rc.ask_guard(st))
            st["last_answer"]="You've hit your weekly limit"
            with patch.object(rc,"checks_on",return_value=[]):
                self.assertEqual(rc.cut_at_cap(st)["limit"],st["last_answer"])
            st["last_answer"]="Vendor's unfinished work, from its record."
            with patch.object(q,"rc_mod",return_value=rc):
                q.cut_run(None,st,"buildbox","2099-01-01","fixture",[])
            self.assertIn(st["last_answer"],self.brief.read_text())
            self.assertEqual(rc.last_answer(st["session"],dict(st,last_answer="")),"")

    def test_vendor_review_credit_is_opt_in(self):
        result=self.launch(); self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        br=importlib.machinery.SourceFileLoader("vendor_credit_review",str(B / "build-review")).load_module()
        d=br.load(br.where(self.wt)[0])
        self.assertIn(d["agent"],("codex","antigravity"))
        self.assertIn("evidence:",d["rounds"][0]["findings"])
        flag=Path(os.environ["REGATTA_CONFIG"]) / "wharf-runs/trust-vendor-review"
        try:
            # A prior Claude loop in the owner's worktree cannot hide the
            # newer vendor loop that arrived in its log with the finish.
            prior=dict(d,agent="claude",ended=d["ended"]-1,rounds=[dict(r,reviewers=["reviewer-high"]) for r in d["rounds"]])
            br.save(br.where(self.wt)[0],prior)
            for value in (None,"off\n","yes\n","on\noff\n"):
                if value is not None: flag.write_text(value)
                ok,why=br.covers(self.wt,"origin/main")
                self.assertFalse(ok); self.assertIn("full Claude review",why)
            flag.write_text("on\n")
            ok,why=br.covers(self.wt,"origin/main")
            self.assertTrue(ok,why)
            # The flag only permits the normal proof; changed code still owes review.
            (self.wt / "f.py").write_text("new code\n")
            v.git(self.wt,"add","f.py"); v.git(self.wt,"commit","-qm","fixture: unreviewed code")
            self.assertFalse(br.covers(self.wt,"origin/main")[0])
        finally:
            flag.unlink(missing_ok=True)

    def test_vendor_handover_carries_evidence_to_owner(self):
        import vendorhandover as hand
        result=self.launch(HANDOVER_LINE=v.common.HANDOVER_LINE); self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        state=json.loads(self.record.read_text())
        self.assertEqual(state["last_answer"],v.common.HANDOVER_LINE)
        br=hand.review_tool()
        path=br.where(self.wt)[0]; review=br.load(path)
        review["rounds"][0]["findings"] += "\n" + "proof "*12000
        br.save(path,review)  # an evidence bundle can exceed one model message
        real_run=subprocess.run
        entries=[]
        seen_payloads=[]
        def run(argv,**kwargs):
            if str(B / "dispatch-queue") in list(map(str,argv)):
                self.assertIn("--build-record",argv)
                self.assertFalse(set(argv) & {"--pin","--prefer","--needs","--env"})
                rights=json.loads(argv[argv.index("--finish")+1])
                self.assertEqual(rights["by"],"handed")
                self.assertEqual(rights["from"],"laptop")
                p_arg=Path(argv[argv.index("--build-record")+1])
                self.assertNotEqual(p_arg.parent,self.record.parent)
                seen_payloads.append(p_arg)
                entries.append(json.loads(p_arg.read_text()))
                return subprocess.CompletedProcess(argv,0,'{"result":"queued"}',"")
            return real_run(argv,**kwargs)
        with patch.object(hand.subprocess,"run",side_effect=run):
            hand.handover(self.wt,self.record)
            hand.handover(self.wt,self.record)  # idempotent after a confirmed put
        self.assertEqual(len(entries),1)
        self.assertFalse(seen_payloads[0].exists())
        self.assertEqual([p.name for p in self.record.parent.glob("*.handover*")], [])
        data=entries[0]
        q=importlib.machinery.SourceFileLoader("handover_queue",str(B / "dispatch-queue")).load_module()
        with patch.object(q,"berth_candidates",return_value=(["laptop"],{})), \
                patch.object(q,"finish_readiness",side_effect=AssertionError("builder host never probes finish readiness")):
            self.assertIn("never a finish",q.claimable({"state":"queued","kind":"finish","repo":str(self.repo),
                                                        "branch":state["branch"],"needs":["finish-queue"]},"laptop"))
        self.assertEqual(data["run"]["agent"],state["agent"])
        self.assertIn("evidence:",data["review"]["rounds"][0]["findings"])
        owner=self.root / "owner"
        with patch.dict(os.environ,BUILD_REVIEW_LOG=str(owner / "build-review.jsonl"),REVIEW_GATE_LOG=str(owner / "review-gate.jsonl")):
            hand.receive(data,self.wt,state["branch"],state["tip"])
            hand.receive(data,self.wt,state["branch"],state["tip"])
            self.assertEqual(len((owner / "build-review.jsonl").read_text().splitlines()),1)
            self.assertEqual(len((owner / "vendor-builds.jsonl").read_text().splitlines()),1)
            self.assertEqual(len((owner / "review-gate.jsonl").read_text().splitlines()),len(data["gates"]))
            with self.assertRaisesRegex(ValueError,"clean tip"):
                hand.receive(data,self.wt,state["branch"],"0"*40)
            malformed=dict(data,review=dict(data["review"],ended="bad time"))
            self.assertIn("numeric end times",hand.bad(malformed,state["branch"],state["tip"]))
            for bad_case, needle in (
                (dict(data,review=dict(data["review"],project="other-proj")),"review does not match"),
                (dict(data,run=dict(data["run"],repo="/tmp/other-proj")),"clean tip"),
                (dict(data,gates=[dict(data["gates"][0],project="other-proj")]),"gate rows"),
                (dict(data,gates=[dict(data["gates"][0],head="not-hex")]),"gate rows"),
                (dict(data,gates=[dict(data["gates"][0],ts="bad")]),"gate rows"),
            ):
                with self.assertRaisesRegex(ValueError,needle):
                    hand.receive(bad_case,self.wt,state["branch"],state["tip"])
            # The owner's verifier findings stay beside the carried build's,
            # under its separate finish phase, including a held fix round.
            br=hand.review_tool()
            report=self.root / "owner-verdict.md"
            report.write_text("f.py:1 — [S2] owner finding\nverdict: WRONG\nevidence: owner traced a defect\n")
            with patch.dict(os.environ,CLAUDE_CODE_SESSION_ID="owner-finish"):
                self.assertEqual(br.main(["round",str(self.wt),"--phase","finish","--verdicts",str(report),
                                          "--fixed","1","--check","green"]),0)
                self.assertEqual(br.main(["end",str(self.wt),"--phase","finish","--outcome","held"]),0)
            records=[json.loads(line) for line in (owner / "build-review.jsonl").read_text().splitlines()]
            self.assertEqual(len(records),2)
            self.assertEqual(records[0]["agent"],state["agent"])
            self.assertIn("owner finding",records[1]["rounds"][0]["findings"])
            self.assertEqual(records[1]["phase"],"finish")

    def test_pending_closing_line_holds_vendor_build(self):
        r=self.launch(CLEAN_REVIEWS="1",BUILD_ANSWER="Built.\n\n"+v.common.PENDING_PREFIX+"own follow-up")
        self.assertEqual(r.returncode,1,r.stdout+r.stderr)
        self.assertEqual(self.state()["outcome"],"held")

    def test_pending_line_waiting_on_the_launcher_holds_nothing(self):
        # #577's false hold in the house line's form: a wait on the launcher's next stage reaches the review loop
        r=self.launch(CLEAN_REVIEWS="1",BUILD_ANSWER="Built.\n\n⏳ "+v.common.PENDING_PREFIX+"the launcher's checks and review")
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        self.assertEqual(self.state()["outcome"],"clean")

    def test_pending_line_naming_the_launcher_then_a_d_item_holds(self):
        # the allowlist is whole: a wait that goes on to a D-item after the launcher still holds (round 2)
        rv=importlib.machinery.SourceFileLoader("vendor_fixture_rv_pending",str(B/"run-vendor")).load_module()
        p=v.common.PENDING_PREFIX
        self.assertTrue(rv.held_by("Built.\n\n⏳ "+p+"the launcher's checks, then D1 in docs/x.md answered"))
        self.assertTrue(rv.held_by("Built.\n\n⏳ "+p+"the launcher to relay D2 in docs/x.md to the owner"))
        self.assertFalse(rv.held_by("Built.\n\n⏳ "+p+"the launcher's checks and review"))

    def test_a_launcher_wait_holds_only_when_it_names_a_decision(self):
        # S5's landing review, round 3: a whole-line allowlist of stage words held the prompt's own "checks or
        # reviews" (#577 again); a wait that opens on the launcher releases unless it names a D-item, a doc or a person
        rv=importlib.machinery.SourceFileLoader("vendor_fixture_rv_decision",str(B/"run-vendor")).load_module()
        p=v.common.PENDING_PREFIX
        for wait, held in (("the launcher's checks, then D2 in docs/x.md", True),
                           ("the launcher's checks or reviews", False),
                           ("the launcher to run checks and review rounds", False),
                           ("the launcher's review loop", False),
                           ("the launcher’s checks, then review", False),
                           ("the launcher's checks and the owner's D1", True),
                           ("the launcher's checks, then a decision on the schema in docs/x.md", True),
                           ("the launcher's checks, then you", True),
                           ("D2, then the launcher's checks", True),
                           ("the launcher's checks.", False)):
            self.assertEqual(rv.held_by("Built.\n\n⏳ "+p+wait), held, wait)
            self.assertEqual(rv.held_by("Built.\n\nWAITING FOR "+wait), held, "bare: "+wait)

    def test_failed_dispatch_next_does_not_persist_next_scheduled(self):
        launcher = importlib.machinery.SourceFileLoader("vendor_fixture_launcher_next_fail", str(B / "run-vendor")).load_module()
        original_run = subprocess.run

        def fail_next(argv, **kw):
            if str(argv[0]) == str(B / "dispatch") and "--next" in argv:
                return subprocess.CompletedProcess(argv, 2, "", "refused")
            return original_run(argv, **kw)
        args = SimpleNamespace(worktree=self.wt, cli="codex", model=v.MODEL, effort="xhigh", origin="", coin=False,
                               record=self.record, brief=self.brief, preflight=False, next=True, timeout=90)
        with patch.dict(os.environ, {"CLEAN_REVIEWS": "1"}), patch.object(launcher.subprocess, "run", fail_next):
            self.assertEqual(launcher.run(args), 0)
        st = self.state()
        self.assertEqual(st["outcome"], "clean")
        self.assertFalse(st.get("next_scheduled"))
        self.assertTrue(str(st.get("launch") or "").startswith("declined:"))

    def test_finish_only_check_repair_and_handover(self):
        import vendorhandover as hand
        self.brief.write_text("Review: finish only\n\nBuild it.\n")
        self.assertEqual(cmd("git","-C",self.wt,"add",str(self.brief)).returncode,0)
        self.assertEqual(cmd("git","-C",self.wt,"commit","-qm","finish-only brief").returncode,0)
        r=self.launch(CHECK_FAIL_BAD="1",HANDOVER_LINE=v.common.HANDOVER_LINE)
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        st=self.state()
        self.assertEqual((st["outcome"],st["review_mode"],st["last_answer"]),
                         ("clean","finish_only",v.common.HANDOVER_LINE))
        entries=[]
        real_run=subprocess.run
        def run(argv,**kwargs):
            if str(B / "dispatch-queue") in list(map(str,argv)):
                rights=json.loads(argv[argv.index("--finish")+1])
                entries.append((rights,json.loads(Path(argv[argv.index("--build-record")+1]).read_text())))
                return subprocess.CompletedProcess(argv,0,'{"result":"queued"}',"")
            return real_run(argv,**kwargs)
        with patch.dict(os.environ,DISPATCH_HOST="buildbox-agy"), \
                patch.object(v.common,"host_name",return_value="owner-mac"), \
                patch.object(hand.subprocess,"run",side_effect=run):
            hand.handover(self.wt,self.record)
        self.assertEqual(len(entries),1)
        rights,data=entries[0]
        self.assertEqual(rights["from"],"buildbox-agy")
        self.assertIsNone(data["review"])
        self.assertEqual(data["gates"],[])
        owner=self.root / "owner-fo"
        with patch.dict(os.environ,BUILD_REVIEW_LOG=str(owner / "build-review.jsonl"),
                        REVIEW_GATE_LOG=str(owner / "review-gate.jsonl")):
            hand.receive(data,self.wt,st["branch"],st["tip"])
            self.assertEqual(len((owner / "vendor-builds.jsonl").read_text().splitlines()),1)
            self.assertFalse((owner / "build-review.jsonl").exists())
            self.assertFalse((owner / "review-gate.jsonl").exists())
            # Spoofing finish_only on a normal brief is rejected by receive().
            self.brief.write_text("Build it.\n")
            self.assertEqual(cmd("git","-C",self.wt,"add",str(self.brief)).returncode,0)
            self.assertEqual(cmd("git","-C",self.wt,"commit","-qm","normal brief").returncode,0)
            new_tip=v.git(self.wt,"rev-parse","HEAD")
            spoof={"run":dict(data["run"],tip=new_tip),"review":None,"gates":[]}
            with self.assertRaisesRegex(ValueError,"finish_only"):
                hand.receive(spoof,self.wt,st["branch"],new_tip)

    def test_a_hanging_enqueue_declines_the_handover(self):
        # S5's landing review, round 3: a queue put that hangs kept dispatch's shell alive with no launch written
        import vendorhandover as hand
        self.brief.write_text("Review: finish only\n\nBuild it.\n")
        self.assertEqual(cmd("git","-C",self.wt,"add",str(self.brief)).returncode,0)
        self.assertEqual(cmd("git","-C",self.wt,"commit","-qm","finish-only brief").returncode,0)
        r=self.launch(CHECK_FAIL_BAD="1",HANDOVER_LINE=v.common.HANDOVER_LINE)
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        real_run=subprocess.run
        seen=[]
        def run(argv,**kwargs):
            if str(B / "dispatch-queue") in list(map(str,argv)):
                seen.append(kwargs.get("timeout"))
                raise subprocess.TimeoutExpired(argv,kwargs.get("timeout") or 0)
            return real_run(argv,**kwargs)
        with patch.dict(os.environ,DISPATCH_HOST="buildbox-agy"), \
                patch.object(v.common,"host_name",return_value="owner-mac"), \
                patch.object(hand.subprocess,"run",side_effect=run):
            hand.handover(self.wt,self.record)
        self.assertEqual(seen,[hand.ENQUEUE_TIMEOUT])
        self.assertIn("did not answer",self.state()["launch"])
        self.assertTrue(self.state()["launch"].startswith("declined:"))

    def test_vendor_handover_modes_and_judge(self):
        import vendorhandover as hand
        design=self.wt / "docs/design-2026-11-04.md"
        design.write_text("# Design\n\n## Action plan\n\n- **S1 — Build it** · session · status: wip\n")
        self.brief.write_text("Task: build it\nSteps: S1 of docs/design-2026-11-04.md\n\nBuild it.\n")
        self.assertEqual(cmd("git","-C",self.wt,"add","docs").returncode,0)
        self.assertEqual(cmd("git","-C",self.wt,"commit","-qm","course step").returncode,0)
        r=self.launch(CLEAN_REVIEWS="1",HANDOVER_LINE=v.common.HANDOVER_LINE,DISPATCH_MODE="ask")
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        hand.handover(self.wt,self.record)
        self.assertIn("mode is ask",self.state()["launch"])
        for mode, expected_by, expected_rule in (("yolo","yolo","M"),("dnd","dnd","M"),("default","handed","C")):
            st=self.state(); st.pop("launch",None); st["dispatch_mode"]=mode
            v.save(self.record,st)
            captured=[]
            real_run=subprocess.run
            def run(argv,**kwargs):
                if str(B / "dispatch-queue") in list(map(str,argv)):
                    captured.append(json.loads(argv[argv.index("--finish")+1]))
                    return subprocess.CompletedProcess(argv,0,'{"result":"queued"}',"")
                return real_run(argv,**kwargs)
            with patch.object(hand.subprocess,"run",side_effect=run):
                hand.handover(self.wt,self.record)
            self.assertEqual(len(captured),1,self.state())
            self.assertEqual((captured[0]["by"],captured[0]["rule"]),(expected_by,expected_rule))
            self.assertEqual(captured[0].get("owed"),["docs/design-2026-11-04.md S1"])
        # Open D-items hold vendor hand-over instead of queuing /finish.
        design.write_text("# Design\n\n- **D1 — Pick one.**\n  - A — one\n  - B — two\n  Reversible: no\n  ➤ Recommended: A\n  ➤ Answer:\n")
        self.assertEqual(cmd("git","-C",self.wt,"add",str(design)).returncode,0)
        self.assertEqual(cmd("git","-C",self.wt,"commit","-qm","open d1").returncode,0)
        new_tip=v.git(self.wt,"rev-parse","HEAD")
        st=self.state(); st.pop("launch",None); st["dispatch_mode"]="default"; st["tip"]=new_tip
        v.save(self.record,st)
        hand.handover(self.wt,self.record)
        self.assertTrue(self.state()["launch"].startswith("no launch — open for"),self.state()["launch"])
        # Clean vendor runs without HANDOVER_LINE or with ending record explicit launch reasons and never raise
        # "closing line: hand-over, its launch never started" in stalls.judge_runs.
        sys.path.insert(0,str(B.parents[1] / "helm/bin"))
        import stalls
        from types import SimpleNamespace
        ad=SimpleNamespace(status=lambda *a,**kw:None,list=lambda:[],last_reply=lambda *a,**kw:None)
        for patch_run, want_sub in (
                ({"dispatch_mode":"ask","last_answer":"Done."}, "mode is ask"),
                ({"dispatch_mode":"default","last_answer":"Done."}, "did not end on the hand-over line"),
                ({"dispatch_mode":"default","last_answer":"Done.","ending":"requeued by dispatch --requeue",
                  "end_reason":"requeued by dispatch --requeue"}, "it was requeued (dispatch --requeue)")):
            st=self.state(); st.pop("launch",None); st.pop("ending",None)
            st["end_reason"]="review and check clean"
            st.update(**patch_run)
            v.save(self.record,st)
            hand.handover(self.wt,self.record)
            cur=self.state()
            self.assertTrue(str(cur.get("launch") or "").startswith("no launch — "),cur)
            self.assertIn(want_sub,cur["launch"])
            view=stalls.facts([("vendor.json",cur)],ad,lambda s:False,lambda s:True,())
            view["raw"]={"vendor.json":dict(cur)}
            s_out,u_out=stalls.judge_runs("laptop-codex",view,[("laptop-codex","vendor.json",dict(cur))],
                                          set(),set(),1000,queued=lambda *a,**kw:False)
            self.assertEqual((len(s_out),len(u_out)),(1,0),s_out)
            self.assertEqual(s_out[0]["rule"],"done, no hand-over: it waits for /finish",s_out[0])
            self.assertFalse(any("no launch recorded" in line for line in s_out[0]["evidence"]),s_out[0])
        # autofinish-run.handover_of keeps vendor hand-over status on empty owed and --by chain relaunches.
        afrun=importlib.machinery.SourceFileLoader("vendor_fixture_afrun",str(B / "autofinish-run")).load_module()
        dq=importlib.machinery.SourceFileLoader("vendor_fixture_dq",str(B / "dispatch-queue")).load_module()
        self.assertIn("HANDOVER_VENDOR",afrun.DROP_JOB)
        for m in ("yolo","dnd"):
            with patch.dict(os.environ,{"HANDOVER_OWED":""},clear=False):
                os.environ.pop("HANDOVER_VENDOR",None)
                self.assertEqual(afrun.handover_of(m,m,None),(False,[]))
                os.environ["HANDOVER_VENDOR"]="1"
                self.assertEqual(afrun.handover_of(m,m,None),(True,[]))
                os.environ.pop("HANDOVER_VENDOR",None)
                self.assertEqual(afrun.handover_of(m,"chain",{"by":m,"handover":True,"owed":["docs/design-2026-11-04.md S1"]}),
                                 (True,["docs/design-2026-11-04.md S1"]))
                self.assertEqual(afrun.handover_of(m,"chain",{"by":m,"handover":True,"owed":None}),
                                 (True,[]))
        self.assertIsNone(dq.finish_bad({"kind":"finish","repo":str(self.repo),"branch":self.state()["branch"],
                                         "tip":new_tip,"finish":{"by":"chain","rule":"M","merge":False,"hold":False,
                                                                 "from":"laptop","owed":["docs/design-2026-11-04.md S1"]}}))

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
    pathlib.Path(a[1]).write_text('' if os.environ.get('OMIT_MODELS_EMAIL') else
                                  'OAuth: authenticated successfully as '+os.environ.get('NATIVE_EMAIL','test@example.invalid')+'\n')
    print('gemini-4-argon-high' if not os.environ.get('MISSING_MODEL') else 'gemini-other'); sys.exit(0)
flags={}; i=0
while i<len(a):
    f=a[i]
    if f=='--add-dir':
        flags.setdefault(f,[]).append(a[i+1]); i+=2; continue
    assert f not in flags, a
    if f in ('--sandbox','--dangerously-skip-permissions','-p='): flags[f]=True; i+=1
    elif f in ('--input-format','--output-format','--model','--effort','--conversation','--log-file','--print-timeout'):
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
assert os.environ.get('REGATTA_CONFIG') and pathlib.Path(os.environ['REGATTA_CONFIG']).is_dir()
home=pathlib.Path(os.environ['HOME']); gemini=pathlib.Path(os.environ['GEMINI_CLI_HOME'])
assert gemini==home/'.gemini'
keys=set(json.loads((gemini/'config/hooks.json').read_text()))
# the gated reporting entry only ever reaches the box with the builder's policy home beside it
assert keys=={'regatta'} or (keys=={'regatta','sessionpipe'} and os.environ.get('SHEEP_POLICY_HOME')), keys
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
# a reviewer gets no git dir to write; the builder's commits in a linked worktree need its git folders
assert ('--add-dir' not in flags) if review else (flags.get('--add-dir') and all(pathlib.Path(d).is_dir() for d in flags['--add-dir'])), (mode, flags)
wt=pathlib.Path(os.getcwd()); f=wt/'f.py'
with open(os.environ['AUDIT'],'a') as audit: audit.write(json.dumps({'mode':mode,'prompt':prompt,'conversation':conv,'home':str(home)})+'\n')
if review and os.environ.get('REVIEW_WRITES'): f.write_text('reviewer wrote\n')
if mode=='build' and os.environ.get('PLANT_HOOK'):
    gd=subprocess.run(['git','rev-parse','--path-format=absolute','--git-common-dir'],capture_output=True,text=True).stdout.strip()
    hook=pathlib.Path(gd)/'hooks/pre-push'; hook.parent.mkdir(exist_ok=True); hook.write_text('#!/bin/sh\nexit 0\n')
if mode=='build' and os.environ.get('PLANT_UNREADABLE_HOOK'):
    gd=subprocess.run(['git','rev-parse','--path-format=absolute','--git-common-dir'],capture_output=True,text=True).stdout.strip()
    hooks=pathlib.Path(gd)/'hooks'; hooks.mkdir(exist_ok=True)
    pp=hooks/'pre-push'; pp.write_text('#!/bin/sh\nprintf PWNED > %r\nexit 0\n' % os.environ['HOOK_MARKER']); pp.chmod(0o755)
    bad=hooks/'zzz_unreadable'; bad.write_text('x\n'); bad.chmod(0)
if mode=='build' and os.environ.get('PLANT_BAD_SYMLINK'):
    gd=subprocess.run(['git','rev-parse','--path-format=absolute','--git-common-dir'],capture_output=True,text=True).stdout.strip()
    hooks=pathlib.Path(gd)/'hooks'; hooks.mkdir(exist_ok=True)
    pp=hooks/'pre-push'; pp.write_text('#!/bin/sh\nprintf PWNED > %r\nexit 0\n' % os.environ['HOOK_MARKER']); pp.chmod(0o755)
    os.symlink(b'\xff', os.fsencode(hooks/'bad_link'))
if mode=='build' and os.environ.get('PLANT_EXEC_ONLY_HOOKS'):
    gd=subprocess.run(['git','rev-parse','--path-format=absolute','--git-common-dir'],capture_output=True,text=True).stdout.strip()
    hooks=pathlib.Path(gd)/'hooks'; hooks.mkdir(exist_ok=True)
    pp=hooks/'pre-push'; pp.write_text('#!/bin/sh\nprintf PWNED > %r\nexit 0\n' % os.environ['HOOK_MARKER']); pp.chmod(0o755)
    hooks.chmod(0o111)
if review:
    if 'name: code-reviewer' in prompt: text='[]'
    elif 'You reformat a review' in prompt: text='NO_FINDINGS'
    elif 'fresh verifier' in prompt:
        text='f.py:1 — [S2] bad result\nverdict: WRONG\nevidence: bad input produces bad output\nfix: write fixed'
    elif os.environ.get('CLEAN_REVIEWS'): text='NO_FINDINGS'
    elif f.read_text().strip()=='bad' or os.environ.get('ALWAYS_FIND'):
        text='f.py:1 — [S2] bad result\nverdict: WRONG\nevidence: bad input produces bad output\nfix: write fixed'
    else: text='NO_FINDINGS'
else:
    if os.environ.get('LEAVE_CONFLICT'):
        sub=wt/'sub'; sub.mkdir(exist_ok=True)
        (sub/'conflict.py').write_text('<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> main\n')
    elif os.environ.get('COMMIT_PROTECTED'):
        p=wt/os.environ['COMMIT_PROTECTED']; p.parent.mkdir(parents=True,exist_ok=True); p.write_text('secret\n')
        subprocess.run(['git','add','-f',os.environ['COMMIT_PROTECTED']],check=True)
        subprocess.run(['git','commit','-qm','fixture: committed protected'],check=True)
    elif os.environ.get('LEAVE_UNCOMMITTED'):
        f.write_text('bad\n' if mode=='build' else 'fixed\n')
        sub=wt/'sub'; sub.mkdir(exist_ok=True); (sub/'added.txt').write_text('added\n')
        (wt/'ignored.tmp').write_text('ignored\n')
        (wt/'notes.md').write_text('Heading\n=======\nBody.\n')
    else:
        f.write_text('bad\n' if mode=='build' else 'fixed\n')
        subprocess.run(['git','add','f.py'],check=True)
        subprocess.run(['git','commit','--allow-empty','-qm','fixture: '+mode],check=True)
    if mode=='build' and os.environ.get('CORRUPT_GITFILE'):
        (wt/'.git').write_text('gitdir: /nonexistent-git-dir\n')
    if mode=='build' and os.environ.get('PLANT_ALTERNATES'):
        gd=subprocess.run(['git','rev-parse','--path-format=absolute','--git-common-dir'],capture_output=True,text=True).stdout.strip()
        alt=pathlib.Path(gd)/'objects/info/alternates'
        alt.parent.mkdir(parents=True,exist_ok=True)
        alt.write_text('/tmp\n')
    hl=os.environ.get('HANDOVER_LINE')
    text=hl if (hl and hl in prompt) else (os.environ.get('BUILD_ANSWER','built') if mode=='build' else 'fixed')
if mode=='review' and os.environ.get('REDIRECT_GITFILE_IN_REVIEW'):
    import shutil
    gd=subprocess.run(['git','rev-parse','--path-format=absolute','--git-common-dir'],capture_output=True,text=True).stdout.strip()
    own=subprocess.run(['git','rev-parse','--path-format=absolute','--absolute-git-dir'],capture_output=True,text=True).stdout.strip()
    evil=wt/'evilcommon'
    shutil.copytree(gd,evil,symlinks=True)
    with open(evil/'info/exclude','a') as fh: fh.write('/evilcommon/\n')
    name=pathlib.Path(own).name
    (evil/'worktrees'/name/'commondir').write_text(str(evil)+'\n')
    (wt/'.git').write_text('gitdir: %s\n' % (evil/'worktrees'/name))
if mode=='review' and os.environ.get('MUTATE_CONFIG_IN_REVIEW'):
    gd=subprocess.run(['git','rev-parse','--path-format=absolute','--git-common-dir'],capture_output=True,text=True).stdout.strip()
    cfg_p=pathlib.Path(gd)/'config'
    cfg_p.write_text(cfg_p.read_text()+'\n[fixture]\nswepthost = 1\n')
if os.environ.get('HOLD_STDOUT'):
    # a tool outside agy's process group keeps stdout open after the turn (the landing review's case)
    subprocess.Popen(['sleep','20'],start_new_session=True,stdin=subprocess.DEVNULL)
if os.environ.get('FENCE_AFTER_BUILD') and mode=='build':
    pathlib.Path(os.environ['CLAUDE_REPOS_JSON']).write_text(json.dumps({'repos':{},'scopes':{'open':{'repos':['*'],'rotation':False}}}))
out({'event':'result','result':{'status':'ERROR' if os.environ.get('FAIL_EXEC') else 'SUCCESS',
     'response':text,'usage':{'input_tokens':10,'output_tokens':5},'num_turns':1}})
'''


class AntigravityTests(unittest.TestCase):
    test_record_first_reply_for_each_reader = VendorTests.test_record_first_reply_for_each_reader
    test_vendor_review_credit_is_opt_in = VendorTests.test_vendor_review_credit_is_opt_in
    test_vendor_handover_carries_evidence_to_owner = VendorTests.test_vendor_handover_carries_evidence_to_owner
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
        self.assertEqual((state['agent'],state['cli'],state['outcome'],state['turns'],state['rounds'],state['launcher_commits']),
                         ('antigravity','agy','clean',2,2,0))
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

    calls = VendorTests.calls
    state = VendorTests.state
    test_uncommitted_turn_is_committed_by_the_launcher = VendorTests.test_uncommitted_turn_is_committed_by_the_launcher
    test_conflict_markers_in_touched_file_are_refused = VendorTests.test_conflict_markers_in_touched_file_are_refused
    test_committed_protected_path_holds_and_is_never_pushed = VendorTests.test_committed_protected_path_holds_and_is_never_pushed
    test_prompt_first_line_privacy_gate_and_step_stamp_rule = VendorTests.test_prompt_first_line_privacy_gate_and_step_stamp_rule
    test_round_cap = VendorTests.test_round_cap
    test_confidential_refused = VendorTests.test_confidential_refused
    test_origin_refused = VendorTests.test_origin_refused

    def test_git_dirs_covers_separate_git_dir_and_common_dir(self):
        from harness_adapters import agy
        common_real = os.path.realpath(self.repo / '.git')
        self.assertEqual(agy.git_dirs(str(self.wt)), [common_real])
        self.assertEqual(agy.git_dirs(str(self.repo)), [], 'primary checkout has .git inside cwd')
        # Move the worktree's own git dir outside --git-common-dir: both roots must be passed as --add-dir.
        moved = self.root / 'separate-wt-git'
        orig_gd = Path(v.git(self.wt, 'rev-parse', '--path-format=absolute', '--git-dir'))
        __import__('shutil').move(str(orig_gd), str(moved))
        (moved / 'commondir').write_text(common_real + '\n')
        (self.wt / '.git').write_text('gitdir: %s\n' % moved)
        self.assertEqual(agy.git_dirs(str(self.wt)), [os.path.realpath(moved), common_real])
        r = self.launch(CLEAN_REVIEWS='1')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
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

    def test_unreadable_git_hook_or_corrupt_gitdir_is_held_without_push(self):
        gd=Path(v.git(self.wt,'rev-parse','--path-format=absolute','--git-common-dir'))
        if os.geteuid() != 0:
            marker=self.root/'hook-marker'
            bad=gd/'hooks/zzz_unreadable'
            pp=gd/'hooks/pre-push'
            try:
                r=self.launch(PLANT_UNREADABLE_HOOK='1',HOOK_MARKER=str(marker))
                self.assertEqual(r.returncode,1,r.stdout+r.stderr)
                state=json.loads(self.record.read_text())
                self.assertEqual(state['outcome'],'held',r.stdout+r.stderr)
                self.assertIn('unreadable',state['end_reason'])
                self.assertFalse(marker.exists(),'planted pre-push must never run after an unreadable hook entry')
                pushed=subprocess.run(['git','-C',str(self.wt),'rev-parse','--verify','-q','refs/remotes/origin/claude/laptop/build'],
                                      capture_output=True,text=True).stdout.strip()
                self.assertNotEqual(pushed,v.git(self.wt,'rev-parse','HEAD'),'nothing pushed after unreadable hook')
            finally:
                if bad.exists(): bad.chmod(0o644); bad.unlink()
                pp.unlink(missing_ok=True)
                (Path(v.git(self.wt,'rev-parse','--absolute-git-dir'))/'claude/owner.json').unlink(missing_ok=True)
                self.record.write_text(json.dumps({'session':'agy-'+self._testMethodName,'repo':str(self.repo),'topic':'build',
                                                   'arm':v.buildercoin.arm_of('argon-high:2:2099-01-01:0')}))
        orig_gitfile=(self.wt/'.git').read_text()
        try:
            r=self.launch(CORRUPT_GITFILE='1')
            self.assertEqual(r.returncode,1,r.stdout+r.stderr)
            state=json.loads(self.record.read_text())
            self.assertEqual(state['outcome'],'held',r.stdout+r.stderr)
            self.assertIn('unreadable',state['end_reason'])
        finally:
            (self.wt/'.git').write_text(orig_gitfile)

    def test_home_preserves_regatta_config_when_unset_in_environ(self):
        u=self.root/'u_prod'
        rcfg=u/'.config/regatta'
        for sub in ('regatta','lighthouse','wharf','wharf-runs'):
            (rcfg/sub).mkdir(parents=True)
        (rcfg/'home').write_text(str(B.parents[2])+'\n')
        (rcfg/'lighthouse/vaults').write_text('VaultA\n')
        (rcfg/'lighthouse/guarded-dirs').write_text(str(rcfg/'lighthouse/secrets')+'\n')
        (rcfg/'wharf/repos.json').write_text(json.dumps({
            'repos':{'vault':{'path':str(u/'projects/vault')}},
            'scopes':{'open':{'repos':['*']},'sec':{'repos':[str(u/'projects/vault')],'confidential':True}}}))
        kc=u/self.f.BUILDER_KC; kc.parent.mkdir(parents=True,exist_ok=True); kc.touch()
        (u/self.f.BUILDER_PW).write_text('a'*32)
        probe=(
            'import json, os, sys\n'
            'sys.path[:0] = [%r, %r, %r]\n'
            'import agybuild, common\n'
            'f = agybuild.codex._fence(); f.SECURITY = %r; agybuild.codex._fence = lambda: f\n'
            'with agybuild.home(%r) as env:\n'
            '    cenv = agybuild.child_env(env)\n'
            '    assert env.get("REGATTA_CONFIG") == str(common.CONFIG), env\n'
            '    assert cenv.get("REGATTA_CONFIG") == str(common.CONFIG), cenv\n'
            '    assert env["HOME"] != %r\n'
            '    r = __import__("subprocess").run([sys.executable, "-c", '
            '"import json, sys; sys.path[:0] = [%r, %r]; import common, secrets_guard; '
            'reg, torn = common.read_registry(); '
            'print(json.dumps([str(common.CONFIG), common.CONFIG.is_dir(), torn, bool(secrets_guard._registry()[0]), secrets_guard.VAULTS, bool(secrets_guard.GUARDED)]))"], '
            'env=cenv, capture_output=True, text=True, check=True)\n'
            '    print(r.stdout.strip())\n'
        ) % (str(B), str(B.parent/'lib'), str(B.parents[1]/'regatta/hooks'), str(self.security),
             str(self.wt), str(u),
             str(B.parents[1]/'regatta/hooks'), str(B.parents[1]/'lighthouse/hooks'))
        p_env=dict(os.environ, HOME=str(u))
        p_env.pop('REGATTA_CONFIG', None)
        p_env.pop('CLAUDE_REPOS_JSON', None)
        r=subprocess.run([sys.executable, '-c', probe], env=p_env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(json.loads(r.stdout.strip()), [str(rcfg), True, False, True, ['VaultA'], True])

    def test_identity_without_accounts_json_uses_real_account_and_vendor_refusal(self):
        accts=v.common.CONFIG/'lighthouse/accounts.json'
        self.assertFalse(accts.exists())
        env=dict(os.environ)
        env.pop('HARNESS_ACCOUNT', None)
        env.pop('ACCOUNTS_FILE', None)
        with patch.dict(os.environ, env, clear=True):
            # an open repo needs no pick on a builder host, which keeps no accounts registry
            self.assertEqual(v.agybuild.identity(self.wt), (None, 'example.invalid'))
            self.assertIsNone(v.agybuild.preflight(self.wt, v.agybuild.MODEL))
            # a confidential repo still fails closed: its text goes only to a login its tenant owns
            Path(os.environ['CLAUDE_REPOS_JSON']).write_text(json.dumps({
                'repos':{},
                'scopes':{'vault':{'repos':[str(self.repo)],'confidential':True}}}))
            with self.assertRaises(v.agybuild.Error):
                v.agybuild.identity(self.wt)
            self.assertTrue(v.agybuild.preflight(self.wt, v.agybuild.MODEL))

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

    def test_a_tool_holding_stdout_does_not_hang_the_turn(self):
        start=time.monotonic()
        with patch.object(v.agybuild,'RESULT_GRACE',2), patch.dict(os.environ,HOLD_STDOUT='1'):
            result=v.turn('antigravity',self.wt,'name: code-reviewer\nhello',review=True,timeout=40)
        self.assertEqual(result['last_answer'],'[]')
        self.assertLess(time.monotonic()-start,25,'the turn ends at its grace, not at the holder\'s exit')

    def test_preflight_allows_models_without_oauth_email_line_and_fresh_timeout_is_90(self):
        self.assertEqual(v.buildercoin.FRESH_TIMEOUT, 90)
        r=self.launch('--preflight', OMIT_MODELS_EMAIL='1')
        self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
        self.assertFalse(self.audit.exists())

    def test_git_trust_allows_maintenance_sweeps_sibling_worktrees_and_locks_while_holding_static_trust(self):
        gd=Path(v.git(self.wt,'rev-parse','--path-format=absolute','--git-common-dir'))
        own=Path(v.git(self.wt,'rev-parse','--path-format=absolute','--absolute-git-dir'))
        t0=v.agybuild.git_trust(self.wt)
        # Normal builder commits, pack-refs and git gc (writing packed-refs, objects/info/packs, commit-graph and
        # info/refs) leave git_trust unchanged.
        (self.wt/'f.py').write_text('step1\n')
        v.git(self.wt,'add','f.py'); v.git(self.wt,'commit','-qm','worktree commit')
        self.assertEqual(v.agybuild.git_trust(self.wt), t0)
        v.git(self.wt,'pack-refs','--all')
        self.assertEqual(v.agybuild.git_trust(self.wt), t0)
        v.git(self.wt,'gc','-q')
        self.assertEqual(v.agybuild.git_trust(self.wt), t0)
        # Host FF sweep on primary checkout and sibling worktree commits leave git_trust unchanged.
        peer=self.root/'peer'
        self.assertEqual(cmd('git','clone','-q',self.root/'origin.git',peer).returncode, 0)
        (peer/'upstream.txt').write_text('ff\n')
        self.assertEqual(cmd('git','-C',peer,'add','upstream.txt').returncode, 0)
        self.assertEqual(cmd('git','-C',peer,'commit','-qm','upstream').returncode, 0)
        self.assertEqual(cmd('git','-C',peer,'push','-q','origin','main').returncode, 0)
        self.git('fetch','-q','origin','main')
        self.git('merge','-q','--ff-only','FETCH_HEAD')
        self.assertEqual(v.agybuild.git_trust(self.wt), t0)
        sib=self.repo/'.claude/worktrees/sib'
        self.git('worktree','add','-b','claude/laptop/sib',sib,'main')
        (sib/'sib.txt').write_text('sib\n')
        v.git(sib,'add','sib.txt'); v.git(sib,'commit','-qm','sibling commit')
        self.assertEqual(v.agybuild.git_trust(self.wt), t0)
        # Live regular *.lock files and transient *.lock entries unlinked between listdir and lstat are ignored.
        lock_file=gd/'info/refs.lock'
        lock_file.parent.mkdir(parents=True, exist_ok=True); lock_file.write_text('lock\n')
        try:
            self.assertEqual(v.agybuild.git_trust(self.wt), t0)
        finally:
            lock_file.unlink(missing_ok=True)
        real_listdir, real_lstat = os.listdir, os.lstat
        hooks_b = os.path.realpath(os.fsencode(gd/'hooks'))
        gone_b = os.path.join(hooks_b, b'gone.lock')
        def listdir_with_lock(p):
            items = real_listdir(p)
            return items + [b'gone.lock'] if os.path.realpath(p) == hooks_b else items
        def lstat_vanished(p, *a, **kw):
            if p == gone_b:
                raise FileNotFoundError(2, 'No such file or directory', p)
            return real_lstat(p, *a, **kw)
        with patch('os.listdir', side_effect=listdir_with_lock), patch('os.lstat', side_effect=lstat_vanished):
            self.assertEqual(v.agybuild.git_trust(self.wt), t0)
        # Static trust targets in common_dir and own (including alternates, http-alternates and own HEAD symref) hold.
        head_oid=v.git(self.wt,'rev-parse','HEAD')
        for target, payload in (
            (gd/'config', (gd/'config').read_text()+'\n[alias]\nx = !true\n'),
            (gd/'hooks/post-checkout', '#!/bin/sh\nexit 0\n'),
            (gd/'info/attributes', '*.py text\n'),
            (gd/'objects/info/alternates', str(self.root)+'\n'),
            (gd/'objects/info/http-alternates', 'http://127.0.0.1/\n'),
            (own/'config', '[core]\n'),
            (own/'config.worktree', '[core]\n'),
            (own/'hooks/post-checkout', '#!/bin/sh\nexit 0\n'),
            (own/'info/attributes', '*.py text\n'),
            (own/'HEAD', 'ref: refs/heads/other\n'),
            (own/'HEAD', head_oid+'\n'),
        ):
            existed=target.exists()
            before_bytes=target.read_bytes() if existed else None
            missing_dirs=[d for d in (target.parent, target.parent.parent) if not d.exists()]
            try:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(payload)
                self.assertNotEqual(v.agybuild.git_trust(self.wt), t0, str(target))
            finally:
                if existed: target.write_bytes(before_bytes)
                else: target.unlink(missing_ok=True)
                for d in missing_dirs:
                    if d.is_dir(): d.rmdir()
            self.assertEqual(v.agybuild.git_trust(self.wt), t0, str(target))
        # Read-only review turns skip git_trust holds when external git config changes during the review.
        orig_cfg=(gd/'config').read_bytes()
        try:
            with patch.dict(os.environ, MUTATE_CONFIG_IN_REVIEW='1'):
                res=v.turn('antigravity', self.wt, 'name: code-reviewer\nhello', review=True)
            self.assertEqual(res['last_answer'], '[]')
        finally:
            (gd/'config').write_bytes(orig_cfg)
        # A reviewer that points wt/.git at a planted git dir is held, as main held it (the landing review).
        orig_gitfile=(self.wt/'.git').read_text()
        try:
            with patch.dict(os.environ, REDIRECT_GITFILE_IN_REVIEW='1'):
                with self.assertRaisesRegex(v.Tainted, 'config or hooks'):
                    v.turn('antigravity', self.wt, 'name: code-reviewer\nhello', review=True)
        finally:
            (self.wt/'.git').write_text(orig_gitfile)
            __import__('shutil').rmtree(self.wt/'evilcommon', ignore_errors=True)
        # End-to-end launch planting objects/info/alternates is held as Tainted and never pushed.
        r=self.launch(PLANT_ALTERNATES='1')
        self.assertEqual(r.returncode, 1, r.stdout+r.stderr)
        state=json.loads(self.record.read_text())
        self.assertEqual(state['outcome'], 'held', r.stdout+r.stderr)
        self.assertIn('config or hooks', state['end_reason'])

    def test_non_utf8_hook_symlink_and_exec_only_hooks_dir_hold_without_push(self):
        gd=Path(v.git(self.wt,'rev-parse','--path-format=absolute','--git-common-dir'))
        hooks=gd/'hooks'
        marker=self.root/'hook-marker-2'
        pp=hooks/'pre-push'
        bad_link=os.fsencode(hooks/'bad_link')
        try:
            r=self.launch(PLANT_BAD_SYMLINK='1', HOOK_MARKER=str(marker))
            self.assertEqual(r.returncode, 1, r.stdout+r.stderr)
            state=json.loads(self.record.read_text())
            self.assertEqual(state['outcome'], 'held', r.stdout+r.stderr)
            self.assertIn('config or hooks', state['end_reason'])
            self.assertFalse(marker.exists(), 'planted pre-push must never execute after non-UTF-8 hook symlink')
        finally:
            with contextlib.suppress(FileNotFoundError): os.unlink(bad_link)
            pp.unlink(missing_ok=True)
            (Path(v.git(self.wt,'rev-parse','--absolute-git-dir'))/'claude/owner.json').unlink(missing_ok=True)
            self.record.write_text(json.dumps({'session':'agy-'+self._testMethodName,'repo':str(self.repo),'topic':'build',
                                               'arm':v.buildercoin.arm_of('argon-high:2:2099-01-01:0')}))
        if os.geteuid() != 0:
            try:
                r=self.launch(PLANT_EXEC_ONLY_HOOKS='1', HOOK_MARKER=str(marker))
                self.assertEqual(r.returncode, 1, r.stdout+r.stderr)
                state=json.loads(self.record.read_text())
                self.assertEqual(state['outcome'], 'held', r.stdout+r.stderr)
                self.assertIn('unreadable', state['end_reason'])
                self.assertFalse(marker.exists(), 'planted pre-push must never execute behind chmod 0o111 hooks/')
            finally:
                if hooks.exists(): hooks.chmod(0o755)
                pp.unlink(missing_ok=True)

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
            self.assertNotIn('_hooks_json', v.agybuild.child_env(home))
            installed = Path(home['GEMINI_CLI_HOME'])/'config/hooks.json'
            # Untampered snapshot refreshes atomically when builder-host's FF sweep runs vendor-hooks apply.
            cfg1 = json.loads(installed.read_text())
            cfg2 = json.loads(json.dumps(cfg1))
            cfg2['regatta']['PreToolUse'][0]['hooks'][0]['timeout'] = 9999
            with patch.object(v.agybuild, 'guards', return_value=cfg2):
                res = v.turn('antigravity', self.wt, 'name: code-reviewer\nhello', review=True, home=home)
            self.assertEqual(res['last_answer'], '[]')
            self.assertEqual(json.loads(installed.read_text()), cfg2)
            self.assertEqual(json.loads(home['_hooks_json']), cfg2)
            # sheep gate run mid-build: its entries reach the box only with the reporting env beside them,
            # else the gate takes the box as its policy home and the rest of the build reports nothing.
            self.assertNotIn('SHEEP_POLICY_HOME', home)
            cfg3 = dict(cfg2, sessionpipe={'enabled': True})
            pins = {'SHEEP_POLICY_HOME': str(self.root), 'XDG_STATE_HOME': str(self.root/'state')}
            seen = []
            def reporting(cfg):
                seen.append(sorted(cfg))
                return dict(pins) if 'sessionpipe' in cfg else {}
            with patch.object(v.agybuild, 'guards', return_value=cfg3), \
                 patch.object(v.agybuild, '_reporting', side_effect=reporting):
                v.turn('antigravity', self.wt, 'name: code-reviewer\nhello', review=True, home=home)
            self.assertEqual(seen, [sorted(cfg3)])
            self.assertEqual(json.loads(installed.read_text()), cfg3)
            self.assertEqual({k: v.agybuild.child_env(home)[k] for k in pins}, pins)
            # Tampering with the per-run hooks.json snapshot still refuses without sending.
            installed.write_text('{}')
            with self.assertRaisesRegex(v.Refused,'per-run guards changed'):
                v.turn('antigravity',self.wt,'hello',home=home)
        # vendor_home with home=None preserves agybuild.Held as Tainted rather than plain Refused.
        with patch.object(v.agybuild, 'turn', side_effect=v.agybuild.Held('held: fixture taint')):
            with self.assertRaises(v.Tainted):
                v.turn('antigravity', self.wt, 'hello', home=None)
        # Brief mid-FF guards() mismatch retries and FOR_NOW classifies persistent vendor-hooks apply mismatches.
        calls = []
        real_once = v.agybuild._guards_once
        def flaky_once():
            calls.append(1)
            if len(calls) == 1:
                raise v.agybuild.Error("agy builder needs regatta's guards alone (vendor-hooks apply)")
            return real_once()
        with patch.object(v.agybuild, 'GUARD_RETRIES', (0.01,)), patch.object(v.agybuild, '_guards_once', side_effect=flaky_once):
            self.assertEqual(v.agybuild.guards(), cfg1)
        self.assertEqual(len(calls), 2)
        launcher = importlib.machinery.SourceFileLoader('agy_for_now_launcher', str(B/'run-vendor')).load_module()
        self.assertTrue(any(w in "agy builder needs regatta's guards alone (vendor-hooks apply)" for w in launcher.FOR_NOW))

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
                         DISPATCH_LABEL='org.example.claude.dispatch.repo.build.202611040000',
                         HEADROOM_SAMPLE='60 0 0',FIRE_FENCE=str(fence_log))
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
