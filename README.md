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
- Static extensions register via `Tcl_StaticLibrary`; their `pkgIndex.tcl`
  and script parts live in the attached image, so plain `package require`
  works.
- **Incremental**: build trees with their object files are kept under
  `work/`; after touching one C file a re-run recompiles one object,
  re-archives, relinks and re-images in seconds.

## Usage

```sh
# default battery set, Linux:
bin/whalebuild build

# pick extensions:
bin/whalebuild build -pkgs {tk sqlite3 thread}

# win64 cross (requires the Linux build first — its native tclsh
# drives `zipfs mkimg` and the thread extension's cross-configure):
bin/whalebuild build -platform win64

# embed an application (dir must contain main.tcl):
bin/whalebuild build -app myapp/ -out myapp.bin

# check the result:
./work/linux/whale tests/selftest.tcl
```

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
recipes only state what deviates: extra link libraries per platform,
script files to wrap into the image, a make target, a native-tclsh
requirement. See `recipes/*.rcp` and NOTES.md for the details and for the
field-tested pitfalls each line encodes.

The extension list is configurable per build (`-pkgs`); named *flavors*
(e.g. `-max`) may appear later.

## Requirements

Linux host with: gcc, make, curl, git, unzip, a `tclsh` (any 8.6+, only
to run the driver), Tcl/Tk build deps (zlib, X11/Xft headers for Tk),
`x86_64-w64-mingw32-gcc` for win64, OpenSSL headers for the tls recipe.
Testing win64 output needs wine; GUI self-test uses Xvfb if present.

## Status

Working proof of concept grown out of a live experiment (2026-07); the
default battery set (tk, treectrl, sqlite3, thread, tls) builds and
self-tests on both platforms. Interfaces (recipe fields, CLI) may change.

## License

TBD.
