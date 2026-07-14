# Feature Specification: uolt-tr

**Feature Branch**: `030-uolt-tr` | **Date**: 2026-07-14 | **Status**: Implemented (translate, -d)

## Summary

`tr set1 set2` translates bytes in set1 to the matching byte of set2 (set2's last byte repeats if
it is shorter); `tr -d set1` deletes bytes in set1. Sets are literal bytes and ranges (a-z). A
256-entry map and a 256-entry delete flag are built on the stack (no heap); input is transformed
block by block through a 64 KB buffer.

## Requirements
- FR-001: Translate each set1 byte to the same-index set2 byte (short set2 -> last byte repeats).
- FR-002: -d deletes every byte in set1.
- FR-003: Sets expand ranges like a-z; a trailing '-' is literal.
- FR-004: No heap (Principle IV); missing operands is a usage error.
- FR-005: README entry recorded.

## Success Criteria
- SC-001: Output matches the system tr (LC_ALL=C) for translate and delete cases (ranges, short
  set2, rot13-style mapping).
- SC-002: Binary < 2 KB on Linux (1040 B; macOS ~7.6 KB floor).

## Assumptions
- Backslash escapes, -s (squeeze), -c (complement), and [:class:] are out of scope. Reuses
  read/write/strlen; adds a set expander and byte-table transform.
