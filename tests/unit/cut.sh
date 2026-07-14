#!/bin/sh
# Unit test for uolt-cut: -c character positions and -f fields with -d, including
# ranges and open-ended ranges.
set -u
BIN=${UOLT_CUT:-${BUILD:-./build}/uolt-cut}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

ck() { want=$1; got=$2; [ "$got" = "$want" ] || { echo "FAIL unit: [$3] -> [$got] want [$want]"; fail=1; }; }

ck "abc"     "$(printf 'abcdef\n' | "$BIN" -c1-3)"   "-c1-3"
ck "adf"     "$(printf 'abcdef\n' | "$BIN" -c1,4,6)" "-c list"
ck "cdef"    "$(printf 'abcdef\n' | "$BIN" -c3-)"    "-c open"
ck "abc"     "$(printf 'abcdef\n' | "$BIN" -c-3)"    "-c from-start"
ck "a:c"     "$(printf 'a:b:c:d\n' | "$BIN" -f1,3 -d:)"  "-f list"
ck "2,3,4"   "$(printf '1,2,3,4\n'  | "$BIN" -f2- -d,)"  "-f open"
ck "b"       "$(printf 'a b c\n'    | "$BIN" -f2 -d' ')" "-f space delim"
ck "nodelim" "$(printf 'nodelim\n'  | "$BIN" -f1 -d:)"   "-f no-delim passthrough"

# LIST attached vs separate argument.
ck "ab" "$(printf 'abcd\n' | "$BIN" -c 1-2)" "-c separate list"

# Multiple lines.
[ "$(printf 'abc\ndef\n' | "$BIN" -c1 | tr '\n' ,)" = "a,d," ] || { echo "FAIL unit: multiline"; fail=1; }

# Missing mode is an error.
"$BIN" foo </dev/null >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL unit: no mode exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/cut"
exit "$fail"
