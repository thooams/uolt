#!/bin/sh
# Differential test: uolt-tee matches the system tee - same stdout and same file
# contents - for the fan-out and -a cases.
set -u
BIN=${UOLT_TEE:-${BUILD:-./build}/uolt-tee}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/tee; [ -x /bin/tee ] && REF=/bin/tee
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

seq 1 500 >input

run() {
    desc=$1; shift
    ud=$(mktemp -d); rd=$(mktemp -d)
    ( cd "$ud"; "$BIN" "$@" <"$tmp/input" >stdout.txt )
    ( cd "$rd"; "$REF" "$@" <"$tmp/input" >stdout.txt )
    us=$(cd "$ud" && find . -type f | sort); rs=$(cd "$rd" && find . -type f | sort)
    [ "$us" = "$rs" ] || { echo "FAIL diff [$desc]: file set differs"; fail=1; }
    for f in $us; do cmp -s "$ud/$f" "$rd/$f" || { echo "FAIL diff [$desc]: $f differs"; fail=1; }; done
    rm -rf "$ud" "$rd"
}

run "one"   a
run "two"   a b
run "none"
# -a: pre-seed identical files, then append.
ud=$(mktemp -d); rd=$(mktemp -d)
printf 'pre\n' >"$ud/a"; printf 'pre\n' >"$rd/a"
( cd "$ud"; "$BIN" -a a <"$tmp/input" >/dev/null )
( cd "$rd"; "$REF" -a a <"$tmp/input" >/dev/null )
cmp -s "$ud/a" "$rd/a" || { echo "FAIL diff [-a]: append differs"; fail=1; }
rm -rf "$ud" "$rd"

[ "$fail" -eq 0 ] && echo "PASS differential/tee (ref: $REF)"
exit "$fail"
