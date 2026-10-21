#!/usr/bin/env python3
"""account_guard: refuse a prompt in a repo the session's account denies (work-account E4).

A row of the login registry (the config dir's `lighthouse/accounts.json`) may carry
`"repos": {"deny": [...]}` — a work login denies the owner's vault and CV repos (the owner's D3,
docs/work-account-2026-10-06.md). `pickup` and `dispatch` honour it through `account pick --repo`;
nothing stands in front of a session the owner starts by hand — `CLAUDE_CONFIG_DIR=<a work dir>
claude` typed in the vault, or a window of that login's VS Code profile opened there. This hook is
that net: on every prompt of a session on a secondary config dir it asks `bin/account allowed
<cwd>`, and on exit 1 blocks the prompt with the way out (the default profile, or a Terminal claude
on the default login).

A tenant's repo (bin/account's header, Tenants, 2026-10-20) is off every login but the tenant's,
the default dir's included, so while the registry names a tenant the hook asks on the default dir
too, and a tenant refusal is passed on as `allowed` words it: it names the login's own way in.
A no-op without CLAUDE_CONFIG_DIR and no tenant (the default dir denies nothing) and for a dir the registry
has no row for — bar a tenant's repo, which such a dir is refused too, and one under Orca's data, which `allowed` answers by the row of the login it is
signed in as, else ORCA_ROW's list (2026-10-17). Fails closed when bin/account cannot run the regatta core (a
traceback: the core missing or its config incomplete, B2b), open on any other error, and by design for a cwd in no repo — bar one that holds a denied repo
(the projects folder, or the home folder for a row denying the vault), refused since 2026-10-18: Claude Code reads the default config dir's CLAUDE.md
as that folder's project memory and follows its imports there. Otherwise the list says where sessions
start; it is no data boundary (section 2 of the doc).
Wired user-wide on UserPromptSubmit (the overlay's `bootstrap.sh --hooks`, or this plugin's
hooks.json). Stdlib only, Python 3.9, never exits non-zero (exit 2 there erases the prompt).
"""
import fnmatch
import json
import os
import subprocess
import sys
from pathlib import Path

ACCOUNT = Path(__file__).resolve().parent.parent / "bin" / "account"


def tenant_entries():
    """The registry's tenant repo entries ([] when none, or unreadable — as before tenancy). A plain read,
    no subprocess: the hook runs on every prompt of every default-dir session."""
    config = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
    reg = Path(os.environ.get("ACCOUNTS_FILE") or config / "lighthouse" / "accounts.json")
    try:
        t = json.loads(reg.read_text()).get("tenants")
    except (OSError, ValueError, AttributeError):
        return []
    if not isinstance(t, dict):
        return []
    return [e for v in t.values() if isinstance(v, dict) and isinstance(v.get("repos"), list)
            for e in map(tenant_entry, v["repos"]) if e]


def tenant_entry(r):
    """bin/account's tenant_entry, copied: the hook must not import the core it guards against losing."""
    if not isinstance(r, str) or r.startswith(("/", "~")):
        return None
    while r.startswith("./"):
        r = r[2:]
    return r.strip("/") or None


def maybe_tenants(cwd, entries):
    """True when cwd could be in a tenant's repo: under the projects folder (the core's `regatta/projects`,
    else `projects` in the home folder) with leading parts an entry matches — a key, or a glob as bin/account reads one.
    A prefilter, so a default-dir prompt elsewhere costs no subprocess (0.4 s, review 2026-10-20).
    A worktree outside the projects folder is not seen here: the default dir's sessions start inside it."""
    config = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
    try:
        projects = Path((config / "regatta" / "projects").read_text().strip().splitlines()[0]).expanduser()
    except (OSError, IndexError):
        projects = Path.home() / "projects"
    try:
        rel = Path(cwd).expanduser().resolve().relative_to(projects.resolve()).parts
    except (ValueError, OSError):
        return False
    # Every leading run of parts, not just as many as the entry has: bin/account matches a glob against the
    # whole repo key, where `*` spans `/` ("*-acme" takes clients/x-acme; review 2026-10-21).
    return any(fnmatch.fnmatchcase("/".join(rel[:k]), e) for e in entries for k in range(1, len(rel) + 1))


def main():
    default_dir = not os.environ.get("CLAUDE_CONFIG_DIR")
    entries = tenant_entries() if default_dir else []
    if default_dir and not entries:
        return
    try:
        data = json.load(sys.stdin)
    except ValueError:
        data = {}
    cwd = (data or {}).get("cwd") or os.getcwd()
    if default_dir and not maybe_tenants(cwd, entries):
        return
    r = subprocess.run([sys.executable, str(ACCOUNT), "allowed", cwd], capture_output=True, text=True, timeout=20)
    # The default dir is the seat a broken core is repaired from: it was never blocked before tenancy,
    # so a traceback there fails open, on stderr (review 2026-10-20). Secondary dirs fail closed below.
    if default_dir and r.returncode != 0 and "Traceback (most recent call last)" in r.stderr:
        lines = [l.strip() for l in r.stderr.splitlines() if l.strip()]
        print(f"account_guard: bin/account could not run ({lines[-1]}) — tenancy unchecked on the default dir", file=sys.stderr)
        return
    # A traceback is bin/account failing to run at all — the regatta core missing, or refusing to
    # load because the config dir lacks the private values its deny list comes from (B2b). That is
    # no answer, so a deny hook blocks: fail closed, in one line that says how to repair it (the
    # overlay branch's review, 2026-10-18). A malformed registry exits 1 with its own one-line
    # message and no traceback, and stays silent below (review 2026-10-06).
    if r.returncode != 0 and "Traceback (most recent call last)" in r.stderr:
        lines = [l.strip() for l in r.stderr.splitlines() if l.strip()]
        why = lines[-1]   # the exception's own line: the traceback's source lines may quote it too
        print(json.dumps({"decision": "block", "reason": f"account_guard: bin/account could not run ({why}) — "
                          "write the regatta config dir (the overlay's bootstrap.sh --config, or the core's install.sh), "
                          "then send the prompt again"}))
        return
    # Otherwise block only on the line `allowed` prints for a denied repo: bin/account also exits 1
    # on a malformed registry (a merge in progress in the repo that holds it), and a guard that read that as
    # "denied" would block every prompt in every secondary-dir session (review 2026-10-06).
    if r.returncode != 1 or " is off " not in r.stdout:
        return
    why = r.stdout.strip()
    if "(accounts.json tenants)" in why:   # a tenant's repo: the line already names its own login's way in
        print(json.dumps({"decision": "block", "reason": why}))
        return
    print(json.dumps({"decision": "block", "reason": f"{why}: open it in the default VS Code profile, "
                      "or a Terminal claude on the default login (no CLAUDE_CONFIG_DIR)"}))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # a guard that crashes must not take the prompt with it
        print(f"account_guard: {e}", file=sys.stderr)
    sys.exit(0)
