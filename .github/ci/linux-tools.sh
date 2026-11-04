#!/usr/bin/env bash
# What the twin's ubuntu runner has and CircleCI's Ubuntu VM may lack, for every `suite` job: the PR
# check's (check-linux.yml on Actions, .circleci/parts/check-linux.yml on CircleCI) and the twin's
# (check.yml's matrix, free CI's S2); CircleCI's twin `linux` job installs its own, inline, to the
# same end. Public since S2 (2026-11-04), beside share.sh.
# Writes the PATH it builds to ~/.linux-path,
# which the step that runs a suite exports (`export PATH="$(cat ~/.linux-path)"`). Never $BASH_ENV:
# every nested non-interactive bash re-reads it, so a suite's own PATH for a stub was overwritten
# (keel's "the CLI's own folder first on PATH" case; the keel Linux fix, 2026-10-27).
#
# python3 is the system one, first on PATH, with apt's PyYAML: the image's python3 is a pyenv shim,
# and a suite that moves HOME lost PyYAML through it (33 "PyYAML is not installed for this python3"
# lines, helm's 82 failures among them, on main b0d03c98's run, 2026-10-27; the shim's HOME is
# inferred as the cause, not read).
#
# On a persistent runner (GitHub's RUNNER_ENVIRONMENT `self-hosted`: a Linux host of one's own that takes
# the share's suites, linux-runner 2026-11-04) a job keeps out of what is the runner login's own, as
# AGENTS.md's runner traps and ci-provider's guard step say: HOME and TMPDIR are the job's own, under
# RUNNER_TEMP (which the runner empties after each job, and which check-linux.yml's suite step exports
# alike), `git config --global` writes the job's file, and this script runs no sudo or apt-get: a missing package
# fails the job, naming it, for the image's owner to add (ci-provider's RUNNER_CONTAINERFILE: ci-provider runs a Linux
# runner in a rootless container with no sudo in it, a fresh one a job, D1-C). Node and the claude CLI are kept in
# RUNNER_TOOL_CACHE by version, each marked complete only once it is, so a job on a runner that keeps its tool cache
# takes them as they are (the container keeps none: each job fetches them, as a hosted one does).
set -euo pipefail
src="$(cd "$(dirname "$0")/../.." && pwd)"
persistent=
if [ "${RUNNER_ENVIRONMENT:-}" = self-hosted ]; then
  persistent=1
  : "${RUNNER_TEMP:?a self-hosted job has RUNNER_TEMP}"
  jh="$RUNNER_TEMP/home"
  export HOME="$jh" TMPDIR="$RUNNER_TEMP/tmp" GIT_CONFIG_GLOBAL="$jh/.gitconfig"
  mkdir -p "$HOME" "$TMPDIR"
  cache="${RUNNER_TOOL_CACHE:-$RUNNER_TEMP}/regatta-linux"
  mkdir -p "$cache"
fi
. /etc/os-release && echo "$PRETTY_NAME; /bin/sh is $(readlink -f /bin/sh); $(ls --version | head -1)"
need=""
for c in jq ruby sqlite3; do command -v "$c" >/dev/null || need="$need $c"; done
/usr/bin/python3 -c 'import yaml' 2>/dev/null || need="$need python3-yaml"
if [ -n "$need" ]; then
  if [ -n "$persistent" ]; then
    echo "linux-tools: this runner lacks$need: add it to the image (ci-provider's RUNNER_CONTAINERFILE) and run --runner install again; this script runs no sudo on a self-hosted runner" >&2
    exit 1
  fi
  sudo apt-get update -qq && sudo apt-get install -y -qq $need
