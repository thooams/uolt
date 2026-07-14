---
description: "Task list for uolt-sort implementation"
---

# Tasks: uolt-sort

**Prerequisites**: open/read/close/write/strlen (from cat).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Tool

- [x] T001 [US1] `src/sort/sort.S`: read all input into a 1 MB text buffer (`read_into` per
        file/stdin, "-" and "--" handled); split into NUL-terminated lines with a pointer array
- [x] T002 [US1] `line_cmp` (unsigned byte compare, sign-extended); in-place insertion sort of
        the pointer array, flipped for `-r`; emit each line + newline
- [x] T003 Makefile: `EXTRA_sort` + append `sort` to `TOOLNAMES`

## Phase 2: Tests

- [x] T004 [P] `tests/unit/sort.sh`: basic, duplicates, -r, byte order, file/two-files, empty
- [x] T005 [P] `tests/differential/sort.sh`: match `LC_ALL=C sort` (+ -r) and a fuzz comparison

## Phase 3: Polish

- [x] T006 Wire sort tests into `make test`
- [x] T007 Update `README.md` with the `uolt-sort` row
- [x] T008 Verify macOS + Linux: all pass. Linux 1016 B (< 2 KB)

## Notes

- Bug: `sub eax, edx` zero-extends into rax, so a negative 32-bit result read as a 64-bit value
  looked positive; added `cdqe` to sign-extend the comparison result.
- Bounded to 1 MB / 128 K lines (no heap). -n/-u/-k and a faster O(n log n) sort are deferred.
