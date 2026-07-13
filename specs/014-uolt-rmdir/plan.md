# Implementation Plan: uolt-rmdir

**Branch**: `main` (spec dir `014-uolt-rmdir`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-rmdir` removes empty directories, with `-p` to remove the ancestor chain. Sibling of
`uolt-mkdir`: it adds the per-OS `rmdir` syscall wrapper and reuses `write`/`strlen`. The `-p`
walk shortens the operand string in place (terminating at each ancestor), so no buffer is used.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: removes directories; no heap  
**Testing**: unit, differential vs system `rmdir` (sandboxed trees)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity (syscall-bound)  
**Constraints**: < 1 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; rmdir (+ write) syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `rmdir.S` + wrapper are assembly |
| II. Direct Syscalls | PASS | rmdir issued directly |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | `-p` walk edits argv in place |
| V. Syscall Abstraction | PASS | calls `uolt_rmdir`; number in `sys/<os>/` |
| VI. Minimal Size | PASS | 848 B on Linux |
| VII. Measured Optimization | PASS | trivial |
| VIII. POSIX, Not GNU | PASS | `-p` only |
| IX. Readable & Explicit | PASS | `-p` walk documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | two test layers |

**Result**: All gates pass.

## Project Structure

```text
sys/linux/rmdir.S  sys/macos/rmdir.S    # SYS_RMDIR 84 / 0x2000089 (carry -> negative)
libuolt/rmdir.S                          # uolt_rmdir(path)
src/rmdir/rmdir.S                        # option scan, plain + -p remove, diagnostics
tests/{unit,differential}/rmdir.sh
```

**Structure Decision**: Plain remove is one `uolt_rmdir(path)`. `-p` strips trailing slashes,
removes the target, then repeatedly cuts the last component (and its slashes) and removes the
parent, stopping at the first failure. The end index is kept in a callee-saved register across
the rmdir syscalls.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
