# Extension backlog

Inventoried 2026-07-12 from the monster-era `whale-max` binaries
(Tcl 8.6b1.2, zip-appended images; cli/gui × linux/win32). The old
battery set is the porting target list; notes reflect a first-pass
upstream assessment — verify before each port.

## Already aboard

tk, sqlite3 (full option set: FTS5, rtree, math...), thread, tls,
tcllib + tcllibc, treectrl, twapi (3.0.0 → 5.x), Registry/Dde
(folded into the static core), itcl, tdbc with all four drivers
(sqlite3, plus the client-less-at-build C trio mysql/odbc/postgres),
tdom (0.8.3 → 0.9.6), Img/tkimg
(1.3 → 2.1.1, all format handlers incl. the four codec support
packages), tkdnd (1.0 → 2.9.5), udp/tcludp (1.0.9 → 1.0.13),
Tkhtml (3.0 → 3.0.2, BAWT snapshot), bwidget (1.x → 1.10.1),
tklib (0.5 → 0.9), awthemes 10.4.0 (replacing the ttk-theme zoo;
scalable variants incl. — Tk 9 renders svg in the core), cffi 2.0.3
(replacing Ffidl 0.6 — same ground, live upstream; libffi 3.7.1
static on both platforms, tclh submodule pinned as an ingredient).

## Easy wins — bundled in the Tcl 9 tarball (`source tclpkgs`)

- **itcl** (was 4.0b4) — `pkgs/itcl` ships in the tcl9 tarball.
- **tdbc** + **tdbcodbc** (was 1.0b14) — also in `pkgs/`; sqlite
  backend (`tdbcsqlite3`) is pure script on top of sqlite3.

## Superseded before porting

- **tksvg** (auriocus) — svg photo images are IN THE CORE on Tk 9
  (nanosvg; tksvg's own pkgIndex no-ops there). Verified live: the
  whale creates svg photos and runs awthemes' scalable awbreeze with
  no extension at all.

## Parked — no Tcl 9 upstream to port (checked 2026-07-12)

The recipe policy is stock sources, zero patches; none of these has
an upstream that builds against Tcl 9 today, so porting them means
maintaining a fork — parked instead, each with its revisit trigger.

- **Expect** (was 5.44, unix, gui image only) — no Tcl 9 release
  exists; the code leans on Tcl internals well beyond the public API,
  so it won't cross-compile clean. Revisit if core.tcl-lang.org ships
  an expect for Tcl 9. The pty niche has no whale substitute till
  then.
- **TclX** (was 8.4) — FlightAware's fork is the live one but its
  Tcl 9 port is unfinished business: tracking issue "Update TclX for
  Tcl 9 API compatibility" open, last commit 2024-01 (8.6.3).
  Revisit when that issue closes. Meanwhile the daily-bread bits
  (signals, fork/exec) remain core-less; cffi covers one-off syscall
  needs at script level.
- **ceptcl** (was 0.4, unix) — upstream dead for ~20 years; AF_UNIX
  is still absent from the Tcl 9 core, so the niche is real, but the
  honest path is a small fresh extension (or script-level cffi for
  datagram/ioctl cases — stream channels need C for the channel
  driver). Not a porting job; parked as a build-from-scratch idea.
- **tktray** (was 1.3.8, X11) — implements the XEmbed tray protocol,
  which the freedesktop world left for DBus StatusNotifierItem;
  GNOME dropped XEmbed trays years ago. A port would target a museum
  piece; on Windows twapi already covers the systray. Dropped.

## Superseded — do not port, note the replacement

- **Mk4tcl / Metakit** → sqlite3 for data (long dead upstream). The
  mk4 FORMAT still lives, though: KitCreator (rkeene) maintains Tcl 9
  ports of tclvfs 1.4.1 + `vfs::mk4` over vlerq/mklite — seen live
  inside the tclkit-9.0.3 fleet. If reading old mk4 kits ever
  matters, port from KitCreator, not from the dead upstreams.
- **Memchan** → core reflected channels (`chan create`) + `tcl::chan::*`
  in tcllib.
- **tclvfs** (+ tclvfs4sqlite) → core zipfs for image needs (but see
  the Mk4tcl entry: a Tcl 9 port exists in KitCreator); the
  sqlite-vfs trick may deserve a fresh look someday.
- **Iocpsock** (win) → obsolete, core winsock got rewritten.
- **Winico / shellicon** (win) → twapi (systray, shell icons).
- **sdx / starkit tooling** → native now: whales run zip kits
  (`whale app.kit`, mounted on //zipfs:/kit) and `whalebuild wrap`
  replaces `sdx wrap`; unwrap/ls is plain `unzip`.
- **tclhttpd** (was 3.4.3) — era piece; modern choice would be
  wapp/naviserver territory. Only port on concrete need.

## Monster-local bits (decide separately, not OSS upstreams)

- **crypt 1.0**, **limit 1.0**, **syslog 1.1**, **tclwrap 0.7**,
  **vtls 0.1** — small local C helpers of the monster era; port on
  demand or fold functionality into modern equivalents (vtls → tls
  2.x / twapi::tls, syslog → tcllib logger + systemd?).
- **whale-apps / whale-shell / whale-tmlib** — the owner's app layer,
  lives above the kit; out of whalebuild scope.
- **xotcl** (was 1.6.6) — successor is **nx/nsf**; core TclOO covers
  much of the ground (itcl 4 itself sits on TclOO). Port nx only on
  concrete need.

## Non-extension ideas picked from the old fleet

- **-max flavor** once a meaningful chunk of the list above lands
  (the old binaries were literally `whale-max-*`).
- **debug variants** (`-dbg` builds with symbols, like
  `whale-max-*-dbg`): a `-debug` build knob (CFLAGS/-g, no strip).
- **linux 32-bit (lx86)** existed back then; today probably skip.
