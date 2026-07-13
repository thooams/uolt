---
description: "Task list for uolt-cp implementation"
---

# Tasks: uolt-cp

**Prerequisites**: open/read/write/close/strlen (from cat).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Foundational

- [x] T001 [P] `sys/{linux,macos}/opendst.S`: open O_WRONLY|O_CREAT|O_TRUNC (0x241 / 0x601)
- [x] T002 `libuolt/opendst.S`: uolt_opendst(path, mode)

## Phase 2: Tool

- [x] T003 [US1] `src/cp/cp.S`: optional `--`, two operands; open src + opendst dst; 64 KB copy
        loop with short-write drain; close both; diagnostics + status 1
- [x] T004 Makefile: `EXTRA_cp` + append `cp` to `TOOLNAMES`

## Phase 3: Tests

- [x] T005 [P] `tests/unit/cp.sh`: copy, truncate target, binary/big, empty, errors
- [x] T006 [P] `tests/differential/cp.sh`: exit + content vs system cp (deterministic seeds)

## Phase 4: Polish

- [x] T007 Wire cp tests into `make test`
- [x] T008 Update `README.md` with the `uolt-cp` row
- [x] T009 Verify macOS + Linux: all pass. Linux 952 B (< 1 KB)

## Notes

- Assembler gotcha: `.set FLAGS, ...` failed to assemble (`FLAGS` is reserved in clang's
  integrated assembler); renamed to `OFLAGS`.
- Differential seeds must be deterministic: `/dev/urandom` seeds differ between the two sandboxes.
- `-r`, dir target, same-file detection (needs stat), and mode/timestamp preservation deferred.
