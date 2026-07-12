# whalebuild

Builds **whales**: single-file Tcl/Tk 9 executables — a statically linked
interpreter with a chosen set of extensions and a zipfs image attached.
Linux native and win64 (mingw-w64 cross) targets, built from a Linux host.

A modern reincarnation of *monster*, a private Tcl build system from the
2000s whose output was called *whale* (a pun on Russian «кит» = tclkit).
Back then the kit machinery — VFS, image attach, boot — had to be built by
hand; Tcl 9 ships all of it in the core (`zipfs mkimg`, TIP 430), so
whalebuild is a thin driver plus per-extension recipes, not a framework.

## What you get

- One executable, no install: `./whale` (Linux, ~8 MB) or `whale.exe`
  (win64). Statically contains Tcl, optionally Tk and extensions; links
  dynamically only against the system layer (libc, X11, and — by policy —
  OpenSSL, so security updates don't require a rebuild).
- **Interpreter by default**, like tclkit: no embedded `main.tcl`, the
  binary behaves as tclsh (`./whale script.tcl args…`, or interactive).
  Embedding an application is an explicit request (`-app <dir>`).
- **Tk is lazy**: compiled in, but not initialized until the script asks
  (`package require Tk`). A CLI script never touches X11/GDI.
- **Windows subsystem follows Tk**: with Tk in the set `whale.exe` is a
  GUI-subsystem binary (wish model) — run bare / double-clicked it opens
  Tk's built-in console as the interactive REPL; running a script keeps
  Tk lazy and redirected output still lands in your files. Without Tk
  (`-flavor cli`) it is a plain console binary.
- Static extensions register via `Tcl_StaticLibrary`; their `pkgIndex.tcl`
  and script parts live in the attached image, so plain `package require`
  works.
- **Incremental**: build trees with their object files are kept under
  `work/`; after touching one C file a re-run recompiles one object,
  re-archives, relinks and re-images in seconds.

## Usage

```sh
# everything supported on the platform (flavor "all", the default):
bin/whalebuild build

# no-GUI flavor: excludes tk and everything that requires it:
bin/whalebuild build -flavor cli        # -> work/linux/whale-cli

# pick extensions (the requires closure is added automatically,
# e.g. treectrl pulls in tk):
bin/whalebuild build -pkgs {tk sqlite3 thread}

# follow upstream: pull git sources and carefully resync the build
# trees (only genuinely changed files are touched, so the rebuild
# stays incremental); tarball sources are pinned by the recipe:
bin/whalebuild build -update

# win64 cross (requires the Linux build first — its native tclsh
# drives `zipfs mkimg` and the thread extension's cross-configure):
bin/whalebuild build -platform win64

# embed an application (dir must contain main.tcl):
bin/whalebuild build -app myapp/ -out myapp.bin

# check the result:
./work/linux/whale tests/selftest.tcl
```

## Kits (the starkit workflow on zipfs)

A *kit* is a plain zip with `main.tcl` at its root (and, optionally, a
`lib/` with packages) — any whale runs it directly, sdx-style:

```sh
bin/whalebuild wrap myapp/ myapp.kit      # sdx wrap analog (zipfs mkzip)
./work/linux/whale myapp.kit args...      # mounts on //zipfs:/kit, runs main.tcl
bin/whalebuild wrap -exec myapp/ myapp.kit  # + shebang, ./myapp.kit runs
unzip -l myapp.kit                        # sdx unwrap/ls analog: it is a zip
```

`-exec` prepends `#!/usr/bin/env whale` (zip readers ignore prefix
data) and marks the file executable.

For a standalone single-file application (the *starpack*), bake the
app into a whale — either at build time (`build -app dir -out file`)
or, with no toolchain at all, onto an existing whale:

```sh
bin/whalebuild pack myapp/ myapp        # runtime: work/linux/whale
bin/whalebuild pack -runtime work/win64/whale-cli.exe myapp/ myapp.exe
```

`pack` merges the runtime's attached image with the app dir and
re-attaches the result; re-packing an already-packed whale works too
(images never stack — see NOTES.md).

## Recipes

One file per extension under `recipes/`, in the spirit of BAWT (which we
would have used, except it doesn't do a *static* set). A simple extension
is a simple file:

```tcl
version 3.53.0
source tclpkgs sqlite3.53.0     ;# bundled in the Tcl source tarball
init Sqlite3                    ;# Tcl_StaticLibrary prefix
pkgindex {package ifneeded sqlite3 3.53.0 {load {} Sqlite3}}
```

The default build style is TEA (`configure --disable-shared && make`);
recipes only state what deviates: extra configure arguments, extra link
libraries per platform (`@SRC@` expands to the recipe's source tree),
script files to wrap into the image, a make target, a native-tclsh
requirement. See `recipes/*.rcp` and NOTES.md for the details and for the
field-tested pitfalls each line encodes.

The extension list is configurable per build (`-pkgs`); named *flavors*
(e.g. `-max`) may appear later.

## Requirements

Linux host with: gcc, make, curl, git, unzip, a `tclsh` (any 8.6+, only
to run the driver), Tcl/Tk build deps (zlib, X11/Xft headers for Tk),
`x86_64-w64-mingw32-gcc` for win64, OpenSSL headers for the tls recipe
(on win64 the static OpenSSL ingredient is cross-built automatically
into `work/cache/openssl-win64` on the first build — declared in
tls.rcp), rsync for `-update`.
Testing win64 output needs wine; GUI self-test uses Xvfb if present.

## Containerized builds (podman)

Two build boxes, one per leg, each with its own **persistent** work
tree bind-mounted over `work/` from outside the container — the build
cache and incremental rebuilds survive container death:

- `Containerfile.linux` — Ubuntu 22.04: the oldest mainstream
  userland whose OpenSSL is the 3.x line — the binary's real floor
  is the openssl symbol-version tags it links against, so building
  against 3.0.2 makes the dynamically-linked-by-policy whale run on
  anything with `libssl.so.3` (newer openssls serve old tags; the
  reverse fails).
- `Containerfile.win64` — fresh Arch: rolling mingw-w64. A native
  Tcl 9 tclsh is baked into the image (`WHALEBUILD_NATIVE_TCLSH`) —
  with a separate work per leg the cross build can't borrow it from
  a linux install.

```sh
./cbuild.sh linux -jobs 8            # -> work-linux/linux/whale
./cbuild.sh win64 -jobs 8            # -> work-win64/win64/whale.exe
./cbuild.sh linux -flavor cli        # any build args pass through:
./cbuild.sh linux -pkgs 'tk sqlite3' # ...-flavor, -pkgs, -update, -app
./cbuild.sh linux selftest           # headless selftest via xvfb-run
./cbuild.sh linux selftest cli       # ...of the cli-flavor whale
./cbuild.sh <leg> -- sh              # poke around inside the box
```

Rootless podman, `--userns=keep-id`: artifacts come out owned by the
invoking user. Images build lazily on first `cbuild.sh` use. Wine is
deliberately not in the win64 box — test that leg on the host.

Extra podman flags ride in via env: `CBUILD_OPTS` for every `podman
run` (e.g. `--network=host -e X=y`), `CBUILD_BUILD_OPTS` for the lazy
image build. A proxy on the host's loopback needs `--network=host`
in both; podman forwards the `HTTP_PROXY`/`HTTPS_PROXY` variables
themselves automatically.

## Status

Working proof of concept grown out of a live experiment (2026-07); the
default battery set (tk, treectrl, sqlite3, thread, tcllib, tls, itcl,
tdbc + tdbc::sqlite3, tdom, tkimg/Img, tkdnd, tkhtml, udp, bwidget,
tklib, awthemes, plus tcllibc on Linux, twapi on Windows) builds and
self-tests on both platforms (tls on win64 = static OpenSSL, verified
under wine incl. winstore certificate verification). Interfaces
(recipe fields, CLI) may change.

## License

The Unlicense (public domain); see UNLICENSE.
