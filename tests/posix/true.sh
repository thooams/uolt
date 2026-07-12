#!/bin/sh
# POSIX conformance (FR-004, FR-005): arguments ignored; behavior independent of stream state.
set -u
BIN=${UOLT_TRUE:-${BUILD:-./build}/uolt-true}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# 1. Arbitrary arguments are ignored, still exit 0 with no output.
"$BIN" a b --c -- --help --version >"$tmp/out" 2>"$tmp/err"
rc=$?
[ "$rc" -eq 0 ]     || { echo "FAIL posix: args caused exit $rc"; fail=1; }
[ ! -s "$tmp/out" ] || { echo "FAIL posix: args produced stdout"; fail=1; }
[ ! -s "$tmp/err" ] || { echo "FAIL posix: args produced stderr"; fail=1; }

# 2. stdin closed.
"$BIN" <&-; [ $? -eq 0 ] || { echo "FAIL posix: exit != 0 with stdin closed"; fail=1; }

# 3. stdin from /dev/null, stdout/stderr to /dev/null.
"$BIN" </dev/null >/dev/null 2>/dev/null
[ $? -eq 0 ] || { echo "FAIL posix: exit != 0 with streams to /dev/null"; fail=1; }

# 4. stdout and stderr closed.
( "$BIN" >&- 2>&- ); [ $? -eq 0 ] || { echo "FAIL posix: exit != 0 with stdout/stderr closed"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS posix/true"
exit "$fail"
