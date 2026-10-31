#!/usr/bin/env python3
"""The parity table: each guard rule a Claude session meets, with a deny case and an allow case, run against
every CLI's payload shape (the owner's D2-A, docs/codex-agy-gaps-2026-10-29.md: "a suite runs each rule's case
against every CLI, so a gap shows as a red row").

    python3 parity_rules.py      the fixture paths come from the environment parity.sh sets

A case names a neutral call — (kind, argument, cwd) with kind shell, read, write or edit — and each CLI builds
its own payload for it (BUILD): Claude Code's is the guard's own input; Codex's goes through hooks/vendor_hook.py
as Codex sends it (`Bash`, `apply_patch`; it has no read tool, so a read is the shell read it makes); Antigravity's
the same, as it sends it (`run_command`, `view_file` and `read_file`, `write_to_file`, `replace_file_content`).
A CLI with no builder for a kind, or whose call the adapter does not translate, is a red row, never a skip.
`native` marks a rule whose Claude socket is not a hook (Claude Code's own trailer; dispatch's launch-time deny
list, checked here by reading that list): it is judged where it lives. Exit 1 on any red row.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

E = os.environ
LH = Path(E["PARITY_LIGHTHOUSE"])
ADAPTER = LH / "hooks" / "vendor_hook.py"
SG = str(LH / "hooks" / "secrets_guard.py")
CP = E.get("PARITY_CHECKPOINT") or ""
DISPATCH = E.get("PARITY_DISPATCH") or ""
HOME, SGV, R, WT = E["HOME"], E["PARITY_SGV"], E["PARITY_PRIMARY"], E["PARITY_WORKTREE"]
CLIS = ("claude-code", "codex", "antigravity")

# --- each CLI's payload for a neutral call ------------------------------------------------------

def claude(kind, arg, cwd):
    tool, inp = {"shell": ("Bash", {"command": arg}), "read": ("Read", {"file_path": arg}),
                 "write": ("Write", {"file_path": arg, "content": "x\n"}),
                 "edit": ("Edit", {"file_path": arg, "old_string": "a", "new_string": "b"})}[kind]
    return [{"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": inp, "cwd": cwd,
             "session_id": "parity-claude"}]


def codex(kind, arg, cwd):
    base = {"hook_event_name": "PreToolUse", "cwd": cwd, "session_id": "parity-codex", "model": "gpt-test",
            "permission_mode": "default", "tool_use_id": "t1", "transcript_path": None, "turn_id": "u1"}
    if kind == "shell":   # a string, and the argv Codex's shell tool may send: both must agree
        return [dict(base, tool_name="Bash", tool_input={"command": arg}),
                dict(base, tool_name="Bash", tool_input={"command": ["bash", "-lc", arg]})]
    if kind == "read":   # Codex reads through its shell
        return [dict(base, tool_name="Bash", tool_input={"command": f"sed -n '1,200p' {arg}"}),
                dict(base, tool_name="Bash", tool_input={"command": ["/bin/zsh", "-lc", f"cat {arg}"]})]
    head = {"write": "Add File", "edit": "Update File"}[kind]
    patch = f"*** Begin Patch\n*** {head}: {arg}\n+x\n*** End Patch\n"
    return [dict(base, tool_name="apply_patch", tool_input={"command": patch})]


def antigravity(kind, arg, cwd):
    base = {"conversationId": "parity-agy", "workspacePaths": ["file://" + cwd], "modelName": "gemini-test",
            "stepIdx": 1}
    def call(name, args):
        return dict(base, toolCall={"name": name, "args": args})
    if kind == "shell":
        return [call("run_command", {"CommandLine": arg, "Cwd": cwd, "WaitMsBeforeAsync": 0})]
    if kind == "read":   # the docs' name, the one this Mac's outbox recorded and the other readers: all must hold
        return [call("view_file", {"AbsolutePath": arg}), call("read_file", {"Path": arg}),
                call("view_code_item", {"File": arg, "NodePaths": ["X"]}),
                call("read_url_content", {"Url": "file://" + arg})]
    if kind == "write":
        return [call("write_to_file", {"TargetFile": arg, "CodeContent": "x", "Overwrite": True}),
                call("write_file", {"Path": arg, "Content": "x"})]
    return [call("replace_file_content", {"TargetFile": arg, "TargetContent": "a", "ReplacementContent": "b"})]


BUILD = {"claude-code": claude, "codex": codex, "antigravity": antigravity}

# --- the table ----------------------------------------------------------------------------------
# (rule, guard, deny case, allow case, env); a case is (kind, argument, cwd). guard "native:<what>" is judged
# by native(); "trailer" expects a rewrite for the deny case (the commit gains the CLI's Co-Authored-By).
S = SGV + "/_secrets"
RULES = [
    ("secrets: a file tool on _secrets", SG, ("read", S + "/app.env", WT), ("read", SGV + "/notes.md", WT), {}),
    ("secrets: a shell read of _secrets", SG, ("shell", f"cat {S}/app.env", WT), ("shell", f"ls {S}", WT), {}),
    ("secrets: a write into _secrets", SG, ("write", S + "/new.env", WT), ("write", WT + "/ok.txt", WT), {}),
    ("CLI login: Codex's auth.json", SG, ("read", HOME + "/.codex/auth.json", WT),
     ("read", HOME + "/.codex/config.toml", WT), {}),
    ("CLI login: Antigravity's oauth_creds.json", SG, ("shell", f"cat {HOME}/.gemini/oauth_creds.json", WT),
     ("shell", f"ls {HOME}/.gemini", WT), {}),
    ("push: --no-verify", CP, ("shell", "git push --no-verify origin claude/x/2026-10-29-t", WT),
     ("shell", "git push -u origin claude/x/2026-10-29-t", WT), {}),
    ("push: -c core.hooksPath", CP, ("shell", "git -c core.hooksPath=/dev/null push origin claude/x/2026-10-29-t", WT),
     ("shell", "git log -1 --oneline", WT), {}),
    ("push: --receive-pack", CP, ("shell", "git push --receive-pack=/bin/true origin claude/x/2026-10-29-t", WT),
     ("shell", "git push origin claude/x/2026-10-29-t", WT), {}),
    ("push: --exec", CP, ("shell", "git push --exec=/bin/true origin claude/x/2026-10-29-t", WT),
     ("shell", "git push origin claude/x/2026-10-29-t", WT), {}),
    ("push: a bare push", CP, ("shell", "git push", WT), ("shell", "git push -u origin claude/x/2026-10-29-t", WT), {}),
    ("push: main", CP, ("shell", "git push origin main", WT), ("shell", "git push origin claude/x/2026-10-29-t", WT), {}),
    ("delete: a claude/* branch", CP, ("shell", "git branch -D claude/x/2026-10-29-old", WT),
     ("shell", "git branch --list", WT), {}),
    ("main: a file written in the primary", CP, ("write", R + "/new.txt", R), ("write", WT + "/new.txt", WT), {}),
    ("main: a file edited in the primary", CP, ("edit", R + "/README.md", R), ("edit", WT + "/README.md", WT), {}),
    ("main: a commit in the primary", CP, ("shell", "git commit -qam x", R), ("shell", "git commit -qam x", WT), {}),
    ("CLI login: a glob over Codex's home", SG, ("shell", f"cat {HOME}/.codex/auth*", WT),
     ("shell", f"cat {HOME}/.codex/config.*", WT), {}),
    ("CLI login: a relative read after cd", SG, ("shell", f"cd {HOME}/.codex && cat auth.json", WT),
     ("shell", f"cd {HOME}/.codex && cat config.toml", WT), {}),
    ("CLI login: agy's keychain fallback file", SG, ("read", HOME + "/.gemini/jetski-standalone-oauth-token", WT),
     ("read", HOME + "/.gemini/settings.json", WT), {}),
    ("CLI hooks: Codex's hooks.json, by a file tool", SG, ("write", HOME + "/.codex/hooks.json", WT),
     ("write", WT + "/hooks.json", WT), {}),
    ("CLI hooks: agy's hooks.json, by a file tool", SG, ("edit", HOME + "/.gemini/config/hooks.json", WT),
     ("edit", WT + "/README.md", WT), {}),
    ("unattended: pr merge", "native:dispatch:Bash(*bin/pr merge*)", ("shell", "bin/pr merge 12", WT),
     ("shell", "git log -1", WT), {"CLAUDE_UNATTENDED": "1"}),
    ("unattended: gh (vendor-neutral marker)", "native:dispatch:Bash(gh:*)", ("shell", "gh pr view 12", WT),
     ("shell", "git status --short", WT), {"REGATTA_UNATTENDED": "1"}),
    ("unattended: ssh", "native:dispatch:Bash(ssh:*)", ("shell", "ssh host ls", WT),
     ("shell", "git status --short", WT), {"CLAUDE_UNATTENDED": "1"}),
    ("unattended: git push", "native:dispatch:Bash(git push:*)", ("shell", "git push -u origin claude/x/2026-10-29-t", WT),
     ("shell", "git status --short", WT), {"REGATTA_UNATTENDED": "1"}),
    ("unattended: the queue's verbs", "native:dispatch:Bash(*dispatch-queue claim*)", ("shell", "x/dispatch-queue claim", WT),
     ("shell", "x/dispatch-queue status", WT), {"CLAUDE_UNATTENDED": "1"}),
    ("attribution: a commit names its CLI", "trailer", ("shell", 'git commit -m "x"', WT),
     ("shell", "git status --short", WT), {}),
]

def native(guard):
    """(what a rule's Claude socket is, a check that it holds) for a rule that is not a PreToolUse hook:
    `native:dispatch:<entry>` is that entry of dispatch's launch-time deny list, read from the file."""
    if guard.startswith("native:dispatch:"):
        entry = guard.split(":", 2)[2]
        return (f"dispatch's launch-time deny list ({entry})",
                lambda: bool(DISPATCH) and Path(DISPATCH).is_file() and f'"{entry}"' in Path(DISPATCH).read_text(encoding="utf-8"))
    return ("Claude Code's own Co-Authored-By", lambda: True)

# --- running a case -----------------------------------------------------------------------------

def run(cmd, payload, env):
    p = subprocess.run(cmd, input=json.dumps(payload), capture_output=True, text=True, timeout=60,
                       env=dict(os.environ, **env))
    return p.stdout.strip(), p.returncode, p.stderr


def verdict(cli, out, rc, err):
    """deny | rewrite | allow | broken (an answer the CLI would not read), from what the CLI would read."""
    if cli == "antigravity":
        try:
            v = json.loads(out.splitlines()[-1]) if out else None
        except ValueError:
            return "broken"
        if not isinstance(v, dict) or len(out.splitlines()) != 1:
            return "broken"   # Antigravity takes anything but one JSON object as a deny
        if v.get("decision") == "deny":
            return "deny"
        return "rewrite" if "overwrite" in v else "allow"
    if rc == 2:
        return "deny"
    for line in reversed(out.splitlines()):
        try:
            v = json.loads(line)
        except ValueError:
            continue
        h = v.get("hookSpecificOutput") if isinstance(v, dict) else None
        if isinstance(h, dict) and h.get("permissionDecision") == "deny":
            return "deny"
        if isinstance(h, dict) and "updatedInput" in h:
            return "rewrite"
        break
    return "allow"


def judge(cli, guard, case, env):
    """(verdict, detail) for one case on one CLI; ('red', why) when the CLI has no road for it."""
    kind, arg, cwd = case
    build = BUILD.get(cli)
    payloads = build(kind, arg, cwd) if build else None
    if not payloads:
        return "red", f"no {cli} payload for a {kind}"
    seen = set()
    for p in payloads:
        if cli == "claude-code":
            if guard.startswith("native:") or guard == "trailer":
                return "native", native(guard)[0]
            out, rc, err = run([sys.executable, guard], p, env)
        else:
            g = CP if guard.startswith("native:") else guard
            if not g:
                return "red", "the guard's module is not here"
            out, rc, err = run([sys.executable, str(ADAPTER), cli, g], p, env)
        seen.add(verdict(cli, out, rc, err))
        detail = out[:160]
    if len(seen) != 1:
        return "red", f"the CLI's tool names disagree: {sorted(seen)}"
    return seen.pop(), detail


def main():
    reds = 0
    width = max(len(r[0]) for r in RULES)
    print(f"{'rule':<{width}}  " + "  ".join(f"{c:<12}" for c in CLIS))
    for rule, guard, deny_case, allow_case, env in RULES:
        cells, why = [], []
        if not guard:
            print(f"{rule:<{width}}  its guard's module is not in this tree: not judged here")
            continue
        for cli in CLIS:
            want = "rewrite" if guard == "trailer" else "deny"
            d, dd = judge(cli, guard, deny_case, env)
            a, ad = judge(cli, guard, allow_case, env)
            if d == "native":
                ok = native(guard)[1]()
                cells.append("native" if ok else "RED")
                if not ok:
                    why.append(f"{cli}: {dd} does not hold it")
                continue
            ok = d == want and a == "allow"
            if guard == "trailer" and d == "rewrite":
                name = {"codex": "Codex gpt-test <noreply@openai.com>",
                        "antigravity": "Antigravity gemini-test <noreply@google.com>"}[cli]
                ok = ok and f"Co-Authored-By: {name}" in dd + _full(cli, guard, deny_case, env)
            cells.append("ok" if ok else "RED")
            if not ok:
                why.append(f"{cli}: deny case {d} ({dd}), allow case {a} ({ad})")
        reds += cells.count("RED")
        print(f"{rule:<{width}}  " + "  ".join(f"{c:<12}" for c in cells))
        for w in why:
            print(f"    {w}")
    print(f"{reds} red" if reds else "all green")
    return 1 if reds else 0


def _full(cli, guard, case, env):
    """The whole answer for a trailer case (judge() keeps a prefix)."""
    kind, arg, cwd = case
    out, _, _ = run([sys.executable, str(ADAPTER), cli, guard], BUILD[cli](kind, arg, cwd)[0], env)
    return out


if __name__ == "__main__":
    sys.exit(main())
