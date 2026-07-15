#!/bin/sh
# Differential test: uolt-tail matches the reference `tail` on stdout (byte for
# byte) and exit code. Cases stay within the BSD/GNU common denominator; stderr
# text is not compared (diagnostic wording differs). Both the seekable (file)
# and non-seekable (stdin pipe) paths are exercised.
set -u
BIN=${UOLT_TAIL:-${BUILD:-./build}/uolt-tail}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/tail; [ -x /bin/tail ] && REF=/bin/tail
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

i=1; : >"$tmp/a"; while [ "$i" -le 200 ]; do echo "row $i" >>"$tmp/a"; i=$((i+1)); done
printf 'short1\nshort2\n' >"$tmp/b"
: >"$tmp/empty"
printf 'no-newline-tail' >"$tmp/c"

compare_args() {
    desc=$1; shift
    "$BIN" "$@" >"$tmp/uo" 2>/dev/null; urc=$?
    "$REF" "$@" >"$tmp/ro" 2>/dev/null; rrc=$?
    [ "$urc" -eq "$rrc" ]      || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    cmp -s "$tmp/uo" "$tmp/ro" || { echo "FAIL diff [$desc]: stdout differs"; fail=1; }
}

compare_args "default"        "$tmp/a"
compare_args "-n1"            -n1 "$tmp/a"
compare_args "-n 7"          -n 7 "$tmp/a"
compare_args "-n5 joined"    -n5 "$tmp/a"
compare_args "-n0"           -n0 "$tmp/a"
compare_args "-n +100"       -n +100 "$tmp/a"
compare_args "-n +1"         -n +1 "$tmp/a"
compare_args "more than file" -n999 "$tmp/b"
compare_args "empty"          "$tmp/empty"
compare_args "no-newline"    -n5 "$tmp/c"
compare_args "two files"     -n3 "$tmp/a" "$tmp/b"
compare_args "three files"   -n2 "$tmp/a" "$tmp/b" "$tmp/c"
compare_args "empty among"   -n2 "$tmp/a" "$tmp/empty" "$tmp/b"
compare_args "-c5"            -c5 "$tmp/a"
compare_args "-c 20"          -c 20 "$tmp/a"
compare_args "-c +100"        -c +100 "$tmp/a"
compare_args "-c big"         -c 99999 "$tmp/b"
compare_args "missing"        "$tmp/nope"
compare_args "missing+good"  -n2 "$tmp/nope" "$tmp/a"

# stdin (non-seekable path): same input to both.
for n in 1 5 50; do
    "$BIN" -n"$n" <"$tmp/a" >"$tmp/uo" 2>/dev/null; urc=$?
    "$REF" -n"$n" <"$tmp/a" >"$tmp/ro" 2>/dev/null; rrc=$?
    [ "$urc" -eq "$rrc" ]      || { echo "FAIL diff [stdin -n$n]: exit $urc vs ref $rrc"; fail=1; }
    cmp -s "$tmp/uo" "$tmp/ro" || { echo "FAIL diff [stdin -n$n]: stdout differs"; fail=1; }
done

# Large non-seekable input whose last N lines exceed the old 64 KB window: the
# regression guard against pipe truncation (the growable mmap slurp handles it).
awk 'BEGIN { for (i = 1; i <= 4000; i++) { s = "line" i " "; while (length(s) < 100) s = s "x"; print s } }' >"$tmp/big"
for n in 1000 2000; do
    cat "$tmp/big" | "$BIN" -n"$n" >"$tmp/uo" 2>/dev/null
    cat "$tmp/big" | "$REF" -n"$n" >"$tmp/ro" 2>/dev/null
    cmp -s "$tmp/uo" "$tmp/ro" || { echo "FAIL diff [pipe large -n$n]: stdout differs"; fail=1; }
done
cat "$tmp/big" | "$BIN" -c 150000 >"$tmp/uo" 2>/dev/null
cat "$tmp/big" | "$REF" -c 150000 >"$tmp/ro" 2>/dev/null
cmp -s "$tmp/uo" "$tmp/ro" || { echo "FAIL diff [pipe large -c]: stdout differs"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS differential/tail (ref: $REF)"
exit "$fail"
