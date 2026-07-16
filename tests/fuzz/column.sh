#!/bin/sh
# Fuzz test for uolt-column. Two invariants:
#   A. Robustness: arbitrary bytes (newlines, tabs, NULs, invalid UTF-8) must
#      never crash the tool - it exits 0 or 1, never via a signal (rc >= 128).
#   B. Reference agreement: on random whitespace-columned input, the output must
#      match the system `column -t` byte-for-byte (skipped if no `column`).
set -u
BIN=${UOLT_COLUMN:-${BUILD:-./build}/uolt-column}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=$(command -v column 2>/dev/null || true)
ITER=${UOLT_FUZZ_ITER:-200}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# ---- A. random-bytes robustness ----
i=0
while [ "$i" -lt "$ITER" ]; do
    sz=$(( (i * 53 + 7) % 4096 ))
    dd if=/dev/urandom of="$tmp/in" bs=1 count="$sz" 2>/dev/null
    "$BIN" <"$tmp/in" >"$tmp/out" 2>/dev/null; rc=$?
    if [ "$rc" -ge 128 ]; then
        echo "FAIL fuzz: crashed (rc=$rc) on random input at iter $i"; fail=1; break
    fi
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
        echo "FAIL fuzz: unexpected exit $rc at iter $i"; fail=1; break
    fi
    i=$((i + 1))
done

# ---- B. agreement with the reference on well-formed grids ----
if [ "$fail" -eq 0 ] && [ -n "$REF" ]; then
    i=0
    while [ "$i" -lt "$ITER" ]; do
        rows=$(( (i % 20) + 1 ))
        cols=$(( (i % 8) + 1 ))
        awk -v R="$rows" -v C="$cols" -v seed="$i" 'BEGIN{
            srand(seed);
            for (r=0; r<R; r++){
                line="";
                for (c=0; c<C; c++){
                    n=int(rand()*6)+1; tok="";
                    for (k=0; k<n; k++) tok=tok sprintf("%c", 97+int(rand()*26));
                    line=(c==0)?tok:line" "tok;
                }
                print line;
            }
        }' >"$tmp/grid"
        "$BIN"    <"$tmp/grid" >"$tmp/uo" 2>/dev/null
        "$REF" -t <"$tmp/grid" >"$tmp/ro" 2>/dev/null
        if ! cmp -s "$tmp/uo" "$tmp/ro"; then
            echo "FAIL fuzz: diverged from reference at iter $i"; fail=1; break
        fi
        i=$((i + 1))
    done
fi

[ "$fail" -eq 0 ] && echo "PASS fuzz/column ($ITER iters)"
exit "$fail"
