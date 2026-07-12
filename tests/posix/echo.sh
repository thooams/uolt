#!/bin/sh
# POSIX-ish behavior for uolt-echo: -n suppresses the trailing newline; spacing
# and exit status are correct; no escape processing (POSIX, not GNU -e).
set -u
BIN=${UOLT_ECHO:-${BUILD:-./build}/uolt-echo}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# -n: no trailing newline.
printf 'foo' >"$tmp/want"
"$BIN" -n foo >"$tmp/got"
cmp -s "$tmp/got" "$tmp/want" || { echo "FAIL posix: -n should suppress newline"; fail=1; }

# -n with multiple args.
printf 'a b' >"$tmp/want"
"$BIN" -n a b >"$tmp/got"
cmp -s "$tmp/got" "$tmp/want" || { echo "FAIL posix: -n multi-arg"; fail=1; }

# -n alone: no output at all.
"$BIN" -n >"$tmp/got"
[ ! -s "$tmp/got" ] || { echo "FAIL posix: '-n' alone should print nothing"; fail=1; }

# No escape processing: backslash-n stays literal (two chars), not a newline.
printf 'x\\ny\n' >"$tmp/want"
"$BIN" 'x\ny' >"$tmp/got"
cmp -s "$tmp/got" "$tmp/want" || { echo "FAIL posix: must not interpret escapes"; fail=1; }

# Exit status is success.
"$BIN" anything >/dev/null; [ $? -eq 0 ] || { echo "FAIL posix: exit != 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS posix/echo"
exit "$fail"
