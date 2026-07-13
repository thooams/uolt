#!/bin/sh
# Fuzz test: random line counts and contents must never crash uolt-tail; stdout
# must match the reference tail byte-for-byte (both the seekable file path and
# the stdin pipe path) and the exit code must agree.
set -u
BIN=${UOLT_TAIL:-${BUILD:-./build}/uolt-tail}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/tail; [ -x /bin/tail ] && REF=/bin/tail
ITER=${UOLT_FUZZ_ITER:-200}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

i=0
while [ "$i" -lt "$ITER" ]; do
    nlines=$(( (i * 11) % 60 ))
    : >"$tmp/f"
    k=0
    while [ "$k" -le "$nlines" ]; do
        LC_ALL=C tr -dc 'A-Za-z0-9 ._:/=+-' </dev/urandom \
            | dd bs=1 count=$(( (i + k) % 25 )) 2>/dev/null >>"$tmp/f"
        printf '\n' >>"$tmp/f"
        k=$((k + 1))
    done

    n=$(( (i % 24) + 1 ))           # 1..24
    # File path.
    "$BIN" -n"$n" "$tmp/f" >"$tmp/uo" 2>/dev/null; urc=$?
    "$REF" -n"$n" "$tmp/f" >"$tmp/ro" 2>/dev/null; rrc=$?
    if [ "$urc" -ne "$rrc" ] || ! cmp -s "$tmp/uo" "$tmp/ro"; then
        echo "FAIL fuzz[file]: iter $i n=$n (exit $urc/$rrc)"; fail=1; break
    fi
    # Pipe path (same input on stdin).
    "$BIN" -n"$n" <"$tmp/f" >"$tmp/uo" 2>/dev/null; urc=$?
    "$REF" -n"$n" <"$tmp/f" >"$tmp/ro" 2>/dev/null; rrc=$?
    if [ "$urc" -ne "$rrc" ] || ! cmp -s "$tmp/uo" "$tmp/ro"; then
        echo "FAIL fuzz[pipe]: iter $i n=$n (exit $urc/$rrc)"; fail=1; break
    fi
    i=$((i + 1))
done

[ "$fail" -eq 0 ] && echo "PASS fuzz/tail ($ITER iters)"
exit "$fail"
