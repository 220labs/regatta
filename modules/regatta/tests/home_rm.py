"""A suite's delete of a folder's worth under $HOME, outside its rm_own (F2, 2026-10-25).

A suite that moves HOME into its own temp folder deletes under it safely while it runs. A block of a
suite run outside it is not safe: on 2026-10-25 a session ran a sed range of test_helm.sh in a shell
whose HOME was the real one, and its `rm -rf "$R"` (R the run records under $HOME) emptied the Mac's
run records. rm_own, defined in the suite, deletes only under the suite's own $T, and a block run
outside the suite has no rm_own, so it deletes nothing. This lists each recursive `rm` (the flag
anywhere in its flag run), each `rm` of a glob, and each `find … -delete` or `-exec rm` whose path
names $HOME, `~/`, or a variable the same file builds from $HOME (followed through other such
variables), as `<file>:<line>: <text>`. An `rm -f` of one named file under HOME is not listed.

    python3 home_rm.py <suite.sh>…
"""
import re
import sys

ASSIGN = re.compile(r'\b([A-Za-z_]\w*)=("[^"]*"|\S*)')
RM = re.compile(r'(?<![\w-])rm\s+((?:-\S*\s+)*)([^;&|#]*)')
FIND = re.compile(r'(?<![\w-])find\s+([^;&|#]*?)\s(?:-delete\b|-exec\s+rm\b)')
GLOB = re.compile(r'[*?\[]')


def home_names(text):
    """Every variable assigned from $HOME, `~/`, or another such variable, to a fixpoint."""
    pairs = ASSIGN.findall(text)
    names = set()
    while True:
        pat = home_re(names)
        more = {n for n, rhs in pairs if n not in names and pat.search(rhs)}
        if not more:
            return names
        names |= more


def home_re(names):
    home = [r"\$\{?HOME\b", r"(?<![\w$])~/"] + [r"\$\{?%s\b" % re.escape(n) for n in sorted(names)]
    return re.compile("|".join(home))


def quoted(line, at):
    """Inside a double-quoted string (a case's data, not a command): an odd count of quotes before it."""
    return line[:at].count('"') % 2 == 1


def flagged(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    under_home = home_re(home_names(text))
    lines, start, buf = [], 0, ""
    for n, line in enumerate(text.splitlines(), 1):
        if not buf:
            start = n
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        lines.append((start, buf + line))
        buf = ""
    for n, line in lines:
        if line.lstrip().startswith("#"):
            continue
        hit = False
        for m in RM.finditer(line):
            if quoted(line, m.start()):
                continue
            recursive = re.search(r"(?:^|\s)(?:-[^-\s]*[rR]|--recursive)", m.group(1))
            for arg in m.group(2).split():
                if under_home.search(arg) and (recursive or GLOB.search(re.sub(r"\$\{[^}]*\}", "", arg))):
                    hit = True
        for m in FIND.finditer(line):
            if not quoted(line, m.start()) and under_home.search(m.group(1)):
                hit = True
        if hit:
            yield "%s:%d: %s" % (path, n, line.strip()[:160])


if __name__ == "__main__":
    hits = [h for p in sys.argv[1:] for h in flagged(p)]
    print("\n".join(hits)) if hits else None
    sys.exit(1 if hits else 0)
