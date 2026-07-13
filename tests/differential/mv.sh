#!/bin/sh
# Differential test: uolt-mv agrees with the system mv on exit status and the
# resulting tree, for the two-operand rename form (no directory targets, which
# are out of scope in v1).
set -u
BIN=${UOLT_MV:-${BUILD:-./build}/uolt-mv}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/mv; [ -x /usr/bin/mv ] && REF=/usr/bin/mv
fail=0

compare() {
    desc=$1; seed=$2; shift 2
    ua=$(mktemp -d); ra=$(mktemp -d)
    ( cd "$ua"; eval "$seed"; "$BIN" "$@" >/dev/null 2>&1 ); urc=$?
    ( cd "$ra"; eval "$seed"; "$REF" "$@" >/dev/null 2>&1 ); rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    ut=$(cd "$ua" && find . | sort; echo "--"; cd "$ua" && cat ./* 2>/dev/null)
    rt=$(cd "$ra" && find . | sort; echo "--"; cd "$ra" && cat ./* 2>/dev/null)
    [ "$ut" = "$rt" ] || { echo "FAIL diff [$desc]: result differs"; fail=1; }
    rm -rf "$ua" "$ra"
}

compare "rename"      "printf hi >a"                 a b
compare "overwrite"   "printf n >a; printf o >b"     a b
compare "rename dir"  "mkdir d"                      d e
compare "missing"     "true"                         nope dest
compare "symlink"     "printf x >t; ln -s t l"       l m

[ "$fail" -eq 0 ] && echo "PASS differential/mv (ref: $REF)"
exit "$fail"
