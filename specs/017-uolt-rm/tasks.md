---
description: "Task list for uolt-rm implementation"
---

# Tasks: uolt-rm

**Prerequisites**: unlink (from ln) + write + strlen.

**Tests**: INCLUDED (Principle XI).

## Phase 1: Tool

- [x] T001 [US1] `src/rm/rm.S`: option scan (-f, --); unlink each operand; -f ignores ENOENT and
        makes no-operands a no-op; diagnostic + status 1 otherwise
- [x] T002 Makefile: `EXTRA_rm` (reuses unlink) + append `rm` to `TOOLNAMES`

## Phase 2: Tests

- [x] T003 [P] `tests/unit/rm.sh`: file, multiple, missing (+/- -f), directory error, no-operand
        rules
- [x] T004 [P] `tests/differential/rm.sh`: exit + tree vs system rm (file/symlink/-f cases)

## Phase 3: Polish

- [x] T005 Wire rm tests into `make test`
- [x] T006 Update `README.md` with the `uolt-rm` row (noting -r deferred)
- [x] T007 Verify macOS + Linux: all pass. Linux 744 B (< 1 KB)

## Notes

- `-r`/`-R` deferred until directory reading is built (with `ls`). `-i` unsupported.
- A directory operand errors (EISDIR/EPERM), matching a non-recursive rm.
