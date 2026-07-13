# Implementation Plan: uolt-cp

**Branch**: `main` (spec dir `019-uolt-cp`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-cp` copies a source file's bytes to a target (two-operand form), streaming through one
64 KB stack buffer. It adds the per-OS `opendst` primitive (open O_WRONLY|O_CREAT|O_TRUNC) and
reuses `open`/`read`/`write`/`close`/`strlen`. Recursive/dir/same-file/preservation are deferred.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: copies file contents; no heap  
**Testing**: unit, differential vs system `cp` (content + exit)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity (I/O-bound)  
**Constraints**: < 1 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; open/read/write/close/opendst syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `cp.S` + wrapper are assembly |
| II. Direct Syscalls | PASS | open/read/write/close direct |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | one 64 KB stack buffer |
| V. Syscall Abstraction | PASS | `uolt_opendst` etc.; flags/numbers in `sys/<os>/` |
| VI. Minimal Size | PASS | 952 B on Linux |
| VII. Measured Optimization | PASS | block copy; measured |
| VIII. POSIX, Not GNU | PASS | two-operand form; -r/dir/preserve deferred |
| IX. Readable & Explicit | PASS | copy loop + per-OS flag documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | two test layers |

**Result**: All gates pass.

## Project Structure

```text
sys/{linux,macos}/opendst.S    # open O_WRONLY|O_CREAT|O_TRUNC (0x241 / 0x601)
libuolt/opendst.S              # uolt_opendst(path, mode)
src/cp/cp.S                    # open src, opendst dst, 64 KB copy loop, close, diagnostics
tests/{unit,differential}/cp.sh
```

**Structure Decision**: Open the source O_RDONLY and the target O_WRONLY|O_CREAT|O_TRUNC (the
O_TRUNC flag value is OS-specific, hidden in `opendst`), then copy in 64 KB blocks draining short
writes, and close both. Any error closes open descriptors and reports with exit 1.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
