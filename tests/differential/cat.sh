#!/bin/sh
# Differential test: uolt-cat matches the reference `/bin/cat` on stdout (byte
# for byte) and exit code. stderr text is intentionally NOT compared - the
# diagnostic wording for a failed open differs by implementation; only its exit
# code and empty stdout matter.
set -u
BIN=${UOLT_CAT:-${BUILD:-./build}/uolt-cat}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/cat; [ -x /usr/bin/cat ] && REF=/usr/bin/cat
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

printf 'line1\nline2\nno-newline-at-end' >"$tmp/a"
printf 'B file\n'                        >"$tmp/b"
: >"$tmp/empty"
# A larger, binary-ish payload to exercise multiple read/write blocks.
head -c 200000 /dev/urandom >"$tmp/big" 2>/dev/null || \
    dd if=/dev/urandom of="$tmp/big" bs=1000 count=200 2>/dev/null

# Compare argv-driven cases (files as operands).
compare_args() {
    desc=$1; shift
    "$BIN" "$@" >"$tmp/uo" 2>/dev/null; urc=$?
    "$REF" "$@" >"$tmp/ro" 2>/dev/null; rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    cmp -s "$tmp/uo" "$tmp/ro" || { echo "FAIL diff [$desc]: stdout differs"; fail=1; }
}

compare_args "single"        "$tmp/a"
compare_args "two files"     "$tmp/a" "$tmp/b"
compare_args "empty"         "$tmp/empty"
compare_args "empty+file"    "$tmp/empty" "$tmp/a"
compare_args "big"           "$tmp/big"
compare_args "big+small"     "$tmp/big" "$tmp/b"
compare_args "missing"       "$tmp/nope"
compare_args "missing+good"  "$tmp/nope" "$tmp/a"

# Compare stdin-driven cases (same input to both).
compare_stdin() {
    desc=$1; src=$2; shift 2
    "$BIN" "$@" <"$src" >"$tmp/uo" 2>/dev/null; urc=$?
    "$REF" "$@" <"$src" >"$tmp/ro" 2>/dev/null; rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    cmp -s "$tmp/uo" "$tmp/ro" || { echo "FAIL diff [$desc]: stdout differs"; fail=1; }
}

compare_stdin "stdin default" "$tmp/a"
compare_stdin "stdin dash"    "$tmp/a" -
compare_stdin "stdin big"     "$tmp/big"

[ "$fail" -eq 0 ] && echo "PASS differential/cat (ref: $REF)"
exit "$fail"
