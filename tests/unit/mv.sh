#!/bin/sh
# Unit test for uolt-mv: rename a file, overwrite an existing target, and the
# operand-count / missing-source errors.
set -u
BIN=${UOLT_MV:-${BUILD:-./build}/uolt-mv}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

printf 'hi\n' >a
"$BIN" a b; { [ $? -eq 0 ] && [ ! -e a ] && [ "$(cat b)" = "hi" ]; } || { echo "FAIL unit: rename"; fail=1; }

# Overwrite an existing target.
printf 'new\n' >c; printf 'old\n' >d
"$BIN" c d; { [ $? -eq 0 ] && [ ! -e c ] && [ "$(cat d)" = "new" ]; } || { echo "FAIL unit: overwrite"; fail=1; }

# Rename a directory (empty target name).
mkdir dir
"$BIN" dir dir2; { [ $? -eq 0 ] && [ -d dir2 ] && [ ! -e dir ]; } || { echo "FAIL unit: rename dir"; fail=1; }

# Move into a directory: dst is an existing directory -> dst/basename(src).
mkdir into; printf 'p\n' >p
"$BIN" p into; { [ $? -eq 0 ] && [ ! -e p ] && [ "$(cat into/p)" = "p" ]; } || { echo "FAIL unit: into-dir"; fail=1; }

# Multiple sources into a directory.
printf '1\n' >s1; printf '2\n' >s2
"$BIN" s1 s2 into; { [ "$(cat into/s1)" = "1" ] && [ "$(cat into/s2)" = "2" ] && [ ! -e s1 ] && [ ! -e s2 ]; } || { echo "FAIL unit: multi into-dir"; fail=1; }

# Source with a slash: only the basename is used inside the directory.
mkdir sub; printf 'q\n' >sub/q
"$BIN" sub/q into; { [ "$(cat into/q)" = "q" ] && [ ! -e sub/q ]; } || { echo "FAIL unit: into-dir basename"; fail=1; }

# Missing source.
"$BIN" nope dest 2>/dev/null; [ $? -ne 0 ] || { echo "FAIL unit: missing source exit 0"; fail=1; }

# Wrong operand counts.
"$BIN" only 2>/dev/null;      [ $? -ne 0 ] || { echo "FAIL unit: one operand exit 0"; fail=1; }
"$BIN" x y z 2>/dev/null;     [ $? -ne 0 ] || { echo "FAIL unit: three operands exit 0"; fail=1; }
"$BIN" >/dev/null 2>&1;       [ $? -ne 0 ] || { echo "FAIL unit: no operand exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/mv"
exit "$fail"
