#!/bin/sh
# Unit test for uolt-grep: fixed-string matching, -i, -v, stdin, multi-file
# prefixes, and grep's exit-status convention (0 match, 1 none, 2 error).
set -u
BIN=${UOLT_GREP:-${BUILD:-./build}/uolt-grep}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

printf 'apple\nbanana\ncherry\nAPPLE pie\n' >f

[ "$("$BIN" apple f | tr '\n' ',')" = "apple," ]                      || { echo "FAIL unit: basic"; fail=1; }
[ "$("$BIN" -i apple f | tr '\n' ',')" = "apple,APPLE pie," ]         || { echo "FAIL unit: -i"; fail=1; }
[ "$("$BIN" -v apple f | tr '\n' ',')" = "banana,cherry,APPLE pie," ] || { echo "FAIL unit: -v"; fail=1; }

# stdin
[ "$(printf 'x\nyy\nzxz\n' | "$BIN" x | tr '\n' ',')" = "x,zxz," ] || { echo "FAIL unit: stdin"; fail=1; }

# Multi-file: matching lines are prefixed with the file name.
printf 'apple tart\n' >g
got=$("$BIN" apple f g | sort | tr '\n' ',')
[ "$got" = "f:apple,g:apple tart," ] || { echo "FAIL unit: multi prefix [$got]"; fail=1; }

# -n prefixes line numbers; -c prints the match count. (f: apple@1, APPLE pie@4.)
[ "$("$BIN" -n apple f)" = "1:apple" ]           || { echo "FAIL unit: -n"; fail=1; }
[ "$("$BIN" -c apple f)" = "1" ]                 || { echo "FAIL unit: -c"; fail=1; }
[ "$("$BIN" -ic apple f)" = "2" ]                || { echo "FAIL unit: -ic"; fail=1; }
[ "$("$BIN" -c zzz f)" = "0" ]                   || { echo "FAIL unit: -c none"; fail=1; }
[ "$("$BIN" -in apple f | tr '\n' ',')" = "1:apple,4:APPLE pie," ] || { echo "FAIL unit: -in"; fail=1; }

# -w: match only on word boundaries; -x: match only the whole line.
printf 'apple\npineapple\napple-pie\nan apple\nappletree\n' >w
[ "$("$BIN" -w apple w | tr '\n' ',')" = "apple,apple-pie,an apple," ] || { echo "FAIL unit: -w"; fail=1; }
[ "$("$BIN" -x apple w | tr '\n' ',')" = "apple," ]                    || { echo "FAIL unit: -x"; fail=1; }
[ "$("$BIN" -c -w apple w)" = "3" ]                                    || { echo "FAIL unit: -wc"; fail=1; }
[ "$("$BIN" -ix APPLE w | tr '\n' ',')" = "apple," ]                   || { echo "FAIL unit: -ix"; fail=1; }

# A final line without a trailing newline still matches.
printf 'no-newline-apple' >h
[ "$("$BIN" apple h)" = "no-newline-apple" ] || { echo "FAIL unit: no trailing newline"; fail=1; }

# Exit status: 0 match, 1 none, 2 error.
"$BIN" apple f >/dev/null;      [ $? -eq 0 ] || { echo "FAIL unit: exit 0 on match"; fail=1; }
"$BIN" zzz f   >/dev/null;      [ $? -eq 1 ] || { echo "FAIL unit: exit 1 on no match"; fail=1; }
"$BIN" x nope  >/dev/null 2>&1; [ $? -eq 2 ] || { echo "FAIL unit: exit 2 on error"; fail=1; }
"$BIN" >/dev/null 2>&1;         [ $? -eq 2 ] || { echo "FAIL unit: exit 2 on usage"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/grep"
exit "$fail"
