#!/bin/sh
# Differential test: uolt-tr matches the system tr (LC_ALL=C) for translation and
# deletion over a range of inputs.
set -u
BIN=${UOLT_TR:-${BUILD:-./build}/uolt-tr}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/tr; [ -x /bin/tr ] && REF=/bin/tr
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

printf 'Hello World 123\nMixed CASE test\nsymbols!@# and 456\n' >"$tmp/in"

compare() {
    u=$(LC_ALL=C "$BIN" "$@" <"$tmp/in" 2>/dev/null)
    r=$(LC_ALL=C "$REF" "$@" <"$tmp/in" 2>/dev/null)
    [ "$u" = "$r" ] || { echo "FAIL diff [$*]: differs"; fail=1; }
}

compare a-z A-Z
compare A-Z a-z
compare -d 0-9
compare -d 'a-zA-Z'
compare 'aeiou' '*'
compare '0-9' '#'
compare -d ' '
compare 'A-Za-z' 'N-ZA-Mn-za-m'   # rot13-ish mapping

[ "$fail" -eq 0 ] && echo "PASS differential/tr (ref: $REF)"
exit "$fail"
