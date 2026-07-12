# Design notes and field-tested pitfalls

Everything below was hit for real while building the prototype (2026-07);
recipes and the driver encode these so users don't have to.

## Design decisions

- **Interpreter by default.** A whale without `-app` carries no `main.tcl`;
  `TclZipfs_AppHook` only auto-runs `//zipfs:/app/main.tcl` when present,
  otherwise `Tcl_Main` handles argv as usual. So the same image layout
  serves both modes and embedding is purely additive.
- **Lazy Tk.** Tk is linked statically but registered via
  `Tcl_StaticLibrary(NULL, "Tk", …)` and initialized only by
  `package require Tk` (through the image's `lib/tk/pkgIndex.tcl`, which
  sets `::tk_library` first). No X11 connection until asked. This is the
  classic tclkit model.
- **System layer stays dynamic — on Linux.** libc, X11 — and OpenSSL:
  tls C code is static, libssl/libcrypto come from the OS (stable
  `.so.3` ABI), so admins apply security updates without touching the
  whale. On Windows there is no system OpenSSL, and DLLs next to the
  exe would break the single-file model — so win64 links OpenSSL
  STATICALLY from the `work/cache/openssl-win64` ingredient, declared
  in tls.rcp (`ingredient` recipe field) and cross-built automatically
  on the first win64 build (OpenSSL >= 3.2 so tcltls's Windows default
  CA store `org.openssl.winstore://` — the native ROOT store — kicks
  in). Security updates on win64 mean rebuilding the kit; that is the
  platform's normal cost. twapi's SChannel TLS remains available in
  parallel.
- **Per-platform source trees, in-tree builds.** Sources are fetched once
  into `work/cache/` (pristine, never built) and copied per platform;
  everything builds in-tree. Out-of-tree (VPATH) builds of third-party
  extensions were a recurring source of subtle breakage in the monster
  era and buy nothing here — while same-family targets (two unixes) would
  collide in a shared tree's `unix/` build dir. Disk is cheap; a dirty
  platform tree is disposable.
- **Two-phase make for incrementality.** A recursive make caches `.a`
  mtimes before sub-makes update them and would skip the relink; the
  driver therefore runs extension sub-makes first, then a fresh link
  step. Build trees under `work/` keep their objects: one-line C change →
  one recompile + relink + re-image, seconds.
- **Kits: starkit UX on core zipfs.** `whale app.kit` works because
  appinit probes the startup script with `zipfs mount`: a zip with
  `main.tcl` at its root gets mounted on `//zipfs:/kit`, `lib/` joins
  `auto_path`, and the startup script is redirected via
  `Tcl_SetStartupScript`. This can't be done from script level (no
  Tcl-level startup-script setter), and the core's own argv[1] kit
  logic hides behind `SUPPORT_BUILTIN_ZIP_INSTALL` — an `#error` stub
  in 9.0.4. The probe is skipped for `//zipfs:/*` startup scripts, so
  an embedded `-app` whale never eats its first argument. Wrapping is
  `zipfs mkzip` (`whalebuild wrap`); `-exec` prepends a shebang via
  `zipfs mkimg`'s infile parameter. Old mk4-format kits are NOT
  readable (see TODO.md — KitCreator keeps tclvfs/vfs::mk4 alive on
  Tcl 9 if that compat is ever wanted).
- **Starpacks without a toolchain.** `whalebuild pack` merges an
  existing whale's mounted image with the app dir into a fresh vfs
  and re-attaches it. The core does the delicate part:
  `zipfs mkimg ... infile` copies only `passOffset` bytes of infile —
  it strips an already-attached image by itself — so any built whale
  serves as a runtime, images never stack, and re-packing a packed
  whale just works. The packer is any zipfs-capable Tcl 9 (a whale
  can pack itself).
