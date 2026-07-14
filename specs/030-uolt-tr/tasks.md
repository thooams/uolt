---
description: "Task list for uolt-tr implementation"
---
# Tasks: uolt-tr
- [x] T001 src/tr/tr.S: option scan (-d/--); expand_set (literals + a-z ranges, trailing '-' literal)
- [x] T002 Build identity map + translate map (short set2 repeats last) or delete table; block transform
- [x] T003 Makefile: EXTRA_tr + TOOLNAMES
- [x] T004 tests/unit/tr.sh (upcase/downcase, delete, literal map, short set2, delete spaces)
- [x] T005 tests/differential/tr.sh (vs system tr, LC_ALL=C; translate/delete/rot13)
- [x] T006 README row; verify macOS + Linux (1040 B)

## Notes
- Escapes, -s, -c, [:class:] deferred. Set buffers are scratch in the (unused-yet) I/O buffer.
