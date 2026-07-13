#!/bin/sh
# POSIX behavior for uolt-dirname: strip trailing slashes, take everything before
# the last component, collapse to "/" or "." at the extremes.
set -u
BIN=${UOLT_DIRNAME:-${BUILD:-./build}/uolt-dirname}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

check() {
    want=$1; shift
    got=$("$BIN" "$@")
    [ "$got" = "$want" ] || { echo "FAIL posix: dirname $* -> [$got], want [$want]"; fail=1; }
}

check .        file
check dir      dir/file
check a/b      a/b/c
check a/b      a/b/c/
check a        a//b
check .        .
check .        ..
check /        /a
check /        /a/
check /usr/bin /usr/bin/tool
# Interior repeated slashes preserved in the directory part.
check a//b     a//b//c
check /        //x

[ "$fail" -eq 0 ] && echo "PASS posix/dirname"
exit "$fail"
