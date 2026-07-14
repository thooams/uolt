# Implementation Plan: uolt-cut

**Branch**: `main` (spec dir `029-uolt-cut`) | **Date**: 2026-07-14

Select characters (-c) or fields (-f/-d). `parse_list` sets a bitmap (8192 positions) + an
open-ended threshold; `selected(pos)` tests it. `cut_line` emits, for -c, contiguous runs of
selected characters; for -f, the selected fields rejoined by the delimiter (a no-delimiter line
is passed through). Reuses the block-read line splitter. No new syscall.

## Constitution Check
All PASS: assembly; open/read/close/write direct; static/stub; no heap (64 KB buffer + 1 KB
bitmap on stack); uolt_* wrappers; 1800 B; measured; POSIX subset; documented; unit+differential.

## Structure
- src/cut/cut.S: option scan (-c/-f/-d/--), parse_list, run_fd line loop, cut_line, selected
- tests/{unit,differential}/cut.sh
