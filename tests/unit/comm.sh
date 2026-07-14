#!/bin/sh
# Unit test for uolt-comm: three-column compare of two sorted files, with the
# -1/-2/-3 column-suppression flags.
set -u
BIN=${UOLT_COMM:-${BUILD:-./build}/uolt-comm}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

printf 'apple\nbanana\ncherry\n' >a
printf 'banana\ncherry\ndate\n'  >b

# Default: col1=apple, col3=banana,cherry (2 tabs), col2=date (1 tab).
got=$("$BIN" a b | sed 's/\t/T/g' | tr '\n' ',')
[ "$got" = "apple,TTbanana,TTcherry,Tdate," ] || { echo "FAIL unit: default [$got]"; fail=1; }

# -12: only the common column, no indentation.
[ "$("$BIN" -12 a b | tr '\n' ,)" = "banana,cherry," ] || { echo "FAIL unit: -12"; fail=1; }

# -3: drop the common column; col1 (apple) and col2 (date, 1 tab).
got=$("$BIN" -3 a b | sed 's/\t/T/g' | tr '\n' ',')
[ "$got" = "apple,Tdate," ] || { echo "FAIL unit: -3 [$got]"; fail=1; }

# -23: only file1-unique lines, no indentation.
[ "$("$BIN" -23 a b | tr '\n' ,)" = "apple," ] || { echo "FAIL unit: -23"; fail=1; }

# Identical files -> everything is common.
[ "$("$BIN" -12 a a | tr '\n' ,)" = "apple,banana,cherry," ] || { echo "FAIL unit: identical"; fail=1; }

# Errors.
"$BIN" nope b >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL unit: missing file exit 0"; fail=1; }
"$BIN" a >/dev/null 2>&1;      [ $? -ne 0 ] || { echo "FAIL unit: one operand exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/comm"
exit "$fail"
