#!/bin/sh
# Unit test for uolt-touch: create missing files, update the mtime of existing
# ones, honour -c (no-create), and error on a missing operand.
set -u
BIN=${UOLT_TOUCH:-${BUILD:-./build}/uolt-touch}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

# Create a missing file.
"$BIN" "$tmp/new"; { [ $? -eq 0 ] && [ -f "$tmp/new" ]; } || { echo "FAIL unit: create"; fail=1; }

# Update the mtime of an existing file (seed an old time via the system touch).
echo x >"$tmp/old"
touch -t 202001010000 "$tmp/old" 2>/dev/null || touch "$tmp/old"
b=$(mtime "$tmp/old")
sleep 1
"$BIN" "$tmp/old"; a=$(mtime "$tmp/old")
[ "$a" -gt "$b" ] 2>/dev/null || { echo "FAIL unit: mtime not advanced ($b -> $a)"; fail=1; }
# Content is untouched.
[ "$(cat "$tmp/old")" = "x" ] || { echo "FAIL unit: content changed"; fail=1; }

# -c does not create a missing file and is not an error.
"$BIN" -c "$tmp/nc"; { [ $? -eq 0 ] && [ ! -e "$tmp/nc" ]; } || { echo "FAIL unit: -c created/erred"; fail=1; }

# -c updates an existing file.
echo y >"$tmp/ex"; touch -t 202001010000 "$tmp/ex" 2>/dev/null || touch "$tmp/ex"
b=$(mtime "$tmp/ex"); sleep 1; "$BIN" -c "$tmp/ex"; a=$(mtime "$tmp/ex")
[ "$a" -gt "$b" ] 2>/dev/null || { echo "FAIL unit: -c did not update existing"; fail=1; }

# Multiple operands.
"$BIN" "$tmp/a" "$tmp/b"; { [ -f "$tmp/a" ] && [ -f "$tmp/b" ]; } || { echo "FAIL unit: multiple"; fail=1; }

# No operand -> error.
"$BIN" >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL unit: no operand exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/touch"
exit "$fail"
