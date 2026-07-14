# Implementation Plan: uolt-grep

**Branch**: `main` (spec dir `023-uolt-grep`) | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-grep` is a fixed-string line matcher (`grep -F`): it prints input lines that contain the
pattern, with `-i` (case fold) and `-v` (invert). Input is read in 64 KB blocks and split on
newlines through a line buffer; matching lines get a "file:" prefix when more than one file is
given. Reuses `open`/`read`/`close`/`write`/`strlen`.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax; clang for both OSes  
**Primary Dependencies**: none at runtime; `make` + clang. Linux static; macOS loader stub  
**Storage**: reads files/stdin, writes stdout; no heap  
**Testing**: unit, differential vs `grep -F`  
**Target Platform**: x86_64 Linux and x86_64 macOS  
**Performance Goals**: parity (I/O-bound)  
**Constraints**: < 2 KB Linux; no heap; no raw syscall number in tool code  
**Scale/Scope**: one executable; open/read/close/write syscalls

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only | PASS | `grep.S` is assembly |
| II. Direct Syscalls | PASS | open/read/close/write direct |
| III. Zero Deps / Static | PASS | Linux static; macOS stub |
| IV. No Heap | PASS | 64 KB line buffer on the stack |
| V. Syscall Abstraction | PASS | `uolt_*`; no new syscall |
| VI. Minimal Size | PASS | 1448 B on Linux |
| VII. Measured Optimization | PASS | naive search is adequate; measured |
| VIII. POSIX, Not GNU | PASS | fixed-string subset; regex/other options deferred |
| IX. Readable & Explicit | PASS | line splitter + search documented |
| X. Docs as Pedagogy | PASS | README + comments |
| XI. Tested & Benchmarked | PASS | two test layers |

**Result**: All gates pass.

## Project Structure

```text
src/grep/grep.S    # option scan, per-file line loop, substring search, prefixes
tests/{unit,differential}/grep.sh
```

**Structure Decision**: `grep_fd` reads 64 KB blocks into the line buffer, splits on newlines
(compacting the leftover partial line to the front, flushing a buffer-full line, and handling a
final line with no newline), and calls `process_line`. `contains` is a naive case-optional
substring scan. `process_line` applies -v, records any match, and prints the line with an
optional name prefix. Exit status is 0/1/2 per grep.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
