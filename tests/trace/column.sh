#!/bin/sh
# Syscall-trace test for uolt-column: it slurps stdin and buffers output through
# explicit, failure-checked mmap regions (Principle IV permits this for a
# whole-input tool), so its only syscalls are read, write, mmap, munmap and exit.
# The forbidden thing is a heap allocation: `brk` must never appear. Best-effort:
# fails on a real violation, SKIPs when tracing is unavailable.
set -u
BIN=${UOLT_COLUMN:-${BUILD:-./build}/uolt-column}
case "$BIN" in /*) ;; *) BIN="$PWD/${BIN#./}";; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'name size date\nfoo 1024 jul16\nbar 42 jul15\n' >"$tmp/in"

os=$(uname -s)
if [ "$os" = "Linux" ] && command -v strace >/dev/null 2>&1; then
    strace -f -o "$tmp/trace" "$BIN" <"$tmp/in" >/dev/null 2>&1
    if grep -Eq '\bbrk\(' "$tmp/trace"; then
        echo "FAIL trace: heap syscall (brk)"; grep -E '\bbrk\(' "$tmp/trace"; exit 1
    fi
    grep -Eq '\bread\(' "$tmp/trace"  || { echo "FAIL trace: no read observed"; exit 1; }
    grep -Eq '\bwrite\(' "$tmp/trace" || { echo "FAIL trace: no write observed"; exit 1; }
    echo "PASS trace/column (strace)"; exit 0
elif [ "$os" = "Darwin" ] && command -v dtruss >/dev/null 2>&1; then
    if dtruss "$BIN" <"$tmp/in" >/dev/null 2>"$tmp/trace"; then
        grep -Eq '\bbrk\(' "$tmp/trace" && { echo "FAIL trace: heap syscall (brk)"; exit 1; }
        echo "PASS trace/column (dtruss)"; exit 0
    fi
    echo "SKIP trace/column: dtruss unavailable (needs sudo / SIP)"; exit 0
fi

echo "SKIP trace/column: no tracer on this platform"; exit 0
