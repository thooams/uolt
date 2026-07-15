#!/bin/sh
# Unit test for uolt-expr: fixed expected value + exit code (0 non-null/non-zero,
# 1 null or "0", 2 error) for the arithmetic, relational, and logical operators.
set -u
BIN=${UOLT_EXPR:-${BUILD:-./build}/uolt-expr}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

ck() { # want_value want_rc args...
    wv=$1; wc=$2; shift 2
    gv=$("$BIN" "$@" 2>/dev/null); gc=$?
    [ "$gv" = "$wv" ] && [ "$gc" -eq "$wc" ] || \
        { echo "FAIL unit: expr $* -> [$gv]($gc), want [$wv]($wc)"; fail=1; }
}

# Arithmetic.
ck 2 0    1 + 1
ck -3 0   5 - 8
ck 12 0   3 '*' 4
ck 3 0    17 / 5
ck 2 0    17 % 5
ck -1 0   -7 % 3
ck -3 0   7 / -2
ck 5 0    10 - 2 - 3           # left-associative
ck 14 0   2 + 3 '*' 4          # * binds tighter than +
ck 20 0   '(' 2 + 3 ')' '*' 4  # grouping

# Relational (numeric when both integers, else lexical) -> 1 / 0.
ck 1 0    5 '>' 3
ck 0 1    5 '<' 3
ck 1 0    5 '>=' 5
ck 1 0    4 '<=' 4
ck 1 0    5 = 5
ck 1 0    5 != 6
ck 1 0    abc '<' abd
ck 0 1    abc = abd
ck 1 0    abc = abc

# Logical | and &.
ck 7 0    0 '|' 7
ck 4 0    4 '|' 7
ck 0 1    0 '&' 7
ck 5 0    5 '&' 7
ck 0 1    "" '|' 0

# Value-based exit status and plain strings.
ck 0 1    0
ck '' 1   ""
ck hello 0 hello
ck 42 0   42

# Errors: non-integer arithmetic, division by zero, syntax, missing operand.
ck '' 2   5 + abc
ck '' 2   1 / 0
ck '' 2   1 +
ck '' 2   '(' 1

[ "$fail" -eq 0 ] && echo "PASS unit/expr"
exit "$fail"
