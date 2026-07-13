# Implementation Plan: uolt-yes

**Branch**: `main` (spec dir `009-uolt-yes`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/009-uolt-yes/spec.md`

## Summary

`uolt-yes` writes a line - the operands joined by spaces, or `y` - to stdout forever. Throughput
is the point, so it builds one copy of the line, replicates it to fill a 64 KB stack buffer, and
writes that buffer whole on every iteration (draining short writes), stopping on SIGPIPE / write
error. It reuses only `write` and `strlen`; no new syscall.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang integrated assembler for both OSes  
**Primary Dependencies**: No runtime library. `make` drives clang. Linux static; macOS loader stub  
**Storage**: Writes stdout only. No files, no heap  
**Testing**: unit, POSIX-style behavior, differential vs reference `yes`, trace (no fuzz - the
output is a fixed infinite stream)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity with system `yes` (pipe-bound)  
**Constraints**: binary size < 1 KB (Linux); no heap; buffer on the stack  
**Scale/Scope**: one executable; one syscall used (`write`)

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only Production Code | PASS | `yes.S` is pure assembly |
| II. Direct Syscalls Only | PASS | only `write`; no libc |
| III. Zero Dependencies, Fully Static | PASS | Linux static; macOS loader-only stub |
| IV. No Heap, No Hidden Allocation | PASS | 64 KB stack buffer; trace asserts no mmap/brk |
| V. Thin Syscall Abstraction + Internal API | PASS | calls `uolt_write`/`uolt_strlen` |
| VI. Minimal Size (Targeted) | PASS | 808 B on Linux, < 1 KB target |
| VII. Optimization: Measured, Never Premature | PASS | block writes chosen for throughput; measured |
| VIII. POSIX, Not GNU | N/A | `yes` is not POSIX; GNU join semantics chosen and documented |
| IX. Readable & Explicit | PASS | named constants; the two paths documented |
| X. Documentation as Pedagogy + README | PASS | README row + commented rationale |
| XI. Tested & Benchmarked | PASS | four test layers + size/throughput bench |

**Result**: All gates pass. No violations.

## Project Structure

```text
src/yes/yes.S    # line build, buffer replication (rep movsb), infinite drained write,
                 #   piecewise fallback for a line > 64 KB

tests/{unit,posix,differential,trace}/yes.sh
bench/run.sh     # yes size row added
```

No new `sys/` or `libuolt/` files: `EXTRA_yes` is just `strlen` + `write` (like `echo`).

**Structure Decision**: The line is assembled once at the buffer start, then replicated by
doubling copies (`rep movsb`) up to the largest whole multiple of its length that fits 64 KB.
The main loop writes that fill length, draining short writes to preserve line alignment, and
loops forever. A line longer than the buffer takes a piecewise path that writes the operands and
separators straight from argv each iteration.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
