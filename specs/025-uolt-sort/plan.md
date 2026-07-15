# Implementation Plan: uolt-sort

**Branch**: `main` (spec dir `025-uolt-sort`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-sort` reads all input into a growable mmap'd text region, records each line's start pointer
in a growable mmap'd array, sorts the pointers by C-locale byte comparison (stable bottom-up merge
sort; `-r` reverses), and writes the lines through a 64 KB output buffer. The regions grow on
demand (double, copy, unmap), so there is no silent truncation; the practical limit is memory.
(Amended 2026-07-15: the original v1 used fixed 1 MB stack buffers and an insertion sort.)

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: reads files/stdin, writes stdout; no heap (bounded stack buffers)  
**Testing**: unit, differential vs `LC_ALL=C sort` (+ fuzz)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity with system sort on large input (buffered output + O(n log n))  
**Constraints**: < 3 KB Linux; explicit failure-checked mmap only (no libc heap); no raw syscall number  
**Scale/Scope**: one executable; open/read/close/write syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `sort.S` is assembly |
| II. Direct Syscalls | PASS | open/read/close/write direct |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | explicit, failure-checked mmap for the growable regions (Principle IV permits mmap when a fixed buffer cannot do the job); no libc heap |
| V. Syscall Abstraction | PASS | `uolt_*`; adds mmap/munmap wrappers |
| VI. Minimal Size | PASS | 2232 B on Linux (target < 3 KB; rework justified by unbounded input + O(n log n) + buffered output) |
| VII. Optimization: Measured, Never Premature | PASS | merge sort + buffered output measured at parity with GNU sort on 1 M lines; the merge inner loop is a future, measured micro-optimization |
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
