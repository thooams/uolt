#!/bin/sh
# Differential test: uolt-cut matches the system cut for -c and -f (with -d)
# selections, including ranges and open-ended ranges.
set -u
BIN=${UOLT_CUT:-${BUILD:-./build}/uolt-cut}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/cut; [ -x /bin/cut ] && REF=/bin/cut
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

printf 'alpha:beta:gamma:delta\none:two:three\nsolo\n' >"$tmp/f"
printf 'abcdefghij\n0123456789\nxy\n' >"$tmp/c"

compare() {
    file=$1; shift
    u=$("$BIN" "$@" "$file" 2>/dev/null)
    r=$("$REF" "$@" "$file" 2>/dev/null)
    [ "$u" = "$r" ] || { echo "FAIL diff [$*]: differs"; fail=1; }
}

compare "$tmp/c" -c1
compare "$tmp/c" -c1-3
compare "$tmp/c" -c3-
compare "$tmp/c" -c-4
compare "$tmp/c" -c1,3,5
compare "$tmp/c" -c2-4,7-
compare "$tmp/f" -f1 -d:
compare "$tmp/f" -f1,3 -d:
compare "$tmp/f" -f2- -d:
compare "$tmp/f" -f-2 -d:
compare "$tmp/f" -f5 -d:
# -s: drop lines with no delimiter
compare "$tmp/f" -s -f1 -d:
compare "$tmp/f" -s -f2 -d:
compare "$tmp/f" -s -f2- -d:
compare "$tmp/f" -s -f1,3 -d:

[ "$fail" -eq 0 ] && echo "PASS differential/cut (ref: $REF)"
exit "$fail"
