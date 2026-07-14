#!/bin/sh
# Unit test for uolt-wc: line/word/byte counts, option selection, multi-file
# totals, stdin, and a nonzero exit (with continued processing) on a bad file.
# Column spacing is implementation-defined, so counts are compared after
# squeezing whitespace.
set -u
BIN=${UOLT_WC:-${BUILD:-./build}/uolt-wc}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
norm() { tr -s ' ' | sed 's/^ //;s/ $//'; }

printf 'hello world\nfoo bar baz\n' >"$tmp/a"      # 2 lines, 5 words, 24 bytes
printf 'abc' >"$tmp/b"                             # 0 lines, 1 word, 3 bytes
: >"$tmp/empty"

got=$("$BIN" "$tmp/a" | norm); rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL unit: exit $rc"; fail=1; }
[ "$got" = "2 5 24 $tmp/a" ] || { echo "FAIL unit: default [$got]"; fail=1; }

[ "$("$BIN" -l "$tmp/a" | norm)" = "2 $tmp/a" ]  || { echo "FAIL unit: -l"; fail=1; }
[ "$("$BIN" -w "$tmp/a" | norm)" = "5 $tmp/a" ]  || { echo "FAIL unit: -w"; fail=1; }
[ "$("$BIN" -c "$tmp/a" | norm)" = "24 $tmp/a" ] || { echo "FAIL unit: -c"; fail=1; }

# No trailing newline: 0 lines, still 1 word.
[ "$("$BIN" "$tmp/b" | norm)" = "0 1 3 $tmp/b" ] || { echo "FAIL unit: no-newline counts"; fail=1; }

# Empty file: all zero.
[ "$("$BIN" "$tmp/empty" | norm)" = "0 0 0 $tmp/empty" ] || { echo "FAIL unit: empty"; fail=1; }

# stdin (no name).
[ "$(printf 'a b c\n' | "$BIN" | norm)" = "1 3 6" ] || { echo "FAIL unit: stdin"; fail=1; }

# Multiple files -> per-file lines plus a total line.
"$BIN" "$tmp/a" "$tmp/b" >"$tmp/o"
last=$(tail -1 "$tmp/o" | norm)
[ "$last" = "2 6 27 total" ] || { echo "FAIL unit: total line [$last]"; fail=1; }

# -m characters (= bytes in the C locale). GNU column order: lines, words, chars,
# bytes; uolt prints two columns when both -m and -c are given.
[ "$("$BIN" -m "$tmp/a" | norm)" = "24 $tmp/a" ]      || { echo "FAIL unit: -m"; fail=1; }
[ "$("$BIN" -cm "$tmp/a" | norm)" = "24 24 $tmp/a" ]  || { echo "FAIL unit: -cm two cols"; fail=1; }
[ "$("$BIN" -lwm "$tmp/a" | norm)" = "2 5 24 $tmp/a" ] || { echo "FAIL unit: -lwm"; fail=1; }
[ "$(printf 'abcd' | "$BIN" -m | norm)" = "4" ]       || { echo "FAIL unit: -m stdin"; fail=1; }

# Missing file -> nonzero exit, stderr, later file still counted.
"$BIN" "$tmp/nope" "$tmp/b" >"$tmp/o" 2>"$tmp/e"; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL unit: missing exit 0"; fail=1; }
[ -s "$tmp/e" ] || { echo "FAIL unit: no stderr diagnostic"; fail=1; }
grep -q "$tmp/b" "$tmp/o" || { echo "FAIL unit: good file dropped after error"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/wc"
exit "$fail"
