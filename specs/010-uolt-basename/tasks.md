---
description: "Task list for uolt-basename implementation"
---

# Tasks: uolt-basename

**Prerequisites**: write + strlen (from echo).

**Tests**: INCLUDED (Principle XI).

## Phase 1: Tool

- [x] T001 [US1] `src/basename/basename.S`: strip trailing '/'; all-slash -> "/"; empty -> empty
        line; find the last component; write it + newline; error on missing operand
- [x] T002 [US2] Inline suffix compare: strip the suffix from the component's tail only when it
        matches and is shorter than the component (equal length kept, per POSIX)
- [x] T003 Makefile: `EXTRA_basename` (strlen + write) + append `basename` to `TOOLNAMES`

## Phase 2: Tests

- [x] T004 [P] `tests/unit/basename.sh`: components, trailing slashes, all-slash, empty, suffix
        removal / equal-suffix / non-match, missing operand
- [x] T005 [P] `tests/posix/basename.sh`: the POSIX algorithm cases (interior/repeated slashes,
        dot components, suffix rules)
- [x] T006 [P] `tests/differential/basename.sh`: match reference `basename` stdout + exit over a
        range of path shapes
- [x] T007 [P] `tests/fuzz/basename.sh`: random path-like strings (with/without a suffix) match

## Phase 3: Polish

- [x] T008 Wire basename tests into `make test`
- [x] T009 Update `README.md` with the `uolt-basename` row
- [x] T010 Verify macOS + Linux: all pass. Linux 728 B (< 1 KB), ~1.4× faster (startup-bound)

## Notes

- Pure string tool: no file I/O, no buffer; the result is written from the operand's own bytes.
- GNU `-a`/`-s`/`-z` deferred; the one/two-operand POSIX form is what GNU and BSD agree on.
