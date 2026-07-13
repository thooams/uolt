#!/bin/sh
# Behavior test for uolt-yes. `yes` is not a POSIX utility; this pins the chosen
# semantics (GNU-style: join all operands with spaces; "y" when none), which is
# also what the Linux reference does.
set -u
BIN=${UOLT_YES:-${BUILD:-./build}/uolt-yes}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# Default line is exactly "y\n".
"$BIN" | head -1 >"$tmp/o"
printf 'y\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL posix: default line"; fail=1; }

# Operands with internal spacing preserved inside each argument, joined by one
# space between arguments.
"$BIN" "two words" x | head -1 >"$tmp/o"
printf 'two words x\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL posix: spacing/join"; fail=1; }

# Every line is identical across a sample.
"$BIN" repeat me | head -5000 >"$tmp/o"
[ "$(sort -u "$tmp/o")" = "repeat me" ] || { echo "FAIL posix: lines differ"; fail=1; }

# A long single operand (exercises the piecewise fallback for very long lines).
long=$(head -c 100000 /dev/zero | tr '\0' 'z')
"$BIN" "$long" | head -3 >"$tmp/o"
[ "$(wc -l <"$tmp/o")" -eq 3 ] || { echo "FAIL posix: long-line line count"; fail=1; }
[ "$(head -1 "$tmp/o")" = "$long" ] || { echo "FAIL posix: long line mangled"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS posix/yes"
exit "$fail"
