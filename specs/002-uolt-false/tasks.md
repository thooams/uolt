---
description: "Task list for uolt-false implementation"
---

# Tasks: uolt-false

**Input**: Design documents from `/specs/002-uolt-false/`
**Prerequisites**: `uolt-true` complete (all scaffolding reused).

**Tests**: INCLUDED (constitution Principle XI).

Mirror of `uolt-true`; only the exit status differs. No new foundational work.

## Phase 1: Implementation (US1)

- [x] T001 [US1] Add `EXIT_FAILURE = 1` to `include/uolt.inc`
- [x] T002 [US1] Implement `src/false/false.S`: `_start`, load `EXIT_FAILURE`, call `uolt_exit`
- [x] T003 [US1] Generalize `Makefile` to a per-tool rule and add `false` to `TOOLNAMES`

## Phase 2: Tests (US1)

- [x] T004 [P] [US1] Unit test `tests/unit/false.sh`: exit 1, no output
- [x] T005 [P] [US1] POSIX test `tests/posix/false.sh`: args ignored, streams, exit 1
- [x] T006 [P] [US1] Differential test `tests/differential/false.sh`: match `/usr/bin/false`
- [x] T007 [P] [US1] Fuzz test `tests/fuzz/false.sh`: random argv → always exit 1, no output

## Phase 3: Polish

- [x] T008 Wire the false tests into `make test`
- [x] T009 Update `README.md` with the `uolt-false` entry (name + size) (Principle X, FR-008)
- [x] T010 Build and run `make test`; confirm all `false` layers pass (done: unit/posix/differential/fuzz PASS on macOS)

## Notes

- Trace layer is shared conceptually with `uolt-true` (same single `exit` syscall); the macOS
  trace test SKIPs under SIP and runs on Linux CI.
- Linux build/size validated by CI (`.github/workflows/ci.yml`).
