---
description: "Task list for uolt-seq implementation"
---

# Tasks: uolt-seq

**Prerequisites**: write + strlen.

**Tests**: INCLUDED (Principle XI).

## Phase 1: Tool

- [x] T001 [US1] `src/seq/seq.S`: `parse_int` (signed, CF on error); resolve first/incr/last from
        1/2/3 operands; ascending/descending loop; `emit_num` (sign + digits + newline)
- [x] T002 Makefile: `EXTRA_seq` + append `seq` to `TOOLNAMES`

## Phase 2: Tests

- [x] T003 [P] `tests/unit/seq.sh`: 1/2/3 operands, negative/descending, empty ranges, errors
- [x] T004 [P] `tests/differential/seq.sh`: match system seq on integer ranges

## Phase 3: Polish

- [x] T005 Wire seq tests into `make test`
- [x] T006 Update `README.md` with the `uolt-seq` row
- [x] T007 Verify macOS + Linux: all pass. Linux 928 B (< 1 KB)

## Notes

- Floats and -w/-f/-s deferred. Zero increment is rejected (would not terminate).