- **Fetch is a no-op once sources exist; `-update` opts into following
  upstream.** It pulls git caches (`git pull --ff-only`; tarballs are
  pinned by the recipe URL — bump the version and clean the cache to
  move) and refreshes the per-platform trees with `rsync -a --checksum`
  and no `--delete`: content-equal files are not touched (no spurious
  rebuilds), build artifacts survive (they don't exist in the cache),
  and only genuinely changed sources get a fresh mtime for make. Not
  the default on purpose: a plain build must never surprise you with
  an upstream drive-by.
- **appinit is generated** from the recipe list (externs +
  `Tcl_StaticLibrary` calls) into the platform template. On Windows the
  template also registers `Registry`/`Dde` — in a static build their
  objects are folded into `libtcl90.a` by the stock makefile.
- **Flavors are computed, not hand-listed.** `-flavor all` (default) =
  every recipe supported on the platform; `-flavor cli` = all minus tk
  and minus everything whose `requires` closure reaches tk. Explicit
  `-pkgs` lists are completed with their requires closure (treectrl
  pulls tk), and the set is built dependencies-first (topological
  order over `requires`). Artifacts: `whale` for all, `whale-<flavor>`
  otherwise.
- **Windows subsystem follows Tk.** With tk in the set the whale links
  `-mwindows` and enters via wWinMain/`Tk_Main` (wish model); without —
  `-mconsole`/`Tcl_Main`. Interactively (no startup script) the GUI
  whale brings Tk up eagerly and attaches the **built-in console**
  (`generic/tkConsole.c` + `tk_library/console.tcl`, both already in
  the static core/image — no tkcon needed) as the REPL; with a script
  Tk stays lazy as everywhere. `Tk_InitConsoleChannels` (called inside
  `Tk_MainEx`) only replaces std channels that are actually invalid,
  so redirected runs keep writing to files — which is what keeps the
  wine selftest working against a GUI-subsystem exe. Verified under
  wine: `wine start whale.exe` (double-click simulation, no inherited
  handles) pops the console REPL.

## Core (Tcl/Tk 9.0.4)

- Static build: `--disable-shared` in `unix/` resp. `win/`. "Static" means
  Tcl inside the binary; the binary itself still links libc etc.
- Script libraries are NOT installed as directory trees in a static
  build — they ship as zips in the build dir (`libtcl9.0.4.zip`,
  `libtk9.0.4.zip`). **The Tk zip contains both** `tcl_library/` and
  `tk_library/`, so a GUI image is one unzip.
- Boot contract (from `tclZipfs.c`): the attached zip mounts at
  `//zipfs:/app`; the core looks for `tcl_library/init.tcl` under it, and
  auto-runs `main.tcl` at the root if present.
- `zipfs mkimg out indir strip password infile`: the **strip argument is
  required** when wrapping a staging dir, else files land under a `vfs/`
  prefix and boot finds nothing.
- `package require` finds image packages because `//zipfs:/app` (parent
  of `tcl_library`) is on `auto_path` — but `lib/<pkg>/` is two levels
  deep, so the generated appinit appends `//zipfs:/app/lib` to
  `auto_path`.

## Extensions (TEA)

- All of sqlite3, thread, treectrl, tcltls built static with stock
  `configure --disable-shared` — zero source patches. Keep stubs on
  (`USE_TCL_STUBS` + `STATIC_BUILD` is what TEA does); link
  `libtclstub.a`/`libtkstub.a` alongside the cores.
- sqlite3 and thread are **bundled in the Tcl source tarball** (`pkgs/`),
  no separate fetch.
- thread's cross-configure packs its script part with zipfs and needs a
  **native Tcl 9 tclsh**: `TCLSH_NATIVE=…` for both configure and make.
- tcltls: `make` fails in the doc generator (system `dtplite` wants a
  tcllib package); build the `binaries` target. Its own pkgIndex already
  anticipates static loading, but `tls.tcl` must be wrapped next to the
  static pkgIndex.
- treectrl (tcltk-depot fork, real Tcl 9 port — `Tcl_Size` throughout):
  on Windows calls uxtheme directly (`IsThemeActive`/`OpenThemeData`) —
  add `-luxtheme` beyond the `tkConfig.sh` list.
- Extension C code finds its script part via `tcl_findLibrary`; the
  static pkgIndex sets the `::<name>_library` variable to the image dir.

## Windows cross (mingw-w64)

- Wine is NOT needed for building (it was in the 2000s) — only for
  testing. First wineboot of a fresh prefix under Xvfb hangs on the Wine
  Mono dialog: `WINEDLLOVERRIDES="mscoree,mshtml="`.
- Compile appinit with `-DSTATIC_BUILD` or tcl.h declares the API
  `dllimport` (`undefined reference to __imp_Tcl_MainExW`). Link with
  `-municode -mconsole -static-libgcc` like the stock tclsh.exe.
- Static lib names differ per platform (`libtcl9.0.a` vs `libtcl90.a`);
  the driver globs instead of hardcoding.

## TWAPI (win64-only)

- MinGW-W64 is an officially supported toolchain upstream; the TEA
  configure sits at the repo root and builds everything as one module
  (`-DTWAPI_SINGLE_MODULE`). A stock static TEA cross-build works with
  three knobs, all encoded in the recipe:
  - `--enable-64bit` — dyncall ships PREBUILT in-tree as `.lib`
    archives, and this flag selects the amd64 copy (default is x86).
    MinGW-made despite the suffix (undefined symbols are only
    malloc/memcpy & co), so GNU ld consumes them as ordinary COFF
    archives; the recipe passes the in-tree path via `@SRC@`.
  - `-DTCL_NO_TOMMATH_H` — twapi uses the bignum API, and
    tclTomMath.h otherwise includes "tommath.h", which lives in the
    Tcl source tree but is never installed. The define (Tcl 9's knob
    for exactly this) makes the header self-contained.
  - `-DTWAPI_STATIC_BUILD` — twapi's own static-build macro, NOT set
    by its configure. Without it every symbol is
    `__declspec(dllexport)` and twapi.c defines `DllMain`, colliding
    with treectrl's at link time (one stray DllMain in an exe is dead
    code; two are a multiple-definition error).
