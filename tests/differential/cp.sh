#!/bin/sh
# Differential test: uolt-cp agrees with the system cp on exit status and the
# resulting file content, for the two-operand regular-file form. Permission bits
# are not compared (v1 does not preserve mode); default-mode files are used.
set -u
BIN=${UOLT_CP:-${BUILD:-./build}/uolt-cp}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/cp; [ -x /usr/bin/cp ] && REF=/usr/bin/cp
fail=0

compare() {
    desc=$1; seed=$2; shift 2
    ua=$(mktemp -d); ra=$(mktemp -d)
    ( cd "$ua"; eval "$seed"; "$BIN" "$@" >/dev/null 2>&1 ); urc=$?
    ( cd "$ra"; eval "$seed"; "$REF" "$@" >/dev/null 2>&1 ); rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    ul=$(cd "$ua" && find . -type f | sort); rl=$(cd "$ra" && find . -type f | sort)
    [ "$ul" = "$rl" ] || { echo "FAIL diff [$desc]: file list differs"; fail=1; }
    for f in $ul; do cmp -s "$ua/$f" "$ra/$f" || { echo "FAIL diff [$desc]: $f content differs"; fail=1; }; done
    rm -rf "$ua" "$ra"
}

compare "basic"      "printf 'hi\n' >a"              a b
compare "overwrite"  "printf new >a; printf old >b"  a b
compare "empty"      ": >a"                          a b
compare "big"        "seq 1 20000 >a"                a b
compare "missing"    "true"                          nope dest
compare "into-dir"   "printf a >f; mkdir d"          f d
compare "multi-dir"  "printf 1 >a; printf 2 >b; mkdir d"  a b d
compare "slash-dir"  "mkdir s; printf x >s/q; mkdir d"    s/q d

# -r: recursive directory copy. Compare the resulting trees (structure + content).
comptree() {
    desc=$1; seed=$2; shift 2
    ua=$(mktemp -d); ra=$(mktemp -d)
    ( cd "$ua"; eval "$seed"; "$BIN" -r "$@" >/dev/null 2>&1 )
    ( cd "$ra"; eval "$seed"; "$REF" -r "$@" >/dev/null 2>&1 )
    ut=$(cd "$ua" && find . | sort); rt=$(cd "$ra" && find . | sort)
    [ "$ut" = "$rt" ] || { echo "FAIL diff [$desc]: tree differs"; fail=1; }
    for f in $(cd "$ua" && find . -type f | sort); do
        cmp -s "$ua/$f" "$ra/$f" || { echo "FAIL diff [$desc]: $f content"; fail=1; }
    done
    rm -rf "$ua" "$ra"
}
comptree "flat"   "mkdir s; printf a >s/x; printf bb >s/y"                 s d
comptree "nested" "mkdir -p s/a/b; printf 1 >s/x; printf 2 >s/a/y; printf 3 >s/a/b/z"  s d
comptree "empty"  "mkdir s"                                                s d
comptree "into"   "mkdir s d; printf a >s/x; printf b >s/y"                s d

[ "$fail" -eq 0 ] && echo "PASS differential/cp (ref: $REF)"
exit "$fail"
