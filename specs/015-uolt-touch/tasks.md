---
description: "Task list for uolt-touch implementation"
---

# Tasks: uolt-touch

**Prerequisites**: close + write + strlen.

**Tests**: INCLUDED (Principle XI).

## Phase 1: Foundational

- [x] T001 [P] `sys/{linux,macos}/create.S`: open O_WRONLY|O_CREAT (flag 0x41 / 0x201)
- [x] T002 [P] `sys/{linux,macos}/utimes.S`: SYS_UTIMES 235 / 0x200008A (NULL = now)
- [x] T003 [P] `libuolt/create.S`, `libuolt/utimes.S`

## Phase 2: Tool

- [x] T004 [US1/US2] `src/touch/touch.S`: option scan (-c/-a/-m, --); create+close unless -c;
        utimes(path, NULL); -c ignores ENOENT; diagnostic + status 1 on real failure
- [x] T005 Makefile: `EXTRA_touch` + append `touch` to `TOOLNAMES`

## Phase 3: Tests

- [x] T006 [P] `tests/unit/touch.sh`: create, update mtime (content preserved), -c missing/
        existing, multiple, missing operand
- [x] T007 [P] `tests/differential/touch.sh`: exit + resulting listing vs system touch

## Phase 4: Polish

- [x] T008 Wire touch tests into `make test`
- [x] T009 Update `README.md` with the `uolt-touch` row
- [x] T010 Verify macOS + Linux: all pass. Linux 912 B (< 1 KB); macOS create/utimes work directly

## Notes

- macOS `utimes` (138) and open-create work as direct syscalls (unlike nanosleep).
- Both times are always set to now, so -a/-m are no-ops; -r/-t deferred.
