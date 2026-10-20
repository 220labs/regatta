#!/usr/bin/env python3
"""secrets_guard — Drive's _secrets folder is closed to agents: no reads, no writes; links allowed.

Since 2026-10-18 the vaults' `_contacts` the same way (docs/work-contacts-2026-10-18.md): work
contact books, third parties' phone numbers, read by the messaging tool in its own process.

The owner, 2026-09-25: read-only at first, then "agents don't need reads in secrets either. They
are passed via .env to whichever apps need them … But agents should be able to symlink to them."

A PreToolUse hook on Read|Grep and Edit|Write|NotebookEdit|Bash, installed user-wide (the
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
names only and is not matched.

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

Fails open: an error in here lets the call through rather than blocking every tool in every
session. Tests: tests/hooks.sh, "secrets_guard".
"""
import glob
import json
import os
import re
import shlex
import sys

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


def resolve(path, cwd, follow=True):
    p = os.path.expanduser(os.path.expandvars(path))
    if not os.path.isabs(p):
        p = os.path.join(cwd, p)
    if follow:
        return os.path.realpath(p)
    return os.path.join(os.path.realpath(os.path.dirname(p)), os.path.basename(p))


def inside(path, cwd, dirs, follow=True):
    if not path:
        return False
    if LITERAL and LITERAL.search(path):
        return True
    p = resolve(path, cwd, follow)
    return any(p == d or p.startswith(d + os.sep) for d in dirs)


def holds(path, cwd, dirs):
    """path is a folder the secrets folder sits somewhere under."""
    p = resolve(path, cwd)
    return any(d.startswith(p.rstrip(os.sep) + os.sep) for d in dirs)


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


def code_hit(verb, code, cwd, dirs, depth):
    """A heredoc body or `-c` string: shell code is judged as a command, other code by the
    paths it names."""
    if verb in SHELL:
        return bash_hit(code, cwd, dirs, depth + 1) if depth < 3 else None
    for c in CANDIDATE.findall(code):
        if inside(c, cwd, dirs):
            return f"`{verb}` code that names {c}"
    return None


def bash_hit(cmd, cwd, dirs, depth=0):
    """What the command would read or write in the folder, or None."""
    cmd, bodies = split_heredocs(cmd)
    for line, body, _ in bodies:   # a body is data unless an interpreter or a shell reads it
        try:
            seg = next((s for s in segments(line) if any(t.startswith("<<") for t in s)), [])
        except ValueError:
            seg = line.split()
        verb = verb_of(seg)
        if INTERPRETER.match(verb) or verb in SHELL or verb == "eval":
            hit = code_hit(verb, body, cwd, dirs, depth)
            if hit:
                return hit
    if depth < 3:   # $(…) and backticks run even inside double quotes; not inside single ones
        for m in SUBST.finditer(blank_single_quoted(cmd)):
            hit = bash_hit(m.group(1) or m.group(2) or "", cwd, dirs, depth + 1)
            if hit:
                return hit
    try:
        segs = list(segments(cmd))
    except ValueError:   # unbalanced quotes: judge path-like mentions in the raw text
        for c in CANDIDATE.findall(cmd):
            if ("/" in c or c == ".env") and inside(c, cwd, dirs):
                return f"{c}, in a command this guard could not parse"
        return None
    for seg in segs:
        words, skip = [], False
        for i, tok in enumerate(seg):
            if skip:
                skip = False
                continue
            if is_redirect(tok):
                nxt = seg[i + 1] if i + 1 < len(seg) else ""
                skip = True
                if nxt and not nxt.isdigit() and not nxt.startswith("&") and inside(nxt, cwd, dirs):
                    return f"a redirection {'into' if '>' in tok else 'from'} {nxt}"
                continue
            words.append(tok)
        while words and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]) or words[0] in WRAPPERS):
            words.pop(0)
        if not words:
            continue
        verb, rest = os.path.basename(words[0]), words[1:]
        opts = [w for w in rest if w.startswith("-")]
        args = [w for w in rest if not w.startswith("-")]
        if verb == "cd":
            cwd = resolve(args[0], cwd) if args else os.path.expanduser("~")
            continue
        if (verb == "secrets" or any(w.endswith("bin/secrets") for w in words)) and "--fix" in words:
            return ("`secrets check --fix` — link with `ln -s`; empty placeholders arrive at the "
                    "next session start")
        if verb in HARMLESS:
            continue
        if verb == "ln" and any(re.match(r"^-[A-Za-z]*s|^--symbolic$", o) for o in opts):
            continue
        follow = verb not in LINK_ITSELF
        values = [words[0]] + args + [w.split("=", 1)[1] for w in rest if "=" in w]
        for v in values:
            if inside(v, cwd, dirs, follow):
                return f"`{verb}` on {v}"
        if INTERPRETER.match(verb) or verb in SHELL or verb == "eval":
            code = [rest[j + 1] for j, o in enumerate(rest[:-1]) if re.match(r"^-[A-Za-z]*[ce]$", o)]
            for c in (code if verb != "eval" else rest):
                hit = code_hit("sh" if verb == "eval" else verb, c, cwd, dirs, depth)
                if hit:
                    return hit
        if verb in RECURSIVE or (verb == "find" and {"-exec", "-execdir", "-ok", "-okdir"} & set(rest)):
            for a in args:
                if holds(a, cwd, dirs):
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
    """keel's `sheep`, by the path a session can run: the regatta checkout's module, else the
    overlay's (the config dir's `legacy`), else the bare name."""
    for base, rel in ((config_lines("home"), ("modules", "keel", "bin", "sheep")), (config_lines("legacy"), ("bin", "sheep"))):
        if base and os.path.isfile(os.path.join(os.path.expanduser(base[0]), *rel)):
            return os.path.join(os.path.expanduser(base[0]), *rel)
    return "sheep"


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
    dirs = secrets_dirs()
    if not dirs:
        return
    what = None
    if tool in ("Read", "Edit", "Write", "MultiEdit", "NotebookEdit"):
        path = inp.get("file_path") or inp.get("notebook_path") or ""
        if inside(path, cwd, dirs):
            what = f"{tool} of {path}"
    elif tool == "Grep":
        path = inp.get("path") or cwd
        if inside(path, cwd, dirs) or holds(path, cwd, dirs):
            what = f"Grep over {path}"
    elif tool == "Bash":
        what = bash_hit(inp.get("command") or "", cwd, dirs)
    if what:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": REASON.format(what=what, owner=OWNER)}}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:   # fail open — see the docstring
        pass
    sys.exit(0)
