#!/bin/sh
# POSIX behavior for uolt-wc: counts always print in the order lines, words,
# bytes regardless of flag order; flags combine; default is all three; "--" ends
# options; unreadable operand -> nonzero exit.
set -u
BIN=${UOLT_WC:-${BUILD:-./build}/uolt-wc}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
norm() { tr -s ' ' | sed 's/^ //;s/ $//'; }

printf 'a b c\nd e\n' >"$tmp/a"    # 2 lines, 5 words, 10 bytes

# Order is always l w c, even when flags are given as -c -l (bytes,lines asked).
[ "$("$BIN" -c -l "$tmp/a" | norm)" = "2 10 $tmp/a" ] || { echo "FAIL posix: fixed order"; fail=1; }

# Combined flag equals separate flags.
a=$("$BIN" -lw "$tmp/a" | norm); b=$("$BIN" -l -w "$tmp/a" | norm)
[ "$a" = "$b" ] || { echo "FAIL posix: -lw vs -l -w"; fail=1; }
[ "$a" = "2 5 $tmp/a" ] || { echo "FAIL posix: -lw counts [$a]"; fail=1; }

# Default prints all three.
[ "$("$BIN" "$tmp/a" | norm)" = "2 5 10 $tmp/a" ] || { echo "FAIL posix: default"; fail=1; }

# "--" ends options.
[ "$("$BIN" -l -- "$tmp/a" | norm)" = "2 $tmp/a" ] || { echo "FAIL posix: -- end options"; fail=1; }

# Tabs and multiple spaces are word separators; CR/VT/FF are blanks too.
printf 'x\ty  z\n' >"$tmp/t"
[ "$("$BIN" -w "$tmp/t" | norm)" = "3 $tmp/t" ] || { echo "FAIL posix: tab/space words"; fail=1; }

# Bytes are exact (binary-safe: NUL counted).
printf 'a\000b' >"$tmp/n"
[ "$("$BIN" -c "$tmp/n" | norm)" = "3 $tmp/n" ] || { echo "FAIL posix: NUL byte count"; fail=1; }

# Unreadable operand -> nonzero exit.
"$BIN" "$tmp/does-not-exist" >/dev/null 2>&1; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL posix: unreadable exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS posix/wc"
exit "$fail"
