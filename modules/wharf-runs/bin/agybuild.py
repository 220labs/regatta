"""Antigravity on the vendor launcher's road; the harness adapter owns its argv.

A private per-run home keeps the builder's conversation between turns, and
holds only its vendor sign-in and Regatta guards. No model call at pre-flight.
"""
import contextlib
import hashlib
import importlib.machinery
import json
import os
from pathlib import Path
import re
import queue
import signal
import subprocess
import tempfile
import threading
import time

from harness_adapters import agy, codex
import common

MODEL = "gemini-4-argon-high"
MESSAGE_CAP = 64 * 1024
RESULT_GRACE = 10   # s: after the result event, how long the turn waits for agy's stdout to close


class Error(RuntimeError):
    pass


class Held(Error):
    """A turn that changed what the launcher's own git trusts, or a reviewer that wrote: no retry answers it, and the
    launcher runs no more git in that worktree (vendorlib.Tainted: no push, no review record)."""


def guards():
    why = agy._guards_why()
    if why:
        raise Error(why)
    cfg = json.loads((Path(agy._gemini()) / "config/hooks.json").read_text())
    tool = common.tool("vendor-hooks")
    if not tool:
        raise Error("vendor-hooks is absent")
    vh = importlib.machinery.SourceFileLoader("agy_builder_vendor_hooks", str(tool)).load_module()
    if cfg != vh.plan_ag({})[0]:
        raise Error("agy builder needs regatta's guards alone (vendor-hooks apply)")
    return cfg


@contextlib.contextmanager
def home(wt):
    cfg = guards()
    f = codex._fence()
    # Never use agy_secret's fallback to the owner's login keychain.
    if not (Path.home() / f.BUILDER_KC).is_file():
        raise Error("agy builder keychain is absent")
    box = tempfile.mkdtemp(prefix="agy-build.")
    try:
        env, _, _ = f._home_agy(box)
        h = Path(env["HOME"])
        gemini = h / ".gemini"
        (gemini / "config/hooks.json").write_text(json.dumps(cfg))
        (gemini / "GEMINI.md").write_text("Read %s/AGENTS.md and its Traps before editing.\n" % wt)
        # the guards inside the turn read the launcher's config dir and registry, never the box's empty HOME's
        env.update(REGATTA_CONFIG=str(common.CONFIG))
        if os.environ.get("CLAUDE_REPOS_JSON"):
            env["CLAUDE_REPOS_JSON"] = os.environ["CLAUDE_REPOS_JSON"]
        env.update(GEMINI_CLI_HOME=str(gemini),
                   GIT_CONFIG_GLOBAL=os.environ.get("GIT_CONFIG_GLOBAL") or str(Path.home() / ".gitconfig"))
        yield env
    except f.FenceError as ex:
        raise Error(str(ex)) from ex
    finally:
        f.drop_box(box)


def child_env(home):
    env = agy._child_env()
    for key in list(env):
        # the depth _child_env just raised stays: harness and dispatch stop a chain by it
        if (key.startswith("DISPATCH_") and key not in ("DISPATCH_DEPTH", "DISPATCH_MAX_DEPTH")) or key == "CODEX_HOME":
            env.pop(key, None)
    env.update(home, REGATTA_UNATTENDED="vendor-build", CLAUDE_UNATTENDED="vendor-build")
    return env


def identity(wt):
    """The tenant's pick (its refusal is the fence's) and the domain agy must be signed in to. `account pick`
    prints no e-mail, so the address is read from agy itself (signed_in), never from the pick (the landing review)."""
    class Context:
        def fail(self, why, code):
            raise Error(why)
    # an open repo needs no pick: vendorlib.fence already ran vendor_refusal, and a builder host keeps no accounts
    # registry (builder-host's KEYS), where the pick exits 4; a fenced repo's text still goes only to a login its
    # tenant owns (agy._pick's rule)
    account = agy._pick(Context(), {"repo": str(wt)}, str(wt))[0] if agy._fenced_why(str(wt)) else None
    domain = "".join(agy._config_first("wharf-runs/agy-domain").split()).lower()
    if not domain:
        raise Error("wharf-runs/agy-domain is not set")
    return account, domain


