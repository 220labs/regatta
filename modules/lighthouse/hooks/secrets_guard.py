#!/usr/bin/env python3
"""secrets_guard — Drive's _secrets folder is closed to agents: no reads, no writes; links allowed.

Since 2026-10-18 the vaults' `_contacts` the same way (docs/work-contacts-2026-10-18.md): work
contact books, third parties' phone numbers, read by the messaging tool in its own process.

The owner, 2026-09-25: read-only at first, then "agents don't need reads in secrets either. They
are passed via .env to whichever apps need them … But agents should be able to symlink to them."

A PreToolUse hook on Read|Grep|Glob and Edit|Write|NotebookEdit|Bash, installed user-wide (the
overlay's `bootstrap.sh --hooks`, or this plugin's hooks.json). The folder holds every repo's
`.env`, and a repo's `.env` is a symlink into it (the home repo's docs/secrets-2026-09-24.md).
Apps read their values themselves through that link — `python3 scripts/ha.py …` never names the
file, so it is never stopped here. Values go in by the owner's hand.

Which folders: `_secrets` and `_contacts` in every Google Drive shared drive this Mac mounts (a
shared drive is a vault when it holds one). Their names, for a path the hook cannot resolve (a
shell variable it never sees), are those shared drives' plus the config dir's `lighthouse/vaults`
(one per line), checked only while at least one such folder is mounted: with none mounted the hook
lets everything through, as the files are then not on this Mac (B9 review). No core is
imported: the guard runs where the regatta core is missing too. The owner's name in the refusals
is the config dir's `regatta/owner` (else "the owner"). The session-start hook's `secrets check --fix` (empty `KEY=` lines) runs as
a hook, not a tool call, so nothing here reaches it.

File tools: Read, Edit, Write, NotebookEdit on a path that resolves into the folder — through
symlinks, so a repo's `.env` counts — and Grep on it or on a folder that holds it. Glob lists
names only and is not matched for these folders (the fence below matches it).

Bash, read from the command text as checkpoint.py's push guard is — it stops accidents, not
intent. Refused: any word, redirection (`<`, `>`), `$(…)` / backtick body, `--opt=value` or
interpreter code (`python3 -c`, `sh -c`, `eval`, a heredoc fed to python / node / a shell)
naming a path that resolves into the folder, with `cd` followed along the command; a
recursive reader or remover (`grep -r`, `rg`, `tar`, `cp -R`, `rm -rf`, `find -exec`) over a
folder that holds it; and `bin/secrets … --fix`. Allowed: `ln -s` (linking to a secret is how
a repo gets its `.env`), `ls`, `stat`, `readlink`, `realpath`, `test` / `[`, `echo`, `printf`,
`git` (it stores a link as a link), `rm` / `mv` / `unlink` of a repo's `.env` link itself, and
a heredoc that is only data (`cat > notes.md <<EOF`, `git commit -F - <<EOF`). Not seen: a
path a program builds at run time or holds in a shell variable the hook never sees (only
`<vault>/_secrets` or `<vault>/_contacts` spelled out is caught then), and a recursive read that follows links
from a repo (`grep -R`, `rg -L`) — plain `grep -r` and rg do not follow them. The real wall
would be the OS (a separate user for agents); there is none today.

Also, since 2026-09-29 (docs/record/machine-settings-2026-09-29.md, D4): Edit, Write, MultiEdit and
NotebookEdit on the live settings.json (the default config dir's, or $CLAUDE_CONFIG_DIR's) are refused, naming
`bin/claude-settings declare` — a change typed into one Mac's file reaches neither git nor the
other Mac. Bash edits pass (`bootstrap.sh --hooks` and `claude-settings apply` are Bash), as
everything here: it stops accidents, not intent.

Also, since 2026-10-16: the Bash commands that take the private-repo gate off sessionpipe or ship
sessions past it (keel's bin/sheep header, R1). The tools are the config dir's `lighthouse/gated-tools`:
its first line the session-sync tool (`sessionpipe` without the key), its second the front end that
runs it (none without one) — below, "the front end". An install or update rewrites every entry ungated,
a bare install backfills 30 days of the private repos' sessions, `replay` re-sends the outbox
(private sessions in it included), `sink add` adds a second sink or tier 3; nothing mechanical
stopped an agent from typing one. The owner runs them in their own terminal, then `sheep gate`. The rule is
fail-closed, not a parse of the command line (the first, positional one missed a dozen shapes
in review): every string in the command is searched — each simple command's words, and, split
again, every quoted word (`ssh host '…'`, `bash -c "…"`, `eval "…"`; `\n` and `\t` in it split
too, as printf's output fed to sh would), every `$(…)` and backtick body outside single quotes
(an apostrophe inside "…" quotes nothing), every `<(…)` / `>(…)`, and every heredoc body — and in
an unquoted heredoc (`<<EOF`, not `<<'EOF'`) the `$(…)` and backticks, whoever reads it. A
`sessionpipe` word (bare, a path ending /sessionpipe, `sessionpipe@…`, a node path into its
package) followed anywhere later in the same simple command by install, update, uninstall,
connect, backfill, replay, `control pair` or `sink add` is denied; so is the front end followed by
`machine on` or `sessions|memory install|backfill|uninstall`. `update` takes no arguments in 0.5.0:
`update off` installs the latest and re-runs install like a bare `update` (cli.js `update()`,
read 2026-10-16). sessionpipe has no help flag (`install --help` installs), so `--help` exempts
only the front end, whose parser honours `-h` anywhere. A simple command that only reads or prints
text may name the words: grep, rg, echo, printf, cat, head, tail, tee, wc, awk, less; sed unless
its script uses GNU's `e` command or `s///e`; git commit / log / show / diff / grep / … (after
`-C`, `-c`, `--git-dir`, `--work-tree`; not with an alias or a `-c` that names a command); gh
unless alias, extension or ssh. So may a script's own arguments and stdin (`python3 bin/memo …`,
`bin/knowledge-commit -m "…"`): a script file's argv is data; `-c` / `-e` code and stdin code
(`python3 -`, a bare `python3`) are searched. Nothing is only reading once anything in the
command is piped (`|`, `|&`) into a shell or into an interpreter reading code from stdin; then
every quoted word is searched as raw text too. Raw text (python, node or perl code) matches only
the verb inside the same string literal as `sessionpipe`, flags allowed between
(`os.system('sessionpipe install')`), or as the next list element (`['sessionpipe', 'install']`) —
not `"sessionpipe" in l and "install" in l`, nor …/sessionpipe/dist/commands/install.js. Not
seen: a command a program builds at run time, or one a script runs from its arguments.

Also, since 2026-10-21 (knowledge-layers S2; the design's D3): the fence. A scope the registry flags
`"confidential": true` is closed to every session whose cwd is outside it — its checkouts and their
worktrees, its transcripts folder, each login's session folder for them (`projects/<slug>/`: the
session transcripts and the memory dir both), the paths the core's scope_paths() names, mirrored here
in the stdlib. Read, Edit, Write, NotebookEdit and Grep as above;
Glob when its path is inside or its pattern descends into one; Bash as above, with three changes for
names, not only contents: `ls` and `stat` are refused, a command after a `cd` or `pushd` into the
scope is, and git is judged by the tree it runs in (`-C`, `--git-dir`, `GIT_DIR=`, the cwd) and the
paths a diff, clone, fetch or `--output=` reads, never by its words, as a grep's pattern is text. A
walker (`grep -r`, rg, ag, ack, find, du, tree, `ls -R`) is judged by the folders it walks — its
arguments that exist, else its cwd, unless it reads a pipe — and refused over one that holds the
scope, counting only the scope's folders this Mac has. A word the shell would expand
(`<projects>/*/memory`) is expanded here and each match below a fenced folder judged; a match that is
the folder's own name only names it (`ls -d <projects>/*`, `for r in <projects>/*/`, as a Glob of the
repos' names), save for a walker or a plain `ls`. A removed worktree's session folder
(`<slug>--claude-worktrees-<topic>`) is fenced too. A session inside the scope reads it all, and every
open scope stays open. The refusal names the scope and the way out, and appends one line to the log
dir's fence.log (the section's own comment says what it holds; a cwd in a scope's paths is `-`).
Not seen: a path a program builds or a script reads by itself (week-digest, a dream's gather) — the
passes bound those (S4), not this hook; brace expansion and zsh's recursive `**`; a differently cased
path on a case-insensitive disk; a glob's matches past the first 2000; chained `-C`; the body of a
`for` loop over the projects folder and `$(echo <path>)` handed to a reader; listers it does not know
(`fd`, `mdfind`); a session folder of a subfolder of a checkout (`<slug>-<sub>`, which a sibling
repo's name would also match).

Also, since 2026-10-26 (lighthouse-ops S1; the sense component's D5-A): the config dir's
`lighthouse/guarded-dirs`, absolute local folders (a leading `~` the home folder) closed the way
`_secrets` is, on every platform and whether or not a Drive is mounted — the desk's token dir on the
yard node first among them. The same tools and shapes as above, with its own refusal; a path behind a
variable (any expansion: `$X`, `${X:-…}`, `$(…)`, a backtick body) is caught when it spells the folder's tail after it (the part below the config dir,
else its last two names); the tail alone, a grep pattern or a doc's mention, passes. An accident guard like the rest: the file stays readable by any process of its user.

Fails open: an error in here lets the call through rather than blocking every tool in every
session. Tests: tests/hooks.sh, "secrets_guard" and "the fence".
"""
import fnmatch
import glob
import itertools
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

