#!/bin/sh
# POSIX conformance for uolt-false: arguments ignored; always exit 1; no output;
# behavior independent of stream state.
set -u
BIN=${UOLT_FALSE:-${BUILD:-./build}/uolt-false}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# 1. Arbitrary arguments are ignored, still exit 1 with no output.
"$BIN" a b --c -- --help --version >"$tmp/out" 2>"$tmp/err"
rc=$?
[ "$rc" -eq 1 ]     || { echo "FAIL posix: args caused exit $rc (expected 1)"; fail=1; }
[ ! -s "$tmp/out" ] || { echo "FAIL posix: args produced stdout"; fail=1; }
[ ! -s "$tmp/err" ] || { echo "FAIL posix: args produced stderr"; fail=1; }

# 2. stdin closed.
"$BIN" <&-; [ $? -eq 1 ] || { echo "FAIL posix: exit != 1 with stdin closed"; fail=1; }

# 3. streams to /dev/null.
"$BIN" </dev/null >/dev/null 2>/dev/null
[ $? -eq 1 ] || { echo "FAIL posix: exit != 1 with streams to /dev/null"; fail=1; }

# 4. stdout and stderr closed.
( "$BIN" >&- 2>&- ); [ $? -eq 1 ] || { echo "FAIL posix: exit != 1 with stdout/stderr closed"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS posix/false"
exit "$fail"
