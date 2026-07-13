#!/bin/sh
# Unit test for uolt-sleep: it actually waits about the requested time, sums
# multiple operands, accepts unit suffixes, and errors on bad or missing input.
set -u
BIN=${UOLT_SLEEP:-${BUILD:-./build}/uolt-sleep}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

elapsed() {  # prints seconds elapsed running "$@"
    t0=$(date +%s.%N); "$@" >/dev/null 2>&1; t1=$(date +%s.%N)
    awk "BEGIN{ d=$t1-$t0; print d }"
}
ge() { awk "BEGIN{ exit !($1 >= $2) }"; }
lt() { awk "BEGIN{ exit !($1 <  $2) }"; }

# sleep 0 returns quickly and succeeds.
"$BIN" 0 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL unit: sleep 0 exit $rc"; fail=1; }
e=$(elapsed "$BIN" 0)
lt "$e" 0.2 || { echo "FAIL unit: sleep 0 too slow ($e)"; fail=1; }

# sleep 0.3 waits at least ~0.25s and not absurdly long.
e=$(elapsed "$BIN" 0.3)
ge "$e" 0.25 || { echo "FAIL unit: sleep 0.3 too short ($e)"; fail=1; }
lt "$e" 2.0  || { echo "FAIL unit: sleep 0.3 too long ($e)"; fail=1; }

# Multiple operands are summed.
e=$(elapsed "$BIN" 0.15 0.15)
ge "$e" 0.25 || { echo "FAIL unit: sum operands too short ($e)"; fail=1; }

# Unit suffix.
e=$(elapsed "$BIN" 0.25s)
ge "$e" 0.2 || { echo "FAIL unit: 0.25s suffix too short ($e)"; fail=1; }

# Bad operand -> exit 1, quickly.
"$BIN" nope >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL unit: bad operand exit 0"; fail=1; }
e=$(elapsed "$BIN" nope)
lt "$e" 0.2 || { echo "FAIL unit: bad operand slept ($e)"; fail=1; }

# No operand -> error.
"$BIN" >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL unit: no operand exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/sleep"
exit "$fail"