CONFIG = os.path.expanduser(os.environ.get("REGATTA_CONFIG") or os.path.join("~", ".config", "regatta"))


def config_lines(name):
    """The config dir's `<name>`: its non-blank lines, or [] (the core's reader, kept here so the
    guard needs no core)."""
    try:
        with open(os.path.join(CONFIG, name), encoding="utf-8-sig") as f:
            return [l.strip() for l in f if l.strip()]
    except (OSError, UnicodeDecodeError):
        return []


OWNER = (config_lines("regatta/owner") or ["the owner"])[0]
TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # this module, for claude-settings' path
REASON = ("⛔ Drive's _secrets folder is closed to agents — no reads, no writes ({owner}, "
          "2026-09-25): {what}. Apps read their values themselves through the repo's .env "
          "link: run the app, don't open the file. Linking to it is fine (`ln -s`), and so are "
          "`ls`, `stat`, `readlink` and `test`. A value goes in by {owner}'s hand: name the key and "
          "the file and ask. The _contacts folder (work contact books, phone numbers) is closed "
          "the same way: the messaging tool that owns the books lists names and sends, and a "
          "number goes in by its own add verb or {owner}'s hand. Don't retry in another shape.")
SETTINGS_REASON = ("⛔ {tool} of the live settings.json is refused: that file is applied from the declared "
                   "settings on every Mac (docs/record/machine-settings-2026-09-29.md). Record the change "
                   "with `{cs} declare [--host <this host>] <key> <json>` "
                   "(or `deny-mcp \"<server>\"`); it is reviewed, launches, and `claude-settings apply` puts it "
                   "here. A key it does not manage (model, theme, env): tell {owner} which and why.")
# The folder's own name, for a path the hook cannot resolve (a shell variable it never sees).
# Not bare `_secrets`: that refused a test fixture's `$SGV/_secrets` on its first day.
# More than one vault since 2026-10-05: one the owner's alone, one shared with a collaborator.
# _contacts (2026-10-18, docs/work-contacts-2026-10-18.md): third parties' phone numbers, read by
# the messaging tool in its own process, never by an agent's tool — a Read would put a colleague's
# number in a transcript, on any login, the employer seats included.
FOLDERS = ("_secrets", "_contacts")
DRIVE_GLOB = os.path.join(os.path.expanduser("~"), "Library", "CloudStorage", "GoogleDrive-*", "Shared drives", "*")


def mounted():
    """The guarded folders on this Mac's Drive: each shared drive's `_secrets` and `_contacts`."""
    return [d for f in FOLDERS for d in glob.glob(os.path.join(DRIVE_GLOB, f))]


VAULTS = sorted(set(config_lines("lighthouse/vaults")) | {os.path.basename(os.path.dirname(d)) for d in mounted()})
LITERAL = re.compile(r"(^|/)(%s)/(%s)(/|$)" % ("|".join(map(re.escape, VAULTS)), "|".join(FOLDERS))) if VAULTS else None
CANDIDATE = re.compile(r"[^\s'\"()\[\]{},;=<>|&`]*(?:\.env|_secrets|_contacts)[^\s'\"()\[\]{},;=<>|&`]*")
SUBST = re.compile(r"\$\(([^()]*)\)|`([^`]*)`")
# A heredoc's opener: `<<EOF`, `<<-EOF`, `<<'EOF'`, `<<"END-DOC"`, `<<\EOF`, `<<EOF.md`. Groups:
# 1 the dash, 2 a quote and 3 the quoted delimiter, 4 a backslash and 5 the bare one.
HEREDOC = re.compile(r"(?<!<)<<(?!<)(-?)[ \t]*(?:(['\"])([^'\"\s]+)\2|(\\?)([A-Za-z_][A-Za-z0-9_.-]*))")
WRAPPERS = {"sudo", "command", "env", "nohup", "time", "exec", "nice", "xargs"}
# Never open a file's content: metadata, printing a word, and git (it stores a link as a link).
HARMLESS = {"ls", "stat", "readlink", "realpath", "test", "[", "echo", "printf", "git"}
LINK_ITSELF = {"rm", "unlink", "rmdir", "mv"}
RECURSIVE = {"grep", "egrep", "fgrep", "rg", "ag", "ack", "tar", "zip", "rsync", "cp", "ditto",
             "scp", "rm", "mv", "chmod", "chown"}
INTERPRETER = re.compile(r"^(python[0-9.]*|node|deno|bun|ruby|perl|php|osascript)$")
SHELL = {"sh", "bash", "zsh"}
# sessionpipe's verbs that ungate its hooks or ship past the gate, and the front end's that run them
# (module docstring, 2026-10-16). `control pair` is `connect`'s second half; `memory install` moves
# the hooks to sessionpipe as `sessions install` does.
GATED = config_lines("lighthouse/gated-tools")
DAEMON = GATED[0] if GATED else "sessionpipe"   # the session-sync tool
FRONT = GATED[1] if len(GATED) > 1 else None     # the front end that runs it, if any
SESSIONPIPE_VERBS = {("install",), ("update",), ("uninstall",), ("connect",), ("backfill",), ("replay",),
                     ("control", "pair"), ("sink", "add")}
FRONT_VERBS = {("machine", "on")} | {(a, b) for a in ("sessions", "memory") for b in ("install", "backfill", "uninstall")}
# Words in front of a simple command's own command word.
KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{", "}", "time", "case"}
# Command words whose simple command only reads or prints text (sed, git and gh by what they run).
READERS = {"grep", "egrep", "fgrep", "rg", "ag", "ack", "echo", "printf", "cat", "head", "tail", "tee",
           "wc", "awk", "less", "more"}
GIT_READS = {"commit", "log", "show", "diff", "grep", "status", "add", "blame", "tag", "notes"}
# git's options that take the next word as their value, in front of the subcommand.
GIT_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
# A `git -c key=value` that runs something: an alias, a pager, an editor, a helper (case-folded).
GIT_RUNS = re.compile(r"alias\.|pager|editor|sshcommand|hookspath|fsmonitor|textconv|command|helper|program|!")
# gh's subcommands that run local code: aliases (`!…` runs a shell), extensions, ssh.
GH_RUNS = {"alias", "extension", "ext", "ssh"}
# GNU sed's s///e flag and `e` command run a shell; BSD sed has neither. An s command's own text
# is set aside first, then /regex/ addresses, so `s/sessionpipe install/x/` is no `e`.
SED_S = re.compile(r"s([^\w\s\\])(?:\\.|(?!\1).)*\1(?:\\.|(?!\1).)*\1([A-Za-z0-9]*)", re.S)
SED_E = re.compile(r"(?:^|[;\n{}!0-9$,])\s*e(?:[\s;}]|$)")
# Interpreter options that take the next word as their value (python -W/-X, node -r/--require,
# ruby -I/-r), so that word is not taken for the script.
INTERP_VALUE_OPTS = {"-W", "-X", "-Q", "-r", "-I", "--require", "--import", "--loader", "--experimental-loader"}
# Where a command word that is a path is a system tool, not a script whose argv is data.
SYSTEM_DIRS = ("/bin/", "/sbin/", "/usr/", "/opt/homebrew/", "/Library/", "/System/")
# Tools that run their arguments as a command, wherever they are installed.
RUNNERS = {"ssh", "env", "sudo", "su", "xargs", "timeout", "nohup", "watch", "script", "flock", "parallel",
           "caffeinate", "npx", "npm", "pnpm", "yarn", "bunx", "eval", "exec", "nice", "time", "command"}
