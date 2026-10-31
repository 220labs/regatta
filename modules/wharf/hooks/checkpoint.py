#!/usr/bin/env python3
"""Checkpoint commits + a one-writer lock per checkout — see rules/git-workflow.md.

Opt-in per project. Installed once, user-wide, by `bootstrap.sh --hooks`, so it fires in
every directory Claude Code opens; it acts only inside a git repo whose top level holds
`.claude/workflow.json`, and exits silently everywhere else (a plain folder, a repo that
never opted in, a repo that still wires its own copy). A repo that must never opt in carries
`.claude/no-workflow` instead: the hook then ignores any workflow.json beside it and denies
creating one (see NO_WORKFLOW_FILE). The file is small:

  {
    "checkpoint": true,             # false (or no file) = this hook does nothing here
    "main": "main",                 # the branch the primary checkout rests on
    "live_write_regex": "…",        # optional: Bash that writes to a LIVE system, not git —
                                    # denied on main and under another session's lock, like
                                    # a commit. (The home-automation repo: its deploy scripts
                                    # without --check-only.)
    "unattended_deny_regex": "…",   # optional: Bash an UNATTENDED run (its marker set,
                                    # bin/dispatch) may never run here, on top of the live-write
                                    # regex and any --live-ok/--estate-ok: what acts on the live
                                    # system without being a deploy (the home repo: ha.py call, test.py
                                    # tiers 2-3). See UNATTENDED_NAMES.
    "in_place": ["memory/", "log.md"]  # optional: records an Edit/Write may change ON the
  }                                 # primary's main — a folder ("x/") or one file. No lock, no
                                    # checkpoint; the repo's own committer takes them (the vault:
                                    # vault_commit.py at session end). Everything else on main
                                    # is denied as anywhere. Bash is untouched: the baseline
                                    # judges git verbs. (The vault, docs/personal-on-workflow-
                                    # 2026-09-29.md.) bin/knowledge-commit reads it too, and a
                                    # "records" key beside it that only it reads.

Born in the home-automation repo (2026-09-10…16); the dated incidents below happened there.

Events:

  UserPromptSubmit  commit anything left dirty since the last turn (an interrupted
                    turn, or edits made outside Claude), then queue the new prompt.
                    Also, at most once an hour repo-wide, sweep orphaned claude/*-raw
                    backups — see sweep_raw_branches() (2026-09-16).
  PreToolUse        two gates, in order (below), and on the ALLOW path one record: a Bash
                    command that takes content from ANOTHER claude/* branch or worktree
                    (merge/rebase of a whole branch; checkout <ref> -- <paths>, restore
                    --source, cherry-pick, a cp from a sibling worktree, a diff piped into
                    git apply — parts of one) appends `<kind> <commit> <branch>` to this
                    worktree's .git/…/claude/carries, once the gates have passed and the lock
                    is this session's. /finish reports it; bin/pr merge closes a carried
                    branch's PR only after proving its content is on main — the record is a
                    pointer, never proof — see carry_sources() (the owner's D2, 2026-09-24;
                    tightened after the two reviews the same day). A `git merge` on main
                    stays allowed whatever it carries: launching is the one write main takes.
                    The gates: (1) the primary checkout stays on main always
                    — any write there is denied, telling Claude to make a worktree
                    (2026-09-15), EXCEPT launching a finished branch (`git merge`) and,
                    only while that merge is actually in progress (MERGE_HEAD present),
                    resolving its conflicts (add/commit/checkout/reset/restore/rm, and
                    Edit/Write on tracked files) — added 2026-09-15 at the user's
                    request, narrowed to that window so nothing else counts as an
                    "arbitrary file" on main; (2) inside a worktree, the /move marker
                    (common.MOVED_FILE, beside the lock): the branch went on on another
                    machine or in the cloud, so every write here is denied with where it
                    went and the way back, whoever owns the lock (teleport design E4,
                    2026-10-02); (3) the lock — the
                    first session to write there owns it, another session's writes are
                    denied (Edit/Write/NotebookEdit; git-mutating and deploying Bash,
                    best-effort).
                    A marked worktree also takes no checkpoint and no push at any event
                    (a commit here would fork the branch from the one now growing
                    elsewhere); its prompts print the marker's line, and SessionEnd still
                    frees the lock.
  Stop              commit the turn's changes: Claude's summary (commit-summary.md in
                    the session scratchpad) + every prompt this session queued since its
                    last commit. A commit that adds `➤ Answer:` lines to a .md file, or
                    any line to a doc that has them, is pushed at once; one that asks (adds
                    a D-item) blocks the reply once until it carries the doc's hand-over
                    line (`keel line`) — see answer_docs(), answer_link_block(). Each pushed
                    D-list doc is then mirrored as a page (keel's mirror) (`keel sheep`), the
                    line's `space` part — see sheep_pages(). On a claude/* branch it
                    writes claude/last-reply (autofinish's idle clock), and a reply ending
                    in the declared line, or a turn under `/autofinish now`, hands the
                    branch to bin/autofinish — see autofinish_at_stop().
  SessionEnd        release the lock; push; on a claude/* branch, bin/autofinish judges the
                    worktree a minute later, detached (autofinish design E3).
  (autofinish)      while its runner holds the lock, a prompt is told so once and a write is
                    refused with the same words; afterwards the outcome is said once.

Checkpoints: prompts queue in .git/claude/prompts.json (per session id), so a discussion
turn that changed nothing still goes into the commit its changes eventually produce. A turn
with changes but no commit-summary.md falls back to Stop's own `last_assistant_message`
(Claude's chat response, handed to the hook for free — see derive_summary()) instead of a
bare `wip(no-summary): <prompt>`; only a turn that changed files AND left no usable response
text is committed as true wip(no-summary), and UserPromptSubmit reminds Claude the next turn when
that happens. Commits only on claude/* branches, never mid-rebase/merge or while /finish is
restructuring (.git/claude/finishing) — a merge made on main is a deliberate act, not a
checkpoint, and is never auto-committed by this hook. The primary checkout stays on main,
always — no branch switch ever happens there, and no write either, apart from merging a
finished branch in and resolving its conflicts (see is_write() / decide() below);
anything else is denied, and the deny reason tells Claude to `git worktree add` +
EnterWorktree first. Every claude/* branch and its checkpoint commits therefore live in a
worktree, not the primary checkout — only a `git merge` commit itself is made directly on
main.

The lock (.git/claude/owner.json: session, branch, last seen) exists because two sessions
in one checkout share one working tree and one branch — on 2026-09-10 each one's
checkpoints swept up the other's edits and prompts. Only the owner commits. The owner is
warned if the branch changed under it between turns. The lock frees on SessionEnd, or
after OWNER_TTL idle, or when the owner marks it `handover` (bin/pickup next): then the next
writer takes it — `pickup open --fresh` in the tab it opened, at once — and the owner's next
prompt withdraws the mark. A second session belongs in its own worktree (the deny reason says
how); state lives in the per-worktree git dir, so each worktree has its own lock and queue.

Stdlib only. Never blocks a turn: any failure is reported and the hook exits 0.
"""
import datetime
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
# The core is the regatta module beside this one, else the one the config dir or Claude Code's
# plugin registry names (lib/core_path.py, the design's C2); none found puts nothing on the path,
# and the `import common` below raises. Without it this hook would die on import with exit 1, which Claude Code reads as "no
# objection": the main-write and bare-push denies would vanish (B1 launch review, 2026-10-17).
# So run as a hook it fails closed instead — core_missing(), below main(). An importer (sync.py,
# a test) gets the ImportError and decides for itself.
CORE_MISSING = ("regatta core not found — clone the regatta repo, then write the config dir "
                "(the core's install.sh, or the overlay's bootstrap.sh --config)")
try:
    sys.path.insert(1, str(Path(__file__).resolve().parent.parent / "lib"))
    import core_path  # noqa: E402
    import knowledge  # noqa: E402 — the knowledge repos' names, from atlas's keys (stdlib only)
    core_path.add()
    import common  # noqa: E402 — host name and the GitHub client, shared with sync.py and bin/pr
    common.OWNER_TTL, common.landed_pr  # an out-of-step core fails here, before a judgement, not halfway through one
    core_error = None
except Exception as exc:  # not ImportError alone: a syntax error, an unreadable file or a missing
    # name in the core killed the hook the same way (exit 1, read as allow; B1 finish review)
    if __name__ != "__main__":
        raise
    common, core_error = None, exc

SUMMARY_NAME = "commit-summary.md"
MAX_DERIVED_LEN = 1200  # cap on a chat-response-derived summary — see derive_summary()
WORKFLOW_FILE = Path(".claude") / "workflow.json"
# A repo that must NEVER join the workflow says so here, in one line of prose that the deny
# message quotes. It beats any workflow.json beside it, and creating one is denied outright:
# `/new-project . --adopt` takes "." from whichever session happens to be open, and on
# 2026-09-17 that was the knowledge layer itself, where ~/.claude points at
# the main checkout, so a worktree edit is live nowhere until it merges (DESIGN D17, undone).
NO_WORKFLOW_FILE = Path(".claude") / "no-workflow"
MAIN = "main"  # replaced from workflow.json in main() — the session's checkout; a `cd X &&`
# target carries its own (Target.main)
# The VS Code extension prefixes prompts with which file is open — noise, not intent.
# (An <ide_selection> is kept: the user chose that context.)
IDE_NOISE_RE = re.compile(r"<ide_opened_file>.*?</ide_opened_file>\s*", re.S)
MAX_PROMPT_CHARS = 4000  # a pasted log shouldn't bloat every checkpoint
MAX_PROMPTS = 20
QUEUE_TTL = 24 * 3600  # another session's uncommitted prompts are dropped after this
OWNER_TTL = common.OWNER_TTL if common else None  # an owner idle this long has gone; the next writer takes over
# Every claude/* branch is pushed to origin as it grows, so the work is visible off this
# machine — GitHub is the hub between the laptop and the other Mac (docs/record/repo-sync-2026-09-22.md,
# flow A). The first push opens a `WIP:` pull request. Pushes are spaced by PUSH_EVERY per
# branch (a chatty session is not a push storm) and always happen at SessionEnd; a failure
# (offline, a branch of the same name pushed from the other machine) is one note, never a
# retry loop and never --force. The Bash guard below is for Claude's commands; this push is
# the hook's own subprocess and goes through the repo's pre-push like any other.
PUSH_EVERY = 600
PUSH_TIMEOUT = 30
# /finish sets `finishing` to stand the hook down while it rewrites history, and removes it
# at the end. A /finish that is abandoned (interrupted, or the session just ends) leaves it
# behind, and it then disables checkpoints for EVERY later session in that checkout — with
# no warning, because a stale marker also suppresses the off_workflow() nag. That is exactly
# what happened 2026-09-10→11: one session's abandoned /finish cost another a turn's work.
# A /finish is minutes, not hours, so anything older than this is abandoned by definition.
FINISHING_TTL = 2 * 3600
# Orphaned `claude/*-raw` backups (finish.md → "Nothing to finish?") are swept on a prompt
# at most once an hour, repo-wide, and only once the backup is RAW_GRACE old: a merge
# launched minutes ago still needs its -raw as the rollback finish.md step 11 promises.
SWEEP_EVERY = 3600
RAW_GRACE = 2 * 3600
DEDUPE_WINDOW = 5  # seconds — see already_handled()
TRAILER = "Co-Authored-By:"
DEFAULT_TRAILER = "Co-Authored-By: Claude <noreply@anthropic.com>"
BUSY_MARKERS = ("rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD")
WRITE_TOOLS = {"Edit", "Write", "NotebookEdit"}
# Bash that changes a checkout's git state is recognised by verb (MUTATING_VERBS below, per
# simple command). Best-effort: arbitrary shell writes can't be recognised, but these are the
# ones sessions actually run. A project adds its own live-system writers (deploy scripts)
# through workflow.json's live_write_regex (Target.live_re).
# The one exception to "no writes on main": launching a finished branch. `git merge` itself
# is always allowed there (that's the whole point — 2026-09-15, at the user's request).
# The conflict-resolution verbs that go with a REAL (non-fast-forward) merge are allowed
# only while one is actually in progress (MERGE_HEAD present) — `git switch`/`rebase`/
# `stash`/etc. stay blocked even then, since none of them are part of finishing a merge.
# Judged per verb, in decide(): a `git merge` in the command excuses only itself (the owner's D7,
# 2026-09-25 — before, it let the whole line through, `git merge x && git checkout claude/y -- f`
# included).
# CREATING a project's opt-in file, in a repo that carries .claude/no-workflow. Write tools
# hand over the path; in Bash this is best-effort like the verb check in judge_bash() and covers the form
# /new-project runs: `cd <path> && … printf … > .claude/workflow.json && …`. It must match on
# writing, not on mentioning: the first version denied any command containing the path, which
# would have blocked `git log -- .claude/workflow.json` in the two repos most likely to need
# it. A write the patterns miss leaves an inert file — load_workflow() ignores it anyway.
ADOPT_WRITE_RE = re.compile(r">>?\s*[\w./~$-]*\.claude/workflow\.json"
                            r"|\b(?:tee|cp|mv|install|touch|ln|dd)\b[^;&|]*\.claude/workflow\.json")
ADOPT_PATH_RE = re.compile(r"[\w./~$-]*\.claude/workflow\.json")
CD_PREFIX_RE = re.compile(r"^\s*cd\s+(?!-)([^\s;&|]+)")
# `git` as a command word, with any global options before the verb: `-C dir` (once or more),
# `-c k=v`, `--git-dir=…` or `--git-dir …`, `--no-pager`, and `"git"` / `'git'` quoted — shared
# by the push, tracking and write guards. The write guard's first version allowed one `-C` and
# nothing else, so `git -c k=v commit`, `"git" commit`, `git --git-dir=… --work-tree=… commit`
# and `git -C a -C b commit` were never writes (the owner's D6, 2026-09-25). An option's value may be
# quoted. Every token parses exactly one way — an option that takes a value is never also a bare
# flag, a value never starts two ways, `--x` is `-` + `-x` only: the push and tracking guards'
# old prefix let `git --a --a …` split each token twice, so eighteen took 15 s and sixty hung the
# hook (found testing D6, 2026-09-25).
_OPT_VALUE = r"(?:\"[^\"]*\"|'[^']*'|[^\s\"'])\S*"
_OPT_WITH_ARG = r"(?:-C|-c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix)"
GIT_PREFIX = (r"\bgit[\"']?(?:\s+(?:" + _OPT_WITH_ARG + r"\s+" + _OPT_VALUE
              + r"|(?!" + _OPT_WITH_ARG + r"(?:\s|$))-[^\s=\"']+(?:=" + _OPT_VALUE + r")?))*\s+")
# Moving `main` is the owner's act alone (rule: git-workflow, "Everywhere"). An agent may push its
# own `claude/*` branch and open a PR; everything else is denied, in every repo and folder,
# opted in or not — after the 2026-09-10 force-push the rule had four prose homes and no
# mechanism (dream 2026-09-16, P1), and the namespace was opened up on 2026-09-19 so the
# honest path exists, because a rule the owner has to work around daily is a rule that gets
# deleted. Global options before the verb (`-C dir`, `-c k=v`, `--git-dir=…`) are allowed
# for; `git log --grep push` is not a push. `git` must stand where a command starts (line
# start, after ; & | ( or `$(`, optionally behind VAR=value or env/command/exec) — otherwise
# a grep for the words "git push" is denied too, which is what the first version did on its
# first day.
PUSH_RE = re.compile(
    r"(?:^|[;&|(]|\$\()\s*(?:(?:env|command|exec|nohup|time)\s+|\w+=\S*\s+)*"
    + GIT_PREFIX + r"push\b", re.M)
# The one shape an agent may push, named in full rather than subtracted from: an explicit
# remote and an explicit `claude/…` ref. A bare `git push` is denied even on a claude/*
# branch, because what it pushes depends on push.default and the upstream — this hook reads
# command text, and text that needs repo state to interpret cannot be judged here.
SAFE_PUSH_RE = re.compile(
    r"^\s*(?:(?:env|command|exec|nohup|time)\s+|\w+=\S*\s+)*"
    r"git(?:\s+(?:-C\s+\S+|--git-dir=\S+|--work-tree=\S+))*\s+push"
    r"(?:\s+(?:-u|--set-upstream|--force-with-lease(?:=\S+)?|-q|--quiet|-n|--dry-run))*"
    r"\s+[\w.@-]+"                                  # the remote
    r"(?:\s+(?:HEAD:)?(?:refs/heads/)?claude/[\w./-]+)+\s*$")
# A branch that tracks a remote ref is a loaded gun: VS Code's Sync pushes a branch onto
# whatever it tracks, and the pre-push guard trusts the button as the owner's click. On 2026-09-24
# `git checkout -b claude/… origin/main` set that upstream and one click fast-forwarded
# household's main to an agent commit. The recipe starts from local `main`, which sets no
# upstream; creating or pointing a branch at origin/… (anything but origin/claude/…) is
# denied unless `--no-track` says so. Text-level, like PUSH_RE; pre-push refuses the push too.
TRACK_RE = re.compile(
    GIT_PREFIX + r"(?:"
    r"(?:checkout|switch)\s+[^;&|]*?(?<![\w-])(?:-[bBcCt]|--track)(?:\s|=)[^;&|]*?"
    r"(?<![\w./-])(?:origin|refs/remotes)/(?!claude/)"
    r"|branch\s+[^;&|]*?(?<![\w-])(?:--set-upstream-to|-u|--track|-t)(?:\s+|=)"
    r"(?:origin|refs/remotes)/(?!claude/)"
    r"|branch\s+(?:-[a-zA-Z]+\s+)*(?!-)[\w./-]+\s+(?:origin|refs/remotes)/(?!claude/)"
    # `worktree add -b <new> <path> origin/main` tracks it too (branch.autoSetupMerge), and it
    # is the shape a session reaches for when local main is stale (review, 2026-09-25).
    r"|worktree\s+add\s+[^;&|]*?(?<![\w-])(?:-[bB]|--track)(?:\s|=)[^;&|]*?"
    r"(?<![\w./-])(?:origin|refs/remotes)/(?!claude/)"
    r")")
NO_TRACK_RE = re.compile(r"--no-track\b")
# `pickup archive … --confirmed` writes "Probably launched, confirmed by the owner" as the archive's
# reason (coding-on-workflow D6, 2026-09-26). The owner types it; an agent running it would put
# the owner's name on a judgement the owner never made. Quoted text is blanked first, so a commit message
# or a doc naming the command is not the command.
CONFIRMED_RE = re.compile(r"\bpickup\b[^;&|\n]*\barchive\b[^;&|\n]*--confirmed\b")
# Denied whatever else matches, because each one defeats the layer that actually decides —
# `pre-push`, which reads the real ref list on stdin. `--no-verify` skips it outright;
# `-c core.hooksPath=…` unhooks the repo for that one command; `--receive-pack`/`--exec`
# run a program of their choosing on the far side. None has an honest use here.
PUSH_BYPASS_RE = re.compile(r"--no-verify|hooksPath|--receive-pack|--exec\b", re.I)
# Quoted text is blanked before matching: `grep 'a|git push'` is a search, not a push.
# (A push hidden inside `bash -c '…'` slips through — this guards habit, not malice.)
QUOTED_RE = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"")

ROOT = "."
# Another CLI's call, through lighthouse's hooks/vendor_hook.py (vendor-hooks, the owner's D2-A,
# docs/codex-agy-gaps-2026-10-29.md): its payload carries `regatta_cli` (`codex`, `antigravity`), and
# main() sets this. Such a call meets every gate here — D1's deletions, the push and tracking denies, a
# write on a primary's main, a moved branch — but takes and honours no lock and records no carry: the
# lock frees at a session's end, which only Claude Code's hooks report to this hook today, so a Codex or
# Antigravity session would hold every worktree it wrote in for OWNER_TTL (the gaps doc's D3 asks
# whether a CLI's session end should free it instead; D3-A: no lock). An unattended one, its marker under
# either name (unattended_mark), is also refused what dispatch's launch-time `denied=(…)` list refuses a
# Claude run (vendor_denied), since a Codex or Antigravity run never reads Claude's permission rules.
VENDOR = ""
# dispatch's denied list, verb by verb, judged on each simple command's words (a commit message that
# mentions `pr merge` is a word, never a verb): (what the refusal names, a test of the words). The
# Claude rules are prefixes (`Bash(gh:*)`) or substrings (`Bash(*bin/pr merge*)`); this reads the verb
# itself, so `git -C x push` and `env X=1 gh …` are caught too. wharf's test_checkpoint.sh reads the list
# from wharf-runs' dispatch and fails on an entry no test here covers.
# kick, --kick and dispatch-rc kick-listen: dispatch-queue S8 added them to dispatch's list (landed beside this
# rule, which then failed its own count on main; build-review's landing, 2026-10-31)
DISPATCH_QUEUE_VERBS = {"enqueue", "claim", "sweep", "poll", "jobs", "unreserve", "requeue", "kick"}
DISPATCH_FLAGS = ("--claim", "--poll", "--requeue", "--kick")
DISPATCH_RC_VERBS = {"kick-listen"}


def vendor_denied(command):
    """The first verb of dispatch's launch-time deny list that COMMAND runs, as text, or None."""
    for words, _, _ in simple_commands(command):
        if not words or words[0] in ("(", ")"):
            continue
        base = [os.path.basename(w) for w in words]
        if base[0] == "git" and git_verb(words)[0] == "push":
            return "git push"
        if base[0] in ("gh", "ssh"):
            return base[0]
        if any(w.endswith("scripts/deploy.py") for w in words[:2]):
            return "scripts/deploy.py"
        for i, b in enumerate(base[:-1]):
            # `pr` as the verb: bin/pr or libexec/pr by path, `regatta pr`, `gh pr` — never `echo pr merge`
            if b == "pr" and words[i + 1] in ("merge", "ready") and (i == 0 or "/" in words[i] or base[i - 1] in ("regatta", "gh")):
                return f"pr {words[i + 1]}"
            if b == "dispatch-rc" and words[i + 1] in DISPATCH_RC_VERBS:
                return f"dispatch-rc {words[i + 1]}"
            if b == "dispatch-queue" and words[i + 1] in DISPATCH_QUEUE_VERBS:
                return f"dispatch-queue {words[i + 1]}"
            if b == "dispatch" and any(w.split("=", 1)[0] in DISPATCH_FLAGS for w in words[i + 1:]):
                return "dispatch " + next(w.split("=", 1)[0] for w in words[i + 1:] if w.split("=", 1)[0] in DISPATCH_FLAGS)
    return None


