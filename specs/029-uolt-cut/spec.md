# Feature Specification: uolt-cut

**Feature Branch**: `029-uolt-cut` | **Date**: 2026-07-14 | **Status**: Implemented (-c, -f/-d)

## Summary

`cut -c LIST [file...]` selects 1-based character positions; `cut -f LIST [-d DELIM] [file...]`
selects delimiter-separated fields (default delimiter tab). LIST is a comma list of N, N-M, N-,
-M. A line with no delimiter is passed through (no -s). Selected positions live in a bitmap plus
an open-ended threshold on the stack (no heap); input is read in 64 KB blocks and split by lines.

## Requirements
- FR-001: -c selects characters; -f selects fields split on the delimiter, rejoined with it.
- FR-002: LIST supports N, N-M, N- (to end), -M (from start), comma-separated.
- FR-003: For -f, a line with no delimiter is output unchanged.
- FR-004: No heap (Principle IV); missing -c/-f is a usage error.
- FR-005: README entry recorded.

## Success Criteria
- SC-001: Output matches the system cut for -c and -f selections incl. ranges/open ranges.
- SC-002: Binary < 2 KB on Linux (1800 B; macOS ~9.8 KB floor).

## Assumptions
- -b (bytes, == -c for single-byte), -s (suppress no-delim lines), and multi-char/--complement
  are out of scope. Reuses open/read/close/write/strlen; adds a LIST parser (bitmap + threshold).
