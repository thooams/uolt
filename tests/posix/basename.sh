#!/bin/sh
# POSIX behavior for uolt-basename, following the standard algorithm: strip
# trailing slashes, collapse an all-slash string to "/", take the last
# component, and remove a matching suffix unless it equals the component.
set -u
BIN=${UOLT_BASENAME:-${BUILD:-./build}/uolt-basename}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

check() {
    want=$1; shift
    got=$("$BIN" "$@")
    [ "$got" = "$want" ] || { echo "FAIL posix: basename $* -> [$got], want [$want]"; fail=1; }
}

# No leading slash, no component separators.
check file       file
check file       file.ext .ext
# Interior slashes and repeated separators.
check c          a/b/c
check c          a//b///c
# Trailing slashes are ignored.
check b          a/b////
# The suffix is only stripped from the end.
check libfoo     libfoo .a
check foo        foo.a .a
# A suffix equal to the whole component is not stripped.
check .a         .a .a
# A dot component.
check .          .
check ..         ..
# Suffix longer than the component -> unchanged.
check x          x .xxx

[ "$fail" -eq 0 ] && echo "PASS posix/basename"
exit "$fail"