def git(*args, input=None, check=True):
    return subprocess.run(["git", *args], cwd=ROOT, input=input,
                          capture_output=True, text=True, check=check)


def is_forbidden(path):
    """Second guard behind .gitignore: secrets never get auto-committed, even if an
    ignore rule slips. .env.example is the one tracked env file and is fine."""
    parts = Path(path).parts
    name = parts[-1]
    return (name == ".env" or (name.startswith(".env.") and name != ".env.example")
            or name == "secrets.yaml" or ".storage" in parts)


# ---- carries: what a branch takes from another branch ----------------------------------
#
# The home repo's drift rule says: when live HA runs another session's unmerged branch, take that
# branch's whole blob as your base and re-apply only your hunks. The session that does so then
# launches BOTH branches' content through its own PR — and the other branch, its PR and its
# worktree stay behind, because GitHub deletes only the merged head and an agent may never
# delete a branch. On 2026-09-24 two such branches had sat for days, and after /finish's
# rewrite no heuristic could prove one of them launched (hooks/branches.py). The only certain
# record is one made at carry time, and the hook already reads every Bash command a session
# runs, so it writes that record here: `<worktree git dir>/claude/carries`, one line per
# carry — `<kind> <commit> <branch>`, the commit being what the source pointed at when it was
# taken. A record is a POINTER, never proof: a merge refused on a dirty tree or aborted, a
# resolution that dropped a file and `merge -s ours` all leave the same line (second review,
# 2026-09-24). /finish reads it (bin/pr carried / merge) to know which branches to prove
# against origin/main after the launch; branches.py shows it as "carried by <branch>
# (whole|part), not proved" until that proof exists.
#
# Written only on the hook's allow path, into the worktree whose lock this session holds:
# the first version recorded at detection, so a denied command, an aborted cherry-pick, a
# heredoc body and a `git diff … > review.patch` all left records (review of 2026-09-24).
# Now heredoc bodies are stripped, quotes are honoured (`;` inside them splits nothing),
# reads (show/diff/log) count only when piped into `git apply`/`git am`/`patch`, and a carry
# command counts as a write, so it passes the same two gates as a commit. No git call unless
# a token looks like a ref, a sha or a sibling worktree path.
CARRIES_NAME = "carries"
CARRY_PRECHECK_RE = re.compile(
    r"claude/|\.claude/worktrees/|\.\./|\b(?:cherry-pick|checkout|restore|merge|rebase|pull)\b")
CLAUDE_REF_RE = re.compile(r"^(?:refs/heads/|refs/remotes/)?(?:origin/)?(claude/[\w./-]+?)(?:[~^]\S*|:\S*)?$")
SHA_RE = re.compile(r"^([0-9a-f]{7,40})(?:[~^]\S*|:\S*)?$")
HEREDOC_RE = re.compile(r"(?<!<)<<-?\s*(['\"]?)(\w+)\1")  # never a here-string's `<<< word`
PATHISH_RE = re.compile(r"\.claude/worktrees/|^\.\./|^/|^~")
COPY_CMDS = {"cp", "rsync", "install", "mv", "ln", "ditto"}
SHELL_KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until", "!", "{", "}"}
WRAPPERS = {"env", "command", "exec", "nohup", "time", "sudo", "nice", "timeout", "xargs", "caffeinate", "stdbuf"}
WRAPPER_OPT_WITH_ARG = {  # a wrapper's options that take their own argument, so it is never the command
    "nice": {"-n", "--adjustment"}, "timeout": {"-s", "--signal", "-k", "--kill-after"},
    "xargs": {"-n", "-I", "-P", "-L", "-s", "-E", "-d", "-J", "--max-args", "--max-procs", "--max-lines"},
    "env": {"-u", "-C", "-S", "--unset", "--chdir"}, "caffeinate": {"-t", "-w"}, "sudo": {"-u", "-g", "-C", "-D", "-h"}}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
UNRESOLVABLE_RE = re.compile(r"[$`]")
GIT_OPT_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
# Options of the verbs below that take their own argument, so it is never read as a ref.
VERB_OPT_WITH_ARG = {"-m", "--mainline", "-s", "--strategy", "-X", "--strategy-option", "-S",
                     "--gpg-sign", "--onto", "--exec"}
NOT_A_CARRY = {"--continue", "--abort", "--skip", "--quit", "-b", "-B", "--orphan", "--ours", "--theirs"}
OPERATORS = {";", "&&", "||", "&", "(", ")"}  # shlex's punctuation tokens that end a pipeline
REDIRECTS = {">", ">>", ">|", "<", "<<", "<<<", ">&", "<&", "&>", "&>>"}
TO_FILE = {">", ">>", ">|", "&>", "&>>"}
APPLIERS = {"apply", "am"}  # git verbs that turn a piped diff into content
NOT_APPLYING = {"--check", "--dry-run", "--stat", "--numstat", "--summary"}  # …unless they only look


class CarryContext:
    """One checkout the command acts in: the session's cwd, or the target of a leading `cd`
    or `git -C`. Lazy — most commands never need a git call."""

    def __init__(self, root, branch=None, gitdir=None, main=None):
        self.root = Path(root)
        self._branch, self._gitdir, self._top, self._wts = branch, gitdir, None, None
        self._main = main

    @property
    def main(self):
        return self._main or MAIN

    def run(self, *args):
        r = subprocess.run(["git", "-C", str(self.root), *args], capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""

    @property
    def branch(self):
        if self._branch is None:
            self._branch = self.run("symbolic-ref", "--quiet", "--short", "HEAD")
        return self._branch

    @property
    def gitdir(self):
        if self._gitdir is None:
            self._gitdir = Path(self.run("rev-parse", "--absolute-git-dir") or (self.root / ".git"))
        return self._gitdir

    @property
    def toplevel(self):
        if self._top is None:
            top = self.run("rev-parse", "--show-toplevel")
            self._top = Path(top).resolve() if top else self.root.resolve()
        return self._top

    @property
    def own(self):
        return {self.branch, f"origin/{self.branch}"}

    def worktrees(self):
        """[(path, branch)] of the repo's worktrees, deepest path first — they live under the
        primary checkout, whose path is a parent of every one of theirs."""
        if self._wts is None:
            wts = []
            for block in self.run("worktree", "list", "--porcelain").split("\n\n"):
                path = branch = None
                for line in block.splitlines():
                    if line.startswith("worktree "):
                        path = line[9:]
                    elif line.startswith("branch refs/heads/"):
                        branch = line[len("branch refs/heads/"):]
                if path and branch:
                    try:
                        wts.append((Path(path).resolve(), branch))
                    except OSError:
                        continue
            self._wts = sorted(wts, key=lambda w: len(w[0].parts), reverse=True)
        return self._wts

    def worktree_hit(self, token):
        """(commit, branch) for the sibling claude/* worktree `token` points into, or None —
        this checkout's own tree and the primary checkout on main never count."""
        tok = token.lstrip("<>")
        if not tok or not PATHISH_RE.search(tok):
            return None
        p = Path(os.path.expanduser(tok))
        if not p.is_absolute():
            p = self.root / p
        try:
            p = p.resolve()
        except OSError:
            return None
        for path, branch in self.worktrees():
            if p == path or path in p.parents:
                if path == self.toplevel or not branch.startswith("claude/"):
                    return None
                r = subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"], capture_output=True,
                                   text=True, timeout=10)
                sha = r.stdout.strip() if r.returncode == 0 else ""
                return (sha, branch) if sha else None
        return None

    def sha_of(self, token):
        return self.run("rev-parse", "--verify", "-q", f"{token}^{{commit}}")

    def resolve(self, token):
        """[(commit, branch)] a ref token stands for: a claude/* name as written (local or
        origin/, `~1` and `:path` suffixes allowed) pinned to the commit it names now, or the
        claude/* branches containing a sha — minus this checkout's own branch and anything
        already in main or in this branch's own history (shared, not carried)."""
        m = CLAUDE_REF_RE.match(token)
        if m:
            if m.group(1) in self.own:
                return []
            sha = self.sha_of(re.sub(r":\S*$", "", token))
            return [(sha, m.group(1))] if sha else []
        m = SHA_RE.match(token)
        if not m:
            return []
        sha = self.sha_of(m.group(1))
        if not sha:
            return []
        for ancestor_of in (self.main, f"origin/{self.main}", "HEAD"):
            if subprocess.run(["git", "-C", str(self.root), "merge-base", "--is-ancestor", sha, ancestor_of],
                              capture_output=True, timeout=10).returncode == 0:
                return []
        names = set()
        for ref in self.run("for-each-ref", "--format=%(refname:short)", f"--contains={sha}",
                            "refs/heads/claude/", "refs/remotes/origin/claude/").split():
            name = ref[len("origin/"):] if ref.startswith("origin/") else ref
            if name not in self.own and not name.endswith("-raw"):
                names.add(name)
        return [(sha, name) for name in sorted(names)]


def strip_heredocs(command):
    """The command with every heredoc body removed — text fed to a program, not a command.
    `git commit -F - <<EOF … git merge claude/x … EOF` mentions a merge and performs none."""
    lines, kept, i = command.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]
        kept.append(line)
        m = HEREDOC_RE.search(line)
        i += 1
        if m:
            term = m.group(2)
            while i < len(lines) and lines[i].lstrip("\t") != term:
                i += 1
            i += 1  # the terminator line
    return "\n".join(kept)


def tokenize(line):
    """Shell words with quotes honoured and operators (`;`, `&&`, `|`, `>`, `2>&1`…) as their
    own tokens, so a `;` inside a commit message splits nothing."""
    lx = shlex.shlex(line, posix=True, punctuation_chars=True)
    lx.whitespace_split = True
    try:
        return list(lx)
    except ValueError:
        return line.split()


def is_applier(words):
    """A stage that turns a piped diff into content: `git apply`, `git am`, `patch` — unless
    it only checks (`--check`, `--dry-run`, `--stat`…), which writes nothing; `--apply` beside
    one of those (`git apply --stat --apply`) really applies."""
    if not words or (any(w in NOT_APPLYING for w in words) and "--apply" not in words):
        return False
    if words[0] == "patch":
        return True
    return words[0] == "git" and git_verb(words)[0] in APPLIERS


def strip_wrappers(words):
    """The command proper: shell keywords (`then git …`, `do git …`, `! git …`, `{ git …`),
    assignments, and process wrappers with their own options (`timeout 30 git …`, `xargs -0 git
    …`, `nice -n 5 git …`, `env FOO=y git …`) come off the front. The fourth review (2026-09-25)
    hid a write on main behind every one of these."""
    while words:
        w = words[0]
        if w in SHELL_KEYWORDS or re.match(r"^\w+=", w):
            words.pop(0)
            continue
        if os.path.basename(w) in WRAPPERS:  # `/usr/bin/env python3 -` too
            w = os.path.basename(w)
            words.pop(0)
            with_arg = WRAPPER_OPT_WITH_ARG.get(w, set())
            while words and words[0].startswith("-") and words[0] != "--":
                if words.pop(0) in with_arg and words:
                    words.pop(0)
            if words and words[0] == "--":
                words.pop(0)
            if w == "timeout" and words and re.match(r"^\d+(?:\.\d+)?[smhd]?$", words[0]):
                words.pop(0)
            continue
        break
    return words


def simple_commands(command):
    """Every simple command in `command`, in order, as (words, writes a file, a later stage of
    its pipeline applies): words with redirects, keywords and wrappers removed. Knowing the
    pipeline tells `git show <ref>:<p> | git apply` (a carry) from `git show <ref>:<p> | head`
    (a read). A `bash -c '…'` / `sh -c` / `eval` payload is parsed as its own command. A `(` or
    `)` is yielded as a one-word marker, so a caller can scope a `cd` to its subshell."""
    for line in strip_heredocs(command).split("\n"):
        units, current = [], []
        for t in tokenize(line):
            if t in OPERATORS:
                units.append(current)
                current = []
                if t in ("(", ")"):
                    units.append(t)
            else:
                current.append(t)
        units.append(current)
        for unit in units:
            if unit in ("(", ")"):
                yield [unit], False, False
                continue
            stages, stage = [], []
            for t in unit:
                if t == "|":
                    stages.append(stage)
                    stage = []
                else:
                    stage.append(t)
            stages.append(stage)
            parsed = []
            for stage in stages:
                words, sink, i = [], False, 0
                while i < len(stage):
                    t = stage[i]
                    if t in REDIRECTS:
                        target = stage[i + 1] if i + 1 < len(stage) else ""
                        sink |= t in TO_FILE and target not in ("", "/dev/null")
                        i += 2
                        continue
                    words.append(t)
                    i += 1
                parsed.append((strip_wrappers(words), sink))
            for n, (words, sink) in enumerate(parsed):
                if words and os.path.basename(words[0]) in SHELLS:
                    # `bash -c '…'`, `bash -lc`, `sh -xc`: the payload is the first word after
                    # an option cluster holding `c`
                    i = next((k for k, w in enumerate(words[1:], 1) if w.startswith("-") and "c" in w[1:]), None)
                    if i is not None and i + 1 < len(words):
                        yield from simple_commands(words[i + 1])
                        continue
                if words and words[0] == "eval":
                    yield from simple_commands(" ".join(words[1:]))
                    continue
                yield words, sink, any(is_applier(w) for w, _ in parsed[n + 1:])


def git_verb(tokens):
    """(verb, its args, [-C dirs in order]) for a `git …` token list, global options consumed.
    `-C a -C b` is applied in sequence by git, `b` relative to `a`."""
    i, cdirs = 1, []
    while i < len(tokens) and tokens[i].startswith("-"):
        opt = tokens[i]
        if opt in GIT_OPT_WITH_ARG:
            if opt == "-C" and i + 1 < len(tokens):
                cdirs.append(tokens[i + 1])
            i += 2
        else:
            i += 1
    return (tokens[i] if i < len(tokens) else None), tokens[i + 1:], cdirs


def positionals(args, with_arg=VERB_OPT_WITH_ARG):
    """Non-option arguments, an option's own argument skipped; None if the command is one of
    the shapes that never carry (a branch creation, --continue, --ours/--theirs)."""
    result, i = [], 0
    while i < len(args):
        a = args[i]
        if a in NOT_A_CARRY:
            return None
        if a == "--":
            result.extend(args[i + 1:])
            break
        if a in with_arg:
            i += 2
            continue
        if a.startswith("-"):
            i += 1
            continue
        result.append(a)
        i += 1
    return result


def resolve_dir(base_root, path):
    """The directory `path` names from `base_root`, or None when it cannot be known here — a
    `$VAR` or backtick, `cd` with no argument, `cd -`, a path that does not exist, a symlink
    loop. The caller then judges by the session's own checkout, as the hook always did."""
    if not path or UNRESOLVABLE_RE.search(path):
        return None
    p = Path(os.path.expanduser(path))
    if not p.is_absolute():
        p = Path(base_root) / p
    try:
        p = p.resolve()
    except (OSError, RuntimeError):  # 3.9 raises RuntimeError on a symlink loop
        return None
    return p if p.is_dir() else None


def at(ctx, path, fallback):
    """A context for `path` as written in the command, relative to ctx's checkout; `fallback`
    (the session's) when the path cannot be resolved."""
    p = resolve_dir(ctx.root, path)
    return CarryContext(p) if p is not None else fallback


def carry_sources(command, root, default=None):
    """{git dir: [(kind, commit, branch), …]} for what `command` takes from other claude/*
    branches, per checkout it acts in (a leading `cd X &&` or `git -C X` moves the checkout).
    Kinds: `merge`/`rebase` take a whole branch; `checkout`, `restore`, `cherry-pick`, `cp` and
    `apply` take part of one. `default` is (branch, gitdir) for `root` when the caller already
    knows them. Detection only — nothing is written here."""
    if not CARRY_PRECHECK_RE.search(command):
        return {}
    ctx, found = CarryContext(root, *(default or ())), {}

    def note(context, kind, hits):
        # No branch filter here: a carry INTO main is detected too, so the gate can deny it.
        # Whether anything is recorded is the allow path's decision (main()).
        if not hits:
            return
        bucket = found.setdefault(context.gitdir, [])
        for sha, name in hits:
            if name not in context.own and (kind, sha, name) not in bucket:
                bucket.append((kind, sha, name))

    def refs_in(context, kind, args):
        for a in positionals(args) or []:
            for part in re.split(r"\.\.\.?", a):
                if part:
                    note(context, kind, context.resolve(part))

    session_ctx, stack, dirs = ctx, [], []
    for words, sink, applies in simple_commands(command):
        if not words:
            continue
        if words == ["("]:  # a subshell's cd ends at its `)`
            stack.append(ctx)
            continue
        if words == [")"]:
            ctx = stack.pop() if stack else ctx
            continue
        if words[0] in ("cd", "pushd"):
            if words[0] == "pushd":
                dirs.append(ctx)
            ctx = at(ctx, words[1] if len(words) > 1 else "", session_ctx)
            continue
        if words[0] == "popd":
            ctx = dirs.pop() if dirs else session_ctx
            continue
        if words[0] != "git":
            if words[0] in COPY_CMDS or sink:
                for t in words[1:]:
                    hit = ctx.worktree_hit(t)
                    if hit:
                        note(ctx, "cp", [hit])
            continue
        verb, args, cdirs = git_verb(words)
        here = ctx
        for d in cdirs:
            here = at(here, d, session_ctx)
        cdir = str(here.root) if cdirs else None
        if verb == "checkout":
            pos = positionals(args)
            if pos and len(pos) >= 2:  # `checkout <ref> [--] <path…>`; a lone arg is a switch
                note(here, "checkout", here.resolve(pos[0]))
        elif verb == "restore":
            for i, a in enumerate(args):
                if a.startswith("--source="):
                    note(here, "restore", here.resolve(a[len("--source="):]))
                elif a in ("--source", "-s") and i + 1 < len(args):
                    note(here, "restore", here.resolve(args[i + 1]))
        elif verb == "cherry-pick":
            refs_in(here, "cherry-pick", args)
        elif verb in ("merge", "pull"):
            refs_in(here, "rebase" if verb == "pull" and "--rebase" in args else "merge", args)
        elif verb == "rebase":
            refs_in(here, "rebase", args)
            if "--onto" in args and args.index("--onto") + 1 < len(args):
                note(here, "rebase", here.resolve(args[args.index("--onto") + 1]))
        elif verb in ("show", "diff", "format-patch", "log") and applies:
            refs_in(here, "apply", args)  # `git show <ref>:<p> | git apply`: a read that writes
        if cdir and (applies or sink):
            # `git -C ../other diff … | git apply` / `git -C ../other show HEAD:x > x`: the
            # content comes from the sibling worktree -C names, into this checkout
            hit = ctx.worktree_hit(cdir)
            if hit:
                note(ctx, "apply", [hit])
    return found


def record_carries(gitdir, records):
    """Append the (kind, commit, branch) records this worktree's file lacks; returns them."""
    if not records or VENDOR:
        return []
    path = Path(gitdir) / "claude" / CARRIES_NAME
    path.parent.mkdir(parents=True, exist_ok=True)
    have = [l.strip() for l in path.read_text().splitlines() if l.strip()] if path.exists() else []
    new = [f"{k} {s} {b}" for k, s, b in records if f"{k} {s} {b}" not in have]
    if new:
        path.write_text("".join(f"{l}\n" for l in have + new))
    return [tuple(l.split()) for l in new]


# ---- the lock -------------------------------------------------------------------------

read_owner = common.read_owner if common else None  # the lock's format lives in common.py, shared with bin/pickup


def claim(state, session, branch, withdraw=False):
    """Take or refresh the lock. A hand-over this session declared (`pickup next`, D7 of
    docs/subagent-cache-2026-10-04.md) survives its own writes and Stop commit — that turn's
    end commits after the tab opens, and dropping the mark there would lock the new tab out —
    and is withdrawn only by `withdraw`: a new prompt here means the owner came back to this one."""
    if VENDOR:
        return True  # another CLI's call takes no lock (VENDOR)
    old = read_owner(state)
    # Re-read, never trust the read at hook start: since a hand-over lets another session in,
    # it may have taken the lock while this hook committed — writing over it would lock that
    # tab out and hand this one back a checkout it gave away (review 2026-10-05).
    if held_by_other(old, session):
        return False
    keep = not withdraw and old and old.get("session") == session and old.get("handover")
    common.write_owner(state, session, branch, handover=old["handover"] if keep else None)
    return True


def held_by_other(owner, session):
    """A handed-over lock holds nobody out: the next session's first write takes it. Another CLI's
    call is held out by none (VENDOR)."""
    return not VENDOR and bool(owner and owner.get("session") != session and not owner.get("handover")
                and time.time() - owner.get("seen", 0) < OWNER_TTL)


def took_from(owner):
    """Whom a write took the lock from, for its 🔒 note."""
    sid = owner["session"][:8]
    return f"session {sid}, which handed it over" if owner.get("handover") else f"idle session {sid}"


def is_write(tool, tool_input, toplevel, branch, merging):
    """Edit/Write/NotebookEdit into this checkout. `branch`/`merging` only ever narrow the
    main-checkout gate — on every other branch they're inert. Bash is judged per simple
    by judge_bash(): the baseline against the session's checkout, or the one whitelisted shape."""
    if tool not in WRITE_TOOLS:
        return False
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    try:  # the scratchpad, auto-memory etc. live outside the checkout and stay writable
        Path(path).resolve().relative_to(toplevel)
    except ValueError:
        return False
    return not (branch == MAIN and merging)  # conflict-resolution edit mid-merge


