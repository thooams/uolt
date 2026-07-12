#!/bin/sh
# Differential test (SC-003, FR-007): uolt-true matches a reference `true` on
# exit code and output, byte for byte, across cases.
set -u
BIN=${UOLT_TRUE:-./build/uolt-true}
REF=${REF_TRUE:-$(command -v true)}
# Prefer a real executable over the shell builtin for an honest comparison.
[ -x /usr/bin/true ] && REF=/usr/bin/true
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

compare "no args"
compare "args" foo bar --baz
compare "many args" 1 2 3 4 5 6 7 8 9 10

[ "$fail" -eq 0 ] && echo "PASS differential/true (ref: $REF)"
exit "$fail"
