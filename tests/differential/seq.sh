#!/bin/sh
# Differential test: uolt-seq matches the system seq on integer ranges.
set -u
BIN=${UOLT_SEQ:-${BUILD:-./build}/uolt-seq}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/seq; [ -x /bin/seq ] && REF=/bin/seq
fail=0

if [ ! -x "$REF" ]; then echo "SKIP differential/seq: no system seq"; exit 0; fi

compare() {
    u=$("$BIN" "$@" 2>/dev/null)
    r=$("$REF" "$@" 2>/dev/null)
    [ "$u" = "$r" ] || { echo "FAIL diff [seq $*]: differs"; fail=1; }
}

compare 10
compare 1 5
compare 3 7
compare 1 2 9
compare 0 3 12
compare 5 -1 1
compare 10 -2 0
compare 100
compare -5 5
compare 7 7

[ "$fail" -eq 0 ] && echo "PASS differential/seq (ref: $REF)"
exit "$fail"
