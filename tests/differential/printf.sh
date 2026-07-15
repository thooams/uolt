#!/bin/sh
# Differential test: uolt-printf matches the system `printf` byte for byte on
# stdout and exit code. Cases stay within the POSIX conversions both GNU and BSD
# agree on (no floats, no dynamic '*', no trailing-junk numeric args - the latter
# make GNU/BSD warn on stderr, which is impl-defined).
set -u
BIN=${UOLT_PRINTF:-${BUILD:-./build}/uolt-printf}
REF=${REF_PRINTF:-/usr/bin/printf}
[ -x "$REF" ] || REF=$(command -v printf)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

compare() {
    desc=$1; shift
    "$BIN" "$@" >"$tmp/uo" 2>/dev/null; urc=$?
    "$REF" "$@" >"$tmp/ro" 2>/dev/null; rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    cmp -s "$tmp/uo" "$tmp/ro" || { echo "FAIL diff [$desc]: stdout differs"; fail=1; }
}

compare "plain text"      'hello world\n'
compare "percent"         '100%%\n'
compare "string"          '%s\n' foo
compare "two strings"     '%s-%s\n' a b
compare "decimal"         '%d\n' 42
compare "negative"        '%d\n' -17
compare "width"           '[%5d][%-5d][%05d]\n' 7 7 7
compare "precision int"   '[%.3d][%.0d]\n' 5 0
compare "plus/space"      '%+d % d %+d\n' 3 4 -5
compare "unsigned"        '%u\n' 42
compare "octal"           '%o %#o\n' 8 8
compare "hex lower/upper" '%x %X\n' 255 255
compare "hex alt"         '%#x %#X\n' 255 255
compare "string prec"     '[%.3s]\n' abcdef
compare "string width"    '[%10s][%-10s]\n' hi hi
compare "char"            '%c%c\n' foo bar
compare "cycle"           '%d ' 1 2 3 4 5
compare "cycle strings"   '%s\n' a b c
compare "octal escape"    'a\101b\tc\n'
compare "named escapes"   'a\tb\rc\\d\n'
compare "b escapes"       '%b\n' 'x\ty\nz'
compare "b octal"         '%b\n' 'A\102C'
compare "b stop"          '%b tail\n' 'keep\cdrop'
compare "quote number"    '%d\n' "'A"
compare "hex input"       '%d\n' 0xff
compare "octal input"     '%d\n' 010
compare "missing numeric" '%d|%x|%o|\n'
compare "missing string"  '[%s][%s]\n'
# Note: %c on a *missing* argument is impl-defined (GNU emits a NUL byte, BSD
# emits nothing), so it is covered by the unit test, not here.
compare "reuse extra"     '%s.' a b c

[ "$fail" -eq 0 ] && echo "PASS differential/printf (ref: $REF)"
exit "$fail"
