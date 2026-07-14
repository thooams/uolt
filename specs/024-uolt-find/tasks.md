---
description: "Task list for uolt-find implementation"
---

# Tasks: uolt-find

**Prerequisites**: opendir/getdents (from ls) + close + write + strlen.

**Tests**: INCLUDED (Principle XI).

## Phase 1: Foundational

- [x] T001 `include/uolt.inc`: add DIRENT_TYPE_OFF (per OS) and DT_* values

## Phase 2: Tool

- [x] T002 [US1] `src/find/find.S`: extract a trailing `-type f|d`; walk each start path (default
        ".") with a recursive `find_entry`; per-level getdents buffer + shared path buffer
- [x] T003 [US2] Classify entries by d_type (DT_DIR descends; DT_REG/DT_LNK/other print without
        descent; DT_UNKNOWN falls back to opendir); `print_cur` applies the -type filter
- [x] T004 Makefile: `EXTRA_find` + append `find` to `TOOLNAMES`

## Phase 3: Tests

- [x] T005 [P] `tests/unit/find.sh`: full walk, named start, -type f/d (symlink excluded), file
        operand (sorted-set comparisons)
- [x] T006 [P] `tests/differential/find.sh`: path set matches system find (sorted) for walk/-type

## Phase 4: Polish

- [x] T007 Wire find tests into `make test`
- [x] T008 Update `README.md` with the `uolt-find` row
- [x] T009 Verify macOS + Linux: all pass. Linux 1072 B (< 2 KB)

## Notes

- Bring-up bug: classifying by opening the path followed symlinks, so a symlink-to-file matched
  `-type f`. Fixed by using the directory entry's d_type (no follow); symlinks are typed 'l'.
- `-name` glob and other predicates deferred. `-type` is recognized as the trailing two operands.
