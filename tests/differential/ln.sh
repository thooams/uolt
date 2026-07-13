#!/bin/sh
# Differential test: uolt-ln agrees with the system ln on exit status and the
# resulting entries (name + type, and symlink target). Each case runs in a fresh
# sandbox seeded identically.
set -u
BIN=${UOLT_LN:-${BUILD:-./build}/uolt-ln}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/ln; [ -x /usr/bin/ln ] && REF=/usr/bin/ln
fail=0

sig() {  # print a stable signature of the current directory's entries
    find . -maxdepth 1 ! -name . | sort | while IFS= read -r p; do
        if [ -L "$p" ]; then echo "L $p -> $(readlink "$p")"
        elif [ -d "$p" ]; then echo "D $p"
        else echo "F $p"; fi
    done
}

compare() {
    desc=$1; seed=$2; shift 2
    ua=$(mktemp -d); ra=$(mktemp -d)
    ( cd "$ua"; eval "$seed"; "$BIN" "$@" >/dev/null 2>&1 ); urc=$?
    ( cd "$ra"; eval "$seed"; "$REF" "$@" >/dev/null 2>&1 ); rrc=$?
    [ "$urc" -eq "$rrc" ] || { echo "FAIL diff [$desc]: exit $urc vs ref $rrc"; fail=1; }
    us=$(cd "$ua" && sig); rs=$(cd "$ra" && sig)
    [ "$us" = "$rs" ] || { echo "FAIL diff [$desc]: entries differ"; fail=1; }
    rm -rf "$ua" "$ra"
}

compare "hard"          "echo a >s"            s h
compare "symlink"       "echo a >s"            -s s l
compare "implicit"      "mkdir d; echo a >d/f" d/f
compare "sym implicit"  "echo a >s"            -s s
compare "existing hard" "echo a >s; echo b >h" s h
compare "force sym"     "echo a >s; echo b >l" -sf s l
compare "missing src"   "true"                 nope dest
compare "sym to missing" "true"                -s nope dest

[ "$fail" -eq 0 ] && echo "PASS differential/ln (ref: $REF)"
exit "$fail"
