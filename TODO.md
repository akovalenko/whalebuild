# Extension backlog

Inventoried 2026-07-12 from the monster-era `whale-max` binaries
(Tcl 8.6b1.2, zip-appended images; cli/gui × linux/win32). The old
battery set is the porting target list; notes reflect a first-pass
upstream assessment — verify before each port.

## Already aboard

tk, sqlite3, thread, tls, tcllib + tcllibc, treectrl, twapi
(3.0.0 → 5.x), Registry/Dde (folded into the static core),
itcl, tdbc + tdbc::sqlite3, tdom (0.8.3 → 0.9.6), Img/tkimg
(1.3 → 2.1.1, all format handlers incl. the four codec support
packages), tkdnd (1.0 → 2.9.5), udp/tcludp (1.0.9 → 1.0.13),
Tkhtml (3.0 → 3.0.2, BAWT snapshot), bwidget (1.x → 1.10.1),
tklib (0.5 → 0.9), awthemes 10.4.0 (replacing the ttk-theme zoo;
scalable variants incl. — Tk 9 renders svg in the core).

## Easy wins — bundled in the Tcl 9 tarball (`source tclpkgs`)

- **itcl** (was 4.0b4) — `pkgs/itcl` ships in the tcl9 tarball.
- **tdbc** + **tdbcodbc** (was 1.0b14) — also in `pkgs/`; sqlite
  backend (`tdbcsqlite3`) is pure script on top of sqlite3.

## Superseded before porting

- **tksvg** (auriocus) — svg photo images are IN THE CORE on Tk 9
  (nanosvg; tksvg's own pkgIndex no-ops there). Verified live: the
  whale creates svg photos and runs awthemes' scalable awbreeze with
  no extension at all.

## C extensions with a live upstream — port next

- **Ffidl** (was 0.6) — superseded by **cffi** (apnadkarni, same
  author as twapi): active, Tcl 9-ready; port cffi instead. Needs
  libffi or dyncall — the twapi recipe already links dyncall.
- **Expect** (was 5.44, unix, gui image only) — upstream near-dead,
  Tcl 9 status doubtful; decide if the niche (pty scripting) is
  still needed.
- **TclX** (was 8.4) — kept alive by FlightAware for 8.6; Tcl 9
  unclear. Much of it (signals, fork) still has no core equivalent.
- **ceptcl** (was 0.4, unix) — AF_UNIX sockets; niche still open in
  the Tcl 9 core, upstream ancient. Candidate for a small modern
  replacement.
- **tktray** (was 1.3.8, X11) — system tray; on Windows the old
  Winico role is covered by twapi. Check freedesktop-era relevance.

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
