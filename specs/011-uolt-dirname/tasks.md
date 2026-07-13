---
description: "Task list for uolt-dirname implementation"
---

# Tasks: uolt-dirname

**Prerequisites**: write + strlen (from echo); mirrors uolt-basename.

**Tests**: INCLUDED (Principle XI).

## Phase 1: Tool

- [x] T001 [US1] `src/dirname/dirname.S`: strip trailing '/'; find the last '/'; strip the
        separator(s); write the directory range, or ".", or "/" at the extremes; error on
        missing operand
- [x] T002 Makefile: `EXTRA_dirname` (strlen + write) + append `dirname` to `TOOLNAMES`

## Phase 2: Tests

- [x] T003 [P] `tests/unit/dirname.sh`: directory part, trailing slashes, all-slash, no-slash,
        empty, missing operand
- [x] T004 [P] `tests/posix/dirname.sh`: the POSIX algorithm cases (interior/repeated slashes,
        dot components, root extremes)
- [x] T005 [P] `tests/differential/dirname.sh`: match reference `dirname` stdout + exit over a
        range of path shapes
- [x] T006 [P] `tests/fuzz/dirname.sh`: random path-like strings match

## Phase 3: Polish

- [x] T007 Wire dirname tests into `make test`
- [x] T008 Update `README.md` with the `uolt-dirname` row
- [x] T009 Verify macOS + Linux: all pass. Linux 688 B (< 1 KB), ~1.4× faster (startup-bound)

## Notes

- Sibling of `uolt-basename`; same in-place argv scan, keeping the directory part.
- GNU `-z` deferred; the single-operand POSIX form is what GNU and BSD agree on.
