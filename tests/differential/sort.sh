#!/bin/sh
# Differential test: uolt-sort matches `LC_ALL=C sort` (byte order) on stdout,
# for plain and -r sorts. Includes a fuzz comparison over random lines.
set -u
BIN=${UOLT_SORT:-${BUILD:-./build}/uolt-sort}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/sort; [ -x /bin/sort ] && REF=/bin/sort
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

printf 'delta\nalpha\nCharlie\nbravo\nalpha\n10\n2\n1\n' >"$tmp/a"

"$BIN" "$tmp/a" >"$tmp/u"; LC_ALL=C "$REF" "$tmp/a" >"$tmp/r"
cmp -s "$tmp/u" "$tmp/r" || { echo "FAIL diff: default"; fail=1; }

"$BIN" -r "$tmp/a" >"$tmp/u"; LC_ALL=C "$REF" -r "$tmp/a" >"$tmp/r"
cmp -s "$tmp/u" "$tmp/r" || { echo "FAIL diff: -r"; fail=1; }

# -u and -n against a mixed numeric/text file.
printf '10\n2\n2\n100\n1\n-5\n2\n33\n' >"$tmp/n"
for o in -u -n -rn -nu -run; do
    "$BIN" $o "$tmp/n" >"$tmp/u"; LC_ALL=C "$REF" $o "$tmp/n" >"$tmp/r"
    cmp -s "$tmp/u" "$tmp/r" || { echo "FAIL diff: $o"; fail=1; }
done

# -f (fold) and -b (ignore leading blanks): ordering matches BSD and GNU because
# both fall back to a raw last-resort compare on ties.
printf 'banana\nApple\ncherry\nBanana\napple\nDelta\n' >"$tmp/fold"
printf '  zebra\nant\n   bee\ncat\nzebra\nAnt\n' >"$tmp/blank"
printf '  30\n5\n 5\n100\n  2\n' >"$tmp/bnum"
for o in -f -rf -fb -rb; do
    "$BIN" $o "$tmp/fold" >"$tmp/u"; LC_ALL=C "$REF" $o "$tmp/fold" >"$tmp/r"
    cmp -s "$tmp/u" "$tmp/r" || { echo "FAIL diff: $o (fold)"; fail=1; }
done
for o in -b -fb; do
    "$BIN" $o "$tmp/blank" >"$tmp/u"; LC_ALL=C "$REF" $o "$tmp/blank" >"$tmp/r"
    cmp -s "$tmp/u" "$tmp/r" || { echo "FAIL diff: $o (blank)"; fail=1; }
done
for o in -bn -bnr; do
    "$BIN" $o "$tmp/bnum" >"$tmp/u"; LC_ALL=C "$REF" $o "$tmp/bnum" >"$tmp/r"
    cmp -s "$tmp/u" "$tmp/r" || { echo "FAIL diff: $o (bnum)"; fail=1; }
done

# Note: -u combined with -f/-b on key-colliding-but-distinct lines is left out of
# the differential set: which representative of an equal-key run is kept is
# underspecified and diverges between BSD (input-first) and GNU (last-resort
# disabled), so uolt's deterministic choice is exercised in the unit test only.

# Large input: well past the old fixed 1 MB buffer, exercising the growable mmap
# regions. This is the regression guard against silent truncation.
awk 'BEGIN { srand(20260715); for (i = 0; i < 200000; i++) print int(rand()*1000000000) }' >"$tmp/big"
"$BIN" "$tmp/big" >"$tmp/u"; LC_ALL=C "$REF" "$tmp/big" >"$tmp/r"
cmp -s "$tmp/u" "$tmp/r" || { echo "FAIL diff: large input (truncation?)"; fail=1; }
"$BIN" -n "$tmp/big" >"$tmp/u"; LC_ALL=C "$REF" -n "$tmp/big" >"$tmp/r"
cmp -s "$tmp/u" "$tmp/r" || { echo "FAIL diff: large input -n"; fail=1; }

# Fuzz: random line sets.
i=0
while [ "$i" -lt 60 ]; do
    n=$(( (i % 40) + 1 ))
    : >"$tmp/f"
    k=0
    while [ "$k" -lt "$n" ]; do
        LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | dd bs=1 count=$(( (i + k) % 8 + 1 )) 2>/dev/null >>"$tmp/f"
        printf '\n' >>"$tmp/f"
        k=$((k + 1))
    done
    "$BIN" "$tmp/f" >"$tmp/u"; LC_ALL=C "$REF" "$tmp/f" >"$tmp/r"
    if ! cmp -s "$tmp/u" "$tmp/r"; then echo "FAIL diff: fuzz iter $i"; fail=1; break; fi
    i=$((i + 1))
done

[ "$fail" -eq 0 ] && echo "PASS differential/sort (ref: LC_ALL=C $REF)"
exit "$fail"
