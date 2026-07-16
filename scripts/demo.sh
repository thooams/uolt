#!/bin/sh
# scripts/demo.sh - a scripted terminal walkthrough of UOLT, for recording an
# asciinema cast (or just to watch).
#
#   asciinema rec uolt.cast -c "sh scripts/demo.sh"     # record
#   sh scripts/demo.sh                                  # just run it
#
# It builds the suite, shows how small it is, proves byte-for-byte compatibility
# against the system tools, and demonstrates sorting a file far larger than any
# fixed buffer. Pure POSIX sh; no dependencies beyond a shell and the toolchain.
#
# RECORD THIS ON LINUX. The size claims (44 KB suite, 384-byte `true`, smaller
# than one grep) hold for the static Linux ELF build; macOS Mach-O binaries carry
# a multi-KB loader floor and would contradict the narration. The behavioural
# parts (sort, wc, cmp = IDENTICAL) are the same on either OS.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

B=${BUILD:-build}            # honours the per-OS build dir (build-linux in CI/demo)
PAUSE=${PAUSE:-1.4}          # seconds between steps (set PAUSE=0 to go fast)

run() {                      # show the command, pause, run it, pause
    printf '\n$ %s\n' "$*"
    sleep "$PAUSE"
    sh -c "$*"
    sleep "$PAUSE"
}
say() { printf '\n# %s\n' "$*"; sleep "$PAUSE"; }

say "UOLT - 34 Unix tools, hand-written in x86_64 assembly. No libc, no heap."

say "Build the entire suite (one clang invocation per tool):"
run "make >/dev/null 2>&1 && ls $B | head"

say "The whole suite is smaller than a single stock grep binary:"
run "wc -c $B/uolt-* | tail -1"
run "wc -c \$(command -v grep)"

say "The smallest tool is 384 bytes - 21 of them are actual machine code:"
run "wc -c $B/uolt-true"

say "They behave like the real tools:"
run "printf 'banana\\napple\\ncherry\\n' | $B/uolt-sort"
run "printf 'one two three\\n' | $B/uolt-wc -w"
run "$B/uolt-echo hello, assembly"

say "Byte-for-byte identical to the system tools on a real file:"
run "seq 1 100000 | awk '{print int(rand()*99999)}' > /tmp/uolt_demo.txt"
run "$B/uolt-sort -n /tmp/uolt_demo.txt > /tmp/uolt_a.txt"
run "LC_ALL=C sort -n /tmp/uolt_demo.txt > /tmp/uolt_b.txt"
run "cmp /tmp/uolt_a.txt /tmp/uolt_b.txt && echo IDENTICAL"

say "A real alternative: sort scales past any fixed buffer (mmap-backed)."
run "wc -l /tmp/uolt_demo.txt"
run "$B/uolt-sort -n /tmp/uolt_demo.txt | tail -1"

say "Shadow the system coreutils on your PATH, fully reversibly:"
run "make install PREFIX=/tmp/uolt-demo 2>/dev/null | tail -2"
run "/tmp/uolt-demo/bin/wc -l /tmp/uolt_demo.txt"
run "make uninstall PREFIX=/tmp/uolt-demo 2>/dev/null | tail -1"

say "34 tools, ~44 KB on Linux, ~49x smaller than coreutils. MIT."
say "github.com/thooams/uolt"
printf '\n'
rm -f /tmp/uolt_demo.txt /tmp/uolt_a.txt /tmp/uolt_b.txt
