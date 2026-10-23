#!/usr/bin/env python3
"""design_route: a new Claude Design artifact is made on the primary account, and shared as made.

PreToolUse and PostToolUse on `Artifact`. The owner, 2026-10-10: "every task that wants to use
claude design with artifacts should auto-dispatch to [the always-on Mac] (run locally as
fallback), and the account picker on start should know that design sessions should be pinned to
[the primary]". An artifact belongs to the login that published it, and nothing in a publish call
shares it: the two design artifacts of that week were made on a work login, so the owner's own
address could not open them.

Pre — a session whose config dir is not the registry's primary row (the config dir's
`lighthouse/accounts.json`, `primary: true`) is denied the call that starts a design: `quickstart`
with `intent: design`, or a publish from the Design or Design System type (DESIGN_TYPES). The
reason says how to hand it off: a seed, then `dispatch <branch> --repo <repo> --on <host>
--fallback here --account bound` — the host is the config dir's `lighthouse/design-host` (without
it the run stays here), bound is `account pick --bound`, the primary, at fire time (wharf-runs'
bin/dispatch), and a repo that is not `physical: none` is seeded in a sibling that is (dispatch
refuses it). A session already on the primary passes, wherever it runs (the owner's answer the
same day: a primary panel on the laptop proceeds in place; a hand-off would lose the conversation
design taste rests on). Everything else on Artifact passes: list, read, an update by url, the
other types.

Post — on the primary, after a publish from a design type, the reply gets one instruction: share
the new artifact with everyone in the logins file's `share.design` list (the config dir's
`lighthouse/logins.json`, kept off git: e-mails stay out of every repo, bin/account's header),
each at the access the list names — through the Artifact tool's `share` action where the tool
offers it (behind a flag in 2.1.296; it asks on a card, so never in an unattended run), else
claude.ai's Share dialog in Chrome; the file is read with dataless files materialised
(setiopolicy_np: a file-provider folder may hold it), and one it cannot read is said, never taken
as an empty list. With Chrome not connected to this login, the session ends naming the share as
the owner's step, with the link. The owner's name is the core's (`regatta/owner`).

The type ids are those `Artifact list scope=types` printed on 2026-10-10 (a work login); they are
[core] types and taken to be the same for every account (not yet seen from the primary: if a
design publish there gets no share line, the id differs — read it from that listing). A
quickstart with `intent: other` (a design system) cannot be told from any other page: the publish
from the type is what catches it. Probed 2026-10-10 (2.1.295): PreToolUse fires on Artifact with
tool_input {"action": "quickstart", "intent": "design"}.

Fails open: no registry, no row for this dir, unreadable input — the call passes. One exception:
with the registry there but the regatta core missing or broken, a design start is denied with one
line (the core reads the rows; B1 launch review, 2026-10-17), and the Post side says the line and
passes. Stdlib only, Python 3.9, never exits non-zero. Seams: ACCOUNTS_FILE (the registry),
ACCOUNT_LOGINS (the logins file). Tests: tests/hooks.sh, "design_route".
"""
import json
import os
import re
import sys
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("REGATTA_CONFIG") or HOME / ".config" / "regatta").expanduser()
CORE_MISSING = ("regatta core not found — clone the regatta repo, then write the config dir "
                "(the core's install.sh, or the overlay's bootstrap.sh --config)")
LIB = Path(__file__).resolve().parent.parent / "lib"


class CoreMissing(Exception):
    """The core would not load — missing or broken. Kept apart from account()'s other failures (a
    registry it cannot read), which still let a design start through unjudged."""


CREATED =re.compile(r"Created a new Artifact at (https://claude\.ai/(?:code/)?artifact/[A-Za-z0-9-]+)")
DESIGN_TYPES = {"QKN21svewxgyPb6SYRqWnd": "Design", "5M7UeXXcx16TP3vzVFNDzd": "Design System"}
ARTIFACT_URL = re.compile(r"https://claude\.ai/(?:code/)?artifact/([A-Za-z0-9-]+)")


def type_id(url):
    m = ARTIFACT_URL.search(url or "")
    return m.group(1) if m else ""


def design_start(ti):
    """The design type this call starts, or None."""
    action = ti.get("action") or "publish"
    if action == "quickstart" and ti.get("intent") == "design":
        return "Design"
    if action == "publish" and not ti.get("url"):
        return DESIGN_TYPES.get(type_id(ti.get("type_url")))
    return None


def core():
    """The regatta core's `common`, or CoreMissing: lib/find_core.py's places, in its order, but
    raising instead of exiting — this hook decides what a missing core means (header)."""
    sys.path.insert(0, str(LIB))
    try:
        import find_core
        found = next((c for c in find_core.candidates() if (c / "common.py").is_file()), None)
        if not found:
            raise CoreMissing("no core in any of find_core's places")
        sys.path.insert(0, str(found))
        import common
    except CoreMissing:
        raise
    except Exception as exc:  # a broken core as well as a missing one (B1 finish review)
        raise CoreMissing(exc) from exc
    return common


def account():
    """(label, primary label) for this session's config dir, or None when the registry can't say."""
    here = Path(os.environ.get("CLAUDE_CONFIG_DIR") or HOME / ".claude").expanduser().absolute()
    path = Path(os.environ.get("ACCOUNTS_FILE") or CONFIG / "lighthouse" / "accounts.json")
    if not os.environ.get("ACCOUNTS_FILE") and ((CONFIG / "regatta" / "overlay").exists() or (CONFIG / "legacy").exists()) and not path.exists():
        # the overlay is installed but this key is not written: a deny hook refuses, as for a
        # missing core, rather than read "no registry" as "nothing to route" (B9 review)
        raise CoreMissing("lighthouse/accounts.json missing — write it with the overlay's bootstrap.sh --config")
    reg = json.loads(path.read_text())
    common = core()
    rows = [a for a in common.account_rows(reg.get("accounts"), HOME) if (a.get("provider") or "claude") == "claude"]
    primary = next((a.get("label") for a in rows if a.get("primary")), None)
    mine = next((a.get("label") for a in rows if common.account_home(a, HOME) == here), None)
    return (mine, primary) if mine and primary else None