# Raw-text search for code a shell does not split (python / node heredocs, -c strings, anything
# piped into an interpreter). The verb must sit in the same string literal as the tool, flags
# allowed between (`'sessionpipe --config x install'`), or be the next list element
# (`['sessionpipe', 'install']`), so `"sessionpipe" in l and "install" in l` and
# …/sessionpipe/dist/commands/install.js pass (review S3, 2026-10-16). No exception for
# `update off`: 0.5.0's update ignores its arguments.
_TOOLWORD = r"\b%s(?:@[^\s'\"]*|/(?:dist|bin|lib)/[^\s'\"]*)?"   # %s: re.escape()d
_FLAGS = r"(?:[ \t]+-[^\s'\"]*(?:[ \t]+[^\s'\"-][^\s'\"]*)?)*"
_LIST_FLAGS = r"(?:['\"]\s*,\s*['\"]-[^'\"]*)*"
_NEXT = r"['\"]\s*,\s*['\"]"


def _raw_pattern(tool, verbs):
    """`tool`, then one of `verbs` (each a list of words) in the same literal or the next element."""
    inline = "|".join(r"[ \t]+".join(v) for v in verbs)
    listed = "|".join(_NEXT.join(v) for v in verbs)
    return re.compile(r"%s(?:%s[ \t]+(?:%s)(?![\w-])|%s%s(?:%s)['\"])"
                      % (_TOOLWORD % re.escape(tool), _FLAGS, inline, _LIST_FLAGS, _NEXT, listed))


RAW_SP = _raw_pattern(DAEMON, [["install"], ["update"], ["uninstall"], ["connect"], ["backfill"],
                                      ["replay"], ["control", "pair"], ["sink", "add"]])
RAW_SS = FRONT and _raw_pattern(FRONT, [["machine", "on"]] + [[a, b] for a in ("sessions", "memory")
                                                            for b in ("install", "backfill", "uninstall")])
GATED_RE = re.compile("|".join(re.escape(x) for x in (DAEMON, FRONT) if x))
SESSIONPIPE_REASON = ("⛔ `{what}` takes the private-repo gate off sessionpipe's hooks or ships sessions past it "
                      "(an install or update rewrites every entry ungated; a bare install backfills 30 days, "
                      "the private repos' included; replay re-sends the outbox — keel's bin/sheep header). "
                      "{owner} runs sessionpipe's install, update, uninstall, connect, backfill, replay and sink add, "
                      "and `{front} machine on`, in {owner}'s own terminal, then `{sheep} gate` "
                      "at once. sessionpipe has no help flag (`install --help` installs; `sessionpipe` with no verb "
                      "prints its help), and `update` ignores its arguments (`update off` installs the latest and "
                      "re-runs install). Read-only verbs pass (`sessionpipe status`, `doctor`, `wait`, `control "
                      "status`); `{sheep} check` says where things stand. Only naming it (a "
                      "commit message, PR body, bulletin line)? Pass the text from a file (`git commit -F <file>`, "
                      "`gh pr create --body-file <file>`).")


def secrets_dirs():
    override = os.environ.get("SECRETS_GUARD_DIR")   # the tests
    return [os.path.realpath(d) for d in ([override] if override else mounted())]


# `lighthouse/guarded-dirs` (the docstring): absolute after `~`; a relative line would name a different
# folder from every cwd, so it is dropped rather than guessed
GUARDED = [os.path.realpath(p) for p in (os.path.expanduser(l) for l in config_lines("lighthouse/guarded-dirs"))
           if os.path.isabs(p)]
GUARDED_REASON = ("⛔ {what}: that folder is closed to agents (the config dir's `lighthouse/guarded-dirs`) — a "
                  "credential only its own job reads, the operations desk's token among them ({owner}'s D5-A, "
                  "2026-10-26). Run the job that reads it; a value goes in by {owner}'s hand, over ssh. "
                  "`ls`, `stat` and `test` are fine. Don't retry in another shape.")


def _tail(d):
    """The part of a guarded folder a command behind a variable still spells: below the config dir
    (`lighthouse/secrets`), else its last two names."""
    cfg = os.path.realpath(CONFIG)
    if d.startswith(cfg + os.sep):
        return d[len(cfg) + 1:]
    return os.sep.join(d.split(os.sep)[-2:])


def guarded_rules():
    if not GUARDED:
        return None
    tails = sorted({_tail(d) for d in GUARDED})
    # behind a variable only (`$X/lighthouse/secrets/…`): a bare `lighthouse/secrets` is the key's name
    # in a grep pattern or a doc, which the landing review found refused (a path that resolves is
    # judged by inside() as it is). Any expansion counts as the variable: `${X:-~/…}`, `$(…)` and a
    # backtick body read the file too (the second landing review); the word is judged alone, so an
    # unquoted body with a space reaches here as its last part (`config-dir`/…`), and shlex splits an
    # unquoted `$(…)` at its parentheses, leaving `/lighthouse/secrets/…`: a word that starts with the tail
    literal = re.compile(r"(?:(?:\$(?:\{[^}]*\}|[A-Za-z_][A-Za-z0-9_]*)|[^\s`]*`|[^\s()]*\))/(?:[^\s'\"]*/)?|^/)(%s)(/|$)"
                         % "|".join(map(re.escape, tails)))
    names = sorted({os.path.basename(d) for d in GUARDED})
    candidate = re.compile(r"[^\s'\"()\[\]{},;=<>|&`]*(?:%s)[^\s'\"()\[\]{},;=<>|&`]*" % "|".join(map(re.escape, names)))
    return Rules(GUARDED, literal, candidate, HARMLESS)


class Rules:
    """What one wall refuses: its folders (real paths), the raw-text pattern for a path the hook
    cannot resolve, the token pattern code is judged by, the verbs that never open a file, and —
    the fence only — whether a command after a `cd` into a folder counts as touching it, git
    judged by the tree it runs in and a grep's pattern taken as text."""

    def __init__(self, dirs, literal, candidate, harmless, fence=False):
        self.dirs, self.literal, self.candidate, self.harmless, self.fence = dirs, literal, candidate, harmless, fence
        self.present = [d for d in dirs if os.path.lexists(d)] if fence else dirs


def resolve(path, cwd, follow=True):
    p = os.path.expanduser(os.path.expandvars(path))
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    if follow:
        return os.path.realpath(p)
    return os.path.join(os.path.realpath(os.path.dirname(p)), os.path.basename(p))


def inside(path, cwd, r, follow=True):
    if not path:
        return False
    if r.literal and r.literal.search(path):
        return True
    if r.fence and any(c in path for c in "*?["):   # a word the shell expands: `cat <projects>/*/memory/x.md`
        # a match below a fenced folder; the folder's own name is a name, as glob_reaches() lets a Glob
        # of the repos' names pass (`ls -d <projects>/*`, `for r in <projects>/*/`); a walker counts it (fence_hit)
        for hit in expand(path, cwd):
            if any(x.startswith(d + os.sep) for x in (resolve(hit, cwd, follow),) for d in r.dirs):
                return True
    p = resolve(path, cwd, follow)
    return any(p == d or p.startswith(d + os.sep) for d in r.dirs)


def holds(path, cwd, r):
    """path is a folder one of the rules' folders sits somewhere under. The fence counts only the
    folders this Mac has: a scope's checkout on another Mac leaves `find <projects>` alone here."""
    p = resolve(path, cwd)
    return any(d.startswith(p.rstrip(os.sep) + os.sep) for d in (r.present if r.fence else r.dirs))


