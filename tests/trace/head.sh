#!/bin/sh
# Syscall-trace test for uolt-head: it may only open/read/close files and write
# (plus exit); it must never allocate (mmap/brk). Best-effort like the other
# trace tests: fails on a real violation, SKIPs when tracing is unavailable.
set -u
BIN=${UOLT_HEAD:-${BUILD:-./build}/uolt-head}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'trace\nme\nnow\n' >"$tmp/in"

os=$(uname -s)
if [ "$os" = "Linux" ] && command -v strace >/dev/null 2>&1; then
    strace -f -o "$tmp/trace" "$BIN" -n2 "$tmp/in" >/dev/null 2>&1
    if grep -Eq '\b(mmap|brk)\(' "$tmp/trace"; then
        echo "FAIL trace: heap syscall"; grep -E '\b(mmap|brk)\(' "$tmp/trace"; exit 1
    fi
    grep -Eq '\b(read|write)\(' "$tmp/trace" || { echo "FAIL trace: no read/write observed"; exit 1; }
    echo "PASS trace/head (strace)"; exit 0
elif [ "$os" = "Darwin" ] && command -v dtruss >/dev/null 2>&1; then
    if dtruss "$BIN" -n2 "$tmp/in" >/dev/null 2>"$tmp/trace"; then
        grep -Eq '\b(mmap|brk)\(' "$tmp/trace" && { echo "FAIL trace: heap syscall"; exit 1; }
        echo "PASS trace/head (dtruss)"; exit 0
    fi
    echo "SKIP trace/head: dtruss unavailable (needs sudo / SIP)"; exit 0
fi

echo "SKIP trace/head: no tracer on this platform"; exit 0
