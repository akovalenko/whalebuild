#!/bin/sh
# cbuild.sh — containerized whalebuild: one podman box per platform
# leg (Containerfile.linux / Containerfile.win64), each with its own
# PERSISTENT work tree bind-mounted over work/ from outside the
# container (work-linux/, work-win64/ next to this script), so the
# build cache and incremental rebuilds survive container death.
#
#   ./cbuild.sh linux [-jobs 8 ...]    -> work-linux/linux/whale
#   ./cbuild.sh win64 [-jobs 8 ...]    -> work-win64/win64/whale.exe
#   ./cbuild.sh linux selftest [cli]  headless selftest (xvfb-run)
#   ./cbuild.sh <leg> -- <cmd...>     arbitrary command in the box
#   ./cbuild.sh <leg> -- sh           poke around interactively
#
# Everything after the leg (except the two verbs above) is passed to
# `bin/whalebuild build -platform <leg>` verbatim — -flavor cli,
# -pkgs, -update, -app, -out all work; quote a -pkgs list as one
# shell word: -pkgs 'tk sqlite3'. `selftest cli` tests the cli-flavor
# artifact (whale-cli) instead of the default whale.
#
# Rootless podman with --userns=keep-id: artifacts in work-<leg>/
# come out owned by the invoking user. HOME inside is /tmp — keep-id
# users have no passwd entry and tools that want $HOME (git, xauth)
# get a writable one. The repo mounts at /w; the work-<leg> mount
# shadows /w/work, so recipes and driver see the usual layout.
#
# Extra podman options ride in through two env knobs (word-split, so
# flags only — no spaces inside a value):
#   CBUILD_OPTS        extra args for every `podman run`
#                      e.g. CBUILD_OPTS='--network=host -e FOO=bar'
#   CBUILD_BUILD_OPTS  extra args for the lazy `podman build`
#                      e.g. CBUILD_BUILD_OPTS='--network=host'
# (They are separate because run flags like -e are not build flags.)
# podman forwards HTTP_PROXY/HTTPS_PROXY/NO_PROXY from the client
# environment into both by itself; a proxy listening on the host's
# 127.0.0.1 additionally needs --network=host to be reachable (or
# slirp4netns:allow_host_loopback=true and the 10.0.2.2 address).
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
    || podman build ${CBUILD_BUILD_OPTS:-} \
        -f "$HERE/Containerfile.$leg" -t "$img" "$HERE"
mkdir -p "$HERE/work-$leg"

tty=
[ -t 0 ] && tty=-it

# Forward the driver's own WHALEBUILD_* env into the container: podman
# run does NOT inherit the host environment, so a plain
# `WHALEBUILD_CORE_CFLAGS=-DPURIFY ./cbuild.sh win64` would otherwise
# reach the driver as unset and silently build a stock kit. `-e NAME`
# (no =value) passes the value through from cbuild.sh's own env.
fwd=
for v in $(env | sed -n 's/^\(WHALEBUILD_[A-Za-z0-9_]*\)=.*/\1/p'); do
    fwd="$fwd -e $v"
done

crun() {
    # ${CBUILD_OPTS} after the defaults, so e.g. -e HOME=... in it
    # overrides ours (later podman flags win).
    podman run --rm $tty --userns=keep-id -e HOME=/tmp \
        $fwd ${CBUILD_OPTS:-} \
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
        shift
        crun xvfb-run -a "work/linux/whale${1:+-$1}" tests/selftest.tcl
        ;;
    --) shift; crun "$@" ;;
    *)  crun bin/whalebuild build -platform "$leg" "$@" ;;
esac
