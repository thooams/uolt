# Implementation Plan: uolt-mv

**Branch**: `main` (spec dir `018-uolt-mv`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-mv` renames a source to a target with the rename syscall (two-operand form). It adds the
per-OS `rename` wrapper and reuses `write`/`strlen`. Moving into a directory and cross-device
moves are out of scope in v1.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: renames; no heap  
**Testing**: unit, differential vs system `mv` (rename cases)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity (syscall-bound)  
**Constraints**: < 1 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; rename (+ write) syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `mv.S` + wrapper are assembly |
| II. Direct Syscalls | PASS | rename direct |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | no buffer |
| V. Syscall Abstraction | PASS | `uolt_rename`; number in `sys/<os>/` |
| VI. Minimal Size | PASS | 664 B on Linux |
| VII. Measured Optimization | PASS | trivial |
| VIII. POSIX, Not GNU | PASS | two-operand form; dir-target/cross-device deferred |
| IX. Readable & Explicit | PASS | documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | two test layers |

**Result**: All gates pass.

## Project Structure

```text
sys/{linux,macos}/rename.S    # SYS_RENAME 82 / 0x2000080 (carry -> negative)
libuolt/rename.S              # uolt_rename(oldpath, newpath)
src/mv/mv.S                   # "--", two-operand rename, diagnostic
tests/{unit,differential}/mv.sh
```

**Structure Decision**: After an optional `--`, exactly two operands are required; `uolt_rename`
performs the move, and any error is reported with exit 1. The dir-target and cross-device cases
that need stat / copy+unlink are deferred.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
