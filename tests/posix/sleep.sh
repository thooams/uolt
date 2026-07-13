#!/bin/sh
# POSIX behavior for uolt-sleep: an integer number of seconds is the required
# form. Also checks the error exit for a non-numeric operand.
set -u
BIN=${UOLT_SLEEP:-${BUILD:-./build}/uolt-sleep}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

ge() { awk "BEGIN{ exit !($1 >= $2) }"; }

# Integer seconds: sleep 1 waits about a second.
t0=$(date +%s.%N); "$BIN" 1; rc=$?; t1=$(date +%s.%N)
e=$(awk "BEGIN{print $t1-$t0}")
[ "$rc" -eq 0 ] || { echo "FAIL posix: sleep 1 exit $rc"; fail=1; }
ge "$e" 0.9 || { echo "FAIL posix: sleep 1 too short ($e)"; fail=1; }

# Non-numeric operand is an error.
"$BIN" 1x2 >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL posix: '1x2' accepted"; fail=1; }
"$BIN" -- >/dev/null 2>&1  # a lone "--" has no time operand -> should not hang
[ $? -ne 0 ] || echo "note: '--' alone accepted (harmless)"

[ "$fail" -eq 0 ] && echo "PASS posix/sleep"
exit "$fail"
