# Implementation Plan: uolt-echo

**Branch**: `main` (spec dir `003-uolt-echo`) | **Date**: 2026-07-12 | **Spec**: [spec.md](./spec.md)

## Summary

First tool with real I/O and argument reading. Introduces a per-OS entry shim and two libuolt
helpers, all reused by later tools.

## Technical Context

Same as prior tools (x86_64 asm, Intel syntax, clang/`as`, platform-aware linkage). New this
feature:
- **Entry-argument ABI differs by OS** (verified empirically): Linux passes argc/argv on the
  stack at `_start`; macOS (LC_MAIN) passes argc in `rdi`, argv in `rsi`. Resolved with a
  per-OS entry shim `sys/<os>/start.S` that normalizes to `uolt_main(argc, argv)` and exits
  with its return value. `true`/`false` were refactored to this `uolt_main` convention too.
- **Output** via `write` syscall through a new `libuolt/write.S` (uolt_write) over per-OS
  `sys/<os>/write.S`; string length via `libuolt/strlen.S`.

## Constitution Check

| Principle | Status | Note |
|-----------|--------|------|
| I–V, VIII–XI | PASS | pure asm, direct syscalls, no heap, per-OS abstraction, POSIX, tested |
| VI (size) | PASS on Linux (608 B < 3 KB); macOS ~5 KB Mach-O floor (documented) |
| VII (opt) | PASS | one write per piece now; writev is a deferred, measured optimization |

## Project Structure

New/changed:

```text
sys/linux/start.S, sys/macos/start.S     # per-OS entry shim -> uolt_main(argc, argv)
sys/linux/write.S, sys/macos/write.S     # write syscall wrappers
libuolt/write.S                          # uolt_write(fd, buf, len)
libuolt/strlen.S                         # uolt_strlen(ptr) -> len
src/echo/echo.S                          # the tool
src/true/true.S, src/false/false.S       # refactored to uolt_main
Makefile                                 # COMMON += start; EXTRA_echo; single clang link
tests/{unit,posix,differential,fuzz,trace}/echo.sh
README.md
```

**Structure Decision**: The entry shim and `libuolt` write/strlen are the reusable additions;
every future tool that reads argv or writes output uses them. The Makefile now links each tool
as `src + COMMON + EXTRA_<tool>` in one clang invocation.

## Complexity Tracking

> No violations.
