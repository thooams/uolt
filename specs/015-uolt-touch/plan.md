# Implementation Plan: uolt-touch

**Branch**: `main` (spec dir `015-uolt-touch`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-touch` creates missing files and stamps access/modification times to now, with `-c` to
skip creation. It adds two per-OS primitives - `create` (open O_WRONLY|O_CREAT) and `utimes`
(NULL = now) - and reuses `close`/`write`/`strlen`. O_CREAT differs by OS, which is why `create`
is a per-OS wrapper.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: creates/stamps files; no heap  
**Testing**: unit (create/update/-c/mtime), differential vs system `touch`  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity (syscall-bound)  
**Constraints**: < 1 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; open-create/close/utimes (+ write) syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `touch.S` + wrappers are assembly |
| II. Direct Syscalls | PASS | open/close/utimes direct |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | no buffer |
| V. Syscall Abstraction | PASS | `uolt_create`/`uolt_utimes`; numbers + O_CREAT flag in `sys/<os>/` |
| VI. Minimal Size | PASS | 912 B on Linux |
| VII. Measured Optimization | PASS | trivial |
| VIII. POSIX, Not GNU | PASS | -c/-a/-m; -r/-t deferred |
| IX. Readable & Explicit | PASS | named constants; per-OS flag documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | two test layers |

**Result**: All gates pass.

## Project Structure

```text
sys/linux/create.S  sys/macos/create.S   # open O_WRONLY|O_CREAT (flag 0x41 / 0x201)
sys/linux/utimes.S  sys/macos/utimes.S   # SYS_UTIMES 235 / 0x200008A
libuolt/create.S    libuolt/utimes.S     # uolt_create / uolt_utimes
src/touch/touch.S                        # option scan, create+close, utimes(NULL)
tests/{unit,differential}/touch.sh
```

**Structure Decision**: For each operand, unless -c, `uolt_create(path, 0666)` opens the file
O_WRONLY|O_CREAT (the flag value is OS-specific, hidden in the wrapper) and it is closed; then
`uolt_utimes(path, NULL)` stamps both times to now. Under -c a missing file's ENOENT from utimes
is ignored. No buffer is used.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
