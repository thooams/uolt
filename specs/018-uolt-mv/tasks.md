---
description: "Task list for uolt-mv implementation"
---

# Tasks: uolt-mv

**Prerequisites**: write + strlen.

**Tests**: INCLUDED (Principle XI).

## Phase 1: Foundational

- [x] T001 [P] `sys/{linux,macos}/rename.S` (SYS_RENAME 82 / 0x2000080)
- [x] T002 `libuolt/rename.S`: uolt_rename(oldpath, newpath)

## Phase 2: Tool

- [x] T003 [US1] `src/mv/mv.S`: optional `--`, require two operands, rename, diagnostic + status 1
- [x] T004 Makefile: `EXTRA_mv` + append `mv` to `TOOLNAMES`

## Phase 3: Tests

- [x] T005 [P] `tests/unit/mv.sh`: rename, overwrite, rename dir, missing source, operand counts
- [x] T006 [P] `tests/differential/mv.sh`: exit + result vs system mv (rename/overwrite/symlink)

## Phase 4: Polish

- [x] T007 Wire mv tests into `make test`
- [x] T008 Update `README.md` with the `uolt-mv` row
- [x] T009 Verify macOS + Linux: all pass. Linux 664 B (< 1 KB)

## Notes

- `mv src... dir` (dir target) and cross-device (EXDEV -> copy+unlink) deferred; both need extra
  machinery (stat / a copy loop). Two-operand rename only.
