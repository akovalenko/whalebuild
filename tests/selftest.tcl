# whale self-test: run as `./whale tests/selftest.tcl`.
# Exercises whatever batteries are compiled in; skips what is absent.
# GUI part runs when a display is plausible (Windows, or DISPLAY set).

proc say {s} {puts $s; flush stdout}
set failed 0
proc check {label script} {
    global failed
    if {[catch {uplevel 1 $script} err]} {
	say "FAIL $label: $err"
	incr failed
    } else {
	say "ok   $label: $err"
    }
}

say "whale: Tcl [info patchlevel], exe=[file tail [info nameofexecutable]]"
say "tcl_library: $tcl_library"

# The whale is self-contained — test the image, not the workshop: on
# the build host the exe's baked-in install prefix puts
# work/<platform>/install/lib on auto_path, and the DYNAMIC builds of
# the bundled packages living there would silently shadow the static
# batteries under test (caught 2026-07-12: "ok itcl" was the install
# tree's itcl.so, while the battery's pkgindex panicked).
set auto_path [lsearch -all -inline $auto_path //zipfs:*]

check sqlite3 {
    package require sqlite3
    sqlite3 db :memory:
    db eval {CREATE TABLE t(a INTEGER, b TEXT)}
    db eval {INSERT INTO t VALUES (1,'one'),(2,'two'),(3,'three')}
    set r [db eval {SELECT b FROM t ORDER BY a}]
    db close
    join $r ,
}

check sqlite3-batteries {
    # the bundled TEA package compiles the full option set by default
    # (FTS3/4/5, R*Tree + geopoly, math funcs, session, stat4...) —
    # pin the headline ones so a future rebundle can't silently drop
    # them
    sqlite3 db :memory:
    db eval {CREATE VIRTUAL TABLE ft USING fts5(body)}
    db eval {INSERT INTO ft VALUES ('the whale swims'), ('the kit builds')}
    set hit [db onecolumn {SELECT body FROM ft WHERE ft MATCH 'whale'}]
    db eval {CREATE VIRTUAL TABLE rt USING rtree(id, x0, x1)}
    set ok [db onecolumn {SELECT sqrt(2) BETWEEN 1.41 AND 1.42}]
    db close
    if {$hit ne "the whale swims" || !$ok} {error "fts5=$hit math=$ok"}
    list fts5 match rtree table math sqrt
}

check thread {
    package require thread
    set tid [thread::create]
    set r [thread::send $tid {expr {6*7}}]
    thread::release $tid
    set r
}

if {![catch {package require tls}]} {
    check tls {tls::version}
    # Loopback handshake — deliberately NO egress: a thread serves TLS
    # on 127.0.0.1 with the long-lived self-signed pair
    # tests/loopback.pem, the client verifies it via -cafile and
    # echoes a line. The negative leg drops -cafile: the DEFAULT store
    # (system CAs on unix, org.openssl.winstore:// on Windows) must
    # reject a self-signed cert — proving verification is really on.
    set pem [file join [file dirname [info script]] loopback.pem]
    if {[catch {package require thread}] || ![file exists $pem]} {
	say "skip tls-loopback: needs the thread battery and tests/loopback.pem"
    } else {
	set tid [thread::create]
	# a fresh thread's interp has the default auto_path, without the
	# image's lib/ — hand ours over so `package require tls` resolves
	thread::send $tid [list set auto_path $auto_path]
	thread::send $tid [list set pem $pem]
	set port [thread::send $tid {
	    package require tls
	    proc accept {ch args} {
		fconfigure $ch -blocking 0 -buffering line
		fileevent $ch readable [list echo $ch]
	    }
	    proc echo {ch} {
		if {[catch {gets $ch line} n] || [eof $ch]} {
		    catch {close $ch}
		    return
		}
		if {$n >= 0} {puts $ch "echo:$line"}
	    }
	    set srv [tls::socket -server accept \
		-certfile $pem -keyfile $pem 0]
	    lindex [fconfigure $srv -sockname] 2
	}]
	check tls-loopback {
	    set so [tls::socket -cafile $::pem -servername localhost \
		127.0.0.1 $::port]
	    tls::handshake $so
	    fconfigure $so -buffering line
	    puts $so whale
	    set r [gets $so]
	    close $so
	    set r
	}
	check tls-verify-negative {
	    set r [catch {
		set so [tls::socket -servername localhost 127.0.0.1 $::port]
		tls::handshake $so
	    }]
	    catch {close $so}
	    if {!$r} {error "self-signed accepted by the default store"}
	    set r "self-signed rejected without -cafile"
	}
	thread::release $tid
    }
} else {
    say "skip tls: not compiled in"
}

if {![catch {package require tcllibc}]} {
    check tcllibc {
	package require md5
	list critcl-accel $::md5::accel(critcl) \
	    md5 [md5::md5 -hex whale]
    }
} else {
    say "skip tcllibc: not compiled in"
}

if {![catch {package require itcl}]} {
    check itcl {
	itcl::class Counter {
	    variable n 0
	    method bump {} {incr n}
	}
	Counter c
	c bump
	c bump
	set r [c bump]
	itcl::delete class Counter
	set r
    }
} else {
    say "skip itcl: not compiled in"
}

if {![catch {package require tdbc::sqlite3}]} {
    check tdbc-sqlite3 {
	tdbc::sqlite3::connection create tconn :memory:
	set stmt [tconn prepare {SELECT :a + :b AS s}]
	set rs [$stmt execute {a 2 b 40}]
	$rs nextdict row
	$rs close
	$stmt close
	tconn close
	dict get $row s
    }
} else {
    say "skip tdbc::sqlite3: not compiled in"
}

# tdbc's C drivers (mysql, odbc, postgres) compile self-contained and
# Tcl_LoadFile the real client library at package require time. A
# failed require on a machine without that library is fine — as long
# as it is the CLIENT loader failing, not the static plumbing ("can't
# find package" = pkgindex/registration broken).
foreach drv {mysql odbc postgres} {
    if {![catch {package require tdbc::$drv} v]} {
	if {[llength [info commands ::tdbc::${drv}::connection]]} {
	    say "ok   tdbc-$drv: $v (client library present)"
	} else {
	    say "FAIL tdbc-$drv: loaded but no connection class"
	    incr failed
	}
    } elseif {![string match {can't find package*} $v]} {
	say "ok   tdbc-$drv: static init ok, no client library here"
    } else {
	say "FAIL tdbc-$drv: $v"
	incr failed
    }
}

if {![catch {package require tdom}]} {
    check tdom {
	set doc [dom parse {<batteries kind="static">
	    <b>tdom</b><b>whale</b></batteries>}]
	set root [$doc documentElement]
	set n [llength [$root selectNodes //b]]
	set first [$root selectNodes {string(//b[1])}]
	$doc delete
	set xslt [dom parse {<xsl:stylesheet version="1.0"
		xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	    <xsl:output method="text"/>
	    <xsl:template match="/">v=<xsl:value-of select="//v"/></xsl:template>
	</xsl:stylesheet>}]
	set src [dom parse <r><v>42</v></r>]
	$src xslt $xslt out
	set r [list count $n first $first xslt [string trim [$out asText]]]
	foreach d [list $xslt $src $out] {$d delete}
	set r
    }
} else {
    say "skip tdom: not compiled in"
}

if {![catch {package require nostr}]} {
    check nostr {
	set sec [string repeat 0 63]3    ;# BIP-340 test vector 0 key
	set ev [nostr::sign -sec $sec -kind 1 -content whale \
	    -created-at 1700000000]
	if {![nostr::verify $ev]} {error "verify failed"}
	if {[nostr::verify [string map {whale whal3} $ev]]} {
	    error "tampering not caught"
	}
	# NIP-44 v2 + NIP-59 gift wrap (the NIP-17 DM crypto)
	set bob [string repeat 0 63]5
	set bpub [nostr::pubkey -hex $bob]
	if {[nostr::nip44 decrypt -sec $bob -pub [nostr::pubkey -hex $sec] \
		[nostr::nip44 encrypt -sec $sec -pub $bpub "gm ⚡"]] ne "gm ⚡"} {
	    error "nip44 roundtrip failed"
	}
	set rumor [nostr::event -pubkey [nostr::pubkey -hex $sec] -kind 14 \
	    -content "sealed"]
	set got [nostr::unwrap -sec $bob [nostr::wrap -sec $sec -to $bpub $rumor]]
	if {[dict get $got rumor] ne $rumor} {error "gift wrap roundtrip failed"}
	list npub [string range [nostr::pubkey $sec] 0 9]… \
	    sign+verify+nip44+giftwrap ok
    }
    if {![catch {package require nostr::relay}]} {
	check nostr::relay {
	    # load-only: the DM/relay procs are defined (no network here)
	    if {![llength [info procs ::nostr::dm::send]]
		    || ![llength [info procs ::nostr::relay::connect]]} {
		error "relay layer did not define its commands"
	    }
	    set _ "connect/publish/subscribe/dm defined"
	}
    } else {
	say "skip nostr::relay: not shipped"
    }
} else {
    say "skip nostr: not compiled in"
}

if {![catch {package require udp}]} {
    check udp {
	set srv [udp_open]
	set port [fconfigure $srv -myport]
	fconfigure $srv -buffering none -translation binary -blocking 0
	set cli [udp_open]
	fconfigure $cli -buffering none -translation binary \
	    -remote [list 127.0.0.1 $port]
	fileevent $srv readable [list set ::udpgot data]
	after 3000 [list set ::udpgot timeout]
	puts -nonewline $cli whale-dgram
	vwait ::udpgot
	set r [read $srv]
	close $cli
	close $srv
	if {$::udpgot eq "timeout"} {error "datagram never arrived"}
	set r
    }
} else {
    say "skip udp: not compiled in"
}

if {![catch {package require cffi}]} {
    check cffi {
	# both halves of libffi: a forward call (ffi_call) and a Tcl
	# proc turned C function pointer (ffi_closure) that qsort calls
	cffi::alias load C    ;# size_t & friends
	if {$tcl_platform(platform) eq "windows"} {
	    cffi::Wrapper create crt msvcrt.dll
	} else {
	    cffi::Wrapper create crt libc.so.6
	}
	crt function strlen size_t {s string}
	if {[strlen whale] != 5} {error "strlen whale: [strlen whale]"}
	cffi::prototype function cmp_proto int \
	    {a {pointer unsafe} b {pointer unsafe}}
	proc cmpbyte {a b} {
	    binary scan [cffi::memory tobinary! $a 1] c x
	    binary scan [cffi::memory tobinary! $b 1] c y
	    expr {$x - $y}
	}
	set cb [cffi::callback new cmp_proto cmpbyte -1]
	crt function qsort void \
	    {base {pointer unsafe} n size_t sz size_t f pointer.cmp_proto}
	set p [cffi::memory frombinary [binary format c* {3 1 4 1 5}]]
	qsort $p 5 1 $cb
	binary scan [cffi::memory tobinary $p 5] c* sorted
	cffi::memory free $p
	cffi::callback free $cb
	if {$sorted ne "1 1 3 4 5"} {error "qsort gave: $sorted"}
	list strlen 5 qsort $sorted
    }
} else {
    say "skip cffi: not compiled in"
}

if {$tcl_platform(platform) eq "windows"} {
    check registry {
	load {} Registry
	llength [registry keys HKEY_CURRENT_USER]
    }
    check dde {
	load {} Dde
	package present dde
    }
    if {![catch {package require twapi_base}]} {
	check twapi {
	    package require twapi          ;# meta: all module scripts
	    if {[twapi::get_current_process_id] != [pid]} {
		error "pid mismatch"
	    }
	    list ver [twapi::get_version -patchlevel] pid [pid]
	}
    } else {
	say "skip twapi: not compiled in"
    }
}

if {($tcl_platform(platform) eq "windows"
	|| ([info exists env(DISPLAY)] && $env(DISPLAY) ne ""))
	&& ![catch {package require tk}]} {
    check Tk {
	package require Tk     ;# deprecated capitalized alias
	list tk [package present tk] Tk [package present Tk]
    }
    check treectrl {
	package require treectrl
	treectrl .t -showheader yes
	.t column create -text probe -width 120
	.t item create -count 3
	pack .t
	update
	set r "[winfo class .t] reqwidth=[winfo reqwidth .t]"
	destroy .t   ;# NOT `destroy .` — that kills Tk for later checks
	set r
    }
    if {![catch {package require tkdnd}]} {
	check tkdnd {
	    # registering really talks to the platform (XdndAware
	    # property / OLE RegisterDragDrop), not just script glue
	    label .dndprobe
	    tkdnd::drop_target register .dndprobe DND_Text
	    set types [bind .dndprobe <<DropTargetTypes>>]
	    tkdnd::drop_target unregister .dndprobe
	    destroy .dndprobe
	    list [package present tkdnd] types $types
	}
    } else {
	say "skip tkdnd: not compiled in"
    }
    if {![catch {package require BWidget}]} {
	check bwidget {
	    ComboBox .cb -values {kit whale}
	    .cb setvalue @1
	    set r [list [package present BWidget] [.cb cget -text]]
	    destroy .cb
	    set r
	}
    } else {
	say "skip bwidget: not compiled in"
    }
    if {![catch {package require awdark}]} {
	check awthemes {
	    ttk::style theme use awdark
	    set r [ttk::style theme use]
	    # scalable variant — proves Tk 9's built-in svg rendering
	    package require awbreeze
	    ttk::style theme use awbreeze
	    lappend r [ttk::style theme use]
	    ttk::style theme use default
	    set r
	}
    } else {
	say "skip awthemes: not compiled in"
    }
    if {![catch {package require ctext}]} {
	check tklib {
	    # ctext stands in for the whole script library
	    ctext .ct -width 20 -height 4
	    .ct insert end whale
	    set r [list ctext [package present ctext] \
		text [string trim [.ct get 1.0 end]]]
	    destroy .ct
	    set r
	}
    } else {
	say "skip tklib: not compiled in"
    }
    if {![catch {package require Tkhtml}]} {
	check tkhtml {
	    html .html
	    .html parse -final {<html><body>
		<h1>Whale</h1><p class="b">batteries included</p>
	    </body></html>}
	    update
	    set h1 [.html search h1]
	    set ps [.html search p.b]
	    set r [list version [package present Tkhtml] \
		h1 [llength $h1] p.b [llength $ps]]
	    destroy .html
	    set r
	}
    } else {
	say "skip tkhtml: not compiled in"
    }
    if {![catch {package require img::jpeg}]} {
	check tkimg {
	    # jpeg and tiff live outside the Tk core (unlike png/gif),
	    # so a roundtrip proves the Img handlers and their support
	    # packages (jpegtcl; tifftcl pulling zlibtcl) really work.
	    package require img::tiff
	    image create photo src -width 16 -height 16
	    src put #ff0000 -to 0 0 16 16
	    set jpg [src data -format jpeg]
	    set tif [src data -format tiff]
	    image create photo back -data $jpg
	    set px [back get 8 8]
	    image delete src back
	    if {[lindex $px 0] < 200} {error "jpeg roundtrip lost red: $px"}
	    list jpeg [string length $jpg] tiff [string length $tif] px $px
	}
    } else {
	say "skip tkimg: not compiled in"
    }
} else {
    say "skip GUI: no DISPLAY or Tk not compiled in"
}

say [expr {$failed ? "SELFTEST FAILED ($failed)" : "SELFTEST PASSED"}]
exit $failed
