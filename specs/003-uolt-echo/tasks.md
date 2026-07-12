---
description: "Task list for uolt-echo implementation"
---

# Tasks: uolt-echo

**Prerequisites**: `uolt-true`/`uolt-false` complete. Introduces the per-OS entry shim and
libuolt write/strlen (reused by later tools).

**Tests**: INCLUDED (constitution Principle XI).

## Phase 1: Foundational (shared scaffolding)

- [x] T001 Verify the entry-arg ABI difference empirically (Linux stack vs macOS rdi/rsi)
- [x] T002 [P] Add `sys/linux/start.S` and `sys/macos/start.S`: normalize entry to `uolt_main(argc, argv)`, exit with its status
- [x] T003 [P] Add `sys/linux/write.S` and `sys/macos/write.S`: `sys_write` wrappers
- [x] T004 [P] Add `libuolt/write.S` (`uolt_write`) and `libuolt/strlen.S` (`uolt_strlen`)
- [x] T005 Refactor `src/true/true.S` and `src/false/false.S` to the `uolt_main` convention
- [x] T006 Generalize the `Makefile` (COMMON += start; `EXTRA_echo`; single clang link)

## Phase 2: Tool (US1 + US2)

- [x] T007 [US1] Implement `src/echo/echo.S`: parse argv, join with spaces, trailing newline
- [x] T008 [US2] Handle leading `-n` (suppress newline); no `-e` escapes

## Phase 3: Tests

- [x] T009 [P] Unit test `tests/unit/echo.sh`
- [x] T010 [P] POSIX test `tests/posix/echo.sh` (-n, no escapes)
- [x] T011 [P] Differential test `tests/differential/echo.sh` vs `/bin/echo`
- [x] T012 [P] Fuzz test `tests/fuzz/echo.sh` (random argv, byte-match reference)
- [x] T013 [P] Trace test `tests/trace/echo.sh` (only write/exit; no heap/read)

## Phase 4: Polish

- [x] T014 Wire echo tests into `make test`
- [x] T015 Update `README.md` with the `uolt-echo` row (size + system comparison) (Principle X)
- [x] T016 Verify on macOS (`make test`) and Linux (`scripts/linux-test.sh`): all PASS; Linux
        echo 608 B; trace/echo proves no heap

## Notes

- Refactor kept `true`/`false` green on both platforms.
- Deferred: single-`writev` output coalescing (measured optimization, Principle VII).
