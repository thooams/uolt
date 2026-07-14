#!/bin/sh
# Differential test: uolt-comm matches the system comm on two sorted files for
# every combination of the -1/-2/-3 column-suppression flags.
set -u
BIN=${UOLT_COMM:-${BUILD:-./build}/uolt-comm}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/comm; [ -x /bin/comm ] && REF=/bin/comm
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# Two sorted files with shared and unique lines (LC_ALL=C sorted).
printf 'aa\nbb\ncc\nee\ngg\n'       >"$tmp/a"
printf 'bb\ncc\ndd\nff\ngg\nhh\n'   >"$tmp/b"

compare() {
    u=$("$BIN" "$@" "$tmp/a" "$tmp/b" 2>/dev/null)
    r=$("$REF" "$@" "$tmp/a" "$tmp/b" 2>/dev/null)
    [ "$u" = "$r" ] || { echo "FAIL diff [$*]: differs"; fail=1; }
}

compare
compare -1
compare -2
compare -3
compare -12
compare -13
compare -23
compare -123

# Empty and identical file edge cases.
: >"$tmp/e"
u=$("$BIN" "$tmp/a" "$tmp/e" 2>/dev/null); r=$("$REF" "$tmp/a" "$tmp/e" 2>/dev/null)
[ "$u" = "$r" ] || { echo "FAIL diff [empty file2]"; fail=1; }
u=$("$BIN" "$tmp/a" "$tmp/a" 2>/dev/null); r=$("$REF" "$tmp/a" "$tmp/a" 2>/dev/null)
[ "$u" = "$r" ] || { echo "FAIL diff [identical]"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS differential/comm (ref: $REF)"
exit "$fail"
