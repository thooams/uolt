#!/bin/sh
# Fuzz test: random argv must never crash; output must match the reference echo
# byte-for-byte (the strongest invariant), and exit status must be 0.
set -u
BIN=${UOLT_ECHO:-./build/uolt-echo}
REF=${REF_ECHO:-/bin/echo}
[ -x "$REF" ] || REF=$(command -v echo)
ITER=${UOLT_FUZZ_ITER:-500}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

i=0
while [ "$i" -lt "$ITER" ]; do
    # 1..4 random args, printable non-space bytes (spaces would split argv).
    n=$(( (i % 4) + 1 ))
    set --
    j=0
    while [ "$j" -lt "$n" ]; do
        a=$(LC_ALL=C tr -dc 'A-Za-z0-9._:/=+-' </dev/urandom | dd bs=1 count=$(( (i % 20) + 1 )) 2>/dev/null)
        set -- "$@" "$a"
        j=$((j + 1))
    done
    "$BIN" "$@" >"$tmp/uo" 2>/dev/null; urc=$?
    "$REF" "$@" >"$tmp/ro" 2>/dev/null
    if [ "$urc" -ne 0 ]; then echo "FAIL fuzz: exit $urc at iter $i (args: $*)"; fail=1; break; fi
    if ! cmp -s "$tmp/uo" "$tmp/ro"; then echo "FAIL fuzz: output differs at iter $i (args: $*)"; fail=1; break; fi
    i=$((i + 1))
done

[ "$fail" -eq 0 ] && echo "PASS fuzz/echo ($ITER iters)"
exit "$fail"
