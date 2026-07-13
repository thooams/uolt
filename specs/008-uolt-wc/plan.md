# Implementation Plan: uolt-wc

**Branch**: `main` (spec dir `008-uolt-wc`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/008-uolt-wc/spec.md`

## Summary

`uolt-wc` is the POSIX `wc` utility: it counts lines, words, and bytes of each file operand or
of standard input, with `-l`/`-w`/`-c` selecting the columns and a `total` line for multiple
files. Counting is a single byte-at-a-time pass over 64 KB read blocks (no heap), keeping the
three counts and an in-word flag in registers. It is the first UOLT tool to format numbers, so
it adds an integer-to-decimal helper; it adds no new syscall.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax via `.intel_syntax noprefix`, clang
integrated assembler for both OSes  
**Primary Dependencies**: No runtime library. Build-time: clang `as` + linker driven by `make`.
Linux fully static; macOS carries the `libSystem.dylib` loader stub  
**Storage**: Reads regular files and stdin; writes stdout/stderr. No temp files, no heap  
**Testing**: unit, POSIX, differential vs reference `wc` (LC_ALL=C, whitespace-normalized),
fuzz, trace  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: at worst parity; measured ~11× faster on ~50 MB (byte-based C-locale scan
vs the stock tool's default multibyte pass)  
**Constraints**: binary size < 2 KB (Linux); no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable (`uolt-wc`); syscalls open/read/close/write (+ exit)

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only Production Code | PASS | `wc.S` is pure assembly; reuses existing wrappers |
| II. Direct Syscalls Only | PASS | open/read/close/write direct; no libc |
| III. Zero Dependencies, Fully Static | PASS | Linux static; macOS loader-only stub |
| IV. No Heap, No Hidden Allocation | PASS | One 64 KB buffer; counts in regs/locals; trace asserts no mmap/brk |
| V. Thin Syscall Abstraction + Internal API | PASS | Calls `uolt_*`; no new syscall |
| VI. Minimal Size (Targeted) | PASS | 1368 B on Linux, < 2 KB target |
| VII. Optimization: Measured, Never Premature | PASS | Simple byte scan; measured much faster than stock |
| VIII. POSIX, Not GNU | PASS | `-l`/`-w`/`-c`, fixed output order; no `-m`, no locale word rules |
| IX. Readable & Explicit | PASS | Named constants and locals; the number formatter is self-contained |
| X. Documentation as Pedagogy + README | PASS | README row (+ speedup caveat) + commented rationale |
| XI. Tested & Benchmarked | PASS | Five test layers + benchmark vs system `wc` |

**Result**: All gates pass. No violations, no entries in Complexity Tracking.

## Project Structure

```text
src/wc/wc.S    # option scan (-l/-w/-c, combined, --), count_fd (byte scan),
               #   emit_line + put_uint/put_str/put_char formatters, totals

tests/{unit,posix,differential,fuzz,trace}/wc.sh
bench/run.sh   # wc size + big-file timing added
```

No new `sys/` or `libuolt/` files: `uolt-wc` links the same `EXTRA` set as `uolt-cat`.

**Structure Decision**: Reuses the cat/head/tail file-I/O primitives. `count_fd` scans each read
block once, updating lines/words/bytes and an in-word flag held in registers the kernel preserves
across the read syscall (r8-r10, r12). Output formatting is new: `put_uint` divides down into a
20-byte stack scratch, and `emit_line` prints the enabled columns in the fixed order lines,
words, bytes. The show mask lives in r12; per-file and running totals live in rbp stack locals.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
