---
description: "Task list for uolt-comm implementation"
---
# Tasks: uolt-comm
- [x] T001 src/comm/comm.S: option scan (-1/-2/-3, combined like -12, --); read_file + split_lines
- [x] T002 Merge two sorted line arrays with line_cmp; emit_col (enable check + tab indentation)
- [x] T003 Makefile: EXTRA_comm + TOOLNAMES
- [x] T004 tests/unit/comm.sh (default, -12, -3, -23, identical, errors)
- [x] T005 tests/differential/comm.sh (all -1/-2/-3 combinations, empty/identical)
- [x] T006 README row; verify macOS + Linux (1496 B)

## Notes
- Combined flags (e.g. -12) needed a loop over the flag characters (first cut only read one).
- read_file returns a negative value with SF set on open error; the success path re-tests to
  clear SF for the caller's `js`.
