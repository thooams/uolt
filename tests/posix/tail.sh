#!/bin/sh
# POSIX behavior for uolt-tail: -n number (joined or separate), -n +number,
# default 10, stdin when no operand, byte-transparent, nonzero on unreadable.
set -u
BIN=${UOLT_TAIL:-${BUILD:-./build}/uolt-tail}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

i=1; : >"$tmp/a"; while [ "$i" -le 20 ]; do echo "L$i" >>"$tmp/a"; i=$((i+1)); done

# Default 10 -> L11..L20.
"$BIN" "$tmp/a" >"$tmp/o"
[ "$(wc -l <"$tmp/o")" -eq 10 ]   || { echo "FAIL posix: default != 10"; fail=1; }
[ "$(head -1 "$tmp/o")" = "L11" ] || { echo "FAIL posix: default first line"; fail=1; }

# Joined and separate -n agree.
"$BIN" -n5 "$tmp/a"  >"$tmp/o1"
"$BIN" -n 5 "$tmp/a" >"$tmp/o2"
cmp -s "$tmp/o1" "$tmp/o2"        || { echo "FAIL posix: -n5 vs -n 5"; fail=1; }
[ "$(head -1 "$tmp/o1")" = "L16" ] || { echo "FAIL posix: -n5 wrong window"; fail=1; }

# -n +N start form (joined and separate).
"$BIN" -n +18 "$tmp/a" >"$tmp/o1"
"$BIN" -n+18 "$tmp/a"  >"$tmp/o2"
cmp -s "$tmp/o1" "$tmp/o2"          || { echo "FAIL posix: +N joined vs separate"; fail=1; }
printf 'L18\nL19\nL20\n' >"$tmp/want"
cmp -s "$tmp/o1" "$tmp/want"        || { echo "FAIL posix: -n +18 wrong"; fail=1; }

# -n0 prints nothing.
"$BIN" -n0 "$tmp/a" >"$tmp/o"
[ ! -s "$tmp/o" ] || { echo "FAIL posix: -n0 produced output"; fail=1; }

# No operand -> stdin.
printf '1\n2\n3\n' | "$BIN" -n1 >"$tmp/o"
printf '3\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL posix: stdin"; fail=1; }

# "--" ends options.
"$BIN" -n1 -- "$tmp/a" >"$tmp/o"
printf 'L20\n' >"$tmp/want"
cmp -s "$tmp/o" "$tmp/want" || { echo "FAIL posix: -- end of options"; fail=1; }

# Binary-safe within a line.
printf 'a\000b\377c\n' >"$tmp/bin"
"$BIN" -n1 "$tmp/bin" >"$tmp/o"
cmp -s "$tmp/o" "$tmp/bin" || { echo "FAIL posix: not binary-safe"; fail=1; }

# Unreadable operand -> nonzero exit.
"$BIN" "$tmp/does-not-exist" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL posix: unreadable exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS posix/tail"
exit "$fail"
