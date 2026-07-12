#!/bin/sh
# Unit test for uolt-cat: copies files and stdin verbatim to stdout, exit 0;
# a missing file sets a nonzero exit but does not stop the other operands.
set -u
BIN=${UOLT_CAT:-${BUILD:-./build}/uolt-cat}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

printf 'hello\nworld\n' >"$tmp/a"
printf 'second file\n'  >"$tmp/b"
: >"$tmp/empty"

# Single file: byte-for-byte, exit 0.
"$BIN" "$tmp/a" >"$tmp/o"; rc=$?
[ "$rc" -eq 0 ]          || { echo "FAIL unit: exit $rc"; fail=1; }
cmp -s "$tmp/o" "$tmp/a" || { echo "FAIL unit: single file mismatch"; fail=1; }

# Multiple files: concatenation in order.
cat "$tmp/a" "$tmp/b" >"$tmp/want"
"$BIN" "$tmp/a" "$tmp/b" >"$tmp/o"; rc=$?
[ "$rc" -eq 0 ]             || { echo "FAIL unit: multi exit $rc"; fail=1; }
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: concatenation mismatch"; fail=1; }

# Empty file: no output, exit 0.
"$BIN" "$tmp/empty" >"$tmp/o"; rc=$?
[ "$rc" -eq 0 ]     || { echo "FAIL unit: empty exit $rc"; fail=1; }
[ ! -s "$tmp/o" ]   || { echo "FAIL unit: empty file produced output"; fail=1; }

# No operands: copy stdin.
printf 'from stdin\n' | "$BIN" >"$tmp/o"; rc=$?
[ "$rc" -eq 0 ]                       || { echo "FAIL unit: stdin exit $rc"; fail=1; }
[ "$(cat "$tmp/o")" = "from stdin" ]  || { echo "FAIL unit: stdin not echoed"; fail=1; }

# "-" operand: stdin, interleaved with a file.
printf 'X\n' | "$BIN" "$tmp/b" - >"$tmp/o"; rc=$?
printf 'second file\nX\n' >"$tmp/want"
[ "$rc" -eq 0 ]             || { echo "FAIL unit: file+dash exit $rc"; fail=1; }
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: file + '-' mismatch"; fail=1; }

# Missing file: nonzero exit, diagnostic on stderr, but a following good file
# is still emitted.
"$BIN" "$tmp/nope" "$tmp/a" >"$tmp/o" 2>"$tmp/e"; rc=$?
[ "$rc" -ne 0 ]          || { echo "FAIL unit: missing file exit 0"; fail=1; }
[ -s "$tmp/e" ]          || { echo "FAIL unit: no stderr diagnostic"; fail=1; }
cmp -s "$tmp/o" "$tmp/a" || { echo "FAIL unit: good file dropped after error"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/cat"
exit "$fail"
