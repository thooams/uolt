#!/bin/sh
# Benchmark uolt-true against reference implementations on size and time
# (Principle XI). Memory for such a trivial process is dominated by loader
# overhead and reported informally.
set -u
BIN=${UOLT_TRUE:-./build/uolt-true}
RUNS=${UOLT_BENCH_RUNS:-100000}

echo "== uolt-true benchmark =="
echo

echo "-- binary size (bytes) --"
for cand in "$BIN" /usr/bin/true /bin/true "$(command -v busybox 2>/dev/null)" "$(command -v toybox 2>/dev/null)"; do
    [ -n "$cand" ] && [ -x "$cand" ] && printf "%-28s %s\n" "$cand" "$(wc -c <"$cand")"
done
echo

echo "-- wall time for $RUNS invocations --"
bench_one() {
    prog=$1
    [ -x "$prog" ] || return
    start=$(date +%s)
    i=0
    while [ "$i" -lt "$RUNS" ]; do "$prog" >/dev/null 2>&1; i=$((i + 1)); done
    end=$(date +%s)
    printf "%-28s %ss\n" "$prog" "$((end - start))"
}
bench_one "$BIN"
bench_one /usr/bin/true

echo
echo "-- single-run timing (startup proxy) --"
if command -v /usr/bin/time >/dev/null 2>&1; then
    /usr/bin/time -p "$BIN" 2>&1 | sed 's/^/  /'
else
    echo "  (/usr/bin/time not available)"
fi