fi
# the sheep kick road's socket client, websockets 14.0+ (wharf-runs' test_kick_socket runs its stub-server cases only
# where it imports, and this job is where a pull request runs that suite): apt's is too old on 24.04 (10.4), so the
# pure-python wheel from PyPI, checked against its sum, unpacked into the system python3's site-packages (no pip
# there; HOME-independent, as the suites move HOME). The landing review of kick-socket, round 2.
if ! /usr/bin/python3 -c 'import sys; from websockets.version import version as v; sys.exit(int(v.split(".")[0]) < 14)' 2>/dev/null; then
  if [ -n "$persistent" ]; then
    echo "linux-tools: this runner lacks websockets 14+: ci-provider's RUNNER_CONTAINERFILE carries it, so run --runner install again; this script runs no sudo on a self-hosted runner" >&2
    exit 1
  fi
  ws_whl=websockets-15.0.1-py3-none-any.whl
  ws_dir="$(mktemp -d)"
  curl -fsSL --retry 3 "https://files.pythonhosted.org/packages/fa/a8/5b41e0da817d64113292ab1f8247140aac61cbf6cfd085d6a0fa77f4984f/$ws_whl" -o "$ws_dir/$ws_whl"
  (cd "$ws_dir" && echo "f7a866fbc1e97b5c617ee4116daaa09b722101d4a3c170c787450ba409f9736f  $ws_whl" | sha256sum -c -)
  ws_site="$(/usr/bin/python3 -c 'import site; print(site.getsitepackages()[0])')"
  sudo mkdir -p "$ws_site"
  sudo /usr/bin/python3 -m zipfile -e "$ws_dir/$ws_whl" "$ws_site"
  /usr/bin/python3 -c 'from websockets.sync.client import connect'   # a failed unpack fails the job, never a quiet skip
fi
# Node as the twin's check.yml asks for it (node-version: 22, the newest 22.x; lighthouse needs
# 22.13+), checked against nodejs.org's own sums
case "$(uname -m)" in
  x86_64) arch=x64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "linux-tools: no Node build for $(uname -m)" >&2; exit 1 ;;
esac
base=https://nodejs.org/dist/latest-v22.x
work="$(mktemp -d)"
curl -fsSL "$base/SHASUMS256.txt" -o "$work/sums"
tarball="$(awk -v a="linux-$arch" '$2 ~ (a "\\.tar\\.xz$") {print $2}' "$work/sums")"
[ -n "$tarball" ] || { echo "linux-tools: nodejs.org lists no linux-$arch build" >&2; exit 1; }
node="$HOME/node"
[ -z "$persistent" ] || node="$cache/${tarball%.tar.xz}"
if [ -e "$node/.complete" ]; then
  echo "Node: ${tarball%.tar.xz}, kept from an earlier job"
else
  (cd "$work" && curl -fsSLO "$base/$tarball" && grep " $tarball\$" sums | sha256sum -c -)
  rm -rf "$node" && mkdir -p "$node" && tar -xJf "$work/$tarball" -C "$node" --strip-components=1
  touch "$node/.complete"
fi
path="$node/bin:/usr/bin:$PATH"
# the claude CLI at the version the twin's check.yml pins, read from it; on a persistent runner in a
# prefix of its own, so the kept Node stays as nodejs.org made it
cli="$(grep -o '@anthropic-ai/claude-code@[0-9.]*' "$src/.github/workflows/check.yml" | head -1)"
if [ -n "$persistent" ]; then
  prefix="$cache/claude-code-${cli##*@}"
  path="$prefix/bin:$path"
fi
printf '%s\n' "$path" > "$HOME/.linux-path"
export PATH="$path"
if [ -z "$persistent" ]; then
  npm install -g "$cli"
elif [ -e "$prefix/.complete" ]; then
  echo "claude: ${cli##*@}, kept from an earlier job"
else
  rm -rf "$prefix" && npm install -g --prefix "$prefix" "$cli"
  touch "$prefix/.complete"
fi
git config --global user.name "CI"
git config --global user.email ci@example.invalid
git config --global init.defaultBranch main
echo "python3 is $(command -v python3): $(python3 -c 'import yaml; print("PyYAML", yaml.__version__)'); $(python3 -c 'import websockets; print("websockets", websockets.__version__)' 2>/dev/null || echo 'no websockets')"
node --version && claude --version