def expand(word, cwd):
    """The shell's matches of a word with `*?[` (at most 2000), else the word itself."""
    if not any(c in word for c in "*?["):
        return [word]
    e = os.path.expanduser(os.path.expandvars(word))
    return list(itertools.islice(glob.iglob(e if os.path.isabs(e) else os.path.join(cwd, e)), 2000)) or [word]


def unquoted_newlines_to_semicolons(cmd):
    out, quote, esc = [], None, False
    for ch in cmd:
        if esc:
            esc = False
        elif ch == "\\" and quote != "'":
            esc = True
        elif quote:
            quote = None if ch == quote else quote
        elif ch in "'\"":
            quote = ch
        elif ch == "\n":
            ch = ";"
        out.append(ch)
    return "".join(out)


def segments_with_seps(cmd):
    """[(simple command's words, the separator token before it — '' for the first)]."""
    lex = shlex.shlex(unquoted_newlines_to_semicolons(cmd), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    seg, sep = [], ""
    for tok in lex:
        # `<(` and `>(` open a process substitution: a command of its own (review S2e, 2026-10-16)
        if tok and (set(tok) <= set(";&|()") or (tok.endswith("(") and set(tok) <= set("<>("))):
            if seg:
                yield seg, sep
            seg, sep = [], tok
        else:
            seg.append(tok)
    if seg:
        yield seg, sep


def segments(cmd):
    for seg, _ in segments_with_seps(cmd):
        yield seg


def is_redirect(tok):
    return bool(tok) and set(tok) <= set("<>&0123456789") and bool(set(tok) & set("<>"))


def blank_single_quoted(cmd):
    """cmd with each single-quoted span outside double quotes emptied and each `\\``, `\\$` dropped:
    what is left is where bash runs `$(…)` and backticks. A `'[^']*'` regex took the apostrophe
    in "the owner's `…`" for a quote and hid the backticks (review S2b, 2026-10-16)."""
    out, quote, i = [], None, 0
    while i < len(cmd):
        ch = cmd[i]
        if quote == "'":
            if ch == "'":
                quote = None
                out.append(ch)
            i += 1
            continue
        if ch == "\\":
            nxt = cmd[i + 1:i + 2]
            out.append("_" if nxt in ("`", "$") and nxt else ch + nxt)
            i += 2
            continue
        if quote == '"':
            if ch == '"':
                quote = None
        elif ch in "'\"":
            quote = ch
        out.append(ch)
        i += 1
    return "".join(out)


def split_heredocs(cmd):
    """The command without its heredoc bodies, and [(the line that opens one, its body, whether
    its delimiter is quoted)]: an unquoted one's body still runs `$(…)` and backticks."""
    lines, kept, bodies, i = cmd.split("\n"), [], [], 0
    while i < len(lines):
        line = lines[i]
        kept.append(line)
        i += 1
        for m in HEREDOC.finditer(line):
            delim, body = m.group(3) or m.group(5), []
            while i < len(lines) and (lines[i].lstrip("\t") if m.group(1) else lines[i]) != delim:
                body.append(lines[i])
                i += 1
            i += 1
            bodies.append((line, "\n".join(body), bool(m.group(2) or m.group(4))))
    return "\n".join(kept), bodies


def verb_of(words):
    while words and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]) or words[0] in WRAPPERS):
        words = words[1:]
    return os.path.basename(words[0]) if words else ""


def code_hit(verb, code, cwd, r, depth):
    """A heredoc body or `-c` string: shell code is judged as a command, other code by the
    paths it names."""
    if verb in SHELL:
        return bash_hit(code, cwd, r, depth + 1) if depth < 3 else None
    for c in r.candidate.findall(code):
        if inside(c, cwd, r):
            return f"`{verb}` code that names {c}"
    return None


GREPS = {"grep", "egrep", "fgrep", "rg", "ag", "ack"}
# git's options that name the tree it runs in: the fence judges git by that tree, not its words,
# so a commit message or a log grep that names a fenced path passes.
GIT_TREE_OPTS = ("-C", "--git-dir", "--work-tree")


# A grep option that carries the pattern, so the first word is a file: `-e x`, `-ex`, `-rnex`,
# `--regexp=x`, `-f list`; and rg's that take none at all (`rg --files <dir>` lists a tree).
GREP_PATTERN_OPT = re.compile(r"^(-[A-Za-z0-9]*[ef]|--regexp(=|$)|--file(=|$))")
GREP_NO_PATTERN = {"--files", "--type-list"}
# The greps that recurse with no -r, and read the cwd when given no path.
WALKS_BY_DEFAULT = {"rg", "ag", "ack"}
# Walkers that walk the cwd when handed no path (find on macOS needs one).
CWD_WALKERS = {"grep", "egrep", "fgrep", "ls", "du", "tree"} | WALKS_BY_DEFAULT
# Copiers walk their sources, never their target (`cp x <projects>/` copies one file in).
COPIERS = {"cp", "ditto", "rsync", "scp"}
RECURSE_FLAG = re.compile(r"^(-[A-Za-z0-9]*[rR]|--recursive$|--dereference-recursive$|--directories=recurse$)")
# Options whose value is the next word, not a path: rg's and grep's globs, types, counts, context.
WALK_VALUE_OPTS = {"-g", "--glob", "--iglob", "-t", "-T", "--type", "--type-not", "--include", "--exclude",
                   "--exclude-dir", "-f", "--file", "--ignore-file", "-m", "--max-count", "-A", "-B", "-C",
                   "-e", "--regexp", "--max-depth", "-d"}


def fence_walks(verb, opts):
    """The command walks a tree (so a folder that holds the scope counts as touching it)."""
    if verb in ("grep", "egrep", "fgrep", "rm", "chmod", "chown"):
        return any(RECURSE_FLAG.match(o) for o in opts)
    if verb == "ls":
        return any(re.match(r"^(-[A-Za-z0-9]*R|--recursive$)", o) for o in opts)
    if verb == "cp":
        return any(re.match(r"^(-[A-Za-z0-9]*[rRa]|--recursive$|--archive$)", o) for o in opts)
    return verb in {"find", "du", "tree", "tar", "zip", "ditto", "rsync", "scp"}   # rg, ag, ack: unless they read a pipe


def walk_paths(verb, rest):
    """The words a walker walks: find's before its expression, else every word that is not an
    option or an option's value."""
    if verb == "find":
        out = []
        for w in rest:
            if w.startswith(("-", "(", "!")) and w not in ("-H", "-L", "-P"):
                break
            if not w.startswith("-"):
                out.append(w)
        return out
    out, skip = [], False
    for w in rest:
        if skip:
            skip = False
        elif w in WALK_VALUE_OPTS:
            skip = True
        elif not w.startswith("-"):
            out.append(w)
    return out


def _find_depth(rest):
    """find's -maxdepth, or None."""
    for i, w in enumerate(rest[:-1]):
        if w == "-maxdepth" and rest[i + 1].isdigit():
            return int(rest[i + 1])
    return None


# git's subcommands that read a path or another repository named in their arguments: a diff goes
# --no-index by itself on a path outside the tree; clone, fetch and pull read the repo they name.
GIT_READS_PATHS = {"diff", "clone", "fetch", "pull", "ls-remote", "archive", "hash-object"}
# What a walker's help, version or list run prints: no tree.
NO_WALK = {"--version", "-V", "-h", "--help", "--type-list"}


