---
description: "Task list for uolt-chmod implementation"
---

# Tasks: uolt-chmod

**Prerequisites**: write + strlen.

**Tests**: INCLUDED (Principle XI).

## Phase 1: Foundational

- [x] T001 [P] `sys/{linux,macos}/chmod.S` (SYS_CHMOD 90 / 0x200000F)
- [x] T002 `libuolt/chmod.S`: uolt_chmod(path, mode)

## Phase 2: Tool

- [x] T003 [US1] `src/chmod/chmod.S`: parse the octal mode (reject non-octal as symbolic); apply
        to each file; diagnostic + status 1 on failure; require mode + >= 1 file
- [x] T004 Makefile: `EXTRA_chmod` + append `chmod` to `TOOLNAMES`

## Phase 3: Tests

- [x] T005 [P] `tests/unit/chmod.sh`: 755/0600/multi/640, symbolic rejected, missing file,
        operand counts
- [x] T006 [P] `tests/differential/chmod.sh`: permission bits + exit vs system chmod over a range
        of octal modes (incl special bits and leading zeros)

## Phase 4: Polish

- [x] T007 Wire chmod tests into `make test`
- [x] T008 Update `README.md` with the `uolt-chmod` row
- [x] T009 Verify macOS + Linux: all pass. Linux 816 B (< 1 KB)

## Notes

- Symbolic modes deferred (relative +/- need the current mode via stat); `-R` deferred (needs
  directory reading). Octal modes only.
