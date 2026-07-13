#!/bin/sh
# Unit test for uolt-ls: list directory entries (one per line), -a for hidden,
# print a file operand's name, and the missing-operand diagnostic. Output order
# is not defined (v1 does not sort), so comparisons are done as sorted sets.
set -u
BIN=${UOLT_LS:-${BUILD:-./build}/uolt-ls}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

touch b a c; mkdir sub; touch .hidden sub/inner

# Default listing (no hidden), as a sorted set.
got=$("$BIN" | sort | tr '\n' ' ')
[ "$got" = "a b c sub " ] || { echo "FAIL unit: default listing [$got]"; fail=1; }

# -a includes dot entries.
got=$("$BIN" -a | sort | tr '\n' ' ')
[ "$got" = ". .. .hidden a b c sub " ] || { echo "FAIL unit: -a listing [$got]"; fail=1; }

# A named directory lists its own entries.
got=$("$BIN" sub | sort | tr '\n' ' ')
[ "$got" = "inner " ] || { echo "FAIL unit: named dir [$got]"; fail=1; }

# A file operand prints its name.
got=$("$BIN" a); rc=$?
{ [ "$rc" -eq 0 ] && [ "$got" = "a" ]; } || { echo "FAIL unit: file operand [$got]"; fail=1; }

# A path with a directory prefix prints the operand as given.
got=$("$BIN" sub/inner)
[ "$got" = "sub/inner" ] || { echo "FAIL unit: file path [$got]"; fail=1; }

# Missing operand -> diagnostic + nonzero exit.
"$BIN" nope >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL unit: missing operand exit 0"; fail=1; }

# An empty directory lists nothing, exit 0.
mkdir empty
got=$("$BIN" empty); rc=$?
{ [ "$rc" -eq 0 ] && [ -z "$got" ]; } || { echo "FAIL unit: empty dir [$got]"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/ls"
exit "$fail"
