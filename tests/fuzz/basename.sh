#!/bin/sh
# Fuzz test: random path-like strings (slashes, dots, letters) with an optional
# random suffix must match the reference basename byte-for-byte and on exit code.
set -u
BIN=${UOLT_BASENAME:-${BUILD:-./build}/uolt-basename}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
REF=/usr/bin/basename; [ -x /bin/basename ] && REF=/bin/basename
ITER=${UOLT_FUZZ_ITER:-500}
fail=0

rand_str() {
    # 1..12 bytes drawn from a path-like alphabet (never empty).
    n=$(( ($1 % 12) + 1 ))
    LC_ALL=C tr -dc 'ab/.' </dev/urandom | dd bs=1 count="$n" 2>/dev/null
}

i=0
while [ "$i" -lt "$ITER" ]; do
    s=$(rand_str "$i")
    if [ $(( i % 3 )) -eq 0 ]; then
        # two-operand form with a short suffix
        suf=$(printf '.%s' "$(LC_ALL=C tr -dc 'ab' </dev/urandom | dd bs=1 count=1 2>/dev/null)")
        u=$("$BIN" "$s" "$suf" 2>/dev/null); urc=$?
        r=$("$REF" "$s" "$suf" 2>/dev/null); rrc=$?
        desc="[$s|$suf]"
    else
        u=$("$BIN" "$s" 2>/dev/null); urc=$?
        r=$("$REF" "$s" 2>/dev/null); rrc=$?
        desc="[$s]"
    fi
    if [ "$urc" -ne "$rrc" ] || [ "$u" != "$r" ]; then
        echo "FAIL fuzz $desc: [$u] != [$r] (exit $urc/$rrc)"; fail=1; break
    fi
    i=$((i + 1))
done

[ "$fail" -eq 0 ] && echo "PASS fuzz/basename ($ITER iters)"
exit "$fail"