def signed_in(who, domain):
    return bool(who) and who.rpartition("@")[2].lower() == domain


def git_trust(wt):
    """What the launcher's unsandboxed git runs from: the common dir's config and hooks/, and the worktree's own
    config. --add-dir grants the sandboxed turn writes there, so a change is held before any launcher git runs."""
    def rp(*args):
        return subprocess.run(["git", "-C", str(wt), "rev-parse", "--path-format=absolute", *args],
                              capture_output=True, text=True, check=True).stdout.strip()
    try:
        common_dir, own = Path(rp("--git-common-dir")), Path(rp("--absolute-git-dir"))
    except (subprocess.CalledProcessError, OSError) as ex:
        raise Error("the worktree's git dir does not read: %s" % ex) from ex
    paths = [common_dir / "config", own / "config", own / "config.worktree"]
    hooks = common_dir / "hooks"
    if hooks.is_dir():
        paths += sorted(x for x in hooks.rglob("*"))
    h = hashlib.sha256()
    for x in paths:
        h.update(str(x).encode() + b"\0")
        if x.is_symlink():
            h.update(b"L" + os.readlink(x).encode())
        elif x.is_file():
            h.update(b"F%o" % (x.stat().st_mode & 0o7777) + x.read_bytes())
        elif x.exists():
            h.update(b"D")
        h.update(b"\0")
    return h.hexdigest()


def tree_state(wt):
    return [subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", str(wt), *a], capture_output=True,
                           text=True).stdout for a in (["rev-parse", "HEAD"], ["status", "--porcelain"])]


