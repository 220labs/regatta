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
the default dir's included, so while the tenants file (else the registry) names a tenant the hook asks on the default dir
too (bar in its own tenant's repos, which it runs: the vault's tenant, S7), and a tenant refusal is passed on as `allowed` words it: it names the login's own way in.
A tenants file that reads nothing, with no last good copy, is closed tenancy (confidential-reach S7b, 2026-10-27): every repo
is asked about and `allowed` refuses each, naming the read that opens it. While the default dir is refused the vault (closed,
or not the vault's tenant), a start in the projects folder or the home folder is asked about too: both hold it.
A no-op without CLAUDE_CONFIG_DIR and no tenant (the default dir denies nothing) and for a dir the registry
has no row for — bar a tenant's repo, which such a dir is refused too, and one under Orca's data, which `allowed` answers by the row of the login it is
signed in as, else ORCA_ROW's list (2026-10-17). Fails closed when bin/account cannot run the regatta core (a
traceback: the core missing or its config incomplete, B2b), open on any other error, and by design for a cwd in no repo — bar one that holds a denied repo
(the projects folder, or the home folder for a row denying the vault), refused since 2026-10-18: Claude Code reads the default config dir's CLAUDE.md
as that folder's project memory and follows its imports there. Otherwise the list says where sessions
start; it is no data boundary (section 2 of the doc). Hence the start is what it judges ($CLAUDE_PROJECT_DIR,
else the event's cwd): a session that later `cd`s into the projects folder is not refused (2026-10-22). Where
the shell went is judged too, bar "it holds a denied repo": a `cd` into a denied or a tenant's repo is still refused —
unless an open bridge from the start's scope waives it (`allowed --from` the start; confidential-reach S8).
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


def fixture_registry(reg, live):
    """bin/account's: an ACCOUNTS_FILE naming another file than the live key is a suite's fixture.
    Naming the live key itself (bootstrap.sh's `account check`) is no fixture (review 2026-10-23)."""
    if not os.environ.get("ACCOUNTS_FILE"):
        return False
    try:
        return reg.resolve() != live.resolve()
    except (OSError, RuntimeError):   # 3.9: a link loop
        return True


def tenant_entries():
    """The tenant repo entries the default dir may be refused: the tenants file's when written, else the
    registry's ([] when none, or unreadable — as before tenancy), less its own tenant's, which it runs (the
    vault's tenant on the default dir, S7: four repos the owner works in, which would cost each prompt there
    a subprocess). A plain read, no subprocess: the hook runs on every prompt of every default-dir session."""
    config = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
    live = config / "lighthouse" / "accounts.json"
    reg = Path(os.environ.get("ACCOUNTS_FILE") or live)
    # bin/account's TENANTS, its fixture rule included, and its last good copy, which holds while the
    # link reads nothing or is gone (the drive away; reviews 2026-10-22)
    tenants = Path(os.environ.get("TENANTS_FILE")
                   or (reg.with_name(reg.name + ".tenants") if fixture_registry(reg, live)
                       else config / "lighthouse" / "tenants.json"))
    last = tenants.with_name("." + tenants.name + ".last")
    # A link into a cloud drive: the copy first, and the link only when it does not read
    # (docs/orca-launcher-2026-10-24.md, S4): a session whose responsible process holds no grant for the
    # drive (Orca's app, 2026-10-24) blocks this hook on a privacy prompt nobody sees. bin/account refreshes
    # the copy under claude-host (the usage tick, every 15 min), so a changed file reaches here within 15 min.
    # A plain file is read first, as before S4: an edit to it takes effect at once (S4 finish review). The
    # copy and the link are asked about before exists(), which follows the link into the drive.
    try:
        accounts = json.loads(reg.read_text()).get("accounts")
    except (OSError, ValueError, AttributeError):
        accounts = None
    if last.is_file() or tenants.is_symlink() or tenants.exists():   # written, the whole of tenancy (bin/account's header)
        t = None
        for f in ((last, tenants) if drive_backed(tenants) else (tenants, last)):
            try:
                t = json.loads(f.read_text())
            except (OSError, ValueError):
                continue
            if isinstance(t, dict):
                break
        if not isinstance(t, dict):
            # closed, as bin/account reads it (its header, S7b): every repo is asked about, and `allowed`
            # refuses each; open here, a work seat's default dir would reach the vault on a new host
            print(f"account_guard: {tenants} unreadable, and no last good copy — tenancy closed", file=sys.stderr)
            return ["*"]
        label = default_row(accounts).get("label")
        own = None
        for n, v in t.items():   # a label in two tenants' logins is the later one's (bin/account's apply_tenants)
            logins = v.get("logins") if isinstance(v, dict) else None
            logins = [logins] if isinstance(logins, str) else logins if isinstance(logins, list) else []
            if label is not None and label in logins:
                own = n
    else:
        try:
            t = json.loads(reg.read_text()).get("tenants")
        except (OSError, ValueError, AttributeError):
            return []
        if not isinstance(t, dict):
            return []
        own = default_row(accounts).get("tenant")
    return [e for n, v in t.items() if n != own and isinstance(v, dict) and isinstance(v.get("repos"), list)
            for e in map(tenant_entry, v["repos"]) if e]


def default_row(accounts):
    """The registry's row for the default dir (`.claude` in the home folder, not one Orca holds), or {}: bin/account's is_default.
    An unreadable registry has none, so no tenant is the default dir's own and every entry is asked about."""
    default = os.path.join(str(Path.home()), ".claude")
    for a in accounts if isinstance(accounts, list) else []:
        if isinstance(a, dict) and a.get("via") != "orca" and a.get("provider", "claude") == "claude" \
                and isinstance(a.get("home"), str) and os.path.abspath(os.path.expanduser(a["home"])) == default:
            return a
    return {}


def drive_backed(p):
    """The core's drive_backed(), copied: is p a link whose text points under a cloud drive's mount? The
    hook must not import the core it guards against losing; the core's check runs both over the same cases."""
    try:
        p = os.fspath(p)
        if not os.path.islink(p):
            return False
        roots = os.environ.get("REGATTA_DRIVE_ROOTS") or os.path.expanduser("~/Library/CloudStorage")
        roots = {x for r in filter(None, roots.split(":"))
                 for x in (os.path.normpath(os.path.abspath(os.path.expanduser(r))), os.path.realpath(os.path.expanduser(r)))}
        for _ in range(8):   # a link to a link (a worktree's .env → main's → the drive): each hop by its text
            parent = os.path.realpath(os.path.dirname(os.path.abspath(p)))
            p = os.path.normpath(os.path.join(parent, os.readlink(p)))
            if any(p == root or p.startswith(root + os.sep) for root in roots):
                return True
            if not os.path.islink(p):   # a hop outside every drive: lstat only, never into a drive
                return False
    except (OSError, TypeError, ValueError):
        return True
    return False


def tenant_entry(r):
    """bin/account's tenant_entry, copied: the hook must not import the core it guards against losing."""
    if not isinstance(r, str) or r.startswith(("/", "~")):
        return None
    while r.startswith("./"):
        r = r[2:]
    return r.strip("/") or None


def projects_folder():
    """The core's `regatta/projects`, else `projects` in the home folder."""
    config = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
    try:
        return Path((config / "regatta" / "projects").read_text().strip().splitlines()[0]).expanduser()
    except (OSError, IndexError):
        return Path.home() / "projects"


def holds_vault(cwd, entries):
    """True when cwd is the projects folder or a folder above it (the home folder) and an entry the default dir
    is refused takes the vault (`lighthouse/vault`): bin/account's holds_denied refuses such a start, since the
    default dir's CLAUDE.md imports the vault's files, and maybe_tenants never sees it (no part under the
    projects folder; the S7 review's third finding, fixed in S7b). Never true where the default dir is the
    vault's tenant: tenant_entries leaves its own tenant's entries out, so the owner's prompts there cost nothing."""
    config = Path(os.environ.get("REGATTA_CONFIG") or Path.home() / ".config" / "regatta").expanduser()
    try:
        vault = (config / "lighthouse" / "vault").read_text().split()[0]
    except (OSError, IndexError):
        return False
    if not any(fnmatch.fnmatchcase(vault, e) for e in entries):
        return False
    try:
        projects = projects_folder().resolve()
        here = Path(cwd).expanduser().resolve()
    except (OSError, RuntimeError):
        return False
    return here == projects or here in projects.parents


def maybe_tenants(cwd, entries):
    """True when cwd could be in a tenant's repo: under the projects folder (the core's `regatta/projects`,
    else `projects` in the home folder) with leading parts an entry matches — a key, or a glob as bin/account reads one.
    A prefilter, so a default-dir prompt elsewhere costs no subprocess (0.4 s, review 2026-10-20).
    A worktree outside the projects folder is not seen here: the default dir's sessions start inside it."""
    projects = projects_folder()
    try:
        rel = Path(cwd).expanduser().resolve().relative_to(projects.resolve()).parts
    except (ValueError, OSError):
        return False
    # Every leading run of parts, not just as many as the entry has: bin/account matches a glob against the
    # whole repo key, where `*` spans `/` ("*-acme" takes clients/x-acme; review 2026-10-21).
    return any(fnmatch.fnmatchcase("/".join(rel[:k]), e) for e in entries for k in range(1, len(rel) + 1))


def own_way(why):
    """True when `allowed`'s line names its own way out, which the guard passes on as it is: a tenant's
    (off_line: the tenant's login) or a closed tenancy's (bin/account's closed_text: the read that opens it)."""
    return "'s, which runs on " in why or "tenancy does not read" in why


def main():
    default_dir = not os.environ.get("CLAUDE_CONFIG_DIR")
    entries = tenant_entries() if default_dir else []
    if default_dir and not entries:
        return
    try:
        data = json.load(sys.stdin)
    except ValueError:
        data = {}
    # Where the session started, not where its shell is now: the hook's `cwd` follows a `cd` (into the
    # projects folder for a cross-repo grep, say), and judged by it every later prompt of a session started
    # in an open repo was blocked — 18 prompts on two work logins in 4 days (2026-10-22). The list
    # is about what Claude Code loads at the start (header), and CLAUDE_PROJECT_DIR keeps the start
    # across a `cd` (probed 2026-10-22 with a two-prompt headless session).
    here = (data or {}).get("cwd") or os.getcwd()
    cwd = os.environ.get("CLAUDE_PROJECT_DIR") or here
    # Where the shell went is judged too, bar the one rule about the start: a denied or a tenant's repo
    # the shell moved into is still refused, while "it holds" a denied repo (the projects folder, the
    # home folder) is about what loads at the start and binds the start only (the branch's reviews).
    if here != cwd and (not default_dir or maybe_tenants(here, entries)):
        # --from the start: an open bridge (confidential-reach S8) waives a route only for a session started in either side
        t = subprocess.run([sys.executable, str(ACCOUNT), "allowed", here, "--from", cwd], capture_output=True, text=True, timeout=20)
        if t.returncode == 1 and " is off " in t.stdout and " holds " not in t.stdout:
            why = t.stdout.strip()
            # a tenant's line (off_line) names its own login's way in, from either source (review 2026-10-23)
            print(json.dumps({"decision": "block", "reason": why if own_way(why) else
                              f"{why}: open it in the default VS Code profile, or a Terminal claude on the default login (no CLAUDE_CONFIG_DIR)"}))
            return
    if default_dir and not maybe_tenants(cwd, entries) and not holds_vault(cwd, entries):
        return
    r = subprocess.run([sys.executable, str(ACCOUNT), "allowed", cwd, "--from", cwd], capture_output=True, text=True, timeout=20)
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
    # a tenant's repo (off_line), or tenancy closed: the line already names its own way out; and the default
    # dir's refusals are all tenancy's, where "use the default login" would send it back to itself (S7b review)
    if own_way(why) or default_dir:
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
