# Implementation Plan: uolt-dirname

**Branch**: `main` (spec dir `011-uolt-dirname`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/011-uolt-dirname/spec.md`

## Summary

`uolt-dirname` prints the directory part of its string operand, following the POSIX algorithm.
It is the sibling of `uolt-basename`: the same in-place scan of the argv operand, but it keeps
everything before the last component (as `.` or `/` at the extremes) instead of the component
itself. Pure string work - no files, no buffer; reuses `write`/`strlen`, no new syscall.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang integrated assembler for both OSes  
**Primary Dependencies**: No runtime library. `make` drives clang. Linux static; macOS loader stub  
**Storage**: Writes stdout/stderr only. No files, no heap  
**Testing**: unit, POSIX, differential vs reference `dirname`, fuzz (random path-like strings)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: at worst parity; measured ~1.4× faster (startup-bound)  
**Constraints**: binary size < 1 KB (Linux); no heap; no file I/O  
**Scale/Scope**: one executable; one syscall used (`write`)

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only Production Code | PASS | `dirname.S` is pure assembly |
| II. Direct Syscalls Only | PASS | only `write`; no libc |
| III. Zero Dependencies, Fully Static | PASS | Linux static; macOS loader-only stub |
| IV. No Heap, No Hidden Allocation | PASS | operates in place on argv; no buffer |
| V. Thin Syscall Abstraction + Internal API | PASS | calls `uolt_write`/`uolt_strlen` |
| VI. Minimal Size (Targeted) | PASS | 688 B on Linux, < 1 KB target |
| VII. Optimization: Measured, Never Premature | PASS | trivial; measured |
| VIII. POSIX, Not GNU | PASS | single-operand form; no `-z` |
| IX. Readable & Explicit | PASS | algorithm steps named and commented |
| X. Documentation as Pedagogy + README | PASS | README row + commented rationale |
| XI. Tested & Benchmarked | PASS | four test layers + size/speed |

**Result**: All gates pass. No violations.

## Project Structure

```text
src/dirname/dirname.S    # trailing-slash strip, last-slash search, separator strip,
                         #   ".", "/", or the directory byte range written once
tests/{unit,posix,differential,fuzz}/dirname.sh
```

No new `sys/` or `libuolt/` files: `EXTRA_dirname` is `strlen` + `write`.

**Structure Decision**: Computes the end index (after stripping trailing slashes), finds the
last '/', then strips that separator (and repeats) to get the directory length; writes that byte
range, or the single-byte `.`/`/` constants at the extremes, plus a newline. No copy is made -
the same approach as `uolt-basename`.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
