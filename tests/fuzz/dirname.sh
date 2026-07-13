#!/bin/sh
# Fuzz test: random path-like strings (slashes, dots, letters) must match the
# reference dirname byte-for-byte and on exit code.
set -u
BIN=${UOLT_DIRNAME:-${BUILD:-./build}/uolt-dirname}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/dirname; [ -x /bin/dirname ] && REF=/bin/dirname
ITER=${UOLT_FUZZ_ITER:-500}
fail=0

i=0
while [ "$i" -lt "$ITER" ]; do
    n=$(( (i % 14) + 1 ))
    s=$(LC_ALL=C tr -dc 'ab/.' </dev/urandom | dd bs=1 count="$n" 2>/dev/null)
    u=$("$BIN" "$s" 2>/dev/null); urc=$?
    r=$("$REF" "$s" 2>/dev/null); rrc=$?
    if [ "$urc" -ne "$rrc" ] || [ "$u" != "$r" ]; then
        echo "FAIL fuzz [$s]: [$u] != [$r] (exit $urc/$rrc)"; fail=1; break
    fi
    i=$((i + 1))
done

[ "$fail" -eq 0 ] && echo "PASS fuzz/dirname ($ITER iters)"
exit "$fail"
