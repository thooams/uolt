#!/bin/sh
# Syscall-trace test for uolt-echo: it may only use write (and exit); it must
# never allocate (mmap/brk) or read. Best-effort like the true trace test:
# fails on a real violation, SKIPs when tracing is unavailable.
set -u
BIN=${UOLT_ECHO:-${BUILD:-./build}/uolt-echo}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

os=$(uname -s)
if [ "$os" = "Linux" ] && command -v strace >/dev/null 2>&1; then
    strace -f -o "$tmp/trace" "$BIN" hello world >/dev/null 2>&1
    if grep -Eq '\b(mmap|brk|read|openat|open)\(' "$tmp/trace"; then
        echo "FAIL trace: unexpected heap/read syscall"; grep -E '\b(mmap|brk|read|openat|open)\(' "$tmp/trace"; exit 1
    fi
    grep -q 'write(' "$tmp/trace" || { echo "FAIL trace: no write syscall observed"; exit 1; }
    echo "PASS trace/echo (strace)"; exit 0
elif [ "$os" = "Darwin" ] && command -v dtruss >/dev/null 2>&1; then
    if dtruss "$BIN" hello world >/dev/null 2>"$tmp/trace"; then
        if grep -Eq '\b(mmap|brk)\(' "$tmp/trace"; then
            echo "FAIL trace: unexpected heap syscall"; exit 1
        fi
        echo "PASS trace/echo (dtruss)"; exit 0
    fi
    echo "SKIP trace/echo: dtruss unavailable (needs sudo / SIP)"; exit 0
fi

echo "SKIP trace/echo: no tracer on this platform"; exit 0
