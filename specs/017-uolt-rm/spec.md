# Feature Specification: uolt-rm

**Feature Branch**: `017-uolt-rm` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented (files only; -r deferred)  
**Input**: User description: "rm"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Remove files (Priority: P1)

`uolt-rm f...` removes the named files. A missing file is an error unless `-f` is given.

**Acceptance Scenarios**:

1. **Given** existing files, **When** `rm a b`, **Then** both are removed, exit 0.
2. **Given** a missing file, **When** `rm x`, **Then** it errors (exit 1).
3. **Given** `-f` and a missing file, **When** run, **Then** it is silently ignored, exit 0.

---

### Edge Cases

- A directory operand is an error (no recursion in v1); `-f` does not remove it either.
- No operand is an error, except `rm -f` with no operands, which is a no-op success.
- A failure sets exit 1 but continues with the remaining operands.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST remove each file operand with unlink.
- **FR-002**: With `-f`, MUST silently ignore non-existent operands and make an empty operand list
  a success.
- **FR-003**: A directory operand MUST be an error (recursive `-r`/`-R` is out of scope in v1).
- **FR-004**: A failure (other than a missing file under -f) MUST diagnose and set exit 1, without
  stopping the remaining operands; `--` ends options.
- **FR-005**: MUST use no heap (Principle IV).
- **FR-006**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Exit status and the resulting tree match the system `rm` across the tested file
  (non-recursive) cases.
- **SC-002**: Binary meets a < 1 KB target on Linux (744 B achieved; macOS ~5.6 KB floor).

## Assumptions

- Recursive removal (`-r`/`-R`) is deferred: it needs directory reading (getdents/getdirentries),
  which will be built together with `ls`. `-i` (interactive) is not supported.
- Reuses the `unlink` wrapper added with `ln`; reuses `write`/`strlen`.
