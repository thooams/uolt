#!/bin/sh
# Differential test: uolt-rm agrees with the system rm on exit status and the
# resulting tree, for the file (non-recursive) cases. -r is out of scope, so no
# directory-recursion cases are compared.
set -u
BIN=${UOLT_RM:-${BUILD:-./build}/uolt-rm}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/rm; [ -x /usr/bin/rm ] && REF=/usr/bin/rm
fail=0

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

compare "one"          "touch f"              f
compare "two"          "touch a b"            a b
compare "missing"      "true"                 gone
compare "-f missing"   "true"                 -f gone
compare "one-missing"  "touch a"              a b
compare "-f one-miss"  "touch a"              -f a b
compare "symlink"      "touch t; ln -s t l"   l
compare "-f no-args"   "true"                 -f

[ "$fail" -eq 0 ] && echo "PASS differential/rm (ref: $REF)"
exit "$fail"
