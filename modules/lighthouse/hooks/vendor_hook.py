#!/usr/bin/env python3
"""vendor_hook — a Claude Code PreToolUse guard, run unchanged inside another CLI's own hooks. Stdlib, Python 3.9.

    python3 <lighthouse>/hooks/vendor_hook.py <cli> <guard.py>     the guard's decision, in <cli>'s words
    python3 <lighthouse>/hooks/vendor_hook.py <cli> trailer        a `git commit` gains the CLI's Co-Authored-By

`<cli>` is `codex` (Codex's ~/.codex/hooks.json) or `antigravity` (its ~/.gemini/config/hooks.json);
bin/vendor-hooks writes one entry per guard into each. Why (the owner's D2-A, 2026-10-29,
docs/codex-agy-gaps-2026-10-29.md): one rule set, each CLI's own socket — so the decision code stays the
guard's alone, never a copy, and this file only translates. One adapter per payload shape:

- In: the CLI's PreToolUse stdin becomes one Claude-shaped payload per thing the call touches
  (`hook_event_name`, `tool_name`, `tool_input`, `cwd`, `session_id`, and `regatta_cli`, which the
  checkpoint hook reads to judge a vendor's call by its gates alone, without the worktree lock).
  - Codex (its hook schema, codex-cli 0.162's embedded `pre-tool-use.command.input`; the hooks docs):
    `tool_name` `Bash` (or its unified-exec names) with `tool_input.command` (or `cmd`) and an optional
    `workdir`. A command is a string, or an argv list: `["bash", "-lc", "<script>"]` (any of SHELLS, any
    flag cluster ending in `c`) is judged as the script itself, since the guards read shell text and a
    joined argv hides it in quotes; any other list is joined as the shell would read it. `write_stdin`'s
    `chars` (text typed into a running shell) is judged as a command too. `apply_patch` with the patch in `tool_input.command`, one Write per `*** Add File:` or
    `*** Move to:`, one Edit per `*** Update File:` or `*** Delete File:`; a Claude tool name passes as it
    is. MCP tools and the rest touch nothing a guard reads: no payload, so they pass.
  - Antigravity (its hooks docs; tool names read from this Mac's sessionpipe outbox and the agy binary,
    2026-10-29, which disagree with the docs, so both are taken): `toolCall.name` and `toolCall.args`,
    PascalCase. `run_command` (`CommandLine`, `Cwd`) → Bash, and `send_command_input`/`write_stdin` (text
    typed into a running command) → Bash of each text argument; the readers (`view_file`, `read_file`,
    `view_code_item`, `view_file_outline`, `view_content_chunk`, `read_url_content` for a `file:` URL,
    `read_terminal`) → one Read per path-like argument; `write_to_file`/`write_file`/`create_file` → Write;
    `replace_file_content`/`multi_replace_file_content`/`edit_file`/`delete_file` → Edit; `list_dir`/
    `find_by_name` → Glob; `grep_search`/`codebase_search`/`code_search` → Grep. A path-like argument is
    one whose value is absolute, `~`-led or a `file:` URI, or whose key names a path (AG_PATH_KEYS), a list's
    items included: the agy binary's schemas are not all readable, so no tool is trusted to one key name.
    `read_terminal` carries no path today (it reads a terminal a guarded command wrote to); it is listed so
    one would be judged. The cwd is `Cwd`, else the first of `workspacePaths`, else this process's.
- Out: a guard's `permissionDecision: deny` (or its exit 2, stderr the reason) is the CLI's deny. Codex
  takes Claude's own shape (its `pre-tool-use.command.output`), so the reason passes as it is; an allow
  prints nothing. Antigravity reads stdout as its answer and takes anything but JSON as a deny
  (sessionpipe's adapters/antigravity.ts), so it gets exactly one JSON object on every path: `{}` to
  carry on, `{"decision": "deny", "reason": …}` to refuse.
- `trailer` (F12): Claude Code adds its own Co-Authored-By; nothing did for the others. A Bash call whose
  whole command is one simple `git commit` (simple_commit: no operator, substitution, heredoc or newline,
  so nothing else rides along) with no Co-Authored-By in it gains `--trailer 'Co-Authored-By: <CLI> <model>
  <noreply@vendor>'`, the model read from the payload (`model`, `modelName`), through the CLI's input
  rewrite. Antigravity's is `overwrite`, sent without a `decision` so its own permission flow is unchanged
  (its embedded hook docs list `decision` as required, yet it takes `{}` as carry on; not probed live: a
  probe needs a model call). Codex 0.162.1 refuses `updatedInput` without `permissionDecision: allow` (its
  binary's "PreToolUse hook returned updatedInput without permissionDecision:allow"), so its rewrite is an
  allow: given only to that one simple commit, and only once both guards pass the rewritten command
  (decide), so the allow never carries a command a guard would refuse.

Fails open, as the guards do: a crash, a guard that times out or prints no JSON lets the call through
(Codex itself continues past a failed hook: its docs). Every guard run of one call shares BUDGET seconds,
under the entry's 30 s timeout (an apply_patch of many files would otherwise outlive it and be killed
mid-judgement); past it the rest is not judged, said on stderr. A call this cannot translate is not judged —
tests/parity.sh is what shows such a gap, as a red row. Tests: tests/parity.sh.
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time
import urllib.parse

BUDGET = 25   # seconds for every guard run of one call together; each entry's own timeout is 30 (bin/vendor-hooks)
try:   # a suite shortens it (tests/parity.sh); never longer
    BUDGET = min(BUDGET, float(os.environ.get("VENDOR_HOOK_BUDGET") or BUDGET))
except ValueError:
    pass
HERE = os.path.dirname(os.path.abspath(__file__))
# the guards a trailer's allow must pass first: the same two the other entries run (bin/vendor-hooks' guards())
TRAILER_GUARDS = (os.path.join(HERE, "secrets_guard.py"),
                  os.path.join(os.path.dirname(os.path.dirname(HERE)), "wharf", "hooks", "checkpoint.py"))
CLIS = ("codex", "antigravity")
# (the trailer's name, its address): who a commit made in that CLI is co-authored by
VENDORS = {"codex": ("Codex", "noreply@openai.com"), "antigravity": ("Antigravity", "noreply@google.com")}

CODEX_SHELL = {"Bash", "exec_command", "shell", "local_shell", "unified_exec"}
CODEX_STDIN = {"write_stdin"}   # unified exec: text typed into a running shell (`chars`)
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
CLAUDE_TOOLS = {"Bash", "Read", "Write", "Edit", "MultiEdit", "NotebookEdit", "Grep", "Glob"}
AG_TOOLS = {   # Antigravity's tool → Claude's
    "run_command": "Bash",
    "send_command_input": "Stdin", "write_stdin": "Stdin",
    "view_file": "Read", "read_file": "Read", "view_code_item": "Read", "view_file_outline": "Read",
    "view_content_chunk": "Read", "read_url_content": "Read", "read_terminal": "Read",
    "write_to_file": "Write", "write_file": "Write", "create_file": "Write",
    "replace_file_content": "Edit", "multi_replace_file_content": "Edit", "edit_file": "Edit", "delete_file": "Edit",
    "list_dir": "Glob", "find_by_name": "Glob",
    "grep_search": "Grep", "codebase_search": "Grep", "code_search": "Grep",
}
# keys whose value is a path even when relative; any other key counts only for an absolute, ~ or file: value
AG_PATH_KEYS = {"AbsolutePath", "TargetFile", "Path", "FilePath", "File", "DirectoryPath", "SearchDirectory",
                "SearchPath", "Directory", "TargetDirectories", "Url", "Uri", "Paths", "Files",
                # the snake_case tools' own (`write_file`, `edit_file`, `read_file`; the finish review, 2026-10-31)
                "file_path", "path", "absolute_path", "target_file", "directory", "dir_path", "paths"}
# keys that hold text, never a path, however it starts (a file's new content may begin with `/`)
AG_TEXT_KEYS = {"CodeContent", "ReplacementContent", "TargetContent", "Instruction", "Query", "Pattern",
                "Description", "explanation", "ReplacementChunks", "CodeMarkdownLanguage", "Includes", "Excludes",
                "content", "new_string", "old_string", "new_content", "old_content", "text", "query", "pattern",
                "instruction", "description", "CodeEdit"}
AG_STDIN_SKIP = {"CommandId", "ProcessID", "ProcessId", "Name", "WaitMs", "WaitMsBeforeAsync", "SafeToAutoRun",
                 "explanation", "Terminate", "SessionId", "session_id", "yield_time_ms", "max_output_tokens"}
PATCH_FILE = re.compile(r"^\*\*\* (Add File|Update File|Delete File|Move to): (.+?)\s*$", re.M)
# `git commit` at the start of a command, global options allowed: where the trailer goes (simple_commit)
COMMIT_RE = re.compile(r"^(\s*git(?:\s+(?:-C\s+\S+|-c\s+\S+|--git-dir(?:=|\s+)\S+"
                       r"|--work-tree(?:=|\s+)\S+|--no-pager))*\s+commit)(?=\s|$)")


def shell_script(v):
    """The index of the script in an argv list `[<sh>, <flags…c>, <script>, …]` (SHELLS, any path; the last
    flag cluster ending in `c`, as `-c`, `-lc`, `-ec`), or None."""
    if not (isinstance(v, list) and len(v) >= 3 and all(isinstance(x, str) for x in v)):
        return None
    if os.path.basename(v[0]) not in SHELLS:
        return None
    i = 1
    while i < len(v) and re.match(r"^-[A-Za-z]+$", v[i]):
        if v[i].endswith("c"):
            return i + 1 if i + 1 < len(v) else None
        i += 1
    return None


def _text(v):
    """A command as the guards read it: a string as it is; an argv list that runs a shell script, the script
    (shlex.join would quote it whole, and no guard looks inside a quoted word); another list joined."""
    if isinstance(v, str):
        return v
    i = shell_script(v)
    if i is not None:
        return v[i]
    if isinstance(v, list) and all(isinstance(x, str) for x in v):
        return shlex.join(v)
    return ""


def _abs(p, cwd):
    p = os.path.expanduser(p)
    return p if os.path.isabs(p) else os.path.join(cwd, p)


def workspace_paths(value):
    """Antigravity's workspacePaths as absolute local paths: a file:// URI decoded, a plain absolute path
    kept, a remote URI or a relative one left out (keel's sheep_gate reads them the same way)."""
    out = []
    for p in value if isinstance(value, list) else []:
        if not isinstance(p, str) or not p:
            continue
        if p[:5].lower() == "file:":
            p = urllib.parse.unquote(urllib.parse.urlparse(p).path)
        elif re.match(r"^[a-z][a-z0-9+.-]*://", p, re.I):
            continue
        if os.path.isabs(p) and p not in out:
            out.append(p)
    return out


def patch_calls(text, cwd):
    """[(Claude tool, absolute path)] for each file an apply_patch body adds, moves to, updates or deletes."""
    out = []
    for kind, path in PATCH_FILE.findall(text or ""):
        out.append(("Write" if kind in ("Add File", "Move to") else "Edit", _abs(path, cwd)))
    return out


def codex_calls(ev):
    """Codex's PreToolUse payload → [(Claude tool, tool_input, cwd)]."""
    name, ti = ev.get("tool_name"), ev.get("tool_input")
    cwd = ev.get("cwd") if isinstance(ev.get("cwd"), str) and ev.get("cwd") else os.getcwd()
    ti = ti if isinstance(ti, dict) else {"command": ti}
    if name in CODEX_SHELL or name in CODEX_STDIN:
        wd = ti.get("workdir") if isinstance(ti.get("workdir"), str) and ti.get("workdir") else None
        raw = ti.get("chars") if name in CODEX_STDIN else (ti.get("command") if "command" in ti else ti.get("cmd"))
        return [("Bash", {"command": _text(raw)}, _abs(wd, cwd) if wd else cwd)]
    if name == "apply_patch":
        body = _text(ti.get("command")) or _text(ti.get("input")) or _text(ti.get("patch"))
        return [(tool, {"file_path": p}, cwd) for tool, p in patch_calls(body, cwd)]
    if name in CLAUDE_TOOLS:
        return [(name, ti, cwd)]
    return []


def ag_paths(args, cwd):
    """Every path-like argument of an Antigravity call (the docstring), absolute, in order, each once."""
    out = []
    for k, v in args.items():
        if k in AG_TEXT_KEYS:
            continue
        for x in v if isinstance(v, list) else [v]:
            if not isinstance(x, str) or not x:
                continue
            if x[:5].lower() == "file:":
                x = urllib.parse.unquote(urllib.parse.urlparse(x).path)
            elif re.match(r"^[a-z][a-z0-9+.-]*://", x, re.I):
                continue   # a web URL reads no file here
            elif not (x.startswith(("/", "~")) or k in AG_PATH_KEYS):
                continue
            p = _abs(x, cwd)
            if p not in out:
                out.append(p)
    return out


def ag_calls(ev):
    """Antigravity's PreToolUse payload → [(Claude tool, tool_input, cwd)]."""
    call = ev.get("toolCall") if isinstance(ev.get("toolCall"), dict) else {}
    name = call.get("name") if isinstance(call.get("name"), str) else ev.get("toolName")
    args = call.get("args") if isinstance(call.get("args"), dict) else {}
    tool = AG_TOOLS.get(name)
    if not tool:
        return []
    cwd = next(iter(workspace_paths(ev.get("workspacePaths"))), None) or os.getcwd()
    wd = args.get("Cwd") if isinstance(args.get("Cwd"), str) and args.get("Cwd") else None
    if tool == "Bash":
        return [("Bash", {"command": _text(args.get("CommandLine"))}, _abs(wd, cwd) if wd else cwd)]
    if tool == "Stdin":   # each text argument is shell input; an id, a wait or a flag is not
        return [("Bash", {"command": v}, _abs(wd, cwd) if wd else cwd)
                for k, v in args.items() if k not in AG_STDIN_SKIP and isinstance(v, str) and v]
    paths = ag_paths(args, cwd)
    if tool in ("Glob", "Grep"):
        pattern = str(args.get("Pattern") or args.get("Query") or args.get("pattern") or args.get("query") or "*")
        return [(tool, {"path": p, "pattern": pattern}, cwd) for p in paths or [cwd]]
    return [(tool, {"file_path": p}, cwd) for p in paths]


def claude_payloads(cli, ev):
    """The Claude-shaped PreToolUse payloads one call of `cli` stands for."""
    calls = codex_calls(ev) if cli == "codex" else ag_calls(ev)
    session = ev.get("session_id") or ev.get("conversationId") or ev.get("sessionId")
    return [{"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": inp, "cwd": cwd,
             "session_id": f"{cli}:{session}" if session else cli, "transcript_path": None,
             "regatta_cli": cli} for tool, inp, cwd in calls]


# A guard that gave no answer: not there, crashed, out of time. The guards' own entries pass it (they fail
# open, as every hook here does); the trailer, whose rewrite is an allow, rewrites only on a clean pass from
# each guard (the finish review, 2026-10-31: a slow checkpoint read as a pass and carried Codex's allow).
UNKNOWN = "\0unknown"


def run_guard(guard, payload, timeout=BUDGET):
    """The guard's deny reason for one Claude payload, None for a clean allow (exit 0, no deny), or UNKNOWN for
    anything that is no answer. A guard that is not there is no answer: python's own exit 2 for a missing script
    would read as a deny."""
    if not os.path.isfile(guard):
        return UNKNOWN
    try:
        p = subprocess.run([sys.executable, guard], input=json.dumps(payload), capture_output=True,
                           text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return UNKNOWN
    if p.returncode not in (0, 2):
        return UNKNOWN
    if p.returncode == 2:
        return (p.stderr or "").strip() or f"refused by {os.path.basename(guard)}"
    for line in reversed((p.stdout or "").strip().splitlines()):
        try:
            out = json.loads(line)
        except ValueError:
            continue
        hso = out.get("hookSpecificOutput") if isinstance(out, dict) else None
        if isinstance(hso, dict) and hso.get("permissionDecision") == "deny":
            return str(hso.get("permissionDecisionReason") or f"refused by {os.path.basename(guard)}")
        if isinstance(out, dict) and out.get("decision") == "block":
            return str(out.get("reason") or f"refused by {os.path.basename(guard)}")
        # checkpoint catches its own crash and says so on exit 0 (`⚠ checkpoint hook failed: …`): no answer
        if isinstance(out, dict) and re.search(r"hook failed", str(out.get("systemMessage") or "")):
            return UNKNOWN
        return None
    return None


def trailer_for(cli, ev):
    name, addr = VENDORS[cli]
    model = ev.get("model") if cli == "codex" else ev.get("modelName")
    model = re.sub(r"[^\w.+ -]", "", model).strip() if isinstance(model, str) and model != "auto" else ""
    return f"Co-Authored-By: {name}{' ' + model if model else ''} <{addr}>"


def simple_commit(command):
    """True when COMMAND is one simple `git commit` and nothing else (the docstring): no operator, redirect,
    subshell, substitution or newline outside quotes, no heredoc, and no Co-Authored-By already."""
    if not isinstance(command, str) or not COMMIT_RE.search(command) or re.search(r"co-authored-by", command, re.I):
        return False
    if "\n" in command or "<<" in command:
        return False
    try:
        words = shlex.split(command)
    except ValueError:
        return False
    # a commit that skips the repo's git hooks gets no trailer, so no allow (the finish review, 2026-10-31):
    # `--no-verify` as git takes it, abbreviated (`--no-veri`), or `-n` in a cluster
    if any((w.startswith("--no-v") and "--no-verify".startswith(w)) or "hookspath" in w.lower()
           or re.match(r"^-[A-Za-z]*n[A-Za-z]*$", w) for w in words):
        return False
    # nor one that sets git config for the call: core.editor, gpg.program, core.fsmonitor and more run a
    # program; only the author's name and address pass (the re-review, 2026-10-31)
    head = words[:words.index("commit")] if "commit" in words else words
    for i, w in enumerate(head):
        if w.startswith("--config-env"):
            return False
        if w == "-c" and i + 1 < len(head) and head[i + 1].split("=", 1)[0].lower() not in ("user.name", "user.email"):
            return False
    return not compound(command)


def compound(command):
    """True when COMMAND holds, outside quotes, an operator, a redirect, a subshell or a backtick, or `$(` or a
    backtick anywhere but inside single quotes. One left-to-right scan: quotes are read in context, so an
    apostrophe inside double quotes opens nothing (two regexes did, and an operator rode along; the finish
    review, 2026-10-31)."""
    state, i = None, 0
    while i < len(command):
        c = command[i]
        if state == "'":
            if c == "'":
                state = None
        elif c == "\\":
            i += 1
        elif c == "`" or command.startswith("$(", i) or command.startswith("${", i):
            return True   # `${…}` too: zsh's `${(e)…}` runs a command (the re-review, 2026-10-31)
        elif state is None and command.startswith("$'", i):
            return True   # ANSI-C quoting, whose `\'` this scan cannot follow: a message needs none
        elif state == '"':
            if c == '"':
                state = None
        elif c in "'\"":
            state = c
        elif c in ";&|<>()\n":
            return True
        i += 1
    return False


def with_trailer(command, trailer):
    """The command with `--trailer` after its `git commit`, or None unless it is one simple commit."""
    if not simple_commit(command):
        return None
    return COMMIT_RE.sub(lambda m: m.group(1) + " --trailer " + shlex.quote(trailer), command, count=1)


def judge(cli, ev, guard, deadline):
    """The first deny reason of GUARD over the payloads one call stands for, None when each passed cleanly, or
    UNKNOWN when one gave no answer; the shared budget spent, the rest is not judged (the docstring)."""
    unknown = False
    for payload in claude_payloads(cli, ev):
        left = deadline - time.monotonic()
        if left < 1:
            sys.stderr.write(f"regatta vendor-hooks: {os.path.basename(guard)} out of time; the rest of this call "
                             "is not judged\n")
            return UNKNOWN
        why = run_guard(guard, payload, timeout=left)
        if why == UNKNOWN:
            unknown = True
        elif why:
            return why
    return UNKNOWN if unknown else None


def decide(cli, guard, ev, deadline=None):
    """('deny', reason) | ('rewrite', new command — a string, or the argv list with its script replaced) |
    ('allow', None) for one call of `cli`."""
    deadline = time.monotonic() + BUDGET if deadline is None else deadline
    if guard == "trailer":
        ti = ev.get("tool_input") if cli == "codex" and isinstance(ev.get("tool_input"), dict) else {}
        calls = codex_calls(ev) if cli == "codex" else ag_calls(ev)
        typed = ev.get("tool_name") in CODEX_STDIN if cli == "codex" else \
            AG_TOOLS.get((ev.get("toolCall") or {}).get("name") or ev.get("toolName")) != "Bash"   # text typed into a shell is no command line; the name read as ag_calls reads it
        if typed or not (len(calls) == 1 and calls[0][0] == "Bash"):
            return "allow", None
        new = with_trailer(calls[0][1]["command"], trailer_for(cli, ev))
        if new is None:
            return "allow", None
        rewritten = dict(ev, tool_input=dict(ti, command=new)) if cli == "codex" else \
            dict(ev, toolCall=dict(ev.get("toolCall") or {}, args=dict((ev.get("toolCall") or {}).get("args") or {}, CommandLine=new)))
        if any(judge(cli, rewritten, g, deadline) is not None for g in TRAILER_GUARDS):
            return "allow", None   # a guard refuses it or gave no answer: its own entry says so; the trailer allows nothing
        raw = ti.get("command") if cli == "codex" else (ev.get("toolCall") or {}).get("args", {}).get("CommandLine")
        i = shell_script(raw)
        if i is not None:
            return "rewrite", raw[:i] + [new] + raw[i + 1:]
        return ("rewrite", new) if isinstance(raw, str) else ("allow", None)
    why = judge(cli, ev, guard, deadline)
    return ("deny", why) if why and why != UNKNOWN else ("allow", None)


def answer(cli, ev, verdict, value):
    """What `cli` reads on stdout for a verdict; "" for none."""
    if cli == "codex":
        if verdict == "deny":
            return json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                                      "permissionDecisionReason": value}}, ensure_ascii=False)
        if verdict == "rewrite":
            ti = ev.get("tool_input") if isinstance(ev.get("tool_input"), dict) else {}
            return json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow",
                                                      "updatedInput": dict(ti, command=value)}}, ensure_ascii=False)
        return ""
    if verdict == "deny":
        return json.dumps({"decision": "deny", "reason": value}, ensure_ascii=False)
    if verdict == "rewrite":   # no `decision`: the rewrite leaves agy's own permission flow as it is
        return json.dumps({"overwrite": {"CommandLine": value}}, ensure_ascii=False)
    return "{}"


def main(argv, data):
    if len(argv) != 2 or argv[0] not in CLIS:
        return "{}" if argv and argv[0] == "antigravity" else ""
    cli, guard = argv
    try:
        ev = json.loads(data or "null")
    except ValueError:
        ev = None
    if not isinstance(ev, dict):
        return answer(cli, {}, "allow", None)
    verdict, value = decide(cli, guard, ev)
    return answer(cli, ev, verdict, value)


if __name__ == "__main__":
    args = sys.argv[1:]
    try:
        out = main(args, sys.stdin.read())
    except BaseException:   # fail open: the CLI's own "carry on"
        out = "{}" if args[:1] == ["antigravity"] else ""
    if out:
        sys.stdout.write(out + "\n")
    sys.exit(0)
