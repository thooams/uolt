#!/bin/sh
# Differential test: uolt-mkdir agrees with the system mkdir on exit status and
# the resulting directory tree (created under fresh temp dirs, same umask).
set -u
BIN=${UOLT_MKDIR:-${BUILD:-./build}/uolt-mkdir}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/mkdir; [ -x /usr/bin/mkdir ] && REF=/usr/bin/mkdir
fail=0

# Run the same argument set with each tool in its own sandbox and compare the
# exit code and the resulting tree.
compare() {
    desc=$1; shift
    ua=$(mktemp -d); ra=$(mktemp -d)
    ( cd "$ua"; "$BIN" "$@" >/dev/null 2>&1 ); urc=$?
    ( cd "$ra"; "$REF" "$@" >/dev/null 2>&1 ); rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    ut=$(cd "$ua" && find . | sort); rt=$(cd "$ra" && find . | sort)
    [ "$ut" = "$rt" ] || { echo "FAIL diff [$desc]: tree differs"; fail=1; }
    rm -rf "$ua" "$ra"
}

compare "one"            one
compare "two"            a b
compare "missing parent" a/b/c
compare "-p chain"       -p a/b/c
compare "-p existing"    -p a a a
compare "mixed"          -p a/b x
compare "trailing slash" -p a/b/

# -m: compare the resulting permission bits too.
perm() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
comparem() {
    desc=$1; target=$2; shift 2
    ua=$(mktemp -d); ra=$(mktemp -d)
    ( cd "$ua"; "$BIN" "$@" >/dev/null 2>&1 ); urc=$?
    ( cd "$ra"; "$REF" "$@" >/dev/null 2>&1 ); rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    [ "$(perm "$ua/$target")" = "$(perm "$ra/$target")" ] \
        || { echo "FAIL diff [$desc]: perm $(perm "$ua/$target") vs $(perm "$ra/$target")"; fail=1; }
    rm -rf "$ua" "$ra"
}
comparem "-m 700"      d -m 700 d
comparem "-m 755"      d -m 755 d
comparem "-m 750"      d -m 750 d
comparem "-m 644"      d -m 644 d
comparem "-m attached" d -m700 d
comparem "-p -m 700"   a/b/c -p -m 700 a/b/c

[ "$fail" -eq 0 ] && echo "PASS differential/mkdir (ref: $REF)"
exit "$fail"
