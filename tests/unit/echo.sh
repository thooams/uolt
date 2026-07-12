#!/bin/sh
# Unit test for uolt-echo: basic output shape and exit status.
set -u
BIN=${UOLT_ECHO:-${BUILD:-./build}/uolt-echo}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# Single argument -> "hello\n".
out=$("$BIN" hello); rc=$?
[ "$rc" -eq 0 ]       || { echo "FAIL unit: exit $rc"; fail=1; }
[ "$out" = "hello" ]  || { echo "FAIL unit: got [$out]"; fail=1; }

# Multiple arguments joined by single spaces.
printf 'a b c\n' >"$tmp/want"
"$BIN" a b c >"$tmp/got"
cmp -s "$tmp/got" "$tmp/want" || { echo "FAIL unit: multi-arg join"; fail=1; }

# No arguments -> a single newline.
"$BIN" >"$tmp/got"
printf '\n' >"$tmp/want"
cmp -s "$tmp/got" "$tmp/want" || { echo "FAIL unit: empty should emit newline"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/echo"
exit "$fail"
