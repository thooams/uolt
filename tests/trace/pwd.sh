#!/bin/sh
# Syscall-trace test for uolt-pwd: no heap (mmap/brk). Best-effort: fails on a
# real violation, SKIPs when tracing is unavailable. Linux resolves the cwd with
# the getcwd syscall; macOS with open/fcntl/close - neither allocates.
set -u
BIN=${UOLT_PWD:-./build/uolt-pwd}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

os=$(uname -s)
if [ "$os" = "Linux" ] && command -v strace >/dev/null 2>&1; then
    strace -f -o "$tmp/trace" "$BIN" >/dev/null 2>&1
    if grep -Eq '\b(mmap|brk)\(' "$tmp/trace"; then
        echo "FAIL trace: heap syscall"; grep -E '\b(mmap|brk)\(' "$tmp/trace"; exit 1
    fi
    grep -Eq '\b(getcwd)\(' "$tmp/trace" || { echo "FAIL trace: no getcwd observed"; exit 1; }
    echo "PASS trace/pwd (strace)"; exit 0
elif [ "$os" = "Darwin" ] && command -v dtruss >/dev/null 2>&1; then
    if dtruss "$BIN" >/dev/null 2>"$tmp/trace"; then
        grep -Eq '\b(mmap|brk)\(' "$tmp/trace" && { echo "FAIL trace: heap syscall"; exit 1; }
        echo "PASS trace/pwd (dtruss)"; exit 0
    fi
    echo "SKIP trace/pwd: dtruss unavailable (needs sudo / SIP)"; exit 0
fi

echo "SKIP trace/pwd: no tracer on this platform"; exit 0
