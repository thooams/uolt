#!/bin/sh
# Unit test for uolt-false: exit 1, no stdout, no stderr.
set -u
BIN=${UOLT_FALSE:-./build/uolt-false}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

"$BIN" >"$tmp/out" 2>"$tmp/err"
rc=$?

fail=0
[ "$rc" -eq 1 ]     || { echo "FAIL unit: exit $rc, expected 1"; fail=1; }
[ ! -s "$tmp/out" ] || { echo "FAIL unit: stdout not empty"; fail=1; }
[ ! -s "$tmp/err" ] || { echo "FAIL unit: stderr not empty"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/false"
exit "$fail"