def fence_hit(verb, rest, args, cwd, r, piped=False):
    """The fence's own reading of one simple command, or (None, args) to go on with: git by the tree
    it runs in and the paths it reads, any other verb by the cwd a `cd` left it in, a grep's first
    word as its pattern, and a walker by the folders it walks — its arguments that exist, else the
    cwd, unless it reads a pipe (review S2, 2026-10-22)."""
    if verb == "git":
        trees = [rest[i + 1] for i, w in enumerate(rest[:-1]) if w in GIT_TREE_OPTS]
        trees += [w.split("=", 1)[1] for w in rest if w.startswith(("--git-dir=", "--work-tree=", "--output="))]
        if GIT_READS_PATHS & set(args[:1] + [a for a in args[:3] if a in GIT_READS_PATHS]):
            trees += [a for a in args[1:] if a not in GIT_READS_PATHS]
        hit = next((t for t in trees for m in expand(t, cwd) if inside(m, cwd, r)), None) or (cwd if inside(cwd, cwd, r) else None)
        return (f"`git` in {hit}" if hit else ""), args
    if verb not in r.harmless and inside(cwd, cwd, r):
        return f"`{verb}` in {cwd}", args
    if verb in r.harmless:   # echo and printf print what a glob expands to: the scope's file names
        hit = next((a for a in args if any(c in a for c in "*?[") and inside(a, cwd, r)), None)
        return (f"`{verb}` of {hit}" if hit else None), args
    opts = [w for w in rest if w.startswith("-")]
    if (verb in GREPS and args and not any(GREP_PATTERN_OPT.match(o) for o in opts)
            and not (GREP_NO_PATTERN & set(opts))):
        args = args[1:]   # the pattern: text that may name a path, never a file it opens
    walks = fence_walks(verb, opts) or (verb in WALKS_BY_DEFAULT and not piped and "-" not in rest
                                        and not NO_WALK & set(opts))
    if walks or (verb == "ls" and not any(re.match(r"^-[A-Za-z0-9]*d", o) for o in opts)):
        # an option's value (`-g '*.md'`, `-m 5`, `-e x`) is no path: the walked folders are the
        # words that exist, each glob expanded, a copier's sources only; none, and a walker that
        # defaults to it walks the cwd
        words = walk_paths(verb, rest)
        if verb in GREPS and words and not any(GREP_PATTERN_OPT.match(o) for o in opts) and not (GREP_NO_PATTERN & set(opts)):
            words = words[1:]
        if verb in COPIERS:
            words = words[:-1]
        found = [m for a in words for m in expand(a, cwd) if os.path.lexists(resolve(m, cwd))]
        depth = _find_depth(rest) if verb == "find" else None

        def reaches(m):
            if inside(m, cwd, r):
                return True
            if not walks or not holds(m, cwd, r):   # ls: one level
                return False
            if depth is None:
                return True
            base = resolve(m, cwd).rstrip(os.sep)   # `find <dir> -maxdepth N` lists names N levels down
            return any(d.startswith(base + os.sep) and d[len(base) + 1:].count(os.sep) + 1 < depth for d in r.present)
        hit = next((m for m in found if reaches(m)), None)
        if hit:
            return f"`{verb}` over {hit}, which holds the folder", args
        if walks and verb in CWD_WALKERS and not any(os.path.isdir(resolve(m, cwd)) for m in found) and holds(cwd, cwd, r):
            return f"`{verb}` over {cwd}, which holds the folder", args
    return None, args


def bash_hit(cmd, cwd, r, depth=0):
    """What the command would read or write in the rules' folders, or None."""
    cmd, bodies = split_heredocs(cmd)
    for line, body, _ in bodies:   # a body is data unless an interpreter or a shell reads it
        try:
            seg = next((s for s in segments(line) if any(t.startswith("<<") for t in s)), [])
        except ValueError:
            seg = line.split()
        verb = verb_of(seg)
        if INTERPRETER.match(verb) or verb in SHELL or verb == "eval":
            hit = code_hit(verb, body, cwd, r, depth)
            if hit:
                return hit
    if depth < 3:   # $(…) and backticks run even inside double quotes; not inside single ones
        for m in SUBST.finditer(blank_single_quoted(cmd)):
            hit = bash_hit(m.group(1) or m.group(2) or "", cwd, r, depth + 1)
            if hit:
                return hit
    try:
        segs = list(segments_with_seps(cmd))
    except ValueError:   # unbalanced quotes: judge path-like mentions in the raw text
        for c in r.candidate.findall(cmd):
            if ("/" in c or c == ".env") and inside(c, cwd, r):
                return f"{c}, in a command this guard could not parse"
        return None
    for seg, sep in segs:
        words, skip = [], False
        for i, tok in enumerate(seg):
            if skip:
                skip = False
                continue
            if is_redirect(tok):
                nxt = seg[i + 1] if i + 1 < len(seg) else ""
                skip = True
                if nxt and not nxt.isdigit() and not nxt.startswith("&") and inside(nxt, cwd, r):
                    return f"a redirection {'into' if '>' in tok else 'from'} {nxt}"
                continue
            words.append(tok)
        if r.fence and words and words[0] == "for":   # `for r in <projects>/*/`: names, as echo prints them
            continue
        while words and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]) or words[0] in WRAPPERS
                         or (r.fence and words[0] in KEYWORDS)):
            m = re.match(r"^(GIT_DIR|GIT_WORK_TREE|GIT_COMMON_DIR)=(.*)$", words[0])
            if r.fence and m and inside(m.group(2), cwd, r):
                return f"`git` in {m.group(2)}"
            words.pop(0)
        if not words:
            continue
        verb, rest = os.path.basename(words[0]), words[1:]
        opts = [w for w in rest if w.startswith("-")]
        args = [w for w in rest if not w.startswith("-")]
        if verb == "cd" or (r.fence and verb == "pushd"):   # the fence takes a glob's first match, as the shell does
            cwd = resolve(expand(args[0], cwd)[0] if r.fence else args[0], cwd) if args else os.path.expanduser("~")
            continue
        if (verb == "secrets" or any(w.endswith("bin/secrets") for w in words)) and "--fix" in words:
            return ("`secrets check --fix` — link with `ln -s`; empty placeholders arrive at the "
                    "next session start")
        if r.fence:
            hit, args = fence_hit(verb, rest, args, cwd, r, sep in ("|", "|&"))
            if hit is not None:
                if hit:
                    return hit
                continue
        if verb in r.harmless:
            continue
        if verb == "ln" and any(re.match(r"^-[A-Za-z]*s|^--symbolic$", o) for o in opts):
            continue
        follow = verb not in LINK_ITSELF
        # a fence grep's pattern is text, `--regexp=<path>` and `'X=<path>'` too
        eq = [w for w in rest if "=" in w and not (r.fence and verb in GREPS and not (w.startswith("-") and not w.startswith("--regexp=")))]
        values = [words[0]] + args + [w.split("=", 1)[1] for w in eq]
        for v in values:
            if inside(v, cwd, r, follow):
                return f"`{verb}` on {v}"
        if INTERPRETER.match(verb) or verb in SHELL or verb == "eval":
            code = [rest[j + 1] for j, o in enumerate(rest[:-1]) if re.match(r"^-[A-Za-z]*[ce]$", o)]
            for c in (code if verb != "eval" else rest):
                hit = code_hit("sh" if verb == "eval" else verb, c, cwd, r, depth)
                if hit:
                    return hit
        if not r.fence and (verb in RECURSIVE or (verb == "find" and {"-exec", "-execdir", "-ok", "-okdir"} & set(rest))):   # the fence: fence_hit
            # a grep walks only with -r, and never its pattern: `ls -p ~ | grep -v /` holds nothing
            walked = ([] if not any(RECURSE_FLAG.match(o) for o in opts) and verb in ("grep", "egrep", "fgrep")
                      else args[1:] if verb in GREPS and not any(GREP_PATTERN_OPT.match(o) for o in opts) else args)
            for a in walked:
                if holds(a, cwd, r):
                    return f"`{verb}` over {a}, which holds the folder"
    return None


def _tool(word):
    """`sessionpipe`, `/opt/homebrew/bin/sessionpipe`, `sessionpipe@latest`, `…/sessionpipe/dist/cli.js`
    → "sessionpipe"; the same for the front end; anything else ''."""
    w = word.rsplit("=", 1)[-1].strip("`'\"(){}!;$")   # `alias.x=!sessionpipe`, `--run=sessionpipe`
    if not w or w.startswith("@"):
        return ""
    for tool in filter(None, (DAEMON, FRONT)):
        if os.path.basename(w.split("@")[0]) == tool or re.search(r"(^|/)%s/(dist|bin|lib)/" % re.escape(tool), w):
            return tool
    return ""