# ---- Bash: the baseline judgement, plus ONE whitelisted shape (D4, narrowed 2026-09-25) ------
#
# The baseline — the hook's rule since 2026-09-15 — reads the raw command text: any `git <verb>`
# anywhere (FLOOR_RE), or the repo's live-write regex, is a write against the SESSION's checkout,
# denied on main (bar launching) and under another session's lock. Two rounds of per-target
# walking — judge each simple command by the checkout a `cd`/`-C` names — each left a way to
# hide a write from the walk (a subshell, a keyword, a wrapper, `$(…)`, a heredoc, GIT_DIR), so
# The owner narrowed D4 to ONE whitelisted shape (fifth review, 2026-09-25): the WHOLE command is
# `cd <X> && git <verb> <args>` (one or more such git steps, or one live-script step) or
# `git -C <X> <verb> <args>`, where X is a literal existing path — a claude/* worktree of an
# opted-in repo whose lock is free or ours, or an un-opted / no-workflow repo — and no part
# holds a separator, an expansion, a heredoc, a git-dir override, `-c`, or a second `git`.
# Only then is the write judged against X (its lock claimed, carries recorded there).
# Since D8 (same day) X may also be an opted-in checkout on its main, which makes the shape
# DENY what the baseline allowed from a worktree (`cd <primary> && git commit`); launching there
# stays allowed. Everything else is the baseline, exactly — never waived by a verb count or a walk.
MUTATING_VERBS = {"commit", "switch", "checkout", "reset", "merge", "rebase", "stash", "add", "rm",
                  "mv", "restore", "cherry-pick", "revert", "apply", "am", "pull"}
MERGE_RESOLVE_VERBS = {"add", "commit", "checkout", "reset", "restore", "rm"}
# The baseline's regex; `(?![\w-])` so `merge-tree` / `merge-base` are the reads they are while
# `git commit)`, `git add;`, `git add|`, a quote or a backtick after the verb still count (sixth
# review: `(?=\s|$)` had dropped those endings the baseline caught).
FLOOR_RE = re.compile(GIT_PREFIX + r"(commit|switch|checkout|reset|merge|rebase|stash|add|rm|mv"
                      r"|restore|cherry-pick|revert|apply|am|pull)(?![\w-])")
PULL_FF_RE = re.compile(GIT_PREFIX + r"pull\b[^;&|\n]*--ff-only")  # --ff-only on the pull's own args
STEP_END_RE = re.compile(r"[;&|\n]")  # where one git step's own arguments end, for PULL_FF_RE
# Nothing of this may appear in a whitelisted command's parts (split on `&&`): separators, an
# expansion, a heredoc, a git-dir override, `-c`. Anything so shaped is the baseline's.
FORBIDDEN_IN_SHAPE_RE = re.compile(r"[;|&\n`]|\$\(|<<|GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR|--git-dir|--work-tree|\s-c\s")
GIT_WORD_RE = re.compile(r"\bgit\b")
# Deleting a claude/* branch, or any worktree, is never an agent's act (the owner's D1, 2026-09-25):
# a branch proved launched is archived by sync.py at session start and pruned a week later
# (coding-on-workflow D4–D6, 2026-09-26), and a merged branch goes by itself — GitHub deletes the
# PR's head, sync.py archives the local copy. Only the push half was denied before; a /finish
# report or bin/pr output put a delete command in the model's context and prose was the only
# thing stopping it.
DELETE_FLAG_RE = re.compile(r"^-[a-zA-Z]*[dD][a-zA-Z]*$")  # -d, -D, -Dr, -fd …; never --long
UNREADABLE_NAME_RE = re.compile(r"[$`{}*?\[]")  # an expansion or a glob: whatever it names, unknown here
CLAUDE_ANY_RE = re.compile(r"^(?:refs/heads/|refs/remotes/)?(?:origin/)?claude/")
# The raw-text floor under deletion_in(), for what the tokenizer cannot read: a shell inside the
# shell (`bash -c`, `eval`, `$(…)`, a backtick, a heredoc). It acts only when such a marker is
# present, per span (never across `;`, `&`, `|` or a newline), after the arguments of `commit -m`
# / `-F` and grep patterns are blanked — so `grep -rn 'branch -D claude/' rules` and a commit
# message quoting the rule stay ordinary work (sixth review). A real delete flag or verb AND
# `claude/`, or a path that ENDS at the worktree machinery — worktree_part()'s shapes as text:
# the worktrees directory, a worktree, a worktree's `.git` — or climbs out of a worktree through
# `..`, which text cannot resolve. A file deeper inside a worktree is ordinary work (2026-09-28;
# the reason is at worktree_part). Unlike deletion_in(), the text cannot tell `mv`'s destination
# from its sources, so moving a file INTO a worktree is refused here: a false deny, never a miss.
SHELL_IN_SHELL_RE = re.compile(r"\b(?:bash|sh|zsh|dash|ksh)\s+-\w*c\b|\beval\b|\$\(|`|<<")
BLANK_ARGS_RE = re.compile(r"(?:\s(?:-m|-F|--grep|-e|--regexp)[=\s]+|\b(?:grep|rg|egrep|ag)\s+(?:-\S+\s+)*)"
                           r"(?:'[^']*'|\"[^\"]*\"|\S+)")
RAW_WORKTREE_END = (r"(?:\.claude/worktrees(?:/[^/\s'\"`;|&)]+(?:/\.git)?)?/?(?=[\s'\"`;|&)]|$)"
                    r"|\.claude/worktrees/[^\s'\"`;|&)]*/\.\.(?=[/\s'\"`;|&)]|$))")
RAW_DELETE_RE = re.compile(
    r"\bbranch\b[^\n;|&]*?\s(?:-[a-zA-Z]*[dD][a-zA-Z]*|--del\w*)\b[^\n;|&]*claude/"
    r"|\bupdate-ref\b[^\n;|&]*?(?:\s-d\b|--stdin)[^\n;|&]*claude/"
    r"|\bworktree\s+remove\b"
    rf"|\b(?:rm|mv)\b[^\n;|&]*{RAW_WORKTREE_END}"
    rf"|\bfind\b[^\n;|&]*{RAW_WORKTREE_END}[^\n;|&]*\s-delete\b")
DELETE_REASON = (
    "⛔ Deleting a claude/* branch or a worktree is never an agent's act (D1, 2026-09-25). A branch "
    "proved launched is archived by the session-start hook and pruned a week later; a probably-launched "
    "one is the owner's to review (`pickup review`); a merged branch goes by itself — GitHub deletes the "
    "PR's head on merge and sync.py archives the local copy at the next session start. The one exception is /finish leaving its worktree "
    "with the ExitWorktree tool, which removes the worktree and its branch. Don't retry or work "
    "around this; if the branch is in the way, say so in the report.")


def worktree_part(path):
    """What of the worktree machinery a normalized `path` is, or None: `.claude` itself, the
    `.claude/worktrees` directory, a worktree (`.claude/worktrees/<name>`, a glob for the name
    counting), or a worktree's `.git` file — removing it orphans the worktree as surely as
    removing the folder. Anything deeper, a file or a folder inside a worktree, is ordinary work.
    2026-09-28: `rm <…>/.claude/worktrees/tidy/scripts/archive.py`, a file the
    session had made in its own worktree, was denied as "rm of a worktree directory" — the test
    was `".claude/worktrees" in p`, true at any depth."""
    parts = path.split("/")
    if parts[-1] == ".claude":
        return ".claude"
    for i in range(len(parts) - 1):
        if parts[i] == ".claude" and parts[i + 1] == "worktrees":
            tail = parts[i + 2:]
            if not tail:
                return "the worktrees directory"
            if len(tail) == 1:
                return "a worktree"
            if tail[1:] == [".git"]:
                return "a worktree's .git file"
    return None


def deletion_in(command):
    """What the first claude/* branch or worktree deletion in `command` is, or None:
    `git branch -D/-d/--delete <claude/…>` (or a name the hook cannot read — `"$B"`, a brace or
    glob, none at all), `git branch -m claude/x <off claude/>`, `git update-ref -d` of one,
    `update-ref --stdin` fed a delete of one, `git worktree remove <any path>`, `rm`/`mv` of a
    worktree, the worktrees directory, `.claude` itself or a worktree's `.git`, `find … -delete`
    from one — through `cd X &&`, `git -C X`, loops, `xargs`, `timeout`, `bash -c`,
    `/usr/bin/git` alike (fourth and fifth reviews, 2026-09-25). A file inside a worktree is not
    one of them (2026-09-28)."""
    lowered = command.lower()
    here = "."  # the cwd as the command moves it: `cd .claude && rm -rf worktrees/b`
    for words, _, _ in simple_commands(command):
        if not words:
            continue
        name = os.path.basename(words[0])
        if name in ("cd", "pushd") and len(words) > 1:
            here = os.path.normpath(os.path.join(here, os.path.expanduser(words[1])))
            continue
        if name in ("rm", "mv", "find"):
            # The worktree machinery (worktree_part), never a file inside a worktree; a file
            # elsewhere under .claude — settings, an agent — is ordinary work too. `find` counts
            # only with -delete on such a path (sixth review). `mv`'s last word is where things
            # go, not what goes (2026-09-28): moving a file INTO a worktree is ordinary work,
            # overwriting a worktree's `.git` is not. `-t DIR` names the destination first, so
            # then every word is judged as a source — a false deny, never a miss.
            paths = [os.path.normpath(os.path.join(here, w)) for w in words[1:] if not w.startswith("-")]
            dest = None
            target_first = any(w.startswith("--t") or (w.startswith("-") and not w.startswith("--") and "t" in w)
                               for w in words[1:])
            if name == "mv" and len(paths) > 1 and not target_first:
                dest, paths = paths[-1], paths[:-1]
            what = next((k for k in map(worktree_part, paths) if k), None)
            if what is None and dest is not None and worktree_part(dest) == "a worktree's .git file":
                what = "a worktree's .git file"
            if what and (name != "find" or "-delete" in words):
                return f"{name} of {what}"
            continue
        if name != "git":
            continue
        verb, args, _ = git_verb(words)
        if verb == "branch":
            names = [a for a in args if not a.startswith("-")]
            unreadable = [a for a in names if UNREADABLE_NAME_RE.search(a)]
            if any(DELETE_FLAG_RE.match(a) or (len(a) >= 5 and "--delete".startswith(a)) for a in args):
                hits = [a for a in names if CLAUDE_ANY_RE.match(a)] + unreadable
                if hits or not names:  # no name at all: it comes on stdin (xargs) — unreadable here
                    return f"git branch -D {hits[0] if hits else '<a name this hook cannot read>'}"
            if any(a in ("-m", "-M", "--move") for a in args) and len(names) >= 2 \
                    and CLAUDE_ANY_RE.match(names[0]) and not CLAUDE_ANY_RE.match(names[1]):
                return f"git branch -m {names[0]} off claude/"
        elif verb == "update-ref":
            if "-d" in args:
                names = [a for a in args if not a.startswith("-")]
                hits = [a for a in names if CLAUDE_ANY_RE.match(a) or UNREADABLE_NAME_RE.search(a)]
                if hits or not names:
                    return f"git update-ref -d {hits[0] if hits else '<a ref this hook cannot read>'}"
            if "--stdin" in args and "delete" in lowered and "claude/" in lowered:
                return "git update-ref --stdin deleting a claude/ ref"
        elif verb == "worktree" and args and args[0] == "remove":
            return "git worktree remove"
    if SHELL_IN_SHELL_RE.search(command) and RAW_DELETE_RE.search(BLANK_ARGS_RE.sub(" ", command)):
        return "a deletion inside a shell the hook cannot read (bash -c, eval, $(…), a heredoc)"
    return None


class Target(CarryContext):
    """A checkout a command writes to, with what the gates need: its opt-in, its main, its
    lock, whether a merge is in progress. Lazy, like CarryContext."""

    def __init__(self, root, branch=None, gitdir=None, workflow=None):
        super().__init__(root, branch, gitdir)
        self._wf, self._common = workflow, None

    @property
    def common(self):
        """The primary checkout's top level, from inside any of its worktrees, or None."""
        if self._common is None:
            c = self.run("rev-parse", "--path-format=absolute", "--git-common-dir")
            self._common = Path(c).parent.resolve() if c.endswith("/.git") else False
        return self._common or None

    @property
    def workflow(self):
        if self._wf is None:
            self._wf = load_workflow_at(self.toplevel, self.common) or False
        return self._wf or None

    @property
    def main(self):
        return (self.workflow or {}).get("main") or "main"

    @property
    def live_re(self):
        rx = (self.workflow or {}).get("live_write_regex")
        return re.compile(rx) if rx else None

    @property
    def state(self):
        return self.gitdir / "claude"

    @property
    def owner(self):
        return read_owner(self.state)

    def locked_out(self, session):
        return held_by_other(self.owner, session)

    @property
    def moved(self):
        """The /move marker (common.MOVED_FILE): the branch went on elsewhere — no writes here."""
        return common.moved(self.state)

    @property
    def merging(self):
        return (self.gitdir / "MERGE_HEAD").exists()


def whitelisted(command, cwd):
    """(Target X, [(verb, the step's text)]) when the WHOLE command is one of the two D4
    shapes — `cd <X> && git <verb> <args> [&& git <verb> <args> …]` or `git -C <X> <verb>
    <args>` — with X a literal, existing path that is a claude/* worktree of an opted-in repo,
    an un-opted / no-workflow repo, or an opted-in checkout on its main. None for anything
    else: that is the baseline's.

    The last kind is the owner's D8 (2026-09-25), the shape's deny side: from a worktree, `cd
    <primary> && git commit` was judged by the session's own checkout and allowed. Judged by X,
    it is a write on X's main — denied, bar launching (a merge, `pull --ff-only`, resolving a
    merge in progress). `pushd`, `(cd …)` and `GIT_DIR=` stay the baseline's, as before."""
    parts = [p.strip() for p in command.strip().split("&&")]
    if any(not p or FORBIDDEN_IN_SHAPE_RE.search(p) for p in parts):
        return None
    steps = []
    if parts[0].startswith("cd "):
        try:
            cd_words = shlex.split(parts[0])
        except ValueError:
            return None
        if len(cd_words) != 2 or len(parts) < 2:
            return None
        xpath = cd_words[1]
        for p in parts[1:]:
            words = tokenize(p)
            if not words:
                return None
            if words[0] != "git" or len(GIT_WORD_RE.findall(p)) != 1:
                return None  # D4 is about git writes; a script keeps the baseline (sixth review)
            verb, args, cdirs = git_verb(words)
            if cdirs or verb is None:
                return None
            steps.append((verb, p))
    elif parts[0].startswith("git ") and len(parts) == 1:
        p = parts[0]
        if len(GIT_WORD_RE.findall(p)) != 1:
            return None
        verb, args, cdirs = git_verb(tokenize(p))
        if len(cdirs) != 1 or verb is None:
            return None
        xpath, steps = cdirs[0], [(verb, p)]
    else:
        return None
    if UNRESOLVABLE_RE.search(xpath):
        return None
    xdir = resolve_dir(cwd, xpath)
    if xdir is None:
        return None
    x = Target(xdir)
    if x.workflow is not None and not (x.branch.startswith("claude/") or x.branch == x.main
                                       or (not x.branch and detached_primary(x.toplevel))):
        return None  # an opted-in checkout on some other branch (detached, a person's own): the baseline's
    return x, steps


def decide(target, verb, session, step="", via=None):
    """("allow"|"deny", reason) for one write on `target`; `step` is that write's own text (a
    `git pull`'s arguments, up to the next separator). Not opted in (or marked no-workflow): no
    gate. On its main: only launching — a merge, a `pull --ff-only` (/finish brings the primary
    down after a GitHub merge), or resolving a merge in progress — each verb for itself (D7).
    Under another session's fresh lock: denied. `via` is the session's cwd when the target was
    reached through `cd`/`-C`, so the reason can say so."""
    if target.workflow is None:
        return "allow", None
    if target.branch == target.main:
        if verb == "merge" or (verb == "pull" and PULL_FF_RE.search(step)) \
                or (target.merging and verb in MERGE_RESOLVE_VERBS):
            return "allow", None
        return "deny", worktree_required_reason(target.toplevel, target.main, via)
    if not target.branch and detached_primary(target.toplevel):
        return "deny", pinned_reason(target.toplevel, target.main, via)
    went = target.moved
    if went:
        return "deny", common.moved_reason(went, target.branch)
    if target.locked_out(session):
        return "deny", lock_reason(target.owner, target.toplevel, target.main, target.state)
    return "allow", None


def deny(reason):
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                   "permissionDecisionReason": reason}}


# An interpreter fed inline code — `python3 - <<'EOF'`, `python3 -c`, `node -e`, `perl -pi -e`,
# `cat <<EOF | ruby` — can write any file, and decide() never sees it: strip_heredocs() drops the
# body and the line carries no write verb. On 2026-10-04 one such heredoc rewrote bin/memo-run in
# a worktree another session held, while the Edit after it was refused (lock-script-writes). So
# under another session's lock an inline program is denied without reading it: parsing what a
# script writes is a losing game. Elsewhere it changes nothing, and it never claims a lock — a
# session's `python3 -c 'print(1)'` in a free worktree makes it no writer. A program from a file
# (`python3 scripts/ha.py state x`, `node x.js --help`) or a module (`python3 -m py_compile x.py`,
# `python3 -m json.tool`) stays allowed: a named script is a tool the repo ships, run as a reader
# runs it — tests, `--help`, the read-only probes the lock section of the suite already allows —
# and its writes, if any, are no more the lock's business than a `cp` is (the lock judges git
# verbs and the live regex, not every program). Not covered, like the rest of this hook: code
# reached through a variable or backticks, `sed -i`, `cat > f <<EOF`, a shell fed a heredoc
# (`bash <<EOF`), `find -exec`, a script written first and run by name, bun and deno. Closing
# those means turning the lock into an allowlist of readers — a design question, not this fix.
INTERPRETER_RE = re.compile(r"^(?:python[\d.]*|node|nodejs|ruby[\d.]*|perl[\d.]*)$")
INLINE_STDIN = {"<<", "<<<"}  # a heredoc or here-string feeding the stage
RUNNERS = {"uv", "poetry", "pipx", "pdm", "rye", "hatch"}  # `uv run python -c …` runs python
INLINE_MODULES = {"code", "pdb", "timeit"}  # `python3 -m <it>` runs code it is fed, not a file
STDIN_SCRIPTS = {"-", "/dev/stdin", "/dev/fd/0"}
# long options whose value is the next word when no `=` is attached (review, 2026-10-04:
# `node --input-type module -e …` read `module` as the script)
LONG_WITH_ARG = {"node": {"--require", "--import", "--loader", "--experimental-loader",
                          "--input-type", "--env-file", "--conditions", "--title"},
                 "python": {"--check-hash-based-pycs"}}
# print and exit; so does perl's, ruby's and node's `-v` — python's is verbose and still runs stdin
INFO_OPTS = {"--version", "--help", "-V", "-h"}


def inline_program(words, fed):
    """True when `words` (one simple command, wrappers and redirects off) runs an interpreter
    on inline code: a code option, or its program read from stdin — `-` or /dev/stdin as the
    script, or no script at all while a heredoc, here-string or earlier pipeline stage feeds
    it (`fed`)."""
    if len(words) > 1 and os.path.basename(words[0]) in RUNNERS and words[1] == "run":
        words = words[2:]
        while words and words[0].startswith("-"):
            words = words[1:]
    if not words:
        return False
    prog = os.path.basename(words[0])
    if not INTERPRETER_RE.match(prog):
        return False
    kind = re.match(r"[a-z]+", prog).group(0)
    # per language: option letters that are code; letters whose argument is the rest of the
    # word, so scanning stops (`-i.bak`, `-Mstrict`); and of those, the ones whose argument is the
    # next word when nothing is attached (`-W error`, `-r json`, `-I lib`). `-l`/`-0` take digits
    # only, so `-lne` reads on to its `e`; perl's `-i` never takes the next word: `-pi -e` is code.
    code, stop, next_word = {"python": ("c", "mWX", "mWX"), "perl": ("eE", "IMmxiCdDF", "I"),
                             "ruby": ("e", "IrCxKEFiW", "rICE")}.get(kind, ("ep", "rC", "rC"))
    i = 1
    while i < len(words):
        w = words[i]
        if w in STDIN_SCRIPTS:
            return True  # the program is stdin
        if w == "--":
            return i + 1 < len(words) and words[i + 1] in STDIN_SCRIPTS
        if not w.startswith("-"):
            return False  # a script file: a named program
        if w.startswith("--"):
            name = w.split("=")[0]
            if kind == "node" and name in ("--eval", "--print"):
                return True
            if "=" not in w and name in LONG_WITH_ARG.get(kind, ()):
                i += 1
            i += 1
            continue
        for k, ch in enumerate(w[1:], 1):
            if ch in code:
                return True
            if ch in stop:
                if kind == "python" and ch == "m":
                    module = w[k + 1:] or (words[i + 1] if i + 1 < len(words) else "")
                    return module in INLINE_MODULES  # else `-m <module>`: a named program
                if ch in next_word and k == len(w) - 1:
                    i += 1  # its argument is the next word
                break
        i += 1
    info = INFO_OPTS | ({"-v"} if kind != "python" else set())
    return fed and not any(w in info for w in words[1:])


def runs_inline_program(command):
    """The first simple command in `command` that feeds an interpreter inline code, or None.
    Its own small walk, not simple_commands: that drops redirects and pipeline position, which
    are exactly what tells `python3 - <<EOF` from `python3 -`… and `cat x | python3` from
    `python3`. A `bash -c` / `sh -c` / `eval` payload is walked as its own command."""
    text = strip_heredocs(command).replace("\\\n", " ")  # a continued line is one line
    for line in text.split("\n"):
        units, current = [], []
        for t in tokenize(line):
            if t in OPERATORS:
                units.append(current)
                current = []
            else:
                current.append(t)
        units.append(current)
        for unit in units:
            stages, stage = [], []
            for t in unit:
                if t in ("|", "|&"):
                    stages.append(stage)
                    stage = []
                else:
                    stage.append(t)
            stages.append(stage)
            for n, stage in enumerate(stages):
                words, fed, i = [], n > 0, 0
                while i < len(stage):
                    if stage[i] in REDIRECTS:
                        fed |= stage[i] in INLINE_STDIN
                        i += 2
                        continue
                    if stage[i].isdigit() and i + 1 < len(stage) and stage[i + 1] in REDIRECTS:
                        i += 1  # the fd of `2>&1` / `2>/dev/null`, which tokenize splits off
                        continue
                    words.append(stage[i])
                    i += 1
                words = strip_wrappers(words)
                payload = None
                if words and os.path.basename(words[0]) in SHELLS:
                    k = next((k for k, w in enumerate(words[1:], 1) if w.startswith("-") and "c" in w[1:]), None)
                    if k is not None and k + 1 < len(words):
                        payload = words[k + 1]
                elif words and words[0] == "eval":
                    payload = " ".join(words[1:])
                if payload is not None:
                    hit = runs_inline_program(payload)
                    if hit:
                        return hit
                    continue
                if inline_program(words, fed):
                    return " ".join(words)
    return None


