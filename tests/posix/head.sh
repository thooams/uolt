#!/bin/sh
# POSIX behavior for uolt-head: -n number (joined or separate), default 10,
# stdin when no operand, byte-transparent line copy, nonzero on unreadable.
set -u
BIN=${UOLT_HEAD:-${BUILD:-./build}/uolt-head}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

i=1; : >"$tmp/a"; while [ "$i" -le 20 ]; do echo "L$i" >>"$tmp/a"; i=$((i+1)); done

# Default is 10 lines.
"$BIN" "$tmp/a" >"$tmp/o"
[ "$(wc -l <"$tmp/o")" -eq 10 ] || { echo "FAIL posix: default != 10"; fail=1; }

# -nN joined and -n N separate agree.
"$BIN" -n5 "$tmp/a"  >"$tmp/o1"
"$BIN" -n 5 "$tmp/a" >"$tmp/o2"
cmp -s "$tmp/o1" "$tmp/o2" || { echo "FAIL posix: -n5 vs -n 5 differ"; fail=1; }
[ "$(wc -l <"$tmp/o1")" -eq 5 ] || { echo "FAIL posix: -n5 wrong count"; fail=1; }

# -n0 prints nothing.
"$BIN" -n0 "$tmp/a" >"$tmp/o"
[ ! -s "$tmp/o" ] || { echo "FAIL posix: -n0 produced output"; fail=1; }

# No operand -> stdin.
printf '1\n2\n3\n' | "$BIN" -n2 >"$tmp/o"
printf '1\n2\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL posix: no-operand stdin"; fail=1; }

# "--" ends options; the following token is a filename.
"$BIN" -n1 -- "$tmp/a" >"$tmp/o"
printf 'L1\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL posix: -- end of options"; fail=1; }

# Binary-safe within a line (NUL and high bytes copied verbatim).
printf 'a\000b\377c\n' >"$tmp/bin"
"$BIN" -n1 "$tmp/bin" >"$tmp/o"
cmp -s "$tmp/o" "$tmp/bin" || { echo "FAIL posix: not binary-safe"; fail=1; }

# Unreadable operand -> nonzero exit.
"$BIN" "$tmp/does-not-exist" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL posix: unreadable exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS posix/head"
exit "$fail"
