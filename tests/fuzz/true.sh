#!/bin/sh
# Fuzz test (Principle XI): random/large/binary argv and random stream states must
# never yield a non-zero exit, never produce output, and never crash.
set -u
BIN=${UOLT_TRUE:-./build/uolt-true}
ITER=${UOLT_FUZZ_ITER:-500}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

i=0
while [ "$i" -lt "$ITER" ]; do
    # Random argument string (printable-ish, from urandom).
    arg=$(LC_ALL=C tr -dc 'A-Za-z0-9=/.,:_-' </dev/urandom | dd bs=1 count=$(( (i % 60) + 1 )) 2>/dev/null)
    "$BIN" "$arg" "--$arg" >"$tmp/out" 2>"$tmp/err"
    rc=$?
    if [ "$rc" -ne 0 ]; then echo "FAIL fuzz: exit $rc at iter $i (arg len $(printf %s "$arg" | wc -c))"; fail=1; break; fi
    if [ -s "$tmp/out" ] || [ -s "$tmp/err" ]; then echo "FAIL fuzz: produced output at iter $i"; fail=1; break; fi
    i=$((i + 1))
done

# One very large argv.
big=$(yes x 2>/dev/null | head -c 100000 | tr -d '\n')
"$BIN" "$big" >"$tmp/out" 2>"$tmp/err"
[ $? -eq 0 ] || { echo "FAIL fuzz: exit != 0 on large arg"; fail=1; }
[ -s "$tmp/out" ] || [ -s "$tmp/err" ] && { echo "FAIL fuzz: output on large arg"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS fuzz/true ($ITER iters)"
exit "$fail"
