#!/bin/sh
# Syscall-trace test for uolt-sleep: no heap (mmap/brk). Linux uses the nanosleep
# syscall; macOS uses select. Best-effort: fails on a real violation, SKIPs when
# tracing is unavailable.
set -u
BIN=${UOLT_SLEEP:-${BUILD:-./build}/uolt-sleep}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

os=$(uname -s)
if [ "$os" = "Linux" ] && command -v strace >/dev/null 2>&1; then
    strace -f -o "$tmp/trace" "$BIN" 0.05 >/dev/null 2>&1
    if grep -Eq '\b(mmap|brk)\(' "$tmp/trace"; then
        echo "FAIL trace: heap syscall"; grep -E '\b(mmap|brk)\(' "$tmp/trace"; exit 1
    fi
    grep -Eq '\b(nanosleep|clock_nanosleep)\(' "$tmp/trace" || { echo "FAIL trace: no nanosleep"; exit 1; }
    echo "PASS trace/sleep (strace)"; exit 0
elif [ "$os" = "Darwin" ] && command -v dtruss >/dev/null 2>&1; then
    if dtruss "$BIN" 0.05 >/dev/null 2>"$tmp/trace"; then
        grep -Eq '\b(mmap|brk)\(' "$tmp/trace" && { echo "FAIL trace: heap syscall"; exit 1; }
        echo "PASS trace/sleep (dtruss)"; exit 0
    fi
    echo "SKIP trace/sleep: dtruss unavailable (needs sudo / SIP)"; exit 0
fi

echo "SKIP trace/sleep: no tracer on this platform"; exit 0
