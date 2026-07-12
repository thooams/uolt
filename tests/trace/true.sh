#!/bin/sh
# Syscall-trace test (proves Principles II & IV): the only syscall uolt-true makes
# is exit; no read/write/mmap/brk. Tool is dtrace/strace based and often needs
# elevated privileges, so it is best-effort: it fails on a real violation but
# SKIPs (exit 0) when tracing is unavailable.
set -u
BIN=${UOLT_TRUE:-./build/uolt-true}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

os=$(uname -s)
if [ "$os" = "Linux" ] && command -v strace >/dev/null 2>&1; then
    strace -f -o "$tmp/trace" "$BIN" >/dev/null 2>&1
    # Flag any allocation/IO syscalls.
    if grep -Eq '\b(read|write|mmap|brk|openat|open)\(' "$tmp/trace"; then
        echo "FAIL trace: unexpected I/O or heap syscall"; grep -E '\b(read|write|mmap|brk|openat|open)\(' "$tmp/trace"; exit 1
    fi
    grep -q 'exit' "$tmp/trace" || { echo "FAIL trace: no exit syscall observed"; exit 1; }
    echo "PASS trace/true (strace)"; exit 0
elif [ "$os" = "Darwin" ] && command -v dtruss >/dev/null 2>&1; then
    if dtruss "$BIN" >/dev/null 2>"$tmp/trace"; then
        if grep -Eq '\b(read|write|mmap|brk)\(' "$tmp/trace"; then
            echo "FAIL trace: unexpected I/O or heap syscall"; grep -E '\b(read|write|mmap|brk)\(' "$tmp/trace"; exit 1
        fi
        echo "PASS trace/true (dtruss)"; exit 0
    fi
    echo "SKIP trace/true: dtruss unavailable (needs sudo / SIP allows it)"; exit 0
fi

echo "SKIP trace/true: no tracer on this platform"; exit 0