def preflight(wt, model):
    if not model.startswith("gemini-"):
        return "agy builder requires a Gemini model"
    try:
        why = agy.sandbox_flag()
        if why:
            return why
        _, domain = identity(wt)
        with home(wt) as env, tempfile.TemporaryDirectory(prefix="agy-models.") as tmp:
            log = str(Path(tmp) / "models.log")
            r = subprocess.run([agy.exe(), "--log-file", log, "models"], env=child_env(env),
                               stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
            if r.returncode or model not in re.findall(r"[\w.-]+", r.stdout):
                return "agy requested model is absent from its catalog"
            # refused on an address of another domain; `models` writing no address at all is not on record either
            # way, so then the turn's init check (proven in print mode) decides, before anything is sent
            who = agy._who(log, 5)
            if who and not signed_in(who, domain):
                return "agy native sign-in does not match wharf-runs/agy-domain"
    except (Error, OSError, ValueError, subprocess.TimeoutExpired) as ex:
        return "agy pre-flight: %s" % ex
    return None


def turn(wt, prompt, *, model, effort, conversation, home, on_pid, on_thread, on_usage, timeout, review=False):
    message = json.dumps({"event": "user", "message": {"role": "user", "content": prompt}}, ensure_ascii=False) + "\n"
    if len(message.encode("utf-8")) > MESSAGE_CAP:
        raise Error("agy message exceeds 64 KB: nothing sent")
    cfg = guards()  # repeated: the builder's hooks may have changed since pre-flight
    installed = Path(home["GEMINI_CLI_HOME"]) / "config/hooks.json"
    if json.loads(installed.read_text()) != cfg:
        raise Error("agy per-run guards changed: nothing sent")
    _, domain = identity(wt)
    env = child_env(home)
    env["REGATTA_WORKTREE"] = str(wt)
    with tempfile.TemporaryDirectory(prefix="agy-turn.") as tmp:
        log = str(Path(tmp) / "agy.log")
        gd = subprocess.run(["git", "-C", str(wt), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                            capture_output=True, text=True, check=True).stdout.strip()
        # a reviewer gets no git dir to write (the landing review): it reads the worktree, and a write it makes
        # anyway is held below; the builder's commits in a linked worktree need the common dir
        argv = agy._argv({"model": model, "effort": effort}, log, None, conversation, add_dirs=[] if review else [gd])
        trust, before = git_trust(wt), tree_state(wt) if review else None
        with tempfile.TemporaryFile(mode="w+") as err:
            p = subprocess.Popen(argv, cwd=str(wt), env=env, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=err, text=True, encoding="utf-8", errors="replace",
                                 start_new_session=True)
            try:
                if on_pid:
                    on_pid(p.pid)
                # Read init before sending bytes: authenticate the native login
                # before the first message, as the harness adapter does.
                events = queue.Queue()
                def read():
                    for line in p.stdout:
                        events.put(line)
                    events.put(None)
                reader = threading.Thread(target=read, daemon=True)
                reader.start()
                until = time.monotonic() + (timeout() if callable(timeout) else timeout)
                init_until = min(until, time.monotonic() + agy._init_wait())
                sent, thread, answer, result = False, None, "", None
                while True:
                    left = (until if sent else init_until) - time.monotonic()
                    if left <= 0 and result is not None:
                        break   # the turn answered; a tool outside the group may hold stdout open (the finally kills)
                    if left <= 0:
                        raise Error("agy turn timed out" if sent else "agy printed no init: nothing sent")
                    try:
                        line = events.get(timeout=left)
                    except queue.Empty:
                        if result is not None:
                            break
                        raise Error("agy turn timed out" if sent else "agy printed no init: nothing sent")
                    if line is None:
                        break
                    try:
                        event = json.loads(line)
                    except ValueError:
                        continue
                    if not isinstance(event, dict):
                        continue
                    if event.get("event") == "init" and not sent:
                        thread = event.get("conversation_id")
                        if not thread or (conversation and thread != conversation):
                            raise Error("agy conversation changed on resume")
                        if not signed_in(agy._who(log, min(5, max(0, left))), domain):
                            raise Error("agy native sign-in does not match wharf-runs/agy-domain: nothing sent")
                        if on_thread:
                            on_thread(thread)
                        p.stdin.write(message)
                        p.stdin.close()
                        sent = True
                    elif event.get("event") == "result":
                        result = event.get("result") or {}
                        if not isinstance(result, dict):
                            raise Error("agy returned a malformed result")
                        answer = result.get("response") or ""
                        until = min(until, time.monotonic() + RESULT_GRACE)
                try:
                    p.wait(timeout=max(.01, until - time.monotonic()))
                except subprocess.TimeoutExpired:
                    if result is None:
                        raise Error("agy turn timed out")
                err.seek(0)
                stderr = err.read()[-300:].strip()
                cost = {"google": (result or {}).get("usage") or {},
                        "anthropic": {"input_tokens": 0, "output_tokens": 0}}
                if on_usage:
                    on_usage(cost)
                if (not sent or p.returncode or not result or result.get("status") != "SUCCESS" or not answer
                        or result.get("truncated") or result.get("input_truncated") or result.get("denied_actions")):
                    # the vendor's own words: a plan's usage limit must not read as a crash
                    detail = str((result or {}).get("error") or stderr).strip()
                    raise Error("agy turn ended without a successful result (exit %s)%s"
                                % (p.returncode, ": " + detail[-300:] if detail else ""))
                return {"conversation": thread, "last_answer": answer, "cost": cost, "turns": 1}
            finally:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(p.pid, signal.SIGTERM)
                if p.poll() is None:
                    try:
                        p.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(p.pid, signal.SIGKILL); p.wait()
                # A tool may outlive an exited CLI and still hold stdout open.
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(p.pid, signal.SIGKILL)
                if p.stdin and not p.stdin.closed:
                    p.stdin.close()
                if 'reader' in locals():
                    reader.join(timeout=2)
                # a holder outside the group (setsid) keeps the reader in readline, and close() would wait on its
                # lock until that holder exits: then the daemon thread keeps the pipe (the landing review's probe)
                if 'reader' not in locals() or not reader.is_alive():
                    p.stdout.close()
                # after the process group is gone and before any launcher git: a held turn overrides its own result
                if git_trust(wt) != trust:
                    raise Held("held: an agy turn changed the git dir's config or hooks")
                if review and tree_state(wt) != before:
                    raise Held("held: an agy reviewer changed the worktree")
