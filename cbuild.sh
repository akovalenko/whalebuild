#!/bin/sh
# cbuild.sh — containerized whalebuild: one podman box per platform
# leg (Containerfile.linux / Containerfile.win64), each with its own
# PERSISTENT work tree bind-mounted over work/ from outside the
# container (work-linux/, work-win64/ next to this script), so the
# build cache and incremental rebuilds survive container death.
#
#   ./cbuild.sh linux [-jobs 8 ...]    -> work-linux/linux/whale
#   ./cbuild.sh win64 [-jobs 8 ...]    -> work-win64/win64/whale.exe
#   ./cbuild.sh linux selftest        headless GUI selftest (xvfb-run)
#   ./cbuild.sh <leg> -- <cmd...>     arbitrary command in the box
#   ./cbuild.sh <leg> -- sh           poke around interactively
#
# Everything after the leg (except the two verbs above) is passed to
# `bin/whalebuild build -platform <leg>` verbatim.
#
# Rootless podman with --userns=keep-id: artifacts in work-<leg>/
# come out owned by the invoking user. HOME inside is /tmp — keep-id
# users have no passwd entry and tools that want $HOME (git, xauth)
# get a writable one. The repo mounts at /w; the work-<leg> mount
# shadows /w/work, so recipes and driver see the usual layout.
#
# Images build lazily on first use. After editing a Containerfile,
# rebuild explicitly:
#   podman build -f Containerfile.<leg> -t whalebuild-<leg> .

set -e
HERE=$(cd "$(dirname "$0")" && pwd)

leg=$1
case "$leg" in
    linux|win64) shift ;;
    *) echo "usage: cbuild.sh linux|win64 [selftest | -- cmd... | build args...]" >&2
       exit 2 ;;
esac
img=localhost/whalebuild-$leg

podman image exists "$img" \
    || podman build -f "$HERE/Containerfile.$leg" -t "$img" "$HERE"
mkdir -p "$HERE/work-$leg"

tty=
[ -t 0 ] && tty=-it
crun() {
    podman run --rm $tty --userns=keep-id -e HOME=/tmp \
        -v "$HERE:/w" -v "$HERE/work-$leg:/w/work" -w /w \
        "$img" "$@"
}

case "${1:-}" in
    selftest)
        if [ "$leg" != linux ]; then
            echo "cbuild.sh: in-box selftest is linux-only;" \
                 "the win64 leg is tested under wine on the host" >&2
            exit 2
        fi
        crun xvfb-run -a work/linux/whale tests/selftest.tcl
        ;;
    --) shift; crun "$@" ;;
    *)  crun bin/whalebuild build -platform "$leg" "$@" ;;
esac
