#!/bin/sh
# Differential test: uolt-find lists the same set of paths as the system find
# (compared sorted, since traversal order is filesystem-defined) for the walk and
# -type f|d cases.
set -u
BIN=${UOLT_FIND:-${BUILD:-./build}/uolt-find}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/find; [ -x /bin/find ] && REF=/bin/find
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
cd "$tmp" || exit 1

mkdir -p a/b/c d; touch a/f1 a/b/f2 a/b/c/f3 d/f4 top; ln -s top slink
touch a/note.txt a/b/data.log readme.txt x.log a/b/c/deep.txt

compare() {
    desc=$1; shift
    u=$("$BIN" "$@" 2>/dev/null | sort)
    r=$("$REF" "$@" 2>/dev/null | sort)
    [ "$u" = "$r" ] || { echo "FAIL diff [$desc]: paths differ"; fail=1; }
}

compare "dot"        .
compare "subdir"     a
compare "-type f"    . -type f
compare "-type d"    . -type d
compare "sub -type f" a -type f
compare "two starts" a d
compare "-name txt"  . -name '*.txt'
compare "-name ?"    . -name '?.txt' 2>/dev/null || true
compare "-name log"  . -name '*.log'
compare "-name none" . -name 'nomatch*'
compare "type+name"  . -type f -name 'f*'
compare "name f4"    . -name 'f4'

[ "$fail" -eq 0 ] && echo "PASS differential/find (ref: $REF)"
exit "$fail"
