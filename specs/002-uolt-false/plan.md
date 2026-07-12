# Implementation Plan: uolt-false

**Branch**: `main` (spec dir `002-uolt-false`) | **Date**: 2026-07-12 | **Spec**: [spec.md](./spec.md)

## Summary

`uolt-false` is the exact mirror of `uolt-true` (see `specs/001-uolt-true/`): ignore argv, no
I/O, always exit non-zero (`1`). All infrastructure - the `libuolt` internal API, the `sys/`
syscall abstraction, the Makefile, and the test/bench harness - already exists from
`uolt-true` and is reused unchanged. The only new production code is one source file that
loads `EXIT_FAILURE` instead of `EXIT_SUCCESS`.

## Technical Context

Identical to `uolt-true`: x86_64 assembly, Intel syntax, one clang/`as` toolchain, Linux
fully static / macOS libSystem-loader-only, no heap, one syscall (`exit`). See
`specs/001-uolt-true/plan.md` for the full context and `research.md` for the toolchain and
platform decisions (all reused).

## Constitution Check

All gates pass exactly as for `uolt-true` (same code shape, same scaffolding). The single new
constant `EXIT_FAILURE = 1` lives in the shared `include/uolt.inc`.

| Principle | Status |
|-----------|--------|
| I–XI | PASS (same rationale as uolt-true) |

## Project Structure

New/changed files only:

```text
include/uolt.inc          # + EXIT_FAILURE = 1
src/false/false.S         # new: _start -> EXIT_FAILURE -> uolt_exit
Makefile                  # TOOLNAMES += false; generic per-tool rule
tests/unit/false.sh       # new
tests/posix/false.sh      # new
tests/differential/false.sh  # new
tests/fuzz/false.sh       # new
README.md                 # + uolt-false row
```

**Structure Decision**: Reuse everything from `uolt-true`. The Makefile was generalized to a
per-tool rule (`TOOLNAMES := true false`) so adding a tool is: create `src/<name>/<name>.S`,
append the name, add tests.

## Complexity Tracking

> No violations. Section intentionally empty.
