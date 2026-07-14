#!/bin/sh
# Unit test for uolt-tee: copy stdin to stdout and to each file, -a to append,
# and error handling for an unopenable file.
set -u
BIN=${UOLT_TEE:-${BUILD:-./build}/uolt-tee}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

printf 'l1\nl2\n' | "$BIN" a b >out; rc=$?
{ [ "$rc" -eq 0 ] && cmp -s out a && cmp -s out b; } || { echo "FAIL unit: fan-out"; fail=1; }
[ "$(cat a)" = "$(printf 'l1\nl2')" ] || { echo "FAIL unit: file content"; fail=1; }

# -a appends rather than truncating.
printf 'more\n' | "$BIN" -a a >/dev/null
[ "$(cat a | tr '\n' ,)" = "l1,l2,more," ] || { echo "FAIL unit: -a append"; fail=1; }

# Without -a, an existing file is truncated.
printf 'z\n' | "$BIN" a >/dev/null
[ "$(cat a)" = "z" ] || { echo "FAIL unit: truncate"; fail=1; }

# No file operand: acts like cat (stdin -> stdout).
[ "$(printf 'hey\n' | "$BIN")" = "hey" ] || { echo "FAIL unit: no-file passthrough"; fail=1; }

# Binary-safe, multi-block.
head -c 200000 /dev/urandom >big 2>/dev/null || dd if=/dev/urandom of=big bs=1000 count=200 2>/dev/null
"$BIN" bcopy <big >bout
{ cmp -s big bcopy && cmp -s big bout; } || { echo "FAIL unit: big/binary"; fail=1; }

# An unopenable file -> exit 1, but stdout still gets the data.
printf 'ok\n' | "$BIN" /nope/x >o3 2>/dev/null; rc=$?
{ [ "$rc" -ne 0 ] && [ "$(cat o3)" = "ok" ]; } || { echo "FAIL unit: bad file"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/tee"
exit "$fail"
