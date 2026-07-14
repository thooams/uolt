# Implementation Plan: uolt-sort

**Branch**: `main` (spec dir `025-uolt-sort`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-sort` reads all input into a fixed 1 MB text buffer, records each line's start pointer in a
fixed array, sorts the pointers by C-locale byte comparison (in-place insertion sort; `-r`
reverses), and writes the lines out. Both buffers are on the stack (no heap); input beyond the
buffer is dropped.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: reads files/stdin, writes stdout; no heap (bounded stack buffers)  
**Testing**: unit, differential vs `LC_ALL=C sort` (+ fuzz)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity for the bounded input  
**Constraints**: < 2 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; open/read/close/write syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `sort.S` is assembly |
| II. Direct Syscalls | PASS | open/read/close/write direct |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | fixed text buffer + pointer array on the stack; documented bound |
| V. Syscall Abstraction | PASS | `uolt_*`; no new syscall |
| VI. Minimal Size | PASS | 1016 B on Linux |
| VII. Optimization: Measured, Never Premature | PASS | insertion sort adequate for the bounded size; a faster sort is a future, measured change |
| VIII. POSIX, Not GNU | PASS | whole-line byte sort + -r; -n/-u/-k deferred |
| IX. Readable & Explicit | PASS | read/split/sort/emit phases documented; sign-extension noted |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | two test layers incl. fuzz |

**Result**: All gates pass.

## Project Structure

```text
src/sort/sort.S    # read-all, split into NUL-terminated lines, insertion sort, emit
tests/{unit,differential}/sort.sh
```

**Structure Decision**: Input is read into the text buffer (`read_into` per file/stdin). The
split phase replaces each newline with NUL and records the line's start in the pointer array.
`line_cmp` is an unsigned byte comparison of two NUL-terminated lines (sign-extended so the
64-bit result carries the correct sign). The insertion sort shifts by that comparison, flipped
for `-r`. Finally each line is written with a trailing newline.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
