#!/bin/sh
# Unit test for uolt-yes: repeats "y" (or the operands joined by spaces) plus a
# newline, forever. Output is sampled through `head`, which closes the pipe and
# stops the tool via SIGPIPE.
set -u
BIN=${UOLT_YES:-${BUILD:-./build}/uolt-yes}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# No operands -> "y" on every line.
"$BIN" | head -5 >"$tmp/o"
printf 'y\ny\ny\ny\ny\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: default not 'y' lines"; fail=1; }

# Single operand.
"$BIN" hello | head -3 >"$tmp/o"
printf 'hello\nhello\nhello\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: single operand"; fail=1; }

# Multiple operands are joined by single spaces (GNU behavior).
"$BIN" a b c | head -2 >"$tmp/o"
printf 'a b c\na b c\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL unit: joined operands"; fail=1; }

# Each repetition ends with a newline (last sampled byte is 0x0a).
"$BIN" foo | head -10 >"$tmp/o"
last=$(tail -c1 "$tmp/o" | od -An -tu1 | tr -d ' ')
[ "$last" = "10" ] || { echo "FAIL unit: no trailing newline"; fail=1; }

# A large sample stays consistent (buffer replication has no seams).
"$BIN" ab | head -100000 >"$tmp/o"
[ "$(sort -u "$tmp/o")" = "ab" ] || { echo "FAIL unit: inconsistent lines in large sample"; fail=1; }
[ "$(wc -l <"$tmp/o")" -eq 100000 ] || { echo "FAIL unit: wrong line count in sample"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/yes"
exit "$fail"
