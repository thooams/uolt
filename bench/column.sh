#!/bin/sh
# Benchmark uolt-column on size and throughput against the system `column -t`
# (util-linux on Linux, BSD on macOS) - the tool it reimplements. Same output,
# so this is a fair time + size comparison.
#
#   sh bench/column.sh
#
# On Linux the tool's own cost is observable and uolt-column should be faster;
# on macOS process-spawn overhead dominates and results hover around parity.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
B=${BUILD:-build}
BIN="$B/uolt-column"

[ -x "$BIN" ] || { echo "build first: make ($BIN missing)"; exit 1; }
REF=$(command -v column 2>/dev/null || true)

echo "== size =="
printf "%-14s %10s\n" tool bytes
printf "%-14s %10s\n" uolt-column "$(wc -c <"$BIN")"
[ -n "$REF" ] && printf "%-14s %10s\n" "column" "$(wc -c <"$REF" 2>/dev/null || echo '?')"
echo

data=$(mktemp)
trap 'rm -f "$data"' EXIT
awk 'BEGIN{ for(i=1;i<=20000;i++) printf "row%d field%d %d value%d\n", i, i%97, i*7, i%13 }' >"$data"

if ! command -v hyperfine >/dev/null 2>&1; then
    echo "hyperfine not found; size-only. (brew install hyperfine / apt install hyperfine)"
    exit 0
fi

echo "== timing: uolt-column <20k rows> =="
if [ -n "$REF" ]; then
    hyperfine --warmup 50 "$BIN < $data" "column -t < $data"
else
    echo "(no system 'column' to compare against; timing uolt-column alone)"
    hyperfine --warmup 50 "$BIN < $data"
fi
