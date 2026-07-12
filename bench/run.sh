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

if ! command -v hyperfine >/dev/null 2>&1; then
    echo "hyperfine not found. Install it (brew install hyperfine / apt install hyperfine)."
    echo "Falling back to size comparison only."
fi

sysecho=/bin/echo; [ -x /usr/bin/echo ] && sysecho=/usr/bin/echo
systrue=/usr/bin/true; [ -x /bin/true ] && systrue=/bin/true
sysfalse=/usr/bin/false; [ -x /bin/false ] && sysfalse=/bin/false

echo "== sizes (uolt vs system) =="
printf "%-12s %10s %12s\n" tool uolt system
printf "%-12s %10s %12s\n" uolt-true  "$(wc -c <build/uolt-true)"  "$(wc -c <"$systrue")"
printf "%-12s %10s %12s\n" uolt-false "$(wc -c <build/uolt-false)" "$(wc -c <"$sysfalse")"
printf "%-12s %10s %12s\n" uolt-echo  "$(wc -c <build/uolt-echo)"  "$(wc -c <"$sysecho")"
echo

command -v hyperfine >/dev/null 2>&1 || exit 0

echo "== timing: uolt-true vs system =="
hyperfine -N --warmup 300 "./build/uolt-true" "$systrue"
echo
echo "== timing: uolt-false vs system =="
hyperfine -N --warmup 300 "./build/uolt-false" "$sysfalse"
echo
echo "== timing: uolt-echo hello world vs system =="
hyperfine -N --warmup 300 "./build/uolt-echo hello world" "$sysecho hello world"
