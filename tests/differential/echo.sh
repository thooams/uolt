#!/bin/sh
# Differential test: uolt-echo matches the reference `/bin/echo` binary on exit
# code and output, byte for byte. Cases avoid backslashes so GNU and BSD echo
# agree (neither processes escapes without -e).
set -u
BIN=${UOLT_ECHO:-./build/uolt-echo}
REF=${REF_ECHO:-/bin/echo}
[ -x "$REF" ] || REF=$(command -v echo)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

compare() {
    desc=$1; shift
    "$BIN" "$@" >"$tmp/uo" 2>"$tmp/ue"; urc=$?
    "$REF" "$@" >"$tmp/ro" 2>"$tmp/re"; rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    cmp -s "$tmp/uo" "$tmp/ro" || { echo "FAIL diff [$desc]: stdout differs"; fail=1; }
    cmp -s "$tmp/ue" "$tmp/re" || { echo "FAIL diff [$desc]: stderr differs"; fail=1; }
}

compare "empty"
compare "one" hello
compare "several" a b c
compare "-n one" -n foo
compare "-n several" -n a b c
compare "spaces preserved" "  leading" "trailing  "
compare "many" 1 2 3 4 5 6 7 8 9 10

[ "$fail" -eq 0 ] && echo "PASS differential/echo (ref: $REF)"
exit "$fail"
