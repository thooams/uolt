#!/bin/sh
# Syscall-trace test for uolt-wc: it may open/read/close files and write (plus
# exit); it must never allocate (mmap/brk). Best-effort like the other trace
# tests: fails on a real violation, SKIPs when tracing is unavailable.
set -u
BIN=${UOLT_WC:-${BUILD:-./build}/uolt-wc}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'count these words\nand lines\n' >"$tmp/in"

os=$(uname -s)
if [ "$os" = "Linux" ] && command -v strace >/dev/null 2>&1; then
    strace -f -o "$tmp/trace" "$BIN" "$tmp/in" >/dev/null 2>&1
    if grep -Eq '\b(mmap|brk)\(' "$tmp/trace"; then
        echo "FAIL trace: heap syscall"; grep -E '\b(mmap|brk)\(' "$tmp/trace"; exit 1
    fi
    grep -Eq '\b(read|write)\(' "$tmp/trace" || { echo "FAIL trace: no read/write observed"; exit 1; }
    echo "PASS trace/wc (strace)"; exit 0
elif [ "$os" = "Darwin" ] && command -v dtruss >/dev/null 2>&1; then
    if dtruss "$BIN" "$tmp/in" >/dev/null 2>"$tmp/trace"; then
        grep -Eq '\b(mmap|brk)\(' "$tmp/trace" && { echo "FAIL trace: heap syscall"; exit 1; }
        echo "PASS trace/wc (dtruss)"; exit 0
    fi
    echo "SKIP trace/wc: dtruss unavailable (needs sudo / SIP)"; exit 0
fi

echo "SKIP trace/wc: no tracer on this platform"; exit 0