def _command_word(words):
    """The simple command's own command word and the words after it: keywords, assignments and
    wrappers in front stripped."""
    while words and (words[0] in KEYWORDS or words[0] in WRAPPERS
                     or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0])):
        words = words[1:]
    return (os.path.basename(words[0]), words[1:]) if words else ("", [])


def _strip_redirects(words):
    """words without redirections: `>`, `<<` and the word after them, `2` in front of `>&`. Only
    shlex's words: it splits every unquoted redirection off, so a word starting with `<` is text."""
    out, i = [], 0
    while i < len(words):
        w = words[i]
        if is_redirect(w):
            i += 1 if w == "<<<" else 2   # a here-string's word is fed to the command: kept
            continue
        if w.isdigit() and i + 1 < len(words) and is_redirect(words[i + 1]):
            i += 1
            continue
        out.append(w)
        i += 1
    return out


def _interp_args(rest):
    """An interpreter's arguments → (the index in rest of the script or module it runs, or None;
    whether it reads code from stdin: `-`, or neither a script nor -c / -e code)."""
    code, i = False, 0
    while i < len(rest):
        w = rest[i]
        if w == "-":
            return None, True
        if w in ("--", "-m"):
            return (i + 1 if i + 1 < len(rest) else None), False
        if re.match(r"^-[A-Za-z]*[ce]$", w) or w in ("--eval", "--print"):
            code, i = True, i + 2
            continue
        if w.startswith(("--eval=", "--print=")):
            code, i = True, i + 1
            continue
        if w in INTERP_VALUE_OPTS:
            i += 2
            continue
        if w.startswith("-"):
            i += 1
            continue
        return i, False
    return None, not code


def _is_script(word):
    """A command word that names a script by its path (`bin/memo`, `<home>/…/hooks/bulletin.py`), not a
    system tool or one that runs its arguments as a command."""
    base = os.path.basename(word)
    return ("/" in word and not _tool(word) and not os.path.expanduser(word).startswith(SYSTEM_DIRS)
            and base not in SHELL and base not in RUNNERS and not INTERPRETER.match(base))


def _searched(words):
    """(the words of a simple command that can run something, whether it runs a script file): a
    script's own argv is data (review S3, 2026-10-16) — `python3 hooks/bulletin.py --post "…"`,
    `bin/knowledge-commit -m "…"`. A script that is sessionpipe's own (`node …/sessionpipe/dist/cli.js
    install`) is searched whole."""
    words = _strip_redirects(words)
    verb, rest = _command_word(words)
    n = len(words) - len(rest)   # the words up to and including the command word
    if INTERPRETER.match(verb):
        script, _ = _interp_args(rest)
        if script is None or _tool(rest[script]):
            return words, False
        return words[:n + script], True
    if n and _is_script(words[n - 1]):
        return words[:n], True
    return words, False


def _reads_stdin_code(words):
    """The simple command runs what arrives on stdin: a shell anywhere in it (`xargs sh`, `ssh host
    bash`), or an interpreter reading its code from stdin (`python3`, `python3 -`)."""
    if any(os.path.basename(w) in SHELL for w in words):
        return True
    verb, rest = _command_word(_strip_redirects(words))
    return bool(INTERPRETER.match(verb)) and _interp_args(rest)[1]


def _sed_execs(rest):
    """sed's arguments use GNU's `e` command or `s///e` flag, or a script file nobody sees here."""
    for w in rest:
        if w == "-f" or w.startswith("--file") or re.match(r"^-[a-zA-Z]*f$", w):
            return True
        if w.startswith("--expression="):
            w = w.split("=", 1)[1]
        elif w.startswith("-"):
            continue
        if any("e" in m.group(2) for m in SED_S.finditer(w)):
            return True
        if SED_E.search(re.sub(r"/(?:\\.|[^/\\\n])*/", " ", SED_S.sub("s", w))):
            return True
    return False


def _reads_only(words):
    verb, rest = _command_word(words)
    if verb in READERS:
        return True
    if verb == "sed":
        return not _sed_execs(rest)
    if verb == "git":   # past -C <dir>, -c <key=value>, --git-dir / --work-tree to the subcommand
        i = 0
        while i < len(rest):
            w = rest[i]
            if w in GIT_VALUE_OPTS:
                if w == "-c" and GIT_RUNS.search(rest[i + 1].lower() if i + 1 < len(rest) else ""):
                    return False
                i += 2
            elif w.startswith("-"):
                i += 1
            else:
                break
        sub = rest[i] if i < len(rest) else ""
        return sub in GIT_READS and not any(w.startswith("!") for w in rest)
    if verb == "gh":   # gh pr create --body "…" carries text; alias, extension and ssh run code
        subs = [w for w in rest if not w.startswith("-")][:2]
        return not (GH_RUNS & set(subs))
    return False


def _verb_after(words):
    """The deny verb a sessionpipe / front-end word is followed by in `words`, or None."""
    clean = [w.strip("`'\"(){};") for w in words]
    for i, w in enumerate(clean):
        tool = _tool(words[i])
        if not tool:
            continue
        if tool == FRONT and ({"-h", "--help"} & set(clean)):
            continue  # the front end's parser honours -h anywhere; sessionpipe has no help flag
        verbs = SESSIONPIPE_VERBS if tool == DAEMON else FRONT_VERBS
        for j in range(i + 1, len(clean)):
            one, two = (clean[j],), (clean[j], clean[j + 1] if j + 1 < len(clean) else "")
            if one in verbs:   # `update off` too: 0.5.0's update() ignores its arguments
                return "%s %s" % (tool, clean[j])
            if two in verbs:
                return "%s %s" % (tool, " ".join(two))
    return None


def _raw(text):
    m = RAW_SP.search(text) or (RAW_SS.search(text) if RAW_SS else None)
    return re.sub(r"\s+", " ", m.group(0))[:80] if m else None


def _substitutions(text, depth):
    """The first hit in the `$(…)` and backtick bodies of `text` (already blanked as needed)."""
    for m in SUBST.finditer(text):
        hit = sessionpipe_hit(m.group(1) or m.group(2) or "", depth + 1)
        if hit:
            return hit
    return None


def sessionpipe_hit(cmd, depth=0):
    """The sessionpipe / front-end command anywhere in `cmd` that ungates its hooks or ships past
    the gate, or None (module docstring: searched, not parsed; fail-closed)."""
    # Every hit below needs one of the two names in the text; quotes and backslashes a shell would
    # drop are dropped first (`sess'ion'pipe`). Most Bash calls end here, the hook runs on all of
    # them; at depth it prunes the `$(…)`, quoted words and bodies that name neither.
    if not GATED_RE.search(re.sub(r"[\\'\"]", "", cmd)):
        return None
    if depth > 4:
        return _raw(cmd)
    main, bodies = split_heredocs(cmd)
    try:
        segs = list(segments_with_seps(main))
    except ValueError:   # unbalanced quotes: the raw text decides
        return _raw(cmd)
    # anything piped into a shell or into code read from stdin: no simple command only reads, and
    # every quoted word is raw text too (`echo "…os.system('…')" | python3`, review S2c)
    piped = any(sep in ("|", "|&") and _reads_stdin_code(seg) for seg, sep in segs)
    hit = _substitutions(blank_single_quoted(main), depth)   # $(…) and backticks run, inside "…" too
    if hit:
        return hit
    for line, body, quoted in bodies:
        if not quoted:   # `<<EOF`: bash runs the body's $(…) and backticks before any reader sees it
            hit = _substitutions(re.sub(r"\\[`$\\]", "_", body), depth)
            if hit:
                return hit
        try:
            opener = next((s for s in segments(line) if any(t.startswith("<<") for t in s)), [])
        except ValueError:   # split on whitespace: drop an attached `<<'EOF'` or `>file` itself
            opener = [w for w in line.split() if not re.match(r"^[0-9&]*[<>]", w)]
        if not piped and (_reads_only(opener) or _searched(opener)[1]):
            continue   # `cat > notes.md <<'EOF'`, `git commit -F - <<'EOF'`, `python3 bin/x.py <<'EOF'`: data
        verb, _ = _command_word(opener)
        if INTERPRETER.match(verb):
            hit = _raw(body)
        else:
            hit = (_raw(body) if piped else None) or sessionpipe_hit(body, depth + 1)
        if hit:
            return hit
    for seg, _ in segs:
        if _reads_only(seg) and not piped:
            continue
        words = _strip_redirects(seg) if piped else _searched(seg)[0]
        hit = _verb_after(words)
        if hit:
            return hit
        # code, or sed's s///e replacement text (sed reaches here only when it runs a command)
        raw = piped or bool(INTERPRETER.match(_command_word(words)[0])) or _command_word(words)[0] == "sed"
        for w in words:   # a quoted word is a command of its own: ssh host '…', bash -c "…", eval "…"
            if re.search(r"[\s;&|()`$<>]", w):
                # printf / echo text fed to sh: its \n and \t separate words (review S2d)
                hit = (_raw(w) if raw else None) or sessionpipe_hit(re.sub(r"\\[nt]", "\n", w), depth + 1)
                if hit:
                    return hit
    return None


