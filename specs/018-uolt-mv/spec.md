# Feature Specification: uolt-mv

**Feature Branch**: `018-uolt-mv` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented (two-operand form)  
**Input**: User description: "mv"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Rename / move a file (Priority: P1)

`uolt-mv source target` renames `source` to `target`, replacing an existing target file.

**Acceptance Scenarios**:

1. **Given** two operands, **When** `mv a b`, **Then** `a` becomes `b`.
2. **Given** an existing target, **When** run, **Then** it is overwritten.
3. **Given** a directory source, **When** `mv d e`, **Then** the directory is renamed.

---

### Edge Cases

- A missing source is an error.
- Exactly two operands are required; other counts are a usage error; `--` ends options.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST rename source to target with the rename syscall (atomic replace of an existing
  target file).
- **FR-002**: MUST require exactly two operands; other counts are a usage error; `--` ends options.
- **FR-003**: On failure MUST write a diagnostic and exit 1.
- **FR-004**: MUST use no heap (Principle IV).
- **FR-005**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Exit status and the resulting tree/content match the system `mv` across the tested
  two-operand cases.
- **SC-002**: Binary meets a < 1 KB target on Linux (664 B achieved; macOS ~5.4 KB floor).

## Assumptions

- Moving several sources into a directory (`mv src... dir`) and cross-device moves (rename ->
  EXDEV, needing copy+unlink) are out of scope in v1; only the two-operand rename form is handled.
- Adds the per-OS `rename` wrapper; reuses `write`/`strlen`.
