# Feature Specification: uolt-seq

**Feature Branch**: `022-uolt-seq` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented (integers)  
**Input**: User description: "seq"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Print a sequence (Priority: P1)

`uolt-seq 5` prints 1..5; `uolt-seq 2 6` prints 2..6; `uolt-seq 1 2 9` steps by 2.

**Acceptance Scenarios**:

1. **Given** one operand, **When** `seq N`, **Then** it prints 1..N, one per line.
2. **Given** two operands, **When** `seq A B`, **Then** it prints A..B.
3. **Given** three operands, **When** `seq A S B`, **Then** it steps by S (S may be negative).

---

### Edge Cases

- A negative step counts down; a step of the wrong sign yields an empty range.
- An empty range (e.g. `seq 5 1`) prints nothing, exit 0.
- A non-integer operand, a zero step, or the wrong operand count is an error (exit 1).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST print the integer sequence from first to last stepping by incr, one per line;
  defaults first = 1, incr = 1.
- **FR-002**: MUST accept 1, 2, or 3 operands; a negative incr counts down.
- **FR-003**: A non-integer operand, a zero incr, or another operand count is an error (exit 1).
- **FR-004**: MUST use no heap (Principle IV): numbers are formatted in a small stack buffer.
- **FR-005**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Output matches the system `seq` on integer ranges (ascending, descending, stepped,
  negative, single, empty).
- **SC-002**: Binary meets a < 1 KB target on Linux (928 B achieved; macOS ~6 KB floor).

## Assumptions

- Floating-point operands and the `-w` / `-f` / `-s` options are out of scope in v1; only integer
  sequences are produced. Reuses `write`/`strlen`; adds a signed integer parser and formatter.
