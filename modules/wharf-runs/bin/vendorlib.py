"""Vendor build turns. The launcher owns network steps and the dispatch record;
the CLI owns one conversation. Both vendors share the same launch/review loop.

No Claude process here. Every fire, including a typed model, meets the same
origin and scope gates; every turn and every review repeats them.
"""
import json
import contextlib
import importlib.machinery
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lib"))
import core_path
core_path.require()
import common
import buildercoin
import agybuild
from harness_adapters import codex

MESSAGE_CAP = agybuild.MESSAGE_CAP
MODEL = "gpt-6.1-sol"  # codex debug models --bundled, recorded with S8
CLIS = {"codex": "codex", "antigravity": "agy"}


def model_for(cli):
    return agybuild.MODEL if cli == "antigravity" else MODEL


class Refused(RuntimeError):
    pass


class Held(Refused):
    """A stop no Claude retry may answer: the fence, an origin marker, a builder's own hold. A class, never a word
    in the text: git's stderr names the branch, and a branch may hold any word (the landing review, item 11)."""


class Tainted(Held):
    """A held turn after which the launcher must not run git in the worktree again (a push would run a planted
    pre-push hook, or carry a reviewer's commit): agybuild.Held."""


def git(wt, *args):
    # fsmonitor off: a vendor turn may write the git dir, and this git runs outside its sandbox (agybuild.git_trust)
    r = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", str(wt), *args], capture_output=True, text=True)
    if r.returncode:
        raise Refused("git %s failed: %s" % (args[0], r.stderr.strip()[-800:]))
    return r.stdout.strip()


_HARNESS = []


def _harness():
    """bin/harness, loaded once per process: a reload re-runs its top level and repeats its once-only warnings."""
    if not _HARNESS:
        _HARNESS.append(importlib.machinery.SourceFileLoader("vendor_harness", str(HERE / "harness")).load_module())
    h = _HARNESS[0]
    h.PUBLIC = tuple(h.config_lines("wharf-runs/public-repos"))
    return h


def main_name(wt):
    """The repo's main: the main checkout's workflow.json `main`, else `main` (dispatch's after_merge and
    build-review's base_ref read the same file; a branch's own copy, which a builder can write, never decides)."""
    try:
        primary = Path(git(wt, "rev-parse", "--path-format=absolute", "--git-common-dir")).parent
        m = json.loads((primary / ".claude" / "workflow.json").read_text()).get("main")
    except (Refused, OSError, ValueError, AttributeError):
        return "main"
    return m if isinstance(m, str) and m.strip() else "main"


def scope_named(name, text):
    """At least what the publish gate holds: a name of 5 or more characters anywhere, a shorter one at a token's
    start, where only a letter before it makes no start, as at the gate (so "ops" never holds "stops"; "acme" still
    holds "acmecorp", and "v2acme" too)."""
    n, t = name.casefold(), text.casefold()
    return n in t if len(n) >= 5 else re.search(r"(?<![a-z])" + re.escape(n), t) is not None


