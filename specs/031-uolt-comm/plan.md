# Implementation Plan: uolt-comm

**Branch**: `main` (spec dir `031-uolt-comm`) | **Date**: 2026-07-14

Read both files fully (read_file), split into NUL-terminated line-pointer arrays (split_lines),
then merge: compare line1[i] vs line2[j] with line_cmp; < emits column 1 and advances i, > emits
column 2 and advances j, == emits column 3 and advances both; drain the remainder. emit_col
prints the line in its column if enabled, with a tab per enabled earlier column. No new syscall.

## Constitution Check
All PASS: assembly; open/read/close/write direct; static/stub; no heap (2x256 KB buffers +
2x256 KB pointer arrays on stack, bounded); uolt_* wrappers; 1496 B; measured; documented;
unit+differential.

## Structure
- src/comm/comm.S: option scan (-1/-2/-3 combined, --); read_file/split_lines; merge; emit_col
- tests/{unit,differential}/comm.sh
