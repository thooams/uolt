#!/bin/sh
# Syscall-trace test for uolt-yes: it may only write (and exit); it must never
# allocate (mmap/brk), read, or open. The tool is stopped by SIGPIPE once the
# `head` sink closes. Best-effort: fails on a real violation, SKIPs when tracing
# is unavailable.
set -u
BIN=${UOLT_YES:-${BUILD:-./build}/uolt-yes}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

os=$(uname -s)
if [ "$os" = "Linux" ] && command -v strace >/dev/null 2>&1; then
    # Trace uolt-yes writing into head; head closing the pipe stops it via SIGPIPE.
    strace -f -o "$tmp/trace" "$BIN" 2>/dev/null | head -200 >/dev/null || true
    if grep -Eq '\b(mmap|brk|openat|open|read)\(' "$tmp/trace"; then
        echo "FAIL trace: unexpected heap/read/open syscall"
        grep -E '\b(mmap|brk|openat|open|read)\(' "$tmp/trace"; exit 1
    fi
    grep -q 'write(' "$tmp/trace" || { echo "FAIL trace: no write syscall observed"; exit 1; }
    echo "PASS trace/yes (strace)"; exit 0
elif [ "$os" = "Darwin" ] && command -v dtruss >/dev/null 2>&1; then
    if dtruss "$BIN" 2>"$tmp/trace" | head -200 >/dev/null; then
        grep -Eq '\b(mmap|brk)\(' "$tmp/trace" && { echo "FAIL trace: heap syscall"; exit 1; }
        echo "PASS trace/yes (dtruss)"; exit 0
    fi
    echo "SKIP trace/yes: dtruss unavailable (needs sudo / SIP)"; exit 0
fi

echo "SKIP trace/yes: no tracer on this platform"; exit 0