- The pkgIndex.tcl generated by configure already falls back to
  `load {} Twapi` when no DLL is found, so the image wraps it
  verbatim next to the (flat) script files — no hand-written
  pkgindex in the recipe.
- The final link needs the ~28 WinAPI import libraries from
  configure.ac's TEA_ADD_LIBS (`.lib` names become `-l` for gcc);
  the recipe repeats that list for the whale's link step.
- Bonus: twapi_crypto ships `twapi::tls_socket` over SChannel, so the
  win64 whale has TLS without OpenSSL (cf. the tls recipe being
  Linux-only).

## tcllibc (critcl accelerators) — experimental, not wired in

tcllib 2.0 script modules wrap fine as image files. The C accelerators
(tcllibc, built by critcl 3.3.1) CAN be linked static — proven — but the
path is crooked; kept out of recipes until it earns its keep:

- critcl compiles module bodies **PIC-only** (companions get both); a
  static archive is assembled from critcl's object cache, preferring
  non-PIC (PIC in an executable is legal).
- critcl embeds its own copy of the stub pointers (`tclStubsPtr` etc.),
  colliding with `libtclstub.a` → `-Wl,--allow-multiple-definition`
  (identical .bss objects; every reference binds to the survivor).
- Collection contract: one `Tcllibc_Init` creates all C commands;
  sub-packages (md5c, …) are NOT `package provide`d — tcllib modules
  detect accelerators by command presence; `tcllibc` itself is provided
  by the pkgIndex, not by the init.
- `critcl -tea` does aggregate a multi-file collection into one generated
  package (named after the first input file), but the generated "TEA"
  build is a facade: its Makefile re-invokes embedded critcl with `-pkg`
  → a shared lib again. critcl simply has no static mode. Its TEA
  generator also chokes on autoconf 2.71 warnings (treats stderr as
  failure). The proper fix is an upstream critcl feature.

## Alternatives surveyed

- **KitCreator** (rkeene): closest relative, modular, documented mingw
  cross; 8.x-centric (kitsh + mk4/zip storage), Tcl 9 support unconfirmed.
- **BAWT** (Obermeier): builds Tcl/Tk + ~100 extensions, source of static
  tclsh/wish "zipkit" templates; but no static extension set.
- **AndroWish / undroidwish / vanillawish** (Werner): living
  batteries-included single-file wishes for many platforms; ride that
  tree if you don't need your own set.
