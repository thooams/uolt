#!/bin/sh
# Differential test: uolt-rmdir agrees with the system rmdir on exit status and
# the resulting tree. Each case runs in a fresh sandbox seeded identically, with
# relative operands so -p climbs only within the sandbox.
set -u
BIN=${UOLT_RMDIR:-${BUILD:-./build}/uolt-rmdir}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/rmdir; [ -x /usr/bin/rmdir ] && REF=/usr/bin/rmdir
fail=0

# seed: shell commands to build the tree; args: passed to rmdir.
compare() {
    desc=$1; seed=$2; shift 2
    ua=$(mktemp -d); ra=$(mktemp -d)
    ( cd "$ua"; eval "$seed"; "$BIN" "$@" >/dev/null 2>&1 ); urc=$?
    ( cd "$ra"; eval "$seed"; "$REF" "$@" >/dev/null 2>&1 ); rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    ut=$(cd "$ua" && find . | sort); rt=$(cd "$ra" && find . | sort)
    [ "$ut" = "$rt" ] || { echo "FAIL diff [$desc]: tree differs"; fail=1; }
    rm -rf "$ua" "$ra"
}

compare "empty"        "mkdir d"              d
compare "non-empty"    "mkdir d; touch d/f"   d
compare "missing"      "true"                 nope
compare "two"          "mkdir a b"            a b
compare "one-bad"      "mkdir a; mkdir b; touch b/f" a b
compare "-p chain"     "mkdir -p a/b/c"       -p a/b/c
compare "-p stop"      "mkdir -p x/y/z; touch x/k" -p x/y/z
compare "-p trailing"  "mkdir -p a/b/c"       -p a/b/c/

[ "$fail" -eq 0 ] && echo "PASS differential/rmdir (ref: $REF)"
exit "$fail"
