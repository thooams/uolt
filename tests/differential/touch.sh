#!/bin/sh
# Differential test: uolt-touch agrees with the system touch on exit status and
# on whether the file ends up existing. Exact timestamps are not compared (both
# set "now"); creation/no-creation and exit code are what matter.
set -u
BIN=${UOLT_TOUCH:-${BUILD:-./build}/uolt-touch}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/touch; [ -x /bin/touch ] && REF=/bin/touch
fail=0

compare() {
    desc=$1; seed=$2; shift 2
    ua=$(mktemp -d); ra=$(mktemp -d)
    ( cd "$ua"; eval "$seed"; "$BIN" "$@" >/dev/null 2>&1 ); urc=$?
    ( cd "$ra"; eval "$seed"; "$REF" "$@" >/dev/null 2>&1 ); rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    ut=$(cd "$ua" && ls -1 | sort); rt=$(cd "$ra" && ls -1 | sort)
    [ "$ut" = "$rt" ] || { echo "FAIL diff [$desc]: listing differs [$ut] vs [$rt]"; fail=1; }
    rm -rf "$ua" "$ra"
}

compare "create"        "true"          f
compare "existing"      "echo x >f"     f
compare "two"           "true"          a b
compare "-c missing"    "true"          -c g
compare "-c existing"   "echo x >f"     -c f
compare "-am flags"     "true"          -am f
compare "-- literal"    "true"          -- -c

[ "$fail" -eq 0 ] && echo "PASS differential/touch (ref: $REF)"
exit "$fail"
