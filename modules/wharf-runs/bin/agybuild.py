"""Antigravity on the vendor launcher's road; the harness adapter owns its argv.

A private per-run home keeps the builder's conversation between turns, and
holds only its vendor sign-in, Regatta guards and, where sheep gate wrote them, its reporting
entries. No model call at pre-flight.
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
import stat
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


def _sheep():
    tool = common.tool("sheep")
    if not tool:
        raise Error("sheep is absent")
    return importlib.machinery.SourceFileLoader("builder_sheep", str(tool)).load_module()


def builder_hooks_ok(cli, cfg, guards):
    """Only our guards and, optionally, the exact entries keel's sheep gate writes.

    Loading the writer also resolves its installed gate and sessionpipe seed. No
    substring command match grants trust to a wrapper or another hook in a group.
    A missing or older keel keeps the guards-only road.
    """
    if cfg == guards:
        return True
    try:
        want = _sheep().builder_hooks(cli)
    except Exception:   # an absent API, unreadable seed or refused shape never widens trust
        return False
    if cli == "antigravity":
        return cfg == dict(guards, **want)
    own = guards["hooks"]["PreToolUse"]
    groups = want["hooks"]["PreToolUse"]
    # vendor-hooks apply and sheep gate may run in either order, each appending its own group.
    return any(cfg == {"hooks": dict(want["hooks"], PreToolUse=order)}
               for order in (own + groups, groups + own))


GUARD_RETRIES = (0.05, 0.1, 0.2, 0.4)   # s: a sweep's fast-forward and its vendor-hooks apply


def _guards_once():
    why = agy._guards_why()
    if why:
        raise Error(why)
    try:
        cfg = json.loads((Path(agy._gemini()) / "config/hooks.json").read_text())
    except (OSError, ValueError) as ex:
        raise Error("agy builder guards do not read (vendor-hooks apply)") from ex
    tool = common.tool("vendor-hooks")
    if not tool:
        raise Error("vendor-hooks is absent")
    vh = importlib.machinery.SourceFileLoader("agy_builder_vendor_hooks", str(tool)).load_module()
    if not builder_hooks_ok("antigravity", cfg, vh.plan_ag({})[0]):
        raise Error("agy builder needs regatta's guards alone or with sheep gate reporting (vendor-hooks apply, then sheep gate)")
    return cfg


def guards():
    for delay in (*GUARD_RETRIES, None):
        try:
            return _guards_once()
        except Error as ex:
            if delay is None or "vendor-hooks apply" not in str(ex):
                raise
            time.sleep(delay)


def _reporting(cfg):
    """Reporting must keep the builder's policy home, sink, outbox and lasting privacy denials,
    rather than resolving their HOME defaults inside the disposable login box."""
    if "sessionpipe" not in cfg:
        return {}
    sheep = None
    try:
        sheep = _sheep()
        return sheep.reporting_env()
    except Error:
        raise
    except Exception as ex:   # a link loop, a half-moved keel: a clean refusal, never a traceback
        if sheep is not None and isinstance(ex, sheep.Refused):
            raise Error(str(ex)) from ex
        raise Error("sheep gate reporting does not resolve: %s" % ex) from ex


@contextlib.contextmanager
def home(wt):
    cfg = guards()
    reporting = _reporting(cfg)
    f = codex._fence()
    # Never use agy_secret's fallback to the owner's login keychain.
    if not (Path.home() / f.BUILDER_KC).is_file():
        raise Error("agy builder keychain is absent")
    box = tempfile.mkdtemp(prefix="agy-build.")
    try:
        env, _, _ = f._home_agy(box)
        h = Path(env["HOME"])
        gemini = h / ".gemini"
        hooks_text = json.dumps(cfg)
        (gemini / "config/hooks.json").write_text(hooks_text)
        (gemini / "GEMINI.md").write_text("Read AGENTS.md and its Traps before editing.\n")
        # the guards inside the turn read the launcher's config dir and registry, never the box's empty HOME's
        env.update(reporting)
        env.update(GEMINI_CLI_HOME=str(gemini),
                   GIT_CONFIG_GLOBAL=os.environ.get("GIT_CONFIG_GLOBAL") or str(Path.home() / ".gitconfig"),
                   REGATTA_CONFIG=os.environ.get("REGATTA_CONFIG") or str(common.CONFIG),
                   _hooks_json=hooks_text)
        if os.environ.get("CLAUDE_REPOS_JSON"):
            env["CLAUDE_REPOS_JSON"] = os.environ["CLAUDE_REPOS_JSON"]
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
    env.update({k: val for k, val in home.items() if not k.startswith("_")},
               REGATTA_UNATTENDED="vendor-build", CLAUDE_UNATTENDED="vendor-build")
    return env


def identity(wt):
    """The tenant's pick (its refusal is the fence's) and the domain agy must be signed in to. A builder-host user
    carries no lighthouse/accounts.json, so vendor_refusal judges the repo there directly. `account pick` prints no
    e-mail, so the address is read from agy itself (signed_in), never from the pick (the landing review)."""
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


def git_trust(wt, review=False):
    """What the launcher's unsandboxed git and check scope trust: static configs, hooks/, info/, objects/info
    alternates, and this worktree's own gitfile, gitdir/commondir links and HEAD symref target. Shared refs,
    packed-refs and pack/graph metadata move on normal commits, gc and host sweeps, so they are not hashed."""
    def rp(*args):
        return subprocess.run(["git", "-C", str(wt), "rev-parse", "--path-format=absolute", *args],
                              capture_output=True, text=True, check=True).stdout.strip()
    try:
        common_dir = os.path.realpath(os.fsencode(rp("--git-common-dir")))
        own = os.path.realpath(os.fsencode(rp("--absolute-git-dir")))
    except (subprocess.CalledProcessError, OSError) as ex:
        raise Error("the worktree's git dir does not read: %s" % ex) from ex
    h = hashlib.sha256()

    def add_entry(tag, b_path):
        h.update(tag + b"\0" + b_path + b"\0")
        try:
            st = os.lstat(b_path)
        except FileNotFoundError:
            h.update(b"-\0")
            return
        mode = st.st_mode
        if stat.S_ISLNK(mode):
            target = os.readlink(b_path)
            h.update((b"L%o:%d:" % (mode & 0o7777, len(target))) + target + b"\0")
        elif stat.S_ISREG(mode):
            with open(b_path, "rb") as fh:
                data = fh.read()
            h.update((b"F%o:%d:" % (mode & 0o7777, len(data))) + data + b"\0")
        elif stat.S_ISDIR(mode):
            h.update(b"D%o\0" % (mode & 0o7777))
        else:
            h.update(b"O%o\0" % mode)

    def add_head(tag, b_path):
        h.update(tag + b"\0" + b_path + b"\0")
        try:
            st = os.lstat(b_path)
        except FileNotFoundError:
            h.update(b"-\0")
            return
        mode = st.st_mode
        if stat.S_ISLNK(mode):
            target = os.readlink(b_path)
            h.update((b"L%o:%d:" % (mode & 0o7777, len(target))) + target + b"\0")
        elif stat.S_ISREG(mode):
            with open(b_path, "rb") as fh:
                data = fh.read(1024)
            stripped = data.strip()
            if stripped.startswith(b"ref:"):
                ref = stripped[4:].strip()
                h.update((b"S:%d:" % len(ref)) + ref + b"\0")
            else:
                h.update((b"H:%d:" % len(stripped)) + stripped + b"\0")
        elif stat.S_ISDIR(mode):
            h.update(b"D%o\0" % (mode & 0o7777))
        else:
            h.update(b"O%o\0" % mode)

    def add_link_only(tag, b_path):
        h.update(tag + b"\0" + b_path + b"\0")
        try:
            st = os.lstat(b_path)
        except FileNotFoundError:
            h.update(b"-\0")
            return
        if stat.S_ISLNK(st.st_mode):
            target = os.readlink(b_path)
            h.update((b"L%o:%d:" % (st.st_mode & 0o7777, len(target))) + target + b"\0")
        elif stat.S_ISDIR(st.st_mode):
            h.update(b"-\0")
        else:
            h.update(b"O%o\0" % st.st_mode)

    def add_tree(tag, root, skip_root_reg=(), fold_empty_dir=False):
        h.update(b"T:" + tag + b"\0" + root + b"\0")
        try:
            st = os.lstat(root)
        except FileNotFoundError:
            h.update(b"-\0")
            return
        if not stat.S_ISDIR(st.st_mode):
            add_entry(b"T-leaf:" + tag, root)
            return

        def collect(cur, is_root):
            cst = os.lstat(cur)
            items = []
            for name in sorted(os.listdir(cur)):
                child = os.path.join(cur, name)
                try:
                    chst = os.lstat(child)
                except FileNotFoundError:
                    if name.endswith(b".lock"):
                        continue
                    raise
                if name.endswith(b".lock") and stat.S_ISREG(chst.st_mode):
                    continue
                if is_root and name in skip_root_reg and stat.S_ISREG(chst.st_mode):
                    continue
                if stat.S_ISDIR(chst.st_mode):
                    items.append((b"D", child, collect(child, False)))
                else:
                    items.append((b"E", child, None))
            return cst.st_mode & 0o7777, items

        root_mode, root_items = collect(root, True)
        if fold_empty_dir and not root_items:
            h.update(b"-\0")
            return

        def emit(cur, mode_bits, items):
            h.update(b"dir:" + cur + (b":%o:%d\0" % (mode_bits, len(items))))
            for kind, child, sub in items:
                if kind == b"D":
                    emit(child, sub[0], sub[1])
                else:
                    add_entry(b"tree:" + tag, child)

        emit(root, root_mode, root_items)

    add_entry(b"wt-git", os.path.join(os.fsencode(os.path.abspath(str(wt))), b".git"))
    # a review turn leaves the common config's content out (a host sweep may write it while a reviewer reads); its
    # path, the gitfile and every other entry still hold a reviewer that redirects `wt/.git` (the landing review)
    if not review:
        add_entry(b"common-config", os.path.join(common_dir, b"config"))
    add_head(b"own-head", os.path.join(own, b"HEAD"))
    for tag, name in ((b"own-config", b"config"), (b"own-config-wt", b"config.worktree"),
                      (b"own-commondir", b"commondir"), (b"own-gitdir", b"gitdir")):
        add_entry(tag, os.path.join(own, name))
    for prefix, base in (((b"common", common_dir),) + (((b"own", own),) if own != common_dir else ())):
        add_tree(prefix + b"-hooks", os.path.join(base, b"hooks"))
        add_tree(prefix + b"-info", os.path.join(base, b"info"), skip_root_reg=(b"refs",), fold_empty_dir=True)
        add_link_only(prefix + b"-objects", os.path.join(base, b"objects"))
        add_link_only(prefix + b"-obj-info", os.path.join(base, b"objects", b"info"))
        add_entry(prefix + b"-alt", os.path.join(base, b"objects", b"info", b"alternates"))
        add_entry(prefix + b"-http-alt", os.path.join(base, b"objects", b"info", b"http-alternates"))
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
    try:
        if installed.is_symlink():
            raise OSError("hooks.json is a symlink")
        installed_cfg = json.loads(installed.read_text())
        expected_cfg = json.loads(home["_hooks_json"]) if "_hooks_json" in home else cfg
    except (OSError, ValueError) as ex:
        raise Error("agy per-run guards changed: nothing sent") from ex
    if installed_cfg != expected_cfg:
        raise Error("agy per-run guards changed: nothing sent")
    if installed_cfg != cfg:
        # sheep gate may have run since home() was made guards-only: its entries need the reporting env too,
        # or the gate reads the box as its policy home and the rest of the build reports nothing.
        if "SHEEP_POLICY_HOME" not in home:
            home.update(_reporting(cfg))
        hooks_text = json.dumps(cfg)
        fd, tmp_hooks = tempfile.mkstemp(prefix=".hooks.", dir=str(installed.parent))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(hooks_text)
            os.replace(tmp_hooks, installed)
        except BaseException:
            with contextlib.suppress(OSError):
                os.unlink(tmp_hooks)
            raise
        home["_hooks_json"] = hooks_text
    else:
        home.setdefault("_hooks_json", json.dumps(cfg))
    _, domain = identity(wt)
    env = child_env(home)
    env["REGATTA_WORKTREE"] = str(wt)
    with tempfile.TemporaryDirectory(prefix="agy-turn.") as tmp:
        log = str(Path(tmp) / "agy.log")
        # a reviewer gets no git dir to write (the landing review): it reads the worktree, and a write it makes
        # anyway is held below; the builder's commits in a linked worktree need `--git-dir` and `--git-common-dir`
        add_dirs = [] if review else agy.git_dirs(str(wt))
        if not review and not add_dirs and (wt / ".git").is_file():
            raise Error("the worktree's git dir does not read")
        argv = agy._argv({"model": model, "effort": effort}, log, None, conversation, add_dirs=add_dirs)
        trust = git_trust(wt, review)
        before = tree_state(wt) if review else None
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
                try:
                    after = git_trust(wt, review)
                except Exception as ex:
                    raise Held("held: the git dir's config or hooks became unreadable after an agy turn") from ex
                if after != trust:
                    raise Held("held: an agy turn changed the git dir's config or hooks")
                if review and tree_state(wt) != before:
                    raise Held("held: an agy reviewer changed the worktree")
