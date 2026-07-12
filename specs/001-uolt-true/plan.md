# Implementation Plan: uolt-true

**Branch**: `main` (spec dir `001-uolt-true`) | **Date**: 2026-07-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-uolt-true/spec.md`

## Summary

`uolt-true` is the POSIX `true` utility: it takes no meaningful action, ignores all
arguments, performs no I/O, and always exits with status `0`. It is the smallest tool in
UOLT and its real job is to stand up the whole infrastructure once: the per-OS syscall
abstraction (`sys/`), the internal `libuolt` API entry point (`exit`), the single-command
build, and the full test/benchmark harness (unit, POSIX, differential, fuzz, syscall-trace).
Every later tool reuses this scaffolding.

## Technical Context

**Language/Version**: x86_64 assembly, Intel syntax via `.intel_syntax noprefix`, one
toolchain (clang integrated assembler) for both OSes and future arm64  
**Primary Dependencies**: No library *usage* at runtime (no libc/libgcc/runtime calls).
Build-time: clang `as` + linker (`ld`) driven by `make`. On macOS the binary carries the
OS-imposed `libSystem.dylib` loader stub (zero calls into it); on Linux it is fully static  
**Storage**: N/A (tool touches no files)  
**Testing**: POSIX-shell harness (black-box assertions on exit code + stdout/stderr),
differential vs reference `true`, fuzz driver (random argv/stream states), syscall trace via
`strace` (Linux) / `dtruss` (macOS)  
**Target Platform**: x86_64 Linux and x86_64 macOS (single architecture per constitution;
arm64 deferred)  
**Project Type**: CLI utility (standalone binary; static on Linux, loader-only dep on macOS)  
**Performance Goals**: startup-to-exit < 1 ms  
**Constraints**: binary size < 1 KB; Linux fully static / macOS zero libSystem calls; no heap;
no raw syscall number in tool code (only symbolic `sys_exit`)  
**Scale/Scope**: one executable (`uolt-true`), one syscall used (`exit`), no data

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Assembly-Only Production Code | PASS | `true.asm` + `sys/` wrappers are pure assembly; only `make`/tests are other languages |
| II. Direct Syscalls Only | PASS | Uses only the `exit` syscall directly; no intermediate layer |
| III. Zero Dependencies, Fully Static | PASS | Linked static, no libc/libgcc/runtime |
| IV. No Heap, No Hidden Allocation | PASS | No memory allocated at all |
| V. Thin Syscall Abstraction + Internal API | PASS | Tool calls `sys_exit`; syscall numbers live in `sys/linux/`, `sys/macos/` |
| VI. Minimal Size (Targeted) | PASS | Target < 1 KB declared; trivially met |
| VII. Optimization: Measured, Never Premature | PASS | Startup + size measured by harness |
| VIII. POSIX, Not GNU | PASS | POSIX `true`; no `--help`/`--version` in v1 |
| IX. Readable & Explicit | PASS | `SYS_EXIT`/`EXIT_SUCCESS` named constants, no magic numbers |
| X. Documentation as Pedagogy + README | PASS | README entry (name, size) + commented rationale required before done |
| XI. Tested & Benchmarked | PASS | Unit, POSIX, differential, fuzz, syscall-trace + benchmark vs GNU/BSD/BusyBox/Toybox |

**Result**: All gates pass. No violations, no entries in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/001-uolt-true/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (N/A rationale)
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── cli.md           # CLI contract for uolt-true
└── checklists/
    └── requirements.md  # Spec quality checklist
```

### Source Code (repository root)

```text
Makefile                 # single-command build: `make` (and `make test`, `make bench`)
README.md                # per-command table (name, size, notes) - constitution Principle X

include/
└── uolt.inc             # shared constants + macros (EXIT_SUCCESS, arch/OS switches)

sys/                     # thin syscall abstraction (Principle V)
├── linux/
│   └── exit.asm         # sys_exit for Linux x86_64 (SYS_EXIT = 60)
└── macos/
    └── exit.asm         # sys_exit for macOS x86_64 (SYS_EXIT = 0x2000001)

libuolt/                 # shared internal API (Principle V)
└── exit.asm             # `uolt_exit` wrapper over sys_exit (grows: strlen, print_string...)

src/
└── true/
    └── true.asm         # uolt-true program: set status 0, call uolt_exit

tests/
├── unit/
│   └── true.sh          # black-box: exit code + no output
├── posix/
│   └── true.sh          # POSIX conformance (args ignored, streams)
├── differential/
│   └── true.sh          # compare vs reference `true`
├── fuzz/
│   └── true.sh          # random argv / stream states, never non-zero, never output
└── trace/
    └── true.sh          # strace/dtruss: only exit syscall, no heap

bench/
└── true.sh              # time/mem/size vs GNU/BSD/BusyBox/Toybox
```

**Structure Decision**: Single-project CLI layout. Cross-cutting infrastructure (`sys/`,
`libuolt/`, `include/uolt.inc`, `Makefile`, test/bench harness) is created now with
`uolt-true` and reused by every future tool. `sys/` isolates OS-specific syscall numbers so
`src/true/true.asm` never names a raw number; `libuolt/` holds the shared `exit` entry point,
the first member of the internal API that later tools (`echo`, `cat`, ...) will extend.

## Complexity Tracking

> No constitution violations. Section intentionally empty.
