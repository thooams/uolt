# Feature Specification: uolt-ln

**Feature Branch**: `016-uolt-ln` (built on `main`)  
**Created**: 2026-07-13  
**Status**: Implemented  
**Input**: User description: "ln"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a link (Priority: P1)

`uolt-ln source target` creates a hard link `target` to `source`; `-s` makes it a symbolic link.

**Acceptance Scenarios**:

1. **Given** two operands, **When** `ln src tgt`, **Then** `tgt` is a hard link to `src`.
2. **Given** `-s`, **When** `ln -s src tgt`, **Then** `tgt` is a symlink whose target is `src`.
3. **Given** one operand, **When** `ln src`, **Then** the link is `basename(src)` in the cwd.

---

### User Story 2 - Force over an existing target (Priority: P2)

`uolt-ln -f source target` removes an existing `target` first; without `-f` an existing target is
an error.

**Acceptance Scenarios**:

1. **Given** an existing target and no -f, **When** run, **Then** it errors.
2. **Given** `-f`, **When** run, **Then** the target is replaced.

---

### Edge Cases

- A hard link to a missing source is an error; a symlink to a missing target succeeds (dangling).
- `--` ends options; missing operand is an error; more than two operands is a usage error.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: MUST create a hard link (default) or symbolic link (`-s`) named target to source.
- **FR-002**: MUST accept `-f` to remove an existing target before linking.
- **FR-003**: With one operand, MUST use `basename(source)` in the current directory as target.
- **FR-004**: MUST support one or two operands; more is a usage error; `--` ends options.
- **FR-005**: On failure MUST write a diagnostic and exit 1.
- **FR-006**: MUST use no heap (Principle IV).
- **FR-007**: MUST record its README entry (name and binary size) per the constitution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Exit status and the resulting entries (name, type, symlink target) match the system
  `ln` across the tested cases.
- **SC-002**: Binary meets a < 1 KB target on Linux (904 B achieved; macOS ~6.2 KB floor).

## Assumptions

- Linking several sources into a directory (the `ln src... dir` form) is out of scope in v1: it
  needs a directory check (stat). Only one/two-operand forms are supported.
- Adds per-OS `link`, `symlink`, and `unlink` wrappers (unlink is reused by `rm`); reuses
  `write`/`strlen`.
