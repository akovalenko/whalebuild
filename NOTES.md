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
- **System layer stays dynamic.** libc, X11 — and OpenSSL: tls C code is
  static, libssl/libcrypto come from the OS (stable `.so.3` ABI), so
  admins apply security updates without touching the whale. On Windows
  there is no system OpenSSL; options are shipping the two DLLs next to
  the exe (updatable in place), SChannel via TWAPI, or static (worst for
  updates) — not decided here, the tls recipe is Linux-only for now.
- **Two-phase make for incrementality.** A recursive make caches `.a`
  mtimes before sub-makes update them and would skip the relink; the
  driver therefore runs extension sub-makes first, then a fresh link
  step. Build trees under `work/` keep their objects: one-line C change →
  one recompile + relink + re-image, seconds.
- **appinit is generated** from the recipe list (externs +
  `Tcl_StaticLibrary` calls) into the platform template. On Windows the
  template also registers `Registry`/`Dde` — in a static build their
  objects are folded into `libtcl90.a` by the stock makefile.

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
