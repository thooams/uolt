# Implementation Plan: uolt-tail

**Branch**: `main` (spec dir `007-uolt-tail`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/007-uolt-tail/spec.md`

## Summary

`uolt-tail` is the POSIX `tail` utility: it writes the last N lines (default 10, `-n` sets N,
`-n +N` starts at line N) of each file operand or standard input, with `==> name <==` headers
for multiple operands. Finding the *last* N lines without a heap is the crux: on a regular file
it seeks to the end and scans fixed 64 KB blocks backwards until the Nth newline, then copies
forward from there; on a non-seekable stream it keeps a sliding 64 KB window. It adds one
syscall wrapper, `lseek`, and otherwise reuses the file-I/O primitives from `uolt-cat`/
`uolt-head`.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax via `.intel_syntax noprefix`, clang
integrated assembler for both OSes  
**Primary Dependencies**: No runtime library. Build-time: clang `as` + linker driven by `make`.
Linux fully static; macOS carries the `libSystem.dylib` loader stub (zero calls into it)  
**Storage**: Reads regular files and stdin; writes stdout/stderr. No temp files, no heap  
**Testing**: unit, POSIX, differential vs reference `tail`, fuzz (file + pipe paths), trace  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: at worst parity with system `tail`; measured ~1.1× (parity) on a 38 MB
file because the backward seek avoids reading the whole file  
**Constraints**: binary size < 2 KB (Linux); no heap; window on the stack; no raw syscall number
in tool code (only `uolt_lseek`/`uolt_read`/`uolt_open`/`uolt_close`/`uolt_write`/`uolt_strlen`)  
**Scale/Scope**: one executable (`uolt-tail`); syscalls open/read/close/lseek/write (+ exit)

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only Production Code | PASS | `tail.S` + the new `lseek` wrappers are pure assembly |
| II. Direct Syscalls Only | PASS | open/read/close/lseek/write issued directly; no libc |
| III. Zero Dependencies, Fully Static | PASS | Linux static; macOS loader-only stub |
| IV. No Heap, No Hidden Allocation | PASS | Backward seek on files; a fixed 2*64 KB stack window on pipes; trace asserts no mmap/brk |
| V. Thin Syscall Abstraction + Internal API | PASS | Tool calls `uolt_*`; numbers stay in `sys/<os>/`; `lseek` added per OS |
| VI. Minimal Size (Targeted) | PASS | 1976 B on Linux, < 2 KB target |
| VII. Optimization: Measured, Never Premature | PASS | Backward seek chosen to meet the perf floor on large files; measured |
| VIII. POSIX, Not GNU | PASS | POSIX `tail` with `-n` (and `+N`); no `-c`/`-f` |
| IX. Readable & Explicit | PASS | Named constants; the two run-time paths are documented; no magic numbers |
| X. Documentation as Pedagogy + README | PASS | README row + heavily commented rationale |
| XI. Tested & Benchmarked | PASS | Five test layers (fuzz covers both paths) + benchmark vs system `tail` |

**Result**: All gates pass. No violations, no entries in Complexity Tracking.

## Project Structure

```text
sys/linux/lseek.S  sys/macos/lseek.S    # SYS_LSEEK 8 / 0x20000C7 (carry -> negative)
libuolt/lseek.S                          # uolt_lseek(fd, offset, whence)

src/tail/tail.S    # option scan (-n / +N / --), last_lines (seek+backscan),
                   #   last_lines_pipe (sliding window), forward_from_line (+N),
                   #   copy_to_eof / read_exact / emit / print_header helpers

tests/{unit,posix,differential,fuzz,trace}/tail.sh
bench/run.sh       # tail size + big-file timing added
```

**Structure Decision**: Adds only the `lseek` wrapper trio; everything else reuses the
`uolt-cat`/`uolt-head` primitives. The backward scan spans `lseek` and `read_exact` calls that
clobber the caller-saved registers, so its running state (newline count, first-byte flag, chunk
size) lives in rbp-relative stack locals; the durable pointers (fd, N, chunk base) stay in
callee-saved registers. Seekability is detected by the sign of `lseek(SEEK_END)` (`-ESPIPE` on a
pipe), which selects the sliding-window fallback.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
