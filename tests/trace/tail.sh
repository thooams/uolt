#!/bin/sh
# Syscall-trace test for uolt-tail on a regular (seekable) file: it may
# open/read/close/lseek and write (plus exit), and that path must stay
# allocation-free (no mmap/brk) - it seeks instead of buffering. (The
# non-seekable pipe path deliberately slurps via mmap; it is not traced here.)
# Best-effort like the other trace tests: fails on a real violation, SKIPs when
# tracing is unavailable.
set -u
BIN=${UOLT_TAIL:-${BUILD:-./build}/uolt-tail}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
i=1; : >"$tmp/in"; while [ "$i" -le 30 ]; do echo "l$i" >>"$tmp/in"; i=$((i+1)); done

os=$(uname -s)
if [ "$os" = "Linux" ] && command -v strace >/dev/null 2>&1; then
    strace -f -o "$tmp/trace" "$BIN" -n3 "$tmp/in" >/dev/null 2>&1
    if grep -Eq '\b(mmap|brk)\(' "$tmp/trace"; then
        echo "FAIL trace: heap syscall"; grep -E '\b(mmap|brk)\(' "$tmp/trace"; exit 1
    fi
    grep -Eq '\b(read|write)\(' "$tmp/trace" || { echo "FAIL trace: no read/write observed"; exit 1; }
    grep -Eq '\blseek\(' "$tmp/trace" || { echo "FAIL trace: no lseek on a regular file"; exit 1; }
    echo "PASS trace/tail (strace)"; exit 0
elif [ "$os" = "Darwin" ] && command -v dtruss >/dev/null 2>&1; then
    if dtruss "$BIN" -n3 "$tmp/in" >/dev/null 2>"$tmp/trace"; then
        grep -Eq '\b(mmap|brk)\(' "$tmp/trace" && { echo "FAIL trace: heap syscall"; exit 1; }
        echo "PASS trace/tail (dtruss)"; exit 0
    fi
    echo "SKIP trace/tail: dtruss unavailable (needs sudo / SIP)"; exit 0
fi

echo "SKIP trace/tail: no tracer on this platform"; exit 0
