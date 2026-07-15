#!/bin/sh
# Unit test for uolt-test: fixed expected exit codes (0 true, 1 false, 2 syntax
# error) for the string, integer, file, and logical primaries, plus the `[`
# invocation, independent of any system test.
set -u
BIN=${UOLT_TEST:-${BUILD:-./build}/uolt-test}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
: > "$d/empty"
printf 'hi\n' > "$d/full"
mkdir "$d/dir"
ln -s "$d/full" "$d/link"
chmod 0644 "$d/full"

ck() { # want, args...
    want=$1; shift
    "$BIN" "$@" >/dev/null 2>&1; got=$?
    [ "$got" -eq "$want" ] || { echo "FAIL unit: test $* -> $got, want $want"; fail=1; }
}

# Strings.
ck 0 -n abc;   ck 1 -n ""
ck 0 -z "";    ck 1 -z abc
ck 0 abc;      ck 1 ""                 # one-argument form
ck 0 a = a;    ck 1 a = b
ck 0 a != b;   ck 1 a != a

# Integers.
ck 0 5 -eq 5;  ck 1 5 -eq 6
ck 0 5 -ne 6;  ck 0 7 -gt 3;   ck 0 3 -lt 7
ck 0 5 -ge 5;  ck 0 4 -le 4;   ck 1 3 -gt 9
ck 0 -5 -lt 0; ck 0 -3 -eq -3
ck 2 5 -eq abc;  ck 2 x -lt 1          # non-integer -> syntax error

# Files.
ck 0 -e "$d/full";   ck 1 -e "$d/none"
ck 0 -f "$d/full";   ck 1 -f "$d/dir"
ck 0 -d "$d/dir";    ck 1 -d "$d/full"
ck 0 -s "$d/full";   ck 1 -s "$d/empty"
ck 0 -r "$d/full";   ck 1 -x "$d/full"
ck 0 -h "$d/link";   ck 1 -h "$d/full"
ck 0 -L "$d/link"

# Logical operators and grouping.
ck 0 ! -e "$d/none"; ck 1 ! -n abc
ck 0 -n a -a -n b;   ck 1 -n a -a -z b
ck 0 -z a -o -n b;   ck 1 -z a -o -z b
ck 0 '(' -n a ')';   ck 0 '(' 5 -eq 5 -o 1 -eq 2 ')'
ck 1 '(' -z a ')'

# Zero arguments -> false. A lone "(" or "-a" is the one-argument form (a
# non-empty string), so it is true, not an error.
ck 1
ck 0 '('
ck 0 -a

# The `[` invocation requires a closing `]`.
LB="$d/["
ln -s "$BIN" "$LB"
"$LB" -n abc ']' >/dev/null 2>&1;  [ $? -eq 0 ] || { echo "FAIL unit: [ -n abc ]"; fail=1; }
"$LB" 5 -gt 9 ']' >/dev/null 2>&1; [ $? -eq 1 ] || { echo "FAIL unit: [ 5 -gt 9 ]"; fail=1; }
"$LB" -n abc      >/dev/null 2>&1; [ $? -eq 2 ] || { echo "FAIL unit: [ without ]"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/test"
exit "$fail"
