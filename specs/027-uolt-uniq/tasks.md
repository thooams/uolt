---
description: "Task list for uolt-uniq implementation"
---
# Tasks: uolt-uniq
- [x] T001 src/uniq/uniq.S: option scan (-c/-d/-u, --); block-read line loop; take_line compares
      each line with the current run (prev buffer) and extends or flushes it
- [x] T002 flush_run applies -d/-u filter + -c count prefix (put_count: digits + space)
- [x] T003 Makefile: EXTRA_uniq + TOOLNAMES
- [x] T004 tests/unit/uniq.sh (default/-c/-d/-u, non-adjacent, file, no-newline)
- [x] T005 tests/differential/uniq.sh (vs system uniq, whitespace-normalized -c, + fuzz)
- [x] T006 README row; verify macOS + Linux (1248 B)

## Notes
- -c field width is implementation-defined (BSD vs GNU); differential normalizes whitespace.
