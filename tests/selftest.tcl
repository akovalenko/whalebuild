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
} else {
    say "skip tls: not compiled in"
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
}

if {$tcl_platform(platform) eq "windows"
	|| ([info exists env(DISPLAY)] && $env(DISPLAY) ne "")} {
    check Tk {
	package require Tk
	package present Tk
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
    say "skip GUI: no DISPLAY"
}

say [expr {$failed ? "SELFTEST FAILED ($failed)" : "SELFTEST PASSED"}]
exit $failed
