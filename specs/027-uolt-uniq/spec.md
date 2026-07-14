# Feature Specification: uolt-uniq

**Feature Branch**: `027-uolt-uniq` | **Date**: 2026-07-14 | **Status**: Implemented

## Summary

`uniq [-c] [-d] [-u] [file]`: collapse adjacent identical lines. Default prints one line per run;
-c prefixes the repeat count; -d prints only repeated runs; -u only single-occurrence runs. Input
is a file operand or stdin. Reads 64 KB blocks and splits lines (no heap); the current run's line
is kept in a separate 64 KB buffer with its count so it survives buffer refills.

## Requirements
- FR-001: MUST collapse adjacent identical lines to one per run.
- FR-002: -c prefixes the count; -d keeps only repeated runs; -u only single runs.
- FR-003: Non-adjacent duplicates MUST NOT be merged.
- FR-004: No heap (Principle IV); a final line without a newline is handled.
- FR-005: README entry recorded.

## Success Criteria
- SC-001: Output matches the system uniq for default/-c/-d/-u plus a fuzz comparison (the -c
  field width is implementation-defined, so -c is compared whitespace-normalized).
- SC-002: Binary < 2 KB on Linux (1248 B; macOS ~9.1 KB floor).

## Assumptions
- -f/-s (skip fields/chars), -i (case), and a separate output-file operand are out of scope.
  Reuses open/read/close/write/strlen; adds a run comparator and a count formatter.
