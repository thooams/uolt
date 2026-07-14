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

# NAME=VALUE on the command line adds a variable.
"$BIN" ADDED=42 "$BIN" | grep -qx 'ADDED=42' || { echo "FAIL unit: assignment"; fail=1; }

# An assignment overrides an inherited variable (no duplicate name).
n=$(OVERRIDE=old "$BIN" OVERRIDE=new "$BIN" | grep -c '^OVERRIDE=')
v=$(OVERRIDE=old "$BIN" OVERRIDE=new "$BIN" | grep '^OVERRIDE=')
{ [ "$n" -eq 1 ] && [ "$v" = "OVERRIDE=new" ]; } || { echo "FAIL unit: override [$n][$v]"; fail=1; }

# -i starts from an empty environment.
[ "$(FOO=x "$BIN" -i ONLY=1 "$BIN" | sort)" = "ONLY=1" ] || { echo "FAIL unit: -i"; fail=1; }

# -u removes a variable.
REMOVE_ME=1 "$BIN" -u REMOVE_ME "$BIN" | grep -q '^REMOVE_ME=' && { echo "FAIL unit: -u"; fail=1; }

# Run a command found via PATH; its exit status is propagated.
"$BIN" true; [ $? -eq 0 ] || { echo "FAIL unit: run true"; fail=1; }
"$BIN" false; [ $? -eq 1 ] || { echo "FAIL unit: run false"; fail=1; }
[ "$("$BIN" echo hi there)" = "hi there" ] || { echo "FAIL unit: run echo"; fail=1; }

# A command with a slash is executed directly.
[ "$("$BIN" /bin/echo direct)" = "direct" ] || { echo "FAIL unit: slash command"; fail=1; }

# A missing command exits 127; an unknown option exits 125.
"$BIN" no_such_cmd_zzz >/dev/null 2>&1; [ $? -eq 127 ] || { echo "FAIL unit: not found exit"; fail=1; }
"$BIN" -z >/dev/null 2>&1; [ $? -eq 125 ] || { echo "FAIL unit: bad option exit"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/env"
exit "$fail"
