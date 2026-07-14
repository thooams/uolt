---
description: "Task list for uolt-cut implementation"
---
# Tasks: uolt-cut
- [x] T001 src/cut/cut.S: option scan (-c/-f/-d/--, LIST attached or separate); parse_list ->
      bitmap + open-end threshold; set_bit/selected
- [x] T002 run_fd block-read line loop; cut_line: -c contiguous runs; -f field split/rejoin,
      no-delimiter passthrough
- [x] T003 Makefile: EXTRA_cut + TOOLNAMES
- [x] T004 tests/unit/cut.sh (-c/-f ranges, open ranges, from-start, no-delim, separate list)
- [x] T005 tests/differential/cut.sh (vs system cut, -c/-f incl. ranges)
- [x] T006 README row; verify macOS + Linux (1800 B)

## Notes
- -b/-s/--complement deferred. LIST bitmap covers positions 1..8192; larger positions use the
  open-end threshold or are ignored.
