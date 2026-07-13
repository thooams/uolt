#!/bin/sh
# Benchmark every uolt tool against the stock system tool it replaces, on time
# and size (constitution Principle XI + performance floor). Uses hyperfine for
# statistically sound timing (warmup + many runs, mean +/- sigma).
#
#   sh bench/run.sh
#
# On Linux the tool's own cost is observable and uolt should be faster. On macOS
# process-spawn overhead (~3 ms) dominates, so results there hover around parity.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Same per-OS build dir the Makefile/tests use (host ./build, container build-linux).
B=${BUILD:-build}

if ! command -v hyperfine >/dev/null 2>&1; then
    echo "hyperfine not found. Install it (brew install hyperfine / apt install hyperfine)."
    echo "Falling back to size comparison only."
fi

sysecho=/bin/echo; [ -x /usr/bin/echo ] && sysecho=/usr/bin/echo
systrue=/usr/bin/true; [ -x /bin/true ] && systrue=/bin/true
sysfalse=/usr/bin/false; [ -x /bin/false ] && sysfalse=/bin/false
syscat=/bin/cat; [ -x /usr/bin/cat ] && syscat=/usr/bin/cat
syshead=/usr/bin/head; [ -x /bin/head ] && syshead=/bin/head
systail=/usr/bin/tail; [ -x /bin/tail ] && systail=/bin/tail

echo "== sizes (uolt vs system) =="
printf "%-12s %10s %12s\n" tool uolt system
printf "%-12s %10s %12s\n" uolt-true  "$(wc -c <$B/uolt-true)"  "$(wc -c <"$systrue")"
printf "%-12s %10s %12s\n" uolt-false "$(wc -c <$B/uolt-false)" "$(wc -c <"$sysfalse")"
printf "%-12s %10s %12s\n" uolt-echo  "$(wc -c <$B/uolt-echo)"  "$(wc -c <"$sysecho")"
printf "%-12s %10s %12s\n" uolt-cat   "$(wc -c <$B/uolt-cat)"   "$(wc -c <"$syscat")"
printf "%-12s %10s %12s\n" uolt-head  "$(wc -c <$B/uolt-head)"  "$(wc -c <"$syshead")"
printf "%-12s %10s %12s\n" uolt-tail  "$(wc -c <$B/uolt-tail)"  "$(wc -c <"$systail")"
echo

command -v hyperfine >/dev/null 2>&1 || exit 0

echo "== timing: uolt-true vs system =="
hyperfine -N --warmup 300 "./$B/uolt-true" "$systrue"
echo
echo "== timing: uolt-false vs system =="
hyperfine -N --warmup 300 "./$B/uolt-false" "$sysfalse"
echo
echo "== timing: uolt-echo hello world vs system =="
hyperfine -N --warmup 300 "./$B/uolt-echo hello world" "$sysecho hello world"
echo
echo "== timing: uolt-cat <20k-line file> vs system =="
bench_data=$(mktemp)
trap 'rm -f "$bench_data"' EXIT
seq 1 20000 >"$bench_data"
hyperfine -N --warmup 300 "./$B/uolt-cat $bench_data" "$syscat $bench_data"
echo
echo "== timing: uolt-head -n 1000 <big file> vs system =="
hyperfine -N --warmup 300 "./$B/uolt-head -n 1000 $bench_data" "$syshead -n 1000 $bench_data"
echo
echo "== timing: uolt-tail -n 10 <big file> vs system (backward seek) =="
hyperfine -N --warmup 300 "./$B/uolt-tail -n 10 $bench_data" "$systail -n 10 $bench_data"
