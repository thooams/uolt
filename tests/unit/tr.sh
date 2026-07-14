#!/bin/sh
# Unit test for uolt-tr: translate (with ranges and a short set2) and delete.
set -u
BIN=${UOLT_TR:-${BUILD:-./build}/uolt-tr}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

ck() { [ "$2" = "$1" ] || { echo "FAIL unit: [$3] -> [$2] want [$1]"; fail=1; }; }

ck "HELLO WORLD" "$(printf 'Hello World\n' | "$BIN" a-z A-Z)"   "upcase"
ck "hello world" "$(printf 'HELLO WORLD\n' | "$BIN" A-Z a-z)"   "downcase"
ck "abc"         "$(printf 'a1b2c3\n'      | "$BIN" -d 0-9)"     "delete digits"
ck "hippo"       "$(printf 'hello\n'       | "$BIN" el ip)"      "literal map"
ck "xxxxx"       "$(printf 'abcde\n'       | "$BIN" abcde x)"    "short set2 repeats last"
ck "_____"       "$(printf 'a b c\n'       | "$BIN" ' abc' '____')" "space+letters"
ck "helloworld"  "$(printf 'h e l l o w o r l d\n' | "$BIN" -d ' ')" "delete spaces"

# Multiple lines / binary-ish (newlines preserved unless mapped).
[ "$(printf 'ab\nba\n' | "$BIN" ab AB | tr '\n' ,)" = "AB,BA," ] || { echo "FAIL unit: multiline"; fail=1; }

# Missing operands -> error.
printf 'x\n' | "$BIN" >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL unit: no set exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/tr"
exit "$fail"
