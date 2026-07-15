#!/bin/sh
# Differential test: uolt-expr matches the system `expr` on stdout and exit code.
# stderr text differs across implementations, so only stdout + status are checked.
# Cases stay within the operators both GNU and BSD agree on (no `:` match, which
# is deferred; no overflow).
set -u
BIN=${UOLT_EXPR:-${BUILD:-./build}/uolt-expr}
REF=${REF_EXPR:-/usr/bin/expr}
[ -x "$REF" ] || REF=/bin/expr
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

compare() {
    "$BIN" "$@" >"$tmp/uo" 2>/dev/null; urc=$?
    "$REF" "$@" >"$tmp/ro" 2>/dev/null; rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$*]: exit $urc vs ref $rrc"; fail=1; }
    cmp -s "$tmp/uo" "$tmp/ro" || { echo "FAIL diff [$*]: stdout differs"; fail=1; }
}

# Arithmetic.
compare 1 + 1
compare 5 - 8
compare 3 '*' 4
compare 17 / 5
compare 17 % 5
compare -7 % 3
compare 7 / -2
compare 10 - 2 - 3
compare 2 + 3 '*' 4
compare '(' 2 + 3 ')' '*' 4
compare -5 + 2

# Relational.
compare 5 '>' 3
compare 5 '<' 3
compare 5 '>=' 5
compare 4 '<=' 4
compare 5 = 5
compare 5 != 6
compare abc '<' abd
compare abc = abd
compare abc = abc

# Logical.
compare 0 '|' 7
compare 4 '|' 7
compare 0 '&' 7
compare 5 '&' 7

# Value-based exit status.
compare 0
compare ''
compare hello
compare 42

# Errors (exit code only; stderr text is implementation-specific).
compare 5 + abc
compare 1 / 0
compare 1 +
compare '(' 1

[ "$fail" -eq 0 ] && echo "PASS differential/expr (ref: $REF)"
exit "$fail"
