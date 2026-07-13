#!/bin/sh
# Syscall-trace test for uolt-ls: it opens the directory, reads it with the
# directory-read syscall, and writes; it must never allocate (mmap/brk). Linux
# uses getdents64, macOS getdirentries64. Best-effort: fails on a real violation,
# SKIPs when tracing is unavailable.
set -u
BIN=${UOLT_LS:-${BUILD:-./build}/uolt-ls}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
touch "$tmp/a" "$tmp/b"

os=$(uname -s)
if [ "$os" = "Linux" ] && command -v strace >/dev/null 2>&1; then
    strace -f -o "$tmp/trace" "$BIN" "$tmp" >/dev/null 2>&1
    if grep -Eq '\b(mmap|brk)\(' "$tmp/trace"; then
        echo "FAIL trace: heap syscall"; grep -E '\b(mmap|brk)\(' "$tmp/trace"; exit 1
    fi
    grep -Eq '\bgetdents' "$tmp/trace" || { echo "FAIL trace: no getdents observed"; exit 1; }
    echo "PASS trace/ls (strace)"; exit 0
elif [ "$os" = "Darwin" ] && command -v dtruss >/dev/null 2>&1; then
    if dtruss "$BIN" "$tmp" >/dev/null 2>"$tmp/trace"; then
        grep -Eq '\b(mmap|brk)\(' "$tmp/trace" && { echo "FAIL trace: heap syscall"; exit 1; }
        echo "PASS trace/ls (dtruss)"; exit 0
    fi
    echo "SKIP trace/ls: dtruss unavailable (needs sudo / SIP)"; exit 0
fi

echo "SKIP trace/ls: no tracer on this platform"; exit 0
