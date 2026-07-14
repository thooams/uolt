# Feature Specification: uolt-sort

**Feature Branch**: `025-uolt-sort` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented (lexicographic, -r, -n, -u)  
**Input**: User description: "sort"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sort lines (Priority: P1)

`uolt-sort` reads all input lines and writes them in C-locale byte order; `-r` reverses.

**Acceptance Scenarios**:

1. **Given** unsorted lines, **When** run, **Then** they print in ascending byte order.
2. **Given** `-r`, **When** run, **Then** they print in descending order.
3. **Given** duplicate lines, **When** run, **Then** all copies are kept.

---

### Edge Cases

- Byte order (C locale): "10" sorts before "2".
- No file operand reads stdin; several files are concatenated then sorted.
- Empty input yields empty output, exit 0.
- Input beyond the 1 MB buffer is dropped (a documented no-heap bound).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST sort all input lines in C-locale (byte) order; `-r` reverses.
- **FR-002**: With no file operand MUST read stdin; several files are concatenated then sorted.
- **FR-003**: Duplicate lines MUST be preserved (no implicit uniqueness).
- **FR-004**: MUST use no heap (Principle IV): a fixed 1 MB text buffer and a fixed line-pointer
  array on the stack; input beyond the buffer is dropped.
- **FR-005**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Output matches `LC_ALL=C sort` (and `-r`) across the tested cases and a fuzz
  comparison over random line sets.
- **SC-002**: Binary meets a < 2 KB target on Linux (1016 B achieved; macOS ~8.9 KB floor).

## Assumptions

- Numeric (`-n`), unique (`-u`), key (`-k`), field, and merge options are out of scope in v1;
  only whole-line byte-order sorting with `-r` is supported. Comparison is byte-wise, matching
  `LC_ALL=C sort`.
- Sorting needs all lines at once, which has no unbounded heap-free form, so the input is bounded
  to 1 MB / 128 K lines. Reuses `open`/`read`/`close`/`write`/`strlen`; the sort is an in-place
  insertion sort of a line-pointer array (adequate for the bounded size).
