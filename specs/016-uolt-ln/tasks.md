---
description: "Task list for uolt-ln implementation"
---

# Tasks: uolt-ln

**Prerequisites**: write + strlen.

**Tests**: INCLUDED (Principle XI).

## Phase 1: Foundational

- [x] T001 [P] `sys/{linux,macos}/link.S` (86 / 0x2000009)
- [x] T002 [P] `sys/{linux,macos}/symlink.S` (88 / 0x2000039)
- [x] T003 [P] `sys/{linux,macos}/unlink.S` (87 / 0x200000A) - reused by rm
- [x] T004 [P] `libuolt/{link,symlink,unlink}.S`

## Phase 2: Tool

- [x] T005 [US1/US2] `src/ln/ln.S`: option scan (-s/-f, combined, --); resolve target (second
        operand or basename of source); optional unlink; link/symlink; diagnostic + status 1
- [x] T006 Makefile: `EXTRA_ln` + append `ln` to `TOOLNAMES`

## Phase 3: Tests

- [x] T007 [P] `tests/unit/ln.sh`: hard link, symlink, existing target, -f replace, implicit
        basename, missing source, no operand
- [x] T008 [P] `tests/differential/ln.sh`: exit + entry signature (name/type/target) vs system ln

## Phase 4: Polish

- [x] T009 Wire ln tests into `make test`
- [x] T010 Update `README.md` with the `uolt-ln` row
- [x] T011 Verify macOS + Linux: all pass. Linux 904 B (< 1 KB)

## Notes

- `ln src... dir` (multiple sources into a directory) deferred; it needs a stat to detect the
  directory. Only one/two-operand forms are handled.
