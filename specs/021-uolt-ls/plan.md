# Implementation Plan: uolt-ls

**Branch**: `main` (spec dir `021-uolt-ls`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-ls` lists directory entries one per line (`-a` for hidden), or prints a file operand's
name. It introduces directory reading - the per-OS `getdents` primitive and an `opendir`
(O_DIRECTORY) primitive - which also unlocks `rm -r` later. Entries flow through a 32 KB stack
buffer; output is unsorted (no bounded heap-free sort).

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: reads directories; no heap  
**Testing**: unit, differential vs `ls -1` (as sorted sets), trace (getdents, no heap)  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity (I/O-bound)  
**Constraints**: < 1 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; opendir/getdents/close/write syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `ls.S` + wrappers are assembly |
| II. Direct Syscalls | PASS | opendir/getdents/close/write direct |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | one 32 KB stack buffer; trace asserts no mmap/brk |
| V. Syscall Abstraction | PASS | `uolt_getdents`/`uolt_opendir`; numbers + flags in `sys/<os>/`; dirent offsets in uolt.inc |
| VI. Minimal Size | PASS | 976 B on Linux |
| VII. Measured Optimization | PASS | block reads; measured |
| VIII. POSIX, Not GNU | PASS | -a/-1; sort/columns/-l deferred |
| IX. Readable & Explicit | PASS | named offsets/constants; the dir-detection trick documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | three test layers |

**Result**: All gates pass.

## Project Structure

```text
include/uolt.inc                 # DIRENT_RECLEN_OFF / DIRENT_NAME_OFF (per -DUOLT_OS_*)
sys/{linux,macos}/getdents.S     # getdents64 217 / getdirentries64 344 (+ position arg)
sys/{linux,macos}/opendir.S      # open O_RDONLY|O_DIRECTORY (0x10000 / 0x100000)
libuolt/{getdents,opendir}.S     # uolt_getdents / uolt_opendir
src/ls/ls.S                      # option scan, per-operand list, entry parse, put_name
tests/{unit,differential,trace}/ls.sh
```

**Structure Decision**: Each operand is opened with O_DIRECTORY. ENOTDIR means it is a file, so
its name is printed; ENOENT/other is a diagnostic. A directory is read in 32 KB batches; each
record's name (at DIRENT_NAME_OFF) is written unless it is hidden and -a is off, advancing by the
record length (at DIRENT_RECLEN_OFF, offset 16 on both OSes). The Makefile passes -DUOLT_OS_* so
uolt.inc picks the right per-OS name offset (19 Linux / 21 macOS).

## Complexity Tracking

> No constitution violations. Section intentionally empty.
