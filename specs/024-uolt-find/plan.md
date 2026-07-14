# Implementation Plan: uolt-find

**Branch**: `main` (spec dir `024-uolt-find`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-find` walks each starting path recursively and prints every path, with an optional
`-type f|d` filter. It reuses the `opendir`/`getdents` primitives from `ls`. Each directory level
keeps its own getdents buffer on the stack (so it survives recursion into children) while a single
path buffer is grown and truncated; entry types come from the directory entry's d_type, so
symlinks are not followed.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: reads directories, writes stdout; no heap  
**Testing**: unit, differential vs system `find` (sorted sets)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity (I/O-bound)  
**Constraints**: < 2 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; opendir/getdents/close/write syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `find.S` is assembly |
| II. Direct Syscalls | PASS | opendir/getdents/close/write direct |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | per-level dir buffer + one path buffer, all on the stack |
| V. Syscall Abstraction | PASS | reuses `uolt_opendir`/`uolt_getdents`; no new syscall |
| VI. Minimal Size | PASS | 1072 B on Linux |
| VII. Measured Optimization | PASS | recursion over d_type; measured |
| VIII. POSIX, Not GNU | PASS | listing + -type; -name/other predicates deferred |
| IX. Readable & Explicit | PASS | d_type classification + recursion documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | two test layers |

**Result**: All gates pass.

## Project Structure

```text
include/uolt.inc      # DIRENT_TYPE_OFF + DT_* values (added here)
src/find/find.S       # -type extraction, recursive find_entry over d_type, print_cur
tests/{unit,differential}/find.sh
```

**Structure Decision**: `find_entry(pathlen, d_type)` prints the path if it passes `-type`, and
for a directory reads it in 4 KB batches, appending each entry's name to the path buffer and
recursing with the entry's d_type. DT_DIR descends; DT_REG/DT_LNK/other print without descending;
DT_UNKNOWN (command-line operands, or filesystems without d_type) falls back to opening the path
(ENOTDIR => a file). The batch length and scan position live in the level's own stack frame so
they survive the recursion.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
