#!/bin/sh
# Differential test: uolt-ls lists the same set of names as the system ls, for a
# single operand. Order is not compared (v1 does not sort), so both outputs are
# sorted before comparison; the system ls is forced to one-per-line with -1.
set -u
BIN=${UOLT_LS:-${BUILD:-./build}/uolt-ls}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/ls; [ -x /usr/bin/ls ] && REF=/usr/bin/ls
fail=0

compare() {
    desc=$1; seed=$2; shift 2
    d=$(mktemp -d)
    ( cd "$d"; eval "$seed" )
    u=$( ( cd "$d"; "$BIN" "$@" ) 2>/dev/null | sort )
    r=$( ( cd "$d"; "$REF" -1 "$@" ) 2>/dev/null | sort )
    [ "$u" = "$r" ] || { echo "FAIL diff [$desc]: names differ"; printf 'uolt:[%s] ref:[%s]\n' "$u" "$r"; fail=1; }
    rm -rf "$d"
}

compare "cwd"          "touch a b c; mkdir d"
compare "-a"           "touch a .b; mkdir d"                -a
compare "named dir"    "mkdir sub; touch sub/x sub/y"       sub
compare "empty dir"    "mkdir e"                            e
compare "file"         "touch f"                            f
compare "many"         "for i in 1 2 3 4 5 6 7 8 9 10; do touch file\$i; done"
compare "dotfiles -a"  "touch .a .b .c normal"              -a

[ "$fail" -eq 0 ] && echo "PASS differential/ls (ref: $REF)"
exit "$fail"
