#!/bin/sh
# Differential test: uolt-head matches the reference `head` on stdout (byte for
# byte) and exit code. Cases stay within the BSD/GNU common denominator: the
# "-" stdin operand is NOT exercised here (BSD head rejects it while GNU treats
# it as stdin), and stderr text is not compared (diagnostic wording differs).
set -u
BIN=${UOLT_HEAD:-${BUILD:-./build}/uolt-head}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/head; [ -x /bin/head ] && REF=/bin/head
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

i=1; : >"$tmp/a"; while [ "$i" -le 50 ]; do echo "row $i" >>"$tmp/a"; i=$((i+1)); done
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

compare_args "default"       "$tmp/a"
compare_args "-n1"           -n1 "$tmp/a"
compare_args "-n 7"          -n 7 "$tmp/a"
compare_args "-n5 joined"    -n5 "$tmp/a"
compare_args "more than file" -n999 "$tmp/b"
compare_args "empty"         "$tmp/empty"
compare_args "no-newline"    -n5 "$tmp/c"
compare_args "two files"     -n3 "$tmp/a" "$tmp/b"
compare_args "three files"   -n2 "$tmp/a" "$tmp/b" "$tmp/c"
compare_args "empty among"   -n2 "$tmp/a" "$tmp/empty" "$tmp/b"
compare_args "-c5"           -c5 "$tmp/a"
compare_args "-c 3"          -c 3 "$tmp/b"
compare_args "-c big"        -c 99999 "$tmp/c"
compare_args "missing"       "$tmp/nope"
compare_args "missing+good"  -n2 "$tmp/nope" "$tmp/a"

# stdin (no operand): same input to both.
"$BIN" -n4 <"$tmp/a" >"$tmp/uo" 2>/dev/null; urc=$?
"$REF" -n4 <"$tmp/a" >"$tmp/ro" 2>/dev/null; rrc=$?
[ "$urc" -eq "$rrc" ]      || { echo "FAIL diff [stdin]: exit $urc vs ref $rrc"; fail=1; }
cmp -s "$tmp/uo" "$tmp/ro" || { echo "FAIL diff [stdin]: stdout differs"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS differential/head (ref: $REF)"
exit "$fail"
