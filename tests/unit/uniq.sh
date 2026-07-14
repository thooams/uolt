#!/bin/sh
# Unit test for uolt-uniq: collapse adjacent duplicates, -c count, -d duplicated,
# -u unique, stdin and file input.
set -u
BIN=${UOLT_UNIQ:-${BUILD:-./build}/uolt-uniq}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
norm() { tr -s ' ' | sed 's/^ //;s/ $//'; }

[ "$(printf 'a\na\nb\nb\nb\nc\na\n' | "$BIN" | tr '\n' ',')" = "a,b,c,a," ] \
    || { echo "FAIL unit: default"; fail=1; }

# Non-adjacent duplicates are NOT merged.
[ "$(printf 'a\nb\na\n' | "$BIN" | tr '\n' ',')" = "a,b,a," ] || { echo "FAIL unit: non-adjacent"; fail=1; }

# -c counts (whitespace-normalized).
[ "$(printf 'a\na\nb\nc\nc\n' | "$BIN" -c | norm | tr '\n' ',')" = "2 a,1 b,2 c," ] \
    || { echo "FAIL unit: -c"; fail=1; }

# -d: only runs that repeat.
[ "$(printf 'a\na\nb\nc\nc\n' | "$BIN" -d | tr '\n' ',')" = "a,c," ] || { echo "FAIL unit: -d"; fail=1; }

# -u: only runs that occur once.
[ "$(printf 'a\na\nb\nc\nc\n' | "$BIN" -u | tr '\n' ',')" = "b," ] || { echo "FAIL unit: -u"; fail=1; }

# File input.
printf 'p\np\nq\n' >"$tmp/f"
[ "$("$BIN" "$tmp/f" | tr '\n' ',')" = "p,q," ] || { echo "FAIL unit: file input"; fail=1; }

# A final line without a trailing newline is still handled.
printf 'z\nz\nw' >"$tmp/g"
[ "$("$BIN" "$tmp/g" | tr '\n' ',')" = "z,w," ] || { echo "FAIL unit: no trailing newline"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/uniq"
exit "$fail"
