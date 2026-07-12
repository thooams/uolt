#!/bin/sh
# Unit test for uolt-true: exit 0, no stdout, no stderr (FR-001, FR-002, FR-003).
set -u
BIN=${UOLT_TRUE:-./build/uolt-true}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

"$BIN" >"$tmp/out" 2>"$tmp/err"
rc=$?

fail=0
[ "$rc" -eq 0 ]        || { echo "FAIL unit: exit $rc, expected 0"; fail=1; }
[ ! -s "$tmp/out" ]    || { echo "FAIL unit: stdout not empty"; fail=1; }
[ ! -s "$tmp/err" ]    || { echo "FAIL unit: stderr not empty"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/true"
exit "$fail"
