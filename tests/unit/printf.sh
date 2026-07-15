#!/bin/sh
# Unit test for uolt-printf: fixed expected outputs for the format engine
# (escapes, conversions, flags, width, precision, argument cycling) and the
# error cases, independent of any system printf.
set -u
BIN=${UOLT_PRINTF:-${BUILD:-./build}/uolt-printf}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

check() {
    want=$1; shift
    got=$("$BIN" "$@")
    [ "$got" = "$want" ] || { echo "FAIL unit: printf $* -> [$got], want [$want]"; fail=1; }
}

# Plain text and escapes (printf $() strips the trailing newline, so add a marker).
check "hello"            'hello'
check "a	b"          'a\tb'                 # \t is a literal tab in want
check "line1"            'line1\n'              # trailing newline stripped by $()
check "A"                '\101'                 # octal escape -> 'A'
check "50%"              '50%%\n'

# String and char.
check "foo"              '%s' foo
check "a-b"              '%s-%s' a b
check "ad"               '%c%c' abc def         # first byte of each

# Integers, bases.
check "42"               '%d' 42
check "-17"              '%d' -17
check "255 ff FF"        '%u %x %X' 255 255 255
check "10 010"           '%o %#o' 8 8
check "0xff"             '%#x' 255

# Flags, width, precision.
check "    7"            '%5d' 7
check "7    "            '%-5d' 7
check "00007"           '%05d' 7
check "007"             '%.3d' 7
check "+7"              '%+d' 7
check " 7"              '% d' 7
check "abc"             '%.3s' abcdef
check "        hi"      '%10s' hi

# Argument cycling: the format repeats while arguments remain.
check "1 2 3 " '%d ' 1 2 3
check "ab"     '%s' a b                          # 'a' then 'b', newlines? none

# Missing arguments default to empty / zero.
check "0||"    '%d|%s|'
check "|0"     '%s|%d'

# %b processes escapes in the argument; \c stops output.
check "x	y"     '%b' 'x\ty'
check "keep"       '%b' 'keep\cdrop'

# Errors: no format operand, or a bad conversion, exit non-zero.
"$BIN" >/dev/null 2>&1;        [ $? -ne 0 ] || { echo "FAIL unit: no format exit 0"; fail=1; }
"$BIN" '%z' x >/dev/null 2>&1; [ $? -ne 0 ] || { echo "FAIL unit: bad conv exit 0"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/printf"
exit "$fail"
