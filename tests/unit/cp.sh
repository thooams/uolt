#!/bin/sh
# Unit test for uolt-cp: copy file contents, truncate an existing target, handle
# binary data, and the operand / error cases.
set -u
BIN=${UOLT_CP:-${BUILD:-./build}/uolt-cp}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

printf 'hello\nworld\n' >a
"$BIN" a b; { [ $? -eq 0 ] && cmp -s a b; } || { echo "FAIL unit: copy"; fail=1; }
# Source is left in place.
[ -f a ] || { echo "FAIL unit: source removed"; fail=1; }

# Truncate/overwrite an existing, longer target.
printf 'a much longer previous content\n' >c
"$BIN" a c; { [ $? -eq 0 ] && cmp -s a c; } || { echo "FAIL unit: truncate target"; fail=1; }

# Binary-safe, multi-block copy.
head -c 200000 /dev/urandom >big 2>/dev/null || dd if=/dev/urandom of=big bs=1000 count=200 2>/dev/null
"$BIN" big big2; cmp -s big big2 || { echo "FAIL unit: big/binary copy"; fail=1; }

# Empty file.
: >empty; "$BIN" empty ecopy; { [ $? -eq 0 ] && [ ! -s ecopy ]; } || { echo "FAIL unit: empty copy"; fail=1; }

# Errors.
"$BIN" nope dest 2>/dev/null;  [ $? -ne 0 ] || { echo "FAIL unit: missing source exit 0"; fail=1; }
mkdir d; "$BIN" a d 2>/dev/null; [ $? -ne 0 ] || { echo "FAIL unit: dir target exit 0"; fail=1; }
"$BIN" a 2>/dev/null;          [ $? -ne 0 ] || { echo "FAIL unit: one operand exit 0"; fail=1; }
"$BIN" >/dev/null 2>&1;        [ $? -ne 0 ] || { echo "FAIL unit: no operand exit 0"; fail=1; }

# -r: recursive directory tree copy.
mkdir -p tree/a/b; printf '1' >tree/x; printf '2' >tree/a/y; printf '3' >tree/a/b/z
"$BIN" -r tree dtree; rc=$?
{ [ "$rc" -eq 0 ] && [ "$(cat dtree/x)" = 1 ] && [ "$(cat dtree/a/y)" = 2 ] && [ "$(cat dtree/a/b/z)" = 3 ]; } \
    || { echo "FAIL unit: -r tree"; fail=1; }
[ -d dtree/a/b ] || { echo "FAIL unit: -r structure"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/cp"
exit "$fail"