def sheep():
    """keel's `sheep`, by the path a session can run: the regatta checkout's module, else the bare
    name (the overlay's copy was the second choice until B14b, 2026-10-23, which deleted it)."""
    return module_tool("keel", "sheep")


def module_tool(module, name):
    """A regatta module's bin tool by the path a session can run (the `home` file's checkout), else its bare name."""
    base = config_lines("home")
    if base and os.path.isfile(os.path.join(os.path.expanduser(base[0]), "modules", module, "bin", name)):
        return os.path.join(os.path.expanduser(base[0]), "modules", module, "bin", name)
    return name


# ---- the fence (knowledge-layers S2, 2026-10-21) ------------------------------------------------
# A scope flagged `"confidential": true` in the registry is a node nothing outside it reads: a
# session whose cwd is outside the scope is refused the scope's paths, a session inside it is not,
# and every open scope stays open. The paths are the core's scope_paths(), mirrored below in the
# stdlib because the guard imports no core (tests/hooks.sh proves the two agree on a fixture; a
# change to one is a change to both). Like the rest of this file it stops accidents, not intent.
#
# Inside means the hook's cwd is in one of the scope's paths and so is $CLAUDE_PROJECT_DIR when
# Claude Code sets it: a session that only `cd`s into the scope keeps its outside start, as the
# Bash tool carries a cd over into the next call's cwd. Every refusal appends one line to the
# log dir's fence.log — time, scope, tool, cwd, session — and never the path asked for: the weekly
# dream reads that log (G3), and a file name inside the scope is the scope's.

def _registry():
    """(repos, scopes), as the core's scope_registry(): ({}, {}) when the registry cannot be read."""
    p = os.environ.get("CLAUDE_REPOS_JSON") or os.path.join(CONFIG, "wharf", "repos.json")
    try:
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        repos, scopes = d.get("repos") or {}, d.get("scopes") or {}
        return (repos, scopes) if isinstance(repos, dict) and isinstance(scopes, dict) else ({}, {})
    except (OSError, ValueError, AttributeError):
        return {}, {}


def _path_key(name, default):
    v = (config_lines("regatta/" + name) or [""])[0]
    return Path(v).expanduser() if v and os.path.isabs(os.path.expanduser(v)) else default


def _members(scope, repos):
    out = []
    listed = (scope or {}).get("repos")
    for m in listed if isinstance(listed, list) else []:   # the core's scope_members: a list only
        if not isinstance(m, str):
            continue
        hits = sorted(k for k in repos if fnmatch.fnmatchcase(k, m)) if any(c in m for c in "*?[") else [m]
        out += [k for k in hits if k not in out]
    return out


def _login_dirs(home):
    """The core's login_dirs(): the home folder's .claude and each accounts.json row's config dir
    that exists, the Orca logins read back included, in the core's order (account_rows, account_home)."""
    def load(p):
        try:
            return json.loads(Path(p).read_text())
        except Exception:
            return None
    orca = os.environ.get("ACCOUNT_ORCA_FILE") or str(home / ".claude" / "account-orca.json")
    try:
        f = os.environ.get("ACCOUNTS_FILE") or os.path.join(CONFIG, "lighthouse", "accounts.json")
        rows = json.loads(Path(f).read_text(encoding="utf-8")).get("accounts") or []
    except (OSError, ValueError, AttributeError):
        rows = []
    rows = [dict(a) for a in rows or [] if isinstance(a, dict)]
    synced = load(orca)
    synced = synced if isinstance(synced, dict) else {}
    named = {a.get("label") for a in rows}
    extra = [{"label": label, "via": "orca", "provider": e.get("provider") if isinstance(e.get("provider"), str) else "claude"}
             for label, e in synced.items() if not label.startswith("_") and label not in named and isinstance(e, dict)]
    at = next((n for n, a in enumerate(rows) if a.get("primary")), len(rows))
    out = [home / ".claude"]
    for a in rows[:at] + extra + rows[at:]:
        if a.get("provider", "claude") != "claude":
            continue
        try:
            got = ((load(orca) or {}).get(a.get("label")) or {}).get("home") if a.get("via") == "orca" else a.get("home")
            d = (home / got[2:] if got.startswith("~/") else Path(got)).absolute() if isinstance(got, str) and got else None
        except Exception:
            d = None
        if d and d not in out:
            out.append(d)
    return [d for d in out if d.is_dir()]


def scope_paths(name, home=None):
    """[str] — the core's scope_paths(name): per repo of the scope its checkout and every
    `git worktree list` entry, PROJECTS/transcripts/<repo>/, and each login dir's
    projects/<slug>/ for each of those trees, its transcripts and memory both (S2's D1-A,
    2026-10-21). [] for a scope the registry lacks."""
    repos, scopes = _registry()
    if name not in scopes:
        return []
    home = home or Path.home()
    projects = _path_key("projects", Path.home() / "projects")
    logins = _login_dirs(home)
    out, seen = [], set()

    def add(p):
        r = os.path.realpath(p)
        if r not in seen:
            seen.add(r)
            out.append(str(p))
    for key in _members(scopes[name], repos):
        if key not in repos:
            continue
        top = projects / key
        trees = [top]
        try:
            g = subprocess.run(["git", "-C", str(top), "worktree", "list", "--porcelain"],
                               capture_output=True, text=True, timeout=10)
            trees += [Path(l[len("worktree "):]) for l in g.stdout.splitlines() if l.startswith("worktree ")] if g.returncode == 0 else []
        except (OSError, subprocess.SubprocessError):
            pass
        trees = [t for n, t in enumerate(trees) if os.path.realpath(t) not in {os.path.realpath(x) for x in trees[:n]}]
        for t in trees:
            add(t)
        add(projects / "transcripts" / key.rsplit("/", 1)[-1])
        for d in logins:
            for t in trees:
                add(d / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(t)))
    return out


def _forms(paths):
    """Each path as the prefix test meets it: its real path, its parent's real path joined to its
    own name (a link that is itself the path: `rm` of it), and the real path of a `memory` link in
    it — a login's memory dir linked elsewhere (knowledge-home, a vault) is the scope's wherever it
    points, as it was when scope_paths() named `…/<slug>/memory` itself."""
    out = []
    for p in paths:
        m = os.path.join(p, "memory")
        forms = [os.path.realpath(p), os.path.join(os.path.realpath(os.path.dirname(p)), os.path.basename(p))]
        for f in forms + ([os.path.realpath(m)] if os.path.islink(m) else []):
            if f not in out:
                out.append(f)
    return out


def _within(p, dirs):
    r = os.path.realpath(p)
    return any(r == d or r.startswith(d + os.sep) for d in dirs)


# Path-ish words in code (python -c, a heredoc fed to node): anything holding a slash.
FENCE_CANDIDATE = re.compile(r"[^\s'\"()\[\]{},;=<>|&`]*/[^\s'\"()\[\]{},;=<>|&`]*")
# Only printing and testing: ls and stat are out, as a confidential folder's file names are its own.
FENCE_HARMLESS = {"echo", "printf", "test", "[", "realpath", "readlink"}
FENCE_REASON = ("⛔ {what}: that is `{scope}`'s, a confidential scope (the registry's `confidential: true`), "
                "and nothing outside it reads its checkouts, worktrees, transcripts or memory ({owner}, "
                "knowledge-layers D3, 2026-10-20). This session started outside it. The way out: do that "
                "work in a session started inside the scope, in its knowledge repo {anchor} or a worktree "
                "of it; what it learns reaches the rest through its own weekly pass, as generalised lines. "
                "If the scope should be open, {owner} runs `{scopes} set {scope} --open`. The refusal is "
                "logged; don't retry in another shape.")


