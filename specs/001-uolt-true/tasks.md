---
description: "Task list for uolt-true implementation"
---

# Tasks: uolt-true

**Input**: Design documents from `/specs/001-uolt-true/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli.md, quickstart.md

**Tests**: INCLUDED. The UOLT constitution (Principle XI) mandates unit, POSIX, differential,
fuzz, and syscall-trace tests plus a benchmark for every tool.

**Organization**: Tasks grouped by user story. US1 (always-success) is the MVP; US2
(repeatable primitive) reuses the same binary and adds robustness coverage.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1, US2 (setup/foundational/polish have no story label)
- Paths are repository-relative.

## Path Conventions

Single-project layout from plan.md: `Makefile`, `include/`, `sys/`, `libuolt/`, `src/`,
`tests/`, `bench/` at repository root.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Skeleton directories and the shared assembly header/constants.

- [x] T001 Create the repository directory tree per plan.md: `include/`, `sys/linux/`, `sys/macos/`, `libuolt/`, `src/true/`, `tests/{unit,posix,differential,fuzz,trace}/`, `bench/`
- [x] T002 [P] Create `include/uolt.inc` with named constants (`EXIT_SUCCESS = 0`) and build-time OS-selection macros; no raw syscall numbers here
- [x] T003 [P] Create `README.md` with an empty command table (columns: command, size, notes) ready for the `uolt-true` entry (constitution Principle X)

**Checkpoint**: Tree and shared header exist.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The syscall abstraction, the internal API `exit`, and the single-command build.
These are the reusable scaffolding every tool depends on.

**⚠️ CRITICAL**: No tool code can build until this phase is complete.

- [x] T004 [P] Implement `sys/linux/exit.s`: `sys_exit` wrapper owning `SYS_EXIT = 60` and the Linux x86_64 syscall convention (Intel syntax, `.intel_syntax noprefix`)
- [x] T005 [P] Implement `sys/macos/exit.s`: `sys_exit` wrapper owning `SYS_EXIT = 0x2000001` and the macOS x86_64 syscall convention (Intel syntax)
- [x] T006 Implement `libuolt/exit.s`: internal-API `uolt_exit` entry point that takes a status and calls `sys_exit` (depends on T004, T005)
- [x] T007 Create `Makefile`: host-OS detection; assemble with clang `as`; Linux link `ld` fully static (`_start`, no libc); macOS link `ld -e _main -lSystem -L$(xcrun --show-sdk-path)/usr/lib`; output to `build/`; targets `all`, `build/uolt-true`, `clean`
- [x] T008 [P] Create the test runner target `make test` in the `Makefile` wiring the `tests/*` layers, and `make bench` wiring `bench/`

**Checkpoint**: Build system and syscall/API scaffolding ready.

---

## Phase 3: User Story 1 - Signal success in a script (Priority: P1) 🎯 MVP

**Goal**: Deliver `uolt-true` that produces no output and always exits `0`.

**Independent Test**: Run `./build/uolt-true`; assert exit status `0` and empty stdout/stderr.

### Tests for User Story 1 ⚠️ (write first, must FAIL before T012)

- [x] T009 [P] [US1] Unit test `tests/unit/true.sh`: run `uolt-true`, assert exit `0` and 0 bytes on stdout and stderr (FR-001, FR-002, FR-003)
- [x] T010 [P] [US1] POSIX test `tests/posix/true.sh`: run with args (`a b --c`) and with stdin/stdout/stderr redirected to `/dev/null` and closed; assert exit `0`, no output (FR-004, FR-005)
- [x] T011 [P] [US1] Trace test `tests/trace/true.sh`: run under `strace`/`dtruss`; assert only the `exit` syscall appears and no `read`/`write`/`mmap`/`brk` (proves Principles II, IV)

### Implementation for User Story 1

- [x] T012 [US1] Implement `src/true/true.s`: `_start` entry, load `EXIT_SUCCESS` as status, call `uolt_exit`; commented rationale per instruction (Principle IX, X); no I/O, no heap
- [x] T013 [US1] Wire `uolt-true` into the `Makefile` build (assemble `src/true/true.s` + link `sys/<os>/exit.s` + `libuolt/exit.s`) producing `build/uolt-true` (static on Linux, `-lSystem` loader on macOS)
- [x] T014 [US1] Run T009–T011; confirm they pass on the built binary

**Checkpoint**: `uolt-true` builds, exits 0, produces no output, uses only `exit`. MVP done.

---

## Phase 4: User Story 2 - Reliable loop and conditional primitive (Priority: P2)

**Goal**: Guarantee identical, repeatable behavior so `uolt-true` is safe as a loop/conditional
primitive.

**Independent Test**: Invoke `uolt-true` 1000 times and inside a loop condition; every
invocation exits `0` with no output.

### Tests for User Story 2 ⚠️

- [x] T015 [P] [US2] Repeatability test `tests/unit/true_repeat.sh`: run `uolt-true` 1000 times and inside `while uolt-true; do break; done`; assert every exit is `0`, no output (FR-006)
- [x] T016 [P] [US2] Differential test `tests/differential/true.sh`: for each case (no args, args, redirected/closed streams) compare exit code and output byte-for-byte against a reference `true` (SC-003, FR-007)
- [x] T017 [P] [US2] Fuzz test `tests/fuzz/true.sh`: feed random/large/binary argv and random stream states; assert never exit != 0, never any output, never crash (Principle XI)

### Implementation for User Story 2

- [x] T018 [US2] Run T015–T017 against the existing binary; if any fail, fix `src/true/true.s` and re-run (no behavior should be argv/stream dependent)

**Checkpoint**: US1 and US2 both pass; tool proven solid and deterministic.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Verify constitution targets and record the tool.

- [x] T019 [P] Benchmark `bench/true.sh`: measure time, memory, and size vs GNU, BSD (macOS), BusyBox, Toybox; record results (Principle XI)
- [x] T020 Verify size < 1 KB (`wc -c build/uolt-true`) and fully static (`ldd` → not dynamic) (SC-004)
- [x] T021 Verify startup < 1 ms via `bench/true.sh` measurement (SC-005)
- [x] T022 Update `README.md` command table with the `uolt-true` entry: name + measured binary size + notes (POSIX true, exit 0); tool is not "done" until this exists (constitution Principle X, FR-008)
- [x] T023 Run `quickstart.md` end to end to confirm build/run/test/bench instructions are accurate

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies; start immediately.
- **Foundational (Phase 2)**: depends on Setup; BLOCKS all story work.
- **US1 (Phase 3)**: depends on Foundational. MVP.
- **US2 (Phase 4)**: depends on US1 (needs the built binary); adds tests only, no new behavior.
- **Polish (Phase 5)**: depends on US1 (and US2 for full coverage).

### Within Each User Story

- Tests (T009–T011, T015–T017) written first and must FAIL before implementation.
- `src/true/true.s` (T012) before build wiring (T013) before test run (T014).

### Parallel Opportunities

- Setup: T002, T003 in parallel (T001 first).
- Foundational: T004, T005 in parallel; T008 in parallel with T006/T007 once T004/T005 done.
- US1 tests: T009, T010, T011 in parallel.
- US2 tests: T015, T016, T017 in parallel.
- Polish: T019 parallel with T020/T021 prep.

---

## Parallel Example: User Story 1

```bash
# Write US1 tests together (they must fail first):
Task: "Unit test in tests/unit/true.sh"
Task: "POSIX test in tests/posix/true.sh"
Task: "Trace test in tests/trace/true.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup.
2. Phase 2: Foundational (syscall abstraction + build) - CRITICAL.
3. Phase 3: US1 - build `uolt-true`, pass unit/POSIX/trace.
4. **STOP and VALIDATE**: exit 0, no output, only `exit` syscall.

### Incremental Delivery

1. Setup + Foundational → scaffolding ready (reused by every future tool).
2. US1 → MVP (`uolt-true` works).
3. US2 → robustness proven (repeat, differential, fuzz).
4. Polish → size/startup verified, README entry recorded.

---

## Notes

- [P] = different files, no dependencies.
- Tests must fail before implementation (T009–T011, T015–T017 before/against T012).
- `sys/`, `libuolt/`, `Makefile`, and the test/bench harness built here are reused by all
  later tools (`echo`, `cat`, ...).
- Commit after each task or logical group.
- README entry (T022) is a hard gate: no command is done without it.
