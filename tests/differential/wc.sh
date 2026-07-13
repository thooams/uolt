#!/bin/sh
# Differential test: uolt-wc matches the reference `wc` on the counts and exit
# code. Column spacing is implementation-defined and differs between GNU and BSD,
# so both outputs are whitespace-normalized before comparison; the counts and the
# name are what must agree. The reference runs under LC_ALL=C so word/byte counts
# are byte-based on both platforms.
set -u
BIN=${UOLT_WC:-${BUILD:-./build}/uolt-wc}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/wc; [ -x /bin/wc ] && REF=/bin/wc
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
norm() { tr -s ' ' | sed 's/^ *//;s/ *$//'; }

printf 'hello world\nfoo bar baz\n'  >"$tmp/a"
printf 'one two three four five\n'   >"$tmp/b"
printf 'no-newline-tail'             >"$tmp/c"
: >"$tmp/empty"
printf 'tabs\tand   spaces\nline2\n' >"$tmp/d"
# A larger mixed file.
i=0; : >"$tmp/big"; while [ "$i" -lt 500 ]; do
    printf 'word%d another %d\tlast\n' "$i" "$i" >>"$tmp/big"; i=$((i+1)); done

compare() {
    desc=$1; shift
    u=$("$BIN" "$@" 2>/dev/null | norm);           urc=$?
    s=$(LC_ALL=C "$REF" "$@" 2>/dev/null | norm);   src=$?
    [ "$urc" -eq "$src" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $src"; fail=1; }
    [ "$u" = "$s" ]       || { echo "FAIL diff [$desc]: [$u] != [$s]"; fail=1; }
}

compare "default"      "$tmp/a"
compare "-l"          -l "$tmp/a"
compare "-w"          -w "$tmp/a"
compare "-c"          -c "$tmp/a"
compare "-lwc"        -lwc "$tmp/a"
compare "-cl order"   -c -l "$tmp/a"
compare "empty"        "$tmp/empty"
compare "no-newline"   "$tmp/c"
compare "tabs"         "$tmp/d"
compare "big"          "$tmp/big"
compare "multi+total"  "$tmp/a" "$tmp/b" "$tmp/c"
compare "missing"      "$tmp/nope"
compare "missing+good" "$tmp/nope" "$tmp/a"

# stdin (no name) under LC_ALL=C.
u=$("$BIN" <"$tmp/d" | norm)
s=$(LC_ALL=C "$REF" <"$tmp/d" | norm)
[ "$u" = "$s" ] || { echo "FAIL diff [stdin]: [$u] != [$s]"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS differential/wc (ref: $REF)"
exit "$fail"
