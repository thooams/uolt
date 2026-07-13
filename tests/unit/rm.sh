#!/bin/sh
# Unit test for uolt-rm: remove files, -f ignores missing operands, a directory
# is an error (no recursion in v1), and the missing-operand rules.
set -u
BIN=${UOLT_RM:-${BUILD:-./build}/uolt-rm}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

touch a b c; mkdir d

"$BIN" a; { [ $? -eq 0 ] && [ ! -e a ]; } || { echo "FAIL unit: remove file"; fail=1; }
"$BIN" b c; { [ $? -eq 0 ] && [ ! -e b ] && [ ! -e c ]; } || { echo "FAIL unit: remove multiple"; fail=1; }

# Missing file: error without -f, silent success with -f.
"$BIN" gone 2>/dev/null; [ $? -ne 0 ] || { echo "FAIL unit: missing exit 0"; fail=1; }
"$BIN" -f gone 2>/dev/null; [ $? -eq 0 ] || { echo "FAIL unit: -f missing not ok"; fail=1; }

# Directory is an error and is preserved (no -r in v1).
"$BIN" d 2>/dev/null; { [ $? -ne 0 ] && [ -d d ]; } || { echo "FAIL unit: directory removed/ok"; fail=1; }
"$BIN" -f d 2>/dev/null; [ -d d ] || { echo "FAIL unit: -f removed directory"; fail=1; }

# No operand: error normally, no-op under -f.
"$BIN" >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL unit: no operand exit 0"; fail=1; }
"$BIN" -f >/dev/null 2>&1; [ $? -eq 0 ] || { echo "FAIL unit: -f no operand not 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/rm"
exit "$fail"
