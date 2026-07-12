#!/bin/sh
# Fuzz test: random file contents and counts must never crash uolt-cat; its
# stdout must match the reference cat byte-for-byte (the strongest invariant)
# and the exit code must agree.
set -u
BIN=${UOLT_CAT:-${BUILD:-./build}/uolt-cat}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/bin/cat; [ -x /usr/bin/cat ] && REF=/usr/bin/cat
ITER=${UOLT_FUZZ_ITER:-200}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

i=0
while [ "$i" -lt "$ITER" ]; do
    # 1..3 files of random size (0..~8 KB) filled with random bytes.
    n=$(( (i % 3) + 1 ))
    set --
    j=0
    while [ "$j" -lt "$n" ]; do
        f="$tmp/f$j"
        sz=$(( (i * 37 + j * 101) % 8192 ))
        dd if=/dev/urandom of="$f" bs=1 count="$sz" 2>/dev/null
        set -- "$@" "$f"
        j=$((j + 1))
    done
    "$BIN" "$@" >"$tmp/uo" 2>/dev/null; urc=$?
    "$REF" "$@" >"$tmp/ro" 2>/dev/null; rrc=$?
    if [ "$urc" -ne "$rrc" ]; then
        echo "FAIL fuzz: exit $urc vs ref $rrc at iter $i"; fail=1; break
    fi
    if ! cmp -s "$tmp/uo" "$tmp/ro"; then
        echo "FAIL fuzz: output differs at iter $i"; fail=1; break
    fi
    i=$((i + 1))
done

[ "$fail" -eq 0 ] && echo "PASS fuzz/cat ($ITER iters)"
exit "$fail"
