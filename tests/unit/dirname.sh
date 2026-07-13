#!/bin/sh
# Unit test for uolt-dirname: the directory part of a path, trailing-slash and
# all-slash handling, no-slash -> ".", empty -> ".".
set -u
BIN=${UOLT_DIRNAME:-${BUILD:-./build}/uolt-dirname}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

check() {
    want=$1; shift
    got=$("$BIN" "$@")
    [ "$got" = "$want" ] || { echo "FAIL unit: dirname $* -> [$got], want [$want]"; fail=1; }
}

check /usr    /usr/lib
check /usr    /usr/lib/
check /       /usr/
check .       usr
check /       /
check /       //
check /       ///
check a       a/b
check a       a/b/
check .       a
check /       /a
check .       a/
check a       a//b
check a//b    a//b//c
check .       ""
check /a/b    /a/b/c/

# Missing operand -> nonzero exit, stderr diagnostic.
"$BIN" >/dev/null 2>/tmp/uolt_dn.$$; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL unit: missing operand exit 0"; fail=1; }
[ -s /tmp/uolt_dn.$$ ] || { echo "FAIL unit: no diagnostic"; fail=1; }
rm -f /tmp/uolt_dn.$$

[ "$fail" -eq 0 ] && echo "PASS unit/dirname"
exit "$fail"