def cd_dirs(command, cwd):
    """Every folder a literal `cd`/`pushd` in `command` moves into, resolved in order from
    `cwd` — the checkouts inline code may run in besides the session's own (review, 2026-10-04:
    `cd <another session's worktree> && python3 - <<EOF` was judged by the session's cwd)."""
    here, dirs = cwd, []
    for words, _, _ in simple_commands(command):
        if words and words[0] in ("cd", "pushd"):
            d = resolve_dir(here, next((w for w in words[1:] if not w.startswith("-")), None))
            if d is not None:
                here = str(d)
                dirs.append(d)
    return dirs


def handle_bash(command, cwd, session):
    """The whole PreToolUse decision for a Bash command. Wrapped: a failure anywhere (a git
    timeout, a symlink loop) falls back to the raw text — a deletion or a write is DENIED with
    the reason, a read is allowed with a note — never to an allow by accident."""
    try:
        return judge_bash(command, cwd, session)
    except Exception as exc:
        return fallback_bash(command, cwd, session, exc)


# An unattended run (bin/dispatch sets this in the `claude -p` environment, which its hooks
# inherit) is read-only on live systems: research, design, code and tests may run in a repo that
# owns a house or a server, deploys and physical checks may not — nobody is there to say yes
# (The owner, 2026-10-03: "we should be able to schedule non-HA work on the home repo any time"). The deny
# is judged per simple command (simple_commands), never on the raw text, so `git add
# scripts/deploy.py` or `grep -- --live-ok` stays allowed — first review, 2026-10-04: the raw text
# denied a seeded run its own commit. A command whose program only reads or is git (READERS) is
# skipped; any other is denied when it carries a consent flag (which an unattended run by
# definition cannot have been given, in any folder) or matches the live_write_regex or
# unattended_deny_regex of the repo it runs in. "Runs in" is the cwd after any `cd`/`pushd`, and
# the repo of every word that names an existing file, matched by its path from that repo's top
# level as well as as typed — the scripts anchor on their own path, so `/abs/home/scripts/
# deploy.py` from household, `../home/scripts/deploy.py` and `cd scripts && python3 deploy.py`
# all deploy the home repo (second review, 2026-10-04). Both regexes come from the PRIMARY checkout's
# workflow.json, never the worktree's: the run edits its worktree and could switch its own guard
# off. An unreadable regex denies — failing open here is the one failure nobody would see. Not
# covered: a script reached through a variable, `env -C`, or an interpreter's own string (`awk
# 'BEGIN{system(…)}'`) — habits no agent falls into by accident.
# The unattended marker, under both its names (vendor-fence's stage 1, the core's UNATTENDED_NAMES): either
# set is an unattended run, and the shed guard below denies dropping either
UNATTENDED_NAMES = tuple(getattr(common, "UNATTENDED_NAMES", None) or ("REGATTA_UNATTENDED", "CLAUDE_UNATTENDED"))
_MARK = "(?:" + "|".join(UNATTENDED_NAMES) + ")"


def unattended_mark():
    """`NAME=value` of the marker that is set, or None (the core's unattended_label; read here without it)."""
    return next((f"{n}={os.environ[n]}" for n in UNATTENDED_NAMES if os.environ.get(n)), None)


CONSENT_FLAG_RE = re.compile(r"--(?:live|estate)-ok\b")
# A run that sheds what marks it unattended: the raise refusals (helmlib.raise_refusal, dispatch's
# --mode check) and every merge gate read the marker and DISPATCH_LABEL from the environment,
# so `env -u`, `unset`, an emptied value, `env -i` or a typed DISPATCH_LABEL would be the run writing
# itself the yes (skipper-modes landing review 20). Read from the raw text with quoted strings cut —
# simple_commands drops `env` and assignments, and a mention in a commit message is no act. The shell's
# own setters count as assignments (`export`, `declare -x`, `typeset`, `local`, `readonly`), and an
# un-export (`export -n`, `declare +x`) sheds as `unset` does (follow-ups item 2). A shed inside a quoted
# string (`bash -c 'unset …'`, `sh -c "env -u …"`) passes: writing a second shell to hide the act is
# intent, not accident, and this hook guards accidents (its header).
_SETTER = r"\b(?:export|declare|typeset|local|readonly)\b(?:\s+-\w+)*\s+(?:[A-Za-z_]\w*\s+)*"
_ASSIGN_AT = (r"(?:(?:^|[;&|(\n]|\benv\b[^\n|;&]*?\s)\s*|" + _SETTER + r")"
              r"(?:[A-Za-z_]\w*=\S*\s+)*")   # where an assignment sets a variable
_UNEXPORT = r"\b(?:export\s+(?:-\w+\s+)*-\w*n|(?:declare|typeset)\s+(?:[-+]\w+\s+)*\+\w*x)\w*\b[^\n|;&]*\b"
UNATTENDED_SHED_RE = re.compile(
    r"\benv\b[^\n|;&]*?\s(?:-u\s*|--unset[= ])" + _MARK + r"\b|\benv\s+(?:-\w*i\b|--ignore-environment\b)"
    r"|\bunset\b[^\n|;&]*\b" + _MARK + r"\b|" + _UNEXPORT + _MARK + r"\b"
    r"|" + _ASSIGN_AT + r"(?:" + _MARK + r"=(?=[\s;&|)]|$)|DISPATCH_LABEL=)")
QUOTED_RE = re.compile(r"'[^']*'|\"(?:[^\"\\]|\\.)*\"")
# The skipper's records (follow-ups item 7, the landing review's finding 20): helm's plans root —
# plan.json, branch-modes.json, events.jsonl — and dispatch's run records. A mode, a raise refusal and a
# run's task_mode are read there, so an unattended run editing one by hand writes itself the yes. Only
# the tools that own them (bin/helm, bin/plan, bin/dispatch) write them, as processes this hook never
# sees; a hand edit is denied — the Write/Edit tools, and a Bash command that names one and is no
# reader (a redirect into it, inline code, any program but READERS, `sed -i`, a `find` that runs).
RECORD_DIRS = ("Library/Logs/claude-weekly/plans", "Library/Logs/claude-weekly/run-seed-runs")
# the lander's launch record in a repo's git dir: its `by` and `eff_mode` are the yes bin/pr's
# re-check trusts, so a run writing it writes itself the yes (the follow-ups' landing review)
AF_STATE = "/claude/autofinish.json"
# the owner's yes itself (the autofinish-exclude landing review, finding 11): /autofinish's marker in a
# worktree's git dir and the yes at the brief in the common one; a run writing either gives itself rule C
AF_YES = ("/claude/autofinish", "/claude/autofinish-briefs")


def record_roots():
    """The record folders as typed paths: under $HOME, and helm's PLANS_DIR where it is set."""
    home = os.environ.get("HOME") or str(Path.home())
    return [os.path.join(home, d) for d in RECORD_DIRS] + [r for r in (os.environ.get("PLANS_DIR"),) if r]


def in_records(path):
    """True when `path` (a Write/Edit target) is under a record folder, links resolved."""
    if not path:
        return False
    p = os.path.realpath(os.path.expanduser(path))
    if p.endswith(AF_STATE) or p.endswith(AF_YES) or AF_YES[1] + "/" in p:
        return True
    return any(p == r or p.startswith(r.rstrip("/") + "/") for r in map(os.path.realpath, record_roots()))


def records_re():
    """A record folder as a command may spell it: absolute, or under `~`, `$HOME` or `${HOME}`."""
    home = os.environ.get("HOME") or str(Path.home())
    alts = [h + "/" + re.escape(d) for d in RECORD_DIRS for h in (re.escape(home), "~", r"\$HOME", r"\$\{HOME\}")]
    alts += [re.escape(r) for r in record_roots()[len(RECORD_DIRS):]]
    alts.append(r"[^\s\"'<>|;&]*" + re.escape(AF_STATE))   # a plain path to it; a $( … ) spelling is intent
    alts.append(r"[^\s\"'<>|;&]*" + re.escape(AF_YES[0]))   # the marker (the lookahead below spares .json)
    alts.append(r"[^\s\"'<>|;&]*" + re.escape(AF_YES[1]) + r"(?:/[^\s\"'<>|;&]*)?")
    return re.compile("(?:" + "|".join(alts) + r")(?![\w.-])")


# The force mark (dispatch-queue S4, D3-A): wharf-runs' force_mark.py writes force/<session> in run-seed's
# cache folder when the owner's typed message says "use the force", and dispatch spends it for one force run.
# Unlike the records above, an attended session is the one that reads it, so a write there is denied to every
# session, attended or not: a session that wrote one would be writing itself the owner's words.
FORCE_DIR = "Library/Caches/run-seed/force"
# the queue's own folders too: an outbox op or a node-local entry written by hand is a put dispatch never judged,
# force or a mode included, which a fired job then runs (S4's second review); and force_mark.py run by hand,
# which writes the mark from whatever prompt it is fed
QUEUE_DIRS = ("Library/Caches/run-seed/queue", "Library/Caches/run-seed/queue-local")


def force_root():
    return os.path.join(os.environ.get("HOME") or str(Path.home()), FORCE_DIR)


def in_force(path):
    """True when `path` (a Write/Edit target) is under the force mark's folder, links resolved."""
    if not path:
        return False
    p = os.path.realpath(os.path.expanduser(path))
    home = os.environ.get("HOME") or str(Path.home())
    for r in [force_root()] + [os.path.join(home, d) for d in QUEUE_DIRS]:
        r = os.path.realpath(r)
        if p == r or p.startswith(r.rstrip("/") + "/"):
            return True
    return False


def force_re():
    home = os.environ.get("HOME") or str(Path.home())
    alts = [h + "/" + re.escape(d) for d in (FORCE_DIR,) + QUEUE_DIRS for h in (re.escape(home), "~", r"\$HOME", r"\$\{HOME\}")]
    alts.append(r"[^\s\"'<>|;&]*force_mark\.py")
    return re.compile("(?:" + "|".join(alts) + r")(?:/[^\s\"'<>|;&]*)?(?![\w.-])")


# a script named in a gh command's text (an issue's title or body) is prose: gh runs no local script, so only a
# folder it names still counts (regatta-logbook#2, queue S10)
SCRIPT_NAME_RE = re.compile(r"[^\s\"'<>|;&]*force_mark\.py")
# …only an issue's or a pull request's text, and never beside a flag that writes a local file: `gh alias set` makes
# a shell alias that runs it, and `gh release download -O` overwrites it (the S10 landing review)
GH_PROSE = {"issue", "pr"}
GH_WRITES = {"-O", "--output", "-D", "--dir", "--clobber"}
# ssh's options that take an argument (OpenSSH's usage line): the first word after them is the host, and the
# rest is a command line the remote shell runs, judged as one of its own (regatta-logbook#2)
SSH_OPT_WITH_ARG = set("BbcDEeFIiJLlmOoPpQRSWw")
# a substitution anywhere in a narrowed command's words — `$(…)`, backticks, `<(…)`, `>(…)` — runs a command the
# tokenizer never splits out, locally or on the peer, so neither the ssh nor the gh road calls such a text a read
# (S10's finish review: main denies them all)
SUBST_RE = re.compile(r"`|[$<>]\(")


def ssh_split(words):
    """(the local words: ssh, its options and HOST; the command lines HOST may run) of an `ssh …` command.
    ssh joins its trailing words with spaces and the remote shell parses them again, so `ssh h 'cat x'` runs
    `cat x`; the words as quoted here are judged too, so `ssh h bash -c 'python3 x'` keeps its payload."""
    i = 1
    while i < len(words) and words[i].startswith("-") and words[i] != "--":
        opt = words[i]
        i += 2 if len(opt) == 2 and opt[1] in SSH_OPT_WITH_ARG else 1
    if i < len(words) and words[i] == "--":
        i += 1
    rest = words[i + 1:]
    lines = [" ".join(rest)] if rest else []
    if len(rest) > 1:
        lines.append(shlex.join(rest))
    return words[:i + 1], lines


def force_reason(what):
    return (f"⛔ `{what}` writes the force mark by hand ({FORCE_DIR} under HOME): it stands for the owner saying \"use the "
            f"force\", so only wharf-runs' force_mark hook writes it, from the owner's typed message, and only dispatch "
            f"spends it. Reading it is fine; to dispatch with force, ask the owner to say it.")


def record_write(command, rx=None):
    """The part of `command` that writes a skipper's record by hand (item 7), or under RX's folders, or None."""
    rx = rx or records_re()
    if not rx.search(command):
        return None
    m = re.search(r"(?:&?>>?|>\|)\s*[\"']?(?:" + rx.pattern + ")", command)
    if m:
        return m.group(0)
    try:
        inline = runs_inline_program(command)
    except Exception:
        inline = "inline code"
    if inline:
        return rx.search(command).group(0)
    for words, _, _ in simple_commands(command):
        text = " ".join(words)
        if not words or not rx.search(text):
            continue
        prog = os.path.basename(words[0])
        if prog in READERS and not (prog == "find" and (FIND_RUNS | {"-delete"}) & set(words)) \
                and not (prog == "sed" and any(w.startswith(("-i", "--in-place")) for w in words[1:])):
            continue
        if prog == "ssh":
            local, remote = ssh_split(words)
            if not SUBST_RE.search(text) and not rx.search(" ".join(local)) \
                    and not any(record_write(r, rx) for r in remote):
                continue
            return text[:80]
        # a quoted substitution stays one word to the tokenizer, so a run inside it is never its own simple command:
        # such a text is no prose (SUBST_RE). A write flag by prefix: `--output=F`, `-OF`
        if prog == "gh" and len(words) > 1 and words[1] in GH_PROSE and not SUBST_RE.search(text) \
                and not any(w.split("=", 1)[0] in GH_WRITES or w.startswith(("-O", "-D")) for w in words[2:]) \
                and not rx.search(SCRIPT_NAME_RE.sub("", text)):
            continue
        return text[:80]
    return None


def record_reason(what):
    return (f"⛔ Unattended run ({unattended_mark()}): `{what}` writes a skipper's "
            f"record by hand (helm's plans — plan.json, branch-modes.json — a dispatch run record, or the "
            f"lander's: its run record, /autofinish's marker, the yes at the brief). A mode, a raise refusal, a "
            f"run's task_mode and the owner's yes are read there, so only their tools (bin/helm, bin/plan, "
            f"bin/dispatch, autofinish) write them. Reading them (cat, jq, grep) is fine; leave the change for the owner.")


def detached_primary(toplevel):
    """True when `toplevel` is a repo's primary checkout on a detached HEAD — lighthouse's hookwatch pins
    it there (autofinish-exclude S4). It is denied writes as main is (the landing review, finding 6):
    a write there is checkpointed nowhere, and its dirt makes the unpin and sync.py refuse."""
    r = git("-C", str(toplevel), "rev-parse", "--path-format=absolute", "--git-common-dir", check=False)
    c = r.stdout.strip() if r.returncode == 0 else ""
    if not c.endswith("/.git") or Path(c).parent.resolve() != Path(str(toplevel)).resolve():
        return False
    return git("-C", str(toplevel), "symbolic-ref", "--quiet", "HEAD", check=False).returncode != 0


def pinned_reason(toplevel, main=None, via=None, workflow=None):
    return (f"⛔ {toplevel} is the primary checkout on a detached HEAD — lighthouse's hookwatch pins it at the "
            f"last clean sha after a hook fault (or a person detached it), and it takes no writes, as {main or MAIN} "
            f"takes none: nothing here is checkpointed, and dirt here stops `hookwatch unpin` and sync.py. "
            f"`hookwatch unpin` puts it back on {main or MAIN} once the fix is in.\n"
            + worktree_required_reason(toplevel, main, via, workflow))


READERS = {"git", "grep", "rg", "egrep", "ag", "cat", "head", "tail", "less", "sed", "awk", "ls",
           "wc", "diff", "echo", "printf", "find", "jq", "stat", "file", "test", "[", "true", "nl"}
FIND_RUNS = {"-exec", "-execdir", "-ok", "-okdir"}  # a find that runs something is no reader
CHECKERS = {"py_compile", "compileall", "pyflakes", "ruff", "mypy"}  # `python3 -m <it>` only reads


def unattended_live(command, cwd):
    """The reason an unattended run may not run this command, or None."""
    if not unattended_mark():
        return None
    shed = UNATTENDED_SHED_RE.search(QUOTED_RE.sub(lambda m: "" if m.group(0) in ("''", '""') else "Q", command))
    if shed:
        return (f"⛔ Unattended run ({unattended_mark()}): `{shed.group(0).strip()}` "
                f"sheds what marks this run unattended — the mode's raise refusal and the merge gates read it, "
                f"so only the owner may run that. Leave it as an open item for the owner in your report.")
    record = record_write(command)
    if record:
        return record_reason(record)
    here, repos, regexes = Path(cwd), {}, {}

    def repo(d):
        """(primary checkout, top level) of the repo holding folder d, cached per folder."""
        if d not in repos:
            t = Target(d)
            repos[d] = (t.common, t.toplevel) if t.common else (None, None)
        return repos[d]

    def patterns(common):
        if common not in regexes:
            wf = load_workflow_at(common, None) if common else None
            regexes[common] = [(k, wf[k]) for k in ("live_write_regex", "unattended_deny_regex")
                               if wf and wf.get(k)]
        return regexes[common]

    for words, _, _ in simple_commands(command):
        if not words:
            continue
        prog = os.path.basename(words[0])
        if prog in ("cd", "pushd"):
            arg = next((w for w in words[1:] if not w.startswith("-")), None)
            if arg and not UNRESOLVABLE_RE.search(arg):
                here = Path(os.path.normpath(here / os.path.expanduser(arg)))
            continue
        if prog in READERS and not (prog == "find" and FIND_RUNS & set(words)):
            continue
        if prog.startswith("python") and len(words) > 2 and words[1] == "-m" and words[2] in CHECKERS:
            continue
        text = " ".join(words)
        hit = CONSENT_FLAG_RE.search(text)
        # nearest_dir takes a file and returns the folder it is in: the cwd as a file in itself
        dirs, rel = [nearest_dir(here / "_")], list(words)
        for i, w in enumerate(words):
            if hit or w.startswith("-") or UNRESOLVABLE_RE.search(w):
                continue
            f = Path(os.path.realpath(here / os.path.expanduser(w)))
            if not f.is_file():
                if "/" in w:  # not there (yet): its repo still judges the path as typed
                    dirs.append(nearest_dir(f))
                continue
            top = repo(f.parent)[1]
            if top:
                rel[i] = os.path.relpath(f, top)
                dirs.append(f.parent)
        texts = [text, " ".join(rel)]
        for d in dirs:
            if hit or d is None:
                continue
            for key, rx in patterns(repo(d)[0]):
                try:
                    hit = next((m for m in (re.search(rx, t) for t in texts) if m), None)
                except re.error:
                    return (f"⛔ Unattended run: {key} in {d}'s workflow.json does not compile, so "
                            f"nothing there can be judged — `{text}` is denied. Leave it for the owner.")
                if hit:
                    break
        if hit:
            return (f"⛔ Unattended run ({unattended_mark()}): read-only on "
                    f"live systems — `{hit.group(0)}` acts on one. Nobody is here to say yes. Leave "
                    f"it as an open item for the owner in your report; reads and --check-only are fine.")
    return None


LIVEISH_RE = re.compile(r"\.py\b|\.sh\b|deploy|apply")  # what a live write looks like, when no regex can be read


def fallback_bash(command, cwd, session, exc):
    why = f"{type(exc).__name__}: {str(exc)[:120]}"
    if RAW_DELETE_RE.search(command) or "worktree remove" in command:
        return deny(f"{DELETE_REASON}\n(judged from the raw text: {why})")
    # unattended: a consent flag is denied here too — the raw text, since nothing parsed
    try:
        inline = runs_inline_program(command)  # inline code writes as well as a git verb does
    except Exception:
        inline = None
    if FLOOR_RE.search(command) or LIVEISH_RE.search(command) or inline or (
            unattended_mark() and CONSENT_FLAG_RE.search(command)):
        return deny(f"⛔ The checkpoint hook could not judge this write ({why}). Run it from the "
                    f"checkout it writes to, without cd or -C, and say so in the report.")
    return {"systemMessage": f"⚠ checkpoint hook could not resolve this command's checkout ({why}); "
                             f"it reads as a read and was allowed"}


