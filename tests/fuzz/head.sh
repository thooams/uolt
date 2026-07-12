#!/bin/sh
# Fuzz test: random line counts and random file contents must never crash
# uolt-head; stdout must match the reference head byte-for-byte and the exit
# code must agree.
set -u
BIN=${UOLT_HEAD:-${BUILD:-./build}/uolt-head}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/head; [ -x /bin/head ] && REF=/bin/head
ITER=${UOLT_FUZZ_ITER:-200}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

i=0
while [ "$i" -lt "$ITER" ]; do
    # A file of random line count/length (some lines may lack a trailing NL).
    nlines=$(( (i * 7) % 40 ))
    : >"$tmp/f"
    k=0
    while [ "$k" -le "$nlines" ]; do
        LC_ALL=C tr -dc 'A-Za-z0-9 ._:/=+-' </dev/urandom \
            | dd bs=1 count=$(( (i + k) % 30 )) 2>/dev/null >>"$tmp/f"
        printf '\n' >>"$tmp/f"
        k=$((k + 1))
    done

    n=$(( (i % 24) + 1 ))           # 1..24 (BSD head rejects -n0, GNU accepts it)
    "$BIN" -n"$n" "$tmp/f" >"$tmp/uo" 2>/dev/null; urc=$?
    "$REF" -n"$n" "$tmp/f" >"$tmp/ro" 2>/dev/null; rrc=$?
    if [ "$urc" -ne "$rrc" ]; then
        echo "FAIL fuzz: exit $urc vs ref $rrc at iter $i (n=$n)"; fail=1; break
    fi
    if ! cmp -s "$tmp/uo" "$tmp/ro"; then
        echo "FAIL fuzz: output differs at iter $i (n=$n)"; fail=1; break
    fi
    i=$((i + 1))
done

[ "$fail" -eq 0 ] && echo "PASS fuzz/head ($ITER iters)"
exit "$fail"
