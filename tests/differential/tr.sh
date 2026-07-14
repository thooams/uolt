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

printf 'Hello   World  123\naaabbbccc\nMixed    CASE test\nsymbols!@#   and 456\n' >"$tmp/in"

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
# -s squeeze (leading option only, for BSD tr compatibility)
compare -s ' '
compare -s 'a-c'
compare -s 'abcglo'
compare -s a-z A-Z          # translate then squeeze the mapped set
compare -ds 'A-Z' ' '
# -c complement of set1
compare -cd 'a-zA-Z'        # delete everything but letters
compare -cd '0-9'
compare -cs 'a-zA-Z0-9'     # squeeze runs of non-alphanumerics
compare -c 'a-zA-Z' ' '     # map every non-letter to a space
compare -c '0-9' '#'
compare -cs 'a-z' ' '

[ "$fail" -eq 0 ] && echo "PASS differential/tr (ref: $REF)"
exit "$fail"
