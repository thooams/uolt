#!/bin/sh
# Benchmark uolt-table on size and throughput. uolt-table has no coreutils peer;
# the closest standard tool is `column -t` (util-linux on Linux, BSD column on
# macOS), which aligns columns into spaces without the box-drawing frame. We use
# it as a throughput reference. Output differs (that is the point of the tool),
# so this compares speed and binary size, not bytes.
#
#   sh bench/table.sh
#
# Like the core bench, Linux is the platform where the tool's own cost is
# observable; macOS process-spawn overhead dominates and hovers around parity.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
B=${BUILD:-build}
BIN="$B/uolt-table"

[ -x "$BIN" ] || { echo "build first: make ($BIN missing)"; exit 1; }

echo "== size =="
printf "%-14s %10s\n" tool bytes
printf "%-14s %10s\n" uolt-table "$(wc -c <"$BIN")"
if command -v column >/dev/null 2>&1; then
    col=$(command -v column)
    printf "%-14s %10s\n" "column" "$(wc -c <"$col" 2>/dev/null || echo '?')"
fi
echo

# A realistic columnar input: many rows of a few whitespace-separated fields.
data=$(mktemp)
trap 'rm -f "$data"' EXIT
awk 'BEGIN{ for(i=1;i<=20000;i++) printf "row%d field%d %d value%d\n", i, i%97, i*7, i%13 }' >"$data"

if ! command -v hyperfine >/dev/null 2>&1; then
    echo "hyperfine not found; size-only. (brew install hyperfine / apt install hyperfine)"
    exit 0
fi

echo "== timing: uolt-table <20k rows> =="
if command -v column >/dev/null 2>&1; then
    hyperfine --warmup 50 "$BIN < $data" "column -t < $data"
else
    echo "(no system 'column' to compare against; timing uolt-table alone)"
    hyperfine --warmup 50 "$BIN < $data"
fi
