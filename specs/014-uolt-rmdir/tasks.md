---
description: "Task list for uolt-rmdir implementation"
---

# Tasks: uolt-rmdir

**Prerequisites**: write + strlen (diagnostics); mirrors uolt-mkdir.

**Tests**: INCLUDED (Principle XI).

## Phase 1: Foundational

- [x] T001 [P] `sys/linux/rmdir.S` (SYS_RMDIR 84), `sys/macos/rmdir.S` (0x2000089, carry->neg)
- [x] T002 `libuolt/rmdir.S`: uolt_rmdir(path)

## Phase 2: Tool

- [x] T003 [US1] `src/rmdir/rmdir.S`: option scan (-p, --); plain rmdir with diagnostic + status 1
- [x] T004 [US2] `rmdir_p`: remove target then each ancestor, stopping at the first failure; end
        index in a callee-saved register (survives the syscalls)
- [x] T005 Makefile: `EXTRA_rmdir` + append `rmdir` to `TOOLNAMES`

## Phase 3: Tests

- [x] T006 [P] `tests/unit/rmdir.sh`: empty, non-empty, -p chain, -p stop, missing, no operand
        (relative operands in a sandbox)
- [x] T007 [P] `tests/differential/rmdir.sh`: exit + resulting tree vs system rmdir (seeded
        sandboxes)

## Phase 4: Polish

- [x] T008 Wire rmdir tests into `make test`
- [x] T009 Update `README.md` with the `uolt-rmdir` row
- [x] T010 Verify macOS + Linux: all pass. Linux 848 B (< 1 KB)

## Notes

- `-p` climbs the given path's ancestors like GNU/BSD (absolute paths climb to a non-empty
  ancestor); tests use relative operands in a sandbox to keep the climb contained.