def materialise():
    """A Drive file not yet downloaded reads as EDEADLK in an agent's shell unless the process asks
    for dataless files to be fetched (IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES,
    IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_ON)."""
    try:
        import ctypes
        ctypes.CDLL(None).setiopolicy_np(3, 0, 2)
    except Exception:
        pass


def share_list():
    """[(email, access)] from the logins file's share.design ([] when it has none), or None when
    the file cannot be read."""
    p = os.environ.get("ACCOUNT_LOGINS")
    path = Path(p) if p else CONFIG / "lighthouse" / "logins.json"
    materialise()
    try:
        rows = json.loads(path.read_text()).get("share", {}).get("design") or []
    except Exception:
        return None
    return [(r["email"], r.get("access") or "view") for r in rows if isinstance(r, dict) and r.get("email")]


def owner(common):
    return getattr(common, "OWNER_NAME", "") or "the owner"


def tool_path(common, name):
    """A peer's path for the hand-off text, else its bare name (not installed here: the text still reads)."""
    try:
        return str(common.tool(name) or name)
    except Exception:
        return name


def pre(kind, who, common):
    mine, primary = who
    me = owner(common)
    host = common.config_line("lighthouse/design-host")
    on = (f"--on {host} --at @$(( $(date +%s) + 120 )) --fallback here --account bound` ({host} first; "
          f"this Mac when {host} cannot take it; ") if host else "--account bound` ("
    reason = (
        f"A new {kind} artifact is made on {primary}, the primary account, so {me} owns it "
        f"(lighthouse's hooks/design_route.py); this session is on {mine}. Hand it off instead of making "
        "it here: write the design brief (what to make, the design system to use, where the inputs "
        f"are) to a file, then `{tool_path(common, 'pickup')} seed <topic> --file <brief> --repo <repo> "
        "--no-start` (ignore the `dispatch … --next` line it prints: --next keeps this session's account) in the repo "
        "the work belongs to — or, when its AGENTS.md does not say `physical: none` (dispatch refuses "
        f"those), in the nearest sibling that does — and `bash {tool_path(common, 'dispatch')} <the "
        f"branch it printed> --repo <that repo> {on}bound is the "
        f"primary, picked when it starts). Then tell {me} where it runs, as dispatch said. If dispatch "
        "refuses (the primary has no room this week, or no repo fits), end with the WAITING line "
        f"naming why: {me} opens it on {primary} in person.")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "deny",
                                             "permissionDecisionReason": reason}}))


def post(kind, response, common):
    me = owner(common)
    text = response if isinstance(response, str) else json.dumps(response)
    created = CREATED.search(text)
    made = [m for m in ARTIFACT_URL.findall(text) if m not in DESIGN_TYPES]
    link = created.group(1) if created else (f"https://claude.ai/artifact/{made[0]}" if made
                                             else "the artifact this call created")
    who = share_list()
    if who is None:
        text = (f"The design share list could not be read (share.design in the logins file, "
                f"the config dir's lighthouse/logins.json): tell {me} {link} is not shared yet, and that "
                f"the share is {me}'s step.")
    elif who:
        people = ", ".join(f"{e} ({a})" for e, a in who)
        text = (f"Share {link} now ({me}, 2026-10-10: every new {kind} artifact is shared as it is made) "
                f"with {people}: with the Artifact tool's own `share` action when it offers one (it asks {me} "
                f"on a card, so only in a session {me} is in), else in Chrome (the Claude in Chrome tools): open "
                "it on claude.ai, Share, add each address at that access, and read the dialog back to "
                "confirm each one is listed. "
                "If Chrome is not connected to this login, or the dialog refuses an address, do not "
                f"retry: end by naming the share as {me}'s step, with the link and the addresses.")
    else:
        text = (f"No share list for design artifacts (share.design in the logins file, the config dir's "
                f"lighthouse/logins.json): tell {me} {link} is shared with nobody yet.")
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": text}}))


def main():
    data = json.load(sys.stdin)
    if data.get("tool_name") != "Artifact":
        return
    kind = design_start(data.get("tool_input") or {})
    if not kind:
        return
    event = data.get("hook_event_name")
    try:
        who = account()
    except CoreMissing as exc:
        # No core (regatta-modules C4): one line; and this being a deny hook, a design start is
        # refused rather than let through unjudged — the account it would run on is unknown.
        print(f"design_route: {CORE_MISSING} ({exc})", file=sys.stderr)
        if event == "PreToolUse":
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason": f"⛔ {CORE_MISSING}. design_route cannot tell which account "
                                            f"this {kind} artifact would belong to without it ({exc})."}},
                             ensure_ascii=False))
        return
    except Exception:
        return
    if not who:
        return
    mine, primary = who
    common = core()
    if event == "PreToolUse" and mine != primary:
        pre(kind, who, common)
    elif event == "PostToolUse" and mine == primary and kind in DESIGN_TYPES.values() \
            and (data.get("tool_input") or {}).get("action", "publish") == "publish":
        post(kind, data.get("tool_response"), common)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # a guard that crashes must not take the call with it
        print(f"design_route: {e}", file=sys.stderr)
    sys.exit(0)
