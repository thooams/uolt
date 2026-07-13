#!/bin/sh
# Unit test for uolt-basename: final path component, trailing-slash handling,
# all-slash and empty strings, and suffix removal.
set -u
BIN=${UOLT_BASENAME:-${BUILD:-./build}/uolt-basename}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

check() {
    want=$1; shift
    got=$("$BIN" "$@")
    [ "$got" = "$want" ] || { echo "FAIL unit: basename $* -> [$got], want [$want]"; fail=1; }
}

check lib   /usr/lib
check lib   /usr/lib/
check usr   /usr/
check usr   usr
check /     /
check /     //
check /     ///
check a     a.txt .txt
check a.txt a.txt .x        # suffix not a tail match -> unchanged
check .txt  .txt .txt       # component equals suffix -> not stripped
check bar   /foo/bar.c .c
check b     a//b//
check c.tar /a/b/c.tar.gz .gz

# Empty string -> empty output (just a newline).
"$BIN" "" >/tmp/uolt_bn.$$ 2>/dev/null
[ "$(cat /tmp/uolt_bn.$$)" = "" ] || { echo "FAIL unit: empty string"; fail=1; }
last=$(tail -c1 /tmp/uolt_bn.$$ | od -An -tu1 | tr -d ' ')
[ "$last" = "10" ] || { echo "FAIL unit: empty string missing newline"; fail=1; }
rm -f /tmp/uolt_bn.$$

# Missing operand -> nonzero exit, stderr diagnostic.
"$BIN" >/dev/null 2>/tmp/uolt_bne.$$; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL unit: missing operand exit 0"; fail=1; }
[ -s /tmp/uolt_bne.$$ ] || { echo "FAIL unit: no diagnostic"; fail=1; }
rm -f /tmp/uolt_bne.$$

[ "$fail" -eq 0 ] && echo "PASS unit/basename"
exit "$fail"
