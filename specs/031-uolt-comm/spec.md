# Feature Specification: uolt-comm

**Feature Branch**: `031-uolt-comm` | **Date**: 2026-07-14 | **Status**: Implemented

## Summary

`comm [-1] [-2] [-3] file1 file2`: compare two sorted files line by line and print three
tab-separated columns - lines only in file1, only in file2, and in both. -1/-2/-3 suppress a
column; a column's tab indentation is the number of non-suppressed columns before it. Both files
are read into fixed buffers and split into line-pointer arrays on the stack (no heap; input beyond
the buffer is dropped), then merged by byte comparison.

## Requirements
- FR-001: Emit three columns (only-1, only-2, both) from a merge of the two sorted inputs.
- FR-002: -1/-2/-3 suppress the respective column; tab indentation adjusts to the enabled columns.
- FR-003: No heap (Principle IV); a missing file or wrong operand count is an error.
- FR-004: README entry recorded.

## Success Criteria
- SC-001: Output matches the system comm for every -1/-2/-3 combination, plus empty and identical
  file cases.
- SC-002: Binary < 2 KB on Linux (1496 B; macOS ~9.1 KB floor).

## Assumptions
- Inputs are assumed sorted (C locale), like comm. -i (case-insensitive) and --check-order are out
  of scope. Reuses open/read/close/write/strlen.