def fences(cwd):
    """[(scope, Rules)] for each confidential scope this session is outside of."""
    scopes = _registry()[1]
    flagged = [n for n, s in scopes.items() if isinstance(s, dict) and s.get("confidential") is True]
    starts = [cwd] + ([os.environ["CLAUDE_PROJECT_DIR"]] if os.environ.get("CLAUDE_PROJECT_DIR") else [])
    repos, out = _registry()[0], []
    fences.inner = []
    for name in flagged:
        dirs = _forms(scope_paths(name) + _gone_trees(name, repos, scopes))
        if not dirs or all(_within(s, dirs) for s in starts):
            fences.inner += dirs
            continue
        keys = [k.rsplit("/", 1)[-1] for k in _members(scopes[name], repos)]
        # a path behind a shell variable the hook never sees: `$P/<repo>/…`
        literal = re.compile(r"\$\{?\w+\}?/(?:%s)(?:/|$)" % "|".join(map(re.escape, keys))) if keys else None
        out.append((name, Rules(dirs, literal, FENCE_CANDIDATE, FENCE_HARMLESS, fence=True)))
    return out


fences.inner = []   # the dirs of the scopes this session is inside: its cwd there is never logged


def _gone_trees(name, repos, scopes):
    """Each login's session folders of a scope's worktrees that are gone (`<slug>--claude-worktrees-<topic>`):
    scope_paths() names only the trees alive now, and a merged worktree's logs outlive it (the core's
    scope_paths() docstring leaves that prefix to the reader; review S2, 2026-10-22)."""
    projects, out = _path_key("projects", Path.home() / "projects"), []
    for key in _members(scopes.get(name), repos):
        if key in repos:
            slug = re.sub(r"[^A-Za-z0-9]", "-", str(projects / key))
            for d in _login_dirs(Path.home()):
                out += sorted(glob.glob(os.path.join(glob.escape(str(d / "projects")), glob.escape(slug) + "--claude-worktrees-*")))
    return out


def glob_reaches(pattern, base, cwd, r):
    """A Glob of `pattern` under `base` lists a name inside the rules' folders: its literal head is
    inside one, or holds one and the rest of the pattern descends into it (`**`, or a segment
    each step matches, one past the folder itself). A pattern that stops at a folder's own name
    lists only that name, which the registry already shows."""
    absolute, parts, head = pattern.startswith("/"), pattern.split("/"), []
    parts = parts[1:] if absolute else parts
    while parts and not any(c in parts[0] for c in "*?[{"):
        head.append(parts.pop(0))
    root = resolve(os.path.join("/" if absolute else (base or cwd), *head), cwd)
    if any(root == d or root.startswith(d + os.sep) for d in r.dirs):
        return True
    for d in r.present:
        if not d.startswith(root.rstrip(os.sep) + os.sep):
            continue
        rel = d[len(root.rstrip(os.sep)) + 1:].split(os.sep)
        for i, seg in enumerate(parts):
            if seg == "**":
                return True
            if i >= len(rel):
                return True
            if "{" not in seg and not fnmatch.fnmatchcase(rel[i], seg):   # a brace set: taken as a match
                break
    return False


def fence_what(tool, inp, cwd, r):
    """What the call would touch behind this fence, or None."""
    if tool in ("Read", "Edit", "Write", "MultiEdit", "NotebookEdit"):
        path = inp.get("file_path") or inp.get("notebook_path") or ""
        return f"{tool} of {path}" if inside(path, cwd, r) else None
    if tool == "Grep":
        path = inp.get("path") or cwd
        return f"Grep over {path}" if inside(path, cwd, r) or holds(path, cwd, r) else None
    if tool == "Glob":
        path, pattern = inp.get("path") or cwd, inp.get("pattern") or ""
        return f"Glob of {pattern} in {path}" if inside(path, cwd, r) or glob_reaches(pattern, path, cwd, r) else None
    if tool == "Bash":
        return bash_hit(inp.get("command") or "", cwd, r)
    return None


def fence_log(scope, tool, cwd, session):
    """One line in the log dir's fence.log; a log that cannot be written never stops the refusal."""
    try:
        d = _path_key("log-dir", Path.home() / ".local" / "state" / "regatta")
        d.mkdir(parents=True, exist_ok=True)
        with open(d / "fence.log", "a", encoding="utf-8") as f:
            f.write("\t".join((time.strftime("%Y-%m-%dT%H:%M:%S%z"), scope, tool or "", cwd, session or "")) + "\n")
    except OSError:
        pass


def fence(data):
    """The refusal for a call that crosses a confidential scope's fence, or None."""
    cwd = data.get("cwd") or os.getcwd()
    tool, inp = data.get("tool_name"), data.get("tool_input") or {}
    fs = fences(cwd)
    for scope, r in fs:
        what = fence_what(tool, inp, cwd, r)
        if what:
            # a cwd in a scope's paths (the cd-in case, another scope's tree) is the scope's: never logged
            fence_log(scope, tool, "-" if any(_within(cwd, x.dirs) for _, x in fs) or _within(cwd, fences.inner) else cwd,
                      data.get("session_id"))
            repos, scopes = _registry()
            anchor = next(iter(_members(scopes[scope], repos)), "")
            return FENCE_REASON.format(what=what, scope=scope, owner=OWNER, scopes=module_tool("wharf", "scopes"),
                                       anchor=str(_path_key("projects", Path.home() / "projects") / anchor))
    return None


def main():
    data = json.loads(sys.stdin.read())
    if data.get("hook_event_name") != "PreToolUse":
        return
    cwd = data.get("cwd") or os.getcwd()
    tool, inp = data.get("tool_name"), data.get("tool_input") or {}
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        path = inp.get("file_path") or inp.get("notebook_path") or ""
        live = os.path.join(os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join("~", ".claude")), "settings.json")
        if path and resolve(path, cwd) == os.path.realpath(live):
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason": SETTINGS_REASON.format(
                    tool=tool, owner=OWNER, cs=os.path.join(TOOLS, "bin", "claude-settings"))}}, ensure_ascii=False))
            return
    if tool == "Bash":   # before the vault lookup: a Mac without Drive mounted is guarded too
        hit = sessionpipe_hit(inp.get("command") or "")
        if hit:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason": SESSIONPIPE_REASON.format(what=hit, owner=OWNER, sheep=sheep(),
                                                                      front=FRONT or "its front end")}}, ensure_ascii=False))
            return
    try:   # the fence fails open on its own, so the secrets check below still runs
        why = fence(data)
    except Exception:
        why = None
    if why:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": why}}, ensure_ascii=False))
        return
    dirs = secrets_dirs()
    walls = ([(Rules(dirs, LITERAL, CANDIDATE, HARMLESS), REASON)] if dirs else []) \
        + [(r, GUARDED_REASON) for r in (guarded_rules(),) if r]   # guarded dirs: with or without Drive
    for r, reason in walls:
        what = touches(tool, inp, cwd, r)
        if what:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason": reason.format(what=what, owner=OWNER)}}, ensure_ascii=False))
            return


def touches(tool, inp, cwd, r):
    """What the call would read or write in the rules' folders, or None."""
    if tool in ("Read", "Edit", "Write", "MultiEdit", "NotebookEdit"):
        path = inp.get("file_path") or inp.get("notebook_path") or ""
        if inside(path, cwd, r):
            return f"{tool} of {path}"
    elif tool == "Grep":
        path = inp.get("path") or cwd
        if inside(path, cwd, r) or holds(path, cwd, r):
            return f"Grep over {path}"
    elif tool == "Bash":
        return bash_hit(inp.get("command") or "", cwd, r)
    return None


if __name__ == "__main__":
    try:
        main()
    except Exception:   # fail open — see the docstring
        pass
    sys.exit(0)
