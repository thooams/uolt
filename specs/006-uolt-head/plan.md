# Implementation Plan: uolt-head

**Branch**: `main` (spec dir `006-uolt-head`) | **Date**: 2026-07-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/006-uolt-head/spec.md`

## Summary

`uolt-head` is the POSIX `head` utility: it writes the first N lines (default 10, set by `-n`)
of each file operand, or of standard input, to standard output. With more than one operand it
prints `==> name <==` section headers. It is the first UOLT tool that interprets its input:
each 64 KB read block is scanned for the cut point (the Nth newline) and the consumed prefix is
drained to stdout. It reuses the file-I/O primitives introduced by `uolt-cat`, adding no new
syscall wrapper.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax via `.intel_syntax noprefix`, clang
integrated assembler for both OSes  
**Primary Dependencies**: No runtime library. Build-time: clang `as` + linker driven by `make`.
Linux fully static; macOS carries the `libSystem.dylib` loader stub (zero calls into it)  
**Storage**: Reads regular files and stdin; writes stdout/stderr. No temp files, no heap  
**Testing**: unit, POSIX, differential vs reference `head`, fuzz (random contents/counts), trace  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: at worst parity with system `head`; measured ~1.6× faster on Linux  
**Constraints**: binary size < 2 KB (Linux); no heap; buffer on the stack; no raw syscall number
in tool code (only `uolt_read`/`uolt_open`/`uolt_close`/`uolt_write`/`uolt_strlen`)  
**Scale/Scope**: one executable (`uolt-head`); syscalls open/read/close/write (+ exit)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only Production Code | PASS | `head.S` is pure assembly; reuses existing wrappers |
| II. Direct Syscalls Only | PASS | open/read/close/write issued directly; no libc |
| III. Zero Dependencies, Fully Static | PASS | Linux static; macOS loader-only stub |
| IV. No Heap, No Hidden Allocation | PASS | One 64 KB stack buffer; trace asserts no mmap/brk |
| V. Thin Syscall Abstraction + Internal API | PASS | Tool calls `uolt_*`; numbers stay in `sys/<os>/` |
| VI. Minimal Size (Targeted) | PASS | 1336 B on Linux, < 2 KB target |
| VII. Optimization: Measured, Never Premature | PASS | Block scan + full-block writes; measured vs system |
| VIII. POSIX, Not GNU | PASS | POSIX `head` with `-n` only; no GNU `-c`/`-q`/`-v` |
| IX. Readable & Explicit | PASS | Named constants; header/diagnostic lengths via literals or strlen, no magic numbers |
| X. Documentation as Pedagogy + README | PASS | README row + heavily commented rationale |
| XI. Tested & Benchmarked | PASS | Five test layers + benchmark vs system `head` |

**Result**: All gates pass. No violations, no entries in Complexity Tracking.

## Project Structure

### Source Code (repository root)

```text
src/head/head.S          # option scan (-n / --), per-operand copy-first-N loop,
                         #   64 KB block newline scan, multi-file headers

tests/{unit,posix,differential,fuzz,trace}/head.sh
bench/run.sh             # head size + timing added
```

No new `sys/` or `libuolt/` files: `uolt-head` links the same `EXTRA` set as `uolt-cat`
(`open`/`read`/`close`/`write`/`strlen`).

**Structure Decision**: Reuses the file-I/O primitives from `uolt-cat`. The new logic is
entirely inside `head.S`: a `-n` option parser (`parse_uint`), a per-descriptor `head_fd` that
scans each read block for the Nth newline and emits the consumed prefix via a short-write-safe
`emit`, and a `print_header` for the `==> name <==` layout. Line count N and the walk pointers
live in callee-saved registers; the operand count and header/first-output flags live in three
stack locals (there are more live values than callee-saved registers).

## Complexity Tracking

> No constitution violations. Section intentionally empty.
