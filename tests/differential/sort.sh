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