def judge_bash(command, cwd, session):
    """D1 first, everywhere. Then either the one whitelisted D4 shape, judged against X, or the
    baseline: the raw text's `git <verb>`s and the session repo's live-write regex, judged
    against the session's checkout. Locks are claimed and carries recorded where the write was
    allowed. Returns the JSON to print, or None."""
    deleting = deletion_in(command)
    if deleting:
        return deny(f"{DELETE_REASON}\n(this command: {deleting})")
    forced = record_write(command, force_re())
    if forced:
        return deny(force_reason(forced))
    unattended = unattended_live(command, cwd)
    if unattended:
        return deny(unattended)
    notes, writes = [], []
    session_target = Target(cwd)
    shape = whitelisted(command, cwd)
    target = shape[0] if shape else session_target
    if shape:
        writes = [(verb, step) for verb, step in shape[1] if verb in MUTATING_VERBS]
    else:
        # Every `git <verb>` in the raw text, each with its own arguments. The launching exception
        # is decide()'s, per verb (D7): before, one `git merge` anywhere let the whole command
        # through on main.
        writes = [(m.group(1), STEP_END_RE.split(command[m.start():], 1)[0])
                  for m in FLOOR_RE.finditer(command)]
    # A live-script write keeps the baseline whatever the shape: the session repo's regex, judged
    # against the session's checkout — `cd <unopted> && python3 /abs/home/scripts/deploy.py`
    # deploys the home repo, since deploy.py anchors on its own path (sixth review).
    live = session_target.live_re is not None and session_target.live_re.search(command)
    if live and not shape:
        writes.append(("live", command))
    # A carry is a write too — recorded where it was allowed. In the baseline only the session's
    # checkout can receive one. On main, per record like the writes (D7): a `merge` record is the
    # launching itself and a `checkout`/`restore` resolves the merge in progress; anything else
    # carried into main (a cp, a cherry-pick, an applied diff, a rebase) is a write there.
    carries = carry_sources(command, cwd)  # lazy: no git call unless a carry shape is present
    mine = {}
    if carries:
        own = str(target.gitdir.resolve())
        mine = {g: r for g, r in carries.items() if str(Path(g).resolve()) == own}
        on_main = target.workflow and target.branch == target.main
        if any(not (on_main and (kind == "merge" or (target.merging and kind in MERGE_RESOLVE_VERBS)))
               for recs in mine.values() for kind, _, _ in recs):
            writes.append(("carry", command))
    if live and shape:  # the shape's git steps go to X; the script is the session's business
        verdict, reason = decide(session_target, "live", session, command)
        if verdict == "deny":
            return deny(reason)
    # Inline code under another session's lock, or in a worktree whose branch moved away: denied,
    # never claimed (the comment above INTERPRETER_RE). Judged in the session's checkout and every
    # one a `cd` enters. On main, or with the lock free or ours, it is as before. The parse is
    # pure text, so a command with no interpreter costs no git call.
    inline = runs_inline_program(command)
    if inline:
        tops = {str(target.toplevel)}
        for t in [target] + [Target(d) for d in cd_dirs(command, cwd)]:
            if t.workflow is None or t.branch == t.main or (t is not target and str(t.toplevel) in tops):
                continue
            tops.add(str(t.toplevel))
            went = t.moved
            if went:
                return deny(common.moved_reason(went, t.branch))
            if t.locked_out(session):
                return deny(lock_reason(t.owner, t.toplevel, t.main, t.state)
                            + f"\n(this command runs inline code, which can write anything: `{inline[:80]}`)")
    if not writes:
        return None
    via = cwd if shape and target.toplevel != session_target.toplevel else None
    for verb, step in writes:
        verdict, reason = decide(target, verb, session, step, via)
        if verdict == "deny":
            return deny(reason)
    if target.workflow is None or target.branch == target.main:
        return None  # no gate there, or a launch on main: the primary checkout takes no lock
    owner = target.owner
    target.state.mkdir(parents=True, exist_ok=True)  # a sibling worktree may have no claude/ yet
    target._branch, note = adopt_spawned(target.toplevel, target.branch, target.main, quiet=True)
    if note:
        notes.append(note)
    claim(target.state, session, target.branch)
    if owner and owner.get("session") != session:
        notes.append(f"🔒 took over {target.toplevel} from {took_from(owner)}")
    if shape:
        remember_claim(session_target, target, session)
    for gitdir, recs in mine.items():
        added = record_carries(gitdir, recs)
        if added:
            notes.append("↩ carries " + ", ".join(f"{b} ({k})" for k, _, b in added) + " — recorded for /finish")
    return {"systemMessage": " · ".join(notes)} if notes else None


def remember_claim(session_target, target, session):
    """A lock taken in ANOTHER checkout is remembered per session, so SessionEnd frees it with
    the session's own instead of leaving it to OWNER_TTL. Nothing to remember from a plain
    folder (no git dir of its own) or for the session's own checkout."""
    if VENDOR or not session_target.gitdir.exists() or target.gitdir.resolve() == session_target.gitdir.resolve():
        return   # another CLI's call takes no lock, so it has none to remember (VENDOR)
    path = session_target.state / f"claimed-{session}"
    path.parent.mkdir(parents=True, exist_ok=True)
    have = path.read_text().splitlines() if path.exists() else []
    key = str(target.gitdir.resolve())
    if key not in have:
        path.write_text("".join(f"{k}\n" for k in have + [key]))


# ---- Edit / Write / NotebookEdit: judged by the FILE's checkout (D2, coding-on-workflow) ----
#
# Until 2026-09-26 a write tool was judged against the session's own checkout, and any path
# outside it was allowed unconditionally: a home-repo session could edit household's primary on
# main, or the layer's, with no gate and no lock (is_write's relative_to test). Now the file's
# checkout decides — the same rule the Bash shape applies to `cd <X> && git …`: its main takes
# no write (bar resolving a merge in progress), a claude/* worktree takes its lock, a repo that
# never opted in (or is marked no-workflow) has no gate. The session's own checkout keeps the
# old path unchanged: SAME_CHECKOUT hands it back to main().
SAME_CHECKOUT = object()


def nearest_dir(path):
    """The existing directory a file would be written into — Write creates missing folders, so
    walk up to the first one that exists. None for a relative or unreadable path."""
    try:
        p = Path(os.path.expanduser(path))
        if not p.is_absolute():
            return None
        d = p.parent
        while not d.is_dir():
            if d.parent == d:
                return None
            d = d.parent
        return d.resolve()
    except (OSError, RuntimeError):
        return None


def in_place_entries(workflow):
    """The workflow's `in_place` entries, normalized ("memory/" → "memory"); [] when absent."""
    entries = (workflow or {}).get("in_place")
    if not isinstance(entries, list):
        return []
    return [e.strip("/") for e in entries
            if isinstance(e, str) and e.strip("/") and e.strip("/") not in (".", "..")]


def in_place_rel(workflow, rel):
    """Whether a path relative to the repo's top level is one of its in-place records."""
    return any(rel == e or rel.startswith(e + "/") for e in in_place_entries(workflow))


def in_place(workflow, toplevel, path):
    """Whether `path` (absolute, symlinks allowed — auto-memory reaches the vault through a
    link in ~/.claude/projects) is an in-place record of the checkout at `toplevel`."""
    if not in_place_entries(workflow) or not path:
        return False
    try:
        rel = Path(os.path.expanduser(path)).resolve().relative_to(Path(toplevel).resolve())
    except (ValueError, OSError, RuntimeError):
        return False
    return in_place_rel(workflow, rel.as_posix())


def gated_dirt(workflow):
    """Dirty paths of the session's checkout that are not in-place records."""
    out = git("status", "--porcelain", "-z", check=False).stdout
    items, paths, skip = out.split("\0"), [], False
    for item in items:
        if skip:
            skip = False
            continue
        if len(item) < 4:
            continue
        skip = item[0] in "RC" or item[1] in "RC"  # the rename's source follows as its own field
        paths.append(item[3:])
    return [p for p in paths if not in_place_rel(workflow, p.rstrip("/"))]


def handle_file_write(tool_input, cwd, session):
    """None (allow), a deny, or SAME_CHECKOUT when the file is in the session's own checkout."""
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    d = nearest_dir(path)
    if d is None:
        return SAME_CHECKOUT
    target = Target(d)
    if not target.run("rev-parse", "--show-toplevel"):
        return None  # not in a repo: the scratchpad, a download, nothing to gate
    session_target = Target(cwd)
    if session_target.run("rev-parse", "--show-toplevel") and target.toplevel == session_target.toplevel:
        return SAME_CHECKOUT
    if target.workflow is None:
        return None
    if target.branch == target.main:
        if target.merging:
            return None  # resolving a merge in progress, as on one's own main
        if in_place(target.workflow, target.toplevel, path):
            return None  # a record written in place (auto-memory, the bulletin): no lock, no checkpoint
        return deny(worktree_required_reason(target.toplevel, target.main, via=cwd, workflow=target.workflow))
    # a pinned (detached) primary, written from another checkout: denied as main is (finding 6's re-review)
    if not target.branch and detached_primary(target.toplevel):
        return deny(pinned_reason(target.toplevel, target.main, via=cwd, workflow=target.workflow))
    went = target.moved
    if went:
        return deny(common.moved_reason(went, target.branch))
    if target.locked_out(session):
        return deny(lock_reason(target.owner, target.toplevel, target.main, target.state))
    if not target.branch.startswith("claude/"):
        return None  # a person's own branch: not the workflow's to lock
    owner = target.owner
    target.state.mkdir(parents=True, exist_ok=True)
    claim(target.state, session, target.branch)
    remember_claim(session_target, target, session)
    if owner and owner.get("session") != session:
        return {"systemMessage": f"🔒 took over {target.toplevel} from {took_from(owner)}"}
    return None


def release_claimed(state, session):
    """Free the locks THIS session took in other checkouts (judge_bash), at its SessionEnd —
    only where the lock still names this session."""
    path = state / f"claimed-{session}"
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        other = Path(line.strip()) / "claude" / "owner.json"
        try:
            if json.loads(other.read_text()).get("session") == session:
                other.unlink()
        except (OSError, ValueError):
            continue
    path.unlink(missing_ok=True)


def off_workflow(branch, busy):
    """A branch outside the workflow's vocabulary: not main (the primary checkout's
    permanent, always-clean resting state — PreToolUse denies writes there) and not
    claude/* (which auto-commits, in a worktree). Checkpoints go silently OFF here —
    this is the only thing that flags it. (2026-09-10: a stray `master` branch, created
    by a `git switch`/`checkout` typo during a /finish merge, sat like this for a full
    session.)"""
    return bool(branch) and branch != MAIN and not branch.startswith("claude/") and not busy


def env_link_line(toplevel):
    """A gitignored .env doesn't follow a worktree; scripts that read it then fail. Only
    worth saying in a project that has one."""
    if (Path(toplevel) / ".env").exists():
        return "   ln -s \"$PWD/.env\" .claude/worktrees/<topic>/.env\n"
    return ""


def branch_recipe(topic="<topic>"):
    """`claude/<host>/<date>-<topic>`, with this machine and today filled in. A branch names
    where it came from, because two machines mint them now and the owner reads the list on GitHub
    (D7, 2026-09-22); the date is filled so nothing is guessed."""
    return f"claude/{common.host_name()}/{datetime.date.today().isoformat()}-{topic}"


SPAWNED_PREFIX = "worktree-"


def _git_ok(top, *args):
    return subprocess.run(["git", "-C", str(top), *args], capture_output=True, text=True,
                          timeout=10).returncode == 0


def spawned(toplevel, branch):
    """A branch Claude Code named for a worktree it made itself, under .claude/worktrees/."""
    return branch.startswith(SPAWNED_PREFIX) and ".claude/worktrees" in Path(str(toplevel)).as_posix()


def adoptable(toplevel, branch, main):
    """True when `branch` is spawned() with nothing of its own yet: its tip on main or origin/main
    (a spawn starts from origin/<main>). False otherwise; None when git did not answer in time."""
    if not spawned(toplevel, branch):
        return False
    try:
        return any(_git_ok(toplevel, "merge-base", "--is-ancestor", "HEAD", ref) for ref in (main, f"origin/{main}"))
    except subprocess.TimeoutExpired:
        return None


def adopt_spawned(toplevel, branch, main, quiet=False):
    """(branch, note): a worktree Claude Code made itself, renamed onto the workflow at its first write.

    Claude Code puts every worktree it creates on `worktree-<slug>` (2.1.288 `worktreeBranchName`):
    a Remote Control host's `--spawn worktree` session (orchestration E2), `claude --worktree`,
    EnterWorktree with a name, an isolated subagent — all of them, intended. Only claude/*
    checkpoints, so without this such a session works with checkpoints off. At the first write,
    not at SessionStart (code review, 2026-10-02): a read-only session then leaves no branch and
    pushes nothing empty, and sync.py has brought main down by then. Never onto a name that
    exists. `quiet`: no note for a branch with commits of its own — PreToolUse would repeat it
    on every write; Stop says it, once a turn, beside the off-workflow nag. Never for another CLI's
    call (VENDOR): a rename is a write to the checkout's state, as a claim is."""
    if VENDOR:
        return branch, None
    can = adoptable(toplevel, branch, main)
    if can is None:
        return branch, f"⚠ git was too slow to tell whether {branch} can join the workflow; not renamed this time"
    if not can:
        if quiet or not spawned(toplevel, branch):
            return branch, None
        return branch, (f"⚠ {branch} has commits of its own, so it was not renamed to claude/* — "
                        f"checkpoints stay off here until it is (git branch -m {branch} {branch_recipe()})")
    topic = re.sub(r"[^a-z0-9-]+", "-", branch[len(SPAWNED_PREFIX):].lower()).strip("-") or "session"
    new = branch_recipe(topic)
    try:
        renamed = not _git_ok(toplevel, "show-ref", "--quiet", "--verify", f"refs/heads/{new}") \
            and _git_ok(toplevel, "branch", "-m", branch, new)
    except subprocess.TimeoutExpired:
        renamed = False
    if not renamed:
        return branch, f"⚠ could not rename {branch} to {new}; checkpoints stay off here"
    return new, f"🌿 {branch} → {new}: on the workflow now, checkpoints on"


# The knowledge repos, by folder name (lib/knowledge.py: atlas's `atlas/layer` and `atlas/vault`
# keys); none where the keys are absent, and such a checkout is judged like any other repo.
KNOWLEDGE_REPOS = knowledge.names() if common else ()


def in_place_line(workflow):
    entries = in_place_entries(workflow)
    if not entries:
        return ""
    return (f"Only its in-place records are written on {(workflow or {}).get('main') or 'main'} "
            f"directly ({', '.join(entries)} — in_place in .claude/workflow.json); this path is "
            f"not one of them.\n")


def worktree_required_reason(toplevel, main=None, via=None, workflow=None):
    """`via`: the session's cwd, when the write reached this checkout from elsewhere — a
    `cd`/`-C` (D8) or a file path in an Edit/Write (D2) — then the recipe names the checkout by
    its absolute path, since a relative one would resolve in the session's own tree. A
    knowledge repo gets knowledge-commit's recipe instead: a session pinned in its own
    worktree cannot run `git -C <that repo> worktree add` (gap review item 16, 2026-10-02)."""
    main = main or MAIN
    name = Path(str(toplevel)).name
    if via and name in KNOWLEDGE_REPOS:
        kc = shown_tool("knowledge-commit")
        return (f"⛔ This writes to {toplevel}, reached from a session in {via}, and that "
                f"checkout stays on {main} (rule: git-workflow). {in_place_line(workflow)}"
                f"Launch the change reviewed, through a branch:\n"
                f"   {kc} {name} --open <slug>\n"
                f"edit the file under the path it prints, then\n"
                f"   {kc} {name} --in <that path> -m \"…\"\n"
                f"which says what review it needs. Don't retry the same write here — it will be "
                f"denied again.")
    if via:
        return (f"⛔ This writes to {toplevel}, reached from a session in {via} (cd/-C, or a file path), which "
                f"stays on {main} — writes there are blocked like any other write on {main} "
                f"(rule: git-workflow; D8, 2026-09-25). Launching is the exception — `git merge`, "
                f"`git pull --ff-only`, or resolving a merge in progress — and this command "
                f"isn't that. Make the change on a claude/* branch instead: in this session's "
                f"own worktree if it is the same repo, or in a worktree of that repo:\n"
                f"   git -C {toplevel} worktree add {toplevel}/.claude/worktrees/<topic> "
                f"-b {branch_recipe()} {main}\n"
                f"and run the write there (`cd <that worktree> && git …`). Don't retry the same "
                f"write here — it will be denied again.")
    return (f"⛔ The checkout {toplevel} stays on {main} — writes are blocked there so the user's "
            f"primary working copy never moves off it (rule: git-workflow). {in_place_line(workflow)}The one "
            f"exception is launching a finished branch: `git merge` itself is always allowed "
            f"on {main}, and once a merge is actually in progress (conflicts), so is "
            f"resolving it (add/commit/checkout/reset/restore/rm, and editing tracked "
            f"files) — but this command isn't part of that. Create a worktree and do the "
            f"work there instead:\n"
            f"1. git worktree add .claude/worktrees/<topic> -b {branch_recipe()} {main}\n"
            f"{env_link_line(toplevel)}"
            f"2. EnterWorktree with path .claude/worktrees/<topic>\n"
            f"Don't retry the same write here — it will be denied again.")


def lock_reason(owner, toplevel, main=None, state=None):
    """Why a write here is refused. `state` (the worktree's claude/ dir) lets it say when the
    lock is autofinish's runner (R2): the panel the owner left is told what holds it, in the words
    its prompt note used, not offered a worktree recipe for work that is being launched."""
    main = main or MAIN
    run = common.autofinish_running(state, owner) if state is not None else None
    if run:
        return (f"⛔ {autofinish_running_line(run, owner.get('branch'))}. That session "
                f"holds this checkout's lock until the run ends, so writes "
                f"here are refused. Don't retry or work around this — tell the user.")
    idle = int((time.time() - owner.get("seen", 0)) / 60)
    return (f"⛔ This checkout ({toplevel}) belongs to another Claude session "
            f"({owner['session'][:8]}, on {owner.get('branch') or '?'}, active {idle} min ago). "
            f"Two sessions writing one folder mix each other's edits and commits, so writes "
            f"here are blocked. Don't retry or work around this — tell the user and offer:\n"
            f"1. Move this session to its own worktree (safe to do; rule: git-workflow):\n"
            f"   git worktree add .claude/worktrees/<topic> -b {branch_recipe()} {main}\n"
            f"{env_link_line(toplevel)}"
            f"   then EnterWorktree with path .claude/worktrees/<topic>\n"
            f"2. Or close the other session; the lock frees when it exits "
            f"(or after {OWNER_TTL // 3600} h idle).")


# ---- the raw-branch sweep -------------------------------------------------------------

def sweep_raw_branches(common):
    """Delete claude/*-raw branches nothing needs any more (finish.md, "Nothing to finish?").
    A -raw is the pre-curation backup /finish makes right before merging; once the plain
    branch is gone (the merge launched, step 11 deleted it) and no worktree holds it, it is a
    leftover — 23 had piled up unswept by 2026-09-16. Refs are shared by every worktree, so
    this is repo-wide and the once-an-hour marker lives in the common git dir. Returns the
    names removed."""
    marker = common / "claude" / "raw-sweep"
    if marker.exists() and time.time() - marker.stat().st_mtime < SWEEP_EVERY:
        return []
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.touch()
    branches = git("for-each-ref", "--format=%(refname:short)", "refs/heads/").stdout.split()
    held = set(re.findall(r"^branch refs/heads/(\S+)$",
                          git("worktree", "list", "--porcelain").stdout, re.M))
    gone = []
    for name in branches:
        if not (name.startswith("claude/") and name.endswith("-raw")):
            continue
        if name[:-4] in branches or name in held:
            continue
        # When the REF last moved (`git branch -f` at /finish step 8) — not the tip's commit
        # date, which can be hours older than the merge the backup exists to undo.
        log = git("reflog", "show", "--date=unix", "-1", f"refs/heads/{name}", check=False).stdout
        found = re.search(r"@\{(\d+)\}", log)
        moved = int(found.group(1)) if found else int(
            git("log", "-1", "--format=%ct", f"refs/heads/{name}").stdout.strip() or 0)
        if time.time() - moved < RAW_GRACE:
            continue
        git("branch", "-D", name)
        gone.append(name)
    return gone


# ---- the prompt queue -----------------------------------------------------------------

def load_queue(path):
    try:
        entries = json.loads(path.read_text())
    except (OSError, ValueError):
        return []
    # Entries queued before the queue was session-aware are bare strings.
    return [e if isinstance(e, dict) else {"session": None, "prompt": e} for e in entries]


def save_queue(path, entries):
    if entries:
        path.write_text(json.dumps(entries[-MAX_PROMPTS:], ensure_ascii=False, indent=1))
    else:
        path.unlink(missing_ok=True)


def clean(prompt):
    return IDE_NOISE_RE.sub("", prompt).strip()


# ---- checkpoints ----------------------------------------------------------------------


def quote(text):
    text = clean(text)
    if len(text) > MAX_PROMPT_CHARS:
        text = text[:MAX_PROMPT_CHARS] + f"\n[… {len(text) - MAX_PROMPT_CHARS} more chars truncated]"
    return "\n".join(("> " + line).rstrip() for line in text.splitlines())


def build_message(summary, prompts, fallback, claude_made_it, session):
    lines = summary.strip().splitlines() if summary.strip() else [fallback]
    trailers = [l for l in lines if l.startswith(TRAILER)]
    if not trailers and (summary.strip() or claude_made_it):
        trailers = [DEFAULT_TRAILER]
    # Which session's hook made this checkpoint — /finish uses it to tell sessions apart.
    trailers.append(f"Claude-Session: {session[:8]}")
    parts = ["\n".join(l for l in lines if not l.startswith(TRAILER)).strip()]
    prompts = [p for p in prompts if clean(p)]
    if prompts:
        label = "Prompt:" if len(prompts) == 1 else "Prompts (oldest first):"
        parts.append(label + "\n" + "\n\n".join(quote(p) for p in prompts))
    parts.append("\n".join(trailers))
    return "\n\n".join(parts) + "\n"


def derive_summary(response):
    """Fall back to Claude's own chat response as the commit summary when it
    forgot to write commit-summary.md — costs no extra tokens, since the text
    already exists. Not pretty (no repo-style subject, no Deployed: line),
    but checkpoint commits are disposable: /finish reads diffs and rewrites
    all of this into real history anyway, so "useful for a human skimming
    `git log` later" is the only bar, not "well-formatted"."""
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", response)      # **bold**
    text = re.sub(r"^#{1,6}\s*", "", text, flags=re.M)    # # headers
    text = text.strip()
    if len(text) > MAX_DERIVED_LEN:
        text = text[:MAX_DERIVED_LEN].rsplit(" ", 1)[0] + " […]"
    return text


