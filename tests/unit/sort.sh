#!/bin/sh
# Unit test for uolt-sort: C-locale lexicographic sort, -r reverse, duplicates
# preserved, stdin and file input.
set -u
BIN=${UOLT_SORT:-${BUILD:-./build}/uolt-sort}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

[ "$(printf 'banana\napple\ncherry\n' | "$BIN" | tr '\n' ',')" = "apple,banana,cherry," ] \
    || { echo "FAIL unit: basic"; fail=1; }

# Duplicates are kept.
[ "$(printf 'b\na\nb\na\n' | "$BIN" | tr '\n' ',')" = "a,a,b,b," ] \
    || { echo "FAIL unit: duplicates"; fail=1; }

# -r reverses.
[ "$(printf 'a\nb\nc\n' | "$BIN" -r | tr '\n' ',')" = "c,b,a," ] \
    || { echo "FAIL unit: -r"; fail=1; }

# Byte order (C locale): '10' sorts before '2'.
[ "$(printf '2\n10\n1\n' | "$BIN" | tr '\n' ',')" = "1,10,2," ] \
    || { echo "FAIL unit: byte order"; fail=1; }

# File input.
printf 'x\nm\na\n' >"$tmp/f"
[ "$("$BIN" "$tmp/f" | tr '\n' ',')" = "a,m,x," ] || { echo "FAIL unit: file input"; fail=1; }

# Two files are concatenated then sorted.
printf 'q\nb\n' >"$tmp/g"
[ "$("$BIN" "$tmp/f" "$tmp/g" | tr '\n' ',')" = "a,b,m,q,x," ] || { echo "FAIL unit: two files"; fail=1; }

# -n: numeric order (10 after 2, negatives first).
[ "$(printf '10\n2\n1\n100\n' | "$BIN" -n | tr '\n' ',')" = "1,2,10,100," ] \
    || { echo "FAIL unit: -n"; fail=1; }
[ "$(printf '5\n-3\n0\n-10\n' | "$BIN" -n | tr '\n' ',')" = "-10,-3,0,5," ] \
    || { echo "FAIL unit: -n negatives"; fail=1; }

# -u: drop duplicate lines.
[ "$(printf 'b\na\nb\na\nc\n' | "$BIN" -u | tr '\n' ',')" = "a,b,c," ] \
    || { echo "FAIL unit: -u"; fail=1; }

# -nu: numeric + unique.
[ "$(printf '3\n1\n3\n2\n1\n' | "$BIN" -nu | tr '\n' ',')" = "1,2,3," ] \
    || { echo "FAIL unit: -nu"; fail=1; }

# Empty input -> empty output, exit 0.
: | "$BIN" >"$tmp/o"; { [ $? -eq 0 ] && [ ! -s "$tmp/o" ]; } || { echo "FAIL unit: empty"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/sort"
exit "$fail"
