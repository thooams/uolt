#!/bin/sh
# Unit test for uolt-rmdir: remove empty dirs, refuse non-empty, -p removes the
# ancestor chain, and errors on missing dirs / missing operand. Uses relative
# operands inside a sandbox so -p does not climb into real parent directories.
set -u
BIN=${UOLT_RMDIR:-${BUILD:-./build}/uolt-rmdir}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

cd "$tmp" || exit 1

mkdir solo
"$BIN" solo; { [ $? -eq 0 ] && [ ! -d solo ]; } || { echo "FAIL unit: remove empty"; fail=1; }

mkdir full; touch full/f
"$BIN" full 2>/dev/null; { [ $? -ne 0 ] && [ -d full ]; } || { echo "FAIL unit: non-empty refused"; fail=1; }

mkdir -p a/b/c
"$BIN" -p a/b/c; { [ $? -eq 0 ] && [ ! -d a ]; } || { echo "FAIL unit: -p chain"; fail=1; }

# -p stops at a non-empty ancestor.
mkdir -p x/y/z; touch x/keep
"$BIN" -p x/y/z 2>/dev/null; rc=$?
{ [ "$rc" -ne 0 ] && [ ! -d x/y ] && [ -d x ]; } || { echo "FAIL unit: -p stop at non-empty"; fail=1; }

"$BIN" nope 2>/dev/null; [ $? -ne 0 ] || { echo "FAIL unit: missing dir exit 0"; fail=1; }
"$BIN" >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL unit: no operand exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/rmdir"
exit "$fail"