def fence(wt, cli, origin="", text=None, paths=False, text_limit=MESSAGE_CAP):
    primary = Path(git(wt, "rev-parse", "--path-format=absolute", "--git-common-dir")).parent
    if origin or os.environ.get("DISPATCH_ORIGIN_MARK"):
        raise Held("an origin marker: no vendor build")
    # A typed harness/model and a coin arm meet the same provider refusal.
    why = common.vendor_refusal(str(wt), cli)
    rotation_why, fields = buildercoin.rotation_gate(str(primary))
    why = why or rotation_why or ("a confidential scope never runs a vendor build" if fields.get("confidential") else None)
    if why:
        raise Held("vendor fence: %s" % why)
    harness = _harness()
    if harness.public_repo(str(primary)):
        raise Held("a public repo: no vendor build")
    tracked = git(wt, "ls-files").splitlines()
    topic = common.branch_topic(git(wt, "branch", "--show-current"))
    if not topic:
        raise Held("cannot read the vendor build's topic")
    if any(Path(p).parent == Path("docs/handoff") and p.endswith(".review")
           and common.branch_topic(Path(p).stem) == topic for p in tracked):
        raise Held("an origin marker in a reviewed brief: no vendor build")
    # The hook-trust / permission bypass trusts only regatta's handler and optional sheep-gated reporting: a project's own .codex/ or
    # .gemini/ (hooks or config the builder could write in one turn and the next would load) never reaches a vendor turn.
    for dot in (".codex", ".gemini"):
        if git(wt, "ls-files", "--", dot) or git(wt, "status", "--porcelain", "--ignored", "--", dot):
            raise Held("vendor fence: the checkout holds a %s/ path" % dot)
    f = codex._fence()
    if paths and f.leave_paths(str(wt)):
        raise Held("vendor fence: checkout holds a protected path")
    if text is not None:
        if len(text.encode("utf-8")) > text_limit:
            raise Refused("vendor message exceeds %d KB" % (text_limit // 1024))   # the design's `failed`: nothing was sent, a retry may do better
        if f.leave_text(text):
            raise Held("vendor verdict holds a credential shape")
        reg, bad = common.read_registry()
        if bad:
            raise Held("scope registry does not read")
        for name, scope in ((reg or {}).get("scopes") or {}).items():
            if isinstance(scope, dict) and scope.get("confidential") is True and name and scope_named(name, text):
                raise Held("vendor verdict holds a confidential scope name")


def preflight(cli, model=None, effort="high", wt=None, review=False):
    """No model call. Only a configured builder user starts a vendor build.
    A missing login/catalog/model is a pre-flight fallback, never a vendor failure.
    """
    model = model or model_for(cli)
    only, bad = common.config_read("wharf-runs/only")
    feature = CLIS[cli]
    allowed = {x.strip() for l in (only or []) for x in l.split(",")}
    if bad or not (allowed.intersection(CLIS.values()) if review else feature in allowed):
        return "no %s builder user configured here (wharf-runs/only)" % cli
    if feature not in features_here():
        return "no %s feature declared on this builder host" % feature
    if cli == "antigravity":
        return agybuild.preflight(wt, model)
    why = codex_guards()
    if why:
        return why
    exe = shutil.which(codex._bin())
    if not exe:
        return "codex is not installed"
    try:
        r = subprocess.run([exe, "login", "status"], capture_output=True, timeout=30)
        if r.returncode:
            return "codex is not signed in"
        cache = Path(codex._codex_home()) / "models_cache.json"
        if cache.is_file():
            catalog = json.loads(cache.read_text())
        else:
            r = subprocess.run([exe, "debug", "models", "--bundled"], capture_output=True, text=True, timeout=30)
            if r.returncode:
                return "codex model catalog did not read"
            catalog = json.loads(r.stdout)
        models = catalog.get("models", [])
        match = next((m for m in models if m.get("slug") == model), None)
        if match is None:
            return "codex model %s is absent from its catalog" % model
        if effort not in [x.get("effort") for x in match.get("supported_reasoning_levels", [])]:
            return "codex model %s does not list effort %s" % (model, effort)
    except (OSError, ValueError, AttributeError, TypeError, subprocess.TimeoutExpired):
        return "codex login or model catalog did not read"
    return None


def codex_guards():
    """Only the known regatta handler and sheep-gated reporting are trusted headlessly. A builder home
    with a missing, disabled, changed or foreign PreToolUse handler is not ready.
    """
    tool = common.tool("vendor-hooks")
    if not tool:
        return "vendor-hooks is absent"
    try:
        vh = importlib.machinery.SourceFileLoader("builder_vendor_hooks", str(tool)).load_module()
        if not vh.adapter_ok():
            return "codex guard adapter is absent or outdated"
        path = Path(codex._codex_home()) / "hooks.json"
        cfg = json.loads(path.read_text())
        want = [{"matcher": "", "hooks": [vh.handler("codex")]}]
        guards_only = {"hooks": {"PreToolUse": want}}
        if not agybuild.builder_hooks_ok("codex", {"hooks": cfg.get("hooks")}, guards_only):
            return "codex builder needs regatta's guards alone or with sheep gate reporting (vendor-hooks apply, then sheep gate)"
        # A sheep gate refused over an ungated notify still leaves its hooks.json written, which the check above
        # trusts: the notify itself is judged by keel's own reader, and a reporting home whose reader will not
        # load refuses (a guards-only home keeps main's road).
        try:
            notify = agybuild._sheep().codex_notify(path)
        except Exception:
            if {"hooks": cfg.get("hooks")} != guards_only:
                return "codex builder's reporting does not read (keel's sheep will not load)"
            notify = False
        if notify:
            return "codex builder's config.toml runs sessionpipe's notify ungated (remove it, then sheep gate)"
    except (OSError, ValueError, AttributeError, TypeError):
        return "codex builder guards do not read (vendor-hooks apply)"
    return None


def features_here():
    rows, bad = common.config_read("wharf-runs/features")
    if bad:
        raise Refused("the builder features file does not read")  # FOR_NOW's words: a wait, never for good
    host = os.environ.get("DISPATCH_HOST") or common.host_name()
    features, last = set(), None
    for line in rows or []:
        h, sep, names = line.partition(":")
        if sep:
            last = h.strip().lower()
        else:
            names = line  # bootstrap's one word per line continues the host
        if last == host.lower():
            features.update(n.strip().lower() for n in names.split(","))
    return features


def reviewer_cli(builder):
    """Cross-vendor where declared; an unavailable second road holds the loop."""
    features = features_here()
    other = "antigravity" if builder == "codex" else "codex"
    return other if CLIS[other] in features else builder


@contextlib.contextmanager
def vendor_home(cli, wt):
    try:
        with agybuild.home(wt) if cli == "antigravity" else contextlib.nullcontext(None) as home:
            yield home
    except agybuild.Held as ex:
        raise Tainted(str(ex)) from ex
    except agybuild.Error as ex:
        raise Refused(str(ex)) from ex


def turn(cli, wt, prompt, *, model=None, effort="high", conversation=None,
         review=False, origin="", on_pid=None, on_thread=None, on_usage=None, timeout=7200, home=None):
    model = model or model_for(cli)
    # Repeat the path scan after the launcher's merge, and for reviews/fixes:
    # the tree may have gained a protected file since the first pre-flight.
    fence(wt, cli, origin, prompt, paths=True)
    if conversation and review:
        raise Refused("a reviewer always starts a fresh conversation")
    if cli == "antigravity":
        try:
            with vendor_home(cli, wt) if home is None else contextlib.nullcontext(home) as agy_home:
                return agybuild.turn(wt, prompt, model=model, effort=effort, conversation=conversation,
                                     home=agy_home, on_pid=on_pid, on_thread=on_thread, on_usage=on_usage, timeout=timeout,
                                     review=review)
        except agybuild.Held as ex:
            raise Tainted(str(ex)) from ex
        except agybuild.Error as ex:
            raise Refused(str(ex)) from ex
    why = codex_guards()
    if why:
        raise Refused(why)
    with tempfile.TemporaryDirectory(prefix="vendor-turn.") as scratch:
        # A review is a plain exec under the read-only rewrite below, never `codex exec review`: review mode ignores
        # the format it is given and writes its own "Review comment: - [P1] ..." text, which no parser here reads
        # (probed on codex-cli 0.166.0, the landing review, 2026-11-05).
        sub = ["resume", conversation] if conversation else []
        argv = codex._argv({"model": model, "effort": effort}, str(wt), sub, scratch=scratch)
        # The exact generated handler was vetted above. This flag trusts hooks,
        # while --approve-for-me and regatta-fence still govern tool permissions.
        argv[2:2] = ["--dangerously-bypass-hook-trust", "--enable", "hooks"]
        if review:
            key = codex._toml_str(os.path.realpath(wt))
            argv = [arg.replace(key + '="write"', key + '="read"')
                    if arg.startswith("permissions.regatta-fence.filesystem=") else arg for arg in argv]
            # `:workspace` grants the cwd whatever the entry above says, and -C is the worktree: the base profile
            # must change too, or the reviewer writes it (`codex sandbox`, 0.166.0, the landing review)
            argv = ['permissions.regatta-fence.extends=":read-only"' if arg == 'permissions.regatta-fence.extends=":workspace"'
                    else arg for arg in argv]
        env = codex.child_env(scratch)
        # A CLI must never inherit a fired job or a dispatch session identity.
        for k in list(env):
            # the depth child_env just raised stays: harness and dispatch stop a chain by it
            if (k.startswith("DISPATCH_") and k not in ("DISPATCH_DEPTH", "DISPATCH_MAX_DEPTH")) \
                    or k in ("CLAUDE_CODE_SESSION_ID", "CLAUDECODE"):
                env.pop(k, None)
        env.update(REGATTA_UNATTENDED="vendor-build", CLAUDE_UNATTENDED="vendor-build", REGATTA_WORKTREE=str(wt))
        with tempfile.TemporaryFile(mode="w+") as err:
            p = subprocess.Popen(argv, cwd=str(wt), env=env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=err, text=True)
            if on_pid:
                on_pid(p.pid)
            try:
                output, _ = p.communicate(prompt, timeout=timeout() if callable(timeout) else timeout)
            except BaseException:
                p.terminate()
                try:
                    p.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    p.kill(); p.wait()
                raise
            err.seek(0)
            stderr = err.read()[-300:].strip()
        result = {"conversation": conversation, "last_answer": "", "cost": {"openai": {},
                  "anthropic": {"input_tokens": 0, "output_tokens": 0}}, "turns": 1}
        completed = failed = False
        reason = ""
        for line in output.splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            kind = event.get("type")
            if kind == "thread.started":
                result["conversation"] = event.get("thread_id")
                if on_thread:
                    on_thread(result["conversation"])
            elif kind == "item.completed" and (event.get("item") or {}).get("type") == "agent_message":
                result["last_answer"] = event["item"].get("text", "")
            elif kind == "turn.completed":
                completed = True
                result["cost"]["openai"] = codex._add_usage(result["cost"]["openai"], event.get("usage") or {})
            elif kind in ("error", "turn.failed"):
                # an `error` alone is a blip Codex retries past ("Reconnecting... 1/2"): exhausted, it ends turn.failed
                failed = failed or kind == "turn.failed"
                inner = event.get("error")
                reason = (inner.get("message") if isinstance(inner, dict) else inner) or event.get("message") or reason
        if on_usage:
            on_usage(result["cost"])
        if failed or p.returncode or not completed or not result["conversation"] or not result["last_answer"]:
            # the vendor's own words: a plan's usage limit must not read as a crash
            detail = reason or stderr
            raise Refused("codex turn ended without a successful result (exit %s)%s"
                          % (p.returncode, ": " + detail[-300:] if detail else ""))
        return result


def add_cost(total, cost):
    for provider, usage in cost.items():
        total[provider] = codex._add_usage(total.get(provider, {}), usage)


def save(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".%d.tmp" % os.getpid())
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(tmp, path)
