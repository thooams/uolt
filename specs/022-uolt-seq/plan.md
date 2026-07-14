# Implementation Plan: uolt-seq

**Branch**: `main` (spec dir `022-uolt-seq`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-seq` prints an integer sequence (`seq [first [incr]] last`). It parses signed integer
operands, loops from first to last by incr, and formats each number into a small stack buffer.
Reuses `write`/`strlen`; no new syscall.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: writes stdout; no heap  
**Testing**: unit, differential vs system `seq` (integer ranges)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity  
**Constraints**: < 1 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; write syscall only

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `seq.S` is assembly |
| II. Direct Syscalls | PASS | only write |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | number buffer on the stack |
| V. Syscall Abstraction | PASS | `uolt_write`/`uolt_strlen`; no new syscall |
| VI. Minimal Size | PASS | 928 B on Linux |
| VII. Measured Optimization | PASS | trivial |
| VIII. POSIX, Not GNU | PASS | integers; floats/-w/-f/-s deferred |
| IX. Readable & Explicit | PASS | signed parse + format documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | two test layers |

**Result**: All gates pass.

## Project Structure

```text
src/seq/seq.S    # signed integer parse, ascending/descending loop, number format
tests/{unit,differential}/seq.sh
```

**Structure Decision**: `parse_int` reads a signed decimal (CF on error). The loop compares the
running value against `last` with the direction set by the sign of `incr`. `emit_num` divides the
value into a 32-byte stack buffer (with a leading '-' for negatives and a trailing newline) and
writes it in one call.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
