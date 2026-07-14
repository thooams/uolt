#!/bin/sh
# Unit test for uolt-env: print the environment, one NAME=value per line.
set -u
BIN=${UOLT_ENV:-${BUILD:-./build}/uolt-env}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
fail=0

# A set variable appears with its value.
out=$(UOLT_TEST_VAR=hello123 "$BIN")
echo "$out" | grep -qx 'UOLT_TEST_VAR=hello123' || { echo "FAIL unit: variable not printed"; fail=1; }

# Every line is NAME=value (contains '='), and output ends with a newline.
UOLT_TEST_VAR=x "$BIN" >/tmp/uolt_env.$$ 2>/dev/null
if grep -q -v '=' /tmp/uolt_env.$$; then echo "FAIL unit: a line without '='"; fail=1; fi
last=$(tail -c1 /tmp/uolt_env.$$ | od -An -tu1 | tr -d ' ')
[ "$last" = "10" ] || { echo "FAIL unit: no trailing newline"; fail=1; }
rm -f /tmp/uolt_env.$$

# Two vars both present.
out=$(A_ONE=1 B_TWO=2 "$BIN")
{ echo "$out" | grep -qx 'A_ONE=1' && echo "$out" | grep -qx 'B_TWO=2'; } \
    || { echo "FAIL unit: multiple vars"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/env"
exit "$fail"
