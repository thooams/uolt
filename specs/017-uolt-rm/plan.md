# Implementation Plan: uolt-rm

**Branch**: `main` (spec dir `017-uolt-rm`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-rm` removes files with unlink, with `-f` to ignore missing operands. Recursive removal is
deferred (it needs directory reading, built later with `ls`). Reuses the `unlink` wrapper from
`ln` plus `write`/`strlen`.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: removes files; no heap  
**Testing**: unit, differential vs system `rm` (file cases)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity (syscall-bound)  
**Constraints**: < 1 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; unlink (+ write) syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `rm.S` is assembly |
| II. Direct Syscalls | PASS | unlink direct |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | no buffer |
| V. Syscall Abstraction | PASS | `uolt_unlink`; number in `sys/<os>/` |
| VI. Minimal Size | PASS | 744 B on Linux |
| VII. Measured Optimization | PASS | trivial |
| VIII. POSIX, Not GNU | PASS | -f; -r/-i deferred |
| IX. Readable & Explicit | PASS | flags documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | two test layers |

**Result**: All gates pass.

## Project Structure

```text
src/rm/rm.S                       # option scan (-f, --), unlink loop, diagnostics
tests/{unit,differential}/rm.sh
```

Reuses `libuolt/unlink.S` + `sys/<os>/unlink.S` (from `ln`); no new wrapper.

**Structure Decision**: Each operand is unlinked. Under -f, an -ENOENT is ignored (no diagnostic,
no status change) and an empty operand list is a success; other errors diagnose and set exit 1. A
directory naturally fails (EISDIR/EPERM), which is the intended v1 behavior.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
