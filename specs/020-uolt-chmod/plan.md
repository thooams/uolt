# Implementation Plan: uolt-chmod

**Branch**: `main` (spec dir `020-uolt-chmod`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-chmod` parses an octal mode and applies it to each file operand with the chmod syscall. It
adds the per-OS `chmod` wrapper and reuses `write`/`strlen`. Symbolic modes (needing a stat) and
`-R` (needing directory reading) are deferred.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: changes file modes; no heap  
**Testing**: unit, differential vs system `chmod` (permission bits + exit)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity (syscall-bound)  
**Constraints**: < 1 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; chmod (+ write) syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `chmod.S` + wrapper are assembly |
| II. Direct Syscalls | PASS | chmod direct |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | no buffer |
| V. Syscall Abstraction | PASS | `uolt_chmod`; number in `sys/<os>/` |
| VI. Minimal Size | PASS | 816 B on Linux |
| VII. Measured Optimization | PASS | trivial |
| VIII. POSIX, Not GNU | PASS | octal modes; symbolic/-R deferred |
| IX. Readable & Explicit | PASS | octal parse documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | two test layers |

**Result**: All gates pass.

## Project Structure

```text
sys/{linux,macos}/chmod.S    # SYS_CHMOD 90 / 0x200000F (carry -> negative)
libuolt/chmod.S              # uolt_chmod(path, mode)
src/chmod/chmod.S            # octal parse, per-file chmod, diagnostics
tests/{unit,differential}/chmod.sh
```

**Structure Decision**: The first operand is parsed base-8 (each digit shifts the accumulator by
3 bits); a non-octal digit means a symbolic mode, which is rejected. The mode is then applied to
each remaining operand with `uolt_chmod`; failures diagnose and set exit 1.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
