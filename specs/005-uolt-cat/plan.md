# Implementation Plan: uolt-cat

**Branch**: `main` (spec dir `005-uolt-cat`) | **Date**: 2026-07-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-uolt-cat/spec.md`

## Summary

`uolt-cat` is the POSIX `cat` utility: it concatenates its file operands (or standard input,
also selected by the operand `-`) to standard output, byte-for-byte. It is the first UOLT tool
that opens files and reads their contents, so it introduces the `read`, `open`, and `close`
syscall wrappers and their `libuolt` API entries. Data is streamed through a single 64 KB stack
buffer (no heap), each chunk drained to stdout in full to tolerate short writes.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax via `.intel_syntax noprefix`, clang
integrated assembler for both OSes  
**Primary Dependencies**: No runtime library. Build-time: clang `as` + linker driven by `make`.
Linux fully static; macOS carries the `libSystem.dylib` loader stub (zero calls into it)  
**Storage**: Reads regular files and stdin; writes stdout/stderr. No temp files, no heap  
**Testing**: unit, POSIX, differential vs reference `cat`, fuzz (random contents), syscall trace  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: at worst parity with system `cat`; measured ~1.7× faster on Linux  
**Constraints**: binary size < 2 KB (Linux); no heap; buffer on the stack; no raw syscall number
in tool code (only `uolt_read`/`uolt_open`/`uolt_close`/`uolt_write`)  
**Scale/Scope**: one executable (`uolt-cat`); syscalls open/read/close/write (+ exit)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only Production Code | PASS | `cat.S` + `sys/` + `libuolt/` wrappers are pure assembly |
| II. Direct Syscalls Only | PASS | open/read/close/write issued directly; no libc |
| III. Zero Dependencies, Fully Static | PASS | Linux static; macOS loader-only stub |
| IV. No Heap, No Hidden Allocation | PASS | Single 64 KB buffer on the stack; trace asserts no mmap/brk |
| V. Thin Syscall Abstraction + Internal API | PASS | Tool calls `uolt_*`; numbers live in `sys/<os>/` |
| VI. Minimal Size (Targeted) | PASS | 824 B on Linux, < 2 KB target |
| VII. Optimization: Measured, Never Premature | PASS | 64 KB block size chosen for fewer syscalls; measured vs system |
| VIII. POSIX, Not GNU | PASS | POSIX `cat`; only `-u` handled (as a no-op), no GNU `-n`/`-A`/... |
| IX. Readable & Explicit | PASS | Named constants (STDIN/STDOUT/STDERR/O_RDONLY/BUFSZ); diagnostic length via strlen, not a magic number |
| X. Documentation as Pedagogy + README | PASS | README row + heavily commented rationale |
| XI. Tested & Benchmarked | PASS | Five test layers + benchmark vs system `cat` |

**Result**: All gates pass. No violations, no entries in Complexity Tracking.

## Project Structure

### Source Code (repository root)

```text
include/uolt.inc         # unchanged (shared constants)

sys/                     # per-OS syscall numbers (Principle V)
├── linux/{open,read,close}.S     # SYS_OPEN=2, SYS_READ=0, SYS_CLOSE=3
└── macos/{open,read,close}.S     # BSD class 0x2000000|n; carry -> negative

libuolt/                 # internal API (Principle V)
├── open.S  read.S  close.S       # thin tail calls over sys_*

src/cat/cat.S            # uolt-cat program: option scan, per-operand copy loop

tests/{unit,posix,differential,fuzz,trace}/cat.sh
bench/run.sh             # cat size + timing added
```

**Structure Decision**: Reuses the existing layout. The new capability is file I/O, added as
three syscall wrappers per OS (`open`/`read`/`close`) plus their `libuolt` entries, mirroring
the existing `write` pair. The macOS wrappers normalize the BSD carry-flag error convention to
a negative return so `cat.S` branches on the sign of the result identically on both platforms -
the same pattern already used for `sys_getcwd`.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
