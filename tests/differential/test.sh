#!/bin/sh
# Differential test: uolt-test matches the system `test` (and `[`) on exit code.
# test writes no stdout, so only the exit status is compared. Cases stay within
# the POSIX primaries both GNU and BSD agree on (no -t, no GNU string < / >).
set -u
BIN=${UOLT_TEST:-${BUILD:-./build}/uolt-test}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=${REF_TEST:-/usr/bin/test}
[ -x "$REF" ] || REF=/bin/test
fail=0

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
: > "$d/empty"
printf 'data\n' > "$d/full"
mkdir "$d/dir"
ln -s "$d/full" "$d/link"
chmod 0644 "$d/full"

compare() {
    "$BIN" "$@" >/dev/null 2>&1; u=$?
    "$REF" "$@" >/dev/null 2>&1; r=$?
    [ "$u" -eq "$r" ] || { echo "FAIL diff [$*]: exit $u vs ref $r"; fail=1; }
}

# Strings.
compare -n abc; compare -n ""; compare -z ""; compare -z abc
compare abc; compare ""
compare a = a; compare a = b; compare a != a; compare a != b
compare = =            # both operands are the string "=" (syntax error both)

# Integers.
compare 5 -eq 5; compare 5 -eq 6; compare 5 -ne 6; compare 7 -gt 3
compare 3 -lt 7; compare 5 -ge 5; compare 4 -le 4; compare 3 -gt 9
compare -5 -lt 0; compare -3 -eq -3
compare 5 -eq abc; compare abc -lt 1        # non-integer -> error on both

# Files (compared against the same system, so permission results agree).
compare -e "$d/full"; compare -e "$d/none"
compare -f "$d/full"; compare -f "$d/dir"
compare -d "$d/dir";  compare -d "$d/full"
compare -s "$d/full"; compare -s "$d/empty"
compare -r "$d/full"; compare -x "$d/full"
compare -h "$d/link"; compare -h "$d/full"; compare -L "$d/link"

# Logical operators and grouping.
compare ! -e "$d/none"; compare ! -n abc
compare -n a -a -n b; compare -n a -a -z b
compare -z a -o -n b; compare -z a -o -z b
compare '(' -n a ')'; compare '(' 5 -eq 5 -o 1 -eq 2 ')'
compare '(' -z a ')'

# Degenerate / error cases.
compare; compare '('; compare -a; compare ')'

# The `[` form, against the system `[`.
LB="$d/["; ln -s "$BIN" "$LB"
RB=${REF_LB:-/usr/bin/[}
[ -x "$RB" ] || RB=/bin/[
compare_lb() {
    "$LB" "$@" >/dev/null 2>&1; u=$?
    "$RB" "$@" >/dev/null 2>&1; r=$?
    [ "$u" -eq "$r" ] || { echo "FAIL diff [ [$*] ]: exit $u vs ref $r"; fail=1; }
}
compare_lb -n abc ']'
compare_lb 5 -gt 9 ']'
compare_lb -f "$d/full" ']'
compare_lb -n abc            # missing ] -> error on both

[ "$fail" -eq 0 ] && echo "PASS differential/test (ref: $REF)"
exit "$fail"
