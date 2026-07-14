#!/bin/sh
# Unit test for uolt-seq: integer sequences with 1/2/3 operands, negative and
# descending steps, empty ranges, and error handling.
set -u
BIN=${UOLT_SEQ:-${BUILD:-./build}/uolt-seq}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

check() {
    want=$1; shift
    got=$("$BIN" "$@" | tr '\n' ' ')
    [ "$got" = "$want" ] || { echo "FAIL unit: seq $* -> [$got], want [$want]"; fail=1; }
}

check "1 2 3 4 5 "        5
check "2 3 4 5 6 "        2 6
check "1 3 5 7 9 "        1 2 9
check "5 4 3 2 1 "        5 -1 1
check "-3 -2 -1 0 1 2 3 " -3 3
check "3 "               3 3          # single-element range
check ""                 5 1          # empty (ascending, first > last)
check ""                 1 -1 5       # empty (descending step, first < last)

# -s separator (GNU style: between numbers, trailing newline). uolt is GNU-style
# on every OS, so the expected output is fixed.
[ "$("$BIN" -s , 1 5)" = "1,2,3,4,5" ]   || { echo "FAIL unit: -s comma"; fail=1; }
[ "$("$BIN" -s : 1 3)" = "1:2:3" ]       || { echo "FAIL unit: -s colon"; fail=1; }
[ "$("$BIN" -s- 1 3)" = "1-2-3" ]        || { echo "FAIL unit: -s attached"; fail=1; }
[ "$("$BIN" -s , 3 1)" = "" ]            || { echo "FAIL unit: -s empty range"; fail=1; }

# -w equal-width zero padding.
check "08 09 10 11 12 "  -w 8 12
check "-5 -4 -3 -2 -1 00 01 02 03 04 05 " -w -5 5
[ "$("$BIN" -w 1 100 | tail -1)" = "100" ] || { echo "FAIL unit: -w max"; fail=1; }
[ "$("$BIN" -w 1 100 | head -1)" = "001" ] || { echo "FAIL unit: -w pad"; fail=1; }

# Errors.
"$BIN" x 2>/dev/null;     [ $? -ne 0 ] || { echo "FAIL unit: non-integer exit 0"; fail=1; }
"$BIN" 1 0 5 2>/dev/null; [ $? -ne 0 ] || { echo "FAIL unit: zero increment exit 0"; fail=1; }
"$BIN" 2>/dev/null;       [ $? -ne 0 ] || { echo "FAIL unit: no operand exit 0"; fail=1; }
"$BIN" 1 2 3 4 2>/dev/null;[ $? -ne 0 ] || { echo "FAIL unit: too many operands exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/seq"
exit "$fail"
