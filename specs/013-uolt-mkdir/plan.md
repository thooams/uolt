# Implementation Plan: uolt-mkdir

**Branch**: `main` (spec dir `013-uolt-mkdir`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-mkdir` creates directories, with `-p` to make missing parents (idempotent). It adds the
per-OS `mkdir` syscall wrapper and reuses `write`/`strlen`. The `-p` walk edits the operand
string in place (NUL-terminating each prefix, creating it, restoring the slash), so no buffer is
needed.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: creates directories; no heap  
**Testing**: unit, POSIX (umask modes), differential vs system `mkdir`  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity (syscall-bound)  
**Constraints**: < 1 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; mkdir (+ write) syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `mkdir.S` + wrapper are assembly |
| II. Direct Syscalls | PASS | mkdir issued directly |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | `-p` walk edits argv in place; no buffer |
| V. Syscall Abstraction | PASS | tool calls `uolt_mkdir`; number in `sys/<os>/` |
| VI. Minimal Size | PASS | 856 B on Linux |
| VII. Measured Optimization | PASS | trivial |
| VIII. POSIX, Not GNU | PASS | `-p` only; `-m` deferred |
| IX. Readable & Explicit | PASS | named constants; `-p` walk documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | three test layers |

**Result**: All gates pass.

## Project Structure

```text
sys/linux/mkdir.S  sys/macos/mkdir.S    # SYS_MKDIR 83 / 0x2000088 (carry -> negative)
libuolt/mkdir.S                          # uolt_mkdir(path, mode)
src/mkdir/mkdir.S                        # option scan, plain + -p create, diagnostics
tests/{unit,posix,differential}/mkdir.sh
```

**Structure Decision**: Plain create is one `uolt_mkdir(path, 0777)`. `-p` walks the path,
terminating at each '/' to create the prefix (ignoring EEXIST) and restoring the slash, then
creating the full path (EEXIST tolerated). The walk index is kept in a callee-saved register so
it survives the mkdir syscalls.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
