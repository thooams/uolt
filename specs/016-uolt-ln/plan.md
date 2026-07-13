# Implementation Plan: uolt-ln

**Branch**: `main` (spec dir `016-uolt-ln`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-ln` creates hard or symbolic links (`-s`), replacing an existing target with `-f`, in the
one/two-operand form. It adds per-OS `link`/`symlink`/`unlink` wrappers (unlink reused by `rm`)
and reuses `write`/`strlen`. The implicit target is the basename tail of the source string, so no
buffer is needed.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: creates links; no heap  
**Testing**: unit, differential vs system `ln` (name/type/target signature)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity (syscall-bound)  
**Constraints**: < 1 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; link/symlink/unlink (+ write) syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `ln.S` + wrappers are assembly |
| II. Direct Syscalls | PASS | link/symlink/unlink direct |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | implicit target is a tail pointer into the source |
| V. Syscall Abstraction | PASS | `uolt_link`/`uolt_symlink`/`uolt_unlink`; numbers in `sys/<os>/` |
| VI. Minimal Size | PASS | 904 B on Linux |
| VII. Measured Optimization | PASS | trivial |
| VIII. POSIX, Not GNU | PASS | -s/-f; multi-source-into-dir deferred |
| IX. Readable & Explicit | PASS | flags and forms documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | two test layers |

**Result**: All gates pass.

## Project Structure

```text
sys/{linux,macos}/{link,symlink,unlink}.S    # 86/88/87 (Linux), 0x2000009/0x2000039/0x200000A
libuolt/{link,symlink,unlink}.S              # uolt_link / uolt_symlink / uolt_unlink
src/ln/ln.S                                  # option scan, target resolution, link/symlink
tests/{unit,differential}/ln.sh
```

**Structure Decision**: Option scan sets -s/-f. The target is the second operand, or the
basename tail of the source when only one is given. With -f, `uolt_unlink(target)` runs first
(result ignored); then `uolt_symlink` or `uolt_link(source, target)`. A failure is reported and
sets exit 1.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
