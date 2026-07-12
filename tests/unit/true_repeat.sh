#!/bin/sh
# Repeatability test (US2, FR-006): 1000 invocations + a loop condition all exit 0, no output.
set -u
BIN=${UOLT_TRUE:-./build/uolt-true}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
i=0
while [ "$i" -lt 1000 ]; do
    "$BIN" >>"$tmp/out" 2>>"$tmp/err" || { echo "FAIL repeat: non-zero exit at run $i"; fail=1; break; }
    i=$((i + 1))
done
[ -s "$tmp/out" ] && { echo "FAIL repeat: stdout not empty"; fail=1; }
[ -s "$tmp/err" ] && { echo "FAIL repeat: stderr not empty"; fail=1; }

# Loop-condition primitive: must run the body exactly once here.
n=0
while "$BIN"; do n=$((n + 1)); break; done
[ "$n" -eq 1 ] || { echo "FAIL repeat: loop primitive misbehaved (n=$n)"; fail=1; }

[ "$fail" -eq 0 ] && echo "PASS unit/true_repeat (1000x)"
exit "$fail"