def checkpoint(summary_path, prompts, fallback, claude_made_it, session, response=""):
    """Commit everything. Returns (note for the user, whether a commit was made)."""
    git("add", "-A")
    staged = [p for p in git("diff", "--cached", "--name-only", "-z").stdout.split("\0") if p]
    if not staged:
        return None, False
    bad = [p for p in staged if is_forbidden(p)]
    if bad:
        git("reset", "-q")
        return f"⚠ checkpoint REFUSED — would commit {', '.join(bad)}. Nothing committed; fix .gitignore.", False
    summary = summary_path.read_text() if summary_path and summary_path.is_file() else ""
    derived = False
    if not summary.strip() and response.strip():
        summary = derive_summary(response)
        derived = True
    message = build_message(summary, prompts, fallback, claude_made_it, session)
    git("commit", "-q", "-F", "-", input=message)
    if summary_path:
        summary_path.unlink(missing_ok=True)
    sha = git("rev-parse", "--short", "HEAD").stdout.strip()
    subject = message.splitlines()[0]
    if not summary.strip() and claude_made_it:
        return f"⚠ checkpoint {sha} has NO SUMMARY — {subject}", True
    if derived:
        return f"✓ checkpoint {sha} (summary derived from chat) — {subject}", True
    return f"✓ checkpoint {sha} — {subject}", True


# ---- publishing ------------------------------------------------------------------------

def has_upstream(branch):
    return git("rev-parse", "--abbrev-ref", f"{branch}@{{u}}", check=False).returncode == 0


def open_wip_pr(branch, session):
    """A `WIP:` pull request for a branch on its first push, so the work is readable on a
    phone — a branch alone is a name in a list. Returns its URL or None. Quiet on every
    failure: no token, no GitHub remote, offline, or a PR already open."""
    if os.environ.get("CLAUDE_HOOK_NO_GITHUB"):
        return None
    slug = common.repo_slug(git("remote", "get-url", "origin", check=False).stdout.strip())
    tok = common.token() if slug else None
    if not tok or common.find_pr(slug, branch, tok):
        return None
    topic = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", branch.rsplit("/", 1)[-1]).replace("-", " ")
    body = (f"Agent work in progress on **{common.host_name()}**, session `{session[:8]}`.\n\n"
            f"Checkpoints are committed here every turn; `/finish` rewrites the history and drops the "
            f"WIP before this is ready to merge.\n\nOpened by wharf's `hooks/checkpoint.py`.")
    pr = common.open_pr(slug, branch, MAIN, f"WIP: {topic}", body, tok)
    return pr.get("html_url") if pr else None


def offered(state):
    """The HEAD the last push attempt was made at ('' before any, or from a marker older than
    2026-10-19, which held nothing)."""
    try:
        return (state / "pushed").read_text().strip()
    except OSError:
        return ""


SPENT_NAME = "spent.json"  # never `landed`: the common git dir's claude/ holds branches.py's record of that name


def landed(state, branch, ask=True):
    """GitHub's word that this branch already launched — {"branch", "number", "url", "origin"} of a
    pull request from it, into MAIN, that merged while none from it is open (common.landed_pr) — or
    None. A yes is kept in the state dir's SPENT_NAME, per branch name, with the origin ref it was
    seen beside, so a spent worktree costs one lookup, not one per turn; once that ref moves
    (someone pushed the branch by hand, as a reopened PR would) the yes is asked again, so an open
    PR wins here too. A no is asked again at the next push, since an open PR may merge meanwhile.
    A PR whose merge commit HEAD already holds is no yes: the branch forked from main after that
    landing, new work under a reused name. `ask=False` reads the kept yes only (the prompt-time
    context, sync after publish). None on every GitHub failure: the push goes ahead, as before."""
    marker = state / SPENT_NAME
    remote = git("rev-parse", "--verify", "-q", f"refs/remotes/origin/{branch}", check=False).stdout.strip()
    try:
        held = json.loads(marker.read_text())
        if held.get("branch") == branch and held.get("number") and held.get("origin", remote) == remote:
            return held
    except (OSError, ValueError, AttributeError):
        pass
    if not ask or os.environ.get("CLAUDE_HOOK_NO_GITHUB"):
        return None
    slug = common.repo_slug(git("remote", "get-url", "origin", check=False).stdout.strip())
    tok = common.token() if slug else None
    pr = common.landed_pr(slug, branch, tok, base=MAIN) if tok else None
    if not pr or not pr.get("number"):
        return None
    merged = pr.get("merge_commit_sha")
    if merged and git("merge-base", "--is-ancestor", merged, "HEAD", check=False).returncode == 0:
        return None
    held = {"branch": branch, "number": pr["number"], "url": pr.get("html_url") or "", "origin": remote}
    try:
        marker.write_text(json.dumps(held) + "\n")
    except OSError:
        pass
    return held


def spent_note(branch, held):
    """What a session in a landed branch's worktree hears instead of a push. The recipe names the
    main checkout absolutely: run from inside the spent worktree, a relative path would nest the
    new worktree in it (as worktree_required_reason's via= form says)."""
    top = main_checkout() or Path(ROOT)
    return (f"⛔ not pushed: {branch} already landed as #{held['number']}"
            + (f" ({held['url']})" if held.get("url") else "")
            + " — this worktree is spent; its new commits stay local. Start new work on a fresh branch:\n"
            f"   git -C {top} worktree add {top}/.claude/worktrees/<topic> -b {branch_recipe()} {MAIN}")


def spent_context(branch, held):
    """The model's copy of spent_note: a Stop note reaches the owner's screen only."""
    return (spent_note(branch, held).replace("⛔ not pushed: ", "The checkpoint hook no longer pushes this branch: ")
            + ", then EnterWorktree. Tell the user; do not push this branch by hand.")


def publish(state, branch, session, force=False):
    """Push this claude/* branch to origin (see PUSH_EVERY). Returns a note or None.
    Never a branch whose PR already merged (landed()): the push would put its checkpoint history
    back on origin and the first-push path would open a WIP PR of work main has (regatta#171)."""
    if not branch.startswith("claude/") or os.environ.get("CLAUDE_HOOK_NO_PUSH"):
        return None
    if git("remote", "get-url", "origin", check=False).returncode != 0:
        return None
    first = not has_upstream(branch)
    marker = state / "pushed"
    if not first:
        if not force and marker.exists() and time.time() - marker.stat().st_mtime < PUSH_EVERY:
            return None
        if git("rev-list", "--count", f"{branch}@{{u}}..HEAD", check=False).stdout.strip() in ("", "0"):
            return None
    # Before the attempt: a failing origin is retried in PUSH_EVERY, not every turn. The marker
    # holds the HEAD it was written at, so a Stop can tell a commit no push has been offered yet
    # (offered(), below) from one a failing origin already refused.
    head = git("rev-parse", "HEAD", check=False).stdout.strip()
    told = offered(state) == head
    marker.write_text(head + "\n")
    spent = landed(state, branch)
    if spent:  # said once per new commit it strands; a forced push (session end, sync) always hears it
        return None if told and not force else spent_note(branch, spent)
    try:
        r = subprocess.run(["git", "push", "-q", "-u", "origin", branch], cwd=ROOT,
                           capture_output=True, text=True, timeout=PUSH_TIMEOUT)
    except subprocess.TimeoutExpired:
        return f"⚠ push of {branch} timed out — origin unreachable?"
    if r.returncode:
        err = (r.stderr.strip().splitlines() or ["?"])[-1]
        return f"⚠ push of {branch} failed: {err[:160]}"
    # The WIP PR once per worktree, not only on the first push: a branch that arrives with an
    # upstream — a seed (`pickup seed` pushes it), or one `pickup` checked out with --track on
    # the other machine — never has a "first" push here (review 2026-09-29, the real seed
    # doc-answers-carry had no PR). The marker keeps it to one GitHub lookup per worktree.
    checked = state / "pr-checked"
    if first or not checked.exists():
        checked.touch()
        url = open_wip_pr(branch, session)
        if first:
            return f"↑ {branch} is on origin" + (f" — PR {url}" if url else "")
        return f"↑ {branch}: PR {url}" if url else None
    return None


# ---- a doc that asks the owner something ------------------------------------------------------
# Why (2026-09-28): a session on the other Mac rendered for hours on the pre-filled answers of
# a memo in another repo, because the owner's real answers sat uncommitted on the laptop's
# `main`, where the old rule (a doc merged to main before asking) had put the doc. Answers now
# travel as commits on the doc's own branch (`/keel`, D2 of docs/feedback-2026-09-29.md):
# a commit that adds answer lines (or any line to a doc that has them) is pushed now, not in
# PUSH_EVERY, and when it asks something the reply must carry the doc's hand-over line (`keel line`;
# since 2026-10-07, the GitHub edit URL before) — blocked once when it does not (`stop_hook_active`
# guard). A reply that itself asks is bin/paste-paths' to judge (answer_link_block stands back); this
# hook keeps the turn that wrote the D-list and handed it over without asking, whose link is only
# true once this hook's commit and push have happened (Stop hooks run in parallel).
# Only a line that STARTS with the marker (after a list bullet) or a D-item line carrying it
# counts, so prose quoting the arrow mid-sentence is not a hit (R4: a false positive costs one
# early push and one link line).
ANSWER_ADDED_RE = re.compile(r"^\+\s*(?:(?:[-*]|\d+\.)\s+)?(?:➤ Answer:|\*{0,2}D\d+\*{0,2}\s*[—–\-.:].*➤ Answer:)")
# An added D-item line: the doc now ASKS something. Answer lines alone are answers arriving
# (`memo merge`, an --on-main copy, the owner's tab edits) — pushed at once, but no link is owed.
ITEM_ADDED_RE = re.compile(r"^\+\s*(?:(?:[-*]|\d+\.)\s+)?\*{0,2}D\d+\*{0,2}\s*[—–\-.:]")
# A doc that HAS answer lines, in any shape the repos used: one pattern, two spellings — POSIX
# classes for `git grep -E` (Apple git's grep has no \s), and the same in Python for the doc read
# with its fences taken out. Inline older shapes count: `1. **D1 Run …** ➤ Answer: yes`,
# `**D2** Keep it? ➤ Answer: yes` (review, 2026-10-04).
ANSWER_DOC_GREP = r"^[[:space:]]*(([-*]|[0-9]+\.)[[:space:]]+)?(\*{0,2}D[0-9]+.*)?➤ Answer:"
ANSWER_DOC_RE = re.compile(r"^\s*(([-*]|[0-9]+\.)\s+)?(\*{0,2}D[0-9]+.*)?➤ Answer:")


def answer_docs(*revs):
    """{doc: asks} for the .md files these commits add answer lines to, or any line to a doc
    that already has them (paths relative to the repo top); `asks` when they add both an
    answer line and a D-item line. `revs`: one commit, or `a..b`. quotePath off and the TAB git
    appends to a path with a space stripped (review 2026-09-29)."""
    args = ("show", "--format=") if len(revs) == 1 and ".." not in revs[0] else ("diff",)
    new = revs[-1].split("..", 1)[1] or "HEAD" if ".." in revs[-1] else revs[-1]  # the diff's new side
    r = git("-c", "core.quotePath=false", *args, "-U0", "--no-color", *revs, "--", "*.md", check=False)
    docs, cur, asks, touched, at, fence = {}, None, set(), set(), 0, None
    for line in r.stdout.splitlines():
        if line.startswith("+++ "):
            cur = line[6:].rstrip("\t") if line.startswith("+++ b/") else None
            fence = None
            continue
        h = HUNK_RE.match(line)
        if h:
            at = int(h.group(1))
            continue
        if not (cur and line.startswith("+")):
            continue
        touched.add(cur)
        at += 1
        answer, item = ANSWER_ADDED_RE.match(line), ITEM_ADDED_RE.match(line)
        if not (answer or item):
            continue
        # An added line inside a fenced block of the new file is an example, neither an answer nor
        # an ask: a commit adding only a fenced D-item to a doc with real answers was blocked for
        # links (memo-lint-fixes, 2026-10-05). Fences come from the whole file, not the hunk, and
        # only for a file with a line that could count (one `git show` each, not per touched doc).
        if fence is None:
            fence = fenced_lines(new, cur)
        if 0 < at - 1 <= len(fence) and fence[at - 2]:
            continue
        if answer:
            docs[cur] = docs.get(cur, False)
        if item:
            asks.add(cur)
    # The owner writes anywhere in a doc, not only on answer lines ("Approved." under D1 in the first
    # live run, 2026-09-29): any added line in a doc that HAS answer lines counts too.
    # POSIX classes, not \s: Apple git's grep -E has no \s and silently matched no indented
    # line. --full-name and :(top,literal): the hook's cwd may be a subfolder (review 2026-09-29).
    answered_here = set(docs)
    rest = sorted(touched - answered_here)
    if rest:
        g = git("-c", "core.quotePath=false", "grep", "-l", "--full-name", "-E",
                ANSWER_DOC_GREP, "HEAD",
                "--", *(":(top,literal)" + p for p in rest), check=False)
        for l in g.stdout.splitlines():
            docs.setdefault(l.split(":", 1)[1] if l.startswith("HEAD:") else l, False)
    # The lines above are read without context, so a fenced example — the D-item shape in
    # agents/architect.md, a doc quoting one — matched too, and its commit was pushed and blocked
    # for edit links to a file that asks nothing (re-review, 2026-10-04). Keep a doc only when the
    # broad answer-doc pattern still matches it at HEAD with its fenced blocks taken out. Not memo's parse:
    # 77 of 251 answer docs use older shapes it does not read (numbered items, no separator,
    # DESIGN.md, the dream skill), and they would lose the immediate push.
    return {d: d in asks and d in answered_here for d in docs if outside_fences(d)}


HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def fenced_lines(rev, rel):
    """common.fenced over the doc at `rev`; [] when git can't show it (then nothing is fenced)."""
    r = git("show", f"{rev}:{rel}", check=False)
    # split("\n"), not splitlines(): the hunk header counts only \n, and splitlines also breaks
    # on \f, \x1c–\x1e, \x85 and U+2028, which would shift every later index (review, 2026-10-05)
    return [] if r.returncode else common.fenced(r.stdout.split("\n"))


def outside_fences(rel):
    """False only when every answer line of the doc at HEAD sits in a fenced block.
    Never raises: on any error the doc stays an answer doc, as before."""
    try:
        r = git("show", f"HEAD:{rel}", check=False)
        if r.returncode:
            return True
        lines = r.stdout.splitlines()
        return any(not f and ANSWER_DOC_RE.match(l) for l, f in zip(lines, common.fenced(lines)))
    except Exception:
        return True


# The page mirror (docs/record/orchestration-proposal-2026-10-02.md, D4 and E3): every D-list doc
# this hook just pushed is redeployed as its page — the form since 2026-10-14, answered with a Save
# or comments, from the phone too — and a reply that asks owes it as the line's course part. bin/keel does the work and decides
# whether it can: no mirror CLI or no key on this Mac is a silent skip, so the mirror
# appears the day step 8's install does. One deploy per changed doc, about a second (a doc the
# page already shows is not redeployed); memo starts no deploy past its budget and the call is
# capped, so a hung CLI never holds a turn long after the push — a failure is a note, never a
# retry. The Stop entry has no `timeout` in settings.json, so the harness default applies.
def shown_tool(name):
    """How a message to a session names a peer tool: the module's through common.tool(), else the
    bare name; under `~` where it can be. The overlay's shim came first until B14b (2026-10-23),
    which deleted it; the account dirs' and unattended runs' allow rules name the module paths since."""
    p = None
    if common:
        try:
            p = common.tool(name)
        except Exception:
            p = None
    if not p:
        return name
    p, home = str(p), os.path.expanduser("~")
    return "~" + p[len(home):] if p.startswith(home + os.sep) else p


# keel is a peer (G4): found through common.tool(); without it no page and no hand-over-line
# block — skipped, silently, like CLAUDE_HOOK_NO_SHEEP.
MEMO = (common.tool("keel") if common else None)
SHEEP_BUDGET = 20
SHEEP_TIMEOUT = 30


