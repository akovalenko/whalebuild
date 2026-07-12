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

if {![catch {package require nostr}]} {
    check nostr {
	set sec [string repeat 0 63]3    ;# BIP-340 test vector 0 key
	set ev [nostr::sign -sec $sec -kind 1 -content whale \
	    -created-at 1700000000]
	if {![nostr::verify $ev]} {error "verify failed"}
	if {[nostr::verify [string map {whale whal3} $ev]]} {
	    error "tampering not caught"
	}
	list npub [string range [nostr::pubkey $sec] 0 9]… sign+verify ok
    }
} else {
    say "skip nostr: not compiled in"
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
	destroy .
	set r
    }
} else {
    say "skip GUI: no DISPLAY or Tk not compiled in"
}

say [expr {$failed ? "SELFTEST FAILED ($failed)" : "SELFTEST PASSED"}]
exit $failed
