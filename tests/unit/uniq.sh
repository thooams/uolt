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

# -i: case-insensitive run detection (keeps the first spelling).
[ "$(printf 'Apple\napple\nAPPLE\nbanana\n' | "$BIN" -i | tr '\n' ',')" = "Apple,banana," ] \
    || { echo "FAIL unit: -i"; fail=1; }
[ "$(printf 'a\nA\nb\n' | "$BIN" -ic | norm | tr '\n' ',')" = "2 a,1 b," ] \
    || { echo "FAIL unit: -ic"; fail=1; }

# File input.
printf 'p\np\nq\n' >"$tmp/f"
[ "$("$BIN" "$tmp/f" | tr '\n' ',')" = "p,q," ] || { echo "FAIL unit: file input"; fail=1; }

# -f N: ignore the first N fields when comparing (the whole line is printed).
[ "$(printf '1 a\n2 a\n3 b\n' | "$BIN" -f1 | tr '\n' ',')" = "1 a,3 b," ] \
    || { echo "FAIL unit: -f1"; fail=1; }
[ "$(printf 'x y z\nq y w\nx w z\n' | "$BIN" -f2 | tr '\n' ',')" = "x y z,q y w,x w z," ] \
    || { echo "FAIL unit: -f2"; fail=1; }

# -s N: ignore the first N characters when comparing.
[ "$(printf 'axfoo\nbxfoo\ncybar\n' | "$BIN" -s2 | tr '\n' ',')" = "axfoo,cybar," ] \
    || { echo "FAIL unit: -s2"; fail=1; }

# -f with -c counts the collapsed run.
[ "$(printf 'a k\nb k\nc j\n' | "$BIN" -c -f1 | norm | tr '\n' ',')" = "2 a k,1 c j," ] \
    || { echo "FAIL unit: -c -f1"; fail=1; }

# A final line without a trailing newline is still handled.
printf 'z\nz\nw' >"$tmp/g"
[ "$("$BIN" "$tmp/g" | tr '\n' ',')" = "z,w," ] || { echo "FAIL unit: no trailing newline"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/uniq"
exit "$fail"