def sheep_pages(branch, docs):
    """({rel: page url}, note) for these pushed docs (paths relative to the repo top)."""
    if not docs or os.environ.get("CLAUDE_HOOK_NO_SHEEP") or not MEMO:
        return {}, None
    if git("rev-list", "--count", f"{branch}@{{u}}..HEAD", check=False).stdout.strip() != "0":
        return {}, None  # the push did not go through: the page would show a copy GitHub lacks
    top = git("rev-parse", "--show-toplevel").stdout.strip()
    # memo stops starting deploys once its budget is spent and prints each doc's line as it
    # goes, so a cap hit mid-run still keeps the pages that finished (review, 2026-10-03)
    proc = subprocess.Popen([sys.executable, str(MEMO), "sheep", "--hook", "--budget", str(SHEEP_BUDGET),
                             *(f"{top}/{d}" for d in docs)],
                            cwd=top, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    timed_out = False
    try:
        out, err = proc.communicate(timeout=SHEEP_TIMEOUT)
    except subprocess.TimeoutExpired:
        proc.kill()
        out, err = proc.communicate()
        timed_out = True
    r = subprocess.CompletedProcess(proc.args, -9 if timed_out else proc.returncode, out, err)
    pages, failed, warned = {}, [], []
    if timed_out:
        failed.append(f"timed out after {SHEEP_TIMEOUT}s — `python3 {shown_tool('keel')} sheep <doc>` by hand")
    for line in r.stdout.splitlines():
        try:
            row = json.loads(line)
        except ValueError:
            continue
        rel = os.path.relpath(row.get("doc", ""), top)
        if row.get("url"):
            pages[rel] = row["url"]
        elif row.get("error"):
            failed.append(f"{rel}: {row['error'][:120]}")
        if row.get("note"):   # keel's own word on a page that deployed: the publish budget's warning
            warned.append(str(row["note"])[:240])
    if r.returncode and not timed_out and not failed:
        failed.append((r.stderr.strip().splitlines() or ["keel sheep failed"])[-1][:160])
    shown = pages
    if pages:
        try:  # the mirror's address while one runs (memo's chat_page); the plain URL on any failure
            memo = _memo_module()
            shown = {d: memo.chat_page(u) for d, u in pages.items()}
        except Exception:
            pass
    note = ("🐑 " + ", ".join(f"{d} → {u}" for d, u in shown.items())) if pages else None
    if failed:
        note = (note + " · " if note else "") + "⚠ page mirror: " + "; ".join(failed)
    if warned:
        note = (note + " · " if note else "") + "⚠ " + "; ".join(dict.fromkeys(warned))
    return pages, note


def _memo_module():
    """bin/keel as a module: its line_findings is the one reader of the hand-over line, shared
    with bin/paste-paths (the same loader). Stdlib, Python 3.9, like this hook."""
    import importlib.util
    from importlib.machinery import SourceFileLoader
    if not MEMO:
        raise ImportError("keel not installed")  # each caller's except: no page note, no block (G4)
    loader = SourceFileLoader("memo_for_checkpoint", str(MEMO))
    mod = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(mod)
    return mod


def answer_link_block(branch, docs, data):
    """The block reason when this turn's commit asks the owner D-items (a D-item line added), the doc
    is on GitHub, and the reply lacks the doc's hand-over line — or None.

    The line is the one `keel line <doc>` prints, `[course or local](…) | [github](…) | [space](…) —
    [<file>](<absolute path>#L1)` (the owner, 2026-10-04/05; enforced 2026-10-07), read by bin/keel's
    line_findings, the same reader bin/paste-paths' Stop hook uses. A reply that itself asks
    (common.asks_answers) is paste-paths' to judge, so this stands back: one Stop, one block, one
    ask. This hook keeps the turn that wrote a D-list and handed it over without asking. Until
    2026-10-07 it asked for the local file, GitHub's edit URL, the page and — in VS Code only —
    the form; since 2026-10-14 the form is the doc's mirrored page, and memo serve's where no page
    can be made, bar an unattended run or a Remote Control session (memo's line_plan). The page is checked against the pin
    sheep_pages' deploy just wrote."""
    if not docs or data.get("stop_hook_active"):
        return None
    if git("rev-list", "--count", f"{branch}@{{u}}..HEAD", check=False).stdout.strip() != "0":
        return None  # not on GitHub (push failed, or no upstream): a link would show the wrong copy
    reply = data.get("last_assistant_message") or ""
    if common.asks_answers(reply):
        return None  # bin/paste-paths owns a reply that asks: the same line, one block
    top = git("rev-parse", "--show-toplevel").stdout.strip()
    try:
        memo = _memo_module()
    except Exception:  # a broken bin/keel must not cost the Stop: no block rather than a wrong one
        return None
    missing = []
    for rel in docs:
        path = Path(top) / rel
        try:
            probs = memo.line_findings(reply, path)
        except Exception:
            continue
        if probs:
            missing.append(f"{rel}: " + "; ".join(probs[:3])
                           + f" (python3 {shown_tool('keel')} line {shlex.quote(str(path))})")
    if not missing:
        return None
    return ("This turn's commit asks the owner D-items, and the doc is on GitHub now. End your reply "
            "with the doc's hand-over line, exactly as `keel line <doc>` prints it — "
            "[course or local](…) | [github](…) | [space](…) — [<file>](<absolute path>#L1); a part it leaves "
            "out comes with its reason on stderr: say that, never build the link (skill /keel). The course link "
            f"is the doc's mirrored page — run `python3 {shown_tool('keel')} sheep wait <doc>` as a background shell when the "
            "session should go on after the owner's Save or comments there — or keel serve's where the doc has "
            f"no page (start `python3 {shown_tool('keel')} serve <doc>` in the background first; `keel line` reuses it): "
            + "; ".join(missing))



# A GitHub link that shows the wrong copy (2026-10-04): three replies that day sent the owner an edit
# page missing the D-items the reply named — two branches never pushed, and one whose push GitHub
# refused because the owner had answered there meanwhile (registrar-access, D7). answer_link_block
# skips an unpushed branch rather than ask for a false link; this catches the reply that carries
# one anyway. Any github.com/<this repo>/(edit|blob)/<this branch>/<path> in the reply is checked
# after this Stop's push, against the remote-tracking ref (moved by that push when there was one;
# PUSH_EVERY may skip it, and then GitHub really lacks the copy) — no fetch: if the owner
# typed answers there and this side has no new commits, GitHub's copy is the newer one and the link
# is fine; if this side has commits too, the push failed and the ref is behind. Blocked once.
def stale_link_block(branch, data, push=None):
    if data.get("stop_hook_active") or not branch.startswith("claude/"):
        return None
    reply = data.get("last_assistant_message") or ""
    slug = common.repo_slug(git("config", "--get", "remote.origin.url", check=False).stdout.strip())
    if not slug or f"github.com/{slug}/" not in reply:
        return None
    from urllib.parse import quote as q, unquote
    ref = q(branch, safe="/")
    found = re.findall(r"https://github\.com/%s/(?:edit|blob)/%s/([^\s)>\]`'\"#?]+)"
                       % (re.escape(slug), re.escape(ref)), reply)
    if not found:
        return None
    if push:
        push()  # the hook owns pushing: a link to this branch makes the PUSH_EVERY spacing moot
    top = git("rev-parse", "--show-toplevel").stdout.strip()
    origin = f"refs/remotes/origin/{branch}"
    base = git("merge-base", "HEAD", origin, check=False).stdout.strip()
    stale = []
    for rel in dict.fromkeys(unquote(f).rstrip(".,;:!*") for f in found):
        path = Path(top) / rel
        if not path.is_file():
            continue
        here = git("hash-object", str(path), check=False).stdout.strip()
        there = git("rev-parse", "-q", "--verify", f"{origin}:{rel}", check=False).stdout.strip()
        if here == there:
            continue
        if base and here == git("rev-parse", "-q", "--verify", f"{base}:{rel}", check=False).stdout.strip():
            continue  # this side never touched it since the two parted: GitHub's is the newer copy
        stale.append(f"{rel} (python3 {shown_tool('keel')} line {shlex.quote(str(path))})")
    if not stale:
        return None
    return ("Your reply links GitHub's copy of a file GitHub does not hold in this checkout's version — "
            "not pushed, or the push was refused because GitHub has commits this branch lacks (answers "
            "the owner typed there?). The owner would open a page without your changes. Run keel line for each: its "
            "stderr names the fix (memo pull, then push), its stdout the checked line; then end the reply again: "
            + "; ".join(stale))

# Session titles by mechanism (A4 of docs/record/orchestration-proposal-2026-10-02.md): 10 of 44
# sessions had no title, and asking the owner to /rename was manual work (D6). At Stop the hook writes
# what /rename writes to disk, `<repo>: <topic>` from the branch, once per session, and only when
# no custom title exists — a /rename or a /move fork's title wins; an ai-title does not, since
# custom-title beats it (lessons/claude-code.md). Two places, both needed: the transcript records
# (bin/pickup and `claude -r` read the whole file) and the sidecar `<session id>/custom-title.json`
# beside it — VS Code's list (extension 2.1.288–2.1.289) reads only the transcript's first and last
# 64 KiB, then that sidecar, and a transcript is past 64 KiB by its first Stop (review,
# 2026-10-04). Disk only: /rename also pushes the name to the Remote Control bridge in-process,
# so the phone, claude.ai and the open tab see this title only once it is picked up again — a name wanted
# there now is still `/rename`. Scope: claude/* branches of workflow repos, not locked out or
# moved. It writes from its own Stop event, never from a tool call: a tool call appending to a
# live transcript is what the auto-mode classifier refuses ("Session Transcript Tampering").
TOPIC_RE = re.compile(r"claude/(?:[^/]+/)?(?:\d{4}-\d{2}-\d{2}-?)?([^/]*)$")
TITLE_RECORD = b'{"type":"custom-title"'  # how the CLI writes it: compact, type first (bin/pickup reads it so)
TITLED_KEEP = 50  # session ids remembered per worktree in titled.json


def branch_topic(branch):
    """`session titles` from `claude/<host>/<date>-session-titles`; None when no word is left."""
    m = TOPIC_RE.match(branch or "")
    words = [w for w in m.group(1).split("-") if w] if m else []
    return " ".join(words) if any(ch.isalpha() for ch in "".join(words)) else None


def title_session(state, branch, data, session, repo_of):
    """Name the session `<repo>: <topic>`; the title written, or None. `repo_of` is called only
    when a title is about to be written: it costs a git call, and most Stops are not that."""
    topic = branch_topic(branch)
    path = data.get("transcript_path")
    if not topic or not path or session == "unknown":
        return None
    titled_path = state / "titled.json"
    try:
        titled = json.loads(titled_path.read_text())
    except (OSError, ValueError):
        titled = []
    titled = titled if isinstance(titled, list) else []
    if session in titled:
        return None
    # Named = a custom-title record in the transcript, which /rename always writes. A sidecar
    # alone is this hook's own write cut short: the retry adds the records and keeps the sidecar.
    sidecar = Path(path).parent / session / "custom-title.json"
    try:
        named, last = False, b"\n"
        with open(path, "rb") as f:  # streamed: a transcript can run to tens of MB
            for line in f:
                if line.startswith(TITLE_RECORD):
                    named = True
                    break
                last = line[-1:] or last
    except FileNotFoundError:
        return None  # not written yet: the next Stop tries again
    repo = None if named else repo_of()
    if repo:
        title = f"{repo}: {topic}"
        dump = lambda rec: json.dumps(rec, ensure_ascii=False, separators=(",", ":"))
        sidecar.parent.mkdir(mode=0o700, exist_ok=True)
        try:  # first: it is what VS Code's list reads
            with os.fdopen(os.open(sidecar, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600),
                           "w", encoding="utf-8") as f:
                f.write(dump({"customTitle": title}))
        except FileExistsError:
            pass
        # Never O_CREAT: a transcript that moved away since the read is not one to start. A torn
        # last line (a write cut short) gets its newline first, or the record glues onto it.
        with os.fdopen(os.open(path, os.O_WRONLY | os.O_APPEND), "w", encoding="utf-8") as f:
            f.write(("" if last == b"\n" else "\n") + "".join(
                dump(rec) + "\n" for rec in (
                    {"type": "custom-title", "customTitle": title, "sessionId": session},
                    {"type": "agent-name", "agentName": title, "sessionId": session})))
    # Recorded only now, so a failed write is tried again at the next Stop.
    titled_path.write_text(json.dumps((titled + [session])[-TITLED_KEEP:]))
    return title if repo else None


# ---- autofinish (docs/autofinish-design-2026-10-02.md, E3 and E6) --------------------------
# bin/autofinish is the launcher; this hook gives it its idle clock and two of its triggers (the
# third is launchd's sweep), and tells the panel the owner left what became of the branch. What it
# reads is bin/autofinish's contract (its header), through common.py's readers; it writes only
# last-reply and its own `.said` record. The launcher always runs as a child process — detached
# for a start, so no turn waits on GitHub or a runner; bounded for the one check a reply waits
# on (the declared line). Disarmed (the default), every child only judges and logs.
# The launcher is wharf-runs' (G1): found through common.tool(), and with none there is no child —
# the same branch as the suites' CLAUDE_HOOK_NO_AUTOFINISH, so the turn still commits, silently.
AUTOFINISH_BIN = (Path(os.environ["CLAUDE_AUTOFINISH_BIN"]) if os.environ.get("CLAUDE_AUTOFINISH_BIN")
                  else (common.tool("autofinish") if common else None) or Path("/nonexistent/autofinish"))
AUTOFINISH_OFF_ENV = "CLAUDE_HOOK_NO_AUTOFINISH"  # the suites: no launcher child, ever
LAST_REPLY = "last-reply"
LAST_REPLY_KEEP = 4000  # the reply's tail: its last lines are all the reply veto reads
AUTOFINISH_AFTER = 60   # SessionEnd's child waits this long, then judges (design E3)
# ls-remote, dispatch's queue (one `dispatch-queue list --all --json`, a fetch of the home) and four GitHub reads,
# under the hook's own 60 s. A slow queue home (its read waits up to 90 s) runs past it: the check then reads
# None, "could not judge", never a start (S3's third landing review, item 7)
AUTOFINISH_CHECK_TIMEOUT = 45
AUTOFINISH_SAID = "autofinish.said"
SAID_KEEP = 50  # sessions remembered per worktree


def autofinish_running_line(run, branch=None):
    # the run's details too: the backstop for a panel its SendMessage did not reach (autofinish-run notify)
    return (f"autofinish is running /finish on this branch since {common.iso_clock(run.get('started'))} "
            f"(window \"{common.autofinish_window(run, branch)}\", session {str(run.get('session') or '?')[:8]}, "
            f"account {run.get('account') or 'unchanged'}, rule {run.get('rule') or '?'}); wait, or /autofinish off")


def reply_tail(text):
    """The reply's last LAST_REPLY_KEEP characters, never cut inside a code block: there the
    block's closing fence would read as an opener, and common.ending — rule C's check and this
    Stop's — would miss a declared line after it (review at rename S2's /finish). A cut that falls
    in a block moves on to the first line outside it."""
    start = len(text) - LAST_REPLY_KEEP
    if start <= 0:
        return text
    lines, pos = text.splitlines(keepends=True), 0
    for line, inside in zip(lines, common.fenced([l.rstrip("\r\n") for l in lines])):
        if pos + len(line) > start and not inside:
            return text[max(pos, start):]
        pos += len(line)
    return text[start:]


def write_last_reply(state, text):
    """The launcher's idle clock is this file's mtime (bin/autofinish, rule `idle`); its text, the
    reply's tail, is what the Stop's own check and a `now` start judge — the transcript may not
    hold the reply yet when this hook runs. Through a rename, so a reader never sees half."""
    tmp = state / f".{LAST_REPLY}.{os.getpid()}"
    tmp.write_text(reply_tail(text), encoding="utf-8")
    os.replace(tmp, state / LAST_REPLY)


def autofinish_due(state, data):
    """(the reply ends in the declared line, `/autofinish now` is set) — either makes this Stop
    push at once and hand the branch to the launcher."""
    _, line, _ = common.ending(data.get("last_assistant_message") or "")
    ov = common.autofinish_override(state)
    return line in common.DECLARED_LINES, bool(ov and ov.get("now") is True)


def spawn_autofinish(*args):
    """bin/autofinish with `args`, detached: its own session, so neither the end of this hook nor
    of Claude Code takes it down (R4). Never waited on. False when the suites switched it off."""
    if os.environ.get(AUTOFINISH_OFF_ENV) or not AUTOFINISH_BIN.exists():
        return False
    subprocess.Popen([str(AUTOFINISH_BIN), *args], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, cwd="/", start_new_session=True)
    return True


def autofinish_verdict(toplevel, session, state):
    """This session's own dry run of its worktree — the verdict part of `<repo> <branch>
    <verdict>` — or None when it could not be read (switched off, too slow, a crash)."""
    if os.environ.get(AUTOFINISH_OFF_ENV) or not AUTOFINISH_BIN.exists():
        return None
    try:
        r = subprocess.run([str(AUTOFINISH_BIN), "--worktree", str(toplevel), "--dry-run", "--session", session,
                            "--reply", str(state / LAST_REPLY)], capture_output=True, text=True,
                           timeout=AUTOFINISH_CHECK_TIMEOUT, cwd="/")
    except (OSError, subprocess.TimeoutExpired):
        return None
    lines = [l for l in r.stdout.splitlines() if l.strip()]
    parts = lines[-1].split(" ", 2) if lines and not r.returncode else []
    return parts[2] if len(parts) == 3 else None


def autofinish_at_stop(state, data, session, toplevel, declared):
    """(block reason, note) at the end of a turn that ends in the declared line, runs under
    `/autofinish now`, or committed a deploy (rule L). The declared line is allowed only when this session's own dry run says
    `start` (E6): otherwise the reply is blocked once (stop_hook_active), as bin/paste-paths
    blocks a wrong closing line. Then the launcher judges the worktree again in a detached child
    and, armed, starts it — a `now` without the line too: rule C starts "at the next turn end
    whose reply asks nothing", and the child's verdict, not this hook, decides that."""
    if declared and not data.get("stop_hook_active"):
        if not os.environ.get(AUTOFINISH_OFF_ENV) and not AUTOFINISH_BIN.exists():
            # G1 absent: no lander is installed, so nothing would ever launch the branch — a
            # promise, not a transient failure to note (B5 review).
            line = common.ending(data.get("last_assistant_message") or "")[1] or common.DECLARED_LINE
            return (f"Your reply ends with `{line}`, but no autofinish is installed here (wharf-runs), "
                    f"so nothing launches this branch by itself. End the reply again without that line: "
                    f"the branch lands by /finish."), None
        v = autofinish_verdict(toplevel, session, state)
        if v is None:
            return None, "⚠ autofinish could not judge this branch, so the declared line went unchecked"
        if not v.startswith("start ("):
            # the line the reply said, old or new (common.DECLARED_LINES): quoted as it was written
            line = common.ending(data.get("last_assistant_message") or "")[1] or common.DECLARED_LINE
            return (f"Your reply ends with `{line}`, but this session's own dry run "
                    f"says `{v}` — the line is only for a branch autofinish would start now "
                    f"(`/autofinish` set, nothing asked, pushed, its PR still WIP:). End the reply "
                    f"again with the line that is true: the WAITING line when the owner must act, "
                    f"`{common.marked('pending', common.PENDING_PREFIX)}<what>` when its own work goes on, or none of these."), None
    if not spawn_autofinish("--worktree", str(toplevel), "--session", session,
                            "--reply", str(state / LAST_REPLY), "--log"):
        return None, None
    return None, ("🤖 autofinish judges this branch now — "
                  + ("armed: it starts /finish when the verdict is start" if common.autofinish_armed()
                     else "disarmed: logged only"))


def autofinish_prompt_note(state, owner, session, branch):
    """(note for the owner, context for the model) about this worktree's run, once per session per
    phase — `running`, then its outcome — or (None, None). The runner's own session is never
    told about itself; a record whose lock is gone without an end (a runner that died) says
    nothing."""
    rec = common.autofinish_run(state)
    if not rec or rec.get("session") == session:
        return None, None
    if common.autofinish_running(state, owner):
        phase, text = "running", autofinish_running_line(rec, branch)
    elif rec.get("ended"):
        phase, text = str(rec.get("outcome")), common.autofinish_outcome(rec)
    else:
        return None, None
    if not text:
        return None, None
    key = f"{rec.get('started')}|{phase}"
    path = state / AUTOFINISH_SAID
    try:
        said = json.loads(path.read_text())
    except (OSError, ValueError):
        said = {}
    said = said if isinstance(said, dict) else {}
    if key in said.get(session, []):
        return None, None
    said[session] = (said.get(session) or []) + [key]
    path.write_text(json.dumps(dict(list(said.items())[-SAID_KEEP:])))
    return f"🤖 {text}", f"{text[0].upper()}{text[1:]}."


def no_workflow_reason(root):
    """Why this repo refuses the workflow, or None. One line of prose, quoted back in the
    deny message so the reason travels with the refusal instead of living in a doc."""
    try:
        text = (Path(root) / NO_WORKFLOW_FILE).read_text().strip()
    except OSError:
        return None
    first = text.splitlines()[0].strip() if text else ""
    return first or "the repo carries .claude/no-workflow"


def adoption_target(tool, tool_input, cwd):
    """The repo root an opt-in file would be created in, or None."""
    if tool in WRITE_TOOLS:
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        hits = [path] if path.replace("\\", "/").endswith(str(WORKFLOW_FILE)) else []
        base = Path(cwd)
    elif tool == "Bash":
        command = tool_input.get("command", "")
        if not ADOPT_WRITE_RE.search(command):
            return None  # mentioning the path is not creating it
        hits = ADOPT_PATH_RE.findall(command)
        cd = CD_PREFIX_RE.match(command)
        base = Path(os.path.expanduser(cd.group(1))) if cd else Path(cwd)
        if not base.is_absolute():
            base = Path(cwd) / base
    else:
        return None
    for hit in hits:
        path = Path(os.path.expanduser(hit))
        if not path.is_absolute():
            path = base / path
        root = Path(os.path.normpath(str(path))).parent.parent
        if no_workflow_reason(root):
            return root
    return None


def load_workflow(toplevel):
    """The project's opt-in, or None. Anything unreadable counts as not opted in: a hook
    that fires in every directory must never nag a project that didn't ask for it."""
    return load_workflow_at(toplevel, main_checkout())


def load_workflow_at(toplevel, main_checkout_root):
    """load_workflow() for any checkout, its primary named explicitly (D4: a `cd X &&`
    target is judged by X's own opt-in)."""
    for root in (toplevel, main_checkout_root):
        if root is None:
            continue
        if no_workflow_reason(root):
            return None  # the marker wins over a workflow.json that slipped in beside it
        try:
            cfg = json.loads((root / WORKFLOW_FILE).read_text())
        except (OSError, ValueError):
            continue
        return cfg if isinstance(cfg, dict) and cfg.get("checkpoint") else None
    return None


def main_checkout():
    """The primary checkout's top level, from inside any of its worktrees. A worktree forked
    before the project opted in has no workflow.json of its own; the project's decision is
    the one on its main checkout, and without this fallback such a worktree would silently
    lose checkpoints and the lock the day the project moves onto the shared hook."""
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir", check=False).stdout.strip()
    return Path(common).parent.resolve() if common.endswith("/.git") else None


def already_handled(state, event, raw):
    """True when another copy of this hook already took this exact event. A session can have
    the hook wired twice — user-wide and through a project's own leftover wiring (a shim) —
    and the two copies run in parallel: both would queue the prompt, and both would race to
    commit. Only the events with side effects are deduplicated; a doubled PreToolUse is
    harmless, and must never be skipped, because skipping is what "allow" looks like."""
    if event not in ("UserPromptSubmit", "Stop"):
        return False
    seen = state / "seen"
    seen.mkdir(parents=True, exist_ok=True)
    now = time.time()
    for f in seen.iterdir():
        try:
            if now - f.stat().st_mtime > DEDUPE_WINDOW:
                f.unlink()
        except OSError:
            pass
    try:
        os.close(os.open(seen / hashlib.sha1(raw.encode()).hexdigest()[:20],
                         os.O_CREAT | os.O_EXCL | os.O_WRONLY))
    except FileExistsError:
        return True
    return False


def main():
    global ROOT, MAIN, VENDOR
    raw = sys.stdin.read()
    data = json.loads(raw)
    cli = data.get("regatta_cli")
    VENDOR = cli if isinstance(cli, str) and cli not in ("", "claude-code") else ""
    # cwd first: after EnterWorktree the session runs in the worktree, while
    # CLAUDE_PROJECT_DIR may still name the checkout it was started from.
    ROOT = data.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or "."
    event = data.get("hook_event_name")
    session = data.get("session_id") or "unknown"

    if event == "PreToolUse" and data.get("tool_name") == "Bash":
        cmd = QUOTED_RE.sub("''", (data.get("tool_input") or {}).get("command", ""))
        if PUSH_RE.search(cmd) and not (
                SAFE_PUSH_RE.match(cmd) and not PUSH_BYPASS_RE.search(cmd)):
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason":
                    "⛔ An agent may push only its own branch, as one explicit command "
                    "(rule: git-workflow):\n    git push -u origin claude/<host>/<yyyy-mm-dd>-<topic>\n"
                    "— in a sibling repo: git -C <its worktree> push -u origin claude/… "
                    "(a `cd … &&` in front is refused: the command must start with git).\n"
                    "(the checkpoint hook already pushes it every turn; this is rarely needed) "
                    "`main` is the owner's: open a PR with `gh pr create --base main` and stop "
                    "there. A bare `git push` is denied even on a claude/* branch — what it "
                    "sends depends on push.default and the upstream, which this hook cannot "
                    "see. Don't retry, and don't reach for --no-verify or -c hooksPath: "
                    "those defeat the pre-push hook and are denied on sight."}},
                             ensure_ascii=False))
            return
        if PUSH_RE.search(cmd):
            # The allowed shape, but never from a worktree whose branch moved: origin holds the
            # target's newer tip, and a --force-with-lease from the old tab would rewind it.
            c = re.search(r"-C\s+(\S+)", cmd)
            try:
                pdir = resolve_dir(ROOT, c.group(1)) if c else Path(ROOT)
                went = common.moved(Target(pdir).state) if pdir else None
            except Exception:
                went = None
            if went:
                print(json.dumps(deny(common.moved_reason(went)), ensure_ascii=False))
                return
        if TRACK_RE.search(cmd) and not NO_TRACK_RE.search(cmd):
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason":
                    "⛔ A branch started from (or pointed at) origin/… tracks it, and VS Code's "
                    "Sync pushes a branch onto whatever it tracks — one click moved household's "
                    "main that way on 2026-09-24, because the pre-push guard trusts the button "
                    "as the owner's (rule: git-workflow). Start from local main, as the recipe does:\n"
                    "    git worktree add .claude/worktrees/<topic> -b "
                    f"{branch_recipe()} {MAIN}\n"
                    "or add --no-track. Never set a branch's upstream to origin/main; the "
                    "hook's own push -u sets it to the branch's twin."}},
                             ensure_ascii=False))
            return

        # the raw text: QUOTED_RE blanked `bash -c '<script>'`, whose script simple_commands parses as its own
        hit = VENDOR and unattended_mark() and vendor_denied((data.get("tool_input") or {}).get("command", ""))
        if hit:
            print(json.dumps(deny(
                f"⛔ Unattended {VENDOR} run ({unattended_mark()}): `{hit}` is on the list a dispatched Claude run "
                "is denied at its launch (dispatch's `denied=(…)`: pushes, GitHub, ssh, deploys, merging or "
                f"readying a pull request, the queue's verbs), and this hook is the same rule in {VENDOR}'s own "
                "socket (docs/codex-agy-gaps-2026-10-29.md, D2-A). Commit on the claude/* branch and stop there; "
                "the checkpoint pushes and /finish lands it."), ensure_ascii=False))
            return
        if CONFIRMED_RE.search(cmd):
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason":
                    "⛔ `pickup archive … --confirmed` records \"Probably launched, confirmed by the owner\" — it is "
                    "the owner's to type, never an agent's (coding-on-workflow D6). Give the owner the "
                    "`pickup review <branch>` line instead, and stop there."}}, ensure_ascii=False))
            return

    if event == "PreToolUse":
        refused = adoption_target(data.get("tool_name"), data.get("tool_input") or {}, ROOT)
        if refused is not None:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason":
                    "\u26d4 " + str(refused) + " must never join the worktree workflow: "
                    + no_workflow_reason(refused) + "\nIts .claude/no-workflow says so, and "
                    "this would have created .claude/workflow.json there. Adopting the project "
                    "you meant? Give /new-project its absolute path, never `.` \u2014 `.` is "
                    "whichever session happens to be open, which is how this repo got adopted "
                    "by accident on 2026-09-17. To lift the refusal, delete the marker by hand "
                    "and say why in the commit."}}, ensure_ascii=False))
            return
        if data.get("tool_name") == "Bash":
            # Judged per checkout the command acts in, whatever the session's own cwd is \u2014
            # a session in a plain folder or a no-workflow repo still gets gated when it
            # writes into an opted-in sibling (D4), and D1 holds everywhere.
            out = handle_bash((data.get("tool_input") or {}).get("command", ""), ROOT, session)
            if out:
                print(json.dumps(out, ensure_ascii=False))
            return
        if data.get("tool_name") in WRITE_TOOLS:
            ti = data.get("tool_input") or {}
            if in_force(ti.get("file_path") or ti.get("notebook_path")):
                print(json.dumps(deny(force_reason(ti.get("file_path") or ti.get("notebook_path"))), ensure_ascii=False))
                return
            if unattended_mark() and in_records(ti.get("file_path") or ti.get("notebook_path")):
                print(json.dumps(deny(record_reason(ti.get("file_path") or ti.get("notebook_path"))), ensure_ascii=False))
                return
            try:
                out = handle_file_write(data.get("tool_input") or {}, ROOT, session)
            except Exception:
                out = SAME_CHECKOUT  # a failure here falls back to the judgement before D2, never looser
            if out is not SAME_CHECKOUT:
                if out:
                    print(json.dumps(out, ensure_ascii=False))
                return

    top = git("rev-parse", "--show-toplevel", check=False)
    if top.returncode != 0 or not top.stdout.strip():
        return  # not a git repo: nothing to checkpoint, nothing to say
    toplevel = Path(top.stdout.strip()).resolve()
    if event == "SessionEnd":  # whatever this repo's opt-in: locks taken elsewhere go with the session
        gd = git("rev-parse", "--absolute-git-dir", check=False).stdout.strip()
        if gd:
            release_claimed(Path(gd) / "claude", session)
    workflow = load_workflow(toplevel)
    if workflow is None:
        return  # this project never opted in
    MAIN = workflow.get("main") or "main"
    state = Path(git("rev-parse", "--absolute-git-dir").stdout.strip()) / "claude"  # per worktree
    state.mkdir(parents=True, exist_ok=True)
    if already_handled(state, event, raw):
        return
    branch = git("symbolic-ref", "--quiet", "--short", "HEAD", check=False).stdout.strip()
    owner = read_owner(state)
    locked_out = held_by_other(owner, session)
    merging = (state.parent / "MERGE_HEAD").exists()  # a real (non-ff) merge in progress
    went = common.moved(state)  # the /move marker: this branch goes on elsewhere

    if event == "PreToolUse":  # Edit/Write/NotebookEdit into this checkout (Bash was handled above)
        if not is_write(data.get("tool_name"), data.get("tool_input") or {}, toplevel, branch, merging):
            return
        ti = data.get("tool_input") or {}
        if branch == MAIN and in_place(workflow, toplevel, ti.get("file_path") or ti.get("notebook_path")):
            return  # a record written in place (the dream's dreams/, the log): no lock, no checkpoint
        if went:
            print(json.dumps(deny(common.moved_reason(went, branch)), ensure_ascii=False))
        elif locked_out:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason": lock_reason(owner, toplevel, state=state)}}, ensure_ascii=False))
        elif branch == MAIN:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason": worktree_required_reason(toplevel, workflow=workflow)}},
                             ensure_ascii=False))
        elif not branch and detached_primary(toplevel):
            print(json.dumps(deny(pinned_reason(toplevel, MAIN, workflow=workflow)), ensure_ascii=False))
        else:
            taking_over = owner and owner.get("session") != session
            branch, note = adopt_spawned(toplevel, branch, MAIN, quiet=True)
            claim(state, session, branch)
            notes = ([note] if note else []) + (
                [f"🔒 took over this checkout from {took_from(owner)}"] if taking_over else [])
            if notes:
                print(json.dumps({"systemMessage": " · ".join(notes)}, ensure_ascii=False))
        return

    if event == "SessionEnd":
        if owner and owner.get("session") == session:
            (state / "owner.json").unlink(missing_ok=True)
        if not locked_out and not went and not any((state.parent / m).exists() for m in BUSY_MARKERS) \
                and not (state / "finishing").exists():
            publish(state, branch, session, force=True)  # whatever the last turn left unpushed
            if branch.startswith("claude/"):
                # The launcher's second trigger (D8): a minute on, this worktree is judged once
                # more and, armed, started. SessionEnd cannot wait, hence the detached child.
                try:
                    spawn_autofinish("--worktree", str(toplevel), "--after", str(AUTOFINISH_AFTER), "--log")
                except Exception:
                    pass  # the sweep is the other trigger; a session end never fails over this
        return

    gitdir = state.parent
    prompts_path = state / "prompts.json"
    scratch = data.get("scratchpad_dir")
    summary_path = Path(scratch) / SUMMARY_NAME if scratch else None
    finishing = state / "finishing"
    if finishing.exists() and time.time() - finishing.stat().st_mtime > FINISHING_TTL:
        finishing.unlink(missing_ok=True)  # abandoned /finish — must not mute the next session
        finishing_stale = True
    else:
        finishing_stale = False
    busy = any((gitdir / m).exists() for m in BUSY_MARKERS) or finishing.exists()
    dirty = bool(git("status", "--porcelain").stdout.strip())
    adopted = None
    if dirty and not busy and not locked_out and not went and event == "Stop":  # a write no PreToolUse saw (`echo >`)
        branch, adopted = adopt_spawned(toplevel, branch, MAIN)
    can_commit = branch.startswith("claude/") and not busy and dirty and not locked_out and not went
    mine = owner and owner.get("session") == session
    if went and mine:
        # The branch goes on elsewhere: this session can write nothing here, so it holds no
        # lock either — or the session that brings the work back is locked out for 2 h.
        (state / "owner.json").unlink(missing_ok=True)
        mine = False

    queue = load_queue(prompts_path)
    now = time.time()
    ours = lambda e: e["session"] in (session, None)  # None: queued before sessions were tracked
    theirs = [e for e in queue if not ours(e) and now - e.get("ts", now) < QUEUE_TTL]
    prompts = [e["prompt"] for e in queue if ours(e)]
    queue = [e for e in queue if ours(e)] + theirs

    notes, context, summary_reminder, worktree_note = [], None, None, None
    block = None  # Stop: why the reply must carry a doc's GitHub link (answer_link_block)
    if event == "UserPromptSubmit":
        if not locked_out and not busy and not went:
            # The wip(no-summary) fallback's own notice arrives in the Stop
            # response, which Claude never sees — only the user's UI shows it.
            # So the miss is otherwise invisible to Claude until the next
            # /finish. Surface it via `context` (fed to Claude), not `notes`
            # (user-facing only). Keeps reminding on every turn HEAD stays a
            # wip(no-summary)/between-turns commit — which includes a run of
            # discussion-only turns, since those commit nothing and don't move
            # HEAD — and stops the moment any real commit is made, wip or not.
            last_subject = git("log", "-1", "--format=%s", check=False).stdout.strip()
            if last_subject.startswith("wip(no-summary):") or last_subject.startswith("wip: changes between turns"):
                summary_reminder = (f"No {SUMMARY_NAME} last turn. A one-liner is enough "
                                    "(\"Area: what changed\") — skip it entirely for a small "
                                    "or trivial change; wip(no-summary) costs nothing, /finish "
                                    "reads diffs.")
        # autofinish's run on this branch, once per phase: under way (its runner holds the lock,
        # so this panel is locked out and is told why, not offered a worktree), then its outcome
        try:
            af_running = bool(common.autofinish_running(state, owner))
            af_note, af_context = autofinish_prompt_note(state, owner, session, branch)
        except Exception as exc:  # a note is never worth the prompt
            af_running, af_note, af_context = False, f"⚠ autofinish note failed: {exc}", None
        if went:  # every prompt, so a tab still open on the old machine says where the work went (R4)
            why = common.moved_reason(went, branch)
            notes.append(why)
            context = why + " Tell the user, and don't work around it: no edits, commits or deploys in this checkout."
        elif locked_out:
            if af_running:
                notes.append(af_note)  # once; the model's context below says it every prompt
            else:
                notes.append(f"🔒 read-only here — session {owner['session'][:8]} owns this checkout "
                             f"({owner.get('branch')}). Writes will be refused; use a worktree.")
            context = lock_reason(owner, toplevel, state=state)
        elif mine and owner.get("branch") != branch:
            notes.append(f"⚠ branch changed under this session: it was on {owner.get('branch')}, "
                         f"checkout is now on {branch or 'a detached HEAD'}")
            context = (f"The checked-out branch changed between turns: was {owner.get('branch')}, "
                       f"now {branch}. Something outside this session switched it. Confirm with "
                       f"the user which branch this work belongs on before writing anything.")
        if branch.startswith("claude/") and not locked_out and not went:
            spent = landed(state, branch, ask=False)  # the kept yes only: no lookup per prompt
            if spent:
                why = spent_context(branch, spent)
                context = f"{context} {why}" if context else why
        if af_note and not (locked_out and af_running) and not went:  # the outcome, once
            notes.append(af_note)
            if af_context:
                context = f"{context} {af_context}" if context else af_context
        # a fresh spawned worktree joins the workflow at its first write: no false nag before it
        if off_workflow(branch, busy) and not locked_out and not adoptable(toplevel, branch, MAIN):
            notes.append(f"⚠ on branch '{branch}' — not {MAIN} or claude/*, so checkpoints are OFF "
                         f"here. Switch to {MAIN}, or a claude/* branch in a worktree, to go on, "
                         f"or confirm with the user this is deliberate.")
        if not locked_out and branch == MAIN:
            records = in_place_entries(workflow)
            if records:  # the dream and the vault's own sessions write these on main, by design
                worktree_note = (f"This checkout is on {MAIN}. Its in-place records "
                                 f"({', '.join(records)}) are written here directly and "
                                 f"committed by the hooks or `knowledge-commit "
                                 f"{toplevel.name} -m …`. Anything else needs a worktree first "
                                 f"(rule: git-workflow): git worktree add "
                                 f".claude/worktrees/<topic> -b {branch_recipe()} {MAIN}, then "
                                 f"EnterWorktree. Other writes here are denied.")
            else:
                worktree_note = (f"This checkout is on {MAIN}, which stays untouched — create a "
                                 f"worktree before editing anything this turn (rule: git-workflow): "
                                 f"git worktree add .claude/worktrees/<topic> -b "
                                 f"{branch_recipe()} {MAIN}, then EnterWorktree. Writes "
                                 f"here are denied.")
        if finishing_stale:
            notes.append("⚠ cleared a stale `finishing` marker left by an abandoned /finish — "
                         "checkpoints were OFF in this checkout and are now back on.")
        elif finishing.exists() and not locked_out:
            notes.append("ℹ `finishing` is set, so checkpoints are OFF — expected mid-/finish. "
                         "If no /finish is running, remove .git/claude/finishing.")
        # Dirty before the turn starts = an interrupted turn or outside edits: commit it under
        # the prompts that preceded it, so it never mixes into the new turn's commit.
        if can_commit:
            note, committed = checkpoint(summary_path, prompts,
                                         "wip: changes between turns (interrupted turn or edits outside Claude)",
                                         claude_made_it=False, session=session)
            notes.append(note)
            if committed:
                queue = theirs
        if mine:
            # Only a prompt the owner typed withdraws a hand-over: a background task finishing arrives
            # here as a <task-notification> "prompt" too, and must not lock the new tab out.
            typed = not (data.get("prompt") or "").lstrip().startswith(("<task-notification", "<agent-message"))
            if owner.get("handover") and typed:
                notes.append("↩ hand-over withdrawn: this session writes here again, so the tab it opened "
                             "would be locked out — close that one")
            claim(state, session, owner.get("branch"), withdraw=typed)  # heartbeat; the branch moves only at Stop
        # a locked-out panel woken by another session (autofinish-run notify's SendMessage) did no
        # work here: queued, it would be quoted as a `Prompt:` in the next commit, as if the owner typed it
        if not (locked_out and (data.get("prompt") or "").lstrip().startswith("<agent-message")):
            save_queue(prompts_path, queue + [{"session": session, "ts": now,
                                               "prompt": clean(data.get("prompt", ""))}])
        if not locked_out:
            try:  # housekeeping only — never let it cost the prompt that was just queued
                common_dir = (Path(ROOT) / git("rev-parse", "--git-common-dir").stdout.strip()).resolve()
                swept = sweep_raw_branches(common_dir)
                if swept:
                    notes.append("🧹 swept merged -raw backups nothing held: " + ", ".join(swept))
            except Exception as exc:
                notes.append(f"⚠ -raw sweep failed: {exc}")
    elif event == "Stop":
        committed = False
        notes.append(adopted)
        if not locked_out and held_by_other(read_owner(state), session):
            # a hand-over's tab took the lock since this hook read it: its checkout now, so no
            # commit here would sweep that tab's first edits in (review 2026-10-05)
            owner = read_owner(state)
            locked_out, can_commit, mine = True, False, False
        if branch == MAIN and dirty and not locked_out and gated_dirt(workflow):
            # Should be unreachable now — PreToolUse denies writes on main so
            # every session moves to a worktree before touching a file. If
            # this still fires, something slipped past that block (Bash
            # detection is best-effort). Surface it loudly rather than
            # switching THIS checkout off main to save it, which is exactly
            # the behaviour the user asked this hook to stop doing.
            notes.append("⚠ main has uncommitted changes despite the write "
                         "block — something slipped past PreToolUse (likely "
                         "a Bash command). NOT auto-branched: this checkout "
                         "stays on main. Move the changes to a worktree by "
                         "hand and check what got past the block.")
        if can_commit:
            last = clean(prompts[-1]) if prompts else ""
            first_line = last.splitlines()[0][:60] if last else "turn checkpoint"
            note, committed = checkpoint(summary_path, prompts, f"wip(no-summary): {first_line}",
                                         claude_made_it=True, session=session,
                                         response=data.get("last_assistant_message") or "")
            notes.append(note)
            if committed:
                queue = theirs
                mine = True  # committing is writing: hold the lock
        elif went and dirty:
            notes.append(f"⚠ files changed here are NOT checkpointed — {common.moved_line(went)}; "
                         f"carry them over by hand or drop them")
        elif not branch.startswith("claude/"):
            queue = theirs  # nothing checkpoints off-branch; don't hoard
            if dirty and not locked_out and off_workflow(branch, busy):
                notes.append(f"⚠ changes made but NOT checkpointed — branch '{branch}' is neither "
                             f"main nor claude/*. Switch to main or a claude/* branch to go on.")
        if mine:
            claim(state, session, branch)  # the turn's own branch changes are legitimate
        af_declared = af_now = af_live = False
        if branch.startswith("claude/") and not locked_out and not went:
            try:  # the launcher's idle clock, and the reply it judges (autofinish section above)
                write_last_reply(state, data.get("last_assistant_message") or "")
                af_declared, af_now = autofinish_due(state, data)
                # rule L: this turn's own commit says it deployed — push now and let the launcher judge,
                # rather than wait for the push throttle and the next sweep (review at /finish, 2026-10-14)
                af_live = bool(committed) and bool(common.deployed(
                    git("log", "-1", "--format=%B", check=False).stdout))
            except Exception as exc:
                notes.append(f"⚠ autofinish's last-reply not written: {exc}")
        if not busy and not locked_out and not went:
            # Force: a change to an answered doc in ANY unpushed commit — the owner's tab edits arrive as the
            # `wip: changes between turns` commit at the prompt, which never pushes itself.
            # Block: only when this turn's own commit asks something (a D-item line added).
            # Only on a turn with fresh commits, so a failing origin is not retried every turn.
            # Autofinish forces it too: the launcher starts only a branch origin holds.
            # Fresh is a HEAD no push was offered yet (offered()): this turn's own commit, the tab
            # edits committed at the prompt, or a commit the session made itself (`bin/ask relay`,
            # a plain `git commit`), where the hook commits nothing — light-gate-b1's D5, committed
            # 22 s after the last push, sat unpushed while its run idled and the owner was handed a page
            # without it (2026-10-19, not the first that week). The wip subject no longer counts:
            # it kept a failing origin retried on every Stop while that commit stayed HEAD (review
            # at /finish, 2026-10-19).
            fresh = offered(state) != git("rev-parse", "HEAD", check=False).stdout.strip()
            unpushed = ({} if not branch.startswith("claude/") or not fresh else
                        answer_docs(f"{branch}@{{u}}..HEAD") if has_upstream(branch) else
                        answer_docs("HEAD") if committed else {})
            notes.append(publish(state, branch, session, force=bool(unpushed) or af_declared or af_now or af_live))
            _, sheep_note = sheep_pages(branch, list(unpushed))  # its pin is what the line's page is checked against
            notes.append(sheep_note)
            asked = answer_docs("HEAD") if committed and unpushed else {}
            block = answer_link_block(branch, [d for d, asks in asked.items() if asks], data)
            try:  # a check, not the checkpoint: never let it cost the Stop's notes and queue
                block = block or stale_link_block(branch, data, lambda: publish(state, branch, session, force=True))
            except Exception as exc:
                notes.append(f"⚠ link check failed: {exc}")
            if not block and (af_declared or af_now or af_live):  # one block a Stop; the next comes back here
                try:
                    block, af_note = autofinish_at_stop(state, data, session, toplevel, af_declared)
                    notes.append(af_note)
                except Exception as exc:
                    notes.append(f"⚠ autofinish check failed: {exc}")
        if branch.startswith("claude/") and not locked_out and not went:
            try:  # a name is a nicety: never let it cost the checkpoint
                titled = title_session(state, branch, data, session,  # no main checkout: no sure name
                                       lambda: (main_checkout() or Path()).name or None)
                if titled:
                    notes.append(f"🏷 named this session “{titled}”")
            except Exception as exc:
                notes.append(f"⚠ session title failed: {exc}")
        save_queue(prompts_path, queue)
        if summary_path and (committed or not dirty):
            # A summary written for a turn that changed nothing must not attach to the next
            # commit. But if there WAS something to commit and it's simply blocked (busy,
            # locked out, off-workflow branch), keep the summary for whenever it unblocks —
            # deleting it here throws away work already done and silently downgrades the
            # eventual commit to wip(no-summary).
            summary_path.unlink(missing_ok=True)

    out = {}
    notes = [n for n in notes if n]
    if notes:
        out["systemMessage"] = " · ".join(notes)
    if block:
        out["decision"], out["reason"] = "block", block
    for extra in (summary_reminder, worktree_note):
        if extra:
            context = f"{context} {extra}" if context else extra
    if context:
        out["hookSpecificOutput"] = {"hookEventName": event, "additionalContext": context}
    if out:
        # JSON, not plain text: UserPromptSubmit feeds plain stdout to Claude as context.
        print(json.dumps(out, ensure_ascii=False))


