# Implementation Plan: uolt-basename

**Branch**: `main` (spec dir `010-uolt-basename`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/010-uolt-basename/spec.md`

## Summary

`uolt-basename` prints the final path component of its string operand (with an optional suffix
removed), following the POSIX algorithm. It is pure string work on the argv operands: it opens no
files and allocates nothing, writing the result straight from the operand's own bytes. It reuses
`write`/`strlen` and adds no syscall.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang integrated assembler for both OSes  
**Primary Dependencies**: No runtime library. `make` drives clang. Linux static; macOS loader stub  
**Storage**: Writes stdout/stderr only. No files, no heap  
**Testing**: unit, POSIX, differential vs reference `basename`, fuzz (random path-like strings)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: at worst parity; measured ~1.4× faster (startup-bound)  
**Constraints**: binary size < 1 KB (Linux); no heap; no file I/O  
**Scale/Scope**: one executable; one syscall used (`write`)

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only Production Code | PASS | `basename.S` is pure assembly |
| II. Direct Syscalls Only | PASS | only `write`; no libc |
| III. Zero Dependencies, Fully Static | PASS | Linux static; macOS loader-only stub |
| IV. No Heap, No Hidden Allocation | PASS | operates in place on argv; no buffer |
| V. Thin Syscall Abstraction + Internal API | PASS | calls `uolt_write`/`uolt_strlen` |
| VI. Minimal Size (Targeted) | PASS | 728 B on Linux, < 1 KB target |
| VII. Optimization: Measured, Never Premature | PASS | trivial; measured |
| VIII. POSIX, Not GNU | PASS | one/two-operand form; no `-a`/`-s`/`-z` |
| IX. Readable & Explicit | PASS | algorithm steps named and commented |
| X. Documentation as Pedagogy + README | PASS | README row + commented rationale |
| XI. Tested & Benchmarked | PASS | four test layers + size/speed |

**Result**: All gates pass. No violations.

## Project Structure

```text
src/basename/basename.S    # trailing-slash strip, all-slash case, last component,
                           #   inline suffix compare, single write of the result
tests/{unit,posix,differential,fuzz}/basename.sh
```

No new `sys/` or `libuolt/` files: `EXTRA_basename` is `strlen` + `write`.

**Structure Decision**: The tool computes two indices into the operand string - the end (after
stripping trailing slashes) and the start of the last component - then writes that byte range
plus a newline. The suffix is removed by shortening the range only when it is a proper tail
match (equal length is left intact, per POSIX). No copy is made.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
