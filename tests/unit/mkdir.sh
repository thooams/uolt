#!/bin/sh
# Unit test for uolt-mkdir: plain create, missing-parent failure, -p parents and
# idempotence, existing-target failure, and the missing-operand error.
set -u
BIN=${UOLT_MKDIR:-${BUILD:-./build}/uolt-mkdir}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

"$BIN" "$tmp/d1"; rc=$?
{ [ "$rc" -eq 0 ] && [ -d "$tmp/d1" ]; } || { echo "FAIL unit: plain create"; fail=1; }

# Missing parent without -p -> error, nothing created.
"$BIN" "$tmp/x/y/z" 2>/dev/null; rc=$?
{ [ "$rc" -ne 0 ] && [ ! -d "$tmp/x" ]; } || { echo "FAIL unit: missing parent"; fail=1; }

# -p creates the chain.
"$BIN" -p "$tmp/a/b/c"; rc=$?
{ [ "$rc" -eq 0 ] && [ -d "$tmp/a/b/c" ]; } || { echo "FAIL unit: -p chain"; fail=1; }

# -p on an existing directory is not an error.
"$BIN" -p "$tmp/a/b/c"; [ $? -eq 0 ] || { echo "FAIL unit: -p idempotent"; fail=1; }

# Existing target without -p -> error.
"$BIN" "$tmp/d1" 2>/dev/null; [ $? -ne 0 ] || { echo "FAIL unit: existing target exit 0"; fail=1; }

# No operand -> error.
"$BIN" >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL unit: no operand exit 0"; fail=1; }

# Multiple operands.
"$BIN" "$tmp/m1" "$tmp/m2"; { [ -d "$tmp/m1" ] && [ -d "$tmp/m2" ]; } || { echo "FAIL unit: multiple"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/mkdir"
exit "$fail"