PUSH_ANY_RE = re.compile(GIT_PREFIX + r"push\b")  # a push anywhere in the text, quoted or not


def in_git_tree(path, cwd):
    """True when `path` (relative to `cwd`) lies inside a git work tree: a `.git` in it or above.
    The file need not exist yet. Stdlib only, no git call — core_missing() trusts nothing else."""
    # resolve(): ~/.claude/rules and the like are links into a checkout (non-strict on 3.9)
    p = Path(cwd or ".", os.path.expanduser(path or "")).resolve()
    return any((d / ".git").exists() for d in (p, *p.parents))


def core_missing(exc):
    """Run as the hook with no core: one line to stderr (C4), and on PreToolUse a deny where the
    hook would have judged a write — fails closed, since an allow is what dying looks like. Denied:
    an Edit, Write or NotebookEdit inside any git work tree, and Bash with a D1 deletion, a git verb
    that writes (FLOOR_RE) or a push, inline program code, or an unattended consent flag, read from
    the raw text as fallback_bash() does — no lock, no opt-in, no checkout to read without the
    core, so every repo is treated as opted in. Everything else (reads, `bootstrap.sh --config`, a
    clone, a `pull --ff-only` of a stale core) passes, so the fix can be run from the session
    itself; for that, LIVEISH_RE is left out (it would catch `bootstrap.sh`)."""
    print(f"checkpoint: {CORE_MISSING} ({exc})", file=sys.stderr)
    try:
        data = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        return
    if not isinstance(data, dict) or data.get("hook_event_name") != "PreToolUse":
        return
    tool, ti = data.get("tool_name"), data.get("tool_input") or {}
    cwd = data.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or "."
    if tool == "Bash":
        cmd = str(ti.get("command") or "")
        verbs = [m.group(1) for m in FLOOR_RE.finditer(cmd)]
        try:
            inline = runs_inline_program(cmd)
        except Exception:
            inline = None
        hit = (deletion_in(cmd) or RAW_DELETE_RE.search(cmd) or "worktree remove" in cmd
               or any(v != "pull" for v in verbs) or ("pull" in verbs and not PULL_FF_RE.search(cmd))
               or PUSH_ANY_RE.search(cmd) or inline
               or (unattended_mark() and CONSENT_FLAG_RE.search(cmd)))
    elif tool in WRITE_TOOLS:
        hit = in_git_tree(ti.get("file_path") or ti.get("notebook_path"), cwd)
    else:
        hit = False
    if hit:
        print(json.dumps(deny(f"⛔ {CORE_MISSING}. The checkpoint hook cannot judge writes or pushes "
                              f"without it, so it refuses them ({exc})."), ensure_ascii=False))


if __name__ == "__main__":
    if core_error is not None:
        try:
            core_missing(core_error)
        except Exception as exc:  # a deny path that crashed: still never a non-zero exit
            print(f"checkpoint: {CORE_MISSING} ({exc})", file=sys.stderr)
        sys.exit(0)
    try:
        main()
    except Exception as exc:  # never break a turn over a checkpoint
        print(json.dumps({"systemMessage": f"⚠ checkpoint hook failed: {exc}"}))
    sys.exit(0)
