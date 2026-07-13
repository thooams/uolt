# Implementation Plan: uolt-sleep

**Branch**: `main` (spec dir `012-uolt-sleep`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/012-uolt-sleep/spec.md`

## Summary

`uolt-sleep` parses one or more decimal time operands (with optional fraction and s/m/h/d
suffix), sums them in nanoseconds, and suspends for that long. The sleep primitive is per-OS
behind `uolt_sleep(sec, nsec)`: `nanosleep` on Linux (resumed on -EINTR), `select` on macOS,
which has no direct `nanosleep` syscall.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang integrated assembler for both OSes  
**Primary Dependencies**: No runtime library. `make` drives clang. Linux static; macOS loader stub  
**Storage**: No files, no heap; the time struct is on the stack  
**Testing**: unit (timing bands), POSIX (integer seconds + errors), trace (nanosleep, no heap)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity by construction (dominated by the sleep itself)  
**Constraints**: binary size < 1 KB (Linux); no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; sleep primitive (+ write for diagnostics)

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only Production Code | PASS | `sleep.S` + per-OS `sleep` primitive are assembly |
| II. Direct Syscalls Only | PASS | nanosleep (Linux) / select (macOS) issued directly |
| III. Zero Dependencies, Fully Static | PASS | Linux static; macOS loader-only stub |
| IV. No Heap, No Hidden Allocation | PASS | time struct on the stack; trace asserts no mmap/brk |
| V. Thin Syscall Abstraction + Internal API | PASS | tool calls `uolt_sleep`; numbers live in `sys/<os>/` |
| VI. Minimal Size (Targeted) | PASS | 960 B on Linux, < 1 KB target |
| VII. Optimization: Measured, Never Premature | PASS | trivial; timing verified |
| VIII. POSIX, Not GNU | PASS | integer seconds is POSIX; fraction/suffix/sum are documented GNU extras |
| IX. Readable & Explicit | PASS | named constants; parser and the per-OS sleep documented |
| X. Documentation as Pedagogy + README | PASS | README row + commented rationale |
| XI. Tested & Benchmarked | PASS | three test layers; timing is the benchmark |

**Result**: All gates pass. No violations.

## Project Structure

```text
sys/linux/sleep.S   sys/macos/sleep.S    # nanosleep(35) / select(0x200005D)
libuolt/sleep.S                           # uolt_sleep(sec, nsec)
src/sleep/sleep.S                         # duration parser + sum + uolt_sleep call
tests/{unit,posix,trace}/sleep.sh
```

**Structure Decision**: The interesting part is the per-OS sleep. macOS has no `nanosleep`
syscall (verified: it is absent from the SDK's `syscall.h`, only `__semwait_signal` exists), so
`sys/macos/sleep.S` uses `select` with a timeout and no descriptors; `sys/linux/sleep.S` uses
`nanosleep` with an -EINTR resume loop. Both build their time struct on the stack and expose the
same `uolt_sleep(sec, nsec)`. The tool stays OS-agnostic: it parses, sums nanoseconds, splits
into seconds/nanoseconds, and calls `uolt_sleep`.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
